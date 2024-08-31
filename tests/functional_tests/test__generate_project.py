"""Test that the cookiecutter template is valid."""

from pathlib import Path


def test__generate_project(project_dir: Path):
    """Doc String."""
    assert project_dir.exists()
