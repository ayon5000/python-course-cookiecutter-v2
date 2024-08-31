from pathlib import Path


def test__generate_project(project_dir: Path):
    """adadasd

    execute: `cookiecutter <template directory> ...`
    """
    assert project_dir.exists()
