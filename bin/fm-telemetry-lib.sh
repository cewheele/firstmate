# shellcheck shell=bash

fm_telemetry_lock() {
  local lock=$1 i=0
  while ! mkdir "$lock" 2>/dev/null; do
    i=$((i + 1)); [ "$i" -lt 20 ] || return 1
    sleep 0.01
  done
  printf '%s\n' "$lock"
}

fm_telemetry_emit() (
  [ "${FM_TELEMETRY:-1}" != 0 ] || exit 0
  umask 077
  local file="$STATE/telemetry.jsonl" lock segment i size json
  mkdir -p "$STATE" || exit 0
  lock=$(fm_telemetry_lock "$file.lock") || exit 0
  trap 'rmdir "$lock" 2>/dev/null || true' EXIT
  for segment in "$file" "$file.1" "$file.2" "$file.3"; do
    [ ! -L "$segment" ] || exit 0
    if [ -e "$segment" ]; then
      [ -f "$segment" ] && chmod 600 "$segment" || exit 0
    fi
  done
  json=$(jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg signal "${1:0:64}" \
    '{schema:"fm-telemetry.v1",ts:$ts,event:"watch_cycle",signal:$signal,source:"watch-arm"}') || exit 0
  size=0
  if [ -f "$file" ]; then
    size=$(wc -c < "$file") || exit 0
  fi
  if [ "$((size + ${#json} + 1))" -gt 1048576 ]; then
    for i in 2 1; do
      if [ -f "$file.$i" ]; then
        mv -f "$file.$i" "$file.$((i + 1))" || exit 0
      fi
    done
    mv -f "$file" "$file.1" || exit 0
  fi
  printf '%s\n' "$json" >> "$file" || true
) >/dev/null 2>&1
