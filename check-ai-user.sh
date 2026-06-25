#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/.env"

PROXY_URL="http://localhost:4000/key/info"

if [ -z "${1:-}" ]; then
    echo "Usage: $0 <key_alias>"
    echo "Example: $0 dev_jdoe"
    exit 1
fi

TARGET="$1"

echo "Querying LiteLLM for: ${TARGET}"
echo "------------------------------------------------------------"

RESPONSE=$(curl -s -X GET "${PROXY_URL}?key_alias=${TARGET}" \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}")

if [[ "$RESPONSE" =~ \"max_budget\":([^, }]+) ]]; then MAX_B="${BASH_REMATCH[1]}"; else MAX_B="Unlimited"; fi
if [[ "$RESPONSE" =~ \"spend\":([^, }]+) ]]; then SPEND="${BASH_REMATCH[1]}"; else SPEND="0.00"; fi
if [[ "$RESPONSE" =~ \"rpm_limit\":([^, }]+) ]]; then RPM="${BASH_REMATCH[1]}"; else RPM="Default"; fi
if [[ "$RESPONSE" =~ \"tpm_limit\":([^, }]+) ]]; then TPM="${BASH_REMATCH[1]}"; else TPM="Default"; fi

echo "Alias:          ${TARGET}"
echo "Budget total:   \$${MAX_B}"
echo "Budget spent:   \$${SPEND}"
echo "Rate limit:     ${RPM} RPM / ${TPM} TPM"
echo "------------------------------------------------------------"
