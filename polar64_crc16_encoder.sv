// polar64_crc16_encoder.sv - $unit defs for tb_basic + encoder module
`timescale 1ns/1ps

import crc_pkg::*;

parameter int unsigned K_INFO = 40;
parameter int unsigned K_DATA = 24;
parameter int unsigned K_CRC  = 16;
parameter int unsigned K_FRZ  = 24;

parameter int unsigned INFO_POS [0:39] = '{
  13,14,15,19,21,22,23,25,26,27,
  28,29,30,31,35,37,38,39,41,42,
  43,44,45,46,47,49,50,51,52,53,
  54,55,56,57,58,59,60,61,62,63
};

parameter int unsigned FROZEN_POS [0:23] = '{
  0,1,2,3,4,5,6,7,8,9,10,11,
  12,16,17,18,20,24,32,33,34,36,40,48
};

function automatic logic [15:0] crc16_ccitt24(input logic [23:0] din);
  return crc_pkg::crc16_ccitt24(din);
endfunction

function automatic logic [63:0] build_u(input logic [23:0] din, input logic [15:0] crc);
  logic [63:0] u;
  int k;
  u = '0;
  for (k = 0; k < K_DATA; k++) u[INFO_POS[k]] = din[23-k];
  for (k = 0; k < K_CRC; k++) u[INFO_POS[K_DATA + k]] = crc[15-k];
  return u;
endfunction

function automatic logic [63:0] polar_transform64(input logic [63:0] u);
  logic [63:0] v;
  int s, i, j, step, half;
  v = u;
  for (s = 0; s <= 5; s++) begin
    step = 1 << (s + 1);
    half = 1 << s;
    for (i = 0; i < 64; i += step)
      for (j = 0; j < half; j++)
        v[i+j] = v[i+j] ^ v[i+j+half];
  end
  return v;
endfunction

function automatic int pos_tables_ok();
  bit [63:0] seen;
  int k;
  seen = 64'b0;
  for (k = 0; k < K_INFO; k++) begin
    if (INFO_POS[k] > 63 || seen[INFO_POS[k]]) return 0;
    seen[INFO_POS[k]] = 1;
  end
  for (k = 0; k < K_FRZ; k++) begin
    if (FROZEN_POS[k] > 63 || seen[FROZEN_POS[k]]) return 0;
    seen[FROZEN_POS[k]] = 1;
  end
  return (seen == 64'hFFFFFFFF_FFFFFFFF);
endfunction

function automatic int min_info_row_weight();
  int k, min_w, w, p, i;
  min_w = 64;
  for (k = 0; k < K_INFO; k++) begin
    p = 0;
    for (i = 0; i < 6; i++) if (INFO_POS[k][i]) p++;
    w = 1 << p;
    if (w < min_w) min_w = w;
  end
  return min_w;
endfunction

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
