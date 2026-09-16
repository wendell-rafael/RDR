import { initializeApp } from 'https://www.gstatic.com/firebasejs/12.0.0/firebase-app.js';
import {
  getAuth,
  GoogleAuthProvider,
  onAuthStateChanged,
  signInWithPopup,
  signOut,
} from 'https://www.gstatic.com/firebasejs/12.0.0/firebase-auth.js';
import {
  doc,
  getDoc,
  getFirestore,
  runTransaction,
  serverTimestamp,
} from 'https://www.gstatic.com/firebasejs/12.0.0/firebase-firestore.js';
import { firebaseConfig } from '../firebase-config.js';

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getFirestore(app);
const mainRef = doc(db, 'racha', 'main');

const $ = (id) => document.getElementById(id);
const esc = (value) => String(value).replace(/[&<>"']/g, (char) => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
}[char]));
const formatDate = (value) => new Date(value).toLocaleDateString('pt-BR');
const phaseNames = ['Fase de grupos', 'Mata-mata', 'Final', 'Semifinal'];

let currentUser = null;
let loadedRevision = 0;
let draft = { players: [], tournaments: [] };
let dirty = false;
let selectedTournamentId = '';
const changedMatchIds = new Set();

class RevisionConflictError extends Error {}

function setDirty(value = true) {
  dirty = value;
  $('save-all').disabled = !value;
  $('save-status').textContent = value ? 'Alterações não salvas' : 'Tudo salvo';
}

function showAuthMessage(message) {
  $('auth-message').textContent = message;
}

function showAuthorized(user) {
  currentUser = user;
  $('account-email').textContent = user.email || 'Conta Google';
  $('auth-view').classList.add('hidden');
  $('admin-view').classList.remove('hidden');
}

function showSignedOut(message = '') {
  currentUser = null;
  $('admin-view').classList.add('hidden');
  $('auth-view').classList.remove('hidden');
  showAuthMessage(message);
}

async function loadData() {
  $('save-status').textContent = 'Carregando dados…';
  const snapshot = await getDoc(mainRef);
  if (!snapshot.exists()) throw new Error('Nenhum dado do racha foi encontrado.');
  const data = snapshot.data();
  loadedRevision = Number(data.revision ?? 0);
  draft = {
    players: structuredClone(data.players ?? []),
    tournaments: structuredClone(data.tournaments ?? []),
  };
  selectedTournamentId = draft.tournaments
    .slice()
    .sort((a, b) => Number(b.createdAt ?? 0) - Number(a.createdAt ?? 0))[0]?.id ?? '';
  changedMatchIds.clear();
  $('revision-label').textContent = `versão ${loadedRevision}`;
  $('conflict').classList.add('hidden');
  renderPlayers();
  renderTournamentSelect();
  renderTournamentMeta();
  renderMatches();
  setDirty(false);
}

function renderPlayers() {
  const players = draft.players.slice().sort((a, b) =>
    String(a.name ?? '').localeCompare(String(b.name ?? ''), 'pt-BR'));
  $('players-editor').innerHTML = players.length ? players.map((player) => `
    <div class="player-row" data-player-id="${esc(player.id)}">
      <label>Nome<input data-player-field="name" value="${esc(player.name ?? '')}" maxlength="60" autocomplete="off"></label>
      <label>Nível<input data-player-field="stars" type="number" value="${Number(player.stars ?? 0)}" min="0" max="5" step="0.5"></label>
      <label>Gols<input data-player-field="goals" type="number" value="${Number(player.goals ?? 0)}" min="0" step="1"></label>
      <label>Títulos<input data-player-field="titles" type="number" value="${Number(player.titles ?? 0)}" min="0" step="1"></label>
    </div>`).join('') : '<div class="empty">Nenhum jogador cadastrado.</div>';
}

function confirmDialog(dialog) {
  dialog.returnValue = 'cancel';
  return new Promise((resolve) => {
    dialog.addEventListener('close', () => resolve(dialog.returnValue === 'confirm'), { once: true });
    dialog.showModal();
  });
}

