// SIMULATION STUB of the AWS HDK sh_ddr block (never upload). top.sv leaves
// DDR disabled (EN_DDR = 0), so the stub only has to accept the connections.
module sh_ddr #(parameter DDR_PRESENT = 0) (
    input wire clk, rst_n, stat_clk, stat_rst_n, CLK_DIMM_DP, CLK_DIMM_DN,
    output wire M_ACT_N, M_PAR, M_CKE, M_ODT, M_CS_N, M_CLK_DN, M_CLK_DP, cl_RST_DIMM_N,
    output wire [16:0] M_MA,
    output wire [1:0] M_BA, M_BG,
    inout wire [63:0] M_DQ,
    inout wire [7:0] M_ECC,
    inout wire [17:0] M_DQS_DP, M_DQS_DN,
    input wire cl_sh_ddr_axi_awid, cl_sh_ddr_axi_awaddr, cl_sh_ddr_axi_awlen,
    input wire cl_sh_ddr_axi_awsize, cl_sh_ddr_axi_awvalid, cl_sh_ddr_axi_awburst,
    input wire cl_sh_ddr_axi_awuser, cl_sh_ddr_axi_awready, cl_sh_ddr_axi_wdata,
    input wire cl_sh_ddr_axi_wstrb, cl_sh_ddr_axi_wlast, cl_sh_ddr_axi_wvalid,
    input wire cl_sh_ddr_axi_wready, cl_sh_ddr_axi_bid, cl_sh_ddr_axi_bresp,
    input wire cl_sh_ddr_axi_bvalid, cl_sh_ddr_axi_bready, cl_sh_ddr_axi_arid,
    input wire cl_sh_ddr_axi_araddr, cl_sh_ddr_axi_arlen, cl_sh_ddr_axi_arsize,
    input wire cl_sh_ddr_axi_arvalid, cl_sh_ddr_axi_arburst, cl_sh_ddr_axi_aruser,
    input wire cl_sh_ddr_axi_arready, cl_sh_ddr_axi_rid, cl_sh_ddr_axi_rdata,
    input wire cl_sh_ddr_axi_rresp, cl_sh_ddr_axi_rlast, cl_sh_ddr_axi_rvalid,
    input wire cl_sh_ddr_axi_rready, sh_ddr_stat_bus_addr, sh_ddr_stat_bus_wdata,
    input wire sh_ddr_stat_bus_wr, sh_ddr_stat_bus_rd, sh_ddr_stat_bus_ack,
    input wire sh_ddr_stat_bus_rdata, ddr_sh_stat_int, sh_cl_ddr_is_ready
);
endmodule
