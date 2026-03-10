{{/*
==============================================================================
Forge Common Library - ResourceQuota Template (Capacity-Based)
==============================================================================
Capacity-based ResourceQuota template following namespace-hardening.sh philosophy.

Philosophy:
  We measure CAPACITY (what COULD be used at peak), not USAGE (what IS used now).
  This enables IMMEDIATE hardening after deployment - no waiting needed!

Measurement Sources (priority order):
  1. Goldilocks VPA recommendations (historical, pre-calculated)
  2. VPA upperBound (P99 + headroom, 7+ days data)
  3. HPA maxReplicas (declared maximum scale, NOT current replicas)
  4. Pod limits (static manifest values)

DaemonSets:
  Max capacity = max_nodes × pod_limits × buffer
  Max nodes from: Karpenter → Cloud provider API → ConfigMap → Fallback (100)

Key Principle:
  - HPA maxReplicas=10 is declared in manifest (doesn't change with traffic)
  - VPA upperBound=600m is already calculated from 7+ days historical data
  - Max nodes=100 is defined in Karpenter/ASG config (infrastructure limit)
  - Pod limits=500m are static values in deployment manifests
  
  Current usage (3 replicas, 200m CPU, 6 nodes) is IGNORED.

Usage:
  {{- include "hardening.resourcequota" . }}

See Also:
  - scripts/namespace-hardening.sh - Full implementation
  - docs/WHY_NO_WAITING.md - Philosophy explanation
==============================================================================
*/}}

