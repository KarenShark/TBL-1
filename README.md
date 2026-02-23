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
| polar64_crc16_encoder | done @ +2 cycles | (1) CRC-16-CCITT on data_in[23:0] via crc.sv; (2) build u[63:0] with data at INFO_POS[0..23], CRC at INFO_POS[24..39], frozen=0; (3) polar butterfly transform (no bit-reversal) |
| polar64_crc16_decoder | done ≤12 cycles | (1) Search all masks with Hamming weight 0..3; (2) for each candidate rx^mask, inverse polar → u_hat, check frozen bits=0; (3) extract data+CRC from u_hat, verify CRC; (4) unique hit → valid=1 else valid=0 |

## Division of Labor

| Task | Contributors |
|------|--------------|
| 1. Encoder + CRC | WANG Xinan, HE Siyu, LIU Yutong |
| 2. Decoder | ZHAO Xingquan, LIU Yutong, TANG Xiwei |
| 3. tb_basic | PAN Yang, ZHAO Xingquan, TANG Xiwei |
| 4. ai_log.txt, README.md, report | WANG Xinan, HE Siyu, PAN Yang |
