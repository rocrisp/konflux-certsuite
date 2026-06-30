# certsuite-operator-test pipeline

The `certsuite-operator-test` pipeline deploys an operator from an FBC
fragment onto a shared OpenShift cluster, deploys operands from a test
bundle, and runs the Red Hat Best Practices Test Suite for Kubernetes
(certsuite).

## Pipeline Flow

1. **parse-metadata** -- Extracts the FBC image, git URL, and revision
   from the Konflux Snapshot.
2. **get-unreleased-bundle** -- Retrieves the unreleased bundle from
   the FBC fragment.
3. **acquire-cluster-lock** -- Creates a Kubernetes Lease to serialize
   access to the shared test cluster.
4. **oadp-restore-pre** -- Restores the cluster to a clean baseline.
5. **deploy-operator** -- Installs the operator via OLM.
6. **deploy-operands** -- Applies the test bundle manifests and waits
   for readiness.
7. **run-certsuite** -- Runs certsuite with the specified labels.
8. **collect-results** -- Pushes results to cert-track-results and OCI.

The `finally` block always runs cleanup-operator, oadp-restore-post,
and release-cluster-lock.

## Usage

Create an `IntegrationTestScenario` referencing this pipeline. See
[examples/integration-test-scenario.yaml](../../../examples/integration-test-scenario.yaml).

## Parameters

See the [project README](../../../README.md#pipeline-parameters) for
the full parameter reference.
