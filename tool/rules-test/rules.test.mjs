// Testes das regras do Firestore, contra o emulador (nada toca a nuvem).
// Rode com tool/test_rules.sh.
//
// A ideia é testar do ponto de vista de quem ataca: o que um visitante, uma
// conta qualquer do Google, um escritor do racha e um escritor da Copa
// conseguem (ou não) ler e gravar.

import { after, before, beforeEach, describe, test } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection, deleteDoc, doc, getDoc, getDocs, serverTimestamp, setDoc, updateDoc,
} from 'firebase/firestore';

const RULES = readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8');
// Payload exatamente como o app da Copa o serializa (times fictícios).
const APP = JSON.parse(readFileSync(new URL('./fixtures/copa-app-payload.json', import.meta.url), 'utf8'));
// Payload como o app do vôlei serializa (gerado pelo próprio app).
const VOLEI = JSON.parse(readFileSync(new URL('./fixtures/volei-app-payload.json', import.meta.url), 'utf8'));

let env;

before(async () => {
  env = await initializeTestEnvironment({ projectId: 'demo-rdr', firestore: { rules: RULES } });
});
after(async () => { await env.cleanup(); });

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'rdr_writers', 'racha@x.com'), {});
    await setDoc(doc(db, 'rdr_writers', 'mesa@x.com'), {});
    await setDoc(doc(db, 'copa_writers', 'mesa@x.com'), {});
    await setDoc(doc(db, 'volei_writers', 'volei@x.com'), {});
  });
});

const google = (email, uid, extra = {}) => env.authenticatedContext(uid, {
  email, email_verified: true, firebase: { sign_in_provider: 'google.com' }, ...extra,
});
const anon = () => env.unauthenticatedContext();
const mesa = () => google('mesa@x.com', 'uid-mesa');         // escritor da Copa
const racha = () => google('racha@x.com', 'uid-racha');      // só escritor do racha
const stranger = () => google('qualquer@gmail.com', 'uid-x'); // Google, sem lista nenhuma

const copaPayload = (uid, revision, patch = {}, copaPatch = {}, derivedPatch = {}) => ({
  updatedAt: serverTimestamp(),
  updatedBy: uid,
  revision,
  copa: { ...structuredClone(APP.copa), ...copaPatch },
  derived: { ...structuredClone(APP.derived), ...derivedPatch },
  ...patch,
});

async function seedCopa(id = 'caesi', revision = 1) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'copa', id), {
      updatedAt: new Date(), updatedBy: 'uid-mesa', revision, copa: APP.copa, derived: APP.derived,
    });
  });
}

describe('Copa — leitura', () => {
  test('qualquer pessoa lê os dois documentos públicos', async () => {
    await seedCopa('caesi'); await seedCopa('caesi_teste');
    await assertSucceeds(getDoc(doc(anon().firestore(), 'copa', 'caesi')));
    await assertSucceeds(getDoc(doc(anon().firestore(), 'copa', 'caesi_teste')));
  });
  test('não dá para listar a coleção nem ler outro documento', async () => {
    await seedCopa('caesi');
    await env.withSecurityRulesDisabled((c) => setDoc(doc(c.firestore(), 'copa', 'segredo'), { x: 1 }));
    await assertFails(getDocs(collection(anon().firestore(), 'copa')));
    await assertFails(getDoc(doc(anon().firestore(), 'copa', 'segredo')));
  });
});

describe('Copa — quem pode gravar', () => {
  test('visitante sem login não grava, não cria, não apaga', async () => {
    await seedCopa();
    await assertFails(setDoc(doc(anon().firestore(), 'copa', 'caesi'), copaPayload('x', 2)));
    await assertFails(updateDoc(doc(anon().firestore(), 'copa', 'caesi'), { revision: 2 }));
    await assertFails(deleteDoc(doc(anon().firestore(), 'copa', 'caesi')));
  });
  test('conta Google qualquer não grava', async () => {
    await seedCopa();
    await assertFails(setDoc(doc(stranger().firestore(), 'copa', 'caesi'), copaPayload('uid-x', 2)));
  });
  test('escritor do RACHA, que não está em copa_writers, NÃO grava na Copa', async () => {
    await seedCopa();
    await assertFails(setDoc(doc(racha().firestore(), 'copa', 'caesi'), copaPayload('uid-racha', 2)));
  });
  test('login que não é Google não grava (mesmo com o e-mail da lista)', async () => {
    await seedCopa();
    const ctx = env.authenticatedContext('uid-mesa', {
      email: 'mesa@x.com', email_verified: true, firebase: { sign_in_provider: 'password' },
    });
    await assertFails(setDoc(doc(ctx.firestore(), 'copa', 'caesi'), copaPayload('uid-mesa', 2)));
  });
  test('e-mail não verificado não grava', async () => {
    await seedCopa();
    const ctx = env.authenticatedContext('uid-mesa', {
      email: 'mesa@x.com', email_verified: false, firebase: { sign_in_provider: 'google.com' },
    });
    await assertFails(setDoc(doc(ctx.firestore(), 'copa', 'caesi'), copaPayload('uid-mesa', 2)));
  });
  test('e-mail em maiúsculas ainda casa com a lista', async () => {
    await seedCopa();
    await assertSucceeds(setDoc(doc(google('Mesa@X.com', 'uid-mesa').firestore(), 'copa', 'caesi'), copaPayload('uid-mesa', 2)));
  });
  test('o escritor da Copa grava a atualização normal (payload real do app)', async () => {
    await seedCopa();
    await assertSucceeds(setDoc(doc(mesa().firestore(), 'copa', 'caesi'), copaPayload('uid-mesa', 2)));
  });
  test('cria o documento do zero com revisão 1', async () => {
    await assertSucceeds(setDoc(doc(mesa().firestore(), 'copa', 'caesi_teste'), copaPayload('uid-mesa', 1)));
  });
});

