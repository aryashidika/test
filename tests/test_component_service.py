import pytest

from app.domain.component_service import ComponentNumberError, create_component, suggest_next_number


def _group_id(conn, code):
    return conn.execute("SELECT id FROM component_group WHERE code=?", (code,)).fetchone()["id"]


def test_reject_number_not_multiple_of_ten(conn):
    gid = _group_id(conn, "a")
    with pytest.raises(ComponentNumberError):
        create_component(conn, 15, "Toe Puff", gid, "APPROVED", "TEST")


def test_reject_number_out_of_group_range(conn):
    gid = _group_id(conn, "a")  # range 0-3990
    with pytest.raises(ComponentNumberError):
        create_component(conn, 4000, "Toe Puff", gid, "APPROVED", "TEST")


def test_accept_valid_component_number(conn):
    gid = _group_id(conn, "a")
    component_id = create_component(conn, 10, "Toe Puff", gid, "APPROVED", "TEST")
    assert component_id


def test_number_cannot_be_reused_even_if_inactive(conn):
    from app.domain.component_service import set_status

    gid = _group_id(conn, "a")
    component_id = create_component(conn, 20, "Lining", gid, "APPROVED", "TEST")
    set_status(conn, component_id, "INACTIVE", "TEST")
    with pytest.raises(ComponentNumberError):
        create_component(conn, 20, "Lining Baru", gid, "APPROVED", "TEST")


def test_suggest_next_number_increments_by_ten(conn):
    gid = _group_id(conn, "a")
    assert suggest_next_number(conn, gid) == 0
    create_component(conn, 0, "Toe Puff", gid, "APPROVED", "TEST")
    assert suggest_next_number(conn, gid) == 10
