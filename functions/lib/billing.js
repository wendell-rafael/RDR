// Corta o faturamento do projeto quando o orçamento estoura.
//
// AVISO: isto é destrutivo de propósito e não tem meio-termo. Ao disparar, o
// projeto é desvinculado da conta de faturamento e volta pro plano Spark:
//
//   - as Cloud Functions param, então o check-in deixa de aceitar inscrição;
//   - Firestore e Hosting continuam de pé, dentro da cota gratuita, então o
//     placar e a lista já existente seguem visíveis;
//   - religar é manual, pelo Console (Faturamento > Vincular conta).
//
// Existe porque o Google não oferece teto de gasto de verdade: orçamento é só
// alerta por e-mail, a cobrança continua correndo. Este é o único mecanismo que
// garante que a fatura para de crescer sozinha.

import { onMessagePublished } from 'firebase-functions/v2/pubsub';
import { CloudBillingClient } from '@google-cloud/billing';
import { Timestamp } from 'firebase-admin/firestore';
import { db } from './firebase.js';

export const BILLING_TOPIC = 'rdr-billing-alerts';

const billing = new CloudBillingClient();

function projectName() {
  const id = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT;
  return `projects/${id}`;
}

export const billingKillSwitch = onMessagePublished({
  region: 'southamerica-east1',
  topic: BILLING_TOPIC,
  maxInstances: 1,
  retryCount: 0,
}, async (event) => {
  const notice = event.data?.message?.json ?? {};
  const cost = Number(notice.costAmount ?? 0);
  const budget = Number(notice.budgetAmount ?? 0);

  // Só corta no estouro real. Os alertas de 50% e 90% servem pra avisar você,
  // não pra derrubar o racha na véspera do jogo.
  if (!budget || cost < budget) {
    console.log(`orçamento em ${cost}/${budget} — sem ação`);
    return;
  }

  const name = projectName();
  await db.collection('checkin_audit').add({
    at: Timestamp.now(),
    action: 'kill-switch',
    result: 'faturamento-desativado',
    cost,
    budget,
    currency: notice.currencyCode ?? '',
  });

  const [info] = await billing.getProjectBillingInfo({ name });
  if (!info.billingEnabled) {
    console.log('faturamento já estava desativado');
    return;
  }

  await billing.updateProjectBillingInfo({
    name,
    projectBillingInfo: { billingAccountName: '' },
  });
  console.error(`FATURAMENTO DESATIVADO: custo ${cost} ${notice.currencyCode} passou do orçamento ${budget}`);
});
