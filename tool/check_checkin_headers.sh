#!/usr/bin/env bash
# Confere que cada rota recebeu a política de segurança certa.
#
# O firebase.json tem dois blocos de cabeçalho que casam com /checkin: o '**'
# geral e o específico. A precedência entre blocos que se sobrepõem não está
# cravada na documentação, então em vez de confiar, mede-se.
#
# Esperado:
#   /            -> CSP restrita, sem identitytoolkit (a landing não faz login)
#   /checkin/    -> CSP com identitytoolkit e cloudfunctions
set -euo pipefail

site="${1:-https://racha-dos-ruins.web.app}"
fail=0

csp_of() {
  curl -sS -D - -o /dev/null "$1" | tr -d '\r' \
    | awk -F': ' 'tolower($1)=="content-security-policy"{ $1=""; sub(/^ /,""); print }'
}

landing="$(csp_of "$site/")"
checkin="$(csp_of "$site/checkin/")"

echo "== / =="
echo "${landing:-<sem CSP>}"
echo
echo "== /checkin/ =="
echo "${checkin:-<sem CSP>}"
echo

if [[ -z "$landing" ]]; then
  echo "FALHOU: a landing page ficou sem Content-Security-Policy." >&2
  fail=1
elif grep -q 'identitytoolkit' <<<"$landing"; then
  echo "FALHOU: a landing page recebeu a CSP do check-in — o bloco '**' foi sobrescrito." >&2
  fail=1
fi

if [[ -z "$checkin" ]]; then
  echo "FALHOU: /checkin/ ficou sem Content-Security-Policy." >&2
  fail=1
elif ! grep -q 'identitytoolkit' <<<"$checkin" || ! grep -q 'cloudfunctions' <<<"$checkin"; then
  echo "FALHOU: /checkin/ recebeu a CSP restrita — login e check-in vão ser bloqueados." >&2
  echo "Corrija movendo o bloco '/checkin/**' no firebase.json ou publique o check-in num site próprio." >&2
  fail=1
fi

if [[ "$fail" -eq 0 ]]; then
  echo "OK: cada rota com a política esperada."
fi
exit "$fail"
