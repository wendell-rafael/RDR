// Teste de corrida do check-in, contra os emuladores.
//
// Os testes de `functions/test` cobrem as contas puras — semana, janela, corte
// da fila. O que eles não conseguem tocar é justamente o motivo de todo o
// desenho existir: o que acontece quando muita gente aperta o botão no mesmo
// instante. Isso só aparece com escritas concorrentes de verdade, e é o que
// este script faz.
//
// Uso:
//   1. ./tool/dev_emulators.sh        (em outro terminal)
//   2. node tool/race_test.mjs
//
// Nada aqui toca a nuvem: tudo fala com 127.0.0.1.

import { resolveEvent } from '../functions/lib/events.js';

const PROJECT = 'racha-dos-ruins';
const AUTH = 'http://127.0.0.1:9099';
const FUNCS = 'http://127.0.0.1:5001';
const STORE = 'http://127.0.0.1:8080';
const REGION = 'southamerica-east1';
const DOCS = `${STORE}/v1/projects/${PROJECT}/databases/(default)/documents`;

const ok = (label) => console.log(`  ok   ${label}`);
const bad = (label, detail) => {
  console.error(`  FALHOU ${label}${detail ? `\n         ${detail}` : ''}`);
  process.exitCode = 1;
};

function check(condition, label, detail) {
  if (condition) ok(label);
  else bad(label, detail);
}

// ── Emulador ─────────────────────────────────────────────────────────────

/**
 * Login Google falso.
 *
 * O emulador aceita um `id_token` montado à mão em `signInWithIdp`, e é assim
 * que se consegue um token com `sign_in_provider = google.com` sem passar pelo
 * Google. A função de check-in recusa qualquer outro provedor, então sem isso
 * não dava pra testar o caminho real.
 */
async function signInAsGoogle(sub, email) {
  const postBody = new URLSearchParams({
    id_token: JSON.stringify({ sub, email, email_verified: true, name: email.split('@')[0] }),
    providerId: 'google.com',
  }).toString();

  const response = await fetch(
    `${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=fake-api-key`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        postBody,
        requestUri: 'http://localhost',
        returnIdpCredential: true,
        returnSecureToken: true,
      }),
    },
  );
  const data = await response.json();
  if (!data.idToken) throw new Error(`login falhou: ${JSON.stringify(data)}`);
  return { idToken: data.idToken, uid: data.localId };
}

async function callFunction(name, idToken, payload) {
  const headers = { 'Content-Type': 'application/json' };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(`${FUNCS}/${PROJECT}/${REGION}/${name}`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ data: payload }),
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok || body.error) {
    const error = new Error(body.error?.message ?? `HTTP ${response.status}`);
    error.status = body.error?.status ?? String(response.status);
    throw error;
  }
  return body.result;
}

const asOwner = { Authorization: 'Bearer owner' };

async function forceOpen(eventId) {
  const response = await fetch(
    `${DOCS}/checkin_events/${eventId}?updateMask.fieldPaths=status`,
    {
      method: 'PATCH',
      headers: { ...asOwner, 'Content-Type': 'application/json' },
      body: JSON.stringify({ fields: { status: { stringValue: 'open' } } }),
    },
  );
  if (!response.ok) throw new Error(`não consegui abrir o evento: ${await response.text()}`);
}

/**
 * Lê a fila com a mesma consulta que a página faz: ordem por `createdAt` e
 * desempate por id. Ordenar do lado de cá daria uma resposta que o app não
 * necessariamente veria — e é exatamente a ordem que o app vê que importa.
 */
async function listEntries(eventId) {
  const response = await fetch(`${DOCS}/checkin_events/${eventId}:runQuery`, {
    method: 'POST',
    headers: { ...asOwner, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      structuredQuery: {
        from: [{ collectionId: 'entries' }],
        orderBy: [
          { field: { fieldPath: 'createdAt' }, direction: 'ASCENDING' },
          { field: { fieldPath: '__name__' }, direction: 'ASCENDING' },
        ],
        limit: 300,
      },
    }),
  });
  const body = await response.json();
  return (body ?? [])
    .filter((row) => row.document)
    .map(({ document }) => ({
      id: document.name.split('/').pop(),
      name: document.fields?.name?.stringValue ?? '',
      role: document.fields?.role?.stringValue ?? 'player',
      createdAt: document.fields?.createdAt?.timestampValue ?? null,
    }));
}

