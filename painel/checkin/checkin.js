// Página de check-in.
//
// A página nunca decide quem entrou: ela só desenha. Quem grava é a Cloud
// Function, e a posição de cada pessoa é lida da ordem de `createdAt`, que é o
// relógio do Firestore. Por isso o botão "Vou" não escreve nada direto no
// banco — as regras negam escrita na fila até para quem administra.
//
// Consequência prática: adiantar o relógio do celular não adianta a vaga. No
// máximo o botão habilita cedo no seu aparelho, e a chamada volta recusada.
//
// Duas inscrições podem cair no mesmo milissegundo. Entre elas não existe quem
// chegou primeiro; o que existe, e é o que basta, é uma ordem única — garantida
// pelo desempate por id declarado na consulta.
//
// São duas filas independentes, linha e goleiro. O corte de cada uma é feito
// aqui na leitura, e é a mesma conta que `splitQueues` faz no servidor — os
// testes de `functions/test` é que fixam o comportamento esperado.

import { initializeApp } from 'https://www.gstatic.com/firebasejs/12.0.0/firebase-app.js';
import {
  initializeAppCheck,
  ReCaptchaV3Provider,
} from 'https://www.gstatic.com/firebasejs/12.0.0/firebase-app-check.js';
import {
  GoogleAuthProvider,
  browserLocalPersistence,
  connectAuthEmulator,
  getAuth,
  getRedirectResult,
  onAuthStateChanged,
  setPersistence,
  signInWithPopup,
  signInWithRedirect,
  signOut,
} from 'https://www.gstatic.com/firebasejs/12.0.0/firebase-auth.js';
import {
  collection,
  connectFirestoreEmulator,
  documentId,
  getFirestore,
  limit,
  onSnapshot,
  orderBy,
  query,
} from 'https://www.gstatic.com/firebasejs/12.0.0/firebase-firestore.js';
import {
  connectFunctionsEmulator,
  getFunctions,
  httpsCallable,
} from 'https://www.gstatic.com/firebasejs/12.0.0/firebase-functions.js';
import { firebaseConfig } from '../firebase-config.js';
import { RECAPTCHA_SITE_KEY } from './appcheck-config.js';

const REGION = 'southamerica-east1';
const $ = (id) => document.getElementById(id);

const app = initializeApp(firebaseConfig);

// Rodando contra o emulador? Aí nada disso fala com a nuvem, e o App Check sai
// de cena: o emulador não valida token de reCAPTCHA, e exigir um em
// desenvolvimento só impediria de testar.
const LOCAL = ['localhost', '127.0.0.1'].includes(location.hostname);

// App Check é o que separa "muita gente clicando" de "um script clicando".
// Sem ele, o endpoint aceitaria chamada de qualquer página ou terminal; com
// ele, o Firebase exige um token que só um navegador de verdade nesta origem
// consegue obter.
if (LOCAL) {
  console.info('modo local: emuladores em uso, App Check desligado');
} else if (RECAPTCHA_SITE_KEY && !RECAPTCHA_SITE_KEY.startsWith('COLOQUE')) {
  initializeAppCheck(app, {
    provider: new ReCaptchaV3Provider(RECAPTCHA_SITE_KEY),
    isTokenAutoRefreshEnabled: true,
  });
} else {
  console.error('App Check sem chave configurada — as chamadas vão ser recusadas.');
}

const auth = getAuth(app);
const db = getFirestore(app);
const functions = getFunctions(app, REGION);

if (LOCAL) {
  connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
  connectFirestoreEmulator(db, '127.0.0.1', 8080);
  connectFunctionsEmulator(functions, '127.0.0.1', 5001);
}
const callCheckin = httpsCallable(functions, 'checkin');
const callCancel = httpsCallable(functions, 'cancelCheckin');

