"""
Reading rows the sensor importer must refuse (XRFF-661).

A NaN or infinite value cannot be sent as JSON, so one such row failed its
whole batch of 500; a timestamp without a UTC offset was stored as if it were
UTC. Both are now rejected per row, with the row number.
"""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parents[3] / "scripts" / "import"))
from ingest_sensor_data import coerce_reading  # noqa: E402


def reading(value="1.5", timestamp="2025-07-01T12:00:00+02:00"):
    return coerce_reading({"sensor_id": "7", "value": value, "timestamp": timestamp}, 3, {})


def test_a_valid_row_passes():
    out, error = reading()
    assert error is None and out["value"] == 1.5 and out["sensor_id"] == 7


@pytest.mark.parametrize("value", ["nan", "inf", "-Infinity"])
def test_non_finite_values_are_refused(value):
    out, error = reading(value=value)
    assert out is None and "finite" in error


@pytest.mark.parametrize("timestamp", ["2025-07-01 12:00", "2025-07-01T12:00:00"])
def test_timestamps_without_offset_are_refused(timestamp):
    out, error = reading(timestamp=timestamp)
    assert out is None and "offset" in error


def test_z_suffix_counts_as_utc():
    out, error = reading(timestamp="2025-07-01T12:00:00Z")
    assert error is None
