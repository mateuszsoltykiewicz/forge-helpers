{{/*
==============================================================================
Forge Common Library - PrometheusRule
==============================================================================
Templates for Prometheus alerting rules.

PrometheusRule defines alerting rules for common monitoring scenarios:
  - Application availability and health
  - Resource utilization (CPU, memory, disk)
  - Golden signals (latency, traffic, errors, saturation)
  - SLO-based alerting
  - Kubernetes workload health

Compatible with:
  - Prometheus Operator 0.60+
  - Kubernetes 1.23-1.29

Usage:
  {{- include "monitoring.prometheusrule" . }}

See Also:
  - https://prometheus-operator.dev/docs/operator/api/#prometheusrule
==============================================================================
*/}}

{{/*
==============================================================================
PrometheusRule: Main Template
==============================================================================
Generate custom PrometheusRule resource.

Usage:
  {{- include "monitoring.prometheusrule" . }}

Requirements:
  .Values.monitoring.prometheusrule.enabled = true
  .Values.monitoring.prometheusrule.groups (at least one rule group)

Output:
  apiVersion: monitoring.coreos.com/v1
  kind: PrometheusRule
  metadata:
    name: my-alerts
    namespace: monitoring
  spec:
    groups:
      - name: my-app-alerts
        interval: 30s
        rules:
          - alert: HighErrorRate
            expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.05
            for: 5m
            labels:
              severity: critical
            annotations:
              summary: High error rate detected
*/}}

{{- define "monitoring.prometheusrule" -}}
{{- if .Values.monitoring -}}
{{- if .Values.monitoring.prometheusrule -}}
{{- if .Values.monitoring.prometheusrule.enabled -}}
---
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "prometheusrule" "name" .Values.monitoring.prometheusrule.name) }}
  namespace: {{ .Values.monitoring.prometheusrule.namespace | default (include "forge.namespace" .) }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    {{- if .Values.monitoring.prometheusrule.labels }}
    {{- toYaml .Values.monitoring.prometheusrule.labels | nindent 4 }}
    {{- end }}
    {{- if .Values.monitoring.prometheusrule.prometheus }}
    prometheus: {{ .Values.monitoring.prometheusrule.prometheus }}
    {{- end }}
    {{- if .Values.monitoring.prometheusrule.role }}
    role: {{ .Values.monitoring.prometheusrule.role }}
    {{- end }}
  annotations:
    {{- with .Values.monitoring.prometheusrule.annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
spec:
  groups:
    {{- range .Values.monitoring.prometheusrule.groups }}
    - name: {{ .name | required "PrometheusRule group name is required" }}
      {{- with .interval }}
      interval: {{ . }}
      {{- end }}
      rules:
        {{- range .rules }}
        - alert: {{ .alert | required "Alert name is required" }}
          expr: {{ .expr | required "Alert expression is required" }}
          {{- with .for }}
          for: {{ . }}
          {{- end }}
          {{- with .labels }}
          labels:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          annotations:
            {{- if .annotations }}
            {{- toYaml .annotations | nindent 12 }}
            {{- else }}
            summary: "{{ .alert }}"
            description: "Alert {{ .alert }} triggered"
            {{- end }}
        {{- end }}
    {{- end }}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
PrometheusRule: Application Availability
==============================================================================
Pre-configured alerts for application availability and uptime.

Usage:
  {{- include "monitoring.prometheusrule.availability" . }}
*/}}

{{- define "monitoring.prometheusrule.availability" -}}
{{- if .Values.monitoring -}}
{{- if .Values.monitoring.alerts -}}
{{- if .Values.monitoring.alerts.availability -}}
{{- if .Values.monitoring.alerts.availability.enabled -}}
---
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "prometheusrule" "name" "availability") }}
  namespace: {{ .Values.monitoring.prometheusrule.namespace | default (include "forge.namespace" .) }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/alert-category: "availability"
spec:
  groups:
    - name: availability
      interval: 30s
      rules:
        # Application is down
        - alert: ApplicationDown
          expr: up{job="{{ include "forge.fullname" . }}"} == 0
          for: {{ .Values.monitoring.alerts.availability.downFor | default "2m" }}
          labels:
            severity: critical
            category: availability
          annotations:
            summary: "Application {{ include "forge.fullname" . }} is down"
            description: "The application has been unreachable for more than {{ .Values.monitoring.alerts.availability.downFor | default "2m" }}"
            runbook_url: "https://runbooks.example.com/ApplicationDown"
        
        # High error rate (5xx responses)
        - alert: HighErrorRate
          expr: |
            (
              sum(rate(http_requests_total{job="{{ include "forge.fullname" . }}", status=~"5.."}[5m]))
              /
              sum(rate(http_requests_total{job="{{ include "forge.fullname" . }}"}[5m]))
            ) > {{ .Values.monitoring.alerts.availability.errorRateThreshold | default 0.05 }}
          for: {{ .Values.monitoring.alerts.availability.errorFor | default "5m" }}
          labels:
            severity: {{ .Values.monitoring.alerts.availability.errorSeverity | default "warning" }}
            category: availability
          annotations:
            summary: "High error rate detected (>{{ .Values.monitoring.alerts.availability.errorRateThreshold | default 0.05 | mul 100 }}%)"
            description: "Error rate is {{`{{ printf \"%.2f\" $value | mul 100 }}`}}% for {{ include "forge.fullname" . }}"
            runbook_url: "https://runbooks.example.com/HighErrorRate"
        
        # High response time (latency)
        - alert: HighResponseTime
          expr: |
            histogram_quantile(0.99,
              sum(rate(http_request_duration_seconds_bucket{job="{{ include "forge.fullname" . }}"}[5m])) by (le)
            ) > {{ .Values.monitoring.alerts.availability.latencyThreshold | default 1 }}
          for: {{ .Values.monitoring.alerts.availability.latencyFor | default "5m" }}
          labels:
            severity: {{ .Values.monitoring.alerts.availability.latencySeverity | default "warning" }}
            category: availability
          annotations:
            summary: "High response time detected (p99 >{{ .Values.monitoring.alerts.availability.latencyThreshold | default 1 }}s)"
            description: "P99 latency is {{`{{ printf \"%.2f\" $value }}`}}s for {{ include "forge.fullname" . }}"
            runbook_url: "https://runbooks.example.com/HighResponseTime"
        
        # Low success rate
        - alert: LowSuccessRate
          expr: |
            (
              sum(rate(http_requests_total{job="{{ include "forge.fullname" . }}", status=~"2.."}[5m]))
              /
              sum(rate(http_requests_total{job="{{ include "forge.fullname" . }}"}[5m]))
            ) < {{ .Values.monitoring.alerts.availability.successRateThreshold | default 0.95 }}
          for: {{ .Values.monitoring.alerts.availability.successFor | default "5m" }}
          labels:
            severity: warning
            category: availability
          annotations:
            summary: "Low success rate (<{{ .Values.monitoring.alerts.availability.successRateThreshold | default 0.95 | mul 100 }}%)"
            description: "Success rate is {{`{{ printf \"%.2f\" $value | mul 100 }}`}}% for {{ include "forge.fullname" . }}"
            runbook_url: "https://runbooks.example.com/LowSuccessRate"
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
PrometheusRule: Resource Utilization
==============================================================================
Pre-configured alerts for CPU, memory, and disk resources.

Usage:
  {{- include "monitoring.prometheusrule.resources" . }}
*/}}

