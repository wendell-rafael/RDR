// Aba de check-in do painel.
//
// Aqui o painel manda no calendário e nas vagas, mas não na fila. A ordem de
// chegada é escrita só pela Cloud Function, e as regras negam escrita em
// `entries` para todo mundo — inclusive para quem administra. Remover alguém
// passa por `adminRemoveEntry`, que confere a allowlist e deixa registro no
// log de auditoria. É de propósito: uma fila que o organizador pode reordenar
// à mão no banco não é uma fila, é uma lista de convidados.

import {
  Timestamp,
  collection,
  doc,
  documentId,
  getDoc,
  limit,
  onSnapshot,
  orderBy,
  query,
  setDoc,
  updateDoc,
} from 'https://www.gstatic.com/firebasejs/12.0.0/firebase-firestore.js';
import {
  connectFunctionsEmulator,
  getFunctions,
  httpsCallable,
} from 'https://www.gstatic.com/firebasejs/12.0.0/firebase-functions.js';

const REGION = 'southamerica-east1';
const $ = (id) => document.getElementById(id);
const esc = (value) => String(value).replace(/[&<>"']/g, (char) => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
}[char]));

const WEEKDAYS = ['Domingo', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado'];
const STATUS_LABELS = {
  auto: 'Automático (segue o horário)',
  open: 'Forçar aberto',
  closed: 'Forçar fechado',
  canceled: 'Cancelado',
};
const ROLE_LABEL = { player: 'Linha', keeper: 'Gol' };

const DEFAULTS = {
  matchWeekday: 2,
  matchHour: 19,
  matchMinute: 0,
  openWeekday: 4,
  openHour: 12,
  openMinute: 0,
  closeMinutesBeforeMatch: 120,
  playerCapacity: 16,
  keeperCapacity: 2,
  playerWaitlist: 10,
  keeperWaitlist: 2,
  fixedPlayers: ['Rafael', 'Augusto', 'Wendell', 'Caio'],
  fixedUids: [],
  maxEntries: 120,
};

const fmtDateTime = new Intl.DateTimeFormat('pt-BR', {
  day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit',
});
// Na lista de inscrições o segundo e o milissegundo importam: é o que prova
// pra quem administra que a ordem não veio de sorte — veio do relógio do
// servidor no instante exato do commit.
const fmtPrecise = new Intl.DateTimeFormat('pt-BR', {
  hour: '2-digit', minute: '2-digit', second: '2-digit', fractionalSecondDigits: 3,
});

let db = null;
let user = null;
let removeEntry = null;
let selectedEventId = null;
let events = [];
let unsubscribeEntries = null;

const toDate = (value) => (value?.toDate ? value.toDate() : null);
const asList = (value) => (Array.isArray(value) ? value : []);

/** Uma linha por nome: é o formato que mais resiste a copiar e colar. */
const linesToList = (text) => String(text ?? '')
  .split('\n')
  .map((line) => line.replace(/\s+/g, ' ').trim())
  .filter((line) => line.length >= 2);

/** `Date` para o formato que `<input type="datetime-local">` aceita. */
function toLocalInput(date) {
  if (!date) return '';
  const pad = (n) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
    + `T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

/** Vagas de linha realmente disputadas: a capacidade menos os fixos. */
function openPlayerSlots(event) {
  return Math.max(0, Number(event?.playerCapacity ?? 0) - asList(event?.fixedPlayers).length);
}

function status(message, kind = '') {
  const box = $('checkin-status');
  box.textContent = message;
  box.className = kind === 'err' ? 'message' : 'help';
}

// ── Configuração semanal ────────────────────────────────────────────────
function renderConfigForm(config) {
  const weekdayOptions = (selected) => WEEKDAYS
    .map((label, index) => `<option value="${index}"${index === selected ? ' selected' : ''}>${label}</option>`)
    .join('');
  const pad = (n) => String(n).padStart(2, '0');

  $('checkin-config').innerHTML = `
    <label>Dia do jogo<select id="cfg-matchWeekday">${weekdayOptions(config.matchWeekday)}</select></label>
    <label>Hora do jogo<input type="time" id="cfg-matchTime" value="${pad(config.matchHour)}:${pad(config.matchMinute)}"></label>
    <label>Dia que abre<select id="cfg-openWeekday">${weekdayOptions(config.openWeekday)}</select></label>
    <label>Hora que abre<input type="time" id="cfg-openTime" value="${pad(config.openHour)}:${pad(config.openMinute)}"></label>
    <label>Fecha quantos minutos antes<input type="number" id="cfg-closeMinutes" min="0" max="10080" value="${config.closeMinutesBeforeMatch}"></label>
    <label>Vagas de linha<input type="number" id="cfg-playerCapacity" min="0" max="200" value="${config.playerCapacity}"></label>
    <label>Vagas de gol<input type="number" id="cfg-keeperCapacity" min="0" max="20" value="${config.keeperCapacity}"></label>
    <label>Espera da linha<input type="number" id="cfg-playerWaitlist" min="0" max="200" value="${config.playerWaitlist}"></label>
    <label>Espera do gol<input type="number" id="cfg-keeperWaitlist" min="0" max="20" value="${config.keeperWaitlist}"></label>
    <label>Teto de inscrições<input type="number" id="cfg-maxEntries" min="1" max="500" value="${config.maxEntries}"></label>
    <label class="wide">Fixos — um nome por linha. Cada um come uma vaga de linha, então a fila disputa o que sobra.
      <textarea id="cfg-fixedPlayers" rows="5">${esc(asList(config.fixedPlayers).join('\n'))}</textarea>
    </label>
    <label class="wide">Contas dos fixos — um uid por linha, opcional. Com o uid preenchido, a pessoa recebe "sua vaga já está garantida" em vez de entrar na fila. Sem ele, o nome sozinho não prova nada e ela disputa como qualquer um.
      <textarea id="cfg-fixedUids" rows="3">${esc(asList(config.fixedUids).join('\n'))}</textarea>
    </label>
    <button type="button" class="primary" id="cfg-save">Salvar configuração</button>
  `;

  $('cfg-save').addEventListener('click', async () => {
    const [matchHour, matchMinute] = $('cfg-matchTime').value.split(':').map(Number);
    const [openHour, openMinute] = $('cfg-openTime').value.split(':').map(Number);
    const payload = {
      matchWeekday: Number($('cfg-matchWeekday').value),
      matchHour,
      matchMinute,
      openWeekday: Number($('cfg-openWeekday').value),
      openHour,
      openMinute,
      closeMinutesBeforeMatch: Number($('cfg-closeMinutes').value),
      playerCapacity: Number($('cfg-playerCapacity').value),
      keeperCapacity: Number($('cfg-keeperCapacity').value),
      playerWaitlist: Number($('cfg-playerWaitlist').value),
      keeperWaitlist: Number($('cfg-keeperWaitlist').value),
      fixedPlayers: linesToList($('cfg-fixedPlayers').value),
      fixedUids: linesToList($('cfg-fixedUids').value),
      maxEntries: Number($('cfg-maxEntries').value),
      updatedAt: Timestamp.now(),
      updatedBy: user.uid,
    };
    try {
      await setDoc(doc(db, 'checkin_config', 'settings'), payload);
      // Só vale do próximo racha em diante: o evento desta semana já existe
      // com os números que tinha quando foi criado.
      status('Configuração salva. Vale a partir do próximo racha ainda não criado.');
    } catch (error) {
      status(`Não consegui salvar: ${error.message}`, 'err');
    }
  });
}

async function loadConfig() {
  try {
    const snap = await getDoc(doc(db, 'checkin_config', 'settings'));
    renderConfigForm({ ...DEFAULTS, ...(snap.exists() ? snap.data() : {}) });
  } catch (error) {
    status(`Não consegui ler a configuração: ${error.message}`, 'err');
  }
}

// ── Eventos ─────────────────────────────────────────────────────────────
function renderEventEditor() {
  const event = events.find((item) => item.id === selectedEventId);
  const host = $('checkin-event-editor');
  if (!event) {
    host.innerHTML = '<p class="empty">Nenhum racha criado ainda. O agendador cria o próximo automaticamente à meia-noite.</p>';
    return;
  }

  const statusOptions = Object.entries(STATUS_LABELS)
    .map(([value, label]) => `<option value="${value}"${event.status === value ? ' selected' : ''}>${label}</option>`)
    .join('');

  host.innerHTML = `
    <label>Abre em<input type="datetime-local" id="ev-openAt" value="${toLocalInput(toDate(event.openAt))}"></label>
    <label>Fecha em<input type="datetime-local" id="ev-closeAt" value="${toLocalInput(toDate(event.closeAt))}"></label>
    <label>Vagas de linha<input type="number" id="ev-playerCapacity" min="0" max="200" value="${event.playerCapacity ?? 0}"></label>
    <label>Vagas de gol<input type="number" id="ev-keeperCapacity" min="0" max="20" value="${event.keeperCapacity ?? 0}"></label>
    <label>Espera da linha<input type="number" id="ev-playerWaitlist" min="0" max="200" value="${event.playerWaitlist ?? 0}"></label>
    <label>Espera do gol<input type="number" id="ev-keeperWaitlist" min="0" max="20" value="${event.keeperWaitlist ?? 0}"></label>
    <label>Situação<select id="ev-status">${statusOptions}</select></label>
    <label class="wide">Fixos deste racha — um nome por linha. Tirar alguém daqui devolve a vaga para a fila, e quem estava esperando sobe na hora.
      <textarea id="ev-fixedPlayers" rows="4">${esc(asList(event.fixedPlayers).join('\n'))}</textarea>
    </label>
    <p class="help wide" id="ev-summary"></p>
    <button type="button" class="primary" id="ev-save">Aplicar neste racha</button>
  `;

  const summary = () => {
    const fixos = linesToList($('ev-fixedPlayers').value).length;
    const livres = Math.max(0, Number($('ev-playerCapacity').value) - fixos);
    $('ev-summary').textContent = `${livres} vagas de linha na disputa `
      + `(${$('ev-playerCapacity').value} menos ${fixos} fixos) e ${$('ev-keeperCapacity').value} no gol.`;
  };
  summary();
  for (const id of ['ev-playerCapacity', 'ev-keeperCapacity', 'ev-fixedPlayers']) {
    $(id).addEventListener('input', summary);
  }

  $('ev-save').addEventListener('click', async () => {
    const openAt = new Date($('ev-openAt').value);
    const closeAt = new Date($('ev-closeAt').value);
    if (Number.isNaN(openAt.getTime()) || Number.isNaN(closeAt.getTime()) || openAt >= closeAt) {
      status('Abertura precisa ser antes do fechamento.', 'err');
      return;
    }
    try {
      await updateDoc(doc(db, 'checkin_events', event.id), {
        openAt: Timestamp.fromDate(openAt),
        closeAt: Timestamp.fromDate(closeAt),
        playerCapacity: Number($('ev-playerCapacity').value),
        keeperCapacity: Number($('ev-keeperCapacity').value),
        playerWaitlist: Number($('ev-playerWaitlist').value),
        keeperWaitlist: Number($('ev-keeperWaitlist').value),
        fixedPlayers: linesToList($('ev-fixedPlayers').value),
        status: $('ev-status').value,
        updatedAt: Timestamp.now(),
        updatedBy: user.uid,
      });
      // Mudar vagas ou fixos não reordena ninguém: a fila continua a mesma, só
      // muda onde passa a linha de corte entre confirmado e espera.
      status('Racha atualizado.');
    } catch (error) {
      status(`Não consegui atualizar: ${error.message}`, 'err');
    }
  });
}

function renderEventPicker() {
  const select = $('checkin-event-select');
  select.innerHTML = events.map((event) => {
    const matchAt = toDate(event.matchAt);
    const label = matchAt ? fmtDateTime.format(matchAt) : event.id;
    return `<option value="${esc(event.id)}"${event.id === selectedEventId ? ' selected' : ''}>${esc(label)}</option>`;
  }).join('');
}

function renderEntries(eventId, rows) {
  const event = events.find((item) => item.id === eventId);
  const slots = { player: openPlayerSlots(event), keeper: Number(event?.keeperCapacity ?? 0) };
  const waits = {
    player: Number(event?.playerWaitlist ?? 0),
    keeper: Number(event?.keeperWaitlist ?? 0),
  };
  const fixos = asList(event?.fixedPlayers);

  $('checkin-entries-count').textContent = `${rows.length} inscrições`;
  if (!rows.length && !fixos.length) {
    $('checkin-entries').innerHTML = '<p class="empty">Ninguém se inscreveu ainda.</p>';
    return;
  }

  const fixedBlock = fixos.length
    ? `<p class="sub-note">Fixos (não passam pela fila)</p>`
      + fixos.map((name, index) => `<div class="entry-row">
          <span class="entry-pos">${String(index + 1).padStart(2, '0')}</span>
          <span class="entry-name">${esc(name)}</span>
          <span class="chip fixed">Fixo</span>
          <span class="entry-at">—</span>
          <span></span>
        </div>`).join('')
    : '';

  const blocks = ['player', 'keeper'].map((role) => {
    const queue = rows.filter((row) => (row.role ?? 'player') === role);
    if (!queue.length) return '';
    return `<p class="sub-note">${ROLE_LABEL[role]} — ${slots[role]} vagas</p>`
      + queue.map((row, index) => {
        const at = toDate(row.createdAt);
        const chip = index < slots[role]
          ? '<span class="chip in">Confirmado</span>'
          : index < slots[role] + waits[role]
            ? '<span class="chip wait">Espera</span>'
            : '<span class="chip out">Fora</span>';
        return `<div class="entry-row">
          <span class="entry-pos">${String(index + 1).padStart(2, '0')}</span>
          <span class="entry-name">${esc(row.name ?? 'Sem nome')}</span>
          ${chip}
          <span class="entry-at">${at ? fmtPrecise.format(at) : '—'}</span>
          <button type="button" class="secondary entry-remove" data-uid="${esc(row.id)}" data-name="${esc(row.name ?? '')}">Remover</button>
        </div>`;
      }).join('');
  }).join('');

  $('checkin-entries').innerHTML = fixedBlock + blocks;

  $('checkin-entries').querySelectorAll('.entry-remove').forEach((button) => {
    button.addEventListener('click', async () => {
      const name = button.dataset.name || 'esta pessoa';
      if (!window.confirm(`Remover ${name} da lista? Quem está esperando sobe uma posição.`)) return;
      button.disabled = true;
      try {
        await removeEntry({ eventId, uid: button.dataset.uid });
        status(`${name} removido da lista.`);
      } catch (error) {
        button.disabled = false;
        status(`Não consegui remover: ${error.message}`, 'err');
      }
    });
  });
}

function watchEntries(eventId) {
  if (unsubscribeEntries) unsubscribeEntries();
  unsubscribeEntries = null;
  if (!eventId) return;

  // O desempate por id é explícito de propósito. Duas inscrições podem cair no
  // mesmo milissegundo — foi medido, acontece — e aí "quem chegou primeiro" não
  // existe entre elas. O que precisa existir é uma ordem única: sem o segundo
  // critério, dois leitores poderiam desempatar diferente e mostrar listas que
  // não batem.
  const entriesQuery = query(
    collection(db, 'checkin_events', eventId, 'entries'),
    orderBy('createdAt', 'asc'),
    orderBy(documentId(), 'asc'),
  );
  unsubscribeEntries = onSnapshot(entriesQuery, (snapshot) => {
    renderEntries(eventId, snapshot.docs.map((entry) => ({ id: entry.id, ...entry.data() })));
  }, (error) => {
    status(`Não consegui ler a lista: ${error.message}`, 'err');
  });
}

function watchEvents() {
  const eventsQuery = query(collection(db, 'checkin_events'), orderBy('matchAt', 'desc'), limit(12));
  onSnapshot(eventsQuery, (snapshot) => {
    events = snapshot.docs.map((entry) => ({ id: entry.id, ...entry.data() }));
    if (!events.some((event) => event.id === selectedEventId)) {
      const now = Date.now();
      const upcoming = events
        .filter((event) => toDate(event.matchAt)?.getTime() > now)
        .sort((a, b) => toDate(a.matchAt) - toDate(b.matchAt))[0];
      selectedEventId = (upcoming ?? events[0])?.id ?? null;
      watchEntries(selectedEventId);
    }
    renderEventPicker();
    renderEventEditor();
  }, (error) => {
    status(`Não consegui listar os rachas: ${error.message}`, 'err');
  });
}

export function initCheckinAdmin(app, firestore, signedInUser) {
  db = firestore;
  user = signedInUser;
  const functions = getFunctions(app, REGION);
  if (['localhost', '127.0.0.1'].includes(location.hostname)) {
    connectFunctionsEmulator(functions, '127.0.0.1', 5001);
  }
  removeEntry = httpsCallable(functions, 'adminRemoveEntry');

  $('checkin-event-select').addEventListener('change', (event) => {
    selectedEventId = event.target.value;
    watchEntries(selectedEventId);
    renderEventEditor();
  });

  loadConfig();
  watchEvents();
}
