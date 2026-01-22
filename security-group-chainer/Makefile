# ==============================================================================
# Makefile for Security Group Chainer - Production Workflow
# ==============================================================================

.PHONY: help build push ecr-create ecr-delete test run run-docker install clean

# Default target
.DEFAULT_GOAL := help

# ==============================================================================
# Variables
# ==============================================================================

# AWS Configuration
AWS_REGION ?= us-east-2
AWS_ACCOUNT_ID ?= $(shell aws sts get-caller-identity --query Account --output text 2>/dev/null)

# Docker Image Configuration
IMAGE_NAME := security-group-chainer
VERSION ?= latest
LOCAL_IMAGE := $(IMAGE_NAME):$(VERSION)
ECR_REPO := $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(IMAGE_NAME)
ECR_IMAGE := $(ECR_REPO):$(VERSION)

# Python Configuration
PYTHON := python3
PYTEST := pytest

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

# ==============================================================================
# Help
# ==============================================================================

help: ## Display this help message
	@echo "$(BLUE)Security Group Chainer - Makefile$(NC)"
	@echo ""
	@echo "$(GREEN)Production Targets:$(NC)"
	@awk 'BEGIN {FS = ":.*##"; printf ""} /^[a-zA-Z_-]+:.*?##/ { printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(BLUE)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(YELLOW)Examples:$(NC)"
	@echo "  make build                    # Build Docker image"
	@echo "  make push                     # Push to ECR (auto-creates repo)"
	@echo "  make run ENV=shared           # Run chainer with configuration-shared.yaml"
	@echo "  make run-docker ENV=shared    # Run chainer in Docker container"
	@echo "  make install ENV=production   # Alias for 'run'"
	@echo "  make test                     # Run unit tests"
	@echo ""

# ==============================================================================
# Docker Build & Push
# ==============================================================================

build: ## Build Docker image locally
	@echo "$(BLUE)Building Docker image...$(NC)"
	@echo "Image: $(LOCAL_IMAGE)"
	@docker build -t $(IMAGE_NAME):$(VERSION) .
	@docker tag $(IMAGE_NAME):$(VERSION) $(IMAGE_NAME):latest
	@echo "$(GREEN)✓ Docker image built successfully$(NC)"
	@echo "  - $(IMAGE_NAME):$(VERSION)"
	@echo "  - $(IMAGE_NAME):latest"

push: ecr-create ## Push Docker image to ECR (creates ECR repo if needed)
	@echo "$(BLUE)Pushing image to ECR...$(NC)"
	@if [ -z "$(AWS_ACCOUNT_ID)" ]; then \
		echo "$(RED)Error: Unable to get AWS Account ID. Please configure AWS CLI.$(NC)"; \
		exit 1; \
	fi
	@echo "ECR Repository: $(ECR_REPO)"
	@echo "$(YELLOW)Logging into ECR...$(NC)"
	@aws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
	@echo "$(YELLOW)Tagging image...$(NC)"
	@docker tag $(IMAGE_NAME):$(VERSION) $(ECR_IMAGE)
	@docker tag $(IMAGE_NAME):$(VERSION) $(ECR_REPO):latest
	@echo "$(YELLOW)Pushing to ECR...$(NC)"
	@docker push $(ECR_IMAGE)
	@docker push $(ECR_REPO):latest
	@echo "$(GREEN)✓ Image pushed to ECR successfully$(NC)"
	@echo "  - $(ECR_IMAGE)"
	@echo "  - $(ECR_REPO):latest"

# ==============================================================================
# ECR Management
# ==============================================================================

