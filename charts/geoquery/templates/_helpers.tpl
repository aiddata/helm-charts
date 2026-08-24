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
