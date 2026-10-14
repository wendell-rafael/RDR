// Chave pública do reCAPTCHA v3 usada pelo App Check.
//
// App Check é o que impede alguém de chamar a função de check-in fora desta
// página — de um terminal, de um script, de um bot inscrevendo dez contas. O
// navegador resolve um desafio invisível e recebe um token; a Cloud Function
// recusa qualquer chamada sem ele (`enforceAppCheck: true`).
//
// Esta chave é pública por natureza, igual à do Firebase: ela aparece no código
// da página. Quem protege é o par dela, a chave secreta, que fica só no Console
// do Google e nunca entra no repositório.
//
// Para preencher:
//   1. Firebase Console > Compilação > App Check > Apps
//   2. registre o app Web e escolha o provedor reCAPTCHA v3
//   3. cole abaixo a "chave do site" que o Console mostrar
//   4. em App Check > APIs, marque Cloud Functions como "Aplicado"
//
// Enquanto estiver com o texto de exemplo, o check-in não funciona: a página
// avisa no console e toda chamada volta recusada.
export const RECAPTCHA_SITE_KEY = 'COLOQUE_AQUI_A_CHAVE_DO_SITE_DO_RECAPTCHA_V3';