ecr-create: ## Create ECR repository if it doesn't exist
	@echo "$(BLUE)Checking ECR repository...$(NC)"
	@if [ -z "$(AWS_ACCOUNT_ID)" ]; then \
		echo "$(RED)Error: Unable to get AWS Account ID. Please configure AWS CLI.$(NC)"; \
		exit 1; \
	fi
	@aws ecr describe-repositories --repository-name $(IMAGE_NAME) --region $(AWS_REGION) >/dev/null 2>&1 || \
		(echo "$(YELLOW)Creating ECR repository: $(IMAGE_NAME)$(NC)" && \
		aws ecr create-repository \
			--repository-name $(IMAGE_NAME) \
			--region $(AWS_REGION) \
			--image-scanning-configuration scanOnPush=true \
			--encryption-configuration encryptionType=AES256 >/dev/null && \
		echo "$(GREEN)✓ ECR repository created$(NC)")
	@echo "$(GREEN)✓ ECR repository exists: $(IMAGE_NAME)$(NC)"

ecr-delete: ## Delete ECR repository (with confirmation)
	@echo "$(RED)WARNING: This will delete the ECR repository and all images!$(NC)"
	@echo "Repository: $(IMAGE_NAME)"
	@echo "Region: $(AWS_REGION)"
	@read -p "Are you sure? Type 'yes' to confirm: " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		echo "$(YELLOW)Deleting ECR repository...$(NC)"; \
		aws ecr delete-repository \
			--repository-name $(IMAGE_NAME) \
			--region $(AWS_REGION) \
			--force && \
		echo "$(GREEN)✓ ECR repository deleted$(NC)"; \
	else \
		echo "$(YELLOW)Aborted$(NC)"; \
	fi

# ==============================================================================
# Testing
# ==============================================================================

test: ## Run unit tests
	@echo "$(BLUE)Running unit tests...$(NC)"
	@$(PYTEST) -v tests/unit/
	@echo "$(GREEN)✓ Tests passed$(NC)"

test-all: ## Run all tests (unit + integration + e2e)
	@echo "$(BLUE)Running all tests...$(NC)"
	@$(MAKE) -f Makefile.tests test-all
	@echo "$(GREEN)✓ All tests passed$(NC)"

# ==============================================================================
# Run Chainer (Local Python)
# ==============================================================================

run: ## Run chainer locally with ENV={environment} (e.g., make run ENV=shared)
	@if [ -z "$(ENV)" ]; then \
		echo "$(RED)Error: ENV is required$(NC)"; \
		echo "Usage: make run ENV=shared"; \
		echo ""; \
		echo "Available configuration files:"; \
		ls -1 configuration-*.yaml 2>/dev/null | sed 's/configuration-/  - /' | sed 's/.yaml//' || echo "  (none found)"; \
		exit 1; \
	fi
	@if [ ! -f "configuration-$(ENV).yaml" ]; then \
		echo "$(RED)Error: Configuration file not found: configuration-$(ENV).yaml$(NC)"; \
		echo ""; \
		echo "Available configuration files:"; \
		ls -1 configuration-*.yaml 2>/dev/null | sed 's/configuration-/  - /' | sed 's/.yaml//' || echo "  (none found)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Running Security Group Chainer$(NC)"
	@echo "Environment: $(ENV)"
	@echo "Configuration: configuration-$(ENV).yaml"
	@echo "$(BLUE)═══════════════════════════════════════════════════════════$(NC)"
	@$(PYTHON) src/chainer.py \
		--yaml-config configuration-$(ENV).yaml \
		--mode apply \
		--output /tmp/chainer-report-$(ENV).yaml
	@echo ""
	@echo "$(GREEN)✓ Chainer execution completed$(NC)"
	@echo "Report: /tmp/chainer-report-$(ENV).yaml"
	@if [ -f /tmp/chainer-report-$(ENV).yaml ]; then \
		echo ""; \
		echo "$(BLUE)Last 20 lines of report:$(NC)"; \
		tail -20 /tmp/chainer-report-$(ENV).yaml; \
	fi

install: run ## Alias for 'run' (e.g., make install ENV=shared)

# ==============================================================================
# Run Chainer (Docker Container)
# ==============================================================================

