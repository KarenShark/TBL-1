`timescale 1ns/1ps

// tb_extra.sv
// ------------------------------------------------------------
// Stronger student TB for local regression (hidden-style).
// Adds:
//  - Randomized regression over many din values
//  - Random bit flips with weights 0..4
//  - Stress start behavior (held-high / start while busy)
//  - Reset mid-transaction
//  - (Best-effort) ambiguity test: if 2+ solutions within radius 3 => valid must be 0
//
// NOTE: This TB is for YOU to validate robustness. Grader uses tb_hidden.
// ------------------------------------------------------------

module tb_extra;

  import polar_common_pkg::*;

  // Clock/reset
  logic clk;
  logic rst_n;

  // Encoder DUT ports
  logic        enc_start, enc_done;
  logic [23:0] data_in;
  logic [63:0] codeword;

  // Decoder DUT ports
  logic        dec_start, dec_done;
  logic [63:0] rx;
  logic [23:0] data_out;
  logic        valid;

  // 100 MHz clock
  initial clk = 1'b0;
  always #5 clk = ~clk;

  polar64_crc16_encoder u_enc (
    .clk(clk), .rst_n(rst_n),
    .start(enc_start), .data_in(data_in),
    .done(enc_done), .codeword(codeword)
  );

  polar64_crc16_decoder u_dec (
    .clk(clk), .rst_n(rst_n),
    .start(dec_start), .rx(rx),
    .done(dec_done), .data_out(data_out), .valid(valid)
  );

  // -------------------------
  // Helpers (similar style to tb_basic)
  // -------------------------

  task automatic pulse_start(ref logic s);
    begin
      @(negedge clk);
      s = 1'b1;
      @(negedge clk);
      s = 1'b0;
    end
  endtask

  // hold start high for N extra negedges after raising it (stress)
  task automatic hold_start(ref logic s, input int unsigned extra_cycles);
    begin
      @(negedge clk);
      s = 1'b1;
      repeat (extra_cycles) @(negedge clk);
      s = 1'b0;
    end
  endtask

  function automatic logic [63:0] ref_encode(input logic [23:0] din);
    logic [15:0] crc;
    logic [63:0] u;
    begin
      crc = crc16_ccitt24(din);
      u   = build_u(din, crc);
      return polar_transform64(u);
    end
  endfunction

  // Single-bit mask
  function automatic logic [63:0] bit_mask(input int unsigned b);
    logic [63:0] m;
    begin
      m = 64'b0;
      m[b] = 1'b1;
      return m;
    end
  endfunction

  // popcount64
  function automatic int unsigned popcount64(input logic [63:0] x);
    int unsigned c;
    begin
      c = 0;
      for (int i=0; i<64; i++) if (x[i]) c++;
      return c;
    end
  endfunction

  // random mask of exact weight w
  function automatic logic [63:0] rand_mask_weight(input int unsigned w, inout int unsigned seed);
    logic [63:0] m;
    int unsigned cnt;
    int unsigned idx;
    begin
      m   = 64'b0;
      cnt = 0;
      while (cnt < w) begin
        idx = $urandom(seed) % 64;
        if (!m[idx]) begin
          m[idx] = 1'b1;
          cnt++;
        end
      end
      return m;
    end
  endfunction

  // Encode transaction + strict latency check (done exactly 2 cycles after start sampled)
  task automatic do_encode_strict(
    input  logic [23:0] din,
    output logic [63:0] cw,
    output logic        timing_ok
  );
    begin
      timing_ok = 1'b1;
      data_in   = din;
      pulse_start(enc_start);

      // +1 cycle: done must still be 0
      @(posedge clk); @(negedge clk);
      if (enc_done) timing_ok = 1'b0;

      // +2 cycles: done must be 1
      @(posedge clk); @(negedge clk);
      if (!enc_done) timing_ok = 1'b0;

      cw = codeword;

      // +3 cycle: done must drop back to 0
      @(posedge clk); @(negedge clk);
      if (enc_done) timing_ok = 1'b0;
    end
  endtask

  // Decode transaction + latency check (done within 12 cycles after start)
  task automatic do_decode_bounded(
    input  logic [63:0] rx_in,
    output logic [23:0] dout,
    output logic        v,
    output int unsigned lat,
    output logic        timing_ok
  );
    begin
      timing_ok = 1'b1;
      lat       = 0;
      rx        = rx_in;
      pulse_start(dec_start);

      // Wait up to 12 cycles for done
      while (1) begin
        @(posedge clk); lat++;
        @(negedge clk);
        if (dec_done) break;
        if (lat >= 12) begin
          timing_ok = 1'b0;
          break;
        end
      end

      dout = data_out;
      v    = valid;

      // done should be a 1-cycle pulse (only check if we saw it)
      if (timing_ok) begin
        @(posedge clk); @(negedge clk);
        if (dec_done) timing_ok = 1'b0;
      end
    end
  endtask

  task automatic apply_reset();
    begin
      enc_start = 1'b0;
      dec_start = 1'b0;
      data_in   = '0;
      rx        = '0;

      rst_n = 1'b0;
      repeat (5) @(posedge clk);
      rst_n = 1'b1;
      repeat (2) @(posedge clk);
    end
  endtask

  // -------------------------
  // Assertions-like checks
  // -------------------------

  task automatic check_equal(
    input string what,
    input logic cond
  );
    begin
      if (!cond) begin
        $display("[FAIL] %s", what);
        $fatal(1);
      end
    end
  endtask

  // -------------------------
  // Main tests
  // -------------------------

  int unsigned seed = 32'h20260223;
  int unsigned N_RANDOM = 2000;   // bump up if you want (runtime grows)
  int unsigned per_w_trials = 4;  // trials per weight for each din

  initial begin
    $display("============================================================");
    $display(" tb_extra : hidden-style local regression");
    $display("============================================================");

    apply_reset();

    // Quick sanity on tables
    $display("[TB] pos_tables_ok=%0d, min_info_row_weight=%0d (target >= 8)",
             pos_tables_ok(), min_info_row_weight());

    check_equal("pos_tables_ok() must be 1", pos_tables_ok());

    // ------------------------------------------------------------
    // Test 1: Random regression (din random, 0..4 flips random masks)
    // ------------------------------------------------------------
    $display("[T1] Random regression: N=%0d, masks per weight=%0d", N_RANDOM, per_w_trials);

    for (int t=0; t<int'(N_RANDOM); t++) begin
      logic [23:0] din;
      logic [63:0] cw_ref, cw_dut;
      logic [23:0] dout;
      logic v;
      int unsigned lat;
      logic enc_timing_ok, dec_timing_ok;

      din    = $urandom(seed);
      cw_ref = ref_encode(din);

      // Encode and check matches reference + strict timing
      do_encode_strict(din, cw_dut, enc_timing_ok);
      check_equal($sformatf("[T1][ENC] timing @t=%0d", t), enc_timing_ok);
      check_equal($sformatf("[T1][ENC] codeword match @t=%0d", t), (cw_dut === cw_ref));

      // weight 0
      do_decode_bounded(cw_ref, dout, v, lat, dec_timing_ok);
      check_equal($sformatf("[T1][DEC] timing w0 @t=%0d", t), dec_timing_ok);
      check_equal($sformatf("[T1][DEC] w0 valid/data @t=%0d", t), (v===1'b1) && (dout===din));

      // weight 1..3 must correct (random masks)
      for (int w=1; w<=3; w++) begin
        for (int k=0; k<int'(per_w_trials); k++) begin
          logic [63:0] m;
          m = rand_mask_weight(w, seed);
          do_decode_bounded(cw_ref ^ m, dout, v, lat, dec_timing_ok);
          check_equal($sformatf("[T1][DEC] timing w%0d @t=%0d", w, t), dec_timing_ok);
          check_equal($sformatf("[T1][DEC] correct w%0d @t=%0d", w, t),
                      (v===1'b1) && (dout===din));
        end
      end

      // weight 4 must reject (random masks)
      for (int k=0; k<int'(per_w_trials); k++) begin
        logic [63:0] m;
        m = rand_mask_weight(4, seed);
        do_decode_bounded(cw_ref ^ m, dout, v, lat, dec_timing_ok);
        check_equal($sformatf("[T1][DEC] timing w4 @t=%0d", t), dec_timing_ok);
        check_equal($sformatf("[T1][DEC] reject w4 @t=%0d", t), (v===1'b0));
      end

      // Occasionally do a mid-transaction reset (stress)
      if ((t % 250) == 0 && t != 0) begin
        $display("[T1] mid-reset stress at t=%0d", t);
        // Start an encode, then reset quickly
        data_in = din;
        pulse_start(enc_start);
        @(posedge clk);
        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // After reset, should still work
        do_encode_strict(din, cw_dut, enc_timing_ok);
        check_equal("[T1][POST-RESET] encoder timing", enc_timing_ok);
      end
    end

    $display("[T1] PASS");

    // ------------------------------------------------------------
    // Test 2: Start behavior stress (held-high / start while busy)
    // ------------------------------------------------------------
    $display("[T2] Start stress: held-high + start while busy");

    begin
      logic [23:0] din;
      logic [63:0] cw_ref, cw_dut;
      logic enc_timing_ok;

      din    = 24'h13579B;
      cw_ref = ref_encode(din);

      data_in = din;

      // Hold start high for multiple cycles (should still only produce ONE done pulse)
      hold_start(enc_start, 3);

      // Expect strict timing still (sampled start at first posedge after negedge assertion)
      // We'll just check pulse width (1-cycle) and codeword match by waiting around.
      // Wait enough cycles to see done pulse.
      repeat (5) @(posedge clk);

      check_equal("[T2][ENC] codeword match after held start", (codeword === cw_ref));

      // done pulse should be 1 cycle; check it doesn't stay high
      if (enc_done) begin
        @(posedge clk);
        check_equal("[T2][ENC] done is 1-cycle pulse", (enc_done===1'b0));
      end

      // Now test repeated start while busy:
      apply_reset();
      data_in = din;

      // Start once
      pulse_start(enc_start);

      // Immediately spam start for a few cycles
      repeat (4) begin
        @(negedge clk);
        enc_start = 1'b1;
        @(negedge clk);
        enc_start = 1'b0;
      end

      // Count done pulses over a window
      int pulses = 0;
      repeat (12) begin
        @(posedge clk);
        if (enc_done) pulses++;
      end
      check_equal($sformatf("[T2][ENC] only 1 done pulse expected, got %0d", pulses), (pulses==1));
    end

    $display("[T2] PASS");

    // ------------------------------------------------------------
    // Test 3: Ambiguity best-effort (non-unique solution => valid must be 0)
    // ------------------------------------------------------------
    $display("[T3] Ambiguity test (best-effort search)");

    begin
      typedef struct packed { logic [23:0] d; logic [63:0] c; } pair_t;
      pair_t pool [0:799];
      int n = 800;

      // Build pool
      for (int i=0; i<n; i++) begin
        logic [23:0] din;
        logic [63:0] cw_ref, cw_dut;
        logic enc_timing_ok;
        din = $urandom(seed);
        cw_ref = ref_encode(din);
        // (optional) skip DUT encode to reduce time; cw_ref is sufficient as "valid codeword"
        pool[i].d = din;
        pool[i].c = cw_ref;

        // light sanity occasionally
        if ((i % 200) == 0) begin
          do_encode_strict(din, cw_dut, enc_timing_ok);
          check_equal("[T3] encoder timing sanity", enc_timing_ok);
          check_equal("[T3] encoder match sanity", (cw_dut === cw_ref));
        end
      end

      bit found = 0;
      logic [63:0] c1, c2, rx_amb;
      logic [23:0] d1, d2;

      // Find close pair dist<=6
      for (int i=0; i<n && !found; i++) begin
        for (int j=i+1; j<n && !found; j++) begin
          int dist = popcount64(pool[i].c ^ pool[j].c);
          if (dist <= 6) begin
            c1 = pool[i].c; d1 = pool[i].d;
            c2 = pool[j].c; d2 = pool[j].d;

            // Try craft rx within 3 of both by flipping 0..3 bits from c1
            for (int tries=0; tries<400 && !found; tries++) begin
              logic [63:0] m;
              int w = $urandom(seed) % 4; // 0..3
              m = rand_mask_weight(w, seed);
              rx_amb = c1 ^ m;
              if (popcount64(rx_amb ^ c2) <= 3) found = 1;
            end
          end
        end
      end

      if (!found) begin
        $display("[T3] No ambiguous case found in this run (OK). If you want, increase pool size.");
      end else begin
        logic [23:0] dout;
        logic v;
        int unsigned lat;
        logic dec_timing_ok;

        do_decode_bounded(rx_amb, dout, v, lat, dec_timing_ok);
        check_equal("[T3] decoder timing", dec_timing_ok);
        // Non-unique => MUST reject
        check_equal("[T3] ambiguity must reject (valid=0)", (v===1'b0));
        $display("[T3] Found ambiguous case (d1=%h d2=%h) => valid correctly 0", d1, d2);
      end
    end

    $display("[T3] DONE");

    $display("============================================================");
    $display(" tb_extra PASS (local regression)");
    $display("============================================================");
    $finish;
  end

endmodule
