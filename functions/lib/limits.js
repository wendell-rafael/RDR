// Controle de carga e de abuso.
//
// Nenhum contador global: documento único é o jeito mais fácil de criar
// contenção justamente no minuto em que todo mundo aperta o botão. Cada limite
// aqui é escrito num documento que só uma pessoa (ou um minuto) disputa.

import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { createHash } from 'node:crypto';

// Por conta: sobra folga pra errar e tentar de novo, mas não pra automatizar.
const USER_WINDOW_MS = 60 * 60 * 1000;
const USER_MAX_PER_WINDOW = 12;

// Por IP e por minuto. O teto é generoso de propósito: operadora de celular
// põe muita gente atrás do mesmo IP (CGNAT), e barrar o bairro inteiro porque
// dez pessoas usam a mesma antena seria pior que o abuso.
const IP_WINDOW_MS = 60 * 1000;
const IP_MAX_PER_WINDOW = 40;

// Quanto tempo os documentos de limite ficam no banco antes da política de TTL
// do Firestore apagá-los.
const LIMIT_TTL_MS = 24 * 60 * 60 * 1000;

export class RateLimited extends Error {
  constructor(scope) {
    super(`rate-limited:${scope}`);
    this.scope = scope;
  }
}

export function hashIp(ip) {
  return createHash('sha256').update(String(ip || 'desconhecido')).digest('hex').slice(0, 32);
}

/**
 * Janela deslizante por conta, numa transação sobre o documento da própria
 * pessoa — duas contas diferentes nunca disputam a mesma linha.
 */
export async function consumeUserQuota(db, uid, now) {
  const ref = db.collection('checkin_rate').doc(uid);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() : null;
    const startedAt = data?.windowStartedAt?.toMillis?.() ?? 0;
    const fresh = now.getTime() - startedAt < USER_WINDOW_MS;
    const count = fresh ? Number(data?.count ?? 0) : 0;
    if (count >= USER_MAX_PER_WINDOW) throw new RateLimited('conta');
    tx.set(ref, {
      count: count + 1,
      windowStartedAt: fresh ? data.windowStartedAt : Timestamp.fromDate(now),
      lastAt: Timestamp.fromDate(now),
      expiresAt: Timestamp.fromMillis(now.getTime() + LIMIT_TTL_MS),
    });
  });
}

/**
 * Por IP, com o minuto no id do documento. Espalhar a escrita no tempo evita o
 * documento quente que um contador acumulado por IP criaria, e o próprio limite
 * garante que ninguém escreve rápido demais na mesma linha.
 */
export async function consumeIpQuota(db, ipHash, now) {
  const bucket = Math.floor(now.getTime() / IP_WINDOW_MS);
  const ref = db.collection('checkin_ip').doc(`${ipHash}_${bucket}`);
  const snap = await ref.get();
  const count = Number(snap.data()?.count ?? 0);
  if (count >= IP_MAX_PER_WINDOW) throw new RateLimited('rede');
  await ref.set({
    count: FieldValue.increment(1),
    expiresAt: Timestamp.fromMillis(now.getTime() + LIMIT_TTL_MS),
  }, { merge: true });
}
