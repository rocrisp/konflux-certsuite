#!/usr/bin/env bash
set -euo pipefail

# Runs certsuite test suites against the deployed operator.
# Iterates over comma-separated labels and runs each suite.

CERTSUITE_LABELS="${CERTSUITE_LABELS:-}"
CERTSUITE_CONFIG="${CERTSUITE_CONFIG:-/workspace/certsuite_config.yml}"
RESULTS_DIR="${RESULTS_DIR:-/workspace/results}"
CERTSUITE_IMAGE="${CERTSUITE_IMAGE:-quay.io/redhat-best-practices-for-k8s/certsuite:latest}"

mkdir -p "${RESULTS_DIR}"

if [[ ! -f "${CERTSUITE_CONFIG}" ]]; then
  echo "ERROR: Certsuite config not found at ${CERTSUITE_CONFIG}" >&2
  exit 1
fi

echo "[$(date -u +%FT%T.%3NZ)] Config: ${CERTSUITE_CONFIG}"

OVERALL_EXIT=0

run_suite() {
  local label="$1"
  local suite_dir="$2"
  mkdir -p "${suite_dir}"

  local label_args=()
  if [[ -n "${label}" ]]; then
    label_args=(--label-filter "${label}")
  fi

  set +e
  certsuite run \
    "${label_args[@]}" \
    --output-dir "${suite_dir}" \
    --config-file "${CERTSUITE_CONFIG}" \
    2>&1 | tee "${suite_dir}/certsuite.log"
  local rc=$?
  set -e

  if [[ -f "${suite_dir}/claim.json" ]]; then
    local total passed failed skipped
    total=$(jq '.claim.results | length' "${suite_dir}/claim.json" 2>/dev/null || echo "?")
    passed=$(jq '[.claim.results[] | select(.state == "passed")] | length' "${suite_dir}/claim.json" 2>/dev/null || echo "?")
    failed=$(jq '[.claim.results[] | select(.state == "failed")] | length' "${suite_dir}/claim.json" 2>/dev/null || echo "?")
    skipped=$(jq '[.claim.results[] | select(.state == "skipped")] | length' "${suite_dir}/claim.json" 2>/dev/null || echo "?")
    echo "[$(date -u +%FT%T.%3NZ)] Results: total=${total} passed=${passed} failed=${failed} skipped=${skipped}"
  else
    echo "[$(date -u +%FT%T.%3NZ)] WARNING: No claim.json generated"
  fi

  return ${rc}
}

if [[ -z "${CERTSUITE_LABELS}" ]]; then
  echo "[$(date -u +%FT%T.%3NZ)] Running all certsuite tests"
  run_suite "" "${RESULTS_DIR}/all" || OVERALL_EXIT=1
else
  echo "[$(date -u +%FT%T.%3NZ)] Running certsuite with labels: ${CERTSUITE_LABELS}"
  IFS=',' read -ra LABELS <<< "${CERTSUITE_LABELS}"

  for LABEL in "${LABELS[@]}"; do
    LABEL=$(echo "${LABEL}" | xargs)

    echo ""
    echo "================================================================"
    echo "[$(date -u +%FT%T.%3NZ)] Running certsuite suite: ${LABEL}"
    echo "================================================================"

    run_suite "${LABEL}" "${RESULTS_DIR}/${LABEL}" || OVERALL_EXIT=1
  done
fi

echo ""
echo "[$(date -u +%FT%T.%3NZ)] All suites complete. Overall exit code: ${OVERALL_EXIT}"
exit ${OVERALL_EXIT}
