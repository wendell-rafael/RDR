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
	- criação de 2 a 5 times
	- re-sorteio e troca manual de jogadores entre times
	- personalização de cor dos times
- Torneio
	- geração da tabela conforme quantidade de times
	- acompanhamento de confrontos, classificação e mata-mata
	- controle de partida com placar e registro de artilheiros
	- tratamento de empate em fase eliminatória com decisão por pênaltis
- Cronômetro de partida
	- modo regressivo ou crescente
	- duração customizável por partida
	- execução em foreground service no Android
	- alerta sonoro e vibração ao fim
- Histórico
	- torneios finalizados
	- ranking de jogadores por títulos ou gols
- Nuvem
	- envio e atualização manual de dados via Firestore
	- envio automático em eventos do fluxo do app

## Stack técnica

- Flutter + Dart
- Riverpod (estado)
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
- Em Configurações, você pode:
	- Enviar agora: sobe os dados locais para a nuvem.
	- Atualizar: substitui os dados locais pelos dados da nuvem.

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
