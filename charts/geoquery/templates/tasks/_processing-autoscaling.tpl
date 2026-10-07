{{/* Fresh desired replicas anchor missing-series handling to a healthy KSM scrape. */}}
{{- define "geoquery.processingAutoscaling.current" -}}
max(
  kube_deployment_spec_replicas{namespace={{ .Release.Namespace | quote }},deployment="processing-worker"}
  and (timestamp(kube_deployment_spec_replicas{namespace={{ .Release.Namespace | quote }},deployment="processing-worker"}) > time() - {{ .Values.tasks.processing.autoscaling.claimContention.metricMaxAgeSeconds }})
  and on(job,instance) (up{job="kube-state-metrics"} == 1)
)
{{- end -}}

{{/* Include pending and terminating workers; their missing metrics must hold scaling. */}}
{{- define "geoquery.processingAutoscaling.expected" -}}
max by (pod) (
  kube_pod_status_phase{namespace={{ .Release.Namespace | quote }},pod=~"processing-worker-[^-]+-[^-]+",phase=~"Pending|Running"} == 1
)
{{- end -}}

{{/* A usable worker needs a live scrape, all gauges and enough counter history. */}}
{{- define "geoquery.processingAutoscaling.workers" -}}
{{- $age := .Values.tasks.processing.autoscaling.claimContention.metricMaxAgeSeconds -}}
{{- $selector := printf "namespace=%q,job=%q" .Release.Namespace (printf "%s/geoquery-processing-worker" .Release.Namespace) -}}
(
  rate(geoquery_extract_dispatch_seconds_sum{ {{ $selector }},stage="claim" }[{{ .Values.tasks.processing.autoscaling.claimContention.utilizationWindow }}])
  and (timestamp(geoquery_extract_dispatch_seconds_sum{ {{ $selector }},stage="claim" }) > time() - {{ $age }})
  and on(pod) (up{ {{ $selector }} } == 1)
  and on(pod) (geoquery_extract_slots{ {{ $selector }} } == {{ .Values.tasks.processing.concurrency }})
  and on(pod) (timestamp(geoquery_extract_slots{ {{ $selector }} }) > time() - {{ $age }})
  and on(pod) geoquery_extract_active_chunks{ {{ $selector }} }
  and on(pod) (timestamp(geoquery_extract_active_chunks{ {{ $selector }} }) > time() - {{ $age }})
  and on(pod) ({{ include "geoquery.processingAutoscaling.expected" . }})
)
{{- end -}}

{{/* Return no series on incomplete coverage, making KEDA hold rather than infer idle. */}}
{{- define "geoquery.processingAutoscaling.coverage" -}}
(
  (count({{ include "geoquery.processingAutoscaling.expected" . }}) >= ({{ include "geoquery.processingAutoscaling.current" . }}))
  and on() (
    (count(
      ({{ include "geoquery.processingAutoscaling.expected" . }})
      unless on(pod) ({{ include "geoquery.processingAutoscaling.workers" . }})
    ) or vector(0)) == 0
  )
)
{{- end -}}

{{- define "geoquery.processingAutoscaling.claim" -}}
sum({{ include "geoquery.processingAutoscaling.workers" . }})
and on() ({{ include "geoquery.processingAutoscaling.coverage" . }})
{{- end -}}

{{- define "geoquery.processingAutoscaling.occupied" -}}
ceil(sum(
  geoquery_extract_active_chunks{namespace={{ .Release.Namespace | quote }},job={{ printf "%s/geoquery-processing-worker" .Release.Namespace | quote }}}
  and on(pod) ({{ include "geoquery.processingAutoscaling.workers" . }})
) / {{ .Values.tasks.processing.concurrency }})
and on() ({{ include "geoquery.processingAutoscaling.coverage" . }})
{{- end -}}

{{- define "geoquery.processingAutoscaling.draining" -}}
(
  count(kube_pod_deletion_timestamp{namespace={{ .Release.Namespace | quote }},pod=~"processing-worker-[^-]+-[^-]+"} > 0)
  or (0 * ({{ include "geoquery.processingAutoscaling.current" . }}))
)
and on() ({{ include "geoquery.processingAutoscaling.current" . }})
{{- end -}}