function toDateInputValue(ms) {
  const d = new Date(ms);
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

function renderTournamentMeta() {
  const tournament = draft.tournaments.find((item) => item.id === selectedTournamentId);
  if (!tournament) {
    $('tournament-meta').innerHTML = '';
    return;
  }
  const teams = tournament.teams ?? [];
  $('tournament-meta').innerHTML = `
    <label>Data<input type="date" data-meta-field="createdAt" value="${toDateInputValue(tournament.createdAt)}"></label>
    <label>Situação<select data-meta-field="status">
      <option value="0"${tournament.status === 0 ? ' selected' : ''}>Em andamento</option>
      <option value="1"${tournament.status === 1 ? ' selected' : ''}>Encerrado</option>
    </select></label>
    <label>Campeão<select data-meta-field="championTeamId">
      <option value=""${tournament.championTeamId ? '' : ' selected'}>Nenhum</option>
      ${teams.map((team) => `<option value="${esc(team.id)}"${team.id === tournament.championTeamId ? ' selected' : ''}>${esc(team.name)}</option>`).join('')}
    </select></label>
    <button type="button" class="secondary delete-tournament" id="delete-tournament">Excluir torneio</button>
  `;
}

function tournamentLabel(tournament) {
  const champion = (tournament.teams ?? []).find((team) =>
    team.id === tournament.championTeamId)?.name;
  return `${formatDate(tournament.createdAt)}${champion ? ` · ${champion}` : ''}`;
}

function renderTournamentSelect() {
  const tournaments = draft.tournaments.slice().sort((a, b) =>
    Number(b.createdAt ?? 0) - Number(a.createdAt ?? 0));
  $('tournament-select').innerHTML = tournaments.length
    ? tournaments.map((tournament) => `<option value="${esc(tournament.id)}"${tournament.id === selectedTournamentId ? ' selected' : ''}>${esc(tournamentLabel(tournament))}</option>`).join('')
    : '<option value="">Nenhum torneio</option>';
}

function scorerCount(match, playerId, teamId) {
  return (match.scorers ?? []).filter((goal) =>
    goal.playerId === playerId && goal.teamId === teamId).length;
}

function scorerEditor(team, match) {
  if (!team) return '<div class="scorer-team"><h3>Time ainda não definido</h3></div>';
  const rosterIds = new Set(team.playerIds ?? []);
  // Jogadores avulsos: marcaram gol pelo time mas não fazem parte do elenco
  // cadastrado (ex.: alguém que completou o time naquele dia). Mostramos
  // também, em vez de esconder — apagar silenciosamente perderia o gol real.
  const guestIds = [...new Set((match.scorers ?? [])
    .filter((goal) => goal.teamId === team.id && !rosterIds.has(goal.playerId))
    .map((goal) => goal.playerId))];
  const row = (player, guest) => `<label class="scorer-row"><span>${esc(player.name)}${guest ? ' <small>(avulso)</small>' : ''}</span><input type="number" min="0" step="1" value="${scorerCount(match, player.id, team.id)}" data-scorer-player="${esc(player.id)}" data-scorer-team="${esc(team.id)}" aria-label="Gols de ${esc(player.name)}"></label>`;
  const players = [
    ...(team.playerIds ?? []).map((id) => draft.players.find((player) => player.id === id)).filter(Boolean).map((player) => row(player, false)),
    ...guestIds.map((id) => draft.players.find((player) => player.id === id)).filter(Boolean).map((player) => row(player, true)),
  ];
  return `<div class="scorer-team"><h3>${esc(team.name)}</h3>${players.length
    ? players.join('')
    : '<p class="empty">Sem jogadores neste time.</p>'}</div>`;
}

function renderMatches() {
  const tournament = draft.tournaments.find((item) => item.id === selectedTournamentId);
  if (!tournament) {
    $('matches-editor').innerHTML = '<div class="empty">Nenhum torneio disponível.</div>';
    return;
  }
  const team = (id) => (tournament.teams ?? []).find((item) => item.id === id);
  const matches = (tournament.matches ?? []).slice().sort((a, b) =>
    Number(a.phase ?? 0) - Number(b.phase ?? 0)
      || Number(a.scheduledOrder ?? 0) - Number(b.scheduledOrder ?? 0)
      || Number(a.leg ?? 1) - Number(b.leg ?? 1));
  $('matches-editor').innerHTML = matches.length ? matches.map((match) => {
    const home = team(match.homeTeamId);
    const away = team(match.awayTeamId);
    const gameLabel = match.tieId ? (match.leg === 2 ? 'Volta' : 'Ida') : `Jogo ${Number(match.scheduledOrder ?? 0) + 1}`;
    return `<article class="match-card" data-match-id="${esc(match.id)}">
      <div class="match-head"><strong>${phaseNames[match.phase] ?? 'Partida'}</strong><span>${gameLabel}</span></div>
      <div class="score-editor">
        <span class="team-name home">${esc(home?.name ?? 'A definir')}</span>
        <label>Placar<input type="number" min="0" step="1" value="${match.homeScore ?? 0}" data-match-field="homeScore"></label>
        <span class="versus">×</span>
        <label>Placar<input type="number" min="0" step="1" value="${match.awayScore ?? 0}" data-match-field="awayScore"></label>
        <span class="team-name">${esc(away?.name ?? 'A definir')}</span>
        <label>Situação<select data-match-field="status"><option value="0"${match.status === 0 ? ' selected' : ''}>A jogar</option><option value="1"${match.status === 1 ? ' selected' : ''}>Em andamento</option><option value="2"${match.status === 2 ? ' selected' : ''}>Encerrado</option></select></label>
      </div>
      <div class="scorers-editor">${scorerEditor(home, match)}${scorerEditor(away, match)}</div>
    </article>`;
  }).join('') : '<div class="empty">Este torneio não possui partidas.</div>';
}

function selectedMatch(matchId) {
  const tournament = draft.tournaments.find((item) => item.id === selectedTournamentId);
  return {
    tournament,
    match: (tournament?.matches ?? []).find((item) => item.id === matchId),
  };
}

function updateScorer(match, tournament, playerId, teamId, nextCount) {
  const previousCount = scorerCount(match, playerId, teamId);
  match.scorers = (match.scorers ?? []).filter((goal) =>
    !(goal.playerId === playerId && goal.teamId === teamId));
  for (let index = 0; index < nextCount; index++) {
    match.scorers.push({ playerId, teamId });
  }
  if (tournament.status === 1) {
    const player = draft.players.find((item) => item.id === playerId);
    if (player) {
      player.goals = Math.max(0, Number(player.goals ?? 0) + nextCount - previousCount);
      for (const row of $('players-editor').querySelectorAll('[data-player-id]')) {
        if (row.dataset.playerId !== playerId) continue;
        const goals = row.querySelector('[data-player-field="goals"]');
        if (goals) goals.value = String(player.goals);
      }
    }
  }
}

function validateDraft() {
  const names = new Set();
  for (const player of draft.players) {
    const name = String(player.name ?? '').trim();
    if (!name) throw new Error('Todos os jogadores precisam ter um nome.');
    const normalized = name.toLocaleLowerCase('pt-BR');
    if (names.has(normalized)) throw new Error(`Há mais de um jogador chamado ${name}.`);
    names.add(normalized);
    if (!Number.isFinite(player.stars) || player.stars < 0 || player.stars > 5) throw new Error(`O nível de ${name} deve ficar entre 0 e 5.`);
    if (!Number.isInteger(player.goals) || player.goals < 0 || !Number.isInteger(player.titles) || player.titles < 0) throw new Error(`Gols e títulos de ${name} precisam ser números inteiros positivos.`);
  }
  for (const tournament of draft.tournaments) {
    const team = (id) => (tournament.teams ?? []).find((item) => item.id === id);
    for (const match of tournament.matches ?? []) {
      if (!changedMatchIds.has(match.id)) continue;
      const homeScore = Number(match.homeScore ?? 0);
      const awayScore = Number(match.awayScore ?? 0);
      const label = `${phaseNames[match.phase] ?? 'Partida'} (${team(match.homeTeamId)?.name ?? 'A definir'} × ${team(match.awayTeamId)?.name ?? 'A definir'}, ${tournamentLabel(tournament)})`;
      if (!Number.isInteger(homeScore) || homeScore < 0 || !Number.isInteger(awayScore) || awayScore < 0) throw new Error(`Placar inválido em ${label}.`);
      if (match.status === 2) {
        const homeEvents = (match.scorers ?? []).filter((goal) => goal.teamId === match.homeTeamId).length;
        const awayEvents = (match.scorers ?? []).filter((goal) => goal.teamId === match.awayTeamId).length;
        if (homeEvents !== homeScore || awayEvents !== awayScore) throw new Error(`Autores dos gols não batem com o placar em ${label} (${homeEvents} × ${awayEvents} registrados, placar ${homeScore} × ${awayScore}).`);
      }
    }
  }
}

async function askSaveConfirmation() {
  return confirmDialog($('confirm-save'));
}

async function saveAll() {
  if (!dirty || !currentUser) return;
  try {
    validateDraft();
  } catch (error) {
    $('save-status').textContent = error.message;
    return;
  }
  if (!await askSaveConfirmation()) return;
  $('save-all').disabled = true;
  $('save-status').textContent = 'Salvando…';
  try {
    const nextRevision = loadedRevision + 1;
    await runTransaction(db, async (transaction) => {
      const snapshot = await transaction.get(mainRef);
      if (!snapshot.exists()) throw new RevisionConflictError();
      const cloudRevision = Number(snapshot.data().revision ?? 0);
      if (cloudRevision !== loadedRevision) throw new RevisionConflictError();
      transaction.set(mainRef, {
        updatedAt: serverTimestamp(),
        updatedBy: currentUser.uid,
        revision: nextRevision,
        players: draft.players,
        tournaments: draft.tournaments,
      });
    });
    loadedRevision = nextRevision;
    $('revision-label').textContent = `versão ${loadedRevision}`;
    changedMatchIds.clear();
    setDirty(false);
  } catch (error) {
    if (error instanceof RevisionConflictError) {
      $('conflict').classList.remove('hidden');
      $('save-status').textContent = 'Conflito detectado';
    } else {
      $('save-status').textContent = error.code === 'permission-denied'
        ? 'Sua conta não tem permissão para salvar.'
        : `Não foi possível salvar: ${error.message}`;
    }
    $('save-all').disabled = false;
  }
}

$('players-editor').addEventListener('input', (event) => {
  const field = event.target.dataset.playerField;
  if (!field) return;
  const row = event.target.closest('[data-player-id]');
  const player = draft.players.find((item) => item.id === row.dataset.playerId);
  if (!player) return;
  player[field] = field === 'name' ? event.target.value : Number(event.target.value);
  setDirty();
});

$('matches-editor').addEventListener('input', (event) => {
  const card = event.target.closest('[data-match-id]');
  if (!card) return;
  const { tournament, match } = selectedMatch(card.dataset.matchId);
  if (!match) return;
  const field = event.target.dataset.matchField;
  if (field) match[field] = Number(event.target.value);
  if (event.target.dataset.scorerPlayer) {
    const rawCount = Number(event.target.value);
    const nextCount = Number.isFinite(rawCount)
      ? Math.max(0, Math.trunc(rawCount))
      : 0;
    event.target.value = String(nextCount);
    updateScorer(match, tournament, event.target.dataset.scorerPlayer,
      event.target.dataset.scorerTeam, nextCount);
  }
  changedMatchIds.add(match.id);
  setDirty();
});

$('add-player').addEventListener('click', () => {
  draft.players.push({
    id: crypto.randomUUID(),
    name: 'Novo jogador',
    stars: 2.5,
    goals: 0,
    titles: 0,
    createdAt: Date.now(),
  });
  renderPlayers();
  setDirty();
  $('players-editor').querySelector('[data-player-id]:last-child input')?.select();
});

$('tournament-select').addEventListener('change', (event) => {
  selectedTournamentId = event.target.value;
  renderTournamentMeta();
  renderMatches();
});

$('tournament-meta').addEventListener('change', (event) => {
  const field = event.target.dataset.metaField;
  if (!field) return;
  const tournament = draft.tournaments.find((item) => item.id === selectedTournamentId);
  if (!tournament) return;
  if (field === 'createdAt') {
    const [year, month, day] = event.target.value.split('-').map(Number);
    const previous = new Date(tournament.createdAt);
    tournament.createdAt = new Date(
      year, month - 1, day,
      previous.getHours(), previous.getMinutes(), previous.getSeconds(),
    ).getTime();
    renderTournamentSelect();
  } else if (field === 'status') {
    tournament.status = Number(event.target.value);
  } else if (field === 'championTeamId') {
    tournament.championTeamId = event.target.value || null;
  }
  setDirty();
});

$('tournament-meta').addEventListener('click', async (event) => {
  if (event.target.id !== 'delete-tournament') return;
  const tournament = draft.tournaments.find((item) => item.id === selectedTournamentId);
  if (!tournament) return;
  $('delete-tournament-label').textContent = `Remover torneio de ${formatDate(tournament.createdAt)}?`;
  if (!await confirmDialog($('confirm-delete-tournament'))) return;
  draft.tournaments = draft.tournaments.filter((item) => item.id !== tournament.id);
  for (const match of tournament.matches ?? []) changedMatchIds.delete(match.id);
  selectedTournamentId = draft.tournaments
    .slice()
    .sort((a, b) => Number(b.createdAt ?? 0) - Number(a.createdAt ?? 0))[0]?.id ?? '';
  renderTournamentSelect();
  renderTournamentMeta();
  renderMatches();
  setDirty();
});

document.querySelectorAll('[data-tab]').forEach((button) => {
  button.addEventListener('click', () => {
    document.querySelectorAll('[data-tab]').forEach((item) => {
      const selected = item === button;
      item.classList.toggle('active', selected);
      item.setAttribute('aria-selected', String(selected));
    });
    $('players-panel').classList.toggle('hidden', button.dataset.tab !== 'players');
    $('matches-panel').classList.toggle('hidden', button.dataset.tab !== 'matches');
  });
});

$('save-all').addEventListener('click', saveAll);
$('reload-data').addEventListener('click', loadData);
$('sign-out').addEventListener('click', () => signOut(auth));
$('sign-in').addEventListener('click', async () => {
  showAuthMessage('Abrindo o Google…');
  try {
    const provider = new GoogleAuthProvider();
    provider.setCustomParameters({ prompt: 'select_account' });
    await signInWithPopup(auth, provider);
  } catch (error) {
    showAuthMessage(error.code === 'auth/popup-closed-by-user'
      ? 'O login foi cancelado.'
      : 'Não foi possível entrar com o Google. Tente novamente.');
  }
});

window.addEventListener('beforeunload', (event) => {
  if (!dirty) return;
  event.preventDefault();
  event.returnValue = '';
});

onAuthStateChanged(auth, async (user) => {
  if (!user) {
    showSignedOut();
    return;
  }
  showAuthMessage('Verificando autorização…');
  try {
    const usesGoogle = user.providerData.some((provider) => provider.providerId === 'google.com');
    const email = user.email?.toLowerCase();
    if (!usesGoogle || !user.emailVerified || !email) throw new Error('Conta Google inválida.');
    const writer = await getDoc(doc(db, 'rdr_writers', email));
    if (!writer.exists()) {
      await signOut(auth);
      showSignedOut(`A conta ${email} não está autorizada.`);
      return;
    }
    showAuthorized(user);
    await loadData();
  } catch (error) {
    if (auth.currentUser) await signOut(auth);
    showSignedOut(error.code === 'permission-denied'
      ? 'Esta conta não está autorizada a administrar o racha.'
      : `Não foi possível carregar o painel: ${error.message}`);
  }
});
