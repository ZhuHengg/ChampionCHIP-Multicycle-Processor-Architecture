"""Slide figures for the Stage 3 video (docs/video/SLIDES.md, slide 4).

    python docs/video/figures/make_figures.py [--png]

Writes three 1920x1080 SVGs, each in a dark and a light theme, next to this
script. --png also renders them to 3840x2160 PNGs through headless Microsoft
Edge, for importing into Canva.

Every address, register and signal name is taken from chip-inventor/rtl
(address_decoder.v, gpio.v, uart.v, uart_rx.v) and firmware/src/main.s.
"""
import argparse
import html
import shutil
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
W, H = 1920, 1080

THEMES = {
    'dark': dict(bg='#0B1020', panel='#141B2E', inner='#1B2440', stroke='#2E3A5C',
                 text='#E8ECF5', muted='#93A0BD',
                 core='#5EC8E5', dec='#F2C94C', imem='#4C8DFF', dmem='#3CCB7F',
                 gpio='#FF8A3D', uart='#B07CFF', emu='#C9D1E3', badge_text='#0B1020'),
    'light': dict(bg='#FFFFFF', panel='#F5F7FB', inner='#EAEFF7', stroke='#D0D7E6',
                  text='#152033', muted='#56627A',
                  core='#1592B3', dec='#B8860B', imem='#2F6FE0', dmem='#1E9E5A',
                  gpio='#E2650E', uart='#7E44D6', emu='#56627A', badge_text='#FFFFFF'),
}

SANS = "Segoe UI, Inter, Helvetica, Arial, sans-serif"
MONO = "Consolas, 'JetBrains Mono', Menlo, monospace"
ACCENTS = ('core', 'dec', 'imem', 'dmem', 'gpio', 'uart', 'emu', 'muted')


class Svg:
    def __init__(self, t):
        self.t = t
        self.parts = []

    def add(self, s):
        self.parts.append(s)

    def rect(self, x, y, w, h, stroke, fill=None, rx=14, sw=2, dash=None):
        d = f' stroke-dasharray="{dash}"' if dash else ''
        self.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" '
                 f'fill="{fill or self.t["panel"]}" stroke="{stroke}" stroke-width="{sw}"{d}/>')

    def text(self, x, y, s, size=20, color=None, weight=400, anchor='start', mono=False):
        fam = MONO if mono else SANS
        self.add(f'<text x="{x}" y="{y}" font-family="{fam}" font-size="{size}" '
                 f'font-weight="{weight}" fill="{color or self.t["text"]}" '
                 f'text-anchor="{anchor}">{html.escape(s)}</text>')

    def line(self, pts, key, sw=3, arrow=True, dash=None):
        path = ' '.join(f'{x},{y}' for x, y in pts)
        m = f' marker-end="url(#ah-{key})"' if arrow else ''
        d = f' stroke-dasharray="{dash}"' if dash else ''
        self.add(f'<polyline points="{path}" fill="none" stroke="{self.t[key]}" '
                 f'stroke-width="{sw}" stroke-linejoin="round"{m}{d}/>')

    def badge(self, n, x, y, key):
        self.add(f'<circle cx="{x}" cy="{y}" r="17" fill="{self.t[key]}"/>')
        self.text(x, y + 7, str(n), 19, self.t['badge_text'], 700, 'middle')

    def label(self, x, y, s, key, size=17, anchor='middle'):
        """Mono label on a small background plate, so it reads over lines."""
        w = len(s) * size * 0.56 + 16
        x0 = x - w / 2 if anchor == 'middle' else x - 8
        self.add(f'<rect x="{x0:.0f}" y="{y - size - 3}" width="{w:.0f}" height="{size + 11}" '
                 f'rx="6" fill="{self.t["bg"]}"/>')
        self.text(x, y, s, size, self.t[key], 600, anchor, mono=True)

    def tristate(self, x, y, key, pointing='right', bubble=False):
        """Buffer triangle with its tip at (x, y)."""
        c = self.t[key]
        if pointing == 'right':
            pts = f'{x - 60},{y - 32} {x},{y} {x - 60},{y + 32}'
        else:
            pts = f'{x + 60},{y - 32} {x},{y} {x + 60},{y + 32}'
        self.add(f'<polygon points="{pts}" fill="{self.t["inner"]}" stroke="{c}" stroke-width="3"/>')

    def render(self):
        markers = ''.join(
            f'<marker id="ah-{k}" viewBox="0 0 10 10" refX="8.5" refY="5" markerWidth="6" '
            f'markerHeight="6" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" '
            f'fill="{self.t[k]}"/></marker>' for k in ACCENTS)
        return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
                f'viewBox="0 0 {W} {H}"><defs>{markers}</defs>'
                f'<rect width="{W}" height="{H}" fill="{self.t["bg"]}"/>'
                + ''.join(self.parts) + '</svg>')


