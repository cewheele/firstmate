# shellcheck shell=bash
# Optional private JSONL telemetry primitives. All public functions are best effort.

fm_telemetry_enabled() {
  case "${FM_TELEMETRY:-}" in
    1|on|true|yes) return 0 ;;
    *) return 1 ;;
  esac
}

fm_telemetry_file() {
  if [ -n "${FM_TELEMETRY_FILE:-}" ]; then
    printf '%s\n' "$FM_TELEMETRY_FILE"
  else
    printf '%s\n' "${STATE:-${FM_STATE_DIR:-state}}/telemetry.jsonl"
  fi
}

fm_telemetry_safe() {
  printf '%s' "${1:-}" | tr '\r\n\t' '   ' | sed -E \
    -e 's/(Bearer[[:space:]]+)[^[:space:]]+/\1[REDACTED]/Ig' \
    -e 's/((token|secret|password|api[_-]?key)[=:][[:space:]]*)[^[:space:]]+/\1[REDACTED]/Ig' \
    -e 's/([?&](token|secret|password|key)=[^&[:space:]]+)/[REDACTED]/Ig' | cut -c1-256
}

fm_telemetry_valid_token() {
  case "${1:-}" in ''|*[!A-Za-z0-9._:/-]*) return 1 ;; esac
}

fm_telemetry_lock() {
  local lock=$1 i=0
  while ! mkdir "$lock" 2>/dev/null; do
    i=$((i + 1)); [ "$i" -lt 20 ] || return 1
    sleep 0.01
  done
  printf '%s\n' "$lock"
}

fm_telemetry_rotate_locked() {
  local file=$1 max=$2 keep=$3 i
  [ -f "$file" ] || return 0
  [ "$(wc -c < "$file" 2>/dev/null | tr -d ' ')" -ge "$max" ] || return 0
  i=$((keep - 1))
  while [ "$i" -ge 1 ]; do
    [ -f "$file.$i" ] && mv -f "$file.$i" "$file.$((i + 1))" 2>/dev/null || true
    i=$((i - 1))
  done
  [ "$keep" -gt 0 ] && mv -f "$file" "$file.1" 2>/dev/null || rm -f "$file" 2>/dev/null || true
}

fm_telemetry_emit_json() {
  fm_telemetry_enabled || return 0
  local file lock dir max keep key duplicate
  file=$(fm_telemetry_file)
  dir=${file%/*}; [ "$dir" = "$file" ] && dir=.
  mkdir -p "$dir" 2>/dev/null || return 0
  max=${FM_TELEMETRY_MAX_BYTES:-1048576}; keep=${FM_TELEMETRY_KEEP_FILES:-3}
  case "$max" in ''|*[!0-9]*|0) max=1048576 ;; esac
  case "$keep" in ''|*[!0-9]*) keep=3 ;; esac
  lock=$(fm_telemetry_lock "$file.lock") || return 0
  key=$(printf '%s' "$1" | jq -r '.idempotency_key // empty' 2>/dev/null || true)
  if [ -n "$key" ] && [ -f "$file" ]; then
    duplicate=$(jq -e -s --arg key "$key" 'any(.[]; .idempotency_key == $key)' "$file" 2>/dev/null || true)
    [ "$duplicate" = true ] && { rmdir "$lock" 2>/dev/null || true; return 0; }
  fi
  fm_telemetry_rotate_locked "$file" "$max" "$keep"
  printf '%s\n' "$1" >> "$file" 2>/dev/null || true
  rmdir "$lock" 2>/dev/null || true
  return 0
}

fm_telemetry_emit() {
  local event=$1 task=$2 run=$3 signal=$4 model=$5 effort=$6 source=$7 key=$8
  local lib_dir
  lib_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  "$lib_dir/fm-telemetry.sh" emit --event "$event" --task "$task" --run "$run" \
    --signal "$signal" --model "$model" --effort "$effort" --source "$source" \
    --idempotency-key "$key" >/dev/null 2>&1 || true
}
