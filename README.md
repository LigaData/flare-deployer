# Data Flare: Google Cloud Marketplace deployer

Deployer, Helm chart and schema for the **Data Flare** listing on Google Cloud Marketplace
(Kubernetes app type). The console runs the deployer image in the customer's GKE cluster to install
Data Flare: the control plane (web UI, REST API, environment service), a built-in engine and a
ready-to-use `dev` environment (engine master, worker and indexer), Redis and optional in-cluster
PostgreSQL.

- [User guide](USER_GUIDE.md): prerequisites, deployment form, access and logins, configuration,
  backup, update, scaling, deletion.
- `deployer/`: `Dockerfile` (built on Google's `deployer_helm` base), `schema.yaml` (the console form
  and image mapping), `chart/data-flare` (the Helm chart), `apptest/` (verification parameters).
- `scripts/`: build and publish steps used by LigaData (copy and annotate images, build the deployer,
  run `mpdev verify`, install through the deployer).

## Deploying outside the console

With the [marketplace tools](https://github.com/GoogleCloudPlatform/marketplace-k8s-app-tools) (`mpdev`):

    kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/marketplace-k8s-app-tools/master/crd/app-crd.yaml
    kubectl create namespace flare4
    mpdev install --deployer=us-docker.pkg.dev/ligadata-public/ligadata-flare/deployer:4.1 \
      --parameters='{"name":"data-flare","namespace":"flare4"}'

Or with Helm directly (images and generated secrets then come from values; see `values.yaml`):

    helm install data-flare deployer/chart/data-flare -n flare4 --create-namespace \
      --set serviceAccount=default

## Images

The deployer and the product images (`dismain`, `disworker`, `flare4ui`, `seed`, `redis`, `postgres`)
are published under `us-docker.pkg.dev/ligadata-public/ligadata-flare` with the release track tag
(`4.1`) and the full version (`4.1.0`). Marketplace copies them to its own registry at publish time.

## Support

support@ligadata.com