def header(s, title, subtitle):
    s.text(70, 88, title, 46, weight=700)
    s.text(70, 132, subtitle, 24, s.t['muted'])


# ---------------------------------------------------------------------------
# Figure 1: where GPIO and UART sit on the bus
# ---------------------------------------------------------------------------
def fig_integration(t):
    s = Svg(t)
    header(s, 'GPIO & UART integration',
           'Memory-mapped peripherals on the RVBL-2 bus, reached with ordinary lw / sw')
    top, bot = 190, 930

    # Core
    s.rect(60, top, 330, bot - top, t['core'], sw=3)
    s.text(90, top + 50, 'RVBL-2 core', 30, t['core'], 700)
    for i, ln in enumerate(('Multicycle, 9-state FSM', 'RV32I + Zmmul + Xicrc', '20 MHz')):
        s.text(90, top + 95 + i * 34, ln, 21, t['muted'])
    s.rect(85, 560, 280, 250, t['core'], t['inner'], rx=10)
    s.text(105, 600, 'Load / store unit', 22, weight=700)
    for i, ln in enumerate(('lw / sw drive:', 'address', 'we · oe · bw', 'write data', '← read data')):
        s.text(105, 640 + i * 32, ln, 19, t['muted'], mono=i > 0)

    # Bus: request to the decoder, read data back
    s.line([(365, 650), (515, 650)], 'core', 4)
    s.label(440, 632, 'request', 'core', 16)
    s.line([(515, 740), (365, 740)], 'core', 4)
    s.label(440, 722, 'read data', 'core', 16)

    # Decoder
    s.rect(520, top, 330, bot - top, t['dec'], sw=3)
    s.text(550, top + 50, 'Address decoder', 30, t['dec'], 700)
    rows = (('0x0040_0000', 'IMEM', 'imem'), ('0x1001_0000', 'DMEM', 'dmem'),
            ('0xF000_0000', 'GPIO', 'gpio'), ('0xF100_0000', 'UART', 'uart'))
    for i, (addr, name, key) in enumerate(rows):
        y = top + 115 + i * 52
        s.text(550, y, addr, 23, t[key], 600, mono=True)
        s.text(760, y, name, 23, t[key], 700)
    s.text(550, top + 350, 'Decodes the address,', 20, t['muted'])
    s.text(550, top + 378, 'gates we / oe to one block,', 20, t['muted'])
    s.text(550, top + 406, 'muxes its read data back.', 20, t['muted'])
    s.text(550, top + 460, 'Unmapped address → reads 0', 20, t['muted'])

    # Targets
    tx, tw = 940, 400
    blocks = (
        ('imem', 'Instruction ROM', ['firmware: 264 instructions'], 190, 125),
        ('dmem', 'Data memory', ['32 bytes · unused by our app'], 335, 115),
        ('gpio', 'GPIO   0xF0000000',
         ['+0 DATAOUT  +4 DATAIN  +8 DATADIR', '8 identical pin cells', 'registered reads'], 470, 215),
        ('uart', 'UART   0xF1000000',
         ['+0 TXDATA  +4 RXDATA  +8 CONTROL', 'TX + RX · 115200 8N1', '174 clocks per bit'], 715, 215),
    )
    for key, title, lines, y, h in blocks:
        s.rect(tx, y, tw, h, t[key], sw=3)
        s.text(tx + 24, y + 42, title, 25, t[key], 700)
        for i, ln in enumerate(lines):
            s.text(tx + 24, y + 80 + i * 32, ln, 19, t['muted'], mono=i == 0 and key in ('gpio', 'uart'))
        s.line([(850, y + h / 2), (tx - 5, y + h / 2)], key, 3)

    # Pins to the outside world
    ex = 1590
    pins = (('pins_i[7:0]', 'gpio', 525, 'in'), ('pins_o[7:0]', 'gpio', 580, 'out'),
            ('pins_oe_o[7:0]', 'gpio', 635, 'out'),
            ('rx_i', 'uart', 790, 'in'), ('tx_o', 'uart', 860, 'out'))
    for name, key, y, d in pins:
        if d == 'in':
            s.line([(ex - 5, y), (tx + tw + 5, y)], key, 3)
        else:
            s.line([(tx + tw + 5, y), (ex - 5, y)], key, 3)
        s.label((tx + tw + ex) / 2, y - 10, name, key, 17)

    # Emulator
    s.rect(ex, 470, 270, 460, t['emu'], sw=3, dash='10 7')
    s.text(ex + 22, 512, 'Emulator  ./emu', 24, t['emu'], 700)
    s.text(ex + 22, 560, 'GPIO  -d -i -o', 20, t['gpio'], 700, mono=True)
    for i, ln in enumerate(('P2–P0 in: pilot', 'P3 in: E-stop', 'P4–P7 out: contactor,', '  lock, grid hold, fault')):
        s.text(ex + 22, 594 + i * 28, ln, 18, t['muted'])
    s.text(ex + 22, 760, 'UART  -t -r', 20, t['uart'], 700, mono=True)
    for i, ln in enumerate(('-t in: meter frames', '-r out: session record')):
        s.text(ex + 22, 794 + i * 28, ln, 18, t['muted'])

    s.text(70, 990, 'Registered peripheral reads match the core\'s MEM_ACCESS_ADDR → MEM_ACCESS_DATA load timing, '
           'so GPIO and UART joined the Stage 2 core with no FSM changes.', 20, t['muted'])
    s.text(70, 1024, 'The core never needs a new instruction to reach the outside world: every pin and every '
           'serial byte is one lw or sw.', 20, t['muted'])
    return s.render()


