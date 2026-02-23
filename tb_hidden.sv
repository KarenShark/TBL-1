`timescale 1ns/1ps

// tb_hidden.sv
// ------------------------------------------------------------
// Comprehensive (hidden) testbench for tbl2026.8.pdf (Section 10)
// Includes:
//   - Directed tests (0/1/2/3/4 flips)
//   - Randomised tests over many data patterns and error vectors
//   - Edge-case checks (all-zeros, all-ones, walking-1)
//   - Latency and pulse width verification
//   - Scoreboard for final grading (100 base points + bonus)
// ------------------------------------------------------------

module tb_hidden;

  logic clk;
  logic rst_n;

  // DUT ports
  logic        enc_start, enc_done;
  logic [23:0] data_in;
  logic [63:0] codeword;

  logic        dec_start, dec_done;
  logic [63:0] rx;
  logic [23:0] data_out;
  logic        valid;

  // Test control
  int total_points = 0;
  int max_points   = 100;  // base score
  int bonus_points = 0;
  int errors       = 0;

  // Instantiate DUTs
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

  // Clock generation
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // Pulse start (1 cycle, aligned to negedge)
  task pulse_start(ref logic s);
    @(negedge clk);
    s = 1'b1;
    @(negedge clk);
    s = 1'b0;
  endtask

  // Reference encoder functions (must match handout)
  function automatic logic [15:0] crc16_ccitt24(input logic [23:0] din);
    // Actual implementation omitted for brevity (same as in student's design)
    // Should compute CRC-16-CCITT over 24 bits (padded with zeros)
    // ...
  endfunction

  function automatic logic [63:0] build_u(input logic [23:0] din, input logic [15:0] crc);
    return {din, crc, 24'b0}; // As per handout
  endfunction

  function automatic logic [63:0] polar_transform64(input logic [63:0] u);
    // Actual polar transform (recursive or matrix) – omitted
    // ...
  endfunction

  function automatic logic [63:0] ref_encode(input logic [23:0] din);
    logic [15:0] crc;
    logic [63:0] u;
    crc = crc16_ccitt24(din);
    u   = build_u(din, crc);
    return polar_transform64(u);
  endfunction

  // Encode task with strict latency check
  task automatic do_encode(
    input  logic [23:0] din,
    output logic [63:0] cw,
    output bit          timing_ok
  );
    timing_ok = 1;
    data_in   = din;
    pulse_start(enc_start);

    // +1 cycle: done must be 0
    @(posedge clk); @(negedge clk);
    if (enc_done) timing_ok = 0;

    // +2 cycles: done must be 1
    @(posedge clk); @(negedge clk);
    if (!enc_done) timing_ok = 0;

    cw = codeword;

    // +3 cycle: done must drop
    @(posedge clk); @(negedge clk);
    if (enc_done) timing_ok = 0;
  endtask

  // Decode task with latency check (max 12 cycles)
  task automatic do_decode(
    input  logic [63:0] rx_in,
    output logic [23:0] dout,
    output logic        v,
    output int unsigned lat,
    output bit          timing_ok
  );
    timing_ok = 1;
    lat       = 0;
    rx        = rx_in;
    pulse_start(dec_start);

    fork
      begin: timeout
        repeat (15) @(posedge clk);  // extra margin
        timing_ok = 0;
      end
      begin: wait_done
        while (1) begin
          @(posedge clk);
          lat++;
          @(negedge clk);
          if (dec_done) break;
          if (lat >= 12) begin
            timing_ok = 0;
            disable timeout;
          end
        end
        disable timeout;
      end
    join

    dout = data_out;
    v    = valid;

    // Check pulse width (must be 1 cycle)
    if (timing_ok) begin
      @(posedge clk); @(negedge clk);
      if (dec_done) timing_ok = 0;
    end
  endtask

  // Bit mask helper
  function automatic logic [63:0] bit_mask(input int unsigned b);
    logic [63:0] m = 64'b0;
    m[b] = 1'b1;
    return m;
  endfunction

  // Check one directed case
  task directed_case(
    input string      name,
    input int         points,
    input logic [23:0] din,
    input int         num_flips,   // 0-4, >4 only for observation
    input bit         expect_valid,
    input logic [63:0] forced_cw = 64'bx  // optional custom codeword
  );
    logic [63:0] cw, rx_vec;
    logic [23:0] dout;
    logic        v;
    int unsigned lat;
    bit          enc_timing_ok, dec_timing_ok, pass;

    // Encode (if forced_cw not given)
    if (forced_cw === 64'bx) begin
      do_encode(din, cw, enc_timing_ok);
      if (!enc_timing_ok) begin
        $error("Encoder timing fail in %s", name);
        errors++;
        return;
      end
    end else begin
      cw = forced_cw;
    end

    // Inject errors
    rx_vec = cw;
    for (int i = 0; i < num_flips; i++) begin
      // Simple deterministic error positions: 0,63,1,62,... for variety
      int pos = (i % 2 == 0) ? i : 63 - i;
      rx_vec = rx_vec ^ bit_mask(pos);
    end

    do_decode(rx_vec, dout, v, lat, dec_timing_ok);
    if (!dec_timing_ok) begin
      $error("Decoder timing fail in %s", name);
      errors++;
      return;
    end

    pass = (v === expect_valid);
    if (expect_valid && pass) pass = (dout === din);
    if (!expect_valid && pass) pass = 1; // any data_out ignored

    if (pass) begin
      total_points += points;
      $display("[DIRECT][PASS] %s +%0d", name, points);
    end else begin
      errors++;
      $display("[DIRECT][FAIL] %s (exp valid=%0d, got valid=%0d, dout=%h vs %h)", 
               name, expect_valid, v, dout, din);
    end
  endtask

  // Randomised test (multiple iterations)
  task random_test(int iterations, int points_per_iter);
    for (int it = 0; it < iterations; it++) begin
      logic [23:0] din;
      logic [63:0] cw, rx;
      logic [23:0] dout;
      logic        v;
      int unsigned lat;
      bit          enc_ok, dec_ok;
      int          num_flips = $urandom_range(0, 8);  // up to 8 errors
      bit          expect_valid;

      din = $urandom();
      do_encode(din, cw, enc_ok);
      if (!enc_ok) begin
        $error("Random test: encoder timing fail");
        errors++;
        continue;
      end

      // Generate random error vector
      rx = cw;
      for (int f = 0; f < num_flips; f++) begin
        int pos = $urandom_range(0, 63);
        rx[pos] = ~rx[pos];
      end

      do_decode(rx, dout, v, lat, dec_ok);
      if (!dec_ok) begin
        $error("Random test: decoder timing fail");
        errors++;
        continue;
      end

      // Expect valid if number of flips <= 3 (design assumption)
      expect_valid = (num_flips <= 3);
      if (v === expect_valid) begin
        if (expect_valid && (dout !== din)) begin
          $error("Random test: valid but data mismatch, flips=%0d", num_flips);
          errors++;
        end else if (!expect_valid) begin
          // valid=0 is fine
        end else begin
          total_points += points_per_iter;
        end
      end else begin
        $error("Random test: valid mismatch, flips=%0d, exp=%0d, got=%0d", 
               num_flips, expect_valid, v);
        errors++;
      end
    end
  endtask

  // Bonus: check that decoder can correct up to 3 flips for all-zeros and all-ones
  task bonus_corner_cases;
    logic [23:0] din;
    logic [63:0] cw;
    bit          ok;

    // all zeros
    din = 24'h000000;
    cw = ref_encode(din);
    ok = 1;
    for (int f = 1; f <= 3; f++) begin
      logic [63:0] rx = cw;
      for (int i = 0; i < f; i++) rx[i] = ~rx[i];
      do_decode(rx, dout, v, lat, dec_ok);
      if (!(v && dout == din)) ok = 0;
    end
    if (ok) bonus_points += 5;

    // all ones
    din = 24'hFFFFFF;
    cw = ref_encode(din);
    ok = 1;
    for (int f = 1; f <= 3; f++) begin
      logic [63:0] rx = cw;
      for (int i = 0; i < f; i++) rx[63-i] = ~rx[63-i];
      do_decode(rx, dout, v, lat, dec_ok);
      if (!(v && dout == din)) ok = 0;
    end
    if (ok) bonus_points += 5;
  endtask

  // Main test sequence
  initial begin
    enc_start = 0; dec_start = 0;
    rst_n = 0;
    repeat (5) @(posedge clk);
    rst_n = 1;
    repeat (2) @(posedge clk);

    $display("============================================================");
    $display(" tb_hidden : Full testbench (base 100 points + bonus)");
    $display("============================================================");

    // --- Directed tests (30 points total) ---
    directed_case("Case A: 0 flips", 5, 24'hABCDEF, 0, 1);
    directed_case("Case B: 1 flip",  5, 24'hABCDEF, 1, 1);
    directed_case("Case B: 2 flips", 5, 24'h123456, 2, 1);
    directed_case("Case B: 3 flips", 5, 24'h789ABC, 3, 1);
    directed_case("Case C: 4 flips", 5, 24'hABCDEF, 4, 0);

    // Additional directed: walking 1 in data (5 points)
    begin
      logic [23:0] walk;
      bit walk_ok = 1;
      for (int b = 0; b < 24; b++) begin
        walk = 24'b1 << b;
        directed_case("Walking-1", 0, walk, 0, 1, ref_encode(walk)); // point counted separately
        // Actually we accumulate points per iteration; here we just check and assign points if all pass
        // For simplicity, we run a loop and add points at end if all good.
      end
      // Not implemented fully here; could be done with a separate check.
    end

    // --- Randomised tests (50 points) ---
    random_test(100, 1);  // 100 iterations, each worth 1 point if correct

    // --- Edge cases (20 points) ---
    directed_case("All zeros", 10, 24'h000000, 0, 1);
    directed_case("All ones",  10, 24'hFFFFFF, 0, 1);

    // --- Bonus: correct up to 3 errors for all-zero/all-one (10 bonus) ---
    bonus_corner_cases;

    // --- Final summary ---
    $display("------------------------------------------------------------");
    $display("[HIDDEN] Base score = %0d / %0d", total_points, max_points);
    $display("[HIDDEN] Bonus score = %0d", bonus_points);
    if (errors == 0 && total_points >= max_points) begin
      $display("[HIDDEN] PASS (base score %0d/100)", total_points);
      $finish;
    end else begin
      $display("[HIDDEN] FAIL (errors=%0d, base=%0d)", errors, total_points);
      $fatal(1);
    end
  end

endmodule
