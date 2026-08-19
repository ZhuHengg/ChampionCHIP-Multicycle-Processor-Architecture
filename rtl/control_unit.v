// control_unit.v — owned by Teammate A
//
// Implements the FSM described in HANDOFF_control_unit.md.
// Follow the workflow in CLAUDE.md: spec review -> interface -> state
// table -> RTL -> self-review -> testbench -> simulate -> document.
//
// `include "pkg/rvbl2_defines.vh" for every opcode/op-code literal.
// Do not hardcode values already defined there.
//
// Recommended build order (handoff doc §11):
//   1. FETCH -> DECODE -> EXECUTE(ALU only) -> WRITE BACK, verify in sim
//   2. Add MEM_ADDR / MEM_ACCESS (load 2-cycle, store 1-cycle)
//   3. Add branch / jump cases inside EXECUTE
//   4. Add MUL / CRC / LUI / AUIPC / system no-op cases inside EXECUTE

`include "pkg/rvbl2_defines.vh"

module control_unit (
    input  wire        clk_i,
    input  wire        rst_i,
    // TODO: opcode/funct3/funct7 inputs from IR, branch_taken from
    // branch_comparator, and every output signal listed in
    // HANDOFF_control_unit.md section 3 (we_o, oe_o, bw_o, address_o,
    // op_size_o, alu_op, mult_op, crc_op, pc_write, pc_src, ir_write,
    // reg_write, result_src, alu_src_a, alu_src_b, imm_sel, mult_en,
    // crc_en) go here as the module is built out.
    input  wire        placeholder_i
);

    // TODO: state register, next-state logic, output logic.
    // See HANDOFF_control_unit.md section 4 for the per-state signal
    // table this module implements.

endmodule
