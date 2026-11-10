# Changelog

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
