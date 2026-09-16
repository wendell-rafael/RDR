#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"

npx --yes \
  --package node@20.19.5 \
  --package firebase-tools@15.30.0 \
  firebase deploy --only hosting --project racha-dos-ruins
