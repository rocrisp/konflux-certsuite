#!/usr/bin/env bash
set -euo pipefail

# Runs certsuite test suites against the deployed operator.
# Iterates over comma-separated labels and runs each suite.

CERTSUITE_LABELS="${CERTSUITE_LABELS:?CERTSUITE_LABELS is required}"
CERTSUITE_CONFIG="${CERTSUITE_CONFIG:-/workspace/certsuite_config.yml}"
RESULTS_DIR="${RESULTS_DIR:-/workspace/results}"
CERTSUITE_IMAGE="${CERTSUITE_IMAGE:-quay.io/redhat-best-practices-for-k8s/certsuite:latest}"

mkdir -p "${RESULTS_DIR}"

if [[ ! -f "${CERTSUITE_CONFIG}" ]]; then
  echo "ERROR: Certsuite config not found at ${CERTSUITE_CONFIG}" >&2
  exit 1
fi

echo "[$(date -u +%FT%T.%3NZ)] Running certsuite with labels: ${CERTSUITE_LABELS}"
echo "[$(date -u +%FT%T.%3NZ)] Config: ${CERTSUITE_CONFIG}"

IFS=',' read -ra LABELS <<< "${CERTSUITE_LABELS}"

OVERALL_EXIT=0

for LABEL in "${LABELS[@]}"; do
  LABEL=$(echo "${LABEL}" | xargs)  # trim whitespace
  SUITE_DIR="${RESULTS_DIR}/${LABEL}"
  mkdir -p "${SUITE_DIR}"

  echo ""
  echo "================================================================"
  echo "[$(date -u +%FT%T.%3NZ)] Running certsuite suite: ${LABEL}"
  echo "================================================================"

  set +e
  certsuite run \
    --label-filter "${LABEL}" \
    --output-dir "${SUITE_DIR}" \
    --config-file "${CERTSUITE_CONFIG}" \
    2>&1 | tee "${SUITE_DIR}/certsuite.log"
  SUITE_EXIT=$?
  set -e

  if [[ ${SUITE_EXIT} -ne 0 ]]; then
    echo "[$(date -u +%FT%T.%3NZ)] WARNING: Suite '${LABEL}' exited with code ${SUITE_EXIT}"
    OVERALL_EXIT=1
  else
    echo "[$(date -u +%FT%T.%3NZ)] Suite '${LABEL}' completed successfully"
  fi

  # Verify claim.json was generated
  if [[ -f "${SUITE_DIR}/claim.json" ]]; then
    TOTAL=$(jq '.claim.results | length' "${SUITE_DIR}/claim.json" 2>/dev/null || echo "?")
    PASSED=$(jq '[.claim.results[] | select(.state == "passed")] | length' "${SUITE_DIR}/claim.json" 2>/dev/null || echo "?")
    FAILED=$(jq '[.claim.results[] | select(.state == "failed")] | length' "${SUITE_DIR}/claim.json" 2>/dev/null || echo "?")
    SKIPPED=$(jq '[.claim.results[] | select(.state == "skipped")] | length' "${SUITE_DIR}/claim.json" 2>/dev/null || echo "?")
    echo "[$(date -u +%FT%T.%3NZ)] Results: total=${TOTAL} passed=${PASSED} failed=${FAILED} skipped=${SKIPPED}"
  else
    echo "[$(date -u +%FT%T.%3NZ)] WARNING: No claim.json generated for suite '${LABEL}'"
  fi
done

echo ""
echo "[$(date -u +%FT%T.%3NZ)] All suites complete. Overall exit code: ${OVERALL_EXIT}"
exit ${OVERALL_EXIT}