run-docker: ## Run chainer in Docker container with ENV={environment}
	@if [ -z "$(ENV)" ]; then \
		echo "$(RED)Error: ENV is required. Usage: make run-docker ENV=shared$(NC)"; \
		echo "$(YELLOW)Available configurations:$(NC)"; \
		ls -1 configuration-*.yaml 2>/dev/null | sed 's/configuration-/  - /' | sed 's/.yaml//' || echo "  None found"; \
		exit 1; \
	fi
	@if [ ! -f "configuration-$(ENV).yaml" ]; then \
		echo "$(RED)Error: Configuration file not found: configuration-$(ENV).yaml$(NC)"; \
		echo "$(YELLOW)Available configurations:$(NC)"; \
		ls -1 configuration-*.yaml 2>/dev/null | sed 's/configuration-/  - /' | sed 's/.yaml//' || echo "  None found"; \
		exit 1; \
	fi
	@echo "$(BLUE)Running Security Group Chainer in Docker$(NC)"
	@echo "Environment: $(GREEN)$(ENV)$(NC)"
	@echo "Configuration: $(GREEN)configuration-$(ENV).yaml$(NC)"
	@echo "Image: $(GREEN)$(IMAGE_NAME):$(VERSION)$(NC)"
	@echo "$(BLUE)═══════════════════════════════════════════════════════════$(NC)"
	@CONFIG_PATH=$$(realpath "configuration-$(ENV).yaml"); \
	AWS_DIR=$$(realpath "$$HOME/.aws"); \
	docker run --rm \
		-v "$$AWS_DIR:/home/chainer/.aws:ro" \
		-v "$$CONFIG_PATH:/app/config.yaml:ro" \
		-e AWS_REGION=$(AWS_REGION) \
		$(IMAGE_NAME):$(VERSION) \
		--yaml-config /app/config.yaml \
		--mode apply
	@echo ""
	@echo "$(GREEN)✓ Chainer execution completed$(NC)"
	@if [ -f "/tmp/chainer-report.yaml" ]; then \
		echo "$(BLUE)Report (last 20 lines):$(NC)"; \
		tail -20 /tmp/chainer-report.yaml; \
	fi

# ==============================================================================
# Cleanup
# ==============================================================================

clean: ## Clean up Docker images, cache, and reports
	@echo "$(BLUE)Cleaning up...$(NC)"
	@docker rmi $(IMAGE_NAME):$(VERSION) 2>/dev/null || true
	@docker rmi $(IMAGE_NAME):latest 2>/dev/null || true
	@docker rmi $(ECR_IMAGE) 2>/dev/null || true
	@docker rmi $(ECR_REPO):latest 2>/dev/null || true
	@rm -f /tmp/chainer-report-*.yaml
	@rm -rf .pytest_cache htmlcov .coverage
	@echo "$(GREEN)✓ Cleanup complete$(NC)"

# ==============================================================================
# Information
# ==============================================================================

info: ## Display current configuration
	@echo "$(BLUE)Current Configuration:$(NC)"
	@echo "  AWS Region:       $(AWS_REGION)"
	@echo "  AWS Account ID:   $(AWS_ACCOUNT_ID)"
	@echo "  Image Name:       $(IMAGE_NAME)"
	@echo "  Version:          $(VERSION)"
	@echo "  Local Image:      $(LOCAL_IMAGE)"
	@echo "  ECR Repository:   $(ECR_REPO)"
	@echo ""
	@echo "$(BLUE)Available Configurations:$(NC)"
	@ls -1 configuration-*.yaml 2>/dev/null | sed 's/configuration-/  - /' | sed 's/.yaml//' || echo "  (none found)"
	@echo ""
	@echo "$(BLUE)Docker Images:$(NC)"
	@docker images $(IMAGE_NAME) --format "  - {{.Repository}}:{{.Tag}} ({{.Size}})" 2>/dev/null || echo "  (none found)"
