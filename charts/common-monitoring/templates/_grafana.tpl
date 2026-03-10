{{/*
==============================================================================
Forge Common Library - Grafana Dashboard
==============================================================================
Templates for Grafana dashboard ConfigMaps.

Dashboard ConfigMaps are automatically discovered by Grafana sidecar:
  - Application metrics dashboard (golden signals)
  - Infrastructure dashboard (Kubernetes resources)
  - Custom dashboards from values

Compatible with:
  - Grafana 9.0+ (tested with 10.2.0)
  - Grafana sidecar for automatic provisioning
  - Kubernetes 1.23-1.29

Usage:
  {{- include "monitoring.grafana.dashboard" . }}

See Also:
  - https://grafana.com/docs/grafana/latest/dashboards/
==============================================================================
*/}}

{{/*
==============================================================================
Grafana Dashboard: Main Template
==============================================================================
Generate ConfigMap with Grafana dashboard JSON.

Usage:
  {{- include "monitoring.grafana.dashboard" . }}

Requirements:
  .Values.monitoring.grafana.dashboard.enabled = true
  .Values.monitoring.grafana.dashboard.json (dashboard JSON content)

Output:
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: my-dashboard
    namespace: monitoring
    labels:
      grafana_dashboard: "1"
  data:
    my-dashboard.json: |
      {...dashboard JSON...}
*/}}