{{- define "hardening.resourcequota" -}}
{{- if .Values.resourceQuota -}}
{{- if .Values.resourceQuota.enabled -}}
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "resourcequota" "name" .Values.resourceQuota.nameOverride) }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/hardening: "capacity-based"
    moai.forge.io/measurement: "{{ .Values.resourceQuota.measurementSource | default "hpa-vpa-limits" }}"
  annotations:
    moai.forge.io/hardening-version: "{{ .Values.resourceQuota.hardeningVersion | default "2.0.0" }}"
    moai.forge.io/buffer-percent: "{{ .Values.resourceQuota.bufferPercent | default 20 }}"
    moai.forge.io/min-vpa-age-days: "{{ .Values.resourceQuota.minVpaAgeDays | default 7 }}"
    moai.forge.io/measured-at: "{{ now | date "2006-01-02T15:04:05Z07:00" }}"
    {{- with .Values.resourceQuota.annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
spec:
  hard:
    {{- /* CPU Limits (millicores) */ -}}
    {{- if .Values.resourceQuota.cpu }}
    {{- if .Values.resourceQuota.cpu.limits }}
    limits.cpu: {{ .Values.resourceQuota.cpu.limits }}
    {{- end }}
    {{- if .Values.resourceQuota.cpu.requests }}
    requests.cpu: {{ .Values.resourceQuota.cpu.requests }}
    {{- end }}
    {{- end }}
    
    {{- /* Memory Limits (bytes with unit: Mi, Gi, etc.) */ -}}
    {{- if .Values.resourceQuota.memory }}
    {{- if .Values.resourceQuota.memory.limits }}
    limits.memory: {{ .Values.resourceQuota.memory.limits }}
    {{- end }}
    {{- if .Values.resourceQuota.memory.requests }}
    requests.memory: {{ .Values.resourceQuota.memory.requests }}
    {{- end }}
    {{- end }}
    
    {{- /* Pod Count (measured from HPA maxReplicas + PDB + DaemonSets) */ -}}
    {{- if .Values.resourceQuota.pods }}
    pods: "{{ .Values.resourceQuota.pods }}"
    {{- end }}
    
    {{- /* PersistentVolumeClaims (from StatefulSet volumeClaimTemplates) */ -}}
    {{- if .Values.resourceQuota.persistentvolumeclaims }}
    persistentvolumeclaims: "{{ .Values.resourceQuota.persistentvolumeclaims }}"
    {{- end }}
    
    {{- /* Services (optional limit) */ -}}
    {{- if .Values.resourceQuota.services }}
    services: "{{ .Values.resourceQuota.services }}"
    {{- end }}
    
    {{- /* ConfigMaps (optional limit) */ -}}
    {{- if .Values.resourceQuota.configmaps }}
    configmaps: "{{ .Values.resourceQuota.configmaps }}"
    {{- end }}
    
    {{- /* Secrets (optional limit) */ -}}
    {{- if .Values.resourceQuota.secrets }}
    secrets: "{{ .Values.resourceQuota.secrets }}"
    {{- end }}
    
    {{- /* Replication Controllers (deprecated, usually 0) */ -}}
    {{- if .Values.resourceQuota.replicationcontrollers }}
    replicationcontrollers: "{{ .Values.resourceQuota.replicationcontrollers }}"
    {{- end }}
    
    {{- /* LoadBalancers (optional limit) */ -}}
    {{- if .Values.resourceQuota.loadbalancers }}
    services.loadbalancers: "{{ .Values.resourceQuota.loadbalancers }}"
    {{- end }}
    
    {{- /* NodePorts (optional limit) */ -}}
    {{- if .Values.resourceQuota.nodeports }}
    services.nodeports: "{{ .Values.resourceQuota.nodeports }}"
    {{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
==============================================================================
Helper: Calculate Capacity-Based CPU Quota
==============================================================================
Calculates CPU quota from workload configurations using precedence rules.

Arguments (dict):
  - context: Root context (.)
  - workloads: List of workload configurations
  - bufferPercent: Buffer percentage (default: 20)
  - minVpaAgeDays: Minimum VPA age in days (default: 7)

Returns:
  CPU in millicores (string, e.g., "5000m")

Precedence for each workload:
  1. Goldilocks VPA recommendation (if available)
  2. VPA upperBound (if age >= minVpaAgeDays)
  3. HPA maxReplicas × pod limits
  4. Static replicas × pod limits

Example workload config:
  workloads:
    - name: api
      type: Deployment
      replicas: 3
      cpuLimit: "500m"
      hpa:
        enabled: true
        maxReplicas: 10
      vpa:
        enabled: true
        upperBound: "600m"
        ageDays: 14
      pdb:
        enabled: true
        minAvailable: 2

Calculation:
  - HPA maxReplicas=10, cpuLimit=500m → 10 × 500m = 5000m
  - VPA upperBound=600m (age 14 days) → 10 × 600m = 6000m (VPA takes precedence)
  - PDB minAvailable=2 → needs 1 extra pod for disruption → 11 × 600m = 6600m
  - Buffer 20% → 6600m × 1.20 = 7920m
==============================================================================
*/}}

{{- define "hardening.calculateCpuQuota" -}}
{{- $context := .context -}}
{{- $workloads := .workloads | default list -}}
{{- $bufferPercent := .bufferPercent | default 20 | int -}}
{{- $minVpaAgeDays := .minVpaAgeDays | default 7 | int -}}

{{- $totalCpuMillicores := 0 -}}

{{- range $workload := $workloads -}}
  {{- $cpuPerPod := 0 -}}
  {{- $podCount := 0 -}}
  
  {{- /* Step 1: Determine CPU per pod (precedence: Goldilocks → VPA → Pod limits) */ -}}
  {{- if and $workload.vpa $workload.vpa.enabled (ge ($workload.vpa.ageDays | default 0 | int) $minVpaAgeDays) -}}
    {{- /* Use VPA upperBound */ -}}
    {{- $cpuPerPod = include "hardening.cpuToMillicores" $workload.vpa.upperBound | int -}}
  {{- else if $workload.cpuLimit -}}
    {{- /* Use pod limits from manifest */ -}}
    {{- $cpuPerPod = include "hardening.cpuToMillicores" $workload.cpuLimit | int -}}
  {{- end -}}
  
  {{- /* Step 2: Determine pod count (HPA maxReplicas or static replicas) */ -}}
  {{- if and $workload.hpa $workload.hpa.enabled -}}
    {{- $podCount = $workload.hpa.maxReplicas | default 1 | int -}}
  {{- else if and $workload.keda $workload.keda.enabled -}}
    {{- $podCount = $workload.keda.maxReplicas | default 1 | int -}}
  {{- else -}}
    {{- $podCount = $workload.replicas | default 1 | int -}}
  {{- end -}}
  
  {{- /* Step 3: Add extra pod if PDB minAvailable is set */ -}}
  {{- if and $workload.pdb $workload.pdb.enabled -}}
    {{- $pdbMin := $workload.pdb.minAvailable | default 0 | int -}}
    {{- if ge $pdbMin $podCount -}}
      {{- $podCount = add $podCount 1 -}}
    {{- end -}}
  {{- end -}}
  
  {{- /* Step 4: Calculate workload total */ -}}
  {{- $workloadCpu := mul $cpuPerPod $podCount -}}
  {{- $totalCpuMillicores = add $totalCpuMillicores $workloadCpu -}}
{{- end -}}

{{- /* Step 5: Apply buffer */ -}}
{{- $bufferMultiplier := divf (add $bufferPercent 100) 100 -}}
{{- $finalCpu := mulf $totalCpuMillicores $bufferMultiplier | ceil | int -}}

{{- /* Step 6: Format as Kubernetes CPU quantity */ -}}
{{- printf "%dm" $finalCpu -}}
{{- end -}}

{{/*
==============================================================================
Helper: Calculate Capacity-Based Memory Quota
==============================================================================
Calculates memory quota from workload configurations using precedence rules.
Same logic as CPU calculation but for memory.

Returns:
  Memory with unit (string, e.g., "16Gi")
==============================================================================
*/}}

{{- define "hardening.calculateMemoryQuota" -}}
{{- $context := .context -}}
{{- $workloads := .workloads | default list -}}
{{- $bufferPercent := .bufferPercent | default 20 | int -}}
{{- $minVpaAgeDays := .minVpaAgeDays | default 7 | int -}}

{{- $totalMemoryBytes := 0 -}}

{{- range $workload := $workloads -}}
  {{- $memoryPerPod := 0 -}}
  {{- $podCount := 0 -}}
  
  {{- /* Step 1: Determine memory per pod (precedence: Goldilocks → VPA → Pod limits) */ -}}
  {{- if and $workload.vpa $workload.vpa.enabled (ge ($workload.vpa.ageDays | default 0 | int) $minVpaAgeDays) -}}
    {{- $memoryPerPod = include "hardening.memoryToBytes" $workload.vpa.memoryUpperBound | int -}}
  {{- else if $workload.memoryLimit -}}
    {{- $memoryPerPod = include "hardening.memoryToBytes" $workload.memoryLimit | int -}}
  {{- end -}}
  
  {{- /* Step 2: Determine pod count (HPA maxReplicas or static replicas) */ -}}
  {{- if and $workload.hpa $workload.hpa.enabled -}}
    {{- $podCount = $workload.hpa.maxReplicas | default 1 | int -}}
  {{- else if and $workload.keda $workload.keda.enabled -}}
    {{- $podCount = $workload.keda.maxReplicas | default 1 | int -}}
  {{- else -}}
    {{- $podCount = $workload.replicas | default 1 | int -}}
  {{- end -}}
  
  {{- /* Step 3: Add extra pod if PDB minAvailable is set */ -}}
  {{- if and $workload.pdb $workload.pdb.enabled -}}
    {{- $pdbMin := $workload.pdb.minAvailable | default 0 | int -}}
    {{- if ge $pdbMin $podCount -}}
      {{- $podCount = add $podCount 1 -}}
    {{- end -}}
  {{- end -}}
  
  {{- /* Step 4: Calculate workload total */ -}}
  {{- $workloadMemory := mul $memoryPerPod $podCount -}}
  {{- $totalMemoryBytes = add $totalMemoryBytes $workloadMemory -}}
{{- end -}}

{{- /* Step 5: Apply buffer */ -}}
{{- $bufferMultiplier := divf (add $bufferPercent 100) 100 -}}
{{- $finalMemory := mulf $totalMemoryBytes $bufferMultiplier | ceil | int -}}

{{- /* Step 6: Format as Kubernetes memory quantity */ -}}
{{- include "hardening.bytesToHumanMemory" $finalMemory -}}
{{- end -}}

{{/*
==============================================================================
Helper: Calculate Pod Quota
==============================================================================
Calculates maximum pod count from workload configurations.

Returns:
  Pod count (integer)

Calculation:
  - Deployments/StatefulSets with HPA: maxReplicas (+ 1 if PDB requires)
  - Deployments/StatefulSets without HPA: static replicas
  - DaemonSets: max_nodes (from Karpenter/ASG/ConfigMap/Fallback)
==============================================================================
*/}}

{{- define "hardening.calculatePodQuota" -}}
{{- $workloads := .workloads | default list -}}
{{- $maxNodes := .maxNodes | default 100 | int -}}

{{- $totalPods := 0 -}}

{{- range $workload := $workloads -}}
  {{- $podCount := 0 -}}
  
  {{- if eq $workload.type "DaemonSet" -}}
    {{- /* DaemonSets run on every (selected) node */ -}}
    {{- $podCount = $maxNodes -}}
  {{- else -}}
    {{- /* Deployment/StatefulSet: HPA maxReplicas or static replicas */ -}}
    {{- if and $workload.hpa $workload.hpa.enabled -}}
      {{- $podCount = $workload.hpa.maxReplicas | default 1 | int -}}
    {{- else if and $workload.keda $workload.keda.enabled -}}
      {{- $podCount = $workload.keda.maxReplicas | default 1 | int -}}
    {{- else -}}
      {{- $podCount = $workload.replicas | default 1 | int -}}
    {{- end -}}
    
    {{- /* Add extra pod if PDB minAvailable is set */ -}}
    {{- if and $workload.pdb $workload.pdb.enabled -}}
      {{- $pdbMin := $workload.pdb.minAvailable | default 0 | int -}}
      {{- if ge $pdbMin $podCount -}}
        {{- $podCount = add $podCount 1 -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
  
  {{- $totalPods = add $totalPods $podCount -}}
{{- end -}}

{{- $totalPods -}}
{{- end -}}

{{/*
==============================================================================
Helper: Convert CPU to Millicores
==============================================================================
Converts Kubernetes CPU quantity to millicores (integer).

Examples:
  - "1" → 1000
  - "500m" → 500
  - "2.5" → 2500
==============================================================================
*/}}

{{- define "hardening.cpuToMillicores" -}}
{{- $cpu := . | toString -}}
{{- if hasSuffix "m" $cpu -}}
  {{- $cpu | trimSuffix "m" | int -}}
{{- else -}}
  {{- $cpuFloat := $cpu | float64 -}}
  {{- mulf $cpuFloat 1000 | int -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
Helper: Convert Memory to Bytes
==============================================================================
Converts Kubernetes memory quantity to bytes (integer).

Examples:
  - "128Mi" → 134217728
  - "1Gi" → 1073741824
  - "512M" → 512000000
==============================================================================
*/}}

{{- define "hardening.memoryToBytes" -}}
{{- $memory := . | toString -}}
{{- $value := 0 -}}
{{- $unit := "" -}}

{{- if hasSuffix "Ei" $memory -}}
  {{- $value = $memory | trimSuffix "Ei" | float64 -}}
  {{- mulf $value 1152921504606846976 | int -}}
{{- else if hasSuffix "Pi" $memory -}}
  {{- $value = $memory | trimSuffix "Pi" | float64 -}}
  {{- mulf $value 1125899906842624 | int -}}
{{- else if hasSuffix "Ti" $memory -}}
  {{- $value = $memory | trimSuffix "Ti" | float64 -}}
  {{- mulf $value 1099511627776 | int -}}
{{- else if hasSuffix "Gi" $memory -}}
  {{- $value = $memory | trimSuffix "Gi" | float64 -}}
  {{- mulf $value 1073741824 | int -}}
{{- else if hasSuffix "Mi" $memory -}}
  {{- $value = $memory | trimSuffix "Mi" | float64 -}}
  {{- mulf $value 1048576 | int -}}
{{- else if hasSuffix "Ki" $memory -}}
  {{- $value = $memory | trimSuffix "Ki" | float64 -}}
  {{- mulf $value 1024 | int -}}
{{- else if hasSuffix "E" $memory -}}
  {{- $value = $memory | trimSuffix "E" | float64 -}}
  {{- mulf $value 1000000000000000000 | int -}}
{{- else if hasSuffix "P" $memory -}}
  {{- $value = $memory | trimSuffix "P" | float64 -}}
  {{- mulf $value 1000000000000000 | int -}}
{{- else if hasSuffix "T" $memory -}}
  {{- $value = $memory | trimSuffix "T" | float64 -}}
  {{- mulf $value 1000000000000 | int -}}
{{- else if hasSuffix "G" $memory -}}
  {{- $value = $memory | trimSuffix "G" | float64 -}}
  {{- mulf $value 1000000000 | int -}}
{{- else if hasSuffix "M" $memory -}}
  {{- $value = $memory | trimSuffix "M" | float64 -}}
  {{- mulf $value 1000000 | int -}}
{{- else if hasSuffix "K" $memory -}}
  {{- $value = $memory | trimSuffix "K" | float64 -}}
  {{- mulf $value 1000 | int -}}
{{- else -}}
  {{- $memory | int -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
Helper: Convert Bytes to Human-Readable Memory
==============================================================================
Converts bytes to Kubernetes memory quantity with appropriate unit.

Examples:
  - 134217728 → "128Mi"
  - 1073741824 → "1Gi"
==============================================================================
*/}}

{{- define "hardening.bytesToHumanMemory" -}}
{{- $bytes := . | int -}}

{{- if ge $bytes 1073741824 -}}
  {{- $gi := divf $bytes 1073741824 -}}
  {{- printf "%.0fGi" $gi -}}
{{- else if ge $bytes 1048576 -}}
  {{- $mi := divf $bytes 1048576 -}}
  {{- printf "%.0fMi" $mi -}}
{{- else if ge $bytes 1024 -}}
  {{- $ki := divf $bytes 1024 -}}
  {{- printf "%.0fKi" $ki -}}
{{- else -}}
  {{- printf "%d" $bytes -}}
{{- end -}}
{{- end -}}
