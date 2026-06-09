#!/usr/bin/env bash
# Continuous Halmos verification runner for SapienVault symbolic properties.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
LOG_DIR="$ROOT/.halmos-loop"
INTERVAL="${HALMOS_LOOP_INTERVAL:-300}"
WATCH=0
[[ "${1:-}" == "--watch" ]] && WATCH=1
mkdir -p "$LOG_DIR"

run_once() {
    local run_id log latest build_rc=0 props_rc=0 inv_rc=0 props_passed=0 inv_passed=0
    run_id="$(date -u +%Y%m%dT%H%M%SZ)"
    log="$LOG_DIR/run-${run_id}.log"
    latest="$LOG_DIR/latest.json"

    {
        echo "=== Halmos verify run ${run_id} ==="
        date -u +%Y-%m-%dT%H:%M:%SZ
    } >"$log"

    echo "[build] FOUNDRY_PROFILE=halmos forge build" | tee -a "$log"
    if ! FOUNDRY_PROFILE=halmos forge build >>"$log" 2>&1; then
        build_rc=$?
    fi

    if [[ $build_rc -eq 0 ]]; then
        local props_log inv_log
        props_log="$(mktemp)"
        inv_log="$(mktemp)"
        if ! FOUNDRY_PROFILE=halmos halmos --forge-build-out out-halmos >"$props_log" 2>&1; then
            props_rc=$?
        fi
        cat "$props_log" >>"$log"
        props_passed="$(rg -c '^\[PASS\]' "$props_log" || echo 0)"

        if ! FOUNDRY_PROFILE=halmos halmos --contract SapienVaultHalmosInvariantTest --forge-build-out out-halmos >"$inv_log" 2>&1; then
            inv_rc=$?
        fi
        cat "$inv_log" >>"$log"
        inv_passed="$(rg -c '^\[PASS\]' "$inv_log" || echo 0)"
        rm -f "$props_log" "$inv_log"
    fi

    local status="pass"
    [[ $build_rc -ne 0 || $props_rc -ne 0 || $inv_rc -ne 0 ]] && status="fail"

    local payload
    payload="$(printf '{"run_id":"%s","status":"%s","build_rc":%d,"properties_rc":%d,"invariants_rc":%d,"properties_passed":%s,"invariants_passed":%s,"log":"%s"}' \
        "$run_id" "$status" "$build_rc" "$props_rc" "$inv_rc" "$props_passed" "$inv_passed" "$log")"
    printf '%s\n' "$payload" >"$latest"

    if [[ "$status" == "fail" ]]; then
        echo "HALMOS_LOOP_FAIL $payload"
        return 1
    fi
    echo "HALMOS_LOOP_PASS $payload"
    return 0
}

if [[ $WATCH -eq 1 ]]; then
    echo "Halmos watch: interval=${INTERVAL}s"
    while true; do
        run_once || exit 1
        sleep "$INTERVAL"
    done
else
    run_once
fi