describe('Copa — o que pode ser gravado', () => {
  const write = (payload, id = 'caesi') => setDoc(doc(mesa().firestore(), 'copa', id), payload);

  test('revisão repetida, pulada ou que volta atrás é recusada', async () => {
    await seedCopa('caesi', 5);
    await assertFails(write(copaPayload('uid-mesa', 5)));
    await assertFails(write(copaPayload('uid-mesa', 7)));
    await assertFails(write(copaPayload('uid-mesa', 3)));
    await assertSucceeds(write(copaPayload('uid-mesa', 6)));
  });
  test('criação só com revisão 1', async () => {
    await assertFails(write(copaPayload('uid-mesa', 9), 'caesi'));
  });
  test('não dá para gravar em nome de outra conta (updatedBy)', async () => {
    await seedCopa();
    await assertFails(write(copaPayload('uid-de-outro', 2)));
  });
  test('updatedAt tem que ser o horário do servidor', async () => {
    await seedCopa();
    await assertFails(write(copaPayload('uid-mesa', 2, { updatedAt: new Date('2020-01-01') })));
  });
  test('campo extra na raiz é recusado', async () => {
    await seedCopa();
    await assertFails(write(copaPayload('uid-mesa', 2, { admin: true })));
  });
  test('campo faltando na raiz é recusado', async () => {
    await seedCopa();
    const p = copaPayload('uid-mesa', 2); delete p.derived;
    await assertFails(write(p));
  });
  test('chave desconhecida dentro de copa/derived é recusada', async () => {
    await seedCopa();
    await assertFails(write(copaPayload('uid-mesa', 2, {}, { lixo: 'x' })));
    await assertFails(write(copaPayload('uid-mesa', 2, {}, {}, { lixo: [] })));
  });
  test('tipos trocados e valores absurdos são recusados', async () => {
    await seedCopa();
    await assertFails(write(copaPayload('uid-mesa', 2, {}, { halfMinutes: '15' })));
    await assertFails(write(copaPayload('uid-mesa', 2, {}, { halfMinutes: 0 })));
    await assertFails(write(copaPayload('uid-mesa', 2, {}, { halfMinutes: 9999 })));
    await assertFails(write(copaPayload('uid-mesa', 2, {}, { halves: 3 })));
    await assertFails(write(copaPayload('uid-mesa', 2, {}, { name: '' })));
    await assertFails(write(copaPayload('uid-mesa', 2, {}, { name: 'x'.repeat(81) })));
    await assertFails(write(copaPayload('uid-mesa', 2, {}, { teams: 'não é lista' })));
    await assertFails(write(copaPayload('uid-mesa', 2, { revision: '2' })));
  });
  test('listas gigantes (inflar o documento) são recusadas', async () => {
    await seedCopa();
    await assertFails(write(copaPayload('uid-mesa', 2, {}, { teams: Array(25).fill({}) })));
    await assertFails(write(copaPayload('uid-mesa', 2, {}, { matches: Array(65).fill({}) })));
    await assertFails(write(copaPayload('uid-mesa', 2, {}, {}, { scorers: Array(301).fill({}) })));
    await assertFails(write(copaPayload('uid-mesa', 2, {}, {}, { cards: Array(301).fill({}) })));
  });
  test('cronômetro pode ser nulo (jogo parado) ou mapa', async () => {
    await seedCopa();
    await assertSucceeds(write(copaPayload('uid-mesa', 2, {}, { clock: null })));
    await assertSucceeds(write(copaPayload('uid-mesa', 3, {}, { clock: { matchId: 'a', durationMs: 1 } })));
    await assertFails(write(copaPayload('uid-mesa', 4, {}, { clock: 'agora' })));
  });
  test('ninguém apaga, nem o escritor', async () => {
    await seedCopa();
    await assertFails(deleteDoc(doc(mesa().firestore(), 'copa', 'caesi')));
  });
  test('documento com outro id não pode ser criado, nem pelo escritor', async () => {
    await assertFails(write(copaPayload('uid-mesa', 1), 'outro'));
  });
});