const fmtDay = new Intl.DateTimeFormat('pt-BR', {
  weekday: 'long', day: '2-digit', month: 'long',
});
const fmtHour = new Intl.DateTimeFormat('pt-BR', { hour: '2-digit', minute: '2-digit' });
// Segundo e milissegundo só aparecem na fila em si, não no cabeçalho do
// evento — é ali que "quem chegou primeiro" precisa de precisão de verdade,
// porque sob concorrência real duas pessoas podem cair no mesmo segundo.
const fmtPrecise = new Intl.DateTimeFormat('pt-BR', {
  hour: '2-digit', minute: '2-digit', second: '2-digit', fractionalSecondDigits: 3,
});
const esc = (value) => String(value).replace(/[&<>"']/g, (char) => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
}[char]));

const ROLE_LABEL = { player: 'linha', keeper: 'gol' };

let currentUser = null;
let currentEvent = null;
let entries = [];
let chosenRole = 'player';
let unsubscribeEntries = null;
let busy = false;

const toDate = (value) => (value?.toDate ? value.toDate() : null);

/** Mesma regra do servidor: override manual vence, senão vale o horário. */
function windowState(event, now = Date.now()) {
  if (!event) return 'none';
  if (event.status === 'canceled') return 'canceled';
  if (event.status === 'closed') return 'closed';
  if (event.status === 'open') return 'open';
  if (!event.openAt || !event.closeAt) return 'none';
  if (now < event.openAt.getTime()) return 'scheduled';
  if (now >= event.closeAt.getTime()) return 'closed';
  return 'open';
}

