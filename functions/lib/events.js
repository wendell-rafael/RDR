// Qual é o racha da vez, quando o check-in abre pra ele e quantas vagas tem.
//
// O id do evento é a data do jogo (`2026-09-22`), não a data da abertura.
// Assim o documento tem o mesmo nome no painel, na página e no log, e criar o
// mesmo evento duas vezes é impossível: o id é derivado, nunca sorteado.
//
// São duas filas independentes, linha e goleiro. Elas não competem entre si:
// goleiro sobrando não vira vaga de linha, e linha sobrando não tapa a falta de
// goleiro. Misturar as duas numa fila só faria o time entrar em campo com
// dezesseis na linha e ninguém no gol.

import { addDays, dateId, zonedParts, zonedTimeToDate } from './time.js';

export const DEFAULT_CONFIG = Object.freeze({
  // 0 = domingo. Jogo na terça às 19h, check-in liberado na quinta anterior
  // ao meio-dia — cinco dias de janela.
  matchWeekday: 2,
  matchHour: 19,
  matchMinute: 0,
  openWeekday: 4,
  openHour: 12,
  openMinute: 0,
  // Fecha duas horas antes da bola rolar.
  closeMinutesBeforeMatch: 120,

  // Dezesseis na linha e dois no gol.
  playerCapacity: 16,
  keeperCapacity: 2,
  playerWaitlist: 10,
  keeperWaitlist: 2,

  // Teto duro de documentos por evento. Acima disso a inscrição é recusada:
  // ninguém nessa faixa jogaria mesmo, e evita alguém encher a coleção.
  maxEntries: 120,
});

// Quem já tem vaga garantida e não precisa apertar botão nenhum. Ocupa vaga de
// linha, então a fila disputa `playerCapacity - fixedPlayers.length`.
export const DEFAULT_FIXED_PLAYERS = Object.freeze(['Rafael', 'Augusto', 'Wendell', 'Caio']);

const RANGE = Object.freeze({
  matchWeekday: [0, 6],
  matchHour: [0, 23],
  matchMinute: [0, 59],
  openWeekday: [0, 6],
  openHour: [0, 23],
  openMinute: [0, 59],
  closeMinutesBeforeMatch: [0, 10080],
  playerCapacity: [0, 200],
  keeperCapacity: [0, 20],
  playerWaitlist: [0, 200],
  keeperWaitlist: [0, 20],
  maxEntries: [1, 500],
});

export const ROLES = Object.freeze(['player', 'keeper']);

const NAME_MAX = 40;
const MAX_FIXED = 40;

/** Lista de fixos: nomes limpos, sem repetição, sem buraco. */
export function normalizeFixedPlayers(raw) {
  if (!Array.isArray(raw)) return [...DEFAULT_FIXED_PLAYERS];
  const seen = new Set();
  const out = [];
  for (const value of raw) {
    if (typeof value !== 'string') continue;
    const name = value.replace(/\s+/g, ' ').trim().slice(0, NAME_MAX);
    if (name.length < 2) continue;
    const key = name.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(name);
    if (out.length >= MAX_FIXED) break;
  }
  return out;
}

/** Uids que dispensam check-in — o vínculo opcional dos fixos com a conta. */
export function normalizeFixedUids(raw) {
  if (!Array.isArray(raw)) return [];
  return raw
    .filter((value) => typeof value === 'string' && value.length > 0 && value.length <= 128)
    .slice(0, MAX_FIXED);
}

/** Descarta qualquer campo fora da faixa e cai no padrão. */
export function normalizeConfig(raw) {
  const config = { ...DEFAULT_CONFIG };
  if (raw && typeof raw === 'object') {
    for (const [key, [min, max]] of Object.entries(RANGE)) {
      const value = raw[key];
      if (typeof value !== 'number' || !Number.isInteger(value)) continue;
      if (value < min || value > max) continue;
      config[key] = value;
    }
  }
  config.fixedPlayers = normalizeFixedPlayers(raw?.fixedPlayers);
  config.fixedUids = normalizeFixedUids(raw?.fixedUids);

  const total = config.playerCapacity + config.keeperCapacity
    + config.playerWaitlist + config.keeperWaitlist;
  if (total > config.maxEntries) config.maxEntries = Math.min(500, total);
  return config;
}

