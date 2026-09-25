"""Run from any directory: python run_tests.py [--iverilog PATH] [--vvp PATH].

Builds into ignored chip-inventor/sim/uart. System tests replace only the
instruction ROM in a scratch copy, preserving the checked-in Stage 2 firmware.
Tests both independently generated flattened source variants.
"""
import argparse
from pathlib import Path
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parent
CHIP = HERE.parents[1]
sys.path.insert(0, str(CHIP.parent / 'legacy/scripts'))
from rvbl2_asm import Asm


def firmware_rom():
    a = Asm()
    a.lui(1, 0xf1000)
    a.label('rxwait')
    a.load('lw', 3, 8, 1)
    a.i('andi', 3, 3, 2)
    a.branch('beq', 3, 0, 'rxwait')
    a.store('sw', 0, 8, 1)
    a.load('lw', 2, 4, 1)
    a.label('txwait')
    a.load('lw', 3, 8, 1)
    a.i('andi', 3, 3, 4)
    a.branch('beq', 3, 0, 'txwait')
    a.store('sw', 2, 0, 1)
    a.li(3, 1)
    a.store('sw', 3, 8, 1)
    a.label('donewait')
    a.load('lw', 3, 8, 1)
    a.i('andi', 3, 3, 4)
    a.branch('beq', 3, 0, 'donewait')
    a.li(4, 0x55)
    a.label('pass')
    a.jal(0, 'pass')
    cases = '\n'.join(f"10'd{(addr-0x00400000)//4}: data_o=32'h{word:08x}; // {text}"
                      for addr, word, text, comment in a.assemble())
    return '''module imem(input wire clk_i, input wire [31:0] addr_i,
input wire oe_i, output reg [31:0] data_o);
always @(*) begin
    data_o=0;
    if (oe_i) begin
        case(addr_i[9:0])
''' + cases + '''
        default: data_o=32'h0000006f;
        endcase
    end
end
endmodule'''


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument('--iverilog', default='iverilog')
    parser.add_argument('--vvp', default='vvp')
    args = parser.parse_args()
    scratch = CHIP / 'sim/uart'
    scratch.mkdir(parents=True, exist_ok=True)

    def run(name, top, sources):
        out = scratch / (name + '.vvp')
        subprocess.run([args.iverilog, '-g2012', '-s', top, '-o', str(out),
                        *map(str, sources)], check=True, cwd=scratch)
        result = subprocess.run([args.vvp, str(out)], check=True, cwd=scratch,
                                capture_output=True, text=True)
        print(name + ':\n' + result.stdout)
        if 'ALL TESTS PASSED' not in result.stdout or 'FAIL ' in result.stdout:
            raise RuntimeError(name + ' failed')

    run('uart', 'tb_uart', [CHIP/'rtl/uart.v', CHIP/'rtl/uart_tx.v', CHIP/'rtl/uart_rx.v', CHIP/'rtl/address_decoder.v', HERE/'tb_uart.v'])
    for variant in ['hdl.v', 'rtl/top.v']:
        tag = variant.replace('/', '_').replace('.v', '')
        source = CHIP / variant
        run(tag + '_stage2', 'testbench', [source, CHIP/'testbench/testbench.v'])
        text, count = re.subn(r'module imem\b.*?endmodule',
                              lambda _: firmware_rom(), source.read_text(), flags=re.S)
        assert count == 1, 'Expected one instruction ROM'
        test_source = scratch / (tag + '_uart_rom.v')
        test_source.write_text(text)
        run(tag + '_uart_system', 'tb_uart_system', [test_source, HERE/'tb_uart_system.v'])


if __name__ == '__main__':
    main()