{{- define "monitoring.prometheusrule.resources" -}}
{{- if .Values.monitoring -}}
{{- if .Values.monitoring.alerts -}}
{{- if .Values.monitoring.alerts.resources -}}
{{- if .Values.monitoring.alerts.resources.enabled -}}
---
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "prometheusrule" "name" "resources") }}
  namespace: {{ .Values.monitoring.prometheusrule.namespace | default (include "forge.namespace" .) }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/alert-category: "resources"
spec:
  groups:
    - name: resources
      interval: 30s
      rules:
        # High CPU usage
        - alert: HighCPUUsage
          expr: |
            sum(rate(container_cpu_usage_seconds_total{namespace="{{ include "forge.namespace" . }}", pod=~"{{ include "forge.fullname" . }}-.*"}[5m])) by (pod)
            /
            sum(container_spec_cpu_quota{namespace="{{ include "forge.namespace" . }}", pod=~"{{ include "forge.fullname" . }}-.*"} / container_spec_cpu_period{namespace="{{ include "forge.namespace" . }}", pod=~"{{ include "forge.fullname" . }}-.*"}) by (pod)
            > {{ .Values.monitoring.alerts.resources.cpuThreshold | default 0.8 }}
          for: {{ .Values.monitoring.alerts.resources.cpuFor | default "5m" }}
          labels:
            severity: {{ .Values.monitoring.alerts.resources.cpuSeverity | default "warning" }}
            category: resources
          annotations:
            summary: "High CPU usage (>{{ .Values.monitoring.alerts.resources.cpuThreshold | default 0.8 | mul 100 }}%)"
            description: "Pod {{`{{ $labels.pod }}`}} CPU usage is {{`{{ printf \"%.2f\" $value | mul 100 }}`}}%"
            runbook_url: "https://runbooks.example.com/HighCPUUsage"
        
        # High memory usage
        - alert: HighMemoryUsage
          expr: |
            sum(container_memory_working_set_bytes{namespace="{{ include "forge.namespace" . }}", pod=~"{{ include "forge.fullname" . }}-.*"}) by (pod)
            /
            sum(container_spec_memory_limit_bytes{namespace="{{ include "forge.namespace" . }}", pod=~"{{ include "forge.fullname" . }}-.*"}) by (pod)
            > {{ .Values.monitoring.alerts.resources.memoryThreshold | default 0.8 }}
          for: {{ .Values.monitoring.alerts.resources.memoryFor | default "5m" }}
          labels:
            severity: {{ .Values.monitoring.alerts.resources.memorySeverity | default "warning" }}
            category: resources
          annotations:
            summary: "High memory usage (>{{ .Values.monitoring.alerts.resources.memoryThreshold | default 0.8 | mul 100 }}%)"
            description: "Pod {{`{{ $labels.pod }}`}} memory usage is {{`{{ printf \"%.2f\" $value | mul 100 }}`}}%"
            runbook_url: "https://runbooks.example.com/HighMemoryUsage"
        
        # Pod restarts
        - alert: PodRestartingFrequently
          expr: |
            rate(kube_pod_container_status_restarts_total{namespace="{{ include "forge.namespace" . }}", pod=~"{{ include "forge.fullname" . }}-.*"}[15m]) > {{ .Values.monitoring.alerts.resources.restartRateThreshold | default 0.01 }}
          for: {{ .Values.monitoring.alerts.resources.restartFor | default "5m" }}
          labels:
            severity: warning
            category: resources
          annotations:
            summary: "Pod restarting frequently"
            description: "Pod {{`{{ $labels.pod }}`}} is restarting {{`{{ printf \"%.2f\" $value | mul 60 }}`}} times per minute"
            runbook_url: "https://runbooks.example.com/PodRestartingFrequently"
        
        # Pod not ready
        - alert: PodNotReady
          expr: |
            kube_pod_status_ready{namespace="{{ include "forge.namespace" . }}", pod=~"{{ include "forge.fullname" . }}-.*", condition="true"} == 0
          for: {{ .Values.monitoring.alerts.resources.notReadyFor | default "5m" }}
          labels:
            severity: warning
            category: resources
          annotations:
            summary: "Pod not ready"
            description: "Pod {{`{{ $labels.pod }}`}} has been not ready for more than {{ .Values.monitoring.alerts.resources.notReadyFor | default "5m" }}"
            runbook_url: "https://runbooks.example.com/PodNotReady"
        
        # Deployment replica mismatch
        - alert: DeploymentReplicaMismatch
          expr: |
            kube_deployment_spec_replicas{namespace="{{ include "forge.namespace" . }}", deployment="{{ include "forge.fullname" . }}"}
            !=
            kube_deployment_status_replicas_available{namespace="{{ include "forge.namespace" . }}", deployment="{{ include "forge.fullname" . }}"}
          for: {{ .Values.monitoring.alerts.resources.replicaMismatchFor | default "10m" }}
          labels:
            severity: warning
            category: resources
          annotations:
            summary: "Deployment replica mismatch"
            description: "Deployment {{ include "forge.fullname" . }} has {{`{{ $labels.spec_replicas }}`}} desired but only {{`{{ $labels.available_replicas }}`}} available"
            runbook_url: "https://runbooks.example.com/DeploymentReplicaMismatch"
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
PrometheusRule: SLO-based Alerts
==============================================================================
Pre-configured alerts based on Service Level Objectives.

Usage:
  {{- include "monitoring.prometheusrule.slo" . }}
*/}}