# ---------------------------------------------------------------------------
# Figure 2: how the peripherals take part in every decision
# ---------------------------------------------------------------------------
def fig_process(t):
    s = Svg(t)
    header(s, 'How GPIO & UART drive every decision',
           'Everything the emulator sends enters through a peripheral; everything it checks leaves the same way')
    cols = ((60, 420, 'Emulator  (./emu)', 'emu'),
            (560, 1060, 'Peripheral hardware', 'text'),
            (1200, 1860, 'Firmware on RVBL-2  (main.s)', 'core'))
    for x0, x1, name, key in cols:
        s.text((x0 + x1) / 2, 185, name, 25, t[key] if key != 'text' else t['text'], 700, 'middle')

    def lane(y0, key, tag):
        s.rect(40, y0, 1840, 380, t[key], t['bg'], rx=18, sw=2, dash='4 6')
        s.label(110, y0 + 8, tag, key, 18)

    def card(x0, x1, y, h, key, title, sub, mono_title=True):
        s.rect(x0, y, x1 - x0, h, t[key], t['panel'], rx=12, sw=2.5)
        s.text(x0 + 20, y + 38, title, 22, t[key], 700, mono=mono_title)
        for i, ln in enumerate(sub):
            s.text(x0 + 20, y + 72 + i * 28, ln, 18, t['muted'])

    # GPIO lane
    g = 215
    lane(g, 'gpio', 'GPIO')
    card(60, 420, g + 30, 130, 'emu', '-i 0x02', ['car asks to charge', '(pilot C on P2–P0)'])
    card(60, 420, g + 215, 130, 'emu', '-o 0x30', ['expects contactor + lock', 'on P4 and P5'])
    card(560, 1060, g + 30, 130, 'gpio', 'DATAIN', ['samples each pin whose DATADIR bit = 0', '(P3–P0 are inputs)'])
    card(560, 1060, g + 215, 130, 'gpio', 'DATAOUT  ·  DATADIR 0xF0',
         ['DATAOUT → pins_o,  DATADIR → pins_oe_o', 'P7–P4 driven as outputs'])
    card(1200, 1860, g + 30, 130, 'core', 'lw  DATAIN',
         ['apply the pilot and E-stop rules', 'app FSM: CONNECTED → CHARGING'])
    card(1200, 1860, g + 215, 130, 'core', 'sw  0x30 → DATAOUT',
         ['one store per state change', '0x20 lock · 0x30 charge · 0x60 hold · 0x80 fault'])
    s.line([(420, g + 95), (555, g + 95)], 'gpio', 4)
    s.label(488, g + 80, 'pins_i', 'gpio', 16)
    s.line([(1060, g + 95), (1195, g + 95)], 'gpio', 4)
    s.label(1128, g + 80, '0xF0000004', 'gpio', 15)
    s.line([(1530, g + 160), (1530, g + 210)], 'core', 3)
    s.line([(1195, g + 280), (1060, g + 280)], 'gpio', 4)
    s.label(1128, g + 265, '0xF0000000', 'gpio', 15)
    s.line([(555, g + 280), (420, g + 280)], 'gpio', 4)
    s.label(488, g + 265, 'pins_o', 'gpio', 16)
    for n, x, y in ((1, 488, g + 118), (2, 1128, g + 118), (3, 1560, g + 185),
                    (4, 1128, g + 303), (5, 488, g + 303)):
        s.badge(n, x, y, 'gpio')

    # UART lane
    u = 635
    lane(u, 'uart', 'UART')
    card(60, 420, u + 30, 130, 'emu', '-t4  -t4', ['one 8-byte meter frame:', 'V · I · F · CRC'])
    card(60, 420, u + 215, 130, 'emu', '-r4  -r2  -r2', ['reads the 8-byte', 'session record'])
    card(560, 1060, u + 30, 130, 'uart', 'Receiver → RXDATA',
         ['2-flop sync · one mid-bit sample', 'byte done → RXDONE = 1'])
    card(560, 1060, u + 215, 130, 'uart', 'TXDATA → Transmitter',
         ['TRANSMIT pulse starts the byte', 'TXDONE = 1 when sent'])
    card(1200, 1860, u + 30, 130, 'core', 'poll RXDONE → lw RXDATA',
         ['crcb folds each byte into the CRC', '8th byte: check frame · mul V × I'])
    card(1200, 1860, u + 215, 130, 'core', 'sw TXDATA · set TRANSMIT',
         ['on unplug or fault: 8-byte record', 'energy · status · frames · CRC'])
    s.line([(420, u + 95), (555, u + 95)], 'uart', 4)
    s.label(488, u + 80, 'rx_i', 'uart', 16)
    s.line([(1060, u + 95), (1195, u + 95)], 'uart', 4)
    s.label(1128, u + 80, '0xF1000004', 'uart', 15)
    s.line([(1530, u + 160), (1530, u + 210)], 'core', 3)
    s.line([(1195, u + 280), (1060, u + 280)], 'uart', 4)
    s.label(1128, u + 265, '0xF1000000', 'uart', 15)
    s.line([(555, u + 280), (420, u + 280)], 'uart', 4)
    s.label(488, u + 265, 'tx_o', 'uart', 16)
    for n, x, y in ((6, 488, u + 118), (7, 1128, u + 118), (8, 1560, u + 185),
                    (9, 1128, u + 303), (10, 488, u + 303)):
        s.badge(n, x, y, 'uart')

    s.text(70, 1050, '115,200 baud at 20 MHz = 174 clocks per bit, so one byte takes 1,740 cycles: '
           'the firmware checks a frame long before the next byte arrives.', 20, t['muted'])
    return s.render()


