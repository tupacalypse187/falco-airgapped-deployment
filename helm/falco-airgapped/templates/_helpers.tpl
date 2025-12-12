{{/*
Expand the name of the chart.
*/}}
{{- define "falco-airgapped.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "falco-airgapped.fullname" -}}
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

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "falco-airgapped.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "falco-airgapped.labels" -}}
helm.sh/chart: {{ include "falco-airgapped.chart" . }}
{{ include "falco-airgapped.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "falco-airgapped.selectorLabels" -}}
app.kubernetes.io/name: {{ include "falco-airgapped.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "falco-airgapped.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "falco-airgapped.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the proper image name
*/}}
{{- define "falco-airgapped.image" -}}
{{- $registry := .Values.image.registry -}}
{{- $repository := .Values.image.repository -}}
{{- $tag := .Values.image.tag | toString -}}
{{- if $registry }}
{{- printf "%s/%s:%s" $registry $repository $tag -}}
{{- else }}
{{- printf "%s:%s" $repository $tag -}}
{{- end }}
{{- end }}

{{/*
Return the proper plugin loader image name
*/}}
{{- define "falco-airgapped.pluginLoaderImage" -}}
{{- $registry := .Values.pluginLoader.image.registry -}}
{{- $repository := .Values.pluginLoader.image.repository -}}
{{- $tag := .Values.pluginLoader.image.tag | toString -}}
{{- if $registry }}
{{- printf "%s/%s:%s" $registry $repository $tag -}}
{{- else }}
{{- printf "%s:%s" $repository $tag -}}
{{- end }}
{{- end }}

{{/*
Return the proper driver loader image name
*/}}
{{- define "falco-airgapped.driverLoaderImage" -}}
{{- $registry := .Values.driver.loader.initContainer.image.registry -}}
{{- $repository := .Values.driver.loader.initContainer.image.repository -}}
{{- $tag := .Values.driver.loader.initContainer.image.tag | toString -}}
{{- if $registry }}
{{- printf "%s/%s:%s" $registry $repository $tag -}}
{{- else }}
{{- printf "%s:%s" $repository $tag -}}
{{- end }}
{{- end }}

{{/*
Check if sidecar plugin loading is enabled
*/}}
{{- define "falco-airgapped.useSidecarPluginLoader" -}}
{{- if and .Values.pluginLoader.enabled (eq .Values.pluginLoadingStrategy "sidecar") }}
true
{{- else }}
false
{{- end }}
{{- end }}

{{/*
Check if S3 plugin loading is enabled
*/}}
{{- define "falco-airgapped.useS3PluginLoader" -}}
{{- if and .Values.s3PluginLoader.enabled (eq .Values.pluginLoadingStrategy "s3") }}
true
{{- else }}
false
{{- end }}
{{- end }}
