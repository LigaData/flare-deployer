# LigaData Data Flare on GKE: user guide (Marketplace Kubernetes app)

Data Flare is a data integration and mediation platform: pipelines read from files, Kafka, databases,
Pub/Sub, Cloud Storage and telecom network elements (ASN.1 CDRs), transform with a governed DSL and
write to warehouses, lakes, Kafka and APIs. This guide covers the Google Cloud Marketplace
*Kubernetes app* deployment: the console deploys Data Flare into a GKE cluster you already have.
Every Kubernetes resource is named after the application instance (`<name>-...`); the examples
below use `data-flare` as the instance name and `flare4` as the namespace.

## 1. Prerequisites

- A GKE Standard or Autopilot cluster, x86 nodes, at least 3 x e2-standard-8 (24 vCPU, 96 GiB) for
  the default sizing (control plane plus the `dev` environment), with the **Filestore CSI driver**
  enabled (storage class `standard-rwx`) or another ReadWriteMany storage class.
- The Application CRD (installed once per cluster; the console does this for you, or run
  `kubectl apply -f "https://raw.githubusercontent.com/GoogleCloudPlatform/marketplace-k8s-app-tools/master/crd/app-crd.yaml"`).
- A licence from LigaData (support@ligadata.com). The licence is bound to the cluster: send the
  output of `kubectl get ns kube-system -o jsonpath='{.metadata.uid}'`.

## 2. Deploy from the console

Open the listing, click **Configure**, choose the cluster and namespace, and fill in:

| Field | Default | Notes |
|---|---|---|
| App instance name | data-flare | prefix of every resource name |
| Service account | create new | needs read access to namespaces (licence binding); created for you |
| Storage class for the shared volume | standard-rwx | must be ReadWriteMany (Filestore or NFS); block classes fail |
| Size of the shared volume | 1Ti | Filestore Basic minimum |
| Run PostgreSQL inside the cluster | on | off = enter your own PostgreSQL host (Cloud SQL private IP) |
| Database name / user / password | flare4 / flare4 / generated | |
| Web UI administrator password | generated | admin@ld.com |
| Pipeline user e-mail / password | dataeng1@example.com / generated | role DataEngL1 |
| Expose the web UI through a load balancer | off | on = GKE external HTTP(S) load balancer; add a DNS name for HTTPS |
| Licence file (base64) | empty | can be installed later |
| Time zone | UTC | |

Deployment takes 5 to 10 minutes: pods seed the shared volume, the control plane and the `dev`
environment start, then the setup job registers `dev` in the web UI and creates the pipeline user.
The Application page in the console shows the status and the notes below.

Command line alternative (same deployer):

    mpdev install --deployer=<deployer image>:4.1 --parameters='{"name":"data-flare","namespace":"flare4"}'

## 3. Access and logins

Web UI, path `/dataflare`. By default it is not exposed outside the cluster:

    kubectl -n flare4 port-forward svc/data-flare-flare4-ui 8080:80      # then open http://localhost:8080/dataflare/

### Shared access over HTTPS

Deploy with the load balancer option and a DNS name (Helm values `ui.ingress.*`):

| Parameter | Value |
|---|---|
| ui_ingress_enabled | true |
| ui_ingress_host | the DNS name you want, for example `flare.example.com` |
| ui_ingress_managed_certificate | true |
| ui_ingress_static_ip_name | empty (an IP named `<namespace>-flare-ui` is reserved for you), or the name of an IP you reserved |

The deployment creates a GKE external HTTP(S) load balancer on a static IP, requests a Google-managed
certificate for the host and redirects HTTP to HTTPS. Its outputs show `ui_ingress_ip` and the final
address in `ui_access`. Then:

1. Create a DNS A record for the host pointing at `ui_ingress_ip` (this must come after the deployment,
   because the IP does not exist before it).
2. Wait for the certificate, typically 15 to 60 minutes after the record resolves:

       kubectl -n flare4 get managedcertificate data-flare-ui

   Until it shows `Active` the site answers on plain HTTP only. No redeployment is needed.

Notes: without a host the ingress serves plain HTTP on its IP. Deleting the deployment releases the
reserved IP, so name a pre-reserved IP in `ui_ingress_static_ip_name` for long-lived installations. To
use a certificate from your own CA instead, install with Helm and set `ui.ingress.tls` to a TLS Secret.
`ui_service_type=LoadBalancer` exposes plain HTTP on a public IP and is meant for demos only.

Logins:

Both passwords are generated at install time and kept in the Kubernetes Secret `data-flare-ligadata-ui-users`
in the installation namespace; nothing is printed or documented in clear text.

- Administrator `admin@ld.com`: manages users, roles and environments, cannot design or run pipelines.

      kubectl -n flare4 get secret data-flare-ligadata-ui-users -o jsonpath='{.data.admin}' | base64 -d

- Pipeline user `dataeng1@example.com` (role DataEngL1), created by the setup job:

      kubectl -n flare4 get secret data-flare-ligadata-ui-users -o jsonpath='{.data.pipelineUser}' | base64 -d

