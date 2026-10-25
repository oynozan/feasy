#!/usr/bin/env bash
# Creates a wallet and appends NAME_PK / NAME_ADDR to the repo .env
set -euo pipefail
NAME="${1:?usage: scripts/new-wallet.sh NAME}"
ENV_FILE="$(dirname "$0")/../.env"
touch "$ENV_FILE"
if grep -q "^${NAME}_PK=" "$ENV_FILE"; then
    echo "$NAME already exists in .env" >&2
    exit 1
fi
OUT="$(cast wallet new --json)"
ADDR="$(echo "$OUT" | sed -n 's/.*"address": *"\([^"]*\)".*/\1/p')"
PK="$(echo "$OUT" | sed -n 's/.*"private_key": *"\([^"]*\)".*/\1/p')"
printf '%s_PK=%s\n%s_ADDR=%s\n' "$NAME" "$PK" "$NAME" "$ADDR" >> "$ENV_FILE"
echo "$NAME $ADDR"
