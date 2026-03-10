{{/*
==============================================================================
Forge Common Library - Trivy Security Scanning
==============================================================================
Templates for Trivy vulnerability and compliance scanning.

Trivy scans container images, filesystems, and configurations for:
  - Vulnerabilities (CVE detection)
  - Misconfigurations (IaC scanning)
  - Secrets (leaked credentials)
  - License compliance

Compatible with:
  - Trivy Operator 0.16+
  - Kubernetes 1.23-1.29

Usage:
  {{- include "security.trivy.vulnerabilityReport" . }}

See Also:
  - https://aquasecurity.github.io/trivy-operator/
==============================================================================
*/}}

{{/*
==============================================================================
Trivy: Vulnerability Report Policy
==============================================================================
Configure VulnerabilityReport scanning policy.

Usage:
  {{- include "security.trivy.vulnerabilityReport" . }}

Requirements:
  .Values.security.trivy.vulnerabilityReport.enabled = true

Output:
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: trivy-vulnerability-policy
    namespace: trivy-system
  data:
    policy.yaml: |
      severities:
        - CRITICAL
        - HIGH
      ignoreUnfixed: true
*/}}

{{- define "security.trivy.vulnerabilityReport" -}}
{{- if .Values.security -}}
{{- if .Values.security.trivy -}}
{{- if .Values.security.trivy.vulnerabilityReport -}}
{{- if .Values.security.trivy.vulnerabilityReport.enabled -}}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "configmap" "name" "trivy-vulnerability-policy") }}
  namespace: {{ .Values.security.trivy.namespace | default "trivy-system" }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/security-tool: "trivy"
    {{- with .Values.security.trivy.vulnerabilityReport.labels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  annotations:
    {{- with .Values.security.trivy.vulnerabilityReport.annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
data:
  policy.yaml: |
    # Trivy Vulnerability Scanning Policy
    
    # Severities to report
    severities:
      {{- range .Values.security.trivy.vulnerabilityReport.severities }}
      - {{ . }}
      {{- end }}
    
    # Ignore unfixed vulnerabilities (no patch available)
    ignoreUnfixed: {{ .Values.security.trivy.vulnerabilityReport.ignoreUnfixed | default true }}
    
    {{- if .Values.security.trivy.vulnerabilityReport.ignoreVulnerabilities }}
    # CVE IDs to ignore
    ignoreVulnerabilities:
      {{- range .Values.security.trivy.vulnerabilityReport.ignoreVulnerabilities }}
      - {{ . }}
      {{- end }}
    {{- end }}
    
    {{- if .Values.security.trivy.vulnerabilityReport.skipDirs }}
    # Directories to skip
    skipDirs:
      {{- range .Values.security.trivy.vulnerabilityReport.skipDirs }}
      - {{ . }}
      {{- end }}
    {{- end }}
    
    {{- if .Values.security.trivy.vulnerabilityReport.skipFiles }}
    # Files to skip
    skipFiles:
      {{- range .Values.security.trivy.vulnerabilityReport.skipFiles }}
      - {{ . }}
      {{- end }}
    {{- end }}
    
    # Scan timeout
    timeout: {{ .Values.security.trivy.vulnerabilityReport.timeout | default "5m" }}
    
    # Offline mode (use local DB)
    offlineScan: {{ .Values.security.trivy.vulnerabilityReport.offlineScan | default false }}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
Trivy: Configuration Audit Policy
==============================================================================
Configure ConfigAuditReport for misconfiguration scanning.

Usage:
  {{- include "security.trivy.configAuditReport" . }}
*/}}

{{- define "security.trivy.configAuditReport" -}}
{{- if .Values.security -}}
{{- if .Values.security.trivy -}}
{{- if .Values.security.trivy.configAuditReport -}}
{{- if .Values.security.trivy.configAuditReport.enabled -}}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "configmap" "name" "trivy-config-audit-policy") }}
  namespace: {{ .Values.security.trivy.namespace | default "trivy-system" }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/security-tool: "trivy"
    {{- with .Values.security.trivy.configAuditReport.labels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
data:
  policy.yaml: |
    # Trivy Configuration Audit Policy
    
    # Severities to report
    severities:
      {{- range .Values.security.trivy.configAuditReport.severities }}
      - {{ . }}
      {{- end }}
    
    # Compliance standards to check
    {{- if .Values.security.trivy.configAuditReport.compliance }}
    compliance:
      {{- range .Values.security.trivy.configAuditReport.compliance }}
      - {{ . }}
      {{- end }}
    {{- end }}
    
    # Scanner configuration
    scanners:
      {{- if .Values.security.trivy.configAuditReport.scanners }}
      {{- range .Values.security.trivy.configAuditReport.scanners }}
      - {{ . }}
      {{- end }}
      {{- else }}
      - config-audit
      - secret
      {{- end }}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
Trivy: Secret Scanning Policy
==============================================================================
Configure secret scanning to detect leaked credentials.

Usage:
  {{- include "security.trivy.secretScan" . }}
*/}}

{{- define "security.trivy.secretScan" -}}
{{- if .Values.security -}}
{{- if .Values.security.trivy -}}
{{- if .Values.security.trivy.secretScan -}}
{{- if .Values.security.trivy.secretScan.enabled -}}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "configmap" "name" "trivy-secret-scan-policy") }}
  namespace: {{ .Values.security.trivy.namespace | default "trivy-system" }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/security-tool: "trivy"
    {{- with .Values.security.trivy.secretScan.labels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
data:
  policy.yaml: |
    # Trivy Secret Scanning Policy
    
    # Secret types to detect
    secretTypes:
      {{- if .Values.security.trivy.secretScan.secretTypes }}
      {{- range .Values.security.trivy.secretScan.secretTypes }}
      - {{ . }}
      {{- end }}
      {{- else }}
      - aws-access-key-id
      - aws-secret-access-key
      - github-token
      - gitlab-token
      - slack-webhook-url
      - slack-access-token
      - generic-api-key
      - private-key
      {{- end }}
    
    # Paths to exclude from scanning
    {{- if .Values.security.trivy.secretScan.excludePaths }}
    excludePaths:
      {{- range .Values.security.trivy.secretScan.excludePaths }}
      - {{ . }}
      {{- end }}
    {{- end }}
    
    # Allow rules (false positives)
    {{- if .Values.security.trivy.secretScan.allowRules }}
    allowRules:
      {{- toYaml .Values.security.trivy.secretScan.allowRules | nindent 6 }}
    {{- end }}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
Trivy: CronJob for Scheduled Scanning
==============================================================================
CronJob to run Trivy scans on a schedule.

Usage:
  {{- include "security.trivy.scanJob" . }}
*/}}

{{- define "security.trivy.scanJob" -}}
{{- if .Values.security -}}
{{- if .Values.security.trivy -}}
{{- if .Values.security.trivy.scanJob -}}
{{- if .Values.security.trivy.scanJob.enabled -}}
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "cronjob" "name" "trivy-scan") }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/security-tool: "trivy"
spec:
  schedule: {{ .Values.security.trivy.scanJob.schedule | default "0 2 * * *" | quote }}
  successfulJobsHistoryLimit: {{ .Values.security.trivy.scanJob.successfulJobsHistoryLimit | default 3 }}
  failedJobsHistoryLimit: {{ .Values.security.trivy.scanJob.failedJobsHistoryLimit | default 1 }}
  concurrencyPolicy: {{ .Values.security.trivy.scanJob.concurrencyPolicy | default "Forbid" }}
  jobTemplate:
    spec:
      template:
        metadata:
          labels:
            {{- include "forge.labels" . | nindent 12 }}
            moai.forge.io/security-tool: "trivy"
        spec:
          restartPolicy: OnFailure
          serviceAccountName: {{ .Values.security.trivy.scanJob.serviceAccountName | default "trivy-operator" }}
          
          {{- with .Values.security.trivy.scanJob.imagePullSecrets }}
          imagePullSecrets:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          
          {{- with .Values.security.trivy.scanJob.tolerations }}
          tolerations:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          
          {{- with .Values.security.trivy.scanJob.nodeSelector }}
          nodeSelector:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          
          {{- if or .Values.security.trivy.scanJob.nodeAffinity .Values.security.trivy.scanJob.podAffinity .Values.security.trivy.scanJob.podAntiAffinity }}
          affinity:
            {{- with .Values.security.trivy.scanJob.nodeAffinity }}
            nodeAffinity:
              {{- toYaml . | nindent 14 }}
            {{- end }}
            {{- with .Values.security.trivy.scanJob.podAffinity }}
            podAffinity:
              {{- toYaml . | nindent 14 }}
            {{- end }}
            {{- with .Values.security.trivy.scanJob.podAntiAffinity }}
            podAntiAffinity:
              {{- toYaml . | nindent 14 }}
            {{- end }}
          {{- end }}
          
          containers:
            - name: trivy-scanner
              image: {{ .Values.security.trivy.scanJob.image | default "aquasec/trivy:0.48.0" }}
              imagePullPolicy: {{ .Values.security.trivy.scanJob.imagePullPolicy | default "IfNotPresent" }}
              
              command:
                - trivy
              
              args:
                - image
                - --format
                - json
                - --output
                - /tmp/scan-results.json
                {{- if .Values.security.trivy.scanJob.severity }}
                - --severity
                - {{ join "," .Values.security.trivy.scanJob.severity }}
                {{- end }}
                {{- if .Values.security.trivy.scanJob.ignoreUnfixed }}
                - --ignore-unfixed
                {{- end }}
                - {{ .Values.security.trivy.scanJob.imageRef | required "security.trivy.scanJob.imageRef is required" }}
              
              {{- with .Values.security.trivy.scanJob.resources }}
              resources:
                {{- toYaml . | nindent 16 }}
              {{- end }}
              
              volumeMounts:
                - name: scan-results
                  mountPath: /tmp
          
          volumes:
            - name: scan-results
              emptyDir: {}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
