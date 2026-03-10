{{/*
==============================================================================
Forge Common Library - Falco Runtime Security
==============================================================================
Templates for Falco runtime security monitoring.

Falco detects suspicious behavior and security threats at runtime:
  - Process execution monitoring
  - File system access detection
  - Network connection tracking
  - System call monitoring
  - Container escape detection

Compatible with:
  - Falco 0.36+
  - Kubernetes 1.23-1.29

Usage:
  {{- include "security.falco.rules" . }}

See Also:
  - https://falco.org/docs/
==============================================================================
*/}}

{{/*
==============================================================================
Falco: Custom Rules ConfigMap
==============================================================================
Define custom Falco security rules.

Usage:
  {{- include "security.falco.rules" . }}

Requirements:
  .Values.security.falco.rules.enabled = true

Output:
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: falco-custom-rules
    namespace: falco
  data:
    custom-rules.yaml: |
      - rule: Suspicious Process Execution
        desc: Detect execution of suspicious processes
        condition: spawned_process and proc.name in (suspicious_procs)
        output: Suspicious process executed (user=%user.name process=%proc.name)
        priority: WARNING
*/}}

{{- define "security.falco.rules" -}}
{{- if .Values.security -}}
{{- if .Values.security.falco -}}
{{- if .Values.security.falco.rules -}}
{{- if .Values.security.falco.rules.enabled -}}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "configmap" "name" "falco-custom-rules") }}
  namespace: {{ .Values.security.falco.namespace | default "falco" }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/security-tool: "falco"
    {{- with .Values.security.falco.rules.labels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  annotations:
    {{- with .Values.security.falco.rules.annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
data:
  custom-rules.yaml: |
    # Falco Custom Security Rules for {{ include "forge.fullname" . }}
    
    {{- if .Values.security.falco.rules.customRules }}
    # Custom rules from values
    {{- .Values.security.falco.rules.customRules | nindent 4 }}
    {{- end }}
    
    {{- if .Values.security.falco.rules.macros }}
    # Custom macros
    {{- range .Values.security.falco.rules.macros }}
    - macro: {{ .name | required "Macro name is required" }}
      condition: {{ .condition | required "Macro condition is required" }}
    {{- end }}
    {{- end }}
    
    {{- if .Values.security.falco.rules.lists }}
    # Custom lists
    {{- range .Values.security.falco.rules.lists }}
    - list: {{ .name | required "List name is required" }}
      items:
        {{- range .items }}
        - {{ . }}
        {{- end }}
    {{- end }}
    {{- end }}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
Falco: Pre-configured Application Security Rules
==============================================================================
Common security rules for application workloads.

Usage:
  {{- include "security.falco.applicationRules" . }}
*/}}

{{- define "security.falco.applicationRules" -}}
{{- if .Values.security -}}
{{- if .Values.security.falco -}}
{{- if .Values.security.falco.applicationRules -}}
{{- if .Values.security.falco.applicationRules.enabled -}}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "configmap" "name" "falco-app-rules") }}
  namespace: {{ .Values.security.falco.namespace | default "falco" }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/security-tool: "falco"
    moai.forge.io/rule-category: "application"
data:
  application-rules.yaml: |
    # Application Security Rules for {{ include "forge.fullname" . }}
    
    # List of allowed application processes
    - list: app_processes
      items:
        {{- if .Values.security.falco.applicationRules.allowedProcesses }}
        {{- range .Values.security.falco.applicationRules.allowedProcesses }}
        - {{ . }}
        {{- end }}
        {{- else }}
        - java
        - node
        - python
        - ruby
        {{- end }}
    
    # Rule: Unexpected process execution in container
    - rule: Unexpected Process in Container
      desc: Detect execution of unexpected processes in application container
      condition: >
        spawned_process
        and container.id != host
        and container.name startswith "{{ include "forge.fullname" . }}"
        and not proc.name in (app_processes)
      output: >
        Unexpected process executed in container
        (user=%user.name process=%proc.name parent=%proc.pname
        container=%container.name image=%container.image.repository)
      priority: {{ .Values.security.falco.applicationRules.priority | default "WARNING" }}
      tags: [application, process, container]
    
    # Rule: Write to sensitive directories
    - rule: Write to Sensitive Directory
      desc: Detect writes to sensitive directories like /etc, /usr/bin
      condition: >
        open_write
        and container.name startswith "{{ include "forge.fullname" . }}"
        and fd.name startswith /etc
        or fd.name startswith /usr/bin
        or fd.name startswith /usr/sbin
      output: >
        Write to sensitive directory detected
        (user=%user.name file=%fd.name container=%container.name)
      priority: {{ .Values.security.falco.applicationRules.priority | default "WARNING" }}
      tags: [application, filesystem, container]
    
    # Rule: Outbound connection to suspicious IP
    {{- if .Values.security.falco.applicationRules.suspiciousIPs }}
    - list: suspicious_ips
      items:
        {{- range .Values.security.falco.applicationRules.suspiciousIPs }}
        - {{ . }}
        {{- end }}
    
    - rule: Outbound Connection to Suspicious IP
      desc: Detect outbound connections to known malicious IPs
      condition: >
        outbound
        and container.name startswith "{{ include "forge.fullname" . }}"
        and fd.sip in (suspicious_ips)
      output: >
        Outbound connection to suspicious IP
        (user=%user.name ip=%fd.sip port=%fd.sport container=%container.name)
      priority: CRITICAL
      tags: [application, network, threat]
    {{- end }}
    
    # Rule: Shell spawned in container
    - rule: Shell Spawned in Container
      desc: Detect shell execution in application container (potential compromise)
      condition: >
        spawned_process
        and container.name startswith "{{ include "forge.fullname" . }}"
        and proc.name in (shell_binaries)
      output: >
        Shell spawned in container (potential compromise)
        (user=%user.name shell=%proc.name parent=%proc.pname container=%container.name)
      priority: CRITICAL
      tags: [application, shell, container, compromise]
    
    # Rule: Privilege escalation attempt
    - rule: Privilege Escalation Attempt
      desc: Detect privilege escalation attempts via sudo or setuid
      condition: >
        spawned_process
        and container.name startswith "{{ include "forge.fullname" . }}"
        and (proc.name in (sudo, su) or (proc.name != "" and proc.exepath contains "setuid"))
      output: >
        Privilege escalation attempt detected
        (user=%user.name process=%proc.name container=%container.name)
      priority: CRITICAL
      tags: [application, privilege-escalation, container]
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
Falco: Pre-configured Compliance Rules
==============================================================================
Compliance and policy enforcement rules.

Usage:
  {{- include "security.falco.complianceRules" . }}
*/}}

