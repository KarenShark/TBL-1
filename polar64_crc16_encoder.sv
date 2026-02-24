// polar64_crc16_encoder.sv - $unit defs for tb_basic + encoder module
`timescale 1ns/1ps

import polar_common_pkg::*;

module polar64_crc16_encoder (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        start,
  input  logic [23:0] data_in,
  output logic        done,
  output logic [63:0] codeword
);

  logic        busy;
  logic [1:0]  cnt;
  logic [63:0] codeword_reg;

  assign codeword = codeword_reg;

  function automatic logic [63:0] encode_word(input logic [23:0] din);
    logic [15:0] crc;
    logic [63:0] u;
    crc = crc16_ccitt24(din);
    u   = build_u(din, crc);
    return polar_transform64(u);
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      done         <= 1'b0;
      busy         <= 1'b0;
      cnt          <= '0;
      codeword_reg <= '0;
    end else begin
      done <= 1'b0;
      if (start && !busy) begin
        busy         <= 1'b1;
        cnt          <= 2;
        codeword_reg <= encode_word(data_in);
      end else if (busy) begin
        if (cnt != 0) cnt <= cnt - 1;
        if (cnt == 1) begin
          done <= 1'b1;
          busy <= 1'b0;
        end
      end
    end
  end

endmodule
