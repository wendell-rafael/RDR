# Racha dos Ruins (RDR)

Aplicativo Flutter para organizar torneios informais de futebol (o famoso racha), com foco em:

- cadastro e avaliação de jogadores
- sorteio balanceado de times
- execução de torneio com controle de partidas
- histórico de campeões e estatísticas
- sincronização dos dados com Firebase Firestore

## Funcionalidades

- Jogadores
	- cadastro, edição, remoção e busca
	- avaliação por estrelas
	- estatísticas por gols e títulos
- Sorteio
	- seleção dos jogadores presentes
	- importação de lista de nomes colada do grupo, casando com o cadastro
	  (nome sem correspondência fica em branco para seleção manual)
	- criação de 2 a 5 times
	- re-sorteio e troca manual de jogadores entre times
	- personalização de cor dos times
	- exportação dos times como mensagem de WhatsApp (copiar ou compartilhar)
- Torneio
	- geração da tabela conforme quantidade de times
	- opção de mata-mata em ida e volta: semifinais e final em dois jogos,
	  decididos pelo placar agregado (play-in de 5 times segue em jogo único)
	- acompanhamento de confrontos, classificação e mata-mata
	- controle de partida com placar e registro de artilheiros
	- gol pode ser creditado a qualquer jogador do cadastro, inclusive quem
	  completou para o time
	- tratamento de empate em fase eliminatória com decisão por pênaltis
	  (no ida e volta, os pênaltis só entram se o agregado empatar)
	- exportação da tabela como mensagem de WhatsApp
- Cronômetro de partida
	- modo regressivo ou crescente
	- duração customizável por partida
	- acréscimo de minutos com a partida em andamento
	- continua rodando ao sair da partida para consultar a tabela, com faixa
	  de atalho para voltar
	- execução em foreground service no Android
- Histórico
	- torneios finalizados
	- ranking de jogadores por títulos ou gols
- Nuvem
	- envio e atualização manual de dados via Firestore
	- envio automático em eventos do fluxo do app

## Stack técnica

- Flutter + Dart
- Riverpod (estado)
- share_plus (compartilhamento das mensagens)
- GoRouter (navegação)
- Hive CE (persistência local)
- Firebase Core + Cloud Firestore (sincronização)
- flutter_foreground_task + flutter_local_notifications (timer/background)

## Estrutura do projeto

```text
lib/
	app/
		router.dart
		theme.dart
	data/
		models/
		repositories/
		services/
	features/
		draw/
		history/
		home/
		match/
		players/
		settings/
		tournament/
	widgets/
```

## Pré-requisitos

- Flutter SDK compatível com Dart >= 3.3.0 e < 4.0.0
- Android Studio (ou SDK/adb configurados)
- Projeto Firebase configurado para Android

## Configuração local

1. Instale as dependências:

```bash
flutter pub get
```

2. Garanta que os arquivos Firebase estão corretos:

- `android/app/google-services.json`
- `lib/firebase_options.dart`

3. Rode o app:

```bash
flutter run
```

### Versão web

O app Flutter também pode ser executado no navegador:

```bash
flutter run -d chrome
```

Para gerar os arquivos de produção:

```bash
flutter build web
```

O resultado fica em `build/web`. O Firebase Hosting configurado neste projeto
continua apontando para `painel/`, então a publicação do app Flutter deve usar
um site ou projeto de Hosting separado do painel administrativo.

## Comandos úteis

```bash
# analisar o projeto
flutter analyze

# rodar testes
flutter test

# gerar arquivos (Hive adapters, etc.)
flutter pub run build_runner build --delete-conflicting-outputs
```

## Observações sobre sincronização

- A sincronização usa um documento no Firestore: `racha/main`.
- A leitura desse documento é pública para alimentar o painel web.
- A escrita exige uma conta Google verificada e o e-mail cadastrado na allowlist
  `rdr_writers`.
- Em Configurações, você pode:
	- Enviar agora: sobe os dados locais para a nuvem.
	- Atualizar: substitui os dados locais pelos dados da nuvem.

### Autorizar responsáveis pela sincronização

1. No Firebase Console, cadastre o SHA-1 da assinatura Android em
   **Configurações do projeto > Seus apps > Android**.
2. Habilite **Authentication > Google** e desabilite o provedor anônimo depois
   que todos estiverem usando esta versão do app.
3. Baixe o `google-services.json` atualizado e coloque-o em `android/app/`.
4. No Firestore, crie a coleção `rdr_writers` e um documento para cada pessoa.
   O ID do documento deve ser exatamente o e-mail Google, em letras minúsculas;
   o documento pode conter apenas um campo descritivo, como `name`.
5. Publique as regras com `firebase deploy --only firestore:rules`.
6. Cada responsável usa **Configurações > Nuvem protegida > Entrar com Google**.

Adicionar ou remover um documento de `rdr_writers` concede ou revoga a escrita
sem exigir uma nova versão do aplicativo. Esses documentos só podem ser
administrados pelo Console ou por um ambiente confiável usando o Admin SDK.

## Observações para Android

O app utiliza permissões e recursos de foreground service/notificação para o cronômetro em segundo plano, incluindo:

- `FOREGROUND_SERVICE`
- `FOREGROUND_SERVICE_DATA_SYNC`
- `POST_NOTIFICATIONS`
- `VIBRATE`
- `WAKE_LOCK`

## Versão

- App: `1.0.0+1`

## Licença

Projeto privado para uso interno.