async function wipeEntries(eventId) {
  const entries = await listEntries(eventId);
  await Promise.all(entries.map((entry) => fetch(
    `${DOCS}/checkin_events/${eventId}/entries/${entry.id}`,
    { method: 'DELETE', headers: asOwner },
  )));
}

/** Zera os contadores de limite pra um teste não estourar a cota do seguinte. */
async function wipeLimits() {
  for (const collection of ['checkin_rate', 'checkin_ip']) {
    const response = await fetch(`${DOCS}/${collection}?pageSize=300`, { headers: asOwner });
    const body = await response.json();
    await Promise.all((body.documents ?? []).map((document) => fetch(
      `${STORE}/v1/${document.name}`,
      { method: 'DELETE', headers: asOwner },
    )));
  }
}

// ── Cenários ─────────────────────────────────────────────────────────────

/**
 * Trinta pessoas apertando o botão ao mesmo tempo.
 *
 * O que se verifica não é "todo mundo entrou" — é que a fila resultante é uma
 * ordem total, sem empate e sem duplicata. Um empate de `createdAt` significaria
 * duas pessoas na mesma posição, e aí a página e o painel poderiam desempatar
 * diferente, mostrando listas que não batem.
 */
async function testeEnxurrada(eventId) {
  console.log('\n30 inscrições simultâneas');
  await wipeEntries(eventId);
  await wipeLimits();

  const pessoas = await Promise.all(
    Array.from({ length: 30 }, (_, index) => signInAsGoogle(`corrida-${index}`, `corrida${index}@exemplo.com`)),
  );

  const resultados = await Promise.allSettled(pessoas.map((pessoa, index) => callFunction(
    'checkin',
    pessoa.idToken,
    { name: `Jogador ${index + 1}`, role: index % 10 === 0 ? 'keeper' : 'player' },
  )));

  const aceitos = resultados.filter((r) => r.status === 'fulfilled').length;
  const barrados = resultados.filter((r) => r.status === 'rejected');
  const porLimite = barrados.filter((r) => r.reason.status === 'RESOURCE_EXHAUSTED').length;
  console.log(`       ${aceitos} aceitos, ${barrados.length} recusados (${porLimite} por limite de carga)`);

  // Sem este piso, todo o resto do cenário passaria com a lista vazia — foi
  // exatamente o que escondeu o App Check barrando tudo na primeira execução.
  check(aceitos >= 20,
    'a maioria das chamadas foi aceita',
    `só ${aceitos} de 30 passaram — o resto do cenário não vale nada assim`);

  const entries = await listEntries(eventId);
  check(entries.length === aceitos,
    'cada chamada aceita virou exatamente um documento',
    `aceitos=${aceitos} documentos=${entries.length}`);

  const uids = new Set(entries.map((entry) => entry.id));
  check(uids.size === entries.length, 'nenhuma inscrição duplicada');

  const carimbos = entries.map((entry) => entry.createdAt);
  const semNulo = carimbos.every(Boolean);
  check(semNulo, 'toda inscrição recebeu carimbo do servidor');

  // Empate de milissegundo acontece de verdade sob carga: medido, 30 gravações
  // simultâneas caíram em 25 instantes distintos. A garantia que sustenta a
  // fila não é "carimbos únicos", é "ordem única": entre dois empatados não
  // existe quem chegou primeiro, mas todo leitor precisa ver a mesma sequência.
  const unicos = new Set(carimbos);
  const empates = carimbos.length - unicos.size;
  console.log(`       ${empates} empate(s) de milissegundo entre ${carimbos.length} inscrições`);

  const naoDecresce = carimbos.every((valor, i) => i === 0 || carimbos[i - 1] <= valor);
  check(naoDecresce, 'a fila sai em ordem de chegada, sem retroceder');

  // A prova de que o desempate é determinístico: duas leituras independentes
  // da mesma consulta têm que devolver exatamente a mesma sequência.
  const outraLeitura = await listEntries(eventId);
  check(outraLeitura.map((e) => e.id).join(',') === entries.map((e) => e.id).join(','),
    'duas leituras da fila devolvem a mesma ordem, mesmo com empate',
    'a ordem mudou entre leituras — o desempate não é determinístico');

  const goleiros = entries.filter((entry) => entry.role === 'keeper');
  check(goleiros.length > 0 && goleiros.length < entries.length,
    'as duas funções foram gravadas na mesma fila de documentos',
    `goleiros=${goleiros.length} de ${entries.length}`);

  const nomes = new Set(entries.map((entry) => entry.name));
  check(nomes.size === entries.length, 'cada documento guardou o nome de quem o criou');
}

