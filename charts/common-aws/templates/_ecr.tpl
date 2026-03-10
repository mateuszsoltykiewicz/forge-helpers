{{/*
==============================================================================
Forge Common Library - ECR (Elastic Container Registry)
==============================================================================
Helpers for AWS ECR image management and authentication.

Compatible with:
  - Amazon ECR (Elastic Container Registry)
  - ECR Public Gallery
  - Cross-account ECR access

Usage:
  {{- include "aws.ecr.imageUrl" . }}
  {{- include "aws.ecr.registryUrl" . }}

See Also:
  - https://docs.aws.amazon.com/AmazonECR/latest/userguide/
==============================================================================
*/}}

{{/*
==============================================================================
AWS ECR: Registry URL
==============================================================================
Generate ECR registry URL from AWS account and region.

Usage:
  {{ include "aws.ecr.registryUrl" . }}

Arguments:
  .Values.aws.accountId - AWS account ID (required)
  .Values.aws.region - AWS region (default: us-east-1)

Output:
  123456789012.dkr.ecr.us-east-1.amazonaws.com
*/}}

{{- define "aws.ecr.registryUrl" -}}
{{- $accountId := .Values.aws.accountId | required "aws.accountId is required for ECR" -}}
{{- $region := .Values.aws.region | default "us-east-1" -}}
{{- printf "%s.dkr.ecr.%s.amazonaws.com" $accountId $region -}}
{{- end -}}

{{/*
==============================================================================
AWS ECR: Image URL
==============================================================================
Generate complete ECR image URL with registry, repository, and tag.

Usage:
  {{ include "aws.ecr.imageUrl" . }}

Arguments:
  .Values.aws.ecr.repository - ECR repository name (required)
  .Values.image.tag - Image tag (default: .Chart.AppVersion)
  .Values.aws.accountId - AWS account ID (required)
  .Values.aws.region - AWS region (default: us-east-1)

Output:
  123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app:v1.0.0
*/}}

{{- define "aws.ecr.imageUrl" -}}
{{- $registry := include "aws.ecr.registryUrl" . -}}
{{- $repository := .Values.aws.ecr.repository | required "aws.ecr.repository is required" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- printf "%s/%s:%s" $registry $repository $tag -}}
{{- end -}}

{{/*
==============================================================================
AWS ECR: Public Gallery URL
==============================================================================
Generate ECR Public Gallery image URL.

Usage:
  {{ include "aws.ecr.publicImageUrl" . }}

Arguments:
  .Values.aws.ecr.publicAlias - ECR Public alias (required)
  .Values.aws.ecr.repository - Repository name (required)
  .Values.image.tag - Image tag (default: .Chart.AppVersion)

Output:
  public.ecr.aws/my-alias/my-app:v1.0.0
*/}}

{{- define "aws.ecr.publicImageUrl" -}}
{{- $alias := .Values.aws.ecr.publicAlias | required "aws.ecr.publicAlias is required for ECR Public" -}}
{{- $repository := .Values.aws.ecr.repository | required "aws.ecr.repository is required" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- printf "public.ecr.aws/%s/%s:%s" $alias $repository $tag -}}
{{- end -}}

{{/*
==============================================================================
AWS ECR: Cross-Account Image URL
==============================================================================
Generate ECR image URL for cross-account access.

Usage:
  {{ include "aws.ecr.crossAccountImageUrl" . }}

Arguments:
  .Values.aws.ecr.sourceAccountId - Source AWS account ID (required)
  .Values.aws.ecr.sourceRegion - Source AWS region (default: us-east-1)
  .Values.aws.ecr.repository - Repository name (required)
  .Values.image.tag - Image tag (default: .Chart.AppVersion)

Output:
  987654321098.dkr.ecr.us-west-2.amazonaws.com/shared-repo:v1.0.0
*/}}

{{- define "aws.ecr.crossAccountImageUrl" -}}
{{- $accountId := .Values.aws.ecr.sourceAccountId | required "aws.ecr.sourceAccountId is required for cross-account ECR" -}}
{{- $region := .Values.aws.ecr.sourceRegion | default "us-east-1" -}}
{{- $repository := .Values.aws.ecr.repository | required "aws.ecr.repository is required" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- printf "%s.dkr.ecr.%s.amazonaws.com/%s:%s" $accountId $region $repository $tag -}}
{{- end -}}

{{/*
==============================================================================
AWS ECR: Image Pull Secret Name
==============================================================================
Generate standardized name for ECR image pull secret.

Usage:
  {{ include "aws.ecr.imagePullSecretName" . }}

Arguments:
  .Release.Name - Release name
  .Values.aws.ecr.imagePullSecretName - Override (optional)

Output:
  my-app-ecr-credentials
*/}}

{{- define "aws.ecr.imagePullSecretName" -}}
{{- if .Values.aws.ecr.imagePullSecretName -}}
  {{- .Values.aws.ecr.imagePullSecretName -}}
{{- else -}}
  {{- include "forge.resourceName" (dict "context" . "type" "secret" "name" "ecr-credentials") -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
AWS ECR: Repository Policy ARN
==============================================================================
Generate IAM policy ARN for ECR repository access.

Usage:
  {{ include "aws.ecr.repositoryPolicyArn" . }}

Arguments:
  .Values.aws.accountId - AWS account ID (required)
  .Values.aws.ecr.repository - Repository name (required)

Output:
  arn:aws:ecr:us-east-1:123456789012:repository/my-app
*/}}

{{- define "aws.ecr.repositoryPolicyArn" -}}
{{- $accountId := .Values.aws.accountId | required "aws.accountId is required" -}}
{{- $region := .Values.aws.region | default "us-east-1" -}}
{{- $repository := .Values.aws.ecr.repository | required "aws.ecr.repository is required" -}}
{{- printf "arn:aws:ecr:%s:%s:repository/%s" $region $accountId $repository -}}
{{- end -}}

{{/*
==============================================================================
AWS ECR: Image with Digest
==============================================================================
Generate ECR image URL with digest (immutable reference).

Usage:
  {{ include "aws.ecr.imageWithDigest" . }}

Arguments:
  .Values.aws.ecr.repository - Repository name (required)
  .Values.image.digest - Image digest (sha256:...) (required)
  .Values.aws.accountId - AWS account ID (required)
  .Values.aws.region - AWS region (default: us-east-1)

Output:
  123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app@sha256:abc123...
*/}}

{{- define "aws.ecr.imageWithDigest" -}}
{{- $registry := include "aws.ecr.registryUrl" . -}}
{{- $repository := .Values.aws.ecr.repository | required "aws.ecr.repository is required" -}}
{{- $digest := .Values.image.digest | required "image.digest is required for digest-based image reference" -}}
{{- printf "%s/%s@%s" $registry $repository $digest -}}
{{- end -}}
