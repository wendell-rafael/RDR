#!/usr/bin/env bash
# Verifica que /racha/public (lido sem autenticação pelo site) nunca carrega
# campos privados — nível/estrelas de jogador ('stars') ou a média do time
# derivada dele ('averageStars'). As regras do Firestore não conseguem
# validar isso (não iteram listas de objetos), então essa é a única rede de
# segurança: roda antes/depois de mexer em backup_service.dart ou admin.js,
# ou periodicamente contra produção.
#
# Uso: tool/check_public_doc.sh [project-id] [api-key]
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"

project="${1:-racha-dos-ruins}"
api_key="${2:-$(sed -n "s/.*apiKey: *'\([^']*\)'.*/\1/p" painel/firebase-config.js)}"

if [[ -z "$api_key" ]]; then
  echo "Não achei a apiKey. Passe como segundo argumento ou confira painel/firebase-config.js." >&2
  exit 2
fi

url="https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/racha/public?key=${api_key}"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
curl -sS "$url" -o "$tmp"

python3 - "$tmp" <<'EOF'
import json, sys

with open(sys.argv[1], encoding="utf-8") as f:
    body = json.load(f)
if "error" in body:
    print(f"Falha ao ler /racha/public: {body['error'].get('message', body['error'])}", file=sys.stderr)
    sys.exit(2)

forbidden = {"stars", "averageStars"}
hits = []

def walk(node, path):
    if isinstance(node, dict):
        for key, value in node.items():
            if key in forbidden:
                hits.append(f"{path}.{key}")
            walk(value, f"{path}.{key}")
    elif isinstance(node, list):
        for i, item in enumerate(node):
            walk(item, f"{path}[{i}]")

walk(body.get("fields", {}), "fields")

if hits:
    print("FALHOU: campo privado encontrado em /racha/public (deveria ser só espelho público, sem dado sensível):")
    for hit in hits:
        print(f"  - {hit}")
    sys.exit(1)

print("OK: /racha/public não carrega 'stars' nem 'averageStars'.")
EOF
