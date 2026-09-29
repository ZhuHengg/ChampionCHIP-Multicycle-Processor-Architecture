"""Tests for the fleet-rebound simulation."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from rebound_sim import rebound


def test_sync_peak_is_everyone():
    # Without staggering, every charger restarts on the same frame: the peak is
    # the whole fleet at once.
    sync, _ = rebound(n_chargers=1000, kw=7.0)
    assert max(sync) == 7.0


def test_staggered_peak_at_least_7x_lower():
    sync, stag = rebound(n_chargers=1000, kw=7.0)
    assert max(sync) / max(stag) >= 7.5, (max(sync), max(stag))