Reading the Secret requires `get` on Secrets in that namespace, which is how access to these logins
is controlled. If you point the installation at a database that already contains Data Flare users,
the administrator keeps the password stored there. Passwords changed in the UI are not written back to
the Secret; update the Secret too if the setup job should keep working on upgrades.

Pipelines cannot be deployed to the built-in "Main Env" (type Main). Deploy them to the `dev`
environment the installation created (Environments page), or to further environments (each one is another deployment of this app, registered under
Environments > Connect). A new
installation ships no sample pipelines, only the system stage templates; create a pipeline in the
designer or import an exported one (Pipelines > Import).


## 4. Configure

- **Licence after install:** create the Secret and restart the master.

      kubectl -n flare4 create secret generic data-flare-ligadata-license \
        --from-file=license.p7s --from-file=trusted-root.fingerprint
      kubectl -n flare4 exec deploy/data-flare-dev-flaredriver -- sh -c 'cp /license/license.p7s /opt/Flare4/DI/config/license/'
      kubectl -n flare4 rollout restart deploy/data-flare-dev-flaredriver

  Check: Administration > Licence in the UI, or `GET /DIEnvService/license/status` on the master.
- **Environments:** the installation creates and registers the environments listed in `environments`
  (default one, `dev`, in namespace `flare4-dev`). To add more later, either change `environments`
  and update the deployment (the new ones are created and registered on upgrade), or install this
  chart again with `mode=environment` into a new namespace and register it under Environments >
  Connect with master URL `http://flaredriver.<namespace>.svc.cluster.local:10001/DIEnvService` and
  that namespace's `DI_secretKey` from Secret `data-flare-dev-ligadata-app`. Environments > Create (building a
  namespace from the UI) is not supported in this release.
- **Users and roles:** Users; LDAP under Settings (LDAPS reachable through Cloud NAT or VPN).
- **Connections to data sources** are defined per environment in the UI (Connections). Private
  sources on premises need Cloud Interconnect or VPN to the cluster's VPC.
- **Time zone:** `timezone` parameter (applies to logs and schedules).

## 5. Basic usage

1. Create a workspace and a pipeline (Pipelines > New), or import a JSON export
   (Pipelines > Import).
2. Deploy it to an environment, approve if your role requires it, and start it.
3. Monitor under Deployed pipelines: throughput, errors, transaction state.
4. Stop and undeploy before changing the DSL.

## 6. Backup and restore

- **Shared volume** (`<release>-flare-data`, Filestore): configuration, libraries, landing zone,
  indexer data, UI storage. Use Filestore backups
  (`gcloud filestore backups create`) or snapshot the share on a schedule.
- **Metadata database:** internal Postgres: `kubectl -n flare4 exec deploy/postgres -- pg_dump -U flare4 flare4 > flare4.sql`;
  Cloud SQL: automated backups.
- **Restore:** reinstall with `existing_claim` pointing at a claim restored from the backup, and
  restore the database before starting the UI (`kubectl -n flare4 scale deploy/flare-deployment-ui --replicas=0` during the restore).

## 7. Update

Deploy the newer release from the console (or `mpdev install` with the new deployer tag); the deployer updates the resources in place.
The shared volume and secrets are kept (`helm.sh/resource-policy: keep`). Stop pipelines first;
deployed pipelines, users and environments persist in the database and on the volume.

## 8. Scale

- Worker count: `worker_replicas` (StatefulSet `disworker`), then raise the environment's worker
  count in the UI.
- Pod resources: Helm values under `resources.*` and `javaOpts.*` (heap sizes).
- Nodes: GKE node pool autoscaling. Filestore capacity can be increased online.

## 9. Delete

Delete the application from the console (Kubernetes Engine > Applications) or `kubectl delete application <name>`, which removes every owned resource. The shared volume claim, the Postgres claim and
the secrets are kept on purpose; delete them explicitly to remove all data:

    kubectl -n flare4 delete pvc --all
    kubectl -n flare4 delete secret data-flare-dev-ligadata-app data-flare-ligadata-license
    kubectl delete namespace flare4
    kubectl delete clusterrolebinding flare4-namespace-uid-reader flare4-ligadatacomputer
    kubectl delete clusterrole flare4-namespace-uid-reader

Environments created from the UI live in their own namespaces; delete them from the UI first.

## 10. Ports and network

Inbound: only the UI (Service port 80 to container 8081, `/dataflare`). Internal: master 10001/9998/9999/7787/9887/9850/7799,
workers 10092/9998/9999/7788/9888/9851/9861/7798, environment service 10002, Redis 6379,
Postgres 5432. Outbound (through Cloud NAT): data sources and targets, LDAPS 636, Kafka 9092,
JDBC. Pods never call LigaData or Google.

## Support

support@ligadata.com, with the output of `kubectl -n flare4 get pods` and the master log
(`kubectl -n flare4 logs deploy/data-flare-dev-flaredriver`).
