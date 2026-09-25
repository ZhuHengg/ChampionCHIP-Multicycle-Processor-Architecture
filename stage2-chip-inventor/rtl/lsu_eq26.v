// Load/store alignment unit.
module lsu_eq26(
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

    // Load path.
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

    // Store path.
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