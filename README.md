# EE3220 TBL-1

## Vivado xsim Commands

```bash
xvlog -sv crc.sv polar64_crc16_encoder.sv polar64_crc16_decoder.sv tb_basic.sv
xelab tb_basic -debug typical -s sim_snapshot
xsim sim_snapshot -runall
```

## Module Descriptions and Latency

| Module | Latency | Description |
|--------|---------|-------------|
| polar64_crc16_encoder | done @ +2 cycles | CRC-16-CCITT + polar transform |
| polar64_crc16_decoder | done ≤12 cycles | Bounded-distance radius=3 + CRC check |

## Division of Labor

| Task | Contributors |
|------|--------------|
| 1. Encoder | WANG Xinan, HE Siyu, LIU Yutong |
| 2. Decoder | ZHAO Xingquan, LIU Yutong, TANG Xiwei |
| 3. tb_basic | PAN Yang, ZHAO Xingquan, TANG Xiwei |
| 4. ai_log.txt, README.md, report | WANG Xinan, HE Siyu, PAN Yang |
| 5. CRC code | HE Siyu |