function humanGap(ms) {
  const total = Math.max(0, Math.floor(ms / 1000));
  const days = Math.floor(total / 86400);
  const hours = Math.floor((total % 86400) / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const seconds = total % 60;
  const pad = (n) => String(n).padStart(2, '0');
  if (days > 0) return `${days}d ${pad(hours)}h ${pad(minutes)}m`;
  return `${pad(hours)}:${pad(minutes)}:${pad(seconds)}`;
}

// ── Filas ────────────────────────────────────────────────────────────────
// Confirmado e espera não são gravados em lugar nenhum: são a posição na
// ordem, dentro da própria função. Quando alguém cancela, todo mundo abaixo
// sobe sozinho, sem job de promoção e sem a janela em que duas pessoas
// achariam ter herdado a mesma vaga.

const fixedPlayers = () => currentEvent?.fixedPlayers ?? [];

/** Vagas de linha realmente disputadas: as 16 menos os fixos. */
function openPlayerSlots() {
  return Math.max(0, Number(currentEvent?.playerCapacity ?? 0) - fixedPlayers().length);
}

function slotsFor(role) {
  return role === 'keeper'
    ? Number(currentEvent?.keeperCapacity ?? 0)
    : openPlayerSlots();
}

function waitlistFor(role) {
  return role === 'keeper'
    ? Number(currentEvent?.keeperWaitlist ?? 0)
    : Number(currentEvent?.playerWaitlist ?? 0);
}

function queueFor(role) {
  return entries.filter((entry) => (entry.role ?? 'player') === role);
}

function splitQueue(role) {
  const queue = queueFor(role);
  const slots = slotsFor(role);
  const waits = waitlistFor(role);
  return {
    confirmed: queue.slice(0, slots),
    waiting: queue.slice(slots, slots + waits),
    overflow: queue.slice(slots + waits),
    slots,
  };
}

function myPlace() {
  if (!currentUser) return null;
  const mine = entries.find((entry) => entry.id === currentUser.uid);
  if (!mine) return null;
  const role = mine.role ?? 'player';
  const index = queueFor(role).findIndex((entry) => entry.id === currentUser.uid);
  const slots = slotsFor(role);
  const waits = waitlistFor(role);
  if (index < slots) return { role, kind: 'in', position: index + 1 };
  if (index < slots + waits) return { role, kind: 'wait', position: index - slots + 1 };
  return { role, kind: 'out', position: index - slots - waits + 1 };
}

function renderRows(rows, startAt) {
  if (!rows.length) return '<li class="empty">Ninguém ainda.</li>';
  return rows.map((row, offset) => {
    const at = toDate(row.createdAt);
    const mine = currentUser && row.id === currentUser.uid ? ' class="me"' : '';
    return `<li${mine}><span class="pos">${String(offset + startAt).padStart(2, '0')}</span>`
      + `<span class="who">${esc(row.name ?? 'Sem nome')}</span>`
      + `<span class="at">${at ? fmtPrecise.format(at) : '—'}</span></li>`;
  }).join('');
}

function renderGroup(title, count, sections) {
  const body = sections
    .filter((section) => section.rows.length || section.always)
    .map((section) => `<p class="sub ${section.tone ?? ''}">${section.label}</p>`
      + `<ol class="queue">${renderRows(section.rows, 1)}</ol>`)
    .join('');
  return `<div class="group"><h3 class="group-head">${title}<small>${count}</small></h3>${body}</div>`;
}

function renderLists() {
  const host = $('lists');
  host.hidden = !currentEvent;
  if (!currentEvent) return;

  const fixed = fixedPlayers();
  const line = splitQueue('player');
  const gol = splitQueue('keeper');
  const playerCapacity = Number(currentEvent.playerCapacity ?? 0);
  const keeperCapacity = Number(currentEvent.keeperCapacity ?? 0);

  // Os fixos aparecem primeiro porque é literalmente o que acontece: eles já
  // ocupam vaga, e a fila disputa o que sobra.
  const fixedBlock = fixed.length
    ? `<div class="group"><h3 class="group-head">Fixos<small>${fixed.length} de ${playerCapacity} vagas de linha</small></h3>`
      + `<ol class="queue">${fixed.map((name, index) => `<li class="fixed">`
        + `<span class="pos">${String(index + 1).padStart(2, '0')}</span>`
        + `<span class="who">${esc(name)}</span>`
        + '<span class="at">fixo</span></li>').join('')}</ol></div>`
    : '';

  host.innerHTML = fixedBlock
    + renderGroup('Linha', `${line.confirmed.length} de ${line.slots} vagas na disputa`, [
      { label: 'Confirmados', rows: line.confirmed, always: true },
      { label: `Espera (${line.waiting.length}/${waitlistFor('player')})`, rows: line.waiting, tone: 'warn', always: true },
      { label: 'Fora da lista', rows: line.overflow, tone: 'bad' },
    ])
    + renderGroup('Gol', `${gol.confirmed.length} de ${keeperCapacity} vagas`, [
      { label: 'Confirmados', rows: gol.confirmed, always: true },
      { label: `Espera (${gol.waiting.length}/${waitlistFor('keeper')})`, rows: gol.waiting, tone: 'warn', always: true },
      { label: 'Fora da lista', rows: gol.overflow, tone: 'bad' },
    ]);
}

function renderMine() {
  const box = $('mine');
  const place = myPlace();
  box.classList.remove('in', 'wait', 'out');
  $('cancel').classList.toggle('hidden', !place);

  if (!place) {
    box.classList.add('hidden');
    return;
  }
  box.classList.remove('hidden');
  box.classList.add(place.kind);
  const onde = ROLE_LABEL[place.role];
  const texts = {
    in: ['Você está dentro', `${place.position}º confirmado na ${onde}. Chegue no horário.`],
    wait: ['Lista de espera', `${place.position}º da espera da ${onde}. Se alguém desistir, você sobe automaticamente.`],
    out: ['Fora da lista', `${place.position}º depois da espera da ${onde}. Só entra se muita gente cair.`],
  };
  const [title, detail] = texts[place.kind];
  box.innerHTML = `<strong>${title}</strong><span>${esc(detail)}</span>`;
}

function renderEvent() {
  if (!currentEvent) {
    $('event-date').textContent = 'Nenhum racha marcado';
    $('event-pill').className = 'pill shut';
    $('event-pill').textContent = 'Sem data';
    $('event-countdown').textContent = '';
    $('event-detail').textContent = 'Assim que a próxima data for agendada, ela aparece aqui.';
    return;
  }

  const matchAt = currentEvent.matchAt;
  $('event-date').textContent = matchAt
    ? `${fmtDay.format(matchAt)}, ${fmtHour.format(matchAt)}`
    : 'Data a confirmar';

  const state = windowState(currentEvent);
  const pill = $('event-pill');
  const countdown = $('event-countdown');
  const detail = $('event-detail');
  const vagas = `${openPlayerSlots()} vagas de linha na disputa `
    + `(${currentEvent.playerCapacity} menos ${fixedPlayers().length} fixos) `
    + `e ${currentEvent.keeperCapacity} no gol`;

  if (state === 'scheduled') {
    pill.className = 'pill soon';
    pill.textContent = 'Abre em';
    countdown.textContent = humanGap(currentEvent.openAt.getTime() - Date.now());
    detail.textContent = `Libera ${fmtDay.format(currentEvent.openAt)} às `
      + `${fmtHour.format(currentEvent.openAt)}. ${vagas}, por ordem de chegada.`;
  } else if (state === 'open') {
    pill.className = 'pill open';
    pill.textContent = 'Aberto';
    countdown.textContent = currentEvent.closeAt
      ? `fecha em ${humanGap(currentEvent.closeAt.getTime() - Date.now())}`
      : '';
    detail.textContent = `${vagas}. Quem aperta primeiro fica na frente.`;
  } else if (state === 'canceled') {
    pill.className = 'pill shut';
    pill.textContent = 'Cancelado';
    countdown.textContent = '';
    detail.textContent = 'Este racha foi cancelado.';
  } else {
    pill.className = 'pill shut';
    pill.textContent = 'Fechado';
    countdown.textContent = '';
    detail.textContent = 'O check-in desta semana já fechou.';
  }
}

function renderRoles() {
  for (const role of ['player', 'keeper']) {
    const button = $(`role-${role}`);
    button.setAttribute('aria-checked', String(chosenRole === role));
  }
  const place = myPlace();
  const fila = queueFor(chosenRole).length;
  const slots = slotsFor(chosenRole);
  const restam = Math.max(0, slots - fila);

  if (place && place.role !== chosenRole) {
    // Aviso antes do clique, não depois: trocar de função recomeça a fila.
    $('role-hint').textContent = `Você já está na fila da ${ROLE_LABEL[place.role]}. `
      + `Trocar para ${ROLE_LABEL[chosenRole]} te manda para o fim da fila nova.`;
    return;
  }
  $('role-hint').textContent = restam > 0
    ? `${restam} ${restam === 1 ? 'vaga livre' : 'vagas livres'} na ${ROLE_LABEL[chosenRole]} agora.`
    : `Sem vaga na ${ROLE_LABEL[chosenRole]} agora — você entra na espera.`;
}

function renderAction() {
  const signedIn = Boolean(currentUser);
  $('signin-card').hidden = signedIn;
  $('action-card').hidden = !signedIn;
  if (!signedIn) return;

  $('account-line').textContent = currentUser.email || 'Conta Google';
  const state = windowState(currentEvent);
  const place = myPlace();
  const nameOk = $('name').value.trim().length >= 2;
  $('go').disabled = busy || state !== 'open' || !nameOk;
  $('go').textContent = !place
    ? 'Vou'
    : place.role === chosenRole ? 'Atualizar meu nome' : `Trocar para ${ROLE_LABEL[chosenRole]}`;
  renderRoles();
}

function renderAll() {
  renderEvent();
  renderLists();
  renderMine();
  renderAction();
}

function showMessage(text, kind = '') {
  const box = $('action-message');
  box.className = `msg ${kind}`.trim();
  box.textContent = text;
  box.classList.toggle('hidden', !text);
}

// ── Dados ao vivo ────────────────────────────────────────────────────────
// Ouve os dois últimos eventos e escolhe o próximo que ainda não começou. Ler
// os documentos em vez de recalcular a data no navegador evita a página e o
// servidor discordarem sobre qual é o racha da vez.
function watchEvent() {
  const eventsQuery = query(collection(db, 'checkin_events'), orderBy('matchAt', 'desc'), limit(2));
  onSnapshot(eventsQuery, (snapshot) => {
    const docs = snapshot.docs.map((entry) => ({
      id: entry.id,
      ...entry.data(),
      openAt: toDate(entry.data().openAt),
      closeAt: toDate(entry.data().closeAt),
      matchAt: toDate(entry.data().matchAt),
    }));
    const now = Date.now();
    const upcoming = docs
      .filter((entry) => entry.matchAt && entry.matchAt.getTime() > now)
      .sort((a, b) => a.matchAt - b.matchAt)[0];
    const chosen = upcoming ?? docs[0] ?? null;

    if (chosen?.id !== currentEvent?.id) {
      entries = [];
      watchEntries(chosen?.id ?? null);
    }
    currentEvent = chosen;
    renderAll();
  }, (error) => {
    $('fatal').classList.remove('hidden');
    $('fatal').textContent = `Não consegui carregar o racha da semana: ${error.message}`;
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
    entries = snapshot.docs.map((entry) => ({ id: entry.id, ...entry.data() }));
    // Quem já está inscrito vê a própria função selecionada ao abrir a página.
    const mine = currentUser && entries.find((entry) => entry.id === currentUser.uid);
    if (mine) chosenRole = mine.role ?? 'player';
    renderAll();
  }, (error) => {
    showMessage(`Não consegui atualizar a lista: ${error.message}`, 'err');
  });
}

// ── Ações ────────────────────────────────────────────────────────────────
function friendlyError(error) {
  const code = error.code?.replace('functions/', '');
  if (code === 'unauthenticated') return 'Sua sessão caiu. Entre de novo.';
  if (['permission-denied', 'failed-precondition', 'resource-exhausted', 'invalid-argument'].includes(code)) {
    return error.message;
  }
  return `Não deu certo: ${error.message}`;
}

async function withBusy(action) {
  if (busy) return;
  busy = true;
  renderAction();
  try {
    await action();
  } catch (error) {
    showMessage(friendlyError(error), 'err');
  } finally {
    busy = false;
    renderAction();
  }
}

$('go').addEventListener('click', () => withBusy(async () => {
  showMessage('Registrando…');
  const result = await callCheckin({ name: $('name').value.trim(), role: chosenRole });
  const messages = {
    inscrito: 'Presença registrada.',
    'ja-inscrito': 'Você já estava na fila — posição mantida.',
    'trocou-de-funcao': `Trocou para ${ROLE_LABEL[chosenRole]}. Você entrou no fim da fila nova.`,
    fixo: 'Você é fixo: sua vaga já está garantida, não precisa confirmar.',
  };
  showMessage(messages[result.data.result] ?? 'Pronto.', 'ok');
}));

$('cancel').addEventListener('click', () => withBusy(async () => {
  showMessage('Liberando sua vaga…');
  await callCancel({});
  showMessage('Vaga liberada. Quem estava na espera subiu.', 'ok');
}));

for (const role of ['player', 'keeper']) {
  $(`role-${role}`).addEventListener('click', () => {
    chosenRole = role;
    showMessage('');
    renderAction();
  });
}

$('name').addEventListener('input', renderAction);

$('sign-in').addEventListener('click', async () => {
  const provider = new GoogleAuthProvider();
  provider.setCustomParameters({ prompt: 'select_account' });
  try {
    await setPersistence(auth, browserLocalPersistence);
    await signInWithPopup(auth, provider);
  } catch (error) {
    // Navegador de celular costuma bloquear popup; o redirect sempre passa.
    if (['auth/popup-blocked', 'auth/popup-closed-by-user', 'auth/cancelled-popup-request',
      'auth/operation-not-supported-in-this-environment'].includes(error.code)) {
      await signInWithRedirect(auth, provider);
      return;
    }
    $('signin-error').classList.remove('hidden');
    $('signin-error').textContent = `Não consegui entrar: ${error.message}`;
  }
});

$('sign-out').addEventListener('click', () => signOut(auth));

getRedirectResult(auth).catch((error) => {
  $('signin-error').classList.remove('hidden');
  $('signin-error').textContent = `Não consegui entrar: ${error.message}`;
});

onAuthStateChanged(auth, (user) => {
  currentUser = user;
  if (user && !$('name').value.trim()) {
    $('name').value = (user.displayName ?? '').slice(0, 40);
  }
  const mine = user && entries.find((entry) => entry.id === user.uid);
  if (mine) chosenRole = mine.role ?? 'player';
  showMessage('');
  renderAll();
});

// Contagem regressiva e virada de janela sem precisar recarregar.
setInterval(() => {
  if (currentEvent) {
    renderEvent();
    renderAction();
  }
}, 1000);

watchEvent();
renderAll();