/**
 * A mesma pessoa martelando o botão.
 *
 * É o caso que um contador ingênuo erraria: vinte chamadas ao mesmo tempo, uma
 * vaga só. A transação toca só o documento daquele uid, então a segunda em
 * diante encontra o documento já criado e não duplica nem reposiciona.
 */
async function testeMesmaPessoa(eventId) {
  console.log('\n20 cliques simultâneos da mesma conta');
  await wipeEntries(eventId);
  await wipeLimits();

  const pessoa = await signInAsGoogle('teimoso', 'teimoso@exemplo.com');
  const resultados = await Promise.allSettled(
    Array.from({ length: 20 }, () => callFunction('checkin', pessoa.idToken, { name: 'Teimoso', role: 'player' })),
  );
  const aceitos = resultados.filter((r) => r.status === 'fulfilled').length;
  const limitados = resultados.filter(
    (r) => r.status === 'rejected' && r.reason.status === 'RESOURCE_EXHAUSTED',
  ).length;
  console.log(`       ${aceitos} aceitos, ${limitados} barrados pelo limite por conta`);
  check(aceitos > 0, 'alguma chamada passou', 'todas falharam — o cenário não testou nada');

  const entries = await listEntries(eventId);
  check(entries.length === 1,
    'vinte cliques simultâneos geraram uma vaga só',
    `documentos=${entries.length}`);
  check(limitados > 0,
    'o limite por conta entrou em ação',
    'nenhuma chamada foi barrada — o teto de 12 por hora não pegou');
}

/**
 * Trocar de função recomeça a fila.
 *
 * Sem isso, o primeiro da linha viraria o primeiro goleiro na hora, passando na
 * frente de quem pediu o gol antes.
 */
async function testeTrocaDeFuncao(eventId) {
  console.log('\nTroca de linha para gol');
  await wipeEntries(eventId);
  await wipeLimits();

  const cedo = await signInAsGoogle('cedo', 'cedo@exemplo.com');
  const tarde = await signInAsGoogle('tarde', 'tarde@exemplo.com');

  await callFunction('checkin', tarde.idToken, { name: 'Trocador', role: 'player' });
  await callFunction('checkin', cedo.idToken, { name: 'Goleiro Cedo', role: 'keeper' });
  const troca = await callFunction('checkin', tarde.idToken, { name: 'Trocador', role: 'keeper' });

  check(troca.result === 'trocou-de-funcao', 'a troca foi reconhecida como troca',
    `resultado=${troca.result}`);

  const goleiros = (await listEntries(eventId)).filter((entry) => entry.role === 'keeper');
  check(goleiros.length === 2, 'os dois estão na fila do gol');
  check(goleiros[0]?.name === 'Goleiro Cedo',
    'quem pediu o gol antes continua na frente de quem trocou depois',
    `primeiro=${goleiros[0]?.name}`);
}

