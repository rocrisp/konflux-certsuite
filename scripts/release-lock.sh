#!/usr/bin/env bash
set -euo pipefail

# Releases the Kubernetes Lease-based mutex, but only if owned by this pipeline run.

LOCK_NAME="${LOCK_NAME:?LOCK_NAME is required}"
LOCK_NAMESPACE="${LOCK_NAMESPACE:-certsuite-locks}"
OWNER="${OWNER:?OWNER is required}"

echo "[$(date -u +%FT%T.%3NZ)] Attempting to release lock '${LOCK_NAME}' in namespace '${LOCK_NAMESPACE}'"

CURRENT_OWNER=$(oc get lease "${LOCK_NAME}" -n "${LOCK_NAMESPACE}" \
  -o jsonpath='{.spec.holderIdentity}' 2>/dev/null || echo "")

if [[ -z "${CURRENT_OWNER}" ]]; then
  echo "[$(date -u +%FT%T.%3NZ)] Lock does not exist or has no holder. Nothing to release."
  exit 0
fi

if [[ "${CURRENT_OWNER}" != "${OWNER}" ]]; then
  echo "[$(date -u +%FT%T.%3NZ)] Lock is held by '${CURRENT_OWNER}', not '${OWNER}'. Skipping release."
  exit 0
fi

oc delete lease "${LOCK_NAME}" -n "${LOCK_NAMESPACE}" --ignore-not-found
echo "[$(date -u +%FT%T.%3NZ)] Lock released successfully"
