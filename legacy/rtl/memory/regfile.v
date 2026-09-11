// regfile.v — 32 GPRs, x0 hardwired zero, async read / sync write

module regfile (
    input  wire        clk_i,
    input  wire        rst_i,

    input  wire [4:0]  rs1_addr_i,
    input  wire [4:0]  rs2_addr_i,
    input  wire [4:0]  rd_addr_i,
    input  wire [31:0] write_data_i,
    input  wire        reg_write_i,

    output wire [31:0] rs1_data_o,
    output wire [31:0] rs2_data_o
);

    reg [31:0] regs [0:31];

    integer i;

    assign rs1_data_o = (rs1_addr_i == 5'd0) ? 32'b0 : regs[rs1_addr_i];
    assign rs2_data_o = (rs2_addr_i == 5'd0) ? 32'b0 : regs[rs2_addr_i];

    // x0 write-protected
    always @(posedge clk_i) begin
        if (rst_i) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'b0;
        end else if (reg_write_i && rd_addr_i != 5'd0) begin
            regs[rd_addr_i] <= write_data_i;
        end
    end

endmodule
