// Higieniza o documento público do Firestore antes de qualquer desenho.
//
// O site monta HTML com os dados do documento. Texto (nomes, ids) passa por
// esc() na hora de desenhar; os NÚMEROS (placar, minutos, gols, datas, fase)
// entram direto no HTML e em comparações. Em vez de confiar que cada ponto
// lembre de converter, tudo que deveria ser número vira número aqui, uma vez,
// na entrada: um valor como "<img onerror=...>" num campo numérico vira 0
// (ou null) e nunca chega ao HTML. Vale mesmo que alguém consiga gravar no
// documento.

export const num = (v, fallback = 0) => {
  const x = Number(v);
  return Number.isFinite(x) ? x : fallback;
};
const optNum = (v) => (v == null ? null : num(v, null));
const arr = (v) => (Array.isArray(v) ? v : []);
const obj = (v) => (v && typeof v === 'object' && !Array.isArray(v) ? v : {});
const str = (v) => (v == null ? '' : String(v));

export function normalize(raw) {
  const data = obj(raw);
  data.revision = optNum(data.revision);
  data.updatedAt = optNum(data.updatedAt);

  data.players = arr(data.players).map(obj);
  for (const p of data.players) {
    p.id = str(p.id);
    p.goals = num(p.goals);
    p.titles = num(p.titles);
  }

  data.tournaments = arr(data.tournaments).map(obj);
  for (const t of data.tournaments) {
    t.id = str(t.id);
    t.createdAt = num(t.createdAt);
    t.status = num(t.status);
    t.championTeamId = t.championTeamId == null ? null : str(t.championTeamId);
    t.twoLegged = t.twoLegged === true;
    t.teams = arr(t.teams).map(obj);
    for (const team of t.teams) {
      team.id = str(team.id);
      team.colorValue = optNum(team.colorValue);
      team.playerIds = arr(team.playerIds).map(str);
    }
    t.matches = arr(t.matches).map(obj);
    for (const m of t.matches) {
      m.id = str(m.id);
      m.homeTeamId = str(m.homeTeamId);
      m.awayTeamId = str(m.awayTeamId);
      m.phase = num(m.phase);
      m.status = num(m.status);
      m.scheduledOrder = num(m.scheduledOrder);
      m.leg = optNum(m.leg);
      m.homeScore = optNum(m.homeScore);
      m.awayScore = optNum(m.awayScore);
      m.penaltyWinnerId = m.penaltyWinnerId == null ? null : str(m.penaltyWinnerId);
      m.scorers = arr(m.scorers).map(obj);
      for (const g of m.scorers) {
        g.playerId = str(g.playerId);
        g.teamId = str(g.teamId);
        g.minute = optNum(g.minute);
      }
    }
  }
  return data;
}
