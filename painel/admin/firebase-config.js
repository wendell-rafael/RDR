// Configuração do app Web do Firebase.
//
// CÓPIA de ../../firebase-config.js — o admin virou um Hosting site
// separado (racha-ruins-admin), então esta pasta é a raiz do próprio
// site e não enxerga mais arquivos fora dela. Se trocar um valor aqui,
// troca no outro arquivo também (são idênticos por design, não é segredo).
//
// Estes são os mesmos valores do app Android (`lib/firebase_options.dart`).
// Testado: a chave não tem restrição de plataforma, então funciona também a
// partir do navegador — não foi preciso registrar um app Web só para o painel.
//
// Para o Firestore o SDK web precisa de `apiKey` e `projectId`; o `appId` só
// importa para Analytics, que o painel não usa.
//
// Estes valores são públicos por natureza: ficam visíveis no código da página.
// Quem protege os dados são as regras do Firestore, não esta chave.
//
// Se um dia quiser separar as chaves, registre um app Web no console
// (Configurações do projeto -> Seus apps -> Adicionar app -> Web) e troque aqui.
export const firebaseConfig = {
  apiKey: 'AIzaSyA-KGihIggSOgWaSWdYKYfDQaEBxCVNI0s',
  authDomain: 'racha-dos-ruins.firebaseapp.com',
  projectId: 'racha-dos-ruins',
  storageBucket: 'racha-dos-ruins.firebasestorage.app',
  messagingSenderId: '798969577133',
  appId: '1:798969577133:android:517bcda3e238a13abcd024',
};