const volei = () => google('volei@x.com', 'uid-volei');
const voleiPayload = (uid, revision, patch = {}, copaPatch = {}, derivedPatch = {}) => ({
  updatedAt: serverTimestamp(),
  updatedBy: uid,
  revision,
  copa: { ...structuredClone(VOLEI.copa), ...copaPatch },
  derived: { ...structuredClone(VOLEI.derived), ...derivedPatch },
  ...patch,
});

describe('Vôlei', () => {
  const write = (ctx, payload, id = 'caesi') => setDoc(doc(ctx.firestore(), 'volei', id), payload);

  test('leitura pública só de caesi e caesi_teste', async () => {
    await assertSucceeds(getDoc(doc(anon().firestore(), 'volei', 'caesi')));
    await assertSucceeds(getDoc(doc(anon().firestore(), 'volei', 'caesi_teste')));
    await assertFails(getDoc(doc(anon().firestore(), 'volei', 'outro')));
    await assertFails(getDocs(collection(anon().firestore(), 'volei')));
  });

  test('escritor do vôlei cria com o payload real do app e segue a revisão', async () => {
    await assertSucceeds(write(volei(), voleiPayload('uid-volei', 1)));
    await assertFails(write(volei(), voleiPayload('uid-volei', 3)));
    await assertSucceeds(write(volei(), voleiPayload('uid-volei', 2)));
    await assertSucceeds(write(volei(), voleiPayload('uid-volei', 1), 'caesi_teste'));
    await assertFails(deleteDoc(doc(volei().firestore(), 'volei', 'caesi')));
    await assertFails(write(volei(), voleiPayload('uid-volei', 1), 'outro'));
  });

  test('ninguém de fora grava: anônimo, Google qualquer, mesa da Copa, racha', async () => {
    for (const [ctx, uid] of [[anon(), 'x'], [stranger(), 'uid-x'], [mesa(), 'uid-mesa'], [racha(), 'uid-racha']]) {
      await assertFails(write(ctx, voleiPayload(uid, 1)));
    }
  });

  test('escritor do vôlei NÃO grava na Copa de futsal nem no racha', async () => {
    await assertFails(setDoc(doc(volei().firestore(), 'copa', 'caesi'), copaPayload('uid-volei', 1)));
    await assertFails(setDoc(doc(volei().firestore(), 'racha', 'public'),
      { updatedAt: serverTimestamp(), updatedBy: 'uid-volei', revision: 1, players: [], tournaments: [] }));
  });

  test('formato errado é recusado', async () => {
    const w = (p) => write(volei(), p);
    await assertFails(w(voleiPayload('uid-outro', 1)));
    await assertFails(w(voleiPayload('uid-volei', 1, { updatedAt: new Date('2020-01-01') })));
    await assertFails(w(voleiPayload('uid-volei', 1, { admin: true })));
    await assertFails(w(voleiPayload('uid-volei', 1, {}, { lixo: 1 })));
    await assertFails(w(voleiPayload('uid-volei', 1, {}, {}, { cards: [] })));
    await assertFails(w(voleiPayload('uid-volei', 1, {}, { setPoints: 0 })));
    await assertFails(w(voleiPayload('uid-volei', 1, {}, { setPoints: 100 })));
    await assertFails(w(voleiPayload('uid-volei', 1, {}, { setPoints: '15' })));
    await assertFails(w(voleiPayload('uid-volei', 1, {}, { setsToWin: 4 })));
    await assertFails(w(voleiPayload('uid-volei', 1, {}, { name: '' })));
    await assertFails(w(voleiPayload('uid-volei', 1, {}, { teams: Array(13).fill({}) })));
    await assertFails(w(voleiPayload('uid-volei', 1, {}, { matches: Array(33).fill({}) })));
    await assertFails(w(voleiPayload('uid-volei', 1, {}, {}, { scorers: Array(201).fill({}) })));
    // payload da Copa de futsal não passa como vôlei
    await assertFails(w(copaPayload('uid-volei', 1)));
  });
});

