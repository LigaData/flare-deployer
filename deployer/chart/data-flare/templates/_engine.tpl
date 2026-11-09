{{/* Engine master, worker and indexer for one engine (control plane's or an environment's), all in the
     release namespace, named <release>-[<env>-]<component>. Context from "flare.ctx". */}}
{{- define "flare.engine" -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .p }}flaredriver
  labels:
    service: {{ .p }}flaredriver
{{ include "flare.labels" . | indent 4 }}
spec:
  replicas: 1
  selector:
    matchLabels:
      service: {{ .p }}flaredriver
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        service: {{ .p }}flaredriver
{{ include "flare.podLabels" . | indent 8 }}
    spec:
      serviceAccountName: {{ include "flare.sa" . }}
      securityContext:
        fsGroup: 1000
      terminationGracePeriodSeconds: 30
{{ include "flare.pullSecrets" . | indent 6 }}
{{ include "flare.scheduling" . | indent 6 }}
      initContainers:
{{ include "flare.seedInit" . | indent 6 }}
      containers:
      - name: flaredriver
        image: {{ include "flare.image" (dict "Values" .Values "name" "disworker") }}
        imagePullPolicy: {{ .Values.imagePullPolicy }}
        env:
        - name: NODE_NAME
          valueFrom: {fieldRef: {apiVersion: v1, fieldPath: spec.nodeName}}
        - name: POD_IP
          valueFrom: {fieldRef: {apiVersion: v1, fieldPath: status.podIP}}
        - name: ENV_RUNMODE
          value: master
        - name: LIGADATA_JAVA_OPTS
          value: {{ .Values.javaOpts.flaredriver | quote }}
{{ include "flare.engineSecretEnv" . | indent 8 }}
{{ include "flare.postStart" . | indent 8 }}
        ports:
        - {containerPort: 10001}
        - {containerPort: 9998, name: listenport}
        - {containerPort: 9999, name: commport}
        - {containerPort: 7787, name: fsremote}
        - {containerPort: 9887, name: nn}
        - {containerPort: 9850, name: dedup}
        - {containerPort: 7799, name: translog}
        resources:
{{ toYaml .Values.resources.flaredriver | indent 10 }}
        volumeMounts:
        - {name: flare-data, mountPath: /etc/hadoop/conf, subPath: masterconfig/hadoop}
        - {name: flare-data, mountPath: /opt/Flare4/DI/config, subPath: masterconfig/config}
        - {name: flare-data, mountPath: /opt/Flare4/DI/EnvBasePath, subPath: masterdata/EnvBasePath}
        - {name: flare-data, mountPath: /opt/Flare4/DI/dbState, subPath: masterdata/dbState}
        - {name: flare-data, mountPath: /opt/Flare4/DI/FileStats, subPath: masterdata/FileStats}
        - {name: flare-data, mountPath: /opt/Flare4/DI/transLog, subPath: masterdata/transLog}
        - {name: flare-data, mountPath: /opt/Flare4/DI/messages, subPath: masterdata/messages}
        - {name: flare-data, mountPath: /opt/Flare4/DI/storage, subPath: masterdata/storage}
        - {name: flare-data, mountPath: /opt/Flare4/DI/ExtLib, subPath: extlibs}
        - {name: flare-data, mountPath: /opt/Flare4/DI/logs, subPath: logs/driver}
        - {name: flare-data, mountPath: /opt/Flare4/Data, subPath: lzdata}
      volumes:
{{ include "flare.sharedVolumes" . | indent 6 }}
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {{ .p }}disworker
  labels:
    app: {{ .p }}disworker
{{ include "flare.labels" . | indent 4 }}
spec:
  serviceName: {{ .p }}disworker
  replicas: {{ .Values.worker.replicas }}
  podManagementPolicy: OrderedReady
  selector:
    matchLabels:
      app: {{ .p }}disworker
  updateStrategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        app: {{ .p }}disworker
{{ include "flare.podLabels" . | indent 8 }}
    spec:
      serviceAccountName: {{ include "flare.sa" . }}
      securityContext:
        fsGroup: 1000
      terminationGracePeriodSeconds: 30
{{ include "flare.pullSecrets" . | indent 6 }}
{{ include "flare.scheduling" . | indent 6 }}
      initContainers:
{{ include "flare.seedInit" . | indent 6 }}
      containers:
      - name: disworker
        image: {{ include "flare.image" (dict "Values" .Values "name" "disworker") }}
        imagePullPolicy: {{ .Values.imagePullPolicy }}
        env:
        - name: NODE_NAME
          valueFrom: {fieldRef: {apiVersion: v1, fieldPath: spec.nodeName}}
        - name: POD_IP
          valueFrom: {fieldRef: {apiVersion: v1, fieldPath: status.podIP}}
        - name: ENV_RUNMODE
          value: worker
        - name: LIGADATA_JAVA_OPTS
          value: {{ .Values.javaOpts.disworker | quote }}
{{ include "flare.engineSecretEnv" . | indent 8 }}
{{ include "flare.postStart" . | indent 8 }}
        ports:
        - {containerPort: 10092}
        - {containerPort: 9998, name: listenport}
        - {containerPort: 9999, name: commport}
        - {containerPort: 7788, name: fsremote}
        - {containerPort: 9888, name: nn}
        - {containerPort: 9851, name: dedup0}
        - {containerPort: 9861, name: dedup1}
        - {containerPort: 7798, name: translog}
        resources:
{{ toYaml .Values.resources.disworker | indent 10 }}
        volumeMounts:
        - {name: flare-data, mountPath: /opt/Flare4/DI/config, subPath: workerconfig/config}
        - {name: flare-data, mountPath: /etc/hadoop/conf, subPath: workerconfig/hadoop}
        - {name: flare-data, mountPath: /opt/Flare4/DI/ExtLib, subPath: extlibs}
        - {name: flare-data, mountPath: /opt/Flare4/DI/logs, subPath: logs/workers}
        - {name: flare-data, mountPath: /opt/Flare4/Data, subPath: lzdata}
      volumes:
{{ include "flare.sharedVolumes" . | indent 6 }}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .p }}disindexer-0
  labels:
    service: {{ .p }}disindexer-0
{{ include "flare.labels" . | indent 4 }}
spec:
  replicas: 1
  selector:
    matchLabels:
      service: {{ .p }}disindexer-0
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        service: {{ .p }}disindexer-0
{{ include "flare.podLabels" . | indent 8 }}
    spec:
      # the engine addresses the indexer as <hostname>.<subdomain>.<namespace>.svc; seed.sh writes the same prefix
      hostname: {{ .p }}disindexer-0
      subdomain: {{ .p }}disindexer-0
      serviceAccountName: {{ include "flare.sa" . }}
      securityContext:
        fsGroup: 1000
      terminationGracePeriodSeconds: 30
{{ include "flare.pullSecrets" . | indent 6 }}
{{ include "flare.scheduling" . | indent 6 }}
      initContainers:
{{ include "flare.seedInit" . | indent 6 }}
      containers:
      - name: disindexer-0
        image: {{ include "flare.image" (dict "Values" .Values "name" "disworker") }}
        imagePullPolicy: {{ .Values.imagePullPolicy }}
        env:
        - name: POD_IP
          valueFrom: {fieldRef: {apiVersion: v1, fieldPath: status.podIP}}
        - name: ENV_RUNMODE
          value: worker
        - name: LIGADATA_JAVA_OPTS
          value: {{ .Values.javaOpts.disindexer | quote }}
{{ include "flare.engineSecretEnv" . | indent 8 }}
{{ include "flare.postStart" . | indent 8 }}
        ports:
        - {containerPort: 10092}
        - {containerPort: 9998, name: listenport}
        - {containerPort: 9999, name: commport}
        - {containerPort: 7788, name: fsremote}
        - {containerPort: 9888, name: nn}
        - {containerPort: 9851, name: dedup0}
        - {containerPort: 9861, name: dedup1}
        - {containerPort: 7798, name: translog}
        resources:
{{ toYaml .Values.resources.disindexer | indent 10 }}
        volumeMounts:
        - {name: flare-data, mountPath: /opt/Flare4/DI/config, subPath: workerconfig/config}
        - {name: flare-data, mountPath: /etc/hadoop/conf, subPath: workerconfig/hadoop}
        - {name: flare-data, mountPath: /opt/Flare4/DI/ExtLib, subPath: extlibs}
        - {name: flare-data, mountPath: /opt/Flare4/DI/logs, subPath: logs/indexers}
        - {name: flare-data, mountPath: /opt/Flare4/Indexer, subPath: indexerdata-0}
        - {name: flare-data, mountPath: /opt/Flare4/IndexerBackup, subPath: indexer-backup}
      volumes:
{{ include "flare.sharedVolumes" . | indent 6 }}
{{- end }}

