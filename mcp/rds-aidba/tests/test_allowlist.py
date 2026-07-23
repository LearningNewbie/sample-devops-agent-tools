"""Tests for the rds-aidba MCP Server query allowlist and validation logic."""

import os
import sys
import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))


class TestQueryAllowlist:
    """Test that the query allowlist is complete and well-formed."""

    def test_all_categories_present(self):
        from server import MYSQL_QUERIES
        expected = {"1", "2", "3", "4", "5", "6", "7", "8", "9"}
        assert set(MYSQL_QUERIES.keys()) == expected

    def test_each_category_has_metadata(self):
        from server import MYSQL_QUERIES
        for cat_num, cat in MYSQL_QUERIES.items():
            assert "_category" in cat, f"Category {cat_num} missing _category"

    def test_each_query_has_required_fields(self):
        from server import MYSQL_QUERIES
        for cat_num, cat in MYSQL_QUERIES.items():
            for qid, qdef in cat.items():
                if qid.startswith("_"):
                    continue
                assert "name" in qdef, f"Query {qid} missing 'name'"
                assert "sql" in qdef, f"Query {qid} missing 'sql'"
                assert len(qdef["sql"]) > 0, f"Query {qid} has empty SQL"

    def test_no_mutative_sql(self):
        from server import MYSQL_QUERIES
        blocked = ["INSERT", "UPDATE", "DELETE", "DROP", "CREATE", "ALTER", "TRUNCATE"]
        for cat_num, cat in MYSQL_QUERIES.items():
            for qid, qdef in cat.items():
                if qid.startswith("_"):
                    continue
                sql_upper = qdef["sql"].upper().strip()
                for keyword in blocked:
                    assert not sql_upper.startswith(keyword), (
                        f"Query {qid} starts with blocked keyword: {keyword}"
                    )

    def test_query_count(self):
        from server import MYSQL_QUERY_COUNT
        assert MYSQL_QUERY_COUNT >= 23, f"Expected >= 23 queries, got {MYSQL_QUERY_COUNT}"


class TestValidation:
    """Test allowlist validation functions."""

    def setup_method(self):
        os.environ["STAGE_NAME"] = "dev"
        os.environ["ALLOWED_CLUSTERS"] = "test-cluster-1,test-cluster-2"
        os.environ["ALLOWED_DATABASES"] = "mcptest,information_schema"

    def teardown_method(self):
        for var in ("STAGE_NAME", "ALLOWED_CLUSTERS", "ALLOWED_DATABASES"):
            os.environ.pop(var, None)

    def test_validate_cluster_allowed(self):
        from server import validate_cluster, ALLOWED_CLUSTERS
        ALLOWED_CLUSTERS.clear()
        ALLOWED_CLUSTERS.update({"test-cluster-1", "test-cluster-2"})
        ok, msg = validate_cluster("test-cluster-1")
        assert ok is True

    def test_validate_cluster_blocked(self):
        from server import validate_cluster, ALLOWED_CLUSTERS
        ALLOWED_CLUSTERS.clear()
        ALLOWED_CLUSTERS.update({"test-cluster-1", "test-cluster-2"})
        ok, msg = validate_cluster("prod-secret-cluster")
        assert ok is False
        assert "not in allowed list" in msg

    def test_validate_database_allowed(self):
        from server import validate_database, ALLOWED_DATABASES
        ALLOWED_DATABASES.clear()
        ALLOWED_DATABASES.update({"mcptest", "information_schema"})
        ok, msg = validate_database("mcptest")
        assert ok is True

    def test_validate_database_blocked(self):
        from server import validate_database, ALLOWED_DATABASES
        ALLOWED_DATABASES.clear()
        ALLOWED_DATABASES.update({"mcptest", "information_schema"})
        ok, msg = validate_database("sensitive_db")
        assert ok is False

    def test_wildcard_allows_all(self):
        from server import validate_cluster, ALLOWED_CLUSTERS
        ALLOWED_CLUSTERS.clear()  # Empty = wildcard
        ok, msg = validate_cluster("anything-goes")
        assert ok is True
