// Check-in do racha.
//
// A ordem da fila é a ordem de `createdAt`, e `createdAt` é o relógio do
// Firestore no instante do commit — não o relógio de quem clicou. Ninguém
// adianta a própria posição mexendo no horário do celular.
//
// Empate de milissegundo acontece: medido no emulador, 30 gravações
// simultâneas caíram em 25 instantes distintos. Entre dois empatados não existe
// "quem chegou primeiro", e tudo bem — o que a fila precisa é de uma ordem
// única, não de carimbos únicos. Quem garante isso é o desempate por id do
// documento, declarado explicitamente na consulta que a página e o painel
// fazem, para que todo leitor veja a mesma sequência.
//
// São duas filas separadas, linha e goleiro, cada uma com a própria
// capacidade. Elas não se misturam: goleiro sobrando não vira vaga de linha.
//
// Nada aqui conta vaga na hora da gravação. Confirmado e lista de espera são
// derivados na leitura, a partir da ordem dentro da função: os primeiros que
// cabem estão dentro, os seguintes esperam. Isso tem duas consequências boas
// sob acesso simultâneo:
//
//   1. não existe contador central pra disputar, então não existe o documento
//      quente que limitaria tudo a uma escrita por segundo;
//   2. quando alguém desiste, a fila anda sozinha — sem job de promoção, sem
//      janela em que duas pessoas achem que herdaram a mesma vaga.

import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { db } from './firebase.js';
import { audit, hashAgent } from './audit.js';
import { RateLimited, consumeIpQuota, consumeUserQuota, hashIp } from './limits.js';
import { DEFAULT_CONFIG, ROLES, normalizeConfig, resolveEvent, windowState } from './events.js';

const BASE_OPTIONS = {
  region: 'southamerica-east1',
  // Teto de concorrência. Com a concorrência padrão de 80 requisições por
  // instância isso dá 800 chamadas simultâneas, muito acima do racha, e limita
  // o pior caso de custo caso alguém resolva martelar o endpoint.
  maxInstances: 10,
  memory: '256MiB',
  timeoutSeconds: 30,
};

// Chamadas abertas ao público exigem App Check: é o que impede a inscrição de
// sair de um script em vez da página.
//
// A exceção é o emulador, que não emite token de App Check — com a exigência
// ligada, nenhuma chamada local passaria e não haveria como testar o fluxo.
// `FUNCTIONS_EMULATOR` é posto pelo próprio emulador e nunca existe em
// produção, então isto não afrouxa nada na nuvem.
const IN_EMULATOR = process.env.FUNCTIONS_EMULATOR === 'true';

const PUBLIC_OPTIONS = {
  ...BASE_OPTIONS,
  enforceAppCheck: !IN_EMULATOR,
  cors: [
    'https://racha-dos-ruins.web.app',
    'https://racha-dos-ruins.firebaseapp.com',
  ],
};

// O painel não passa por App Check — ele mora em outra origem e teria que
// registrar o próprio provedor. Aqui a barreira é mais forte que um token de
// navegador: conta Google verificada e e-mail presente na allowlist
// `rdr_writers`, a mesma que autoriza gravar o racha inteiro.
const ADMIN_OPTIONS = {
  ...BASE_OPTIONS,
  enforceAppCheck: false,
  cors: [
    'https://racha-ruins-admin.web.app',
    'https://racha-ruins-admin.firebaseapp.com',
  ],
};

