`timescale 1ns/1ps
// Updated to match tbl2026.8.pdf spec (30 Jan 2026)
// Polar(64,40) + CRC-16-CCITT, non-contiguous INFO/FROZEN positions, no bit-reversal.
//
// NOTE for TBL:
//   - Each team is expected to DESIGN the INFO_POS[] and FROZEN_POS[] sets.
//   - Encoder/decoder/testbenches import this package so your position design is
//     centralized and consistent across the project.
//   - Requirements for a *valid* design:
//       (a) INFO_POS and FROZEN_POS are disjoint,
//       (b) INFO_POS has 40 unique indices, FROZEN_POS has 24 unique indices,
//       (c) Together they cover all positions 0..63 exactly once.
//   - Distance note: With dmin = 8, bounded-distance decoding with radius 3
//     guarantees correction of 1-3 flips and rejection of any 4-flip pattern.

package polar_common_pkg;

  // ---------------------------------------------------------------------------
  // Design Parameters & Position Tables
  // ---------------------------------------------------------------------------
  localparam int unsigned N      = 64;
  localparam int unsigned K_INFO = 40;
  localparam int unsigned K_DATA = 24;
  localparam int unsigned K_CRC  = 16;
  localparam int unsigned N_FROZEN = 24;

  // INFO_POS: 40 indices
  localparam int unsigned INFO_POS [0:39] = '{
    13,14,15,19,21,22,23,25,26,27,
    28,29,30,31,35,37,38,39,41,42,
    43,44,45,46,47,49,50,51,52,53,
    54,55,56,57,58,59,60,61,62,63
  };

  // FROZEN_POS: 24 indices
  localparam int unsigned FROZEN_POS [0:23] = '{
    0,1,2,3,4,5,6,7,8,9,10,11,
    12,16,17,18,20,24,32,33,34,36,40,48
  };

  function automatic logic [15:0] crc16_ccitt24(input logic [K_DATA-1:0] data);
    logic [15:0] crc;
    logic fb;
    int i;
    begin
      crc = 16'h0000;
      for (i = K_DATA-1; i >= 0; i--) begin
        fb  = data[i] ^ crc[15];
        crc = {crc[14:0], 1'b0};
        if (fb) crc ^= 16'h1021;
      end
      return crc;
    end
  endfunction

  function automatic logic [N-1:0] build_u(
    input logic [K_DATA-1:0] data,
    input logic [K_CRC-1:0]  crc
  );
    logic [N-1:0] u;
    int k;
    begin
      u = '0;

      // Place data bits (MSB-first)
      for (k = 0; k < K_DATA; k++) begin
        u[INFO_POS[k]] = data[K_DATA-1-k];
      end

      // Place CRC bits (MSB-first)
      for (k = 0; k < K_CRC; k++) begin
        u[INFO_POS[K_DATA + k]] = crc[K_CRC-1-k];
      end

      // Enforce frozen bits to 0 (even if a team accidentally overlaps sets)
      for (k = 0; k < N_FROZEN; k++) begin
        u[FROZEN_POS[k]] = 1'b0;
      end

      return u;
    end
  endfunction

 function automatic logic [N-1:0] polar_transform64(input logic [N-1:0] u_in);
    logic [N-1:0] v;
    int s, i, j;
    int step, half;
    begin
      v = u_in;
      for (s = 0; s < 6; s++) begin
        step = 1 << (s + 1);
        half = 1 << s;
        for (i = 0; i < N; i += step) begin
          for (j = 0; j < half; j++) begin
            v[i + j] = v[i + j] ^ v[i + j + half];
          end
        end
      end
      return v;
    end
  endfunction

  function automatic logic pos_tables_ok();
    logic [N-1:0] seen;
    int unsigned k;
    begin
      seen = '0;

      // INFO positions
      for (k = 0; k < K_INFO; k++) begin
        if (INFO_POS[k] >= N) return 1'b0;
        if (seen[INFO_POS[k]]) return 1'b0;
        seen[INFO_POS[k]] = 1'b1;
      end

      // FROZEN positions
      for (k = 0; k < N_FROZEN; k++) begin
        if (FROZEN_POS[k] >= N) return 1'b0;
        if (seen[FROZEN_POS[k]]) return 1'b0; // overlap or duplicate
        seen[FROZEN_POS[k]] = 1'b1;
      end

      // Must cover all bits exactly once
      return (seen == '1);
    end
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

endpackage
