// Log de auditoria.
//
// Escrito só pelo Admin SDK e fechado para qualquer cliente nas regras. É o que
// permite responder depois "quem entrou primeiro" e "quem tentou o quê" sem
// depender da palavra de quem estava do outro lado da tela.

import { Timestamp } from 'firebase-admin/firestore';
import { createHash } from 'node:crypto';

export function hashAgent(userAgent) {
  return createHash('sha256').update(String(userAgent || '')).digest('hex').slice(0, 16);
}

export async function audit(db, record) {
  try {
    await db.collection('checkin_audit').add({
      ...record,
      at: Timestamp.now(),
    });
  } catch (error) {
    // Auditoria nunca derruba a inscrição de quem está na fila.
    console.error('falha ao gravar auditoria', error);
  }
}