describe('Listas de escritores', () => {
  test('cada um só consulta a própria autorização', async () => {
    await assertSucceeds(getDoc(doc(mesa().firestore(), 'copa_writers', 'mesa@x.com')));
    await assertFails(getDoc(doc(mesa().firestore(), 'copa_writers', 'racha@x.com')));
    await assertFails(getDoc(doc(racha().firestore(), 'rdr_writers', 'mesa@x.com')));
    await assertSucceeds(getDoc(doc(racha().firestore(), 'rdr_writers', 'racha@x.com')));
  });
  test('ninguém lista, cria ou altera as listas, nem quem já está nelas', async () => {
    await assertSucceeds(getDoc(doc(volei().firestore(), 'volei_writers', 'volei@x.com')));
    await assertFails(getDoc(doc(volei().firestore(), 'volei_writers', 'mesa@x.com')));
    for (const col of ['copa_writers', 'rdr_writers', 'volei_writers']) {
      await assertFails(getDocs(collection(mesa().firestore(), col)));
      await assertFails(setDoc(doc(mesa().firestore(), col, 'novo@x.com'), {}));
      await assertFails(setDoc(doc(stranger().firestore(), col, 'qualquer@gmail.com'), {}));
      await assertFails(deleteDoc(doc(mesa().firestore(), col, 'mesa@x.com')));
      await assertFails(setDoc(doc(anon().firestore(), col, 'novo@x.com'), {}));
    }
  });
});

describe('Racha e check-in (regressão: nada disso mudou)', () => {
  const racha_ = (uid) => ({
    updatedAt: serverTimestamp(), updatedBy: uid, revision: 1, players: [], tournaments: [],
  });
  test('espelho público: leitura aberta, escrita só do escritor do racha', async () => {
    await assertSucceeds(getDoc(doc(anon().firestore(), 'racha', 'public')));
    await assertSucceeds(setDoc(doc(racha().firestore(), 'racha', 'public'), racha_('uid-racha')));
    await assertFails(setDoc(doc(stranger().firestore(), 'racha', 'public'), racha_('uid-x')));
    await assertFails(setDoc(doc(anon().firestore(), 'racha', 'public'), racha_('x')));
  });
  test('documento completo do racha é privado', async () => {
    await assertFails(getDoc(doc(anon().firestore(), 'racha', 'main')));
    await assertFails(getDoc(doc(stranger().firestore(), 'racha', 'main')));
    await assertSucceeds(getDoc(doc(racha().firestore(), 'racha', 'main')));
    await assertSucceeds(setDoc(doc(racha().firestore(), 'racha', 'main'), racha_('uid-racha')));
  });
  test('escritor da Copa que não é do racha não mexe no racha', async () => {
    await env.withSecurityRulesDisabled((c) => deleteDoc(doc(c.firestore(), 'rdr_writers', 'mesa@x.com')));
    await assertFails(setDoc(doc(mesa().firestore(), 'racha', 'public'), racha_('uid-mesa')));
  });
  test('fila do check-in: ninguém grava, nem o administrador', async () => {
    await assertFails(setDoc(doc(racha().firestore(), 'checkin_events', 'e1', 'entries', 'u'), { n: 1 }));
    await assertFails(setDoc(doc(anon().firestore(), 'checkin_events', 'e1', 'entries', 'u'), { n: 1 }));
  });
  test('auditoria e limites do check-in são invisíveis ao cliente', async () => {
    for (const col of ['checkin_audit', 'checkin_rate', 'checkin_ip']) {
      await assertFails(getDoc(doc(racha().firestore(), col, 'a')));
      await assertFails(setDoc(doc(racha().firestore(), col, 'a'), { n: 1 }));
    }
  });
  test('coleção inventada é negada para todos (padrão fechado)', async () => {
    await assertFails(getDoc(doc(racha().firestore(), 'qualquer', 'coisa')));
    await assertFails(setDoc(doc(mesa().firestore(), 'qualquer', 'coisa'), { n: 1 }));
  });
});

// Opcional: confere o documento REAL da Copa (baixado do Firestore público)
// contra as regras. Não fica no repositório porque tem nomes de pessoas:
//   COPA_REAL_PAYLOAD=/caminho/doc.json tool/test_rules.sh
describe('Compatibilidade com o documento real da Copa', { skip: !process.env.COPA_REAL_PAYLOAD }, () => {
  test('o que o app gravou de verdade passa nas regras', async () => {
    const real = JSON.parse(readFileSync(process.env.COPA_REAL_PAYLOAD, 'utf8'));
    await env.withSecurityRulesDisabled((c) => setDoc(doc(c.firestore(), 'copa', 'caesi'), {
      updatedAt: new Date(), updatedBy: 'uid-mesa', revision: 4, copa: real.copa, derived: real.derived,
    }));
    await assertSucceeds(setDoc(doc(mesa().firestore(), 'copa', 'caesi'), {
      updatedAt: serverTimestamp(), updatedBy: 'uid-mesa', revision: 5, copa: real.copa, derived: real.derived,
    }));
  });
});
