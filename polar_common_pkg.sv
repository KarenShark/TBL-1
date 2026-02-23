// polar_common_pkg.sv
// ------------------------------------------------------------
// Shared helpers used by tb_basic.sv (reference model) and by
// our encoder/decoder implementation.
//
// IMPORTANT:
// - tb_basic.sv does: `import polar_common_pkg::*;`
// - It calls: crc16_ccitt24(), build_u(), polar_transform64()
//
// So we provide exactly those names + the position maps.
//
// Spec references: handout Section 6.3 (polar transform) and
// Section 7 (CRC-16-CCITT) and Section 8.2 (bit extraction).
// ------------------------------------------------------------

package polar_common_pkg;

  // --------------------------------------------------------------------------
  // 1) INFO_POS / FROZEN_POS
  //
  // K = 40 information bits = 24 data + 16 CRC
  // N = 64 codeword bits
  // frozen = 64 - 40 = 24 bits
  //
  // This mapping is a DESIGN CHOICE (handout asks teams to design it).
  // But: once chosen, encoder/decoder/testbench reference MUST match.
  //
  // Here we choose indices with Hamming weight >= 3 as information positions
  // (exclude 7 and 11 to make exactly 40).
  // That ensures min row-weight >= 8 -> dmin >= 8 (good for correcting 3 flips).
  // --------------------------------------------------------------------------

  localparam int unsigned K_INFO = 40;
  localparam int unsigned K_DATA = 24;
  localparam int unsigned K_CRC  = 16;
  localparam int unsigned K_FRZ  = 24;

  // 40 information positions (first 24 carry data, next 16 carry CRC)
  localparam int unsigned INFO_POS [0:K_INFO-1] = '{
    // weight>=3 positions, ascending, excluding 7 and 11
    13,14,15,19,21,22,23,25,26,27,
    28,29,30,31,35,37,38,39,41,42,
    43,44,45,46,47,49,50,51,52,53,
    54,55,56,57,58,59,60,61,62,63
  };

  // 24 frozen positions: all remaining indices not in INFO_POS
  localparam int unsigned FROZEN_POS [0:K_FRZ-1] = '{
    0,1,2,3,4,5,6,7,8,9,10,11,
    12,16,17,18,20,24,32,33,34,36,40,48
  };

  // --------------------------------------------------------------------------
  // 2) CRC-16-CCITT for 24-bit payload
  //
  // Handout CRC conventions:
  // - init remainder = 16'h0000
  // - bit order = MSB-first (din[23] down to din[0])
  // - no reflection
  // - xorout = 0
  // - feedback polynomial constant = 16'h1021
  //
  // Reference bit-serial algorithm (handout):
  // crc = 0
  // for i=23 downto 0:
  //   feedback = data_in[i] XOR crc[15]
  //   crc = (crc << 1) & 0xFFFF
  //   if feedback: crc ^= 0x1021
  // --------------------------------------------------------------------------

  function automatic logic [15:0] crc16_ccitt24(input logic [23:0] din);
    logic [15:0] crc;
    logic        feedback;
    int          i;
    begin
      crc = 16'h0000;
      for (i = 23; i >= 0; i--) begin
        feedback = din[i] ^ crc[15];
        crc      = {crc[14:0], 1'b0};
        if (feedback) crc ^= 16'h1021;
      end
      return crc;
    end
  endfunction

  // --------------------------------------------------------------------------
  // 3) Build u[63:0] given data + crc
  //
  // Handout mapping rules:
  // - data bits are mapped by INFO_POS[0..23]
  //   data_out[23-k] = u_hat[INFO_POS[k]]  (decoder rule)
  // So in encoder we do:
  //   u[INFO_POS[k]] = data_in[23-k]
  //
  // - crc bits mapped by INFO_POS[24..39]
  //   crc_rx[15-k] = u_hat[INFO_POS[24+k]]
  // So in encoder:
  //   u[INFO_POS[24+k]] = crc[15-k]
  //
  // Frozen bits are 0.
  // --------------------------------------------------------------------------

  function automatic logic [63:0] build_u(
    input logic [23:0] din,
    input logic [15:0] crc
  );
    logic [63:0] u;
    int k;
    begin
      u = '0;

      // data bits (MSB-first into INFO_POS[0..23])
      for (k = 0; k < K_DATA; k++) begin
        u[INFO_POS[k]] = din[23-k];
      end

      // crc bits (MSB-first into INFO_POS[24..39])
      for (k = 0; k < K_CRC; k++) begin
        u[INFO_POS[K_DATA + k]] = crc[15-k];
      end

      // frozen bits already 0 by initialization
      return u;
    end
  endfunction

  // --------------------------------------------------------------------------
  // 4) Polar transform (N=64), NO bit-reversal permutation
  //
  // Handout algorithm:
  // v = u
  // for s = 0..5:
  //   step = 2^(s+1), half = 2^s
  //   for i in 0..63 step step:
  //     for j in 0..half-1:
  //       v[i+j] = v[i+j] XOR v[i+j+half]
  // codeword = v
  //
  // This transform is self-inverse over GF(2), so we can also use it
  // as "inverse" to recover u_hat from a candidate codeword.
  // --------------------------------------------------------------------------

  function automatic logic [63:0] polar_transform64(input logic [63:0] u);
    logic [63:0] v;
    int s, i, j;
    int step, half;
    begin
      v = u;

      for (s = 0; s <= 5; s++) begin
        step = 1 << (s + 1);
        half = 1 << s;

        for (i = 0; i < 64; i += step) begin
          for (j = 0; j < half; j++) begin
            v[i+j] = v[i+j] ^ v[i+j+half];
          end
        end
      end

      return v;
    end
  endfunction

  // --------------------------------------------------------------------------
  // 5) pos_tables_ok / min_info_row_weight (tb_basic validation)
  //
  // pos_tables_ok: INFO_POS + FROZEN_POS cover 0..63, no dup, no overlap
  // min_info_row_weight: min over INFO_POS of 2^popcount(i); target >= 8
  // --------------------------------------------------------------------------

  function automatic int pos_tables_ok();
    bit [63:0] seen;
    int k;
    begin
      seen = 64'b0;
      for (k = 0; k < K_INFO; k++) begin
        if (INFO_POS[k] > 63) return 0;
        if (seen[INFO_POS[k]]) return 0;
        seen[INFO_POS[k]] = 1;
      end
      for (k = 0; k < K_FRZ; k++) begin
        if (FROZEN_POS[k] > 63) return 0;
        if (seen[FROZEN_POS[k]]) return 0;
        seen[FROZEN_POS[k]] = 1;
      end
      if (seen != 64'hFFFFFFFF_FFFFFFFF) return 0;
      return 1;
    end
  endfunction

  function automatic int min_info_row_weight();
    int k, min_w, w, p, i;
    begin
      min_w = 64;
      for (k = 0; k < K_INFO; k++) begin
        p = 0;
        for (i = 0; i < 6; i++) begin
          if (INFO_POS[k][i]) p++;
        end
        w = 1 << p;
        if (w < min_w) min_w = w;
      end
      return min_w;
    end
  endfunction

endpackage