{{- define "security.falco.complianceRules" -}}
{{- if .Values.security -}}
{{- if .Values.security.falco -}}
{{- if .Values.security.falco.complianceRules -}}
{{- if .Values.security.falco.complianceRules.enabled -}}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "configmap" "name" "falco-compliance-rules") }}
  namespace: {{ .Values.security.falco.namespace | default "falco" }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/security-tool: "falco"
    moai.forge.io/rule-category: "compliance"
data:
  compliance-rules.yaml: |
    # Compliance Security Rules
    
    # Rule: Container running as root
    - rule: Container Running as Root
      desc: Container should not run as root user (violates Pod Security Standards)
      condition: >
        spawned_process
        and container.id != host
        and container.name startswith "{{ include "forge.fullname" . }}"
        and user.uid = 0
      output: >
        Container running as root user (compliance violation)
        (user=%user.name container=%container.name image=%container.image.repository)
      priority: {{ .Values.security.falco.complianceRules.priority | default "WARNING" }}
      tags: [compliance, pss, container]
    
    # Rule: Privileged container detected
    - rule: Privileged Container Launched
      desc: Privileged containers violate security policies
      condition: >
        container_started
        and container.name startswith "{{ include "forge.fullname" . }}"
        and container.privileged = true
      output: >
        Privileged container launched (compliance violation)
        (container=%container.name image=%container.image.repository)
      priority: CRITICAL
      tags: [compliance, privileged, container]
    
    # Rule: Sensitive mount detected
    - rule: Sensitive Mount in Container
      desc: Container has sensitive host paths mounted
      condition: >
        container_started
        and container.name startswith "{{ include "forge.fullname" . }}"
        and container.mount.dest in (/proc, /sys, /dev, /var/run/docker.sock)
      output: >
        Container has sensitive host path mounted
        (container=%container.name mount=%container.mount.dest)
      priority: {{ .Values.security.falco.complianceRules.priority | default "WARNING" }}
      tags: [compliance, mount, container]
    
    # Rule: Package management in container
    - rule: Package Management in Container
      desc: Detect package installation in running container (container should be immutable)
      condition: >
        spawned_process
        and container.name startswith "{{ include "forge.fullname" . }}"
        and proc.name in (apt-get, yum, apk, pip, npm)
      output: >
        Package management executed in running container (immutability violation)
        (user=%user.name process=%proc.name container=%container.name)
      priority: {{ .Values.security.falco.complianceRules.priority | default "WARNING" }}
      tags: [compliance, immutability, container]
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
