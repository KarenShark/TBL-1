# Deep Space Error Correction Subsystem (Polar + CRC-16)

A high-performance SystemVerilog implementation of an Error Correction Code (ECC) subsystem designed for ultra-reliable communication in deep-space environments (e.g., Mars Robotic Missions).

## Technical Architecture

This project implements a hybrid error control system combining **Polar Coding** and **Cyclic Redundancy Check (CRC)** to achieve high reliability over extremely noisy channels.

### Core Components

#### 1. Polar(64,40) Encoder
- **Algorithm**: Implements the standard polar butterfly transform without bit-reversal.
- **Bit Mapping**: Maps 24 data bits and 16 CRC bits to optimized `INFO_POS` indices, maximizing the minimum Hamming distance ($d_{min} = 8$).
- **Performance**: Pulse-based control interface with a fixed latency of **2 clock cycles**.

#### 2. Bounded-Distance Decoder (Radius=3)
- **Decoding Strategy**: Exhaustive search within a Hamming radius of 3.
- **Verification Engine**: 
    - Applies inverse polar transform on candidate vectors.
    - Rigorously validates frozen-bit constraints ($u_{frozen} = 0$).
    - Performs secondary CRC-16 validation to eliminate mis-correction.
- **Fail-Safe Logic**: Specifically designed to assert `valid=0` if no unique, high-confidence candidate is found, preventing "wrong action" in robotic control.
- **Throughput**: Optimized search path ensuring completion within **12 clock cycles**.

#### 3. CRC-16-CCITT Engine
- **Polynomial**: $x^{16} + x^{12} + x^5 + 1$ (0x1021).
- **Implementation**: bit-serial hardware architecture with MSB-first processing.

### Hardware Performance Specs

| Metric | Specification |
|--------|---------------|
| **Codeword Length** | 64 bits |
| **Information Bits** | 40 bits (24 Data + 16 CRC) |
| **Encoder Latency** | 2 Cycles |
| **Decoder Latency** | ≤ 12 Cycles |
| **Error Correction** | 1-3 Bit Flips (Guaranteed) |
| **Error Detection** | 4 Bit Flips (Guaranteed) |

## Verification Methodology

The codebase includes a comprehensive verification suite targeting various noise profiles:

- **Directed Tests**: Verification of zero-error and low-weight error cases.
- **Extended Edge Cases**: 
    - **Burst Errors**: High-density noise clusters.
    - **Scattered Flips**: Randomly distributed bit flips.
    - **Boundary Flips**: Errors at the start/end of codewords.
- **Extreme Payloads**: Validation with `0x000000`, `0xFFFFFF`, and alternating `0x555555` patterns.

## Reproducing Results

To simulate the design using Vivado `xsim`:

```bash
# Compile the package and modules
xvlog -sv polar_common_pkg.sv polar64_crc16_encoder.sv polar64_crc16_decoder.sv tb_basic.sv

# Elaborate the design
xelab tb_basic -debug typical -s sim_snapshot

# Run simulation
xsim sim_snapshot -runall
```

---
*Architected for reliability. Optimized for hardware.*
