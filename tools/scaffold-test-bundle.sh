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

Options:
  --name NAME          Bundle name (required)
  --package PACKAGE    OLM package name (required)
  --channel CHANNEL    OLM channel (default: stable)
  --namespace NS       Target namespace for operands (default: auto)
  --output DIR         Output directory (default: ./certsuite-test-bundle)
  --crd-suffix SUFFIX  CRD name suffix for certsuite config (optional)
  -h, --help           Show this help message
EOF
}

NAME=""
PACKAGE=""
CHANNEL="stable"
NAMESPACE=""
OUTPUT="./certsuite-test-bundle"
CRD_SUFFIX=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)      NAME="$2"; shift 2 ;;
    --package)   PACKAGE="$2"; shift 2 ;;
    --channel)   CHANNEL="$2"; shift 2 ;;
    --namespace) NAMESPACE="$2"; shift 2 ;;
    --output)    OUTPUT="$2"; shift 2 ;;
    --crd-suffix) CRD_SUFFIX="$2"; shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "${NAME}" || -z "${PACKAGE}" ]]; then
  echo "ERROR: --name and --package are required"
  usage
  exit 1
fi

echo "Scaffolding test bundle: ${NAME}"
echo "  Package: ${PACKAGE}"
echo "  Channel: ${CHANNEL}"
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
    Software-only test deployment of ${NAME} for certsuite testing.
    This bundle deploys operands without hardware or license dependencies.

  operator:
    packageName: ${PACKAGE}
    channel: ${CHANNEL}

  readiness:
    timeout: 300
    checks:
      - kind: Deployment
        name: ${NAME}-controller
      # Add more readiness checks as needed

  certsuite:
    labels:
      - "networking"
      - "lifecycle"
      - "platform-alteration"
      - "observability"
      - "access-control"
EOF

# ── certsuite_config.yml ───────────────────────────────────────────────
CRD_BLOCK=""
if [[ -n "${CRD_SUFFIX}" ]]; then
  CRD_BLOCK="
targetCrdFilters:
  - nameSuffix: \"${CRD_SUFFIX}\"
    scalable: false"
fi

cat > "${OUTPUT}/certsuite_config.yml" <<EOF
# Certsuite configuration for ${NAME}
# See: https://redhat-best-practices-for-k8s.github.io/certsuite/configuration/
targetNameSpaces:
  - name: ""  # Filled in by the pipeline

podsUnderTestLabels:
  - "redhat-best-practices-for-k8s.com/generic: target"

operatorsUnderTestLabels:
  - "redhat-best-practices-for-k8s.com/operator: target"
${CRD_BLOCK}
EOF

# ── Example operand Deployment ─────────────────────────────────────────
cat > "${OUTPUT}/operands/example-workload.yaml" <<EOF
# TODO: Replace with your operator's actual operand CRs and workloads.
#
# If your operator reconciles Custom Resources that create workloads,
# add the CR manifests here. If the operator does not auto-create
# workloads, add Deployment manifests directly.
#
# Key requirements:
#   - All pods must have the certsuite discovery label
#   - Use software-only configuration (no hardware, no licenses)
#   - Use UBI base images from registry.access.redhat.com
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${NAME}-workload
  labels:
    app: ${NAME}-workload
    redhat-best-practices-for-k8s.com/generic: target
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${NAME}-workload
  template:
    metadata:
      labels:
        app: ${NAME}-workload
        redhat-best-practices-for-k8s.com/generic: target
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
          securityContext:
            runAsNonRoot: true
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
            seccompProfile:
              type: RuntimeDefault
EOF

# ── Example prerequisite ───────────────────────────────────────────────
cat > "${OUTPUT}/prerequisites/.gitkeep" <<EOF
EOF

echo ""
echo "Test bundle scaffolded at: ${OUTPUT}"
echo ""
echo "Next steps:"
echo "  1. Replace operands/example-workload.yaml with your operator's CRs"
echo "  2. Update certsuite_config.yml with your labels and CRD filters"
echo "  3. Add any prerequisite Secrets/ConfigMaps to prerequisites/"
echo "  4. Validate: ./tools/validate-test-bundle.sh ${OUTPUT}"
echo "  5. Test locally against a cluster before onboarding to Konflux"
