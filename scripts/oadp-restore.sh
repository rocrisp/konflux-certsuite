#!/usr/bin/env bash
set -euo pipefail

# Creates an OADP Restore CR from a named backup and polls until complete.

BACKUP_NAME="${BACKUP_NAME:?BACKUP_NAME is required}"
OADP_NAMESPACE="${OADP_NAMESPACE:-openshift-adp}"
RESTORE_TIMEOUT="${RESTORE_TIMEOUT:-900}"

RESTORE_NAME="${BACKUP_NAME}-restore-$(date +%s)"

echo "[$(date -u +%FT%T.%3NZ)] Creating OADP Restore '${RESTORE_NAME}' from backup '${BACKUP_NAME}'"

oc apply -f - <<EOF
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: ${RESTORE_NAME}
  namespace: ${OADP_NAMESPACE}
spec:
  backupName: ${BACKUP_NAME}
  existingResourcePolicy: update
  includedResources:
    - '*'
  restorePVs: true
EOF

echo "[$(date -u +%FT%T.%3NZ)] Waiting for restore to complete (timeout: ${RESTORE_TIMEOUT}s)"

ELAPSED=0
POLL_INTERVAL=10

while true; do
  PHASE=$(oc get restore "${RESTORE_NAME}" -n "${OADP_NAMESPACE}" \
    -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

  case "${PHASE}" in
    Completed)
      echo "[$(date -u +%FT%T.%3NZ)] Restore completed successfully"
      exit 0
      ;;
    PartiallyFailed)
      echo "[$(date -u +%FT%T.%3NZ)] WARNING: Restore partially failed. Continuing."
      WARNINGS=$(oc get restore "${RESTORE_NAME}" -n "${OADP_NAMESPACE}" \
        -o jsonpath='{.status.warnings}' 2>/dev/null || echo "0")
      ERRORS=$(oc get restore "${RESTORE_NAME}" -n "${OADP_NAMESPACE}" \
        -o jsonpath='{.status.errors}' 2>/dev/null || echo "0")
      echo "[$(date -u +%FT%T.%3NZ)] Warnings: ${WARNINGS}, Errors: ${ERRORS}"
      exit 0
      ;;
    Failed|FailedValidation)
      echo "[$(date -u +%FT%T.%3NZ)] ERROR: Restore failed with phase '${PHASE}'"
      oc get restore "${RESTORE_NAME}" -n "${OADP_NAMESPACE}" -o yaml
      exit 1
      ;;
    *)
      echo "[$(date -u +%FT%T.%3NZ)] Restore phase: ${PHASE} (${ELAPSED}/${RESTORE_TIMEOUT}s)"
      ;;
  esac

  if [[ ${ELAPSED} -ge ${RESTORE_TIMEOUT} ]]; then
    echo "[$(date -u +%FT%T.%3NZ)] ERROR: Timed out waiting for restore after ${RESTORE_TIMEOUT}s"
    exit 1
  fi

  sleep ${POLL_INTERVAL}
  ELAPSED=$((ELAPSED + POLL_INTERVAL))
done
