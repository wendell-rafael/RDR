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
- Check-in (site)
	- confirmação de presença com conta Google, liberada toda quinta
	- fila por ordem de chegada com lista de espera automática
	- administração de horários, vagas e remoções pelo painel

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

## Check-in do racha

Página pública em `/checkin/` onde cada pessoa entra com a conta Google, escolhe
entre **linha** e **gol**, e aperta **Vou**. O racha é **terça às 19h**; a lista
abre na **quinta anterior ao meio-dia** e fecha duas horas antes do jogo — cinco
dias de janela. Quem chega primeiro fica na frente; passando da capacidade, a
pessoa cai na lista de espera.

São **16 vagas de linha e 2 no gol**. Quatro das dezesseis já são dos fixos
(Rafael, Augusto, Wendell e Caio), que não passam pela fila — sobram **12 vagas
de linha em disputa**.

As duas filas são independentes: goleiro sobrando não vira vaga de linha, nem o
contrário. Uma fila só faria o time entrar em campo com dezesseis na linha e
ninguém no gol.

### Como a fila fica honesta com muita gente ao mesmo tempo

O problema de uma fila por ordem de chegada não é guardar nomes, é decidir a
ordem quando trinta pessoas apertam o botão no mesmo minuto. Três decisões
sustentam isso:

**A hora vem do servidor, não do navegador.** Cada inscrição é gravada por uma
Cloud Function com `serverTimestamp()`, que é o relógio do Firestore no instante
do commit. Adiantar o relógio do celular não adianta a vaga.

**Empate de milissegundo acontece.** Medido: 30 inscrições simultâneas caíram em
25 instantes distintos. Entre duas pessoas empatadas não existe "quem chegou
primeiro" — e não precisa existir. O que a fila precisa é de uma **ordem única**,
não de carimbos únicos: se dois leitores desempatassem diferente, a página e o
painel mostrariam listas que não batem. Por isso a consulta declara o desempate
por id do documento explicitamente, e `tool/race_test.mjs` confere que duas
leituras da mesma fila devolvem a mesma sequência.

**Ninguém escreve na fila direto.** As regras negam escrita em
`checkin_events/{id}/entries` para todos os clientes, inclusive o painel de
administração. Se o navegador pudesse criar o próprio documento, ele escolheria
o horário gravado, e a ordem viraria disputa de quem mente melhor sobre o
relógio.

**Confirmado e espera não são gravados em lugar nenhum.** São a posição na
ordem: os primeiros `capacity` estão dentro, os `waitlistCapacity` seguintes
esperam. Isso evita o contador central, que seria o gargalo óbvio — um único
documento no Firestore aguenta cerca de uma escrita por segundo, e é exatamente
nele que todas as inscrições bateriam ao mesmo tempo. Sem contador, cada pessoa
escreve só o próprio documento e não disputa linha com ninguém.

O efeito colateral é bom: quando alguém cancela, a fila anda sozinha. Não existe
job de promoção nem a janela em que duas pessoas acham que herdaram a mesma
vaga.

### Contra quem tenta burlar

| Tentativa | O que barra |
| --- | --- |
| Entrar várias vezes | id do documento é o uid da conta Google — reentrar mantém a posição, não cria outra |
| Entrar no lugar de outro | login obrigatório; o nome é só rótulo, a vaga é da conta |
| Chamar o endpoint por script | App Check (reCAPTCHA v3) recusa chamada sem token de navegador |
| Marretar o botão | 12 chamadas por hora por conta, 40 por minuto por rede |
| Clicar antes de abrir | a janela é conferida no servidor; o relógio do cliente só afeta o cliente |
| Encher a coleção | teto de `maxEntries` por racha |
| Apagar o próprio rastro | `checkin_audit` é negado a todo cliente; só o Admin SDK escreve e lê |

Contas Google novas ainda conseguem uma vaga cada. É o piso: para subir dele
seria preciso verificação por telefone, que custa por SMS.

### Estrutura no Firestore

| Caminho | Leitura | Escrita |
| --- | --- | --- |
| `checkin_config/settings` | pública | allowlist `rdr_writers` |
| `checkin_events/{data}` | pública | allowlist `rdr_writers` |
| `checkin_events/{data}/entries/{uid}` | pública | **ninguém** — só a Cloud Function |

Cada inscrição guarda `role` (`player` ou `keeper`), `name`, `uid` e o
`createdAt` do servidor. Trocar de função regrava o `createdAt`: quem era o
primeiro da linha não vira o primeiro goleiro na hora, passando na frente de
quem pediu o gol antes. A posição é da fila, não da pessoa.
| `checkin_audit/{id}` | negada | negada — só a Cloud Function |
| `checkin_rate`, `checkin_ip` | negada | negada — só a Cloud Function |

