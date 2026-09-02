{{/*
Render an env entry whose value comes from an existing Secret in the release
namespace. Secrets are created and managed outside this chart, so nothing
sensitive has to live in values.yaml.

Usage:
  {{- include "geoquery.secretEnv" (dict "name" "DJANGO_SECRET_KEY" "ref" .Values.django.secretKey) | nindent 12 }}

Renders nothing when the ref has no secretName, which leaves the variable
unset in the container — the way to disable an optional setting.
*/}}
{{- define "geoquery.secretEnv" -}}
{{- $ref := .ref | default dict -}}
{{- if $ref.secretName -}}
- name: {{ .name }}
  valueFrom:
    secretKeyRef:
      name: {{ $ref.secretName }}
      key: {{ $ref.key | default "password" }}
{{- end -}}
{{- end -}}

{{/*
Host the processing-worker autoscaler reads the pending task count from.
Prefer the ro pooler (a slightly stale count from a replica is fine), then
the rw pooler, then the primary service directly -- the same fallback order
the backend uses for its read-only connection. The NetworkPolicy exceptions
for the KEDA operator in networkpolicies/pooler.yaml and database.yaml are
conditioned on the same choices; keep them in step with this.

The name is namespace-qualified because the lookup is done by the KEDA
operator from its own namespace, where a bare Service name does not resolve.
*/}}
{{- define "geoquery.processingAutoscaling.dbHost" -}}
{{- if and .Values.database.pooler.enabled .Values.database.pooler.ro.enabled -}}
geoquery-db-pooler-ro.{{ .Release.Namespace }}.svc
{{- else if .Values.database.pooler.enabled -}}
geoquery-db-pooler-rw.{{ .Release.Namespace }}.svc
{{- else -}}
geoquery-db-rw.{{ .Release.Namespace }}.svc
{{- end -}}
{{- end -}}
