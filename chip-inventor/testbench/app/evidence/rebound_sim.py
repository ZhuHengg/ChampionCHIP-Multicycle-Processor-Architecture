"""Fleet rebound: what the CRC-hashed restart delay is actually worth (P2).

One grid event pauses a whole fleet of chargers. If every charger waits the
same number of healthy frames, they all reconnect on the same frame and the
grid sees the entire fleet's load return as one step -- the "rebound" that
makes naive demand response dangerous.

Our restart delay is HOLD_BASE + (CRC-16(CHARGER_ID, seed=trigger CRC) & 7), so
chargers that saw the *same* event still restart on different frames, with no
coordination, no clock and no configuration.

Run as a script for the per-frame table; saves docs/figures/rebound.png if
matplotlib is available.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from golden import HOLD_BASE, restart_delay

BASE_ID = 0x4D590000          # fleet of sequential charger IDs
TRIGGER_CRC = 0x1D0F          # one shared grid event


def rebound(n_chargers=1000, kw=7.0, trigger_crc=TRIGGER_CRC, base_id=BASE_ID):
    """Load restored per frame, in MW, for both strategies.

    Returns (synchronised, staggered): lists indexed by frames since the grid
    recovered. Index i holds the load that reconnects on frame i.
    """
    fleet_mw = n_chargers * kw / 1000.0

    # Every charger waits the same fixed delay.
    span = HOLD_BASE + 8
    sync = [0.0] * span
    sync[HOLD_BASE] = fleet_mw

    # Each charger hashes its own ID with the event's CRC.
    stag = [0.0] * span
    for k in range(n_chargers):
        stag[restart_delay(trigger_crc, base_id + k)] += kw / 1000.0

    return sync, stag


def main():
    sync, stag = rebound()
    print(f'Fleet: 1000 chargers x 7.0 kW = {sum(sync):.1f} MW, '
          f'one shared grid event (trigger CRC 0x{TRIGGER_CRC:04X})')
    print()
    print('frame   synchronised   staggered')
    for i, (a, b) in enumerate(zip(sync, stag)):
        print(f'{i:>5}   {a:>9.3f} MW   {b:>6.3f} MW')
    print()
    print(f'peak synchronised: {max(sync):.3f} MW')
    print(f'peak staggered:    {max(stag):.3f} MW')
    print(f'reduction:         {max(sync) / max(stag):.2f}x')

    try:
        import matplotlib
        matplotlib.use('Agg')
        import matplotlib.pyplot as plt
    except ImportError:
        print('\n(matplotlib not installed: skipping the figure)')
        return

    frames = range(len(sync))
    fig, ax = plt.subplots(figsize=(7, 3.5))
    ax.bar([f - 0.2 for f in frames], sync, width=0.4, label='fixed delay (all together)')
    ax.bar([f + 0.2 for f in frames], stag, width=0.4, label='CRC-hashed delay')
    ax.set_xlabel('frames after the grid recovers')
    ax.set_ylabel('load restored (MW)')
    ax.set_title('1000 x 7 kW chargers restarting after one grid event')
    ax.legend()
    fig.tight_layout()
    out = Path(__file__).resolve().parents[4] / 'docs' / 'figures' / 'rebound.png'
    out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out, dpi=150)
    print(f'\nwrote {out}')


if __name__ == '__main__':
    main()
