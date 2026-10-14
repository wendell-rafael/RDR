// Testes das partes puras do check-in: cálculo da semana e corte das filas.
// Rodar com `node --test` dentro de `functions/`.

import test from 'node:test';
import assert from 'node:assert/strict';
import {
  DEFAULT_CONFIG,
  DEFAULT_FIXED_PLAYERS,
  normalizeConfig,
  openPlayerSlots,
  resolveEvent,
  splitQueues,
  windowState,
} from '../lib/events.js';
import { addDays, dateId, zonedParts, zonedTimeToDate } from '../lib/time.js';

const at = (iso) => new Date(iso);

// ── Semana e fuso ────────────────────────────────────────────────────────

test('quinta 12h em São Paulo é 15h UTC', () => {
  assert.equal(
    zonedTimeToDate({ year: 2026, month: 9, day: 17, hour: 12, minute: 0 }).toISOString(),
    '2026-09-17T15:00:00.000Z',
  );
});

test('dia da semana sai no fuso do racha, não no do servidor', () => {
  // 23h de São Paulo já é o dia seguinte em UTC.
  assert.equal(zonedParts(at('2026-09-18T02:00:00Z')).day, 17);
  assert.equal(zonedParts(at('2026-09-18T02:00:00Z')).weekday, 4);
});

test('soma de dias atravessa a virada do mês', () => {
  assert.equal(dateId(addDays({ year: 2026, month: 9, day: 30 }, 2)), '2026-10-02');
});

test('o racha da vez só troca depois de a bola rolar', () => {
  // Terça, 19h em São Paulo = 22h UTC.
  const before = resolveEvent(at('2026-09-22T21:59:00Z'), null);
  const after = resolveEvent(at('2026-09-22T22:01:00Z'), null);
  assert.equal(before.eventId, '2026-09-22');
  assert.equal(after.eventId, '2026-09-29');
});

test('o padrão é jogo na terça 19h com abertura na quinta anterior ao meio-dia', () => {
  const event = resolveEvent(at('2026-09-16T12:00:00Z'), null);
  assert.equal(zonedParts(event.matchAt).weekday, 2);
  assert.equal(zonedParts(event.matchAt).hour, 19);
  assert.equal(zonedParts(event.openAt).weekday, 4);
  assert.equal(zonedParts(event.openAt).hour, 12);
  assert.equal(event.openAt.toISOString(), '2026-09-17T15:00:00.000Z');
  // Quinta meio-dia até terça 19h: cinco dias e sete horas de janela.
  assert.equal(event.matchAt.getTime() - event.openAt.getTime(), 5 * 86400000 + 7 * 3600000);
});

test('a abertura nunca cai depois do jogo', () => {
  for (const iso of ['2026-09-16T12:00:00Z', '2026-09-22T21:00:00Z', '2026-09-23T03:00:00Z']) {
    const event = resolveEvent(at(iso), null);
    assert.ok(event.openAt < event.matchAt, iso);
    assert.ok(event.closeAt < event.matchAt, iso);
  }
});

test('jogo e abertura no mesmo dia da semana voltam uma semana inteira', () => {
  // Jogo na quinta e abertura na quinta: tem que abrir sete dias antes, senão
  // abriria depois do próprio jogo.
  const event = resolveEvent(at('2026-09-14T12:00:00Z'), {
    ...DEFAULT_CONFIG, matchWeekday: 4, openWeekday: 4, openHour: 12, matchHour: 20,
  });
  assert.equal(event.matchAt.getTime() - event.openAt.getTime(), 7 * 86400000 + 8 * 3600000);
});

// ── Configuração ─────────────────────────────────────────────────────────

test('o padrão é 16 de linha, 2 no gol e 4 fixos', () => {
  assert.equal(DEFAULT_CONFIG.playerCapacity, 16);
  assert.equal(DEFAULT_CONFIG.keeperCapacity, 2);
  assert.deepEqual([...DEFAULT_FIXED_PLAYERS], ['Rafael', 'Augusto', 'Wendell', 'Caio']);
  assert.deepEqual(normalizeConfig(null).fixedPlayers, ['Rafael', 'Augusto', 'Wendell', 'Caio']);
});

test('configuração fora da faixa é descartada, não aplicada', () => {
  const config = normalizeConfig({ playerCapacity: 9999, matchWeekday: 12, keeperCapacity: 3 });
  assert.equal(config.playerCapacity, DEFAULT_CONFIG.playerCapacity);
  assert.equal(config.matchWeekday, DEFAULT_CONFIG.matchWeekday);
  assert.equal(config.keeperCapacity, 3);
});

test('lista de fixos é limpa: sem repetido, sem espaço solto, sem lixo', () => {
  const config = normalizeConfig({
    fixedPlayers: ['  Rafael ', 'rafael', 'Augusto', '', 'x', 42, 'Caio'],
  });
  assert.deepEqual(config.fixedPlayers, ['Rafael', 'Augusto', 'Caio']);
});

test('o teto de inscrições sobe sozinho se as vagas não couberem nele', () => {
  const config = normalizeConfig({
    playerCapacity: 200, keeperCapacity: 20, playerWaitlist: 200, keeperWaitlist: 20, maxEntries: 1,
  });
  assert.equal(config.maxEntries, 440);
});