const NAME_MAX = 40;
const NAME_MIN = 2;
const INVISIBLE = /[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/gu;

/** Nome é só rótulo na lista: tira controle, normaliza espaço e corta. */
function sanitizeName(raw) {
  const cleaned = String(raw ?? '')
    .replace(INVISIBLE, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, NAME_MAX);
  if (cleaned.length < NAME_MIN) return null;
  return cleaned;
}

/** Linha ou goleiro. Qualquer outra coisa é recusada, não corrigida. */
function readRole(raw) {
  const role = String(raw ?? 'player');
  return ROLES.includes(role) ? role : null;
}

function clientIp(request) {
  const forwarded = request.rawRequest?.headers?.['x-forwarded-for'];
  if (typeof forwarded === 'string' && forwarded.length) return forwarded.split(',')[0].trim();
  return request.rawRequest?.ip ?? '';
}

/** Só conta Google verificada entra na fila. */
function requireGoogleAccount(request) {
  const auth = request.auth;
  if (!auth) throw new HttpsError('unauthenticated', 'Entre com sua conta Google para confirmar presença.');
  const token = auth.token ?? {};
  if (token.firebase?.sign_in_provider !== 'google.com') {
    throw new HttpsError('permission-denied', 'Use o botão "Entrar com Google".');
  }
  if (token.email_verified !== true || typeof token.email !== 'string') {
    throw new HttpsError('permission-denied', 'Sua conta Google precisa de e-mail verificado.');
  }
  return { uid: auth.uid, email: token.email.toLowerCase(), token };
}

async function loadConfig() {
  const snap = await db.collection('checkin_config').doc('settings').get();
  return normalizeConfig(snap.exists ? snap.data() : DEFAULT_CONFIG);
}

/**
 * Garante o documento do evento da semana.
 *
 * O id é derivado da data do jogo, então `create()` é idempotente por
 * construção: se duas chamadas simultâneas tentarem criar, uma vence e a outra
 * recebe ALREADY_EXISTS, que aqui não é erro. Um evento já ajustado à mão no
 * painel nunca é sobrescrito, porque só existe create, nunca update.
 */
async function ensureEvent(resolved) {
  const ref = db.collection('checkin_events').doc(resolved.eventId);
  const snap = await ref.get();
  if (snap.exists) return { ref, data: snap.data() };

  const fresh = {
    openAt: Timestamp.fromDate(resolved.openAt),
    closeAt: Timestamp.fromDate(resolved.closeAt),
    matchAt: Timestamp.fromDate(resolved.matchAt),
    playerCapacity: resolved.playerCapacity,
    keeperCapacity: resolved.keeperCapacity,
    playerWaitlist: resolved.playerWaitlist,
    keeperWaitlist: resolved.keeperWaitlist,
    // Copiado pro evento de propósito: mudar a lista de fixos na configuração
    // não pode reordenar um racha que já está com gente inscrita.
    fixedPlayers: resolved.fixedPlayers,
    maxEntries: resolved.maxEntries,
    status: 'auto',
    createdAt: Timestamp.now(),
    createdBy: 'system',
  };
  try {
    await ref.create(fresh);
    return { ref, data: fresh };
  } catch (error) {
    if (error?.code !== 6) throw error; // 6 = ALREADY_EXISTS
    const again = await ref.get();
    return { ref, data: again.data() };
  }
}

function toDate(value) {
  return value?.toDate ? value.toDate() : new Date(0);
}

function readWindow(eventData, now) {
  return windowState({
    status: eventData.status,
    openAt: toDate(eventData.openAt),
    closeAt: toDate(eventData.closeAt),
  }, now);
}

export const checkin = onCall(PUBLIC_OPTIONS, async (request) => {
  const now = new Date();
  const { uid, email, token } = requireGoogleAccount(request);
  const ip = clientIp(request);
  const ipHash = hashIp(ip);
  const agentHash = hashAgent(request.rawRequest?.headers?.['user-agent']);

  const name = sanitizeName(request.data?.name ?? token.name);
  if (!name) {
    throw new HttpsError('invalid-argument', 'Informe um nome com pelo menos 2 letras.');
  }
  const role = readRole(request.data?.role);
  if (!role) {
    throw new HttpsError('invalid-argument', 'Escolha entre linha e goleiro.');
  }

  const base = { uid, email, ipHash, agentHash, action: 'checkin', role };

  try {
    await consumeIpQuota(db, ipHash, now);
    await consumeUserQuota(db, uid, now);
  } catch (error) {
    if (!(error instanceof RateLimited)) throw error;
    await audit(db, { ...base, result: 'rejeitado', reason: `limite:${error.scope}` });
    throw new HttpsError('resource-exhausted', 'Muitas tentativas seguidas. Espere um minuto e tente de novo.');
  }

  const config = await loadConfig();

  // Quem é fixo não disputa fila: a vaga já é dele. Só vale quando a conta foi
  // vinculada no painel — sem o vínculo, o nome sozinho não prova nada, então
  // a pessoa entra na fila como qualquer um.
  if (config.fixedUids.includes(uid)) {
    await audit(db, { ...base, result: 'fixo' });
    return { result: 'fixo' };
  }

  const resolved = resolveEvent(now, config);
  if (!resolved) {
    await audit(db, { ...base, result: 'rejeitado', reason: 'sem-evento' });
    throw new HttpsError('failed-precondition', 'Nenhum racha marcado no momento.');
  }

  const { ref: eventRef, data: eventData } = await ensureEvent(resolved);
  const state = readWindow(eventData, now);
  if (state !== 'open') {
    await audit(db, { ...base, eventId: resolved.eventId, result: 'rejeitado', reason: `janela:${state}` });
    const message = state === 'scheduled'
      ? 'O check-in ainda não abriu.'
      : state === 'canceled'
        ? 'Este racha foi cancelado.'
        : 'O check-in desta semana já fechou.';
    throw new HttpsError('failed-precondition', message);
  }

  const entriesRef = eventRef.collection('entries');
  const entryRef = entriesRef.doc(uid);

  // Válvula de segurança, não é o limite de vagas. Fica muito acima da
  // capacidade + espera justamente pra poder ficar fora da transação: contar
  // dentro dela faria toda inscrição nova conflitar com todas as outras e
  // viraria tempestade de retentativa na hora do pico.
  const maxEntries = Number(eventData.maxEntries ?? resolved.maxEntries);
  const total = (await entriesRef.count().get()).data().count;
  if (total >= maxEntries && !(await entryRef.get()).exists) {
    await audit(db, { ...base, eventId: resolved.eventId, result: 'rejeitado', reason: 'lotado' });
    throw new HttpsError('resource-exhausted', 'A lista desta semana está cheia.');
  }

  // A transação toca só o documento desta pessoa, então duas inscrições
  // simultâneas nunca disputam a mesma linha.
  const outcome = await db.runTransaction(async (tx) => {
    const snap = await tx.get(entryRef);
    if (snap.exists) {
      const current = snap.data();
      if ((current.role ?? 'player') !== role) {
        // Trocar de função recomeça a fila. Sem isso, quem fosse o primeiro da
        // linha viraria o primeiro goleiro na hora, passando na frente de quem
        // pediu o gol antes — a posição é da fila, não da pessoa.
        tx.update(entryRef, { role, name, createdAt: FieldValue.serverTimestamp() });
        return 'trocou-de-funcao';
      }
      // Reentrar na mesma função não manda pro fim nem pro começo: quem já
      // está inscrito continua exatamente na posição que conquistou.
      if (current.name !== name) tx.update(entryRef, { name });
      return 'ja-inscrito';
    }
    tx.create(entryRef, {
      uid,
      name,
      role,
      createdAt: FieldValue.serverTimestamp(),
      source: 'web',
    });
    return 'inscrito';
  });

  await audit(db, { ...base, eventId: resolved.eventId, name, result: outcome });
  return { eventId: resolved.eventId, result: outcome };
});

export const cancelCheckin = onCall(PUBLIC_OPTIONS, async (request) => {
  const now = new Date();
  const { uid, email } = requireGoogleAccount(request);
  const ipHash = hashIp(clientIp(request));
  const base = { uid, email, ipHash, action: 'cancel' };

  try {
    await consumeUserQuota(db, uid, now);
  } catch (error) {
    if (!(error instanceof RateLimited)) throw error;
    await audit(db, { ...base, result: 'rejeitado', reason: `limite:${error.scope}` });
    throw new HttpsError('resource-exhausted', 'Muitas tentativas seguidas. Espere um minuto.');
  }

  const resolved = resolveEvent(now, await loadConfig());
  if (!resolved) throw new HttpsError('failed-precondition', 'Nenhum racha marcado no momento.');

  const eventRef = db.collection('checkin_events').doc(resolved.eventId);
  const eventSnap = await eventRef.get();
  if (eventSnap.exists && readWindow(eventSnap.data(), now) === 'closed') {
    await audit(db, { ...base, eventId: resolved.eventId, result: 'rejeitado', reason: 'janela:closed' });
    throw new HttpsError('failed-precondition', 'O check-in já fechou — avise no grupo se não puder ir.');
  }

  await eventRef.collection('entries').doc(uid).delete();
  await audit(db, { ...base, eventId: resolved.eventId, result: 'cancelado' });
  return { eventId: resolved.eventId, result: 'cancelado' };
});

/** Remoção pelo painel: só quem está na allowlist `rdr_writers`. */
export const adminRemoveEntry = onCall(ADMIN_OPTIONS, async (request) => {
  const { uid, email } = requireGoogleAccount(request);
  const writer = await db.collection('rdr_writers').doc(email).get();
  if (!writer.exists) throw new HttpsError('permission-denied', 'Conta sem permissão de administração.');

  const eventId = String(request.data?.eventId ?? '');
  const target = String(request.data?.uid ?? '');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(eventId) || !target) {
    throw new HttpsError('invalid-argument', 'Evento ou inscrição inválidos.');
  }

  await db.collection('checkin_events').doc(eventId).collection('entries').doc(target).delete();
  await audit(db, {
    uid, email, action: 'admin-remove', eventId, targetUid: target, result: 'removido',
  });
  return { result: 'removido' };
});