{{- define "monitoring.grafana.dashboard" -}}
{{- if .Values.monitoring -}}
{{- if .Values.monitoring.grafana -}}
{{- if .Values.monitoring.grafana.dashboard -}}
{{- if .Values.monitoring.grafana.dashboard.enabled -}}
{{- if .Values.monitoring.grafana.dashboard.name -}}
{{- if .Values.monitoring.grafana.dashboard.json -}}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "dashboard" "name" .Values.monitoring.grafana.dashboard.name) }}
  namespace: {{ .Values.monitoring.grafana.dashboard.namespace | default (include "forge.namespace" .) }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    grafana_dashboard: "1"
    {{- with .Values.monitoring.grafana.dashboard.labels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  annotations:
    {{- with .Values.monitoring.grafana.dashboard.annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
data:
  {{- $dashboardName := printf "%s.json" (include "forge.resourceName" (dict "context" . "type" "dashboard" "name" .Values.monitoring.grafana.dashboard.name)) }}
  {{ $dashboardName }}: |
    {{- .Values.monitoring.grafana.dashboard.json | nindent 4 }}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
Grafana Dashboard: Application Metrics
==============================================================================
Pre-configured dashboard for application golden signals.

Usage:
  {{- include "monitoring.grafana.dashboard.application" . }}
*/}}

{{- define "monitoring.grafana.dashboard.application" -}}
{{- if .Values.monitoring -}}
{{- if .Values.monitoring.grafana -}}
{{- if .Values.monitoring.grafana.dashboards -}}
{{- if .Values.monitoring.grafana.dashboards.application -}}
{{- if .Values.monitoring.grafana.dashboards.application.enabled -}}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "dashboard" "name" "application") }}
  namespace: {{ .Values.monitoring.grafana.dashboard.namespace | default (include "forge.namespace" .) }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    grafana_dashboard: "1"
    moai.forge.io/dashboard-type: "application"
data:
  application-metrics.json: |
    {
      "annotations": {
        "list": [
          {
            "builtIn": 1,
            "datasource": "-- Grafana --",
            "enable": true,
            "hide": true,
            "iconColor": "rgba(0, 211, 255, 1)",
            "name": "Annotations & Alerts",
            "type": "dashboard"
          }
        ]
      },
      "editable": true,
      "gnetId": null,
      "graphTooltip": 0,
      "id": null,
      "links": [],
      "panels": [
        {
          "datasource": "Prometheus",
          "fieldConfig": {
            "defaults": {
              "mappings": [],
              "thresholds": {
                "mode": "absolute",
                "steps": [
                  {"color": "green", "value": null},
                  {"color": "red", "value": 0}
                ]
              }
            }
          },
          "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0},
          "id": 1,
          "options": {
            "colorMode": "value",
            "graphMode": "area",
            "justifyMode": "auto",
            "orientation": "auto",
            "reduceOptions": {
              "calcs": ["lastNotNull"],
              "fields": "",
              "values": false
            }
          },
          "pluginVersion": "10.2.0",
          "targets": [
            {
              "expr": "up{job=\"{{ include "forge.fullname" . }}\"}",
              "refId": "A"
            }
          ],
          "title": "Availability",
          "type": "stat"
        },
        {
          "datasource": "Prometheus",
          "fieldConfig": {
            "defaults": {
              "unit": "reqps"
            }
          },
          "gridPos": {"h": 4, "w": 6, "x": 6, "y": 0},
          "id": 2,
          "options": {
            "colorMode": "value",
            "graphMode": "area",
            "reduceOptions": {"calcs": ["lastNotNull"]}
          },
          "targets": [
            {
              "expr": "sum(rate(http_requests_total{job=\"{{ include "forge.fullname" . }}\"}[5m]))",
              "refId": "A"
            }
          ],
          "title": "Request Rate",
          "type": "stat"
        },
        {
          "datasource": "Prometheus",
          "fieldConfig": {
            "defaults": {
              "unit": "percentunit"
            }
          },
          "gridPos": {"h": 4, "w": 6, "x": 12, "y": 0},
          "id": 3,
          "options": {
            "colorMode": "value",
            "graphMode": "area",
            "reduceOptions": {"calcs": ["lastNotNull"]}
          },
          "targets": [
            {
              "expr": "sum(rate(http_requests_total{job=\"{{ include "forge.fullname" . }}\",status=~\"5..\"}[5m])) / sum(rate(http_requests_total{job=\"{{ include "forge.fullname" . }}\"}[5m]))",
              "refId": "A"
            }
          ],
          "title": "Error Rate",
          "type": "stat"
        },
        {
          "datasource": "Prometheus",
          "fieldConfig": {
            "defaults": {
              "unit": "s"
            }
          },
          "gridPos": {"h": 4, "w": 6, "x": 18, "y": 0},
          "id": 4,
          "options": {
            "colorMode": "value",
            "graphMode": "area",
            "reduceOptions": {"calcs": ["lastNotNull"]}
          },
          "targets": [
            {
              "expr": "histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket{job=\"{{ include "forge.fullname" . }}\"}[5m])) by (le))",
              "refId": "A"
            }
          ],
          "title": "P99 Latency",
          "type": "stat"
        },
        {
          "datasource": "Prometheus",
          "fieldConfig": {
            "defaults": {
              "custom": {"drawStyle": "line", "fillOpacity": 10}
            }
          },
          "gridPos": {"h": 8, "w": 12, "x": 0, "y": 4},
          "id": 5,
          "options": {
            "legend": {"displayMode": "list", "placement": "bottom"}
          },
          "targets": [
            {
              "expr": "sum(rate(http_requests_total{job=\"{{ include "forge.fullname" . }}\"}[5m])) by (status)",
              "legendFormat": "{{`{{ status }}`}}",
              "refId": "A"
            }
          ],
          "title": "Request Rate by Status",
          "type": "timeseries"
        },
        {
          "datasource": "Prometheus",
          "fieldConfig": {
            "defaults": {
              "custom": {"drawStyle": "line", "fillOpacity": 10},
              "unit": "s"
            }
          },
          "gridPos": {"h": 8, "w": 12, "x": 12, "y": 4},
          "id": 6,
          "options": {
            "legend": {"displayMode": "list", "placement": "bottom"}
          },
          "targets": [
            {
              "expr": "histogram_quantile(0.50, sum(rate(http_request_duration_seconds_bucket{job=\"{{ include "forge.fullname" . }}\"}[5m])) by (le))",
              "legendFormat": "p50",
              "refId": "A"
            },
            {
              "expr": "histogram_quantile(0.90, sum(rate(http_request_duration_seconds_bucket{job=\"{{ include "forge.fullname" . }}\"}[5m])) by (le))",
              "legendFormat": "p90",
              "refId": "B"
            },
            {
              "expr": "histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket{job=\"{{ include "forge.fullname" . }}\"}[5m])) by (le))",
              "legendFormat": "p99",
              "refId": "C"
            }
          ],
          "title": "Response Time Percentiles",
          "type": "timeseries"
        }
      ],
      "refresh": "30s",
      "schemaVersion": 38,
      "style": "dark",
      "tags": ["application", "golden-signals", "{{ include "forge.fullname" . }}"],
      "templating": {"list": []},
      "time": {"from": "now-6h", "to": "now"},
      "timepicker": {},
      "timezone": "",
      "title": "{{ include "forge.fullname" . }} - Application Metrics",
      "uid": "{{ include "forge.fullname" . }}-app",
      "version": 1
    }
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
Grafana Dashboard: Infrastructure Metrics
==============================================================================
Pre-configured dashboard for Kubernetes resource metrics.

Usage:
  {{- include "monitoring.grafana.dashboard.infrastructure" . }}
*/}}

