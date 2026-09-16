import { firebaseConfig } from './firebase-config.js';

function decodeValue(v){if(!v||'nullValue'in v)return null;if('stringValue'in v)return v.stringValue;if('integerValue'in v)return Number(v.integerValue);if('doubleValue'in v)return Number(v.doubleValue);if('booleanValue'in v)return v.booleanValue;if('timestampValue'in v)return new Date(v.timestampValue).getTime();if('arrayValue'in v)return(v.arrayValue.values??[]).map(decodeValue);if('mapValue'in v)return decodeFields(v.mapValue.fields??{});return null}
function decodeFields(fields){const out={};for(const key in fields)out[key]=decodeValue(fields[key]);return out}
const $=(id)=>document.getElementById(id);
const fmtNumber=new Intl.NumberFormat('pt-BR');
const fmtDate=(ms)=>new Date(ms).toLocaleDateString('pt-BR',{day:'2-digit',month:'2-digit',year:'numeric'});
const plural=(n,one,many)=>`${fmtNumber.format(n)} ${n===1?one:many}`;
const esc=(s)=>String(s).replace(/[&<>"']/g,(c)=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const colorOf=(team)=>team?.colorValue==null?'#7b9488':`#${(Number(team.colorValue)&0xffffff).toString(16).padStart(6,'0')}`;
const phaseName=['Fase de grupos','Mata-mata','Final','Semifinal'];
let currentData={players:[],tournaments:[]};
const playerLink=(id,name)=>`<button type="button" class="player-link" data-player-id="${esc(id)}" aria-haspopup="dialog">${esc(name)}</button>`;

function showError(title,detail){$('loading').classList.add('hidden');$('updated').textContent='';const el=$('error');el.classList.remove('hidden');el.innerHTML=`<strong>${esc(title)}</strong>${detail?`<code>${esc(detail)}</code>`:''}<button type="button" class="retry">Tentar novamente</button>`;el.querySelector('.retry').addEventListener('click',()=>location.reload())}
function ranking(players,key,limit=Infinity){return players.filter((p)=>Number(p[key]??0)>0).map((p)=>({id:p.id,name:p.name||'Sem nome',value:Number(p[key])})).sort((a,b)=>b.value-a.value||a.name.localeCompare(b.name,'pt-BR')).slice(0,limit)}
function renderRankTable(rows,color,unitOne,unitMany,startAt,max){return `<table class="rank"><tbody>${rows.map((r,i)=>`<tr><td class="pos">${String(i+startAt).padStart(2,'0')}</td><td class="who" title="${esc(r.name)}">${playerLink(r.id,r.name)}</td><td class="barcell"><div class="bar" style="width:${Math.max((r.value/max)*100,2)}%;background:${color}"></div></td><td class="val">${fmtNumber.format(r.value)} <small>${r.value===1?unitOne:unitMany}</small></td></tr>`).join('')}</tbody></table>`}
function renderRank(host,rows,color,unitOne,unitMany){
  if(!rows.length){host.innerHTML='<div class="msg">Nada registrado ainda.</div>';return}
  const max=Math.max(rows[0].value,1);
  const podium=rows.slice(0,3),rest=rows.slice(3);
  const medal=['🥇','🥈','🥉'];
  const podiumHtml=`<div class="podium">${[1,0,2].filter((i)=>podium[i]).map((i)=>{const r=podium[i];return `<div class="podium-slot place-${i+1}"><span class="podium-medal" aria-hidden="true">${medal[i]}</span>${playerLink(r.id,r.name)}<strong>${fmtNumber.format(r.value)}</strong><span class="podium-unit">${r.value===1?unitOne:unitMany}</span></div>`}).join('')}</div>`;
  host.innerHTML=podiumHtml+(rest.length?renderRankTable(rest,color,unitOne,unitMany,4,max):'');
}

// ── Recordes ─────────────────────────────────────────────────────────────
function allFinishedMatches(tournaments){const rows=[];for(const t of tournaments){for(const m of t.matches??[]){if(m.status!==2||m.homeScore==null||m.awayScore==null)continue;rows.push({t,m})}}return rows}
function teamName(tournament,id){return esc((tournament.teams??[]).find((team)=>team.id===id)?.name||'Time')}
function computeRecords(players,tournaments){
  const playerMap=new Map(players.map((p)=>[p.id,p]));
  const finished=allFinishedMatches(tournaments);
  if(!finished.length)return null;
  let blowout=null,highScoring=null,hatTrick=null,edgeScorer=null,lateGoal=null;
  for(const {t,m} of finished){
    const diff=Math.abs(m.homeScore-m.awayScore);
    if(!blowout||diff>blowout.diff)blowout={diff,t,m};
    const total=m.homeScore+m.awayScore;
    if(!highScoring||total>highScoring.total)highScoring={total,t,m};
    const counts=new Map();
    for(const g of m.scorers??[])counts.set(g.playerId,(counts.get(g.playerId)??0)+1);
    for(const [playerId,count] of counts)if(count>=2&&(!hatTrick||count>hatTrick.count))hatTrick={count,playerId,t,m};
    for(const g of m.scorers??[]){
      if(typeof g.minute!=='number')continue;
      if(!lateGoal||g.minute>lateGoal.minute)lateGoal={minute:g.minute,playerId:g.playerId,t,m};
    }
  }
  for(const t of tournaments){
    const counts=new Map();
    for(const m of t.matches??[])for(const g of m.scorers??[])counts.set(g.playerId,(counts.get(g.playerId)??0)+1);
    for(const [playerId,count] of counts)if(!edgeScorer||count>edgeScorer.count)edgeScorer={count,playerId,t};
  }
  const sorted=tournaments.slice().sort((a,b)=>Number(a.createdAt??0)-Number(b.createdAt??0));
  let bestStreak=null;
  const activeStreaks=new Map();
  for(const t of sorted){
    const champ=(t.teams??[]).find((team)=>team.id===t.championTeamId);
    const champPlayers=new Set(champ?.playerIds??[]);
    for(const playerId of [...activeStreaks.keys()])if(!champPlayers.has(playerId))activeStreaks.delete(playerId);
    for(const playerId of champPlayers){
      const next=(activeStreaks.get(playerId)??0)+1;
      activeStreaks.set(playerId,next);
      if(!bestStreak||next>bestStreak.count)bestStreak={count:next,playerId,lastTournament:t};
    }
  }
  return {blowout,highScoring,hatTrick,edgeScorer,bestStreak,lateGoal,playerMap};
}
function renderRecords(players,tournaments){
  const data=computeRecords(players,tournaments);
  const heading=$('records').previousElementSibling;
  if(!data){$('records').innerHTML='';if(heading)heading.classList.add('hidden');$('records').classList.add('hidden');return}
  if(heading)heading.classList.remove('hidden');
  $('records').classList.remove('hidden');
  const {blowout,highScoring,hatTrick,edgeScorer,bestStreak,lateGoal,playerMap}=data;
  const playerName=(id)=>esc(playerMap.get(id)?.name||'Jogador');
  const cards=[];
  if(blowout)cards.push({icon:'💥',label:'Maior goleada',value:`${blowout.diff} ${blowout.diff===1?'gol':'gols'} de diferença`,detail:`${teamName(blowout.t,blowout.m.homeTeamId)} ${blowout.m.homeScore} × ${blowout.m.awayScore} ${teamName(blowout.t,blowout.m.awayTeamId)} · ${fmtDate(blowout.t.createdAt)}`});
  if(highScoring)cards.push({icon:'🥅',label:'Jogo com mais gols',value:plural(highScoring.total,'gol','gols'),detail:`${teamName(highScoring.t,highScoring.m.homeTeamId)} ${highScoring.m.homeScore} × ${highScoring.m.awayScore} ${teamName(highScoring.t,highScoring.m.awayTeamId)} · ${fmtDate(highScoring.t.createdAt)}`});
  if(hatTrick)cards.push({icon:'🎩',label:'Mais gols em um jogo',value:plural(hatTrick.count,'gol','gols'),detail:`${playerName(hatTrick.playerId)} · ${fmtDate(hatTrick.t.createdAt)}`});
  if(edgeScorer)cards.push({icon:'👑',label:'Artilheiro de uma edição',value:plural(edgeScorer.count,'gol','gols'),detail:`${playerName(edgeScorer.playerId)} · torneio de ${fmtDate(edgeScorer.t.createdAt)}`});
  if(bestStreak&&bestStreak.count>1)cards.push({icon:'🔥',label:'Maior sequência de títulos',value:`${bestStreak.count} seguidos`,detail:`${playerName(bestStreak.playerId)} · até ${fmtDate(bestStreak.lastTournament.createdAt)}`});
  if(lateGoal)cards.push({icon:'⏱️',label:'Gol mais tardio',value:`${lateGoal.minute}'`,detail:`${playerName(lateGoal.playerId)} · ${teamName(lateGoal.t,lateGoal.m.homeTeamId)} ${lateGoal.m.homeScore} × ${lateGoal.m.awayScore} ${teamName(lateGoal.t,lateGoal.m.awayTeamId)} · ${fmtDate(lateGoal.t.createdAt)}`});
  $('records').innerHTML=cards.length?cards.map((c)=>`<div class="record-card"><span class="record-icon" aria-hidden="true">${c.icon}</span><strong>${c.value}</strong><span class="record-label">${c.label}</span><span class="record-detail">${c.detail}</span></div>`).join(''):'<div class="msg">Nada registrado ainda.</div>';
}

// ── Campeão da semana ────────────────────────────────────────────────────
// Fica com o time campeão do torneio mais recente que já teve campeão
// definido — continua ali até um torneio mais novo coroar outro campeão.
function computeCurrentChampion(tournaments){
  const sorted=tournaments.slice().sort((a,b)=>Number(b.createdAt??0)-Number(a.createdAt??0));
  for(const t of sorted){
    const team=(t.teams??[]).find((item)=>item.id===t.championTeamId);
    if(team)return {tournament:t,team};
  }
  return null;
}
function renderTeamOfWeek(tournaments,players){
  const host=$('champion-card'),heading=host.previousElementSibling,data=computeCurrentChampion(tournaments);
  if(!data){host.innerHTML='';heading?.classList.add('hidden');host.classList.add('hidden');return}
  heading?.classList.remove('hidden');host.classList.remove('hidden');
  const {tournament,team}=data;
  const row=standings(tournament).find((item)=>item.team.id===team.id);
  const sg=row?row.gf-row.ga:null;
  const roster=(team.playerIds??[]).map((id)=>players.get(id)).filter(Boolean);
  const statsHtml=row?`<div class="champion-stats"><div><strong>${row.pts}</strong><span>PTS</span></div><div><strong>${row.w}</strong><span>V</span></div><div><strong>${row.d}</strong><span>E</span></div><div><strong>${row.l}</strong><span>D</span></div><div><strong>${sg>0?'+':''}${sg}</strong><span>SG</span></div></div>`:'';
  host.innerHTML=`<div class="champion-head"><span class="champion-trophy" aria-hidden="true">🏆</span><span class="dot" style="background:${colorOf(team)}"></span><strong>${esc(team.name)}</strong><span class="champion-tag">CAMPEÃO ATUAL</span></div>${statsHtml}<p class="champion-meta">Desde o torneio de ${fmtDate(tournament.createdAt)}</p>${roster.length?`<p class="champion-roster">${roster.map((p)=>playerLink(p.id,p.name||'Sem nome')).join(', ')}</p>`:''}`;
}

// ── Ao vivo ──────────────────────────────────────────────────────────────
function renderLiveBanner(tournaments){
  const active=tournaments.find((t)=>Number(t.status)===0);
  const el=$('live-banner');
  if(!active){el.classList.add('hidden');el.innerHTML='';return}
  const played=(active.matches??[]).filter((m)=>m.status===2).length,total=(active.matches??[]).length;
  el.classList.remove('hidden');
  el.innerHTML=`<span class="live-dot" aria-hidden="true"></span><span>Racha rolando agora — ${played}/${total} jogos disputados</span><button type="button" data-open-tournament="${esc(active.id)}">Ver ao vivo</button>`;
}
$('live-banner').addEventListener('click',(event)=>{
  const trigger=event.target.closest('[data-open-tournament]');
  if(!trigger)return;
  const details=document.getElementById(`tournament-${trigger.dataset.openTournament}`);
  if(details){details.open=true;details.scrollIntoView({behavior:'smooth',block:'start'})}
});

// ── Comparar jogadores ───────────────────────────────────────────────────
function populateCompareSelects(players){
  const options=players.slice().sort((a,b)=>String(a.name??'').localeCompare(String(b.name??''),'pt-BR')).map((p)=>`<option value="${esc(p.id)}">${esc(p.name||'Sem nome')}</option>`).join('');
  $('compare-a').innerHTML=`<option value="">Selecione…</option>${options}`;
  $('compare-b').innerHTML=`<option value="">Selecione…</option>${options}`;
}
function headToHead(playerA,playerB,tournaments){
  let matchesTogether=0,matchesAgainst=0;
  for(const t of tournaments){
    const teamOf=(id)=>(t.teams??[]).find((team)=>team.id===id);
    for(const m of t.matches??[]){
      if(m.status!==2)continue;
      const home=teamOf(m.homeTeamId),away=teamOf(m.awayTeamId);
      const aHome=home?.playerIds?.includes(playerA.id),aAway=away?.playerIds?.includes(playerA.id);
      const bHome=home?.playerIds?.includes(playerB.id),bAway=away?.playerIds?.includes(playerB.id);
      if(!(aHome||aAway)||!(bHome||bAway))continue;
      if((aHome&&bHome)||(aAway&&bAway))matchesTogether++;else matchesAgainst++;
    }
  }
  return {matchesTogether,matchesAgainst};
}
function renderCompare(){
  const idA=$('compare-a').value,idB=$('compare-b').value,host=$('compare-result');
  if(!idA||!idB){host.innerHTML='';return}
  if(idA===idB){host.innerHTML='<div class="msg">Escolha dois jogadores diferentes.</div>';return}
  const players=currentData.players??[],tournaments=currentData.tournaments??[];
  const a=players.find((p)=>p.id===idA),b=players.find((p)=>p.id===idB);
  if(!a||!b)return;
  const historyA=playerHistory(a,tournaments),historyB=playerHistory(b,tournaments);
  const h2h=headToHead(a,b,tournaments);
  const row=(label,va,vb)=>`<tr><td class="cmp-val cmp-a">${va}</td><td class="cmp-label">${label}</td><td class="cmp-val cmp-b">${vb}</td></tr>`;
  host.innerHTML=`<div class="compare-heads"><span>${esc(a.name||'Sem nome')}</span><span class="compare-vs">×</span><span>${esc(b.name||'Sem nome')}</span></div>
    <table class="compare-table"><tbody>
      ${row('Gols',fmtNumber.format(Number(a.goals??0)),fmtNumber.format(Number(b.goals??0)))}
      ${row('Títulos',fmtNumber.format(Number(a.titles??0)),fmtNumber.format(Number(b.titles??0)))}
      ${row('Torneios',historyA.length,historyB.length)}
    </tbody></table>
    <p class="compare-h2h">${h2h.matchesTogether||h2h.matchesAgainst?`Jogaram juntos em ${plural(h2h.matchesTogether,'partida','partidas')} e um contra o outro em ${plural(h2h.matchesAgainst,'partida','partidas')}.`:'Nunca jogaram juntos nem um contra o outro nas partidas sincronizadas.'}</p>`;
}
$('compare-a').addEventListener('change',renderCompare);
$('compare-b').addEventListener('change',renderCompare);

function standings(tournament){
  const rows=new Map((tournament.teams??[]).map((team)=>[team.id,{team,p:0,w:0,d:0,l:0,gf:0,ga:0,pts:0}]));
  for(const match of tournament.matches??[]){if(match.phase!==0||match.status!==2||!rows.has(match.homeTeamId)||!rows.has(match.awayTeamId))continue;const home=rows.get(match.homeTeamId),away=rows.get(match.awayTeamId),hs=Number(match.homeScore??0),as=Number(match.awayScore??0);home.p++;away.p++;home.gf+=hs;home.ga+=as;away.gf+=as;away.ga+=hs;if(hs>as){home.w++;away.l++;home.pts+=3}else if(as>hs){away.w++;home.l++;away.pts+=3}else{home.d++;away.d++;home.pts++;away.pts++}}
  return [...rows.values()].filter((row)=>row.p>0).sort((a,b)=>b.pts-a.pts||(b.gf-b.ga)-(a.gf-a.ga)||b.gf-a.gf||a.team.name.localeCompare(b.team.name,'pt-BR'));
}
function renderStandings(tournament){const rows=standings(tournament);if(!rows.length)return'';return `<p class="subhead">Classificação da fase de grupos</p><div class="table-scroll"><table class="standing"><thead><tr><th>#</th><th>Time</th><th>P</th><th>J</th><th>V</th><th>E</th><th>D</th><th>GP</th><th>GC</th><th>SG</th></tr></thead><tbody>${rows.map((r,i)=>`<tr><td>${i+1}</td><td class="team-cell"><span class="dot" style="display:inline-block;background:${colorOf(r.team)}"></span> ${esc(r.team.name)}</td><td class="pts">${r.pts}</td><td>${r.p}</td><td>${r.w}</td><td>${r.d}</td><td>${r.l}</td><td>${r.gf}</td><td>${r.ga}</td><td>${r.gf-r.ga}</td></tr>`).join('')}</tbody></table></div>`}

function scorerText(events,teamId,players){
  const byPlayer=new Map();
  for(const goal of events??[]){
    if(goal.teamId!==teamId)continue;
    const player=players.get(goal.playerId);
    const entry=byPlayer.get(goal.playerId)??{name:player?.name||'Jogador',minutes:[]};
    entry.minutes.push(typeof goal.minute==='number'?goal.minute:null);
    byPlayer.set(goal.playerId,entry);
  }
  return [...byPlayer].map(([id,item])=>{
    const known=item.minutes.filter((m)=>m!=null).sort((a,b)=>a-b);
    const label=known.length&&known.length===item.minutes.length
      ?` ${known.map((m)=>`${m}'`).join(', ')}`
      :item.minutes.length>1?` (${item.minutes.length})`:'';
    return `${playerLink(id,item.name)}${label}`;
  }).join(', ');
}
function renderMatch(match,tournament,players){
  const team=(id)=>(tournament.teams??[]).find((item)=>item.id===id);const home=team(match.homeTeamId),away=team(match.awayTeamId);const played=match.status!==0&&match.homeScore!=null&&match.awayScore!=null;const status=['A jogar','Em andamento','Encerrado'][match.status]??'—';const phaseInfo=match.tieId?`${match.leg===2?'volta':'ida'}`:`jogo ${Number(match.scheduledOrder??0)+1}`;const homeGoals=scorerText(match.scorers,match.homeTeamId,players),awayGoals=scorerText(match.scorers,match.awayTeamId,players);const goals=[homeGoals?`<span><b>${esc(home?.name||'Time')}:</b> ${homeGoals}</span>`:'',awayGoals?`<span><b>${esc(away?.name||'Time')}:</b> ${awayGoals}</span>`:''].filter(Boolean).join(' · ');const penalty=match.penaltyWinnerId?`<span class="penalty">${esc(team(match.penaltyWinnerId)?.name||'Time')} venceu nos pênaltis</span>`:'';
  return `<div class="match"><span class="match-info">${phaseInfo}</span><span class="team-home">${esc(home?.name||'A definir')}</span><span class="score">${played?`${Number(match.homeScore??0)} × ${Number(match.awayScore??0)}`:'×'}</span><span class="team-away">${esc(away?.name||'A definir')}</span><span class="match-status ${match.status===1?'live':match.status===2?'done':''}">${status}</span>${goals||penalty?`<div class="match-extra">${goals}${goals&&penalty?' · ':''}${penalty}</div>`:''}</div>`;
}
function renderMatches(tournament,players){const phases=[[0,'Fase de grupos'],[1,'Mata-mata'],[3,'Semifinais'],[2,'Final']];return phases.map(([id,label])=>{const matches=(tournament.matches??[]).filter((m)=>m.phase===id).sort((a,b)=>Number(a.scheduledOrder??0)-Number(b.scheduledOrder??0)||Number(a.leg??1)-Number(b.leg??1));return matches.length?`<section class="phase"><h3 class="phase-title">${label}</h3>${matches.map((m)=>renderMatch(m,tournament,players)).join('')}</section>`:''}).join('')}
function renderSquads(tournament,players){const teams=tournament.teams??[];if(!teams.length)return'';return `<p class="subhead">Times e jogadores</p><div class="squads">${teams.map((team)=>{const roster=(team.playerIds??[]).map((id)=>players.has(id)?playerLink(id,players.get(id).name||'Sem nome'):'').filter(Boolean);return `<div class="squad"><div class="squad-title"><span class="dot" style="background:${colorOf(team)}"></span>${esc(team.name)}</div><p>${roster.length?roster.join(', '):'Elenco não informado'}</p></div>`}).join('')}</div>`}
function renderTournament(tournament,index,isLatest,players){const teams=tournament.teams??[],matches=tournament.matches??[],champ=teams.find((team)=>team.id===tournament.championTeamId);const finished=matches.filter((m)=>m.status===2);const goals=finished.reduce((sum,m)=>sum+Number(m.homeScore??0)+Number(m.awayScore??0),0);const champMarkup=champ?`<span class="champ"><span class="dot" style="background:${colorOf(champ)}"></span><span class="tag">CAMPEÃO</span><span class="champ-name">${esc(champ.name)}</span></span>`:'<span class="nochamp">sem campeão</span>';
  const live=Number(tournament.status)===0;
  return `<details class="tourney${live?' is-live':''}" id="tournament-${esc(tournament.id)}"><summary><span class="date">${fmtDate(tournament.createdAt)}</span>${champMarkup}<span class="meta">${plural(teams.length,'time','times')} · ${finished.length}/${matches.length} jogos${tournament.twoLegged?' · ida e volta':''}</span><span class="chevron" aria-hidden="true">⌄</span></summary><div class="tourney-body"><div class="tourney-stats"><div class="tourney-stat"><strong>${teams.length}</strong><span>Times</span></div><div class="tourney-stat"><strong>${finished.length}</strong><span>Jogos</span></div><div class="tourney-stat"><strong>${goals}</strong><span>Gols</span></div></div>${renderStandings(tournament)}<p class="subhead">Jogo a jogo</p>${renderMatches(tournament,players)||'<div class="msg">Nenhuma partida registrada.</div>'}${renderSquads(tournament,players)}</div></details>`}

function positionOf(players,player,key){const index=ranking(players,key).findIndex((row)=>row.id===player.id);return index<0?'—':`${index+1}º`}
function playerHistory(player,tournaments){return tournaments.map((tournament)=>{const teams=(tournament.teams??[]).filter((team)=>(team.playerIds??[]).includes(player.id));if(!teams.length)return null;const teamIds=new Set(teams.map((team)=>team.id));const matches=(tournament.matches??[]).filter((match)=>match.status===2&&(teamIds.has(match.homeTeamId)||teamIds.has(match.awayTeamId)));const goals=(tournament.matches??[]).reduce((sum,match)=>sum+(match.scorers??[]).filter((goal)=>goal.playerId===player.id).length,0);return{tournament,teams,matches,goals,champion:teams.some((team)=>team.id===tournament.championTeamId)}}).filter(Boolean).sort((a,b)=>Number(b.tournament.createdAt??0)-Number(a.tournament.createdAt??0))}
function scoredMatches(player,history){const rows=[];for(const item of history){for(const match of item.tournament.matches??[]){const playerGoals=(match.scorers??[]).filter((goal)=>goal.playerId===player.id);if(!playerGoals.length)continue;const minutes=playerGoals.map((goal)=>typeof goal.minute==='number'?goal.minute:null).filter((m)=>m!=null).sort((a,b)=>a-b);const team=(id)=>(item.tournament.teams??[]).find((value)=>value.id===id);rows.push({date:item.tournament.createdAt,phase:phaseName[match.phase]??'Partida',home:team(match.homeTeamId)?.name||'A definir',away:team(match.awayTeamId)?.name||'A definir',homeScore:match.homeScore,awayScore:match.awayScore,goals:playerGoals.length,minutes:minutes.length===playerGoals.length?minutes:[]})}}return rows.sort((a,b)=>Number(b.date??0)-Number(a.date??0))}
let activeProfilePlayerId=null;
function openPlayerProfile(playerId){
  const players=currentData.players??[],player=players.find((item)=>item.id===playerId);if(!player)return;
  activeProfilePlayerId=playerId;
  const history=playerHistory(player,currentData.tournaments??[]),matches=history.reduce((sum,item)=>sum+item.matches.length,0),historicGoals=history.reduce((sum,item)=>sum+item.goals,0),scored=scoredMatches(player,history);
  $('player-profile').innerHTML=`<div class="profile-head"><div><p class="eyebrow">Perfil do jogador</p><h2 class="profile-title" id="player-profile-name">${esc(player.name||'Sem nome')}</h2></div><button type="button" class="dialog-close" aria-label="Fechar perfil">×</button></div><div class="profile-stats"><div class="profile-stat"><strong>${fmtNumber.format(Number(player.goals??0))}</strong><span>Gols gerais</span></div><div class="profile-stat"><strong>${fmtNumber.format(Number(player.titles??0))}</strong><span>Títulos</span></div><div class="profile-stat"><strong>${history.length}</strong><span>Torneios</span></div><div class="profile-stat"><strong>${matches}</strong><span>Partidas</span></div></div><div class="rank-positions"><span>Artilharia: <strong>${positionOf(players,player,'goals')}</strong></span><span>Títulos: <strong>${positionOf(players,player,'titles')}</strong></span></div><button type="button" class="share-btn" id="download-card">Baixar cartão</button><p class="subhead">Histórico por torneio</p>${history.length?`<div class="profile-list">${history.map((item)=>`<div class="profile-row"><time>${fmtDate(item.tournament.createdAt)}</time><span class="profile-team">${item.teams.map((team)=>esc(team.name)).join(', ')}${item.champion?'<span class="profile-badge">campeão</span>':''}</span><span class="profile-numbers"><strong>${plural(item.goals,'gol','gols')}</strong><br><small>${plural(item.matches.length,'jogo','jogos')}</small></span></div>`).join('')}</div>`:'<div class="profile-empty">Nenhuma participação encontrada no histórico.</div>'}<p class="subhead">Partidas em que marcou</p>${scored.length?`<div class="profile-list">${scored.map((match)=>`<div class="scored-match"><div class="scored-match-main"><span>${esc(match.home)} ${Number(match.homeScore??0)} × ${Number(match.awayScore??0)} ${esc(match.away)}</span><span class="scored-match-goals">${match.minutes.length?match.minutes.map((m)=>`${m}'`).join(', '):plural(match.goals,'gol','gols')}</span></div><div class="scored-match-meta">${fmtDate(match.date)} · ${match.phase}</div></div>`).join('')}</div>`:`<div class="profile-empty">Nenhum gol identificado nas partidas sincronizadas.${Number(player.goals??0)>historicGoals?' O total geral inclui registros anteriores ao histórico disponível.':''}</div>`}`;
  const dialog=$('player-dialog');dialog.querySelector('.dialog-close').addEventListener('click',()=>dialog.close());if(!dialog.open)dialog.showModal();
}

// ── Cartão pra compartilhar ──────────────────────────────────────────────
function wrapCanvasText(ctx,text,x,y,maxWidth,lineHeight){
  const words=text.split(' ');let line='';const lines=[];
  for(const word of words){const test=line?`${line} ${word}`:word;if(line&&ctx.measureText(test).width>maxWidth){lines.push(line);line=word}else line=test}
  if(line)lines.push(line);
  lines.forEach((l,i)=>ctx.fillText(l,x,y+i*lineHeight));
  return lines.length;
}
function buildPlayerCardCanvas(player,history,matches){
  const canvas=document.createElement('canvas');canvas.width=1080;canvas.height=1350;
  const ctx=canvas.getContext('2d');
  ctx.fillStyle='#071410';ctx.fillRect(0,0,canvas.width,canvas.height);
  ctx.strokeStyle='#24463a';ctx.lineWidth=3;ctx.beginPath();ctx.arc(540,-60,460,0,Math.PI*2);ctx.stroke();
  ctx.fillStyle='#7b9488';ctx.font='700 26px "Barlow Semi Condensed",Arial';ctx.fillText('RACHA DOS RUINS · PERFIL', 64, 110);
  ctx.fillStyle='#eaf2ec';ctx.font='400 88px Anton,Arial';
  const nameLines=wrapCanvasText(ctx,(player.name||'Sem nome').toUpperCase(),64,240,950,92);
  const statsTop=240+nameLines*92+70;
  const stats=[[fmtNumber.format(Number(player.goals??0)),'GOLS'],[fmtNumber.format(Number(player.titles??0)),'TÍTULOS'],[String(history.length),'TORNEIOS'],[String(matches),'PARTIDAS']];
  const boxW=(canvas.width-128)/2,boxH=170;
  stats.forEach(([value,label],i)=>{
    const col=i%2,rowIdx=Math.floor(i/2);
    const x=64+col*(boxW+0),y=statsTop+rowIdx*(boxH+18);
    ctx.strokeStyle='#24463a';ctx.lineWidth=1;ctx.strokeRect(x,y,boxW-16,boxH);
    ctx.fillStyle='#ffc531';ctx.font='400 72px Anton,Arial';ctx.fillText(value,x+22,y+96);
    ctx.fillStyle='#7b9488';ctx.font='700 20px "Barlow Semi Condensed",Arial';ctx.fillText(label,x+22,y+134);
  });
  ctx.fillStyle='#7b9488';ctx.font='500 22px "Barlow Semi Condensed",Arial';
  ctx.fillText(`Gerado em ${fmtDate(Date.now())}`,64,canvas.height-64);
  return canvas;
}
async function downloadPlayerCard(playerId){
  const player=(currentData.players??[]).find((item)=>item.id===playerId);if(!player)return;
  const button=$('download-card');if(button){button.disabled=true;button.textContent='Gerando…'}
  try{
    if(document.fonts?.ready)await document.fonts.ready;
    const history=playerHistory(player,currentData.tournaments??[]);
    const matches=history.reduce((sum,item)=>sum+item.matches.length,0);
    const canvas=buildPlayerCardCanvas(player,history,matches);
    canvas.toBlob((blob)=>{
      if(!blob)return;
      const url=URL.createObjectURL(blob);
      const a=document.createElement('a');
      a.href=url;a.download=`${(player.name||'jogador').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g,'').replace(/[^a-z0-9]+/g,'-').replace(/^-+|-+$/g,'')||'jogador'}-racha-dos-ruins.png`;
      document.body.appendChild(a);a.click();a.remove();
      setTimeout(()=>URL.revokeObjectURL(url),4000);
    });
  }finally{
    if(button){button.disabled=false;button.textContent='Baixar cartão'}
  }
}

document.addEventListener('click',(event)=>{const trigger=event.target.closest?.('[data-player-id]');if(trigger)openPlayerProfile(trigger.dataset.playerId)});
$('player-dialog').addEventListener('click',(event)=>{
  if(event.target===event.currentTarget){event.currentTarget.close();return}
  if(event.target.id==='download-card'&&activeProfilePlayerId)downloadPlayerCard(activeProfilePlayerId);
});

function render(data){const players=Array.isArray(data.players)?data.players:[],playerMap=new Map(players.map((p)=>[p.id,p]));const tournaments=(Array.isArray(data.tournaments)?data.tournaments:[]).slice().sort((a,b)=>Number(b.createdAt??0)-Number(a.createdAt??0));currentData={players,tournaments};const totalGoals=players.reduce((sum,p)=>sum+Number(p.goals??0),0),finishedMatches=tournaments.reduce((sum,t)=>sum+(t.matches??[]).filter((m)=>m.status===2).length,0);
    const matchGoals=allFinishedMatches(tournaments).reduce((sum,{m})=>sum+Number(m.homeScore??0)+Number(m.awayScore??0),0);
    const avgGoals=finishedMatches?(matchGoals/finishedMatches).toLocaleString('pt-BR',{minimumFractionDigits:1,maximumFractionDigits:1}):'—';
    $('totals').innerHTML=[[fmtNumber.format(tournaments.length),'Torneios'],[fmtNumber.format(players.length),'Jogadores'],[fmtNumber.format(totalGoals),'Gols'],[fmtNumber.format(finishedMatches),'Partidas'],[avgGoals,'Gols/partida']].map(([n,label])=>`<div><span class="n">${n}</span><span class="l">${label}</span></div>`).join('');renderLiveBanner(tournaments);renderRecords(players,tournaments);renderTeamOfWeek(tournaments,playerMap);renderRank($('scorers'),ranking(players,'goals',12),'var(--lamp)','gol','gols');renderRank($('titles'),ranking(players,'titles',12),'var(--paint)','título','títulos');populateCompareSelects(players);renderCompare();$('tourneys').innerHTML=tournaments.length?tournaments.map((t,i)=>renderTournament(t,i,i===0,playerMap)).join(''):'<div class="msg">Nenhum torneio registrado ainda.</div>';$('updated').textContent=data.updatedAt?`Atualizado em ${fmtDate(data.updatedAt)}`:'Sem data de atualização';$('loading').classList.add('hidden');$('content').classList.remove('hidden')}
async function main(){if(!firebaseConfig.apiKey||firebaseConfig.apiKey==='COLE_AQUI'){showError('Configuração do Firebase não preenchida.','Registre um app Web no console e copie os valores para painel/firebase-config.js');return}const url=`https://firestore.googleapis.com/v1/projects/${firebaseConfig.projectId}/databases/(default)/documents/racha/public?key=${firebaseConfig.apiKey}`;try{const res=await fetch(url);if(res.status===404){showError('Nenhum dado na nuvem ainda.','Use “Enviar agora” nas Configurações do app.');return}if(res.status===403){showError('Sem permissão para ler os dados.','Confirme a leitura pública do documento /racha/public.');return}if(!res.ok){showError('Falha ao carregar.',`HTTP ${res.status}`);return}const body=await res.json();render(decodeFields(body.fields??{}))}catch(error){showError('Falha ao carregar.',String(error))}}
main();
