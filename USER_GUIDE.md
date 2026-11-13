# LigaData Data Flare on GKE: user guide (Marketplace Kubernetes app)

Data Flare is a data integration and mediation platform: pipelines read from files, Kafka, databases,
Pub/Sub, Cloud Storage and telecom network elements (ASN.1 CDRs), transform with a governed DSL and
write to warehouses, lakes, Kafka and APIs. This guide covers the Google Cloud Marketplace
*Kubernetes app* deployment: the console deploys Data Flare into a GKE cluster you already have.
Every Kubernetes resource is named after the application instance (`<instance>-...`). The examples
below use the instance name the console proposes, `ligadata-flare-1`, and the namespace `data-flare`;
substitute the values you chose in the deploy form.

## 1. Prerequisites

- A GKE Standard or Autopilot cluster with x86 nodes. The pods request about 2.2 vCPU and 6.5 GiB for
  the control plane and 1.5 vCPU and 4.5 GiB for the `dev` environment. With the default block-disk
  storage each of the two groups runs on a single node. The console applies its own, more conservative
  eligibility check and may mark a cluster of that size as "does not fit the application"; in that case
  use the size the console recommends (three nodes with about 6 vCPU and 24 GiB each) or let the deploy
  page create a new cluster, which it sizes to fit. See section 8 for the multi-node production layout,
  which needs the **Filestore CSI driver** (storage class `standard-rwx`) or another ReadWriteMany class.
- The account that clicks Deploy needs the **Project Owner** role on the project, or **Consumer
  Procurement Entitlement Manager** in addition to its GKE roles: the Marketplace records a (zero-cost)
  entitlement before it deploys, and the console otherwise reports "You need additional access".
- The Application CRD (installed once per cluster; the console does this for you, or run
  `kubectl apply -f "https://raw.githubusercontent.com/GoogleCloudPlatform/marketplace-k8s-app-tools/master/crd/app-crd.yaml"`).
- A licence from LigaData (support@ligadata.com). The licence is bound to the cluster: send the
  output of `kubectl get ns kube-system -o jsonpath='{.metadata.uid}'`.

## 2. Deploy from the console

Open the listing, click **Configure**, choose the cluster and namespace, and fill in:

| Field | Default | Notes |
|---|---|---|
| App instance name | ligadata-flare-1 | proposed by the console; prefix of every resource name |
| Service account | create new | needs read access to namespaces (licence binding); created for you |
| Shared volume access mode | ReadWriteOnce | ReadWriteOnce = block disk, one node per engine; ReadWriteMany = Filestore or NFS, pods spread across nodes |
| Storage class for the shared volume | standard-rwo | must match the access mode: standard-rwo / premium-rwo, or standard-rwx / premium-rwx / enterprise-rwx |
| Size of the shared volume | 100Gi | one volume per engine (two with the defaults); Filestore Basic rounds up to 1Ti |
| Run PostgreSQL inside the cluster | on | off = enter your own PostgreSQL host (Cloud SQL private IP) |
| Database name / user / password | flare4 / flare4 / generated | |
| Web UI administrator password | generated | admin@ld.com |
| Pipeline user e-mail / password | dataeng1@example.com / generated | role DataEngL1 |
| Expose the web UI through a load balancer | off | on = GKE external HTTP(S) load balancer, plain HTTP on a public IP |
| DNS name for the web UI | empty | optional; the load balancer then answers only for that host name. HTTPS is added after the deployment, see section 3 |
| Licence file (base64) | empty | can be installed later |
| Time zone | UTC | |

Deployment takes 5 to 10 minutes: pods seed the shared volume, the control plane and the `dev`
environment start, then the setup job registers `dev` in the web UI and creates the pipeline user.
The Application page in the console (Kubernetes Engine > Applications) shows the status and the notes
below.

Billing: every Data Flare pod carries the Marketplace label `goog-partner-solution`. Google Cloud Billing
attributes the cluster resources those pods use to the Data Flare listing only if **GKE cost allocation**
is enabled on the cluster (cluster details > Features, or
`gcloud container clusters update <cluster> --enable-cost-allocation`). This is optional and changes
nothing in what you pay; it only labels the GKE usage in your billing reports.

## 3. Access and logins

### Default logins

| Login | User name | E-mail | Role | Password |
|---|---|---|---|---|
| Administrator | admin | `admin@ld.com` | Admin: users, roles, environments; cannot design or run pipelines | generated at install, or the value you entered in the form; Secret key `admin` |
| Pipeline user | dataeng1 | `dataeng1@example.com` (or the e-mail you entered) | DataEngL1: designs, deploys and runs pipelines | generated at install, or the value you entered; Secret key `pipelineUser` |

Log in to the web UI with the **e-mail** address. Both passwords are in the Kubernetes Secret
`<instance>-ligadata-ui-users` in the installation namespace:

    kubectl -n data-flare get secret ligadata-flare-1-ligadata-ui-users -o jsonpath='{.data.admin}' | base64 -d; echo
    kubectl -n data-flare get secret ligadata-flare-1-ligadata-ui-users -o jsonpath='{.data.pipelineUser}' | base64 -d; echo

