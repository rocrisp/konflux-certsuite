# Konflux Certsuite Test

A [Konflux](https://konflux-ci.dev/) integration test pipeline that deploys an
operator from an FBC (File-Based Catalog) fragment, runs the
[Red Hat Best Practices Test Suite for Kubernetes](https://github.com/redhat-best-practices-for-k8s/certsuite)
(certsuite) against it, and collects results.

## Two Pipeline Variants

### EaaS (Recommended)

`certsuite-operator-test-eaas.yaml` -- provisions a fresh ephemeral
Hypershift cluster per run via Konflux EaaS. No kubeconfig secrets, no
cluster locks, no OADP. The cluster is automatically destroyed when the
run completes.

### Shared Cluster

`certsuite-operator-test.yaml` -- uses a pre-existing cluster via a
kubeconfig Secret. Includes Lease-based queueing and OADP
backup/restore. Use this only when your tests require persistent
infrastructure (e.g. hardware-dependent tests).

## Key Features

- **Operator test bundle** -- operator owners provide a portable bundle of
  software-only operand manifests so the full operator scope is exercised
  without hardware or license dependencies.
- **All tests by default** -- runs the full certsuite suite unless
  `CERTSUITE_LABELS` specifies a subset.
- **Results to cert-track-results** -- claim.json is optionally pushed to
  the cert-track-results web app with retention policies.

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

## EaaS Pipeline Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `SNAPSHOT` | auto | -- | Provided by Konflux |
| `TEST_BUNDLE_REF` | yes | -- | Git URL to the operator test bundle |
| `CERTSUITE_LABELS` | no | `""` (all) | Comma-separated certsuite labels; empty runs all tests |
| `PACKAGE_NAME` | no | auto-detect | OLM package name |
| `CHANNEL_NAME` | no | auto-detect | OLM channel name |
| `CREDENTIALS_SECRET_NAME` | no | `""` | Secret for OCI push; empty skips |
| `OCI_REF` | no | `""` | OCI artifact ref; empty skips |
| `CERT_TRACK_URL` | no | `""` | cert-track-results URL; empty skips |
| `CERT_TRACK_SECRET_NAME` | no | `""` | cert-track API token secret |

## Shared Cluster Pipeline Parameters

Additional parameters (on top of the EaaS ones):

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `KUBECONFIG_SECRET_NAME` | no | `shared-cluster-kubeconfig` | Secret holding the kubeconfig |
| `KUBECONFIG_VALUE` | no | `""` | Base64 kubeconfig for testing; auto-creates a temporary Secret |
| `OADP_BACKUP_NAME` | no | `certsuite-clean-baseline` | OADP Backup name; first run creates it; empty skips OADP |
| `LOCK_TIMEOUT` | no | `1800` | Seconds to wait for cluster lock |
| `LOCK_NAME` | no | `certsuite-cluster-lock` | Lease name for the mutex |

## License

Apache License 2.0