/** Cancelar libera a vaga e faz a espera subir sem nada ser regravado. */
async function testeCancelamento(eventId) {
  console.log('\nCancelamento faz a fila andar');
  await wipeEntries(eventId);
  await wipeLimits();

  const pessoas = [];
  for (let index = 0; index < 4; index += 1) {
    const pessoa = await signInAsGoogle(`fila-${index}`, `fila${index}@exemplo.com`);
    await callFunction('checkin', pessoa.idToken, { name: `Fila ${index + 1}`, role: 'player' });
    pessoas.push(pessoa);
  }

  const antes = (await listEntries(eventId)).map((entry) => entry.name);
  await callFunction('cancelCheckin', pessoas[1].idToken, {});
  const depois = await listEntries(eventId);

  check(depois.length === 3, 'a vaga foi liberada');
  check(depois.map((entry) => entry.name).join(',') === 'Fila 1,Fila 3,Fila 4',
    'quem estava atrás subiu sem nenhuma regravação',
    `antes=[${antes}] depois=[${depois.map((e) => e.name)}]`);

  const carimbos = depois.map((entry) => entry.createdAt);
  check(carimbos.every((valor, i) => i === 0 || carimbos[i - 1] < valor),
    'os carimbos de quem ficou não mudaram de ordem');
}

/** Entrada malformada é recusada, não corrigida por conta própria. */
async function testeEntradaInvalida(eventId) {
  console.log('\nEntradas inválidas');
  await wipeEntries(eventId);
  await wipeLimits();

  const pessoa = await signInAsGoogle('invalido', 'invalido@exemplo.com');

  for (const [rotulo, payload] of [
    ['função inexistente', { name: 'Fulano', role: 'zagueiro' }],
    ['nome curto demais', { name: 'a', role: 'player' }],
    ['nome só de espaço', { name: '   ', role: 'player' }],
  ]) {
    try {
      await callFunction('checkin', pessoa.idToken, payload);
      bad(`${rotulo} foi aceita`, 'deveria ter sido recusada');
    } catch (error) {
      check(error.status === 'INVALID_ARGUMENT', `${rotulo} recusada`, `status=${error.status}`);
    }
  }

  check((await listEntries(eventId)).length === 0, 'nenhuma entrada inválida virou documento');
}

/**
 * Sem login não passa, mesmo com o resto todo certo.
 *
 * O código exato varia: token forjado volta como PERMISSION_DENIED, cabeçalho
 * ausente como UNAUTHENTICATED. O que precisa ser verdade é só que a chamada
 * não entrou — qual dos dois é detalhe de implementação do Firebase.
 */
const RECUSADO = ['UNAUTHENTICATED', 'PERMISSION_DENIED', 'INVALID_ARGUMENT', '401', '403'];

async function testeSemLogin(eventId) {
  console.log('\nChamadas sem login válido');
  await wipeEntries(eventId);

  for (const [rotulo, token] of [
    ['token forjado', 'token-invalido'],
    ['sem cabeçalho de autorização', null],
  ]) {
    try {
      await callFunction('checkin', token, { name: 'Anônimo', role: 'player' });
      bad(`${rotulo} foi aceito`, 'deveria ter sido recusado');
    } catch (error) {
      check(RECUSADO.includes(error.status), `${rotulo} recusado`, `status=${error.status}`);
    }
  }

  check((await listEntries(eventId)).length === 0, 'nenhuma chamada sem login virou documento');
}

// ── Execução ─────────────────────────────────────────────────────────────

async function main() {
  const resolved = resolveEvent(new Date(), null);
  const eventId = resolved.eventId;
  console.log(`Racha do teste: ${eventId} (jogo ${resolved.matchAt.toISOString()})`);

  const semente = await signInAsGoogle('semente', 'semente@exemplo.com');
  // A primeira chamada cria o documento do evento mesmo sendo recusada pela
  // janela — `ensureEvent` roda antes da conferência do horário.
  await callFunction('checkin', semente.idToken, { name: 'Semente', role: 'player' }).catch(() => {});
  await forceOpen(eventId);
  console.log('Janela forçada como aberta para o teste.\n');

  await testeEnxurrada(eventId);
  await testeMesmaPessoa(eventId);
  await testeTrocaDeFuncao(eventId);
  await testeCancelamento(eventId);
  await testeEntradaInvalida(eventId);
  await testeSemLogin(eventId);

  await wipeEntries(eventId);
  console.log(process.exitCode ? '\nFALHOU' : '\nTudo certo.');
}

main().catch((error) => {
  console.error('\nErro ao rodar o teste:', error.message);
  console.error('Os emuladores estão de pé? Rode ./tool/dev_emulators.sh em outro terminal.');
  process.exit(1);
});
