#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Validating Bicep files ==="

# Build main template (this also validates all referenced modules)
echo "Building infra/main.bicep..."
az bicep build --file "$ROOT_DIR/infra/main.bicep" --stdout > /dev/null
echo "  OK"

# Validate each parameter file
for env in dev acc prod; do
  PARAM_FILE="$ROOT_DIR/infra/main.${env}.bicepparam"
  if [ -f "$PARAM_FILE" ]; then
    echo "Validating parameters: main.${env}.bicepparam..."
    az bicep build-params --file "$PARAM_FILE" --stdout > /dev/null
    echo "  OK"
  fi
done

echo ""
echo "=== All validations passed ==="
