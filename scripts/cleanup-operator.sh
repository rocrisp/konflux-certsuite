#!/usr/bin/env bash
set -euo pipefail

# Cleans up an OLM-managed operator and all its resources from the cluster.

INSTALL_NAMESPACE="${INSTALL_NAMESPACE:-}"
CLEANUP_TIMEOUT="${CLEANUP_TIMEOUT:-300}"

if [[ -z "${INSTALL_NAMESPACE}" && -f /workspace/install-namespace ]]; then
  INSTALL_NAMESPACE=$(cat /workspace/install-namespace)
fi

if [[ -z "${INSTALL_NAMESPACE}" ]]; then
  echo "[$(date -u +%FT%T.%3NZ)] No install namespace found. Nothing to clean up."
  exit 0
fi

echo "[$(date -u +%FT%T.%3NZ)] Cleaning up operator in namespace: ${INSTALL_NAMESPACE}"

# Read stored resource names
SUB_NAME=""
CSV_NAME=""
CATSRC_NAME=""
OG_NAME=""
[[ -f /workspace/subscription-name ]] && SUB_NAME=$(cat /workspace/subscription-name)
[[ -f /workspace/csv-name ]] && CSV_NAME=$(cat /workspace/csv-name)
[[ -f /workspace/catalogsource-name ]] && CATSRC_NAME=$(cat /workspace/catalogsource-name)
[[ -f /workspace/operatorgroup-name ]] && OG_NAME=$(cat /workspace/operatorgroup-name)

# Delete Subscription
if [[ -n "${SUB_NAME}" ]]; then
  echo "[$(date -u +%FT%T.%3NZ)] Deleting Subscription: ${SUB_NAME}"
  oc delete subscription "${SUB_NAME}" -n "${INSTALL_NAMESPACE}" --ignore-not-found --timeout=60s || true
fi

# Delete CSV
if [[ -n "${CSV_NAME}" ]]; then
  echo "[$(date -u +%FT%T.%3NZ)] Deleting CSV: ${CSV_NAME}"
  oc delete csv "${CSV_NAME}" -n "${INSTALL_NAMESPACE}" --ignore-not-found --timeout=60s || true
fi

# Delete CatalogSource
if [[ -n "${CATSRC_NAME}" ]]; then
  echo "[$(date -u +%FT%T.%3NZ)] Deleting CatalogSource: ${CATSRC_NAME}"
  oc delete catalogsource "${CATSRC_NAME}" -n "${INSTALL_NAMESPACE}" --ignore-not-found --timeout=60s || true
fi

# Delete OperatorGroup
if [[ -n "${OG_NAME}" ]]; then
  echo "[$(date -u +%FT%T.%3NZ)] Deleting OperatorGroup: ${OG_NAME}"
  oc delete operatorgroup "${OG_NAME}" -n "${INSTALL_NAMESPACE}" --ignore-not-found --timeout=60s || true
fi

# Delete CRDs installed by this operator
echo "[$(date -u +%FT%T.%3NZ)] Deleting operator-installed CRDs..."
CRDS=$(oc get crd -l "olm.managed=true" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
for CRD in ${CRDS}; do
  echo "  Deleting CRD: ${CRD}"
  oc delete crd "${CRD}" --ignore-not-found --timeout=60s || true
done

# Delete operand namespace if it was created separately
if [[ -f /workspace/operand-namespace ]]; then
  OPERAND_NS=$(cat /workspace/operand-namespace)
  if [[ "${OPERAND_NS}" != "${INSTALL_NAMESPACE}" ]]; then
    echo "[$(date -u +%FT%T.%3NZ)] Deleting operand namespace: ${OPERAND_NS}"
    oc delete namespace "${OPERAND_NS}" --ignore-not-found --timeout="${CLEANUP_TIMEOUT}s" || true
  fi
fi

# Delete install namespace
echo "[$(date -u +%FT%T.%3NZ)] Deleting install namespace: ${INSTALL_NAMESPACE}"
oc delete namespace "${INSTALL_NAMESPACE}" --ignore-not-found --timeout="${CLEANUP_TIMEOUT}s" || true

echo "[$(date -u +%FT%T.%3NZ)] Cleanup complete"