{{- define "monitoring.prometheusrule.slo" -}}
{{- if .Values.monitoring -}}
{{- if .Values.monitoring.alerts -}}
{{- if .Values.monitoring.alerts.slo -}}
{{- if .Values.monitoring.alerts.slo.enabled -}}
---
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "prometheusrule" "name" "slo") }}
  namespace: {{ .Values.monitoring.prometheusrule.namespace | default (include "forge.namespace" .) }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/alert-category: "slo"
spec:
  groups:
    - name: slo
      interval: 1m
      rules:
        # SLO: Availability target (e.g., 99.9%)
        - alert: SLOAvailabilityBudgetBurn
          expr: |
            (
              1 - (
                sum(rate(http_requests_total{job="{{ include "forge.fullname" . }}", status!~"5.."}[1h]))
                /
                sum(rate(http_requests_total{job="{{ include "forge.fullname" . }}"}[1h]))
              )
            ) > (1 - {{ .Values.monitoring.alerts.slo.availabilityTarget | default 0.999 }})
          for: 5m
          labels:
            severity: critical
            category: slo
          annotations:
            summary: "SLO availability budget burning fast"
            description: "Current error budget burn rate will exhaust the {{ .Values.monitoring.alerts.slo.availabilityTarget | default 0.999 | mul 100 }}% SLO"
            runbook_url: "https://runbooks.example.com/SLOAvailabilityBudgetBurn"
        
        # SLO: Latency target (e.g., p99 < 1s)
        - alert: SLOLatencyBudgetBurn
          expr: |
            histogram_quantile(0.99,
              sum(rate(http_request_duration_seconds_bucket{job="{{ include "forge.fullname" . }}"}[1h])) by (le)
            ) > {{ .Values.monitoring.alerts.slo.latencyTarget | default 1 }}
          for: 5m
          labels:
            severity: warning
            category: slo
          annotations:
            summary: "SLO latency budget burning"
            description: "P99 latency {{`{{ printf \"%.2f\" $value }}`}}s exceeds {{ .Values.monitoring.alerts.slo.latencyTarget | default 1 }}s target"
            runbook_url: "https://runbooks.example.com/SLOLatencyBudgetBurn"
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
