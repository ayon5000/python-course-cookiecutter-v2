"""
For testing the makefile in the generated project i.e.
- does linting pass in a newly generated project? testing? install?

Setup:
1. generate a project using cookiecutter
2. create a virtual environment and install project dependencies

Tests:
3. run tests
4. run linting

Cleanup/Teardown:
5. remove virtual environment
6. remove generated project

"""

import subprocess
from pathlib import Path


def test__linting_passes(project_dir: Path):
    subprocess.run(["make", "lint-ci"], cwd=project_dir, check=True)


def test__tests_pass(project_dir: Path):
    subprocess.run(["make", "install"], cwd=project_dir, check=True)
    subprocess.run(["make", "test-wheel-locally"], cwd=project_dir, check=True)
