// lsu.v
// Guide §3.3. Combinational — sits between core and memory, handles
// byte/half/word selection + extension on loads, and positioning on
// stores.
//
// PORT NAMING (guide Figure 2, §3.3.3): names are from the CORE's
// perspective, so core_data_o / core_address_o / op_size_o are LSU
// INPUTS (they are the core's outputs). mem_data_i is also named from
// the core's naming convention carried into this module per
// MEMORY_BUILD_PLAN.md's port table (it's the LSU's read of the memory
// word, an LSU input). Matches Figure 2 exactly; directions commented
// per-port below since this is the easiest place in the project to wire
// backwards.
//
// bw_o is NOT generated here. The control unit already computes it
// (handoff decision #11, control_unit.v bw_lookup) from op_size + the
// low address bits. This module only positions data; if this were to
// grow byte-mask logic, that would duplicate the control unit's job.
//
// ============================================================================
// RESOLVED (was flagged for user decision; confirmed — reading (a) below is
// correct, and this implementation is right as written). Guide §3.3.1's
// repositioning paragraph illustrates BYTE SELECTION, not sign extension:
// it never names an instruction, sign extension already had its own worked
// examples earlier in the same section, the guide's explicit general rule
// for lb/lh contradicts the literal reading, and RISC-V settles it
// independently (lb sign-extends, unconditionally — a core returning
// 0x000000F3 for lb would fail the validation firmware). 0x000000F3 is the
// lbu result at that address. MEMORY_BUILD_PLAN.md has been corrected; its
// vector table previously repeated the guide's figure uncritically.
//
// Original analysis kept below — the reasoning is what justifies the call.
// ----------------------------------------------------------------------
// FLAG — Table 12 / guide §3.3.1 apparent inconsistency (do not silently
// resolve, per CLAUDE.md step 1/9 and MEMORY_BUILD_PLAN.md instruction):
//
// Guide §3.3.1 states plainly for lb/lh: "fill the rest of the register
// bits with the signal bit (MSB) value of the read value (signal
// extension)". Applied uniformly, lb at 0x10010002 (byte = 0xF3, MSB=1)
// should sign-extend to 0xFFFFFFF3.
//
// But guide's own worked text for repositioning says: "when reading the
// 0x10010002 address, only the 0xF3 byte ... will be placed in the
// register (which should then have the value 0x000000F3)" — i.e. NOT
// sign-extended, contradicting the general lb rule stated two paragraphs
// earlier in the same section. MEMORY_BUILD_PLAN.md's Table-12-vector
// list repeats this same value (0x000000F3) as a load golden vector.
//
// These two statements cannot both be literal en clair: either (a) the
// repositioning example is illustrating BYTE SELECTION only, independent
// of which load instruction (lb vs lbu) is used, and the guide simply
// didn't bother re-stating "for lbu" on that example — or (b) it's a
// genuine error in the guide's worked example, and a real lb at that
// address should read 0xFFFFFFF3 per the general rule.
//
// RESOLUTION TAKEN: implemented per the general rule in §3.3.1 (lb always
// sign-extends off the selected byte's MSB, regardless of which byte
// lane was selected) — this is the only internally-consistent reading of
// the *stated rule*, versus the *specific worked example* which never
// says outright which instruction (lb or lbu) produced 0x000000F3. Since
// the example prose only says "the 0xF3 byte ... will be placed in the
// register" without naming lb explicitly at that point, reading it as an
// lbu-style byte-select illustration (not a full lb load) resolves the
// conflict without contradicting the explicit signed-extension rule.
//
// Do not "fix" this by special-casing byte-lane 2 to skip sign extension;
// that would encode the contradiction instead of resolving it. lbu at the
// same address (0x000000F3) is unambiguous and is the better regression
// test — it passes under either reading.
// ============================================================================

module lsu (
    input  wire [31:0] core_data_o,     // INPUT: store data from core (rs2)
    input  wire [31:0] core_address_o,  // INPUT: effective address from core (uses [1:0])
    input  wire [2:0]  op_size_o,       // INPUT: from control unit
    input  wire [31:0] mem_data_o,      // INPUT: word read back from memory

    output reg  [31:0] core_data_i,     // OUTPUT: load result, extended, back to core
    output reg  [31:0] mem_data_i       // OUTPUT: store data, positioned, out to memory
);

    // Operation Size Encodings (from guide / handoff)
    localparam [2:0] OP_SIZE_BYTE_S = 3'b000; // lb / sb
    localparam [2:0] OP_SIZE_BYTE_U = 3'b001; // lbu
    localparam [2:0] OP_SIZE_HALF_S = 3'b010; // lh / sh
    localparam [2:0] OP_SIZE_HALF_U = 3'b011; // lhu
    localparam [2:0] OP_SIZE_WORD   = 3'b100; // lw / sw

    wire [1:0] byte_sel = core_address_o[1:0];

    // -----------------------------------------------------------------
    // Load path: select the addressed lane out of mem_data_o, extend.
    // -----------------------------------------------------------------
    reg [7:0]  load_byte;
    reg [15:0] load_half;

    always @(*) begin
        load_byte = 8'b0;
        case (byte_sel)
            2'b00:   load_byte = mem_data_o[ 7: 0];
            2'b01:   load_byte = mem_data_o[15: 8];
            2'b10:   load_byte = mem_data_o[23:16];
            2'b11:   load_byte = mem_data_o[31:24];
            default: load_byte = mem_data_o[7:0];
        endcase
    end

    always @(*) begin
        load_half = 16'b0;
        case (byte_sel[1])
            1'b0:    load_half = mem_data_o[15: 0];
            1'b1:    load_half = mem_data_o[31:16];
            default: load_half = mem_data_o[15:0];
        endcase
    end

    always @(*) begin
        core_data_i = 32'b0; // default
        case (op_size_o)
            OP_SIZE_BYTE_S: core_data_i = {{24{load_byte[7]}}, load_byte};
            OP_SIZE_BYTE_U: core_data_i = {24'b0, load_byte};
            OP_SIZE_HALF_S: core_data_i = {{16{load_half[15]}}, load_half};
            OP_SIZE_HALF_U: core_data_i = {16'b0, load_half};
            OP_SIZE_WORD:   core_data_i = mem_data_o;
            default:         core_data_i = mem_data_o;
        endcase
    end

    // -----------------------------------------------------------------
    // Store path: position core_data_o's low bits into the addressed
    // lane. bw_o (which lane(s) actually get written) comes from the
    // control unit, not here — this only shifts the data into place.
    // Guide §3.3.2 example: writing 0x12 to 0x10010002 -> 0x00120000.
    // -----------------------------------------------------------------
    always @(*) begin
        mem_data_i = 32'b0; // default
        case (op_size_o[2:1]) // size bits only; sign bit don't-care for stores
            2'b00: begin // byte
                case (byte_sel)
                    2'b00:   mem_data_i = {24'b0, core_data_o[7:0]};
                    2'b01:   mem_data_i = {16'b0, core_data_o[7:0], 8'b0};
                    2'b10:   mem_data_i = {8'b0, core_data_o[7:0], 16'b0};
                    2'b11:   mem_data_i = {core_data_o[7:0], 24'b0};
                    default: mem_data_i = {24'b0, core_data_o[7:0]};
                endcase
            end
            2'b01: begin // half
                mem_data_i = byte_sel[1] ? {core_data_o[15:0], 16'b0}
                                          : {16'b0, core_data_o[15:0]};
            end
            2'b10: mem_data_i = core_data_o; // word
            default: mem_data_i = core_data_o;
        endcase
    end

endmodule
