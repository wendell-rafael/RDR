// node --test painel/test
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { normalize } from '../data.js';

const EVIL = '<img src=x onerror=alert(1)>';

test('números legítimos passam intactos', () => {
  const d = normalize({
    revision: 12, updatedAt: 1760000000000,
    players: [{ id: 'p', name: 'Ana', goals: 7, titles: 2 }],
    tournaments: [{
      id: 't', createdAt: 1760000000000, status: 2, championTeamId: 'a', twoLegged: true,
      teams: [{ id: 'a', name: 'Time A', colorValue: 0xff1e5bff, playerIds: ['p'] }],
      matches: [{ id: 'm', phase: 0, status: 2, homeScore: 3, awayScore: 1, scheduledOrder: 4, leg: 1,
        homeTeamId: 'a', awayTeamId: 'b', scorers: [{ playerId: 'p', teamId: 'a', minute: 6 }] }],
    }],
  });
  assert.equal(d.players[0].goals, 7);
  assert.equal(d.tournaments[0].matches[0].homeScore, 3);
  assert.equal(d.tournaments[0].matches[0].scorers[0].minute, 6);
  assert.equal(d.tournaments[0].twoLegged, true);
});

test('HTML em campo numérico vira 0 ou null', () => {
  const d = normalize({
    revision: EVIL,
    players: [{ goals: EVIL, titles: EVIL }],
    tournaments: [{ createdAt: EVIL, status: EVIL, teams: [{ colorValue: EVIL, playerIds: 'x' }],
      matches: [{ phase: EVIL, status: EVIL, homeScore: EVIL, scorers: [{ minute: EVIL }] }] }],
  });
  const t = d.tournaments[0], m = t.matches[0];
  assert.equal(d.revision, null);
  assert.equal(d.players[0].goals, 0);
  assert.equal(t.createdAt, 0);
  assert.equal(t.teams[0].colorValue, null);
  assert.deepEqual(t.teams[0].playerIds, []);
  assert.equal(m.phase, 0);
  assert.equal(m.homeScore, null);
  assert.equal(m.scorers[0].minute, null);
});

test('estrutura inválida vira vazia', () => {
  const d = normalize({ players: 'x', tournaments: { a: 1 } });
  assert.deepEqual(d.players, []);
  assert.deepEqual(d.tournaments, []);
  assert.deepEqual(normalize(null).players, []);
});
