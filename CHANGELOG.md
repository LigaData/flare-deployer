# Changelog

## 4.1.1 (2026-11-10)
- Setup job never exits non-zero before its deadline: connection errors, DNS failures, non-JSON and
  5xx answers while the UI or the environment master is still starting are logged and retried
  (Google's verifier saw the job crash-loop on a warm cluster where the UI answered before PostgreSQL
  was ready). Job backoffLimit raised to 10.
- publishedVersion 4.1.1; deployer tagged 4.1 and 4.1.1 (product images keep 4.1 / 4.1.0).

## 4.1.0 (2026-11-09)
- First Google Cloud Marketplace release of the Data Flare deployer: control plane, built-in engine,
  ready-to-use `dev` environment, Redis, optional in-cluster PostgreSQL, setup job (environment
  registration and pipeline user), verification tester.
- Storage: new `storage.accessMode` (default ReadWriteOnce on `standard-rwo`, so the deployer works on
  any GKE cluster; pods sharing a volume are co-scheduled on one node). ReadWriteMany with
  `standard-rwx` remains the multi-node production layout. Default volume size 100Gi.
- Lower pod resource requests (evaluation footprint: about 2 vCPU / 6 GiB for the control plane,
  1.5 vCPU / 4.5 GiB per environment); limits unchanged.
- Deployer waits up to 1500 s for the application to become ready (was the 300 s default), after
  Google's verifier timed out on fresh clusters.
