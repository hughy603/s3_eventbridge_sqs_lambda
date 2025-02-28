# CLAUDE.md - Assistant Guidelines

## Build & Deploy Commands

- `poetry install` - Install dependencies
- `poetry run pytest` - Run all tests
- `poetry run pytest src/python/tests/test_file.py::test_function` - Run a specific test
- `poetry run ruff check --fix src/python/` - Lint and fix Python code
- `poetry run ruff format src/python/` - Format Python code
- `poetry shell` - Activate virtual environment
- `poetry add <package>` - Add new dependencies
- `poetry add -G dev <package>` - Add development dependencies
- `pre-commit run --all-files` - Run all pre-commit hooks
- `terraform init` - Initialize Terraform
- `terraform plan` - Preview infrastructure changes
- `terraform apply` - Apply infrastructure changes

## Code Style Guidelines

- **Python**: Follow PEP 8 standards and use Poetry
- **Imports**: Group standard library, third-party, and local imports
- **Terraform**: Use HCL format conventions with 2-space indentation
- **Naming**: snake_case for Python variables/functions, PascalCase for classes
- **Types**: Use type annotations for Python functions
- **Error Handling**: Use try/except blocks with specific exceptions
- **Documentation**: Docstrings for functions/classes using Google style
- **Testing**: Unit tests for Python, Terratest for infrastructure

## Project Structure

This project connects S3 events to Lambda functions through EventBridge and SQS, built with Python 3.13 and Terraform.
