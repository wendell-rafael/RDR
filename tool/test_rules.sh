#!/usr/bin/env bash
# Roda os testes das regras do Firestore no emulador. Nada toca a nuvem.
# Rode sempre que mudar o firestore.rules, ANTES de publicar.
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"

if [[ ! -d tool/rules-test/node_modules ]]; then
  echo "== Instalando dependências dos testes =="
  (cd tool/rules-test && npm install --no-audit --no-fund)
fi

npx --yes --package node@20.19.5 --package firebase-tools@15.30.0 \
  firebase emulators:exec --only firestore --project demo-rdr \
  "cd tool/rules-test && node --test"
