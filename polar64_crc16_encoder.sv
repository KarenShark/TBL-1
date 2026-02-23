// polar64_crc16_encoder.sv
// ------------------------------------------------------------
// Polar (64,40) encoder with embedded CRC-16-CCITT.
//
// Interface + timing (handout):
// - start: 1-cycle pulse
// - done : MUST pulse exactly 2 cycles after start is sampled
// - codeword[63:0] is the encoded block
// ------------------------------------------------------------

`timescale 1ns/1ps

module polar64_crc16_encoder (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        start,
  input  logic [23:0] data_in,
  output logic        done,
  output logic [63:0] codeword
);

  import polar_common_pkg::*;

  logic        busy;
  logic [1:0]  cnt;          // countdown to done (2 -> 1 -> done)
  logic [63:0] codeword_reg;

  assign codeword = codeword_reg;

  // Compute the codeword for a given payload (pure combinational helper)
  function automatic logic [63:0] encode_word(input logic [23:0] din);
    logic [15:0] crc;
    logic [63:0] u;
    begin
      crc = crc16_ccitt24(din);
      u   = build_u(din, crc);
      return polar_transform64(u);
    end
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      done         <= 1'b0;
      busy         <= 1'b0;
      cnt          <= '0;
      codeword_reg <= '0;
    end else begin
      done <= 1'b0; // default: pulse only

      // accept start only if not busy
      if (start && !busy) begin
        busy         <= 1'b1;
        cnt          <= 2;                 // done after exactly 2 cycles
        codeword_reg <= encode_word(data_in);
      end else if (busy) begin
        // countdown
        if (cnt != 0) cnt <= cnt - 1;

        // when cnt == 1 at the beginning of this cycle => this is start+2 cycle
        if (cnt == 1) begin
          done <= 1'b1;
          busy <= 1'b0;
        end
      end
    end
  end

endmodule