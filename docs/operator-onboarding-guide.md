# Operator Onboarding Guide

This guide walks operator owners through creating a **certsuite test
bundle**, testing it locally, and onboarding their operator to the
Konflux certsuite shared test pipeline.

## What Is a Test Bundle?

A test bundle is a directory in your operator's git repository that
contains everything needed to deploy a **software-only** version of
your operator's workloads for certsuite testing. "Software-only" means:

- No specialized hardware (SR-IOV NICs, GPUs, FPGAs)
- No license keys or entitlements
- No external service dependencies (cloud APIs, databases)
- No PersistentVolumes requiring specific storage classes

The goal is a portable, self-contained set of manifests that deploys
your operator's operands on any OpenShift cluster so that certsuite
can validate best-practices compliance.

## Bundle Directory Structure

```
certsuite-test-bundle/
  certsuite-test-bundle.yaml       # Required: bundle metadata
  certsuite_config.yml             # Required: certsuite configuration
  operands/                        # Required: operand manifests
    my-custom-resource.yaml        #   Your operator's CR instances
    deployment.yaml                #   Any additional workloads
    service.yaml                   #   Services, etc.
  prerequisites/                   # Optional: pre-deploy resources
    pull-secret.yaml               #   Secrets, ConfigMaps, etc.
```

## Step 1: Create the Bundle Manifest

Create `certsuite-test-bundle.yaml` at the root of your bundle directory:

```yaml
apiVersion: certsuite.redhat.com/v1alpha1
kind: TestBundle
metadata:
  name: my-operator-test-bundle
  labels:
    app.kubernetes.io/part-of: my-operator
spec:
  # Leave empty to use the operator's install namespace
  namespace: ""

  description: |
    Software-only test deployment of my-operator for certsuite.

  operator:
    packageName: my-operator       # Must match your OLM package name
    channel: stable                # Channel used for testing

  readiness:
    timeout: 300                   # Seconds to wait for operands
    checks:
      - kind: Deployment
        name: my-controller
      - kind: StatefulSet
        name: my-datastore

  certsuite:
    labels:
      - "networking"
      - "lifecycle"
      - "access-control"
```

## Step 2: Create Operand Manifests

Place Kubernetes manifests in the `operands/` directory. These are
applied with `oc apply -f operands/` after the operator is installed.

### Guidelines for Software-Only Operands

**Custom Resources**: Create minimal CR instances that your operator
will reconcile. Use test/development profiles if your operator supports
them:

```yaml
# operands/my-app.yaml
apiVersion: myoperator.example.com/v1
kind: MyApp
metadata:
  name: test-instance
  labels:
    redhat-best-practices-for-k8s.com/generic: target
spec:
  replicas: 1
  profile: test         # Use a lightweight profile
  storage:
    type: emptyDir      # Avoid PVC requirements
  features:
    hardware-offload: false
    external-auth: false
```

**Deployments**: If your operator doesn't auto-create workloads from
CRs, include explicit Deployments:

```yaml
# operands/workload.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-workload
  labels:
    app: my-workload
    redhat-best-practices-for-k8s.com/generic: target
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-workload
  template:
    metadata:
      labels:
        app: my-workload
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
```

**Important labels**: certsuite discovers workloads via labels. Make sure
your pods have the labels referenced in `certsuite_config.yml`:

- `redhat-best-practices-for-k8s.com/generic: target` for pods
- `redhat-best-practices-for-k8s.com/operator: target` for operator CSVs

### What to Avoid

| Avoid | Why | Alternative |
|-------|-----|-------------|
| PVCs with specific StorageClasses | May not exist on test cluster | Use `emptyDir` volumes |
| NodeSelectors for specialized hardware | Nodes won't have the hardware | Remove or use `preferredDuringScheduling` |
| External service endpoints | Not available in test env | Use mock services or in-cluster alternatives |
| License/entitlement Secrets | Not shareable | Disable features that require them |

Some operators legitimately require `hostNetwork`, privileged containers,
or other elevated permissions. Certsuite will flag these, but they can be
addressed with exceptions in cert-track-results. Do not change your
operator's actual requirements just to pass validation.

## Step 3: Create the Certsuite Configuration

Create `certsuite_config.yml` to tell certsuite which workloads to test:

```yaml
targetNameSpaces:
  - name: ""   # Filled in by the pipeline

podsUnderTestLabels:
  - "redhat-best-practices-for-k8s.com/generic: target"

operatorsUnderTestLabels:
  - "redhat-best-practices-for-k8s.com/operator: target"

targetCrdFilters:
  - nameSuffix: "myoperator.example.com"
    scalable: false
```

See the [certsuite configuration docs](https://redhat-best-practices-for-k8s.github.io/certsuite/configuration/)
for all available options.

## Step 4: Add Prerequisites (Optional)

If your operands need Secrets, ConfigMaps, or RBAC resources before
they can start, place them in a `prerequisites/` directory:

```yaml
# prerequisites/test-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-operator-test-config
data:
  mode: "test"
  log_level: "debug"
```

These are applied before the operand manifests.

## Step 5: Validate Locally

Use the provided validation tool to check your bundle before pushing:

```bash
# From the konflux-certsuite repository
./tools/validate-test-bundle.sh /path/to/your/certsuite-test-bundle
```

The tool checks:
- `certsuite-test-bundle.yaml` exists and has required fields
- `operands/` directory exists and contains at least one manifest
- `certsuite_config.yml` exists and is valid YAML
- Pod manifests include the required certsuite labels

### Test Against a Local Cluster

For a more thorough local test:

```bash
# 1. Install your operator on a test cluster
# 2. Apply the bundle manifests
oc apply -f certsuite-test-bundle/prerequisites/ 2>/dev/null || true
oc apply -f certsuite-test-bundle/operands/

# 3. Wait for readiness
oc rollout status deployment/my-workload

# 4. Run certsuite locally
certsuite run \
  --label-filter "networking" \
  --config-file certsuite-test-bundle/certsuite_config.yml \
  --output-dir /tmp/certsuite-results
```

## Step 6: Scaffold with the CLI Tool

To generate a boilerplate test bundle:

```bash
./tools/scaffold-test-bundle.sh \
  --name my-operator \
  --package my-operator \
  --channel stable \
  --output /path/to/output
```

This creates a complete bundle directory with placeholder manifests
that you can customize.

## Step 7: Onboard to Konflux

1. **Push the test bundle** to a directory in your operator's git
   repository (e.g. `certsuite-test-bundle/`).

2. **Create Secrets** in your Konflux tenant namespace:

   ```bash
   # Shared cluster kubeconfig
   oc create secret generic shared-cluster-kubeconfig \
     --from-file=kubeconfig=/path/to/kubeconfig \
     -n <tenant-namespace>

   # cert-track-results API token
   oc create secret generic cert-track-api-token \
     --from-literal=api-token=<your-token> \
     -n <tenant-namespace>

   # OCI registry credentials
   oc create secret docker-registry quay-dockerconfig \
     --docker-server=quay.io \
     --docker-username=<user> \
     --docker-password=<token> \
     -n <tenant-namespace>
   ```

3. **Create an IntegrationTestScenario** in your tenants-config
   repository. See
   [examples/integration-test-scenario.yaml](../examples/integration-test-scenario.yaml)
   for a template.

   Key parameters to set:
   - `TEST_BUNDLE_REF`: Git URL to your test bundle, e.g.
     `https://github.com/org/repo.git#certsuite-test-bundle`
   - `CERTSUITE_LABELS`: Which test suites to run
   - `CERT_TRACK_URL`: URL of the cert-track-results instance

4. **Merge a change** to your FBC component. The pipeline triggers
   automatically on push events.

## Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| "certsuite-test-bundle.yaml not found" | Wrong `TEST_BUNDLE_REF` path | Check the `#path` fragment in the ref |
| Operands never become Ready | Missing dependencies or bad config | Test locally first (Step 5) |
| Certsuite finds 0 pods | Labels don't match config | Verify `podsUnderTestLabels` in config |
| Lock timeout | Another pipeline is running | Increase `LOCK_TIMEOUT` or wait |
| OADP restore fails | Backup expired or missing | Recreate the baseline backup |

## Reference

- [Architecture Guide](architecture.md)
- [Certsuite Documentation](https://redhat-best-practices-for-k8s.github.io/certsuite/)
- [Certsuite Configuration](https://redhat-best-practices-for-k8s.github.io/certsuite/configuration/)
- [Certsuite Test Catalog](https://github.com/redhat-best-practices-for-k8s/certsuite/blob/main/CATALOG.md)