The UI password policy is at least 8 characters with an upper-case letter, a lower-case letter, a digit
and one of `@ # $ % ^ & + = _ ! *`; passwords you enter in the form must follow it.

Nothing is printed or documented in clear text. Reading the Secret requires `get` on Secrets in that
namespace, which is how access to these logins is controlled. If you point the installation at a
database that already contains Data Flare users, the administrator keeps the password stored there.
Passwords changed in the UI are not written back to the Secret; update the Secret too if the setup job
should keep working on updates.

### Reaching the web UI

Web UI, path `/dataflare`. By default it is not exposed outside the cluster:

    kubectl -n data-flare port-forward svc/ligadata-flare-1-flare4-ui 8080:80      # then open http://localhost:8080/dataflare/

With the load balancer option enabled, the address appears on the Ingress a few minutes after the
deployment:

    kubectl -n data-flare get ingress ligadata-flare-1-ui          # open http://<ADDRESS>/dataflare/

The load balancer serves plain HTTP on an ephemeral public IP. If you entered a DNS name in the form, the
load balancer answers only for that host name (a request by IP address gets a 404 from the default
backend), so create the DNS record before using it.

### Shared access over HTTPS

This release does not request a certificate by itself. To serve the UI over HTTPS, deploy with the load
balancer option and a DNS name, then add a Google-managed certificate to the Ingress:

1. Keep the load balancer's IP. Read it from the Ingress (above) and promote it to a reserved global
   address so it survives changes to the Ingress:

       gcloud compute addresses create ligadata-flare-1-ui --global --addresses <ADDRESS>
       kubectl -n data-flare annotate ingress ligadata-flare-1-ui kubernetes.io/ingress.global-static-ip-name=ligadata-flare-1-ui

2. Create a DNS A record for the host name pointing at that address.
3. Request the certificate and attach it to the Ingress:

       cat <<'YAML' | kubectl -n data-flare apply -f -
       apiVersion: networking.gke.io/v1
       kind: ManagedCertificate
       metadata:
         name: ligadata-flare-1-ui
       spec:
         domains:
         - flare.example.com
       YAML
       kubectl -n data-flare annotate ingress ligadata-flare-1-ui networking.gke.io/managed-certificates=ligadata-flare-1-ui

4. Wait for the certificate, typically 15 to 60 minutes after the DNS record resolves:

       kubectl -n data-flare get managedcertificate ligadata-flare-1-ui

   Until it shows `Active` the site answers on plain HTTP only.
5. Once it is `Active`, redirect HTTP to HTTPS:

       cat <<'YAML' | kubectl -n data-flare apply -f -
       apiVersion: networking.gke.io/v1beta1
       kind: FrontendConfig
       metadata:
         name: ligadata-flare-1-ui
       spec:
         redirectToHttps:
           enabled: true
       YAML
       kubectl -n data-flare annotate ingress ligadata-flare-1-ui networking.gke.io/v1beta1.FrontendConfig=ligadata-flare-1-ui

Notes: the certificate, the FrontendConfig and the reserved address are yours, not part of the
application. Deploying a newer release from the console rewrites the Ingress, so re-apply the three
annotations afterwards; delete the three objects and release the address when you delete the
application. To use a certificate from your own CA instead of a managed one, store it in a TLS Secret
and add it under `spec.tls` of the Ingress (`kubectl -n data-flare edit ingress ligadata-flare-1-ui`).

### Environments

Pipelines cannot be deployed to the built-in "Main Env" (type Main). Deploy them to the `dev`
environment the installation created (Environments page), or to further environments (each one is
another deployment of this app, registered under Environments > Connect, see section 4). A new
installation ships no sample pipelines, only the system stage templates; create a pipeline in the
designer or import an exported one (Pipelines > Import).

## 4. Configure

- **Licence after install:** copy the file into the master's configuration directory on the shared
  volume (both masters, Main Env and `dev`) and restart them:

      for m in ligadata-flare-1-flaredriver ligadata-flare-1-dev-flaredriver; do
        kubectl -n data-flare exec -i deploy/$m -- sh -c 'cat > /opt/Flare4/DI/config/license/license.p7s' < license.p7s
      done
      kubectl -n data-flare rollout restart deploy/ligadata-flare-1-flaredriver deploy/ligadata-flare-1-dev-flaredriver

  Also store it in the Secret the deployer would have created from the form, so that a future
  installation on a fresh volume (section 6) picks it up automatically:

      kubectl -n data-flare create secret generic ligadata-flare-1-ligadata-license \
        --from-file=license.p7s --from-file=trusted-root.fingerprint

  Check: Administration > Licence in the UI, or `GET /DIEnvService/license/status` on the master.
