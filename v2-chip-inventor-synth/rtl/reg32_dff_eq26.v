module reg32_dff_eq26 #(
    parameter RESET_VALUE = 32'h00000000
) (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        en_i,       // Enable: 1 = load d_i, 0 = hold current value
    input  wire [31:0] d_i,        // Data input (D)
    output reg  [31:0] q_o         // Data output (Q)
);

    always @(posedge clk_i) begin
        if (rst_i) begin
            q_o <= RESET_VALUE;
        end else if (en_i) begin
            q_o <= d_i;
        end
    end

endmodule
/* With a D Flip-Flop:
 Cycle 4: LSU outputs 0x00000042.
          At the clock edge, the Flip-Flop SNAPS A PHOTO 📸 and freezes 0x00000042.
 Cycle 5: Even though the LSU input changes, the Flip-Flop holds the frozen photo!
          RegFile safely writes 0x00000042 into rd! 🎉
Summary:
A Wire changes instantaneously (0 delay).
A D Flip-Flop acts as a 1-cycle memory buffer (takes a snapshot at the clock edge and holds it stable for the next cycle). */