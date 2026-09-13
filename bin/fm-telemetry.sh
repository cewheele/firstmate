#!/usr/bin/env bash
# Private, optional, offline-readable telemetry for firstmate lifecycle boundaries.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/fm-telemetry-lib.sh
. "$SCRIPT_DIR/fm-telemetry-lib.sh"

die() { printf 'fm-telemetry: %s\n' "$1" >&2; exit 2; }
cmd=${1:-}; [ -n "$cmd" ] || die "expected emit, read, or summary"
shift
case "$cmd" in
  read)
    file=${1:-$(fm_telemetry_file)}
    [ -f "$file" ] && jq -c . "$file" 2>/dev/null || true
    i=1; while [ -f "$file.$i" ]; do jq -c . "$file.$i" 2>/dev/null || true; i=$((i + 1)); done
    exit 0 ;;
  summary)
    file=${1:-$(fm_telemetry_file)}
    [ -f "$file" ] || { printf '{"events":0,"duration_ms":0,"input_tokens":0,"output_tokens":0}\n'; exit 0; }
    files=("$file"); i=1; while [ -f "$file.$i" ]; do files+=("$file.$i"); i=$((i + 1)); done
    jq -s '{events:length, by_event:(group_by(.event)|map({key:.[0].event,value:length})|from_entries), duration_ms:(map(.duration_ms // 0)|add // 0), input_tokens:(map(.usage.input_tokens // 0)|add // 0), output_tokens:(map(.usage.output_tokens // 0)|add // 0)}' "${files[@]}" 2>/dev/null || true
    exit 0 ;;
  emit) ;;
  *) die "unknown command: $cmd" ;;
esac

event='' task='' run='' signal='' model='' effort='' source='' usage_source='' idempotency='' duration='' input='' output=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --event) event=${2-}; shift 2 ;; --task) task=${2-}; shift 2 ;; --run) run=${2-}; shift 2 ;;
    --signal) signal=${2-}; shift 2 ;; --model) model=${2-}; shift 2 ;; --effort) effort=${2-}; shift 2 ;;
    --source) source=${2-}; shift 2 ;; --usage-source) usage_source=${2-}; shift 2 ;;
    --idempotency-key) idempotency=${2-}; shift 2 ;; --duration-ms) duration=${2-}; shift 2 ;;
    --input-tokens) input=${2-}; shift 2 ;; --output-tokens) output=${2-}; shift 2 ;;
    *) die "unknown option: $1" ;;
  esac
done
fm_telemetry_valid_token "$event" || die "event is required and must be a safe token"
for value in "$task" "$run" "$idempotency"; do
  [ -z "$value" ] || fm_telemetry_valid_token "$value" || die "invalid telemetry identifier"
done
signal=$(fm_telemetry_safe "$signal"); model=$(fm_telemetry_safe "$model"); effort=$(fm_telemetry_safe "$effort")
source=$(fm_telemetry_safe "$source"); usage_source=$(fm_telemetry_safe "$usage_source")
for value in "$duration" "$input" "$output"; do
  [ -z "$value" ] || case "$value" in ''|*[!0-9]*) die "numeric signal is invalid" ;; esac
done
json=$(jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg event "$event" \
  --arg task "$task" --arg run "$run" --arg signal "$signal" --arg model "$model" \
  --arg effort "$effort" --arg source "$source" --arg usage_source "$usage_source" \
  --arg idempotency "$idempotency" --argjson duration "${duration:-null}" --argjson input "${input:-null}" --argjson output "${output:-null}" \
  '{schema:"fm-telemetry.v1",ts:$ts,event:$event} + (if $task!="" then {task_id:$task} else {} end) + (if $run!="" then {run_id:$run} else {} end) + (if $signal!="" then {signal:$signal} else {} end) + (if $model!="" then {model:$model} else {} end) + (if $effort!="" then {effort:$effort} else {} end) + (if $source!="" then {source:$source} else {} end) + (if $idempotency!="" then {idempotency_key:$idempotency} else {} end) + (if $duration != null then {duration_ms:$duration} else {} end) + (if $usage_source!="" and ($input != null or $output != null) then {usage_source:$usage_source,usage:({} + (if $input != null then {input_tokens:$input} else {} end) + (if $output != null then {output_tokens:$output} else {} end))} else {} end)') || exit 0
fm_telemetry_emit_json "$json"
