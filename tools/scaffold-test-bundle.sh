#!/usr/bin/env bash
set -euo pipefail

# Generates a boilerplate certsuite test bundle directory.
#
# Usage:
#   ./scaffold-test-bundle.sh --name my-operator --package my-operator \
#       --channel stable --output ./certsuite-test-bundle

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Generate a certsuite test bundle scaffold.

The test bundle describes how to deploy your operator's operands in a
software-only mode for certsuite testing. It does NOT include certsuite
configuration -- that is managed separately via the pipeline's
CERTSUITE_CONFIG_SECRET parameter.

Options:
  --name NAME          Bundle name (required)
  --namespace NS       Target namespace for operands (default: auto)
  --output DIR         Output directory (default: ./certsuite-test-bundle)
  -h, --help           Show this help message
EOF
}

NAME=""
NAMESPACE=""
OUTPUT="./certsuite-test-bundle"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)      NAME="$2"; shift 2 ;;
    --namespace) NAMESPACE="$2"; shift 2 ;;
    --output)    OUTPUT="$2"; shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "${NAME}" ]]; then
  echo "ERROR: --name is required"
  usage
  exit 1
fi

echo "Scaffolding test bundle: ${NAME}"
echo "  Output:  ${OUTPUT}"

mkdir -p "${OUTPUT}/operands" "${OUTPUT}/prerequisites"

# ── certsuite-test-bundle.yaml ─────────────────────────────────────────
cat > "${OUTPUT}/certsuite-test-bundle.yaml" <<EOF
apiVersion: certsuite.redhat.com/v1alpha1
kind: TestBundle
metadata:
  name: ${NAME}-test-bundle
  labels:
    app.kubernetes.io/part-of: ${NAME}
spec:
  namespace: "${NAMESPACE}"

  description: |
    Software-only test deployment of ${NAME} operands.
    Deploys without hardware or license dependencies.

  readiness:
    timeout: 300
    checks:
      - kind: Deployment
        name: ${NAME}-controller
      # Add more readiness checks as needed
EOF

# ── Example operand manifest ──────────────────────────────────────────
cat > "${OUTPUT}/operands/example-workload.yaml" <<EOF
# TODO: Replace with your operator's actual operand CRs and workloads.
#
# If your operator reconciles Custom Resources that create workloads,
# add the CR manifests here. If the operator does not auto-create
# workloads, add Deployment manifests directly.
#
# Key requirements:
#   - Use software-only configuration (no hardware, no licenses)
#   - Use UBI base images from registry.access.redhat.com
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${NAME}-workload
  labels:
    app: ${NAME}-workload
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${NAME}-workload
  template:
    metadata:
      labels:
        app: ${NAME}-workload
    spec:
      containers:
        - name: app
          image: registry.access.redhat.com/ubi9/ubi-minimal:latest
          command: ["sleep", "infinity"]
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 200m
              memory: 256Mi
EOF

# ── Example prerequisite ───────────────────────────────────────────────
cat > "${OUTPUT}/prerequisites/.gitkeep" <<EOF
EOF

echo ""
echo "Test bundle scaffolded at: ${OUTPUT}"
echo ""
echo "Next steps:"
echo "  1. Replace operands/example-workload.yaml with your operator's CRs"
echo "  2. Add any prerequisite Secrets/ConfigMaps to prerequisites/"
echo "  3. Validate: ./tools/validate-test-bundle.sh ${OUTPUT}"
echo "  4. Test locally against a cluster before onboarding to Konflux"
echo ""
echo "Note: Certsuite configuration (certsuite_config.yml) is managed"
echo "separately via the CERTSUITE_CONFIG_SECRET pipeline parameter."
