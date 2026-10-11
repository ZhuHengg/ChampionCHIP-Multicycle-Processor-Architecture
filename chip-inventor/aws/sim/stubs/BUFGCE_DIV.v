// SIMULATION MODEL of the Xilinx UltraScale+ BUFGCE_DIV primitive (never
// upload: Vivado supplies the real cell). Behavioural only: O rises on the
// I edge that starts each divide period and is high for ceil(N/2) I cycles,
// like the real buffer's odd-divide duty cycle. CE and CLR are tied off by
// riscv.sv, so the model ignores them.
module BUFGCE_DIV #(parameter integer BUFGCE_DIVIDE = 1) (
    input  wire I,
    input  wire CE,
    input  wire CLR,
    output reg  O
);
    integer count = 0;
    initial O = 1'b0;
    always @(posedge I) begin
        count = (count == BUFGCE_DIVIDE - 1) ? 0 : count + 1;
        O = (count < (BUFGCE_DIVIDE + 1) / 2);
    end
    always @(negedge I) if (BUFGCE_DIVIDE == 1) O = 1'b0;
endmodule
