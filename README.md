# Konflux Certsuite Shared Test

A [Konflux](https://konflux-ci.dev/) integration test pipeline that deploys an
operator from an FBC (File-Based Catalog) fragment onto a **shared, long-lived
OpenShift cluster** and runs the
[Red Hat Best Practices Test Suite for Kubernetes](https://github.com/redhat-best-practices-for-k8s/certsuite)
(certsuite) against it.

## Key Features

- **Shared cluster model** -- uses an existing OpenShift cluster via kubeconfig
  instead of provisioning an ephemeral one, reducing cost and spin-up time.
- **Concurrency queue** -- Kubernetes Lease-based mutex ensures only one
  pipeline run uses the cluster at a time; others wait in line.
- **OADP cleanup** -- cluster state is restored to a known baseline before and
  after every run via OpenShift API for Data Protection (OADP / Velero).
- **Operator test bundle** -- operator owners provide a portable bundle of
  software-only operand manifests so the full operator scope is exercised
  without hardware or license dependencies.
- **Parameterized suites** -- certsuite test labels are a pipeline parameter,
  so each project can choose which suites to run.
- **Results to cert-track-results** -- claim.json is automatically pushed to
  the cert-track-results web app with retention policies (last 3 full results
  per operator/release; older runs are stripped of debug data).

## Quick Start

See the [Architecture Guide](docs/architecture.md) for the full workflow and
the [Operator Onboarding Guide](docs/operator-onboarding-guide.md) for
step-by-step instructions on creating a test bundle and adding the test to your
Konflux application.

## Repository Layout

```
pipelines/          Tekton Pipeline definitions
tasks/              Reusable Tekton Task definitions
scripts/            Shell scripts used by the tasks
tools/              Scaffolding & validation helpers for operator owners
docs/               Architecture and onboarding documentation
examples/           Example IntegrationTestScenario, OADP backup, test bundle
```

## Shared Cluster Prerequisites

Before any pipeline run the shared cluster must have:

1. **OADP operator** installed with a `DataProtectionApplication` CR configured
   against an S3-compatible backend (e.g. AWS S3, MinIO, ODF).
2. **Baseline OADP Backup** created from the clean cluster state. See
   [examples/oadp-baseline-backup.yaml](examples/oadp-baseline-backup.yaml).
3. **Kubeconfig Secret** in every Konflux tenant namespace that will use this
   pipeline:

   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: shared-cluster-kubeconfig
     namespace: <tenant-namespace>
   type: Opaque
   data:
     kubeconfig: <base64-encoded-kubeconfig>
   ```

4. **RBAC** -- the kubeconfig identity needs permissions to:
   - Create/delete Leases in the `certsuite-locks` namespace
   - Create OADP Restore CRs in the OADP namespace
   - Manage OLM resources (CatalogSource, Subscription, OperatorGroup, CSV)
   - Create/delete namespaces and CRDs
5. **cert-track-results API token** stored as a Secret:

   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: cert-track-api-token
     namespace: <tenant-namespace>
   type: Opaque
   data:
     api-token: <base64-encoded-token>
   ```

## Pipeline Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `SNAPSHOT` | yes | -- | Konflux ApplicationSnapshot JSON |
| `KUBECONFIG_SECRET_NAME` | yes | -- | Secret holding the shared cluster kubeconfig |
| `KUBECONFIG_SECRET_KEY` | no | `kubeconfig` | Key inside the secret |
| `TEST_BUNDLE_REF` | yes | -- | Git URL or OCI ref to the operator test bundle |
| `CERTSUITE_LABELS` | no | `""` (all) | Comma-separated certsuite labels; empty runs all tests |
| `OADP_BACKUP_NAME` | yes | -- | OADP Backup name to restore from |
| `OADP_NAMESPACE` | no | `openshift-adp` | Namespace of the OADP operator |
| `PACKAGE_NAME` | no | auto-detect | OLM package name |
| `CHANNEL_NAME` | no | auto-detect | OLM channel name |
| `LOCK_TIMEOUT` | no | `1800` | Seconds to wait for cluster lock |
| `LOCK_NAME` | no | `certsuite-cluster-lock` | Lease name for the mutex |
| `CREDENTIALS_SECRET_NAME` | yes | -- | Secret for OCI registry credentials |
| `OCI_REF` | yes | -- | OCI artifact reference for results |
| `CERT_TRACK_URL` | yes | -- | Base URL of cert-track-results |
| `CERT_TRACK_SECRET_NAME` | yes | -- | Secret with cert-track API token |
| `CERT_TRACK_SECRET_KEY` | no | `api-token` | Key inside the token secret |

## License

Apache License 2.0