{{/* ClusterIP services of one engine */}}
{{- define "flare.engineServices" -}}
apiVersion: v1
kind: Service
metadata:
  name: {{ .p }}flaredriver
  labels:
{{ include "flare.labels" . | indent 4 }}
spec:
  type: ClusterIP
  selector:
    service: {{ .p }}flaredriver
  ports:
  - {name: http, port: 10001, targetPort: 10001}
  - {name: listener, port: 9998, targetPort: 9998}
  - {name: comm, port: 9999, targetPort: 9999}
  - {name: fsremote, port: 7787, targetPort: 7787}
  - {name: nn, port: 9887, targetPort: 9887}
  - {name: dedup, port: 9850, targetPort: 9850}
  - {name: translog, port: 7799, targetPort: 7799}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ .p }}disworker
  labels:
    app: {{ .p }}disworker
{{ include "flare.labels" . | indent 4 }}
spec:
  type: ClusterIP
  selector:
    app: {{ .p }}disworker
  ports:
  - {name: webhttp, port: 10092, targetPort: 10092}
  - {name: listener, port: 9998, targetPort: listenport}
  - {name: comm, port: 9999, targetPort: commport}
  - {name: fsremote, port: 7788, targetPort: 7788}
  - {name: nn, port: 9888, targetPort: 9888}
  - {name: dedup0, port: 9851, targetPort: 9851}
  - {name: dedup1, port: 9861, targetPort: 9861}
  - {name: translog, port: 7798, targetPort: 7798}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ .p }}disindexer-0
  labels:
    service: {{ .p }}disindexer-0
{{ include "flare.labels" . | indent 4 }}
spec:
  type: ClusterIP
  selector:
    service: {{ .p }}disindexer-0
  ports:
  - {name: webhttp, port: 10092, targetPort: 10092}
  - {name: listener, port: 9998, targetPort: 9998}
  - {name: comm, port: 9999, targetPort: 9999}
  - {name: fsremote, port: 7788, targetPort: 7788}
  - {name: nn, port: 9888, targetPort: 9888}
  - {name: dedup0, port: 9851, targetPort: 9851}
  - {name: dedup1, port: 9861, targetPort: 9861}
  - {name: translog, port: 7798, targetPort: 7798}
{{- end }}

{{/* shared ReadWriteMany claim of one engine */}}
{{- define "flare.pvcResource" -}}
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ .pvcName }}
  labels:
{{ include "flare.labels" . | indent 4 }}
spec:
  accessModes: [ReadWriteMany]
  storageClassName: {{ .Values.storage.className | quote }}
  resources:
    requests:
      storage: {{ .Values.storage.size }}
{{- end }}
