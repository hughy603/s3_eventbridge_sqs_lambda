.PHONY: init lint test deploy run-simulation monitor clean

# Setup
init:
	poetry install
	pre-commit install

# Linting
lint:
	pre-commit run --all-files

# Testing
test:
	poetry run pytest

# Terraform
tf-init:
	cd src/terraform && terraform init

tf-plan:
	cd src/terraform && terraform plan

tf-apply:
	cd src/terraform && terraform apply

tf-destroy:
	cd src/terraform && terraform destroy

# Run simulation
simulate:
	@echo "Usage: make simulate BUCKET=your-bucket-name [FILES=100] [ROWS=50] [WORKERS=10]"
	@if [ -z "$(BUCKET)" ]; then echo "Error: BUCKET is required"; exit 1; fi
	poetry run python src/python/simulate_uploads.py --bucket $(BUCKET) \
		--files $(or $(FILES),100) \
		--rows $(or $(ROWS),50) \
		--workers $(or $(WORKERS),10)

# Monitor processing
monitor:
	@echo "Usage: make monitor QUEUE=queue-url STATE_MACHINE=state-machine-arn FUNCTION=function-name"
	@if [ -z "$(QUEUE)" ]; then echo "Error: QUEUE is required"; exit 1; fi
	@if [ -z "$(STATE_MACHINE)" ]; then echo "Error: STATE_MACHINE is required"; exit 1; fi
	@if [ -z "$(FUNCTION)" ]; then echo "Error: FUNCTION is required"; exit 1; fi
	poetry run python src/python/monitor_processing.py --queue $(QUEUE) \
		--state-machine $(STATE_MACHINE) \
		--function $(FUNCTION)

# Run performance test
perf-test:
	@echo "Usage: make perf-test BUCKET=bucket-name QUEUE=queue-url STATE_MACHINE=state-machine-arn FUNCTION=function-name [FILES_PER_BATCH=50] [ROWS_PER_FILE=20] [NUM_BATCHES=5]"
	@if [ -z "$(BUCKET)" ]; then echo "Error: BUCKET is required"; exit 1; fi
	@if [ -z "$(QUEUE)" ]; then echo "Error: QUEUE is required"; exit 1; fi
	@if [ -z "$(STATE_MACHINE)" ]; then echo "Error: STATE_MACHINE is required"; exit 1; fi
	@if [ -z "$(FUNCTION)" ]; then echo "Error: FUNCTION is required"; exit 1; fi
	poetry run python src/python/performance_test.py --bucket $(BUCKET) \
		--queue $(QUEUE) \
		--state-machine $(STATE_MACHINE) \
		--function $(FUNCTION) \
		--files-per-batch $(or $(FILES_PER_BATCH),50) \
		--rows-per-file $(or $(ROWS_PER_FILE),20) \
		--num-batches $(or $(NUM_BATCHES),5) \
		--output-dir performance_results

# Clean
clean:
	find . -type d -name __pycache__ -exec rm -rf {} +
	find . -type f -name "*.pyc" -delete
	find . -type f -name "*.pyo" -delete
	find . -type f -name "*.pyd" -delete
	find . -type f -name ".coverage" -delete
	find . -type d -name "*.egg-info" -exec rm -rf {} +
	find . -type d -name "*.egg" -exec rm -rf {} +
	find . -type d -name ".pytest_cache" -exec rm -rf {} +
	find . -type d -name ".ruff_cache" -exec rm -rf {} +
	rm -rf .coverage
	rm -rf htmlcov/
	rm -rf .pytest_cache/
	rm -rf dist/
	rm -rf build/
	rm -rf .ruff_cache/
	rm -rf src/terraform/.terraform/
	rm -f src/terraform/terraform.tfstate*
	rm -f src/terraform/*.zip
