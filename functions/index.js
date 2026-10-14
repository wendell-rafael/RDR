// Ponto de entrada das Cloud Functions do Racha dos Ruins.
//
// Tudo roda em southamerica-east1 (São Paulo) pra encurtar a ida e volta de
// quem está apertando o botão no celular no meio da semana.

export { adminRemoveEntry, cancelCheckin, checkin } from './lib/checkin.js';
export { openWeeklyCheckin } from './lib/schedule.js';
export { billingKillSwitch } from './lib/billing.js';
