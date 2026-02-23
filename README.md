# EE3220 TBL-1

## How to Reproduce

```bash
# Download team_XX_submission.zip, unzip, then:
cd <extracted_folder>   # e.g. team_XX_submission after unzip

# Vivado xsim compile and run
xvlog -sv crc.sv polar64_crc16_encoder.sv polar64_crc16_decoder.sv tb_basic.sv
xelab tb_basic -debug typical -s sim_snapshot
xsim sim_snapshot -runall
```

## Module Descriptions and Latency

| Module | Latency | Description |
|--------|---------|-------------|
| polar64_crc16_encoder | done @ +2 cycles | CRC-16-CCITT (crc.sv) + build u[INFO_POS] + polar butterfly transform |
| polar64_crc16_decoder | done ≤12 cycles | Bounded-distance radius=3 mask search + frozen-bit check + CRC verify |

## Division of Labor

| Task | Contributors |
|------|--------------|
| 1. Encoder + CRC | WANG Xinan, HE Siyu, LIU Yutong |
| 2. Decoder | ZHAO Xingquan, LIU Yutong, TANG Xiwei |
| 3. tb_basic | PAN Yang, ZHAO Xingquan, TANG Xiwei |
| 4. ai_log.txt, README.md, report | WANG Xinan, HE Siyu, PAN Yang |
