#!/usr/bin/env bash
# Deploy das Cloud Functions do check-in, com os testes como porteiro.
#
# As partes que decidem a semana e o corte da fila são puras e testáveis sem
# nuvem — então elas rodam aqui antes de qualquer coisa subir. Um erro no
# cálculo da quinta-feira só apareceria na quinta-feira, com todo mundo
# tentando entrar ao mesmo tempo; é tarde demais pra descobrir em produção.
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir/functions"

echo "== Instalando dependências =="
npx --yes --package node@22.11.0 npm install --no-audit --no-fund

echo
echo "== Testes =="
npx --yes --package node@22.11.0 node --test test/

echo
echo "== Deploy =="
cd "$project_dir"
npx --yes \
  --package node@22.11.0 \
  --package firebase-tools@15.30.0 \
  firebase deploy --only functions --project racha-dos-ruins
