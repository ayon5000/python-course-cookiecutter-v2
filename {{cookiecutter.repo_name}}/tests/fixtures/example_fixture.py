"""Doc String."""

from uuid import uuid4

import pytest

from tests.consts import PROJECT_DIR


@pytest.fixture(scope="session")
def test_session_id() -> str:
    """Doc string."""
    test_session_id = str(PROJECT_DIR) + str(uuid4())[:6]
    return test_session_id