O id do evento é a data do jogo (`2026-09-19`). Como é derivado e não sorteado,
criar o mesmo racha duas vezes é impossível: a segunda tentativa esbarra em
`ALREADY_EXISTS`.

### Funções

| Função | Para quê |
| --- | --- |
| `checkin` | grava a inscrição; exige App Check e conta Google verificada |
| `cancelCheckin` | libera a vaga e faz a espera subir |
| `adminRemoveEntry` | remoção pelo painel; exige `rdr_writers` |
| `openWeeklyCheckin` | agendada, cria o racha da semana à meia-noite |
| `billingKillSwitch` | desliga o faturamento se o orçamento estourar |

### Padrão semanal

Os valores iniciais são **jogo na terça às 19h**, **abertura na quinta anterior
ao meio-dia**, 16 vagas de linha (4 delas dos fixos), 2 de gol, 10 de espera na
linha e 2 no gol. Para mudar, use **Administração > Check-in > Padrão semanal**. A configuração vale para os rachas ainda não
criados: o desta semana continua com o horário que já recebeu, e é em
**Administração > Check-in > Este racha** que se ajusta um caso isolado.

O cálculo da abertura sempre volta para o `openWeekday` anterior ao jogo. Com
terça e quinta isso dá cinco dias; se os dois caírem no mesmo dia da semana,
volta uma semana inteira, nunca abre depois do próprio jogo.

### Fixos

Os fixos ocupam vaga de linha sem apertar botão nenhum: a fila disputa
`playerCapacity - fixedPlayers.length`. A lista é copiada para dentro do
documento do evento na hora em que ele é criado, de propósito — mudar os fixos
na configuração não pode reordenar um racha que já está com gente inscrita. Para
mexer numa semana específica, use **Administração > Check-in > Este racha**;
tirar um fixo de lá devolve a vaga para a fila e quem estava esperando sobe na
hora.

Há um campo opcional `fixedUids`. Preenchido com o uid da conta Google do fixo,
a pessoa que apertar **Vou** recebe "sua vaga já está garantida" em vez de
ocupar uma das vagas em disputa. **Sem esse vínculo, um fixo que aperte o botão
entra na fila como qualquer outro e o racha fica com uma vaga a mais ocupada** —
o nome digitado sozinho não prova identidade, e tratar nome como prova seria
justamente o buraco que o login veio fechar. O uid aparece no log de auditoria
depois do primeiro check-in da pessoa.

### Testar localmente

Tudo roda em `127.0.0.1`: Auth, Firestore e Functions emulados. O projeto de
produção não é tocado e não existe cobrança — dá pra apertar o botão à vontade.
Precisa de Java instalado (o emulador do Firestore roda na JVM).

```bash
# terminal 1 — emuladores + página servida em http://127.0.0.1:8090/checkin/ (ou a porta que o script imprimir)
./tool/dev_emulators.sh

# terminal 2 — contas puras: semana, janela, corte das filas
cd functions && npm test

# terminal 2 — corrida de verdade, contra os emuladores
node tool/race_test.mjs
```

No login, o emulador abre uma tela falsa do Google: escolha **Add new account**,
invente um e-mail e entre. Para testar o painel, crie um documento em
`rdr_writers` com esse e-mail como id, pela interface em
http://127.0.0.1:4000/firestore.

**O que `race_test.mjs` cobre.** Os testes de `functions/test` não conseguem
tocar no motivo de todo o desenho existir: o que acontece quando muita gente
aperta o botão no mesmo instante. Isso só aparece com escritas concorrentes de
verdade.

| Cenário | O que precisa ser verdade |
| --- | --- |
| 30 inscrições simultâneas | um documento por chamada aceita, sem duplicata, **sem empate de horário** |
| 20 cliques da mesma conta ao mesmo tempo | uma vaga só, e o limite por conta entra em ação |
| Troca de linha para gol | quem pediu o gol antes continua na frente |
| Cancelamento | a fila anda sem nada ser regravado |
| Função inexistente, nome vazio | recusado, não corrigido por conta própria |
| Chamada sem login | recusada |

O empate de horário é o que mais importa ali. Dois `createdAt` iguais
significariam duas pessoas na mesma posição, e aí a página e o painel poderiam
desempatar diferente, mostrando listas que não batem.

**O que o teste local não cobre:**

- **App Check.** O emulador não valida token de reCAPTCHA, então a página
  desliga o App Check em `localhost`. A proteção contra script só existe de
  verdade em produção, depois do passo 1 da publicação.
- **Content-Security-Policy.** A página local é servida por um servidor estático
  simples, não pelo emulador de Hosting, porque a CSP de produção — corretamente
  — não libera conexão com `127.0.0.1` e bloquearia os emuladores. Confira a
  política real depois do deploy com `./tool/check_checkin_headers.sh`.
