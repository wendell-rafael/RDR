#!/usr/bin/env bash
# Deploy de firestore.rules com checagem obrigatória antes.
#
# `firebase deploy --dry-run` compila as regras, mas uma função/variável
# inexistente vira só um warning ([W]) — o dry-run "passa" mesmo assim, e um
# deploy real nesse estado nega toda leitura/escrita em produção (regra
# inválida = tudo cai no catch-all `if false`). Confirmado na prática ao
# testar se Firestore Rules v2 itera listas de objetos (não itera).
#
# Este script trata qualquer '[W]' na saída do dry-run como erro e recusa
# seguir pro deploy real.
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"

echo "== Validando firestore.rules (dry-run) =="
dry_run_status=0
dry_run_output="$(npx --yes --package node@20.19.5 --package firebase-tools@15.30.0 \
  firebase deploy --only firestore:rules --project racha-dos-ruins --dry-run 2>&1)" \
  || dry_run_status=$?
echo "$dry_run_output"

if [[ "$dry_run_status" -ne 0 ]] || echo "$dry_run_output" | grep -qE '\[W\]|\[E\]'; then
  echo
  echo "FALHOU: dry-run reportou warning/erro nas regras (ou saiu com erro) — não vou seguir pro deploy real." >&2
  echo "Revise firestore.rules antes de tentar de novo." >&2
  exit 1
fi

echo
echo "== Dry-run limpo, aplicando de verdade =="
npx --yes --package node@20.19.5 --package firebase-tools@15.30.0 \
  firebase deploy --only firestore:rules --project racha-dos-ruins
