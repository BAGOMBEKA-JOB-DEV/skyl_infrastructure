{{/*
Name helpers. Standard Helm shape; nothing surprising.
*/}}
{{- define "skyl-gateway.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "skyl-gateway.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "skyl-gateway.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "skyl-gateway.labels" -}}
helm.sh/chart: {{ include "skyl-gateway.chart" . }}
{{ include "skyl-gateway.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: skyl
{{- end }}

{{- define "skyl-gateway.selectorLabels" -}}
app.kubernetes.io/name: {{ include "skyl-gateway.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "skyl-gateway.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "skyl-gateway.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Image reference.

Digest wins. A tag is only allowed when it is asked for explicitly AND a digest
was not supplied, and that combination is what image.allowMutableTag exists to
make deliberate — it is for kind and CI, and CI policy rejects it everywhere
else. Failing here with a readable message beats deploying a mutable reference
that nobody notices until a rollback lands on different bytes.
*/}}
{{- define "skyl-gateway.image" -}}
{{- $repo := .Values.image.repository -}}
{{- if .Values.image.digest -}}
{{- if not (hasPrefix "sha256:" .Values.image.digest) -}}
{{- fail (printf "image.digest must start with 'sha256:', got %q" .Values.image.digest) -}}
{{- end -}}
{{- printf "%s@%s" $repo .Values.image.digest -}}
{{- else if and .Values.image.tag .Values.image.allowMutableTag -}}
{{- printf "%s:%s" $repo .Values.image.tag -}}
{{- else -}}
{{- fail "image.digest is required. Take it from skyl's publish-image workflow summary. To use a mutable tag for local testing, set image.tag and image.allowMutableTag=true." -}}
{{- end -}}
{{- end }}

{{/*
Environment variables from .Values.config.

Only non-empty values are emitted. The gateway treats an empty string as a
malformed value for the duration and integer settings and exits 1, so passing
`SKYL_MAX_RETRIES=""` is worse than not passing it at all — omission means
"use the documented default", which is what an unset value in the chart means
too.
*/}}
{{- define "skyl-gateway.configEnv" -}}
{{- $c := .Values.config -}}
- name: SKYL_ADDR
  value: {{ $c.addr | quote }}
- name: SKYL_METRICS
  value: {{ $c.metrics | quote }}
- name: SKYL_INCLUDE_RAW
  value: {{ $c.includeRaw | quote }}
- name: SKYL_MAX_CONCURRENT
  value: {{ $c.maxConcurrent | quote }}
{{- with $c.allowedOrigins }}
- name: SKYL_ALLOWED_ORIGINS
  value: {{ join "," . | quote }}
{{- end }}
{{- with $c.defaultProvider }}
- name: SKYL_DEFAULT_PROVIDER
  value: {{ . | quote }}
{{- end }}
{{- with $c.requestTimeout }}
- name: SKYL_REQUEST_TIMEOUT
  value: {{ . | quote }}
{{- end }}
{{- with $c.attemptTimeout }}
- name: SKYL_ATTEMPT_TIMEOUT
  value: {{ . | quote }}
{{- end }}
{{- with $c.maxRetries }}
- name: SKYL_MAX_RETRIES
  value: {{ . | quote }}
{{- end }}
{{- with $c.retryBaseDelay }}
- name: SKYL_RETRY_BASE_DELAY
  value: {{ . | quote }}
{{- end }}
{{- with $c.retryMaxDelay }}
- name: SKYL_RETRY_MAX_DELAY
  value: {{ . | quote }}
{{- end }}
{{- with $c.retryAfterCap }}
- name: SKYL_RETRY_AFTER_CAP
  value: {{ . | quote }}
{{- end }}
{{- with $c.heartbeatInterval }}
- name: SKYL_HEARTBEAT_INTERVAL
  value: {{ . | quote }}
{{- end }}
{{- end }}

{{/*
The Secret name the pod mounts: either the one External Secrets materialises,
or a pre-existing one for kind/CI.
*/}}
{{- define "skyl-gateway.secretName" -}}
{{- if .Values.secrets.existingSecret -}}
{{- .Values.secrets.existingSecret -}}
{{- else -}}
{{- include "skyl-gateway.fullname" . -}}
{{- end -}}
{{- end }}
