# Deep Space ECC Subsystem: Polar(64,40) + CRC-16

A professional-grade SystemVerilog implementation of a high-reliability Error Correction Code (ECC) subsystem. Designed for critical communication links in deep-space environments, this system provides 100% reliability for corrections of up to 3-bit flips and robust detection of uncorrectable errors.

## Core Technical Architecture

The architecture is a hardware-optimized hybrid of **Polar Coding** and **Cyclic Redundancy Checking (CRC)**, engineered for low-latency hardware execution.

### 1. High-Throughput Hardware Encoder
- **Integrated CRC-16**: Pre-processes 24-bit payload data with a CCITT-standard CRC-16 engine ($x^{16} + x^{12} + x^5 + 1$) for end-to-end integrity.
- **Optimized Bit Placement**: Dynamically maps the 40 information bits (Data + CRC) into optimal `INFO_POS` indices, maximizing the code's minimum Hamming distance ($d_{min} = 8$).
- **Polar Butterfly Network**: Executes a 64-point polar transform in hardware, producing a robust codeword.
- **Latency**: Pulse-triggered interface with a deterministic **2-cycle** processing delay.

### 2. Error-Correction Decoder (BD-Search Radius=3)
- **Bounded-Distance Algorithm**: Implements an exhaustive search within the Hamming sphere of radius 3 around the received signal.
- **Multi-Stage Validation**:
    - **Polar Inverse**: Recovers the original bit positions using an inverse butterfly transform.
    - **Frozen-Bit Constraint**: Enforces the $u_{frozen}=0$ rule to validate codeword candidates.
    - **CRC Verification**: Cross-references the recovered payload against the embedded CRC to guarantee zero mis-corrections.
- **Reliability Metric**: Optimized to output `valid=0` if a unique, high-confidence solution is not identified, ensuring "fail-safe" behavior for downstream robotic controllers.
- **Performance**: High-efficiency search path completed in **under 12 clock cycles**.

## System Performance Specifications

| Metric | Performance |
|--------|-------------|
| **ECC Type** | Polar(64,40) |
| **Integrity Check** | CRC-16-CCITT |
| **Error Correction Capacity** | 3 Bits (Full Hamming Distance Support) |
| **Error Detection Capacity** | 4 Bits (Guaranteed Detection) |
| **Encoder Throughput** | 2 Cycles/Codeword |
| **Decoder Throughput** | ≤ 12 Cycles/Codeword |

## Advanced Verification Suite

The implementation is validated against a rigorous testbench suite designed for space-channel simulation:

- **Directed Tests**: validation of corner cases and zero-noise environments.
- **Stochastic Noise Injection**: Simulation of random bit flips across the entire codeword.
- **Burst Noise Analysis**: Validation against clustered noise and boundary-condition errors.
- **Hardware-in-the-Loop Readiness**: Designed for seamless integration into Xilinx/Vivado synthesis flows.

---
*Engineering focus: Reliability, Latency, and Hardware Efficiency.*