# ---------------------------------------------------------------------------
# Figure 3: one GPIO pin cell, guide Figure 1 vs ours
# ---------------------------------------------------------------------------
def fig_pin_cell(t):
    s = Svg(t)
    header(s, 'One GPIO pin: guide vs our design',
           'Same registers and behaviour; the tri-state buffer moves to the pad')

    def ff(x, y, name, key):
        s.rect(x, y, 170, 90, t[key], t['inner'], rx=8, sw=2.5)
        s.text(x + 85, y + 38, name, 20, t[key], 700, 'middle')
        s.text(x + 85, y + 70, 'flip-flop', 16, t['muted'], anchor='middle')

    def pad(x, y, label):
        s.add(f'<rect x="{x - 22}" y="{y - 22}" width="44" height="44" fill="none" '
              f'stroke="{t["text"]}" stroke-width="3"/>')
        s.add(f'<path d="M{x - 22},{y - 22} L{x + 22},{y + 22} M{x + 22},{y - 22} L{x - 22},{y + 22}" '
              f'stroke="{t["text"]}" stroke-width="2"/>')
        s.text(x, y + 52, label, 18, t['muted'], 600, 'middle', mono=True)

    # Left panel: guide Figure 1
    s.rect(50, 180, 880, 700, t['stroke'], t['panel'], rx=18)
    s.text(80, 228, 'Guide, Figure 1', 26, weight=700)
    s.text(80, 262, 'tri-state buffers inside the block, one inout pin', 19, t['muted'])
    ff(90, 310, 'DATADIR', 'gpio')
    ff(90, 480, 'DATAOUT', 'gpio')
    ff(90, 700, 'DATAIN', 'gpio')
    s.tristate(560, 525, 'gpio')                         # output buffer, tip at 560
    s.tristate(500, 745, 'gpio', pointing='left')        # input buffer, tip at 500
    s.line([(260, 525), (500, 525)], 'gpio', 3, arrow=False)
    s.line([(260, 355), (530, 355), (530, 505)], 'gpio', 3)
    s.line([(530, 355), (620, 355), (620, 700), (530, 700), (530, 721)], 'gpio', 3)
    s.add(f'<circle cx="530" cy="720" r="7" fill="{t["panel"]}" stroke="{t["gpio"]}" stroke-width="3"/>')
    s.line([(560, 525), (800, 525)], 'gpio', 3, arrow=False)
    s.line([(700, 525), (700, 745), (565, 745)], 'gpio', 3)
    s.line([(500, 745), (265, 745)], 'gpio', 3)
    pad(830, 525, 'pins_io')
    s.text(80, 850, 'Needs a true bidirectional pin inside the design.', 19, t['muted'])

    # Right panel: ours
    s.rect(990, 180, 880, 700, t['gpio'], t['panel'], rx=18, sw=3)
    s.text(1020, 228, 'Our gpio.v', 26, t['gpio'], 700)
    s.text(1020, 262, 'split bus out of the core; the pad does the tri-state', 19, t['muted'])
    ff(1030, 310, 'DATADIR', 'gpio')
    ff(1030, 480, 'DATAOUT', 'gpio')
    ff(1030, 700, 'DATAIN', 'gpio')
    edge = 1420
    s.add(f'<line x1="{edge}" y1="290" x2="{edge}" y2="820" stroke="{t["muted"]}" '
          f'stroke-width="2" stroke-dasharray="8 8"/>')
    s.text(edge - 10, 305, 'core', 16, t['muted'], anchor='end')
    s.text(edge + 10, 305, 'pad', 16, t['muted'])
    s.line([(1200, 355), (edge + 150, 355)], 'gpio', 3)
    s.label(1310, 340, 'pins_oe_o', 'gpio', 17)
    s.line([(1200, 525), (edge + 150, 525)], 'gpio', 3)
    s.label(1310, 510, 'pins_o', 'gpio', 17)
    s.line([(edge + 150, 745), (1205, 745)], 'gpio', 3)
    s.label(1310, 730, 'pins_i', 'gpio', 17)
    s.text(1045, 820, 'samples only when DATADIR = 0', 16, t['muted'])
    s.rect(edge + 150, 320, 280, 460, t['stroke'], t['inner'], rx=10, dash='6 6')
    s.text(edge + 290, 500, 'pad / FPGA pin', 20, t['text'], 700, 'middle')
    s.text(edge + 290, 545, 'pin = pins_oe_o', 18, t['muted'], anchor='middle', mono=True)
    s.text(edge + 290, 575, '? pins_o : Z', 18, t['muted'], anchor='middle', mono=True)
    s.text(edge + 290, 620, 'pins_i = pin', 18, t['muted'], anchor='middle', mono=True)

    s.text(70, 950, 'Why: ChipInventor\'s inout pin drops its control inputs, and FPGA fabric and Sky130 pads '
           'expect separate in / out / enable signals.', 21, t['muted'])
    s.text(70, 990, 'Behaviour is unchanged: DATADIR bit 1 drives DATAOUT onto the pin; bit 0 releases it '
           'and DATAIN samples it.', 21, t['muted'])
    return s.render()


FIGURES = {
    'gpio_uart_integration': fig_integration,
    'gpio_uart_process': fig_process,
    'gpio_pin_cell': fig_pin_cell,
}


def edge_binary():
    for p in (r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
              r'C:\Program Files\Microsoft\Edge\Application\msedge.exe'):
        if Path(p).exists():
            return p
    return shutil.which('msedge') or shutil.which('microsoft-edge')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--png', action='store_true', help='also render 2x PNGs via headless Edge')
    args = ap.parse_args()
    edge = edge_binary() if args.png else None
    if args.png and not edge:
        ap.error('Microsoft Edge not found; open the SVGs in a browser instead')

    for name, fn in FIGURES.items():
        for theme, t in THEMES.items():
            svg = HERE / f'{name}_{theme}.svg'
            svg.write_text(fn(t), encoding='utf-8')
            print('wrote', svg.name)
            if edge:
                png = HERE / f'{name}_{theme}.png'
                subprocess.run([edge, '--headless=new', '--disable-gpu', '--hide-scrollbars',
                                f'--window-size={W},{H}', '--force-device-scale-factor=2',
                                f'--screenshot={png}', svg.as_uri()],
                               check=True, capture_output=True)
                print('wrote', png.name)


if __name__ == '__main__':
    main()
