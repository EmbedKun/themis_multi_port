# Hybrid Themis DDR Resource Sweep, 2026-09-08

This note records the remote Vivado out-of-context synthesis run for the
Hybrid-Themis DDR-aware baseline.

Common settings:

- Remote host: `172.22.5.106`
- Remote work directory: `/home/user/hestia_hybrid_20260908_192126`
- Vivado: `/tools/Xilinx/Vivado/2020.2/bin/vivado`
- FPGA part: `xcu200-fsgd2104-2-e`
- Flow: out-of-context synthesis, core only
- Excluded: U200 shell, DDR4 IP, ILA, synthetic generator, and checkers
- SRAM capacity: `81920` 64-byte cells, approximately 5 MiB
- DDR logical capacity: `8388608` batches x `8` cells/batch x 64 bytes/cell,
  approximately 4 GiB
- Metadata mode: external/memory-backed metadata enabled

Hybrid-Themis keeps the common descriptor, SRAM free-list, DDR batch, and
per-port BBQ substrate. Its SRAM-residency policy adds per-port dynamic-threshold
admission and Themis-style DDR spillover/migration hints.

| Design | Ports | CLB LUTs | CLB Registers | LUTRAM | BRAM tiles | URAM | WNS ns |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Hybrid-Themis | 1 | 6271 | 1396 | 0 | 391 | 160 | -1.951 |
| Hybrid-Themis | 2 | 7579 | 2046 | 0 | 391 | 160 | -3.241 |
| Hybrid-Themis | 4 | 10338 | 3074 | 0 | 401 | 160 | -7.009 |
| Hybrid-Themis | 8 | 15842 | 5124 | 0 | 401 | 160 | -13.690 |

The exact command used on the remote source tree was:

```bash
VIVADO_BIN=/tools/Xilinx/Vivado/2020.2/bin/vivado \
HESTIA_SWEEP_DESIGNS=hybrid_themis \
bash scripts/rerun_resource_sweeps.sh fullscale
```

The generated summary files are:

- `/home/user/hestia_hybrid_20260908_192126/build/rerun_resource_fullscale_20260908_192225/resource_summary.csv`
- `/home/user/hestia_hybrid_20260908_192126/build/rerun_resource_fullscale_20260908_192225/resource_summary.md`

Functional sanity check was also run on the remote host with
`HESTIA_BASELINE_DDR_POLICY_MODE=4`:

```text
generated=96, dequeued=96, sram_admit=6, ddr_admit=90,
swap_out=0, swap_in=0, direct_ddr=90, drop=0
PASS: DDR-aware shared-buffer baseline policy=4 preserves per-port rank order
```
