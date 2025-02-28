"""Root conftest.py to set up Python path for testing."""

import os
import sys

# Add src directory to the Python path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "src")))