// ── Janela ───────────────────────────────────────────────────────────────

test('override manual vence o horário', () => {
  const janela = {
    openAt: at('2026-09-17T15:00:00Z'),
    closeAt: at('2026-09-22T20:00:00Z'),
  };
  const dentro = at('2026-09-18T12:00:00Z');
  assert.equal(windowState({ ...janela, status: 'auto' }, dentro), 'open');
  assert.equal(windowState({ ...janela, status: 'closed' }, dentro), 'closed');
  assert.equal(windowState({ ...janela, status: 'canceled' }, dentro), 'canceled');
  assert.equal(windowState({ ...janela, status: 'open' }, at('2026-09-16T12:00:00Z')), 'open');
});

test('janela automática respeita abertura e fechamento', () => {
  const event = {
    status: 'auto',
    openAt: at('2026-09-17T15:00:00Z'),
    closeAt: at('2026-09-22T20:00:00Z'),
  };
  assert.equal(windowState(event, at('2026-09-17T14:59:59Z')), 'scheduled');
  assert.equal(windowState(event, at('2026-09-17T15:00:00Z')), 'open');
  assert.equal(windowState(event, at('2026-09-22T20:00:00Z')), 'closed');
});

// ── Corte das filas ──────────────────────────────────────────────────────

const EVENT = {
  playerCapacity: 16,
  keeperCapacity: 2,
  playerWaitlist: 10,
  keeperWaitlist: 2,
  fixedPlayers: ['Rafael', 'Augusto', 'Wendell', 'Caio'],
};

/** Fila fabricada: `n` inscritos da função pedida, em ordem de chegada. */
const queue = (role, n, from = 1) => Array.from(
  { length: n },
  (_, index) => ({ id: `${role}-${index + from}`, role }),
);

test('os quatro fixos saem das 16 vagas, sobrando 12 na disputa', () => {
  assert.equal(openPlayerSlots(16, 4), 12);
  const { player } = splitQueues(queue('player', 20), EVENT);
  assert.equal(player.slots, 12);
  assert.equal(player.confirmed.length, 12);
  assert.equal(player.waiting.length, 8);
  assert.equal(player.overflow.length, 0);
});

test('mais fixos que vagas não devolve fatia invertida', () => {
  const lotado = { ...EVENT, playerCapacity: 3 };
  const { player } = splitQueues(queue('player', 5), lotado);
  assert.equal(player.slots, 0);
  assert.equal(player.confirmed.length, 0);
  assert.equal(player.waiting.length, 5);
});

test('linha e gol são filas independentes', () => {
  const entries = [...queue('player', 14), ...queue('keeper', 4)];
  const { player, keeper } = splitQueues(entries, EVENT);
  // Sobrar gente na linha não abre vaga no gol, e vice-versa.
  assert.equal(player.confirmed.length, 12);
  assert.equal(player.waiting.length, 2);
  assert.equal(keeper.confirmed.length, 2);
  assert.equal(keeper.waiting.length, 2);
  assert.equal(keeper.overflow.length, 0);
});

test('goleiro sobrando não vira vaga de linha', () => {
  const entries = [...queue('player', 20), ...queue('keeper', 1)];
  const { player, keeper } = splitQueues(entries, EVENT);
  assert.equal(player.confirmed.length, 12);
  assert.equal(keeper.confirmed.length, 1);
});

test('inscrição sem função declarada conta como linha', () => {
  const { player } = splitQueues([{ id: 'antigo' }], EVENT);
  assert.equal(player.confirmed.length, 1);
});

test('desistência faz a fila andar sozinha, sem promover ninguém à mão', () => {
  const entries = queue('player', 14);
  const antes = splitQueues(entries, EVENT);
  assert.equal(antes.waiting?.length, undefined); // o corte vem por função
  assert.deepEqual(antes.player.waiting.map((e) => e.id), ['player-13', 'player-14']);

  const depois = splitQueues(entries.filter((e) => e.id !== 'player-2'), EVENT);
  // 'player-13' subiu sem que nada tenha sido gravado.
  assert.deepEqual(depois.player.waiting.map((e) => e.id), ['player-14']);
  assert.ok(depois.player.confirmed.some((e) => e.id === 'player-13'));
});

test('mudar a capacidade só move a linha de corte, não reordena', () => {
  const entries = queue('player', 14);
  const maior = splitQueues(entries, { ...EVENT, playerCapacity: 18 });
  assert.equal(maior.slots, undefined);
  assert.equal(maior.player.slots, 14);
  assert.deepEqual(maior.player.confirmed.map((e) => e.id), entries.map((e) => e.id));
  assert.equal(maior.player.waiting.length, 0);
});

test('quem passa da espera cai no excedente', () => {
  const apertado = { ...EVENT, playerWaitlist: 2 };
  const { player } = splitQueues(queue('player', 16), apertado);
  assert.equal(player.confirmed.length, 12);
  assert.equal(player.waiting.length, 2);
  assert.equal(player.overflow.length, 2);
});
