// Cria o documento do racha da semana antes de alguém precisar dele.
//
// A chamada de check-in também cria sob demanda, então isto não é obrigatório
// pro fluxo funcionar. O ganho é a página conseguir mostrar "abre quinta às
// 12h" com contagem regressiva desde já, em vez de só depois que a primeira
// pessoa se inscrever.

import { onSchedule } from 'firebase-functions/v2/scheduler';
import { Timestamp } from 'firebase-admin/firestore';
import { db } from './firebase.js';
import { DEFAULT_CONFIG, normalizeConfig, resolveEvent } from './events.js';

export const openWeeklyCheckin = onSchedule({
  region: 'southamerica-east1',
  schedule: '10 0 * * *',
  timeZone: 'America/Sao_Paulo',
  maxInstances: 1,
  retryCount: 2,
}, async () => {
  const snap = await db.collection('checkin_config').doc('settings').get();
  const config = normalizeConfig(snap.exists ? snap.data() : DEFAULT_CONFIG);
  const resolved = resolveEvent(new Date(), config);
  if (!resolved) {
    console.log('nenhum racha a agendar');
    return;
  }

  const ref = db.collection('checkin_events').doc(resolved.eventId);
  try {
    // Só create: um evento já ajustado à mão no painel nunca é sobrescrito.
    await ref.create({
      openAt: Timestamp.fromDate(resolved.openAt),
      closeAt: Timestamp.fromDate(resolved.closeAt),
      matchAt: Timestamp.fromDate(resolved.matchAt),
      playerCapacity: resolved.playerCapacity,
      keeperCapacity: resolved.keeperCapacity,
      playerWaitlist: resolved.playerWaitlist,
      keeperWaitlist: resolved.keeperWaitlist,
      fixedPlayers: resolved.fixedPlayers,
      maxEntries: resolved.maxEntries,
      status: 'auto',
      createdAt: Timestamp.now(),
      createdBy: 'system',
    });
    console.log(`evento ${resolved.eventId} criado`);
  } catch (error) {
    if (error?.code === 6) {
      console.log(`evento ${resolved.eventId} já existia`);
      return;
    }
    throw error;
  }
});
