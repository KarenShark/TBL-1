`timescale 1ns/1ps

// tb_extended.sv
// ------------------------------------------------------------
// Extended testbench for TBL1 project.
// Covers additional edge cases beyond tb_basic.sv:
//   - Data patterns: 0x000000, 0xFFFFFF, 0x555555, 0xAAAAAA
//   - Error patterns: End-of-frame flips, Burst flips, Boundary flips
//
// Usage:
//   xvlog -sv polar_common_pkg.sv polar64_crc16_encoder.sv polar64_crc16_decoder.sv tb_extended.sv
//   xelab tb_extended -debug typical -s sim_snapshot_ext
//   xsim sim_snapshot_ext -runall
// ------------------------------------------------------------

module tb_extended;

  import polar_common_pkg::*;

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

  // Test signals
  logic [23:0] din;
  logic [63:0] cw_ref, cw_dut;
  logic [23:0] dout;
  logic        v;
  int unsigned lat;

  // Local flags
  logic enc_timing_ok;
  logic dec_timing_ok;
  bit   dec_ok;
  
  // Scoring
  int test_score;
  int test_total;
  int test_fail;

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

  // 100 MHz clock
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // Start pulse helper
  task automatic pulse_start(ref logic s);
    begin
      @(negedge clk);
      s = 1'b1;
      @(negedge clk);
      s = 1'b0;
    end
  endtask

  // Reference encoder (same as tb_basic)
  function automatic logic [63:0] ref_encode(input logic [23:0] din);
    logic [15:0] crc;
    logic [63:0] u;
    begin
      crc = crc16_ccitt24(din);
      u   = build_u(din, crc);
      return polar_transform64(u);
    end
  endfunction

  // Decoder transaction wrapper
  task automatic do_decode(
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
    end
  endtask

  // Single-bit mask helper
  function automatic logic [63:0] bit_mask(input int unsigned b);
    logic [63:0] m;
    begin
      m = 64'b0;
      m[b] = 1'b1;
      return m;
    end
  endfunction

  task automatic test_item(
    input string name,
    input int    pts,
    input bit    pass
  );
    begin
      if (pass) begin
        test_score += pts;
        $display("[EXT][PASS] +%0d : %s", pts, name);
      end else begin
        test_fail++;
        $display("[EXT][FAIL] +%0d : %s", pts, name);
      end
    end
  endtask

  initial begin
    enc_start  = 1'b0;
    dec_start  = 1'b0;
    data_in    = '0;
    rx         = '0;

    test_score = 0;
    test_fail  = 0;
    test_total = 10; // 5 cases * 2 pts

    // reset
    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    $display("============================================================");
    $display(" tb_extended (TBL1) : Additional Corner Cases");
    $display("============================================================");

    // 1. Data Pattern: All Zeros + 3 flips (end of frame)
    din = 24'h000000;
    cw_ref = ref_encode(din);
    do_decode(cw_ref ^ bit_mask(61) ^ bit_mask(62) ^ bit_mask(63), dout, v, lat, dec_timing_ok);
    dec_ok = (v === 1'b1) && (dout === din) && dec_timing_ok;
    test_item("All Zeros + 3 flips (end of frame) -> CORRECT", 2, dec_ok);

    // 2. Data Pattern: All Ones + 4-bit burst flips (Reject)
    din = 24'hFFFFFF;
    cw_ref = ref_encode(din);
    do_decode(cw_ref ^ bit_mask(10) ^ bit_mask(11) ^ bit_mask(12) ^ bit_mask(13), dout, v, lat, dec_timing_ok);
    dec_ok = (v === 1'b0) && dec_timing_ok;
    test_item("All Ones + 4-bit burst flips -> REJECT", 2, dec_ok);

    // 3. Data Pattern: Alternating 0x555555 + 3 scattered flips
    din = 24'h555555;
    cw_ref = ref_encode(din);
    do_decode(cw_ref ^ bit_mask(0) ^ bit_mask(30) ^ bit_mask(60), dout, v, lat, dec_timing_ok);
    dec_ok = (v === 1'b1) && (dout === din) && dec_timing_ok;
    test_item("0x555555 + 3 scattered flips -> CORRECT", 2, dec_ok);

    // 4. Data Pattern: Alternating 0xAAAAAA + 4 scattered flips (Reject)
    din = 24'hAAAAAA;
    cw_ref = ref_encode(din);
    do_decode(cw_ref ^ bit_mask(5) ^ bit_mask(15) ^ bit_mask(25) ^ bit_mask(35), dout, v, lat, dec_timing_ok);
    dec_ok = (v === 1'b0) && dec_timing_ok;
    test_item("0xAAAAAA + 4 scattered flips -> REJECT", 2, dec_ok);

    // 5. Boundary 4-bit flips (0,1,62,63) on 0xABCDEF
    din = 24'hABCDEF;
    cw_ref = ref_encode(din);
    do_decode(cw_ref ^ bit_mask(0) ^ bit_mask(1) ^ bit_mask(62) ^ bit_mask(63), dout, v, lat, dec_timing_ok);
    dec_ok = (v === 1'b0) && dec_timing_ok;
    test_item("Boundary 4-bit flips (0,1,62,63) -> REJECT", 2, dec_ok);

    // Summary
    $display("------------------------------------------------------------");
    $display("[SUMMARY] Extended Score = %0d / %0d", test_score, test_total);
    $display("------------------------------------------------------------");

    if (test_fail != 0) begin
      $display("[tb_extended] FAIL");
      $fatal(1);
    end else begin
      $display("[tb_extended] PASS");
      $finish;
    end
  end

endmodule
