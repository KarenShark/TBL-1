// crc.sv
// ------------------------------------------------------------
// CRC-16-CCITT for 24-bit payload (handout Section 7).
// init=0, MSB-first, poly 0x1021, xorout=0.
// ------------------------------------------------------------

`timescale 1ns/1ps

package crc_pkg;

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

endpackage