- **Environments:** the installation creates and registers one environment, `dev`, in the same
  namespace (resources named `ligadata-flare-1-dev-...`). For more environments, deploy this app
  again from the console into another namespace (for example as `ligadata-flare-2` in `data-flare-stg`)
  and register its `dev` environment in the first installation under Environments > Connect with master
  URL `http://ligadata-flare-2-dev-flaredriver.data-flare-stg.svc.cluster.local:10001/DIEnvService` and
  the key `DI_secretKey` from that namespace's Secret `ligadata-flare-2-dev-ligadata-app`. Environments >
  Create (building a namespace from the UI) is not supported in this release.
- **Users and roles:** Users; LDAP under Settings (LDAPS reachable through Cloud NAT or VPN).
- **Connections to data sources** are defined per environment in the UI (Connections). Private
  sources on premises need Cloud Interconnect or VPN to the cluster's VPC.
- **Time zone:** the `Time zone` field of the deploy form (applies to logs and schedules).

## 5. Basic usage

1. Create a workspace and a pipeline (Pipelines > New), or import a JSON export
   (Pipelines > Import).
2. Deploy it to an environment, approve if your role requires it, and start it.
3. Monitor under Deployed pipelines: throughput, errors, transaction state.
4. Stop and undeploy before changing the DSL.

## 6. Backup and restore

- **Shared volumes** (`ligadata-flare-1-flare-data`, `ligadata-flare-1-dev-flare-data`): configuration,
  libraries, landing zone, indexer data, UI storage. Block disks: schedule Persistent Disk snapshots
  (`gcloud compute disks snapshot` or a resource policy). Filestore: `gcloud filestore backups create`.
- **Metadata database:** internal PostgreSQL (volume `ligadata-flare-1-postgres-data`):
  `kubectl -n data-flare exec deploy/ligadata-flare-1-postgres -- pg_dump -U flare4 flare4 > flare4.sql`;
  Cloud SQL: automated backups.
- **Restore:** the volume claims and the secrets survive a deletion of the application (section 9).
  Restore the disks behind the claims from their snapshots and the database from the dump, then deploy
  the app again with the **same instance name and namespace**: it binds the existing claims and secrets
  instead of creating new ones. Keep the UI stopped while the database is being restored
  (`kubectl -n data-flare scale deploy/ligadata-flare-1-flare-deployment-ui --replicas=0`, then back to 1).

## 7. Update

Deploy the newer release from the console; the deployer updates the resources in place. The shared
volumes and secrets are kept (`helm.sh/resource-policy: keep`). Stop pipelines first; deployed pipelines,
users and environments persist in the database and on the volumes. Re-apply the HTTPS annotations
(section 3) and the worker count (section 8) afterwards.

## 8. Scale

- **Workers:** the deploy form does not expose the worker count. Scale the StatefulSet directly, then
  raise the environment's worker count in the UI (Environments):

      kubectl -n data-flare scale statefulset ligadata-flare-1-dev-disworker --replicas=3

  Deploying a newer release resets it to one worker; repeat after updates.
- **Pod resources and heap sizes** are fixed in this release at an evaluation footprint. For a
  production sizing (larger heaps, guaranteed requests) contact support@ligadata.com.
- **Nodes:** GKE node pool autoscaling. Filestore capacity can be increased online.
- **Multi-node:** with the default ReadWriteOnce storage every pod of an engine is pinned to one node
  (pod affinity on the volume label), so more workers compete for that node. For production, enable the
  Filestore CSI driver on the cluster and deploy with access mode **ReadWriteMany** and class
  `standard-rwx` (or an NFS class); the pods then spread across the node pool. Changing the mode of
  an existing deployment means a fresh install; export pipelines first.

## 9. Delete

Delete the application from the console (Kubernetes Engine > Applications) or
`kubectl -n data-flare delete application ligadata-flare-1`, which removes every owned resource. The
shared volume claims, the PostgreSQL claim and the secrets are kept on purpose; delete them explicitly
to remove all data, together with the service account's cluster roles:

    kubectl -n data-flare delete pvc ligadata-flare-1-flare-data ligadata-flare-1-dev-flare-data ligadata-flare-1-postgres-data
    kubectl -n data-flare delete secret ligadata-flare-1-ligadata-app ligadata-flare-1-dev-ligadata-app \
      ligadata-flare-1-ligadata-ui-users ligadata-flare-1-ligadata-license
    kubectl get clusterrole,clusterrolebinding -o name | grep 'data-flare:ligadata-flare-1:' | xargs kubectl delete
    kubectl delete namespace data-flare

If you added HTTPS (section 3), delete the ManagedCertificate and FrontendConfig and release the
reserved address (`gcloud compute addresses delete ligadata-flare-1-ui --global`).

## 10. Ports and network

Inbound: only the UI (Service port 80 to container 8081, `/dataflare`). Internal: master 10001/9998/9999/7787/9887/9850/7799,
workers 10092/9998/9999/7788/9888/9851/9861/7798, environment service 10002, Redis 6379,
Postgres 5432. Outbound (through Cloud NAT): data sources and targets, LDAPS 636, Kafka 9092,
JDBC. Pods never call LigaData or Google.

## Support

support@ligadata.com, with the output of `kubectl -n data-flare get pods` and the master log
(`kubectl -n data-flare logs deploy/ligadata-flare-1-dev-flaredriver`).