{{- define "monitoring.grafana.dashboard.infrastructure" -}}
{{- if .Values.monitoring -}}
{{- if .Values.monitoring.grafana -}}
{{- if .Values.monitoring.grafana.dashboards -}}
{{- if .Values.monitoring.grafana.dashboards.infrastructure -}}
{{- if .Values.monitoring.grafana.dashboards.infrastructure.enabled -}}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "dashboard" "name" "infrastructure") }}
  namespace: {{ .Values.monitoring.grafana.dashboard.namespace | default (include "forge.namespace" .) }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    grafana_dashboard: "1"
    moai.forge.io/dashboard-type: "infrastructure"
data:
  infrastructure-metrics.json: |
    {
      "annotations": {"list": []},
      "editable": true,
      "gnetId": null,
      "graphTooltip": 0,
      "id": null,
      "links": [],
      "panels": [
        {
          "datasource": "Prometheus",
          "fieldConfig": {"defaults": {"unit": "percentunit"}},
          "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
          "id": 1,
          "targets": [
            {
              "expr": "sum(rate(container_cpu_usage_seconds_total{namespace=\"{{ include "forge.namespace" . }}\",pod=~\"{{ include "forge.fullname" . }}-.*\"}[5m])) by (pod) / sum(container_spec_cpu_quota{namespace=\"{{ include "forge.namespace" . }}\",pod=~\"{{ include "forge.fullname" . }}-.*\"} / container_spec_cpu_period{namespace=\"{{ include "forge.namespace" . }}\",pod=~\"{{ include "forge.fullname" . }}-.*\"}) by (pod)",
              "legendFormat": "{{`{{ pod }}`}}",
              "refId": "A"
            }
          ],
          "title": "CPU Usage by Pod",
          "type": "timeseries"
        },
        {
          "datasource": "Prometheus",
          "fieldConfig": {"defaults": {"unit": "bytes"}},
          "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
          "id": 2,
          "targets": [
            {
              "expr": "sum(container_memory_working_set_bytes{namespace=\"{{ include "forge.namespace" . }}\",pod=~\"{{ include "forge.fullname" . }}-.*\"}) by (pod)",
              "legendFormat": "{{`{{ pod }}`}}",
              "refId": "A"
            }
          ],
          "title": "Memory Usage by Pod",
          "type": "timeseries"
        },
        {
          "datasource": "Prometheus",
          "fieldConfig": {"defaults": {}},
          "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
          "id": 3,
          "targets": [
            {
              "expr": "sum(rate(container_network_receive_bytes_total{namespace=\"{{ include "forge.namespace" . }}\",pod=~\"{{ include "forge.fullname" . }}-.*\"}[5m])) by (pod)",
              "legendFormat": "{{`{{ pod }}`}} RX",
              "refId": "A"
            },
            {
              "expr": "sum(rate(container_network_transmit_bytes_total{namespace=\"{{ include "forge.namespace" . }}\",pod=~\"{{ include "forge.fullname" . }}-.*\"}[5m])) by (pod)",
              "legendFormat": "{{`{{ pod }}`}} TX",
              "refId": "B"
            }
          ],
          "title": "Network I/O by Pod",
          "type": "timeseries"
        },
        {
          "datasource": "Prometheus",
          "fieldConfig": {"defaults": {}},
          "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
          "id": 4,
          "targets": [
            {
              "expr": "kube_pod_container_status_restarts_total{namespace=\"{{ include "forge.namespace" . }}\",pod=~\"{{ include "forge.fullname" . }}-.*\"}",
              "legendFormat": "{{`{{ pod }}`}}",
              "refId": "A"
            }
          ],
          "title": "Pod Restarts",
          "type": "timeseries"
        }
      ],
      "refresh": "30s",
      "schemaVersion": 38,
      "style": "dark",
      "tags": ["infrastructure", "kubernetes", "{{ include "forge.fullname" . }}"],
      "templating": {"list": []},
      "time": {"from": "now-6h", "to": "now"},
      "timepicker": {},
      "timezone": "",
      "title": "{{ include "forge.fullname" . }} - Infrastructure Metrics",
      "uid": "{{ include "forge.fullname" . }}-infra",
      "version": 1
    }
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
