{{/* Labels. app.kubernetes.io/name must equal the Application instance name (the deployer's rule). */}}
{{- define "flare.labels" -}}
app.kubernetes.io/name: {{ .Release.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
{{- end }}

{{/* labels every pod template carries: Application selector plus Marketplace consumption tracking */}}
{{- define "flare.podLabels" -}}
app.kubernetes.io/name: {{ .Release.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Values.marketplace.solutionUrn }}
goog-partner-solution: {{ .Values.marketplace.solutionUrn | quote }}
{{- end }}
{{- end }}

{{/* usage: include "flare.image" (dict "Values" .Values "name" "dismain") */}}
{{- define "flare.image" -}}
{{- $i := index .Values.images .name -}}
{{ $i.repository }}:{{ $i.tag }}
{{- end }}

{{/* rendering context for one engine: the control plane's built-in engine or the environment.
     keys: root, p (resource-name prefix incl. trailing dash), mode (control|environment), env (name or ""),
     pvcName, secretName. "flare.ctx" copies Values/Release/Chart in so helpers work on it. */}}
{{- define "flare.ctx" -}}
{{- $_ := set . "Values" .root.Values }}{{- $_ := set . "Release" .root.Release }}{{- $_ := set . "Chart" .root.Chart }}
{{- end }}

{{/* the ServiceAccount provisioned by Marketplace (schema SERVICE_ACCOUNT); "default" outside Marketplace */}}
{{- define "flare.sa" -}}
{{ .Values.serviceAccount | default "default" }}
{{- end }}

{{- define "flare.dbHost" -}}
{{- if .Values.database.internal }}{{ .Release.Name }}-postgres{{ else }}{{ required "database.host is required when database.internal=false" .Values.database.host }}{{ end }}
{{- end }}

{{- define "flare.pullSecrets" -}}
{{- with .Values.imagePullSecrets }}
imagePullSecrets:
{{- range . }}
- name: {{ . }}
{{- end }}
{{- end }}
{{- end }}

{{/* copies the engine's hosts file and krb5.conf into the container at start, as on the reference install */}}
{{- define "flare.postStart" -}}
lifecycle:
  postStart:
    exec:
      command:
      - /bin/sh
      - -c
      - sudo sh -c '[ -f /opt/Flare4/DI/config/hosts ] && cat /opt/Flare4/DI/config/hosts >> /etc/hosts; [ -f /opt/Flare4/DI/config/krb5.conf ] && cp /opt/Flare4/DI/config/krb5.conf /etc/krb5.conf; true'
{{- end }}

{{/* init container that fills the shared volume on first start and waits otherwise */}}
{{- define "flare.seedInit" -}}
- name: seed
  image: {{ include "flare.image" (dict "Values" .Values "name" "seed") }}
  imagePullPolicy: {{ .Values.imagePullPolicy }}
  command: ["/bin/sh", "/seed.sh"]
  env:
  - name: FLARE_MODE
    value: {{ .mode | quote }}
  - name: NAMESPACE
    valueFrom:
      fieldRef:
        fieldPath: metadata.namespace
  - name: HOST_PREFIX
    value: {{ .p | quote }}
  volumeMounts:
  - name: flare-data
    mountPath: /data
  - name: license
    mountPath: /license
    readOnly: true
  resources:
{{ toYaml .Values.resources.seed | indent 4 }}
{{- end }}

{{- define "flare.sharedVolumes" -}}
- name: flare-data
  persistentVolumeClaim:
    claimName: {{ .pvcName }}
- name: license
  secret:
    secretName: {{ .Release.Name }}-ligadata-license
    optional: true
{{- end }}

{{- define "flare.engineSecretEnv" -}}
- name: DIExecServerManager.secretKey
  valueFrom:
    secretKeyRef:
      name: {{ .secretName }}
      key: DI_secretKey
- name: DI_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ .secretName }}
      key: DI_secretKey
- name: TZ
  value: {{ .Values.timezone | quote }}
- name: HADOOP_USER_NAME
  value: {{ .Values.hadoopUserName | quote }}
# the engine finds Redis through this variable (Kubernetes would inject it only for a Service named "redis")
- name: REDIS_SERVICE_HOST
  value: {{ .Release.Name }}-redis
{{- end }}

{{- define "flare.scheduling" -}}
{{- with .Values.nodeSelector }}
nodeSelector:
{{ toYaml . | indent 2 }}
{{- end }}
{{- with .Values.tolerations }}
tolerations:
{{ toYaml . | indent 2 }}
{{- end }}
{{- end }}