- **Kill switch de faturamento.** Depende da API de faturamento do Google; não
  há como exercitar fora da nuvem.

### Publicar pela primeira vez

A ordem importa: as duas primeiras etapas são o que impede o endpoint de nascer
aberto, e a quarta é o que impede a fatura de crescer sem teto.

1. **App Check.** No Console: *Compilação > App Check > Apps*, registre o app
   Web com o provedor reCAPTCHA v3. Cole a chave do site em
   `painel/checkin/appcheck-config.js`. Em *App Check > APIs*, marque **Cloud
   Functions** como **Aplicado**. Sem isso a página avisa no console e toda
   chamada volta recusada.
2. **Domínios do reCAPTCHA.** Autorize `racha-dos-ruins.web.app` e
   `racha-dos-ruins.firebaseapp.com` nas configurações da chave.
3. **Plano Blaze.** As Cloud Functions exigem faturamento ativo. O uso deste
   check-in cabe folgado na cota gratuita; o risco não é o uso normal, é o
   abuso — por isso a etapa seguinte.
4. **Kill switch de faturamento.** Ver a seção abaixo. Faça antes de divulgar a
   página, não depois.
5. **Regras:** `./tool/deploy_rules.sh`
6. **Funções:** `./tool/deploy_functions.sh`
7. **Site:** `./tool/deploy_site.sh`
8. **Confira os cabeçalhos:** `./tool/check_checkin_headers.sh`
9. **TTL.** Em *Firestore > TTL*, crie políticas no campo `expiresAt` para
   `checkin_rate` e `checkin_ip`. Sem isso os contadores de limite ficam no
   banco para sempre.

### Kill switch de faturamento

O Google não oferece teto de gasto de verdade: orçamento é só alerta por e-mail,
e a cobrança continua correndo. O que existe aqui é um corte automático.

**O que acontece ao disparar:** o projeto é desvinculado da conta de faturamento
e volta ao plano Spark. As Cloud Functions param, então o check-in deixa de
aceitar inscrição. Firestore e Hosting continuam de pé dentro da cota gratuita,
então o placar e a lista já existente seguem visíveis. **Religar é manual**, no
Console, em *Faturamento > Vincular conta*.

É um corte bruto de propósito — a alternativa é uma fatura que ninguém está
olhando às três da manhã.

```bash
PROJETO=racha-dos-ruins

# 1. Tópico que recebe o aviso de orçamento
gcloud pubsub topics create rdr-billing-alerts --project "$PROJETO"

# 2. Orçamento apontando para o tópico
#    Console: Faturamento > Orçamentos e alertas > Criar orçamento
#    - valor: o teto que você aceita (ex.: R$ 5)
#    - alertas em 50%, 90% e 100%
#    - em "Gerenciar notificações", marque o tópico rdr-billing-alerts
#    A função só corta em 100%; os alertas menores servem pra avisar você.

# 3. Permitir que a função desligue o faturamento
CONTA_FATURAMENTO="$(gcloud beta billing projects describe "$PROJETO" \
  --format='value(billingAccountName)' | sed 's|billingAccounts/||')"
SERVICO="$(gcloud projects describe "$PROJETO" --format='value(projectNumber)')-compute@developer.gserviceaccount.com"

gcloud beta billing accounts add-iam-policy-binding "$CONTA_FATURAMENTO" \
  --member="serviceAccount:$SERVICO" \
  --role=roles/billing.projectManager
```

Sem o passo 3 a função dispara, grava o registro em `checkin_audit`, e falha ao
cortar — o log mostra erro de permissão.

### Segundo cinto: cotas de API

O kill switch reage ao gasto, que o faturamento só apura com algumas horas de
atraso. Para limitar o estrago nesse intervalo, dá pra travar a torneira em
*Console > IAM e administrador > Cotas*, reduzindo as cotas diárias de gravação
do Firestore e de invocações do Cloud Run para algo bem acima do racha e bem
abaixo de uma fatura. Ao bater o limite, o check-in recusa inscrição até o dia
seguinte — inclusive de quem é legítimo.

`maxInstances: 10` já está no código e limita a concorrência a cerca de 800
chamadas simultâneas, muito acima do racha.

### Manutenção

- **Limpeza do Artifact Registry.** Cada deploy de função guarda uma imagem. A
  cota gratuita é de 0,5 GB e o acúmulo é o único item que realmente pode virar
  centavos por mês. Em *Artifact Registry > gcf-artifacts*, crie uma política de
  limpeza que mantenha as três versões mais recentes.
- **Auditoria.** `checkin_audit` não é visível pelo painel de propósito — um log
  que o próprio auditado pudesse abrir não serve de prova. Consulte pelo Console
  do Firestore ou pelo Admin SDK.

```bash
# testes das partes puras (semana, janela, corte da fila)
cd functions && npm test
```

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
