#!/usr/bin/env bash
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
TMP_ROOT=$(fm_test_tmproot telemetry)
FILE="$TMP_ROOT/telemetry.jsonl"
CLI="$ROOT/bin/fm-telemetry.sh"
export FM_TELEMETRY=1 FM_TELEMETRY_FILE="$FILE" FM_TELEMETRY_MAX_BYTES=4096 FM_TELEMETRY_KEEP_FILES=2

"$CLI" emit --event spawn --task task-1 --run run-1 --model opus --effort high --input-tokens 12 --usage-source provider
"$CLI" emit --event spawn --task task-1 --run run-1 --idempotency-key launch-1 --source 'Bearer secret' --signal 'token=hidden'
"$CLI" emit --event spawn --task task-1 --run run-1 --idempotency-key launch-1
[ "$(jq -s length "$FILE")" -eq 2 ] || fail "telemetry emit or idempotency failed"
[ "$(jq -s -r '.[0].usage.input_tokens' "$FILE")" = 12 ] || fail "supported usage signal missing"
[ "$(jq -s -r '.[1] | has("usage")' "$FILE")" = false ] || fail "unsupported usage was fabricated"
! jq -e 'select(.source? | contains("secret"))' "$FILE" >/dev/null 2>&1 || fail "secret was not redacted"
SUMMARY=$("$CLI" summary "$FILE")
[ "$(printf '%s' "$SUMMARY" | jq -r .events)" -eq 2 ] || fail "offline summary failed"
FM_TELEMETRY_MAX_BYTES=1 "$CLI" emit --event wake --task task-1 --run run-1 --idempotency-key wake-1
[ -s "$FILE.1" ] || fail "telemetry rotation did not retain the previous segment"
FM_TELEMETRY=0 "$CLI" emit --event disabled --task task-1
[ "$(jq -s length "$FILE")" -eq 1 ] || fail "disabled telemetry wrote a record"
pass "private JSONL telemetry emits, redacts, deduplicates, bounds usage, and reads offline"
