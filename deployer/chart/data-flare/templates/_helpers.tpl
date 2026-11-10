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
{{- with .pvcName }}
flare.ligadata.com/volume: {{ . }}
{{- end }}
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
{{- /* a ReadWriteOnce block disk attaches to one node: every pod mounting the same claim must land
       there. Required pod affinity on the volume label does that; the first pod of a group matches
       its own labels, so it schedules anywhere. Needs the ctx dict (.pvcName). */ -}}
{{- if and .pvcName (eq .Values.storage.accessMode "ReadWriteOnce") }}
affinity:
  podAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - topologyKey: kubernetes.io/hostname
      labelSelector:
        matchLabels:
          flare.ligadata.com/volume: {{ .pvcName }}
{{- end }}
{{- end }}

{{/* The web UI (User.scala) accepts a password only when it matches
     ^(?=.*[0-9])(?=.*[a-z])(?=.*[A-Z])(?=.*[@#$%^&+=_!*])(?=\S+$).{8,}$ : the special character must come
     from that exact set. A GENERATED_PASSWORD from the deployer is random and may miss a class or use another
     symbol, so a supplied value has whitespace removed and a character appended for each class it lacks
     (deterministic: the Secret is stable across upgrades). usage: include "flare.policyPassword" <password> */}}
{{- define "flare.policyPassword" -}}
{{- $p := regexReplaceAll "\\s" (toString .) "" -}}
{{- if not (regexMatch "[A-Z]" $p) }}{{ $p = printf "%sQ" $p }}{{ end -}}
{{- if not (regexMatch "[a-z]" $p) }}{{ $p = printf "%sx" $p }}{{ end -}}
{{- if not (regexMatch "[0-9]" $p) }}{{ $p = printf "%s7" $p }}{{ end -}}
{{- if not (regexMatch "[@#$%^&+=_!*]" $p) }}{{ $p = printf "%s!" $p }}{{ end -}}
{{- if lt (len $p) 8 }}{{ $p = printf "%sQx7!Qx7!" $p }}{{ end -}}
{{- $p -}}
{{- end -}}
