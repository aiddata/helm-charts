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

{{/*
Public URL of the MCP server, without a trailing slash: mcp.baseUrl, or the
website's django.baseUrl when that is unset. The backend registers
{this}/auth/callback as the OIDC client's redirect URI and the MCP server
builds the same URI, and the provider matches it exactly, so every workload
must render it from here.
*/}}
{{- define "geoquery.mcpBaseUrl" -}}
{{- .Values.mcp.baseUrl | default .Values.django.baseUrl | trimSuffix "/" -}}
{{- end -}}

{{/*
Hostname (no port) of mcp.baseUrl when it differs from django.baseUrl's, else
empty. geoquery-proxy serves the MCP server on a server block of its own for
that host; when empty it routes the MCP paths on the website's hostname.
*/}}
{{- define "geoquery.mcpDedicatedHost" -}}
{{- $mcpHost := regexReplaceAll ":[0-9]+$" (urlParse (include "geoquery.mcpBaseUrl" .)).host "" -}}
{{- $siteHost := regexReplaceAll ":[0-9]+$" (urlParse .Values.django.baseUrl).host "" -}}
{{- if ne $mcpHost $siteHost }}{{ $mcpHost }}{{ end -}}
{{- end -}}

{{/*
Path the MCP tool endpoint is served on, which follows the topology:

* On a hostname of its own, "/" -- clients connect to mcp.baseUrl with nothing
  appended. FastMCP registers the tool endpoint as an exact-match route, so
  the OAuth routes it also serves at the root (/authorize, /token, ...) keep
  their own paths alongside it.
* On the website's hostname, "/mcp" -- the root there belongs to the frontend.

Both `run_mcp --path` and the proxy's location block render from here. Split
them and the proxy would route a path the server does not serve.
*/}}
{{- define "geoquery.mcpPath" -}}
{{- if include "geoquery.mcpDedicatedHost" . }}/{{ else }}/mcp{{ end -}}
{{- end -}}
