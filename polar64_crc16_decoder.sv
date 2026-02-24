// polar64_crc16_decoder.sv
// ------------------------------------------------------------
// Bounded-distance decoder (radius=3) + CRC fail-safe.
//
// Spec highlights (handout):
// - If exists UNIQUE polar-valid codeword within Hamming distance <= 3:
//     valid=1, output corresponding data_out
//   else valid=0
// - CRC is additional integrity check: if CRC fails, valid must be 0
// - done must assert within 12 cycles after start
// ------------------------------------------------------------

`timescale 1ns/1ps

import polar_common_pkg::*;

module polar64_crc16_decoder (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        start,
  input  logic [63:0] rx,
  output logic        done,
  output logic [23:0] data_out,
  output logic        valid
);

  // decode result struct: ok=valid, data=24-bit payload
  typedef struct packed {
    logic        ok;
    logic [23:0] data;
  } dec_result_t;

  logic        busy;
  logic [1:0]  cnt;
  logic [23:0] data_reg;
  logic        valid_reg;
  dec_result_t r_comb;       // combinational decode of current rx

  assign data_out = data_reg;
  assign valid    = valid_reg;

  // Check if a 64-bit candidate is a valid codeword under:
  // 1) frozen bits are all 0 in u_hat
  // 2) embedded CRC matches recomputed CRC(data)
  function automatic dec_result_t check_candidate(input logic [63:0] cand_cw);
    dec_result_t r;
    logic [63:0] u_hat;
    logic [23:0] dout;
    logic [15:0] crc_rx, crc_calc;
    int k;
    begin
      r.ok   = 1'b0;
      r.data = '0;

      // Because the polar transform here is self-inverse over GF(2),
      // we can recover u_hat by applying the same transform again.
      u_hat = polar_transform64(cand_cw);

      // Frozen-bit constraint: all frozen positions must be 0
      for (k = 0; k < N_FROZEN; k++) begin
        if (u_hat[FROZEN_POS[k]] != 1'b0) begin
          return r; // fail fast
        end
      end

      // Extract data bits (MSB-first) following the handout decoder rule
      for (k = 0; k < K_DATA; k++) begin
        dout[23-k] = u_hat[INFO_POS[k]];
      end

      // Extract CRC bits (MSB-first)
      for (k = 0; k < K_CRC; k++) begin
        crc_rx[15-k] = u_hat[INFO_POS[K_DATA + k]];
      end

      // Recompute CRC and compare
      crc_calc = crc16_ccitt24(dout);
      if (crc_calc != crc_rx) begin
        return r; // CRC fail => invalid
      end

      // Passed all checks
      r.ok   = 1'b1;
      r.data = dout;
      return r;
    end
  endfunction

  // Bounded-distance decoding radius=3:
  // search all masks with weight 0..3 and check_candidate(rx ^ mask).
  // Unique hit => ok.
  function automatic dec_result_t decode_bd3(input logic [63:0] rx_in);
    dec_result_t hit, tmp, out;
    int found;
    int i, j, k;
    logic [63:0] mask;
    begin
      found    = 0;
      out.ok   = 1'b0;
      out.data = '0;

      // weight 0
      tmp = check_candidate(rx_in);
      if (tmp.ok) begin
        found = 1;
        hit   = tmp;
      end

      // weight 1
      for (i = 0; i < 64 && found <= 1; i++) begin
        mask = (64'h1 << i);
        tmp  = check_candidate(rx_in ^ mask);
        if (tmp.ok) begin
          found++;
          hit = tmp;
        end
      end

      // weight 2
      for (i = 0; i < 64 && found <= 1; i++) begin
        for (j = i+1; j < 64 && found <= 1; j++) begin
          mask = (64'h1 << i) ^ (64'h1 << j);
          tmp  = check_candidate(rx_in ^ mask);
          if (tmp.ok) begin
            found++;
            hit = tmp;
          end
        end
      end

      // weight 3
      for (i = 0; i < 64 && found <= 1; i++) begin
        for (j = i+1; j < 64 && found <= 1; j++) begin
          for (k = j+1; k < 64 && found <= 1; k++) begin
            mask = (64'h1 << i) ^ (64'h1 << j) ^ (64'h1 << k);
            tmp  = check_candidate(rx_in ^ mask);
            if (tmp.ok) begin
              found++;
              hit = tmp;
            end
          end
        end
      end

      // Unique solution?
      if (found == 1) begin
        out = hit;
      end else begin
        out.ok   = 1'b0;
        out.data = '0;
      end

      return out;
    end
  endfunction

  // continuously compute decode; sampled into FFs when start fires
  always_comb r_comb = decode_bd3(rx);

  // done pulses exactly at start+2 cycles (satisfies <=12 requirement)
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      done      <= 1'b0;
      busy      <= 1'b0;
      cnt       <= '0;
      data_reg  <= '0;
      valid_reg <= 1'b0;
    end else begin
      done <= 1'b0;

      if (start && !busy) begin
        data_reg  <= r_comb.data;
        valid_reg <= r_comb.ok;
        busy      <= 1'b1;
        cnt       <= 2;
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
