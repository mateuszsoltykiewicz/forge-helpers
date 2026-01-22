.PHONY: help test test-unit coverage install-test clean build run

.DEFAULT_GOAL := help

PYTHON := python3
PYTEST := pytest
SRC_DIR := src
TEST_DIR := tests

help: ## Display this help
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

install-test: ## Install test dependencies
	pip install -r requirements-test.txt

test: ## Run all tests
	$(PYTEST) -v $(TEST_DIR)

test-unit: ## Run unit tests only
	$(PYTEST) -v -m unit $(TEST_DIR)/unit/

coverage: ## Run tests with coverage
	$(PYTEST) --cov=$(SRC_DIR) --cov-report=html --cov-report=term-missing $(TEST_DIR)

clean: ## Clean build artifacts
	rm -rf __pycache__ .pytest_cache htmlcov .coverage
	find . -type d -name "__pycache__" -exec rm -rf {} +
	find . -type f -name "*.pyc" -delete

build: ## Build Docker image locally
	docker build -t lambda-log-transformer:latest .

run: ## Run Docker container with test event
	docker run --rm -e CUSTOMER=acme -e PROJECT=forge -e ENVIRONMENT=production lambda-log-transformer:latest