/**
 * Vagas realmente disputadas na fila de linha.
 *
 * Os fixos já ocupam parte da capacidade, então a fila briga pelo que sobra.
 * Se algum dia a lista de fixos passar da capacidade, sobra zero — nunca um
 * número negativo, que viraria fatia invertida na hora de cortar a fila.
 */
export function openPlayerSlots(capacity, fixedCount) {
  return Math.max(0, Number(capacity ?? 0) - Number(fixedCount ?? 0));
}

/**
 * Evento corrente: o próximo jogo que ainda não começou.
 *
 * Varre no máximo oito dias à frente porque `matchWeekday` cai dentro de uma
 * semana por definição — o dia extra cobre o caso de hoje ser o dia do jogo com
 * a hora já passada.
 */
export function resolveEvent(now, rawConfig) {
  const config = normalizeConfig(rawConfig);
  const today = zonedParts(now);

  let matchDay = null;
  let matchAt = null;
  for (let ahead = 0; ahead <= 8; ahead += 1) {
    const candidate = addDays(today, ahead);
    const weekday = new Date(Date.UTC(candidate.year, candidate.month - 1, candidate.day)).getUTCDay();
    if (weekday !== config.matchWeekday) continue;
    const at = zonedTimeToDate({
      ...candidate,
      hour: config.matchHour,
      minute: config.matchMinute,
    });
    // O jogo de hoje só continua sendo "o da vez" até a hora marcada.
    if (at.getTime() <= now.getTime()) continue;
    matchDay = candidate;
    matchAt = at;
    break;
  }
  if (!matchDay) return null;

  // Abertura: o `openWeekday` imediatamente anterior ao jogo. Se cair no mesmo
  // dia da semana, volta uma semana inteira em vez de abrir depois do jogo.
  let daysBack = (config.matchWeekday - config.openWeekday + 7) % 7;
  if (daysBack === 0) daysBack = 7;
  const openDay = addDays(matchDay, -daysBack);
  const openAt = zonedTimeToDate({
    ...openDay,
    hour: config.openHour,
    minute: config.openMinute,
  });
  const closeAt = new Date(matchAt.getTime() - config.closeMinutesBeforeMatch * 60000);

  return {
    eventId: dateId(matchDay),
    openAt,
    closeAt,
    matchAt,
    playerCapacity: config.playerCapacity,
    keeperCapacity: config.keeperCapacity,
    playerWaitlist: config.playerWaitlist,
    keeperWaitlist: config.keeperWaitlist,
    fixedPlayers: config.fixedPlayers,
    fixedUids: config.fixedUids,
    maxEntries: config.maxEntries,
  };
}

/** Janela aberta? Considera o override manual gravado no documento do evento. */
export function windowState(event, now) {
  const at = now.getTime();
  if (event.status === 'canceled') return 'canceled';
  if (event.status === 'closed') return 'closed';
  if (event.status === 'open') return 'open';
  if (at < event.openAt.getTime()) return 'scheduled';
  if (at >= event.closeAt.getTime()) return 'closed';
  return 'open';
}

/**
 * Corta as duas filas.
 *
 * Recebe a lista já ordenada por `createdAt` e devolve, por função, quem está
 * dentro, quem espera e quem sobrou. Nada disso fica gravado: é sempre a
 * posição na ordem. Por isso uma desistência faz a fila andar sozinha, e mudar
 * a capacidade só move a linha de corte, sem reordenar ninguém.
 *
 * Usada pelo teste; a página e o painel repetem a mesma conta em JavaScript de
 * navegador, e os testes daqui é que fixam o comportamento esperado.
 */
export function splitQueues(entries, event) {
  const fixedCount = (event.fixedPlayers ?? []).length;
  const slots = {
    player: openPlayerSlots(event.playerCapacity, fixedCount),
    keeper: Number(event.keeperCapacity ?? 0),
  };
  const waits = {
    player: Number(event.playerWaitlist ?? 0),
    keeper: Number(event.keeperWaitlist ?? 0),
  };

  const result = {};
  for (const role of ROLES) {
    const queue = entries.filter((entry) => (entry.role ?? 'player') === role);
    result[role] = {
      confirmed: queue.slice(0, slots[role]),
      waiting: queue.slice(slots[role], slots[role] + waits[role]),
      overflow: queue.slice(slots[role] + waits[role]),
      slots: slots[role],
    };
  }
  return result;
}
