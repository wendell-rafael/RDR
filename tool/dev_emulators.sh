#!/usr/bin/env bash
# Sobe os emuladores do Firebase e serve a página do check-in localmente.
#
# Nada aqui encosta na nuvem: Auth, Firestore e Functions rodam em 127.0.0.1, e
# o projeto de produção não é tocado. Dá pra apertar o botão à vontade.
#
# A página é servida por um servidor estático simples, não pelo emulador de
# Hosting, de propósito: o de Hosting aplicaria a Content-Security-Policy do
# firebase.json, que — corretamente — não libera conexão com 127.0.0.1 e
# bloquearia os emuladores. A CSP de verdade se confere depois do deploy, com
# ./tool/check_checkin_headers.sh.
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"

if [[ ! -d functions/node_modules ]]; then
  echo "== Instalando dependências das functions =="
  (cd functions && npm install --no-audit --no-fund)
fi

# 8000 é porta comum demais pra confiar que está livre — em algumas máquinas
# (e neste próprio ambiente de desenvolvimento) já tem outra coisa nela, e aí
# o navegador cai no serviço errado em vez da página, sem aviso nenhum. Testa
# antes de escolher.
static_port=8000
if command -v python3 >/dev/null && python3 -c "
import socket, sys
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sys.exit(0 if s.connect_ex(('127.0.0.1', $static_port)) == 0 else 1)
"; then
  static_port=8090
  echo "== Porta 8000 já está em uso por outra coisa; usando $static_port =="
fi

echo "== Servindo painel/ em http://127.0.0.1:$static_port =="
python3 -m http.server "$static_port" --directory painel --bind 127.0.0.1 >/dev/null 2>&1 &
static_pid=$!
trap 'kill "$static_pid" 2>/dev/null || true' EXIT

echo
echo "  Check-in:   http://127.0.0.1:$static_port/checkin/"
echo "  Painel:     http://127.0.0.1:$static_port/admin/"
echo "  Emuladores: http://127.0.0.1:4000"
echo
echo "No login, o emulador abre uma tela falsa do Google — escolha"
echo "\"Add new account\", invente um e-mail e entre. Nenhuma conta real é usada."
echo

npx --yes \
  --package node@22.11.0 \
  --package firebase-tools@15.30.0 \
  firebase emulators:start --only auth,functions,firestore --project racha-dos-ruins
