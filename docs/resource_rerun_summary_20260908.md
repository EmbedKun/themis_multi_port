# Resource Rerun Summary, 2026-09-08

This note records the Vivado out-of-context synthesis rerun used as the
current reproducibility anchor for Hestia and the DDR-aware baseline policies.

Common settings:

- Vivado 2020.2
- FPGA part: `xcu200-fsgd2104-2-e`
- Flow: out-of-context synthesis
- Excluded: U200 shell, DDR4 IP, ILA, synthetic generator, and checkers

## Compact Control-Core Configuration

The compact configuration keeps the complete control boundary but uses small
logical memories. It is useful for tracking how the per-port scheduler and
shared-buffer control logic scale.

| Design | Ports | LUTs | FFs | LUTRAM | BRAM | URAM | WNS ns |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| DT-Hybrid | 1 | 3972 | 2321 | 293 | 0 | 0 | 0.560 |
| Hestia | 1 | 4791 | 2528 | 341 | 0 | 0 | 0.710 |
| OBM-Hybrid | 1 | 4370 | 2395 | 317 | 0 | 0 | 0.877 |
| Occamy-Hybrid | 1 | 4379 | 2383 | 317 | 0 | 0 | 0.570 |
| DT-Hybrid | 2 | 6786 | 4666 | 586 | 0 | 0 | 0.354 |
| Hestia | 2 | 9496 | 5081 | 682 | 0 | 0 | 0.182 |
| OBM-Hybrid | 2 | 7531 | 4798 | 634 | 0 | 0 | -0.289 |
| Occamy-Hybrid | 2 | 7928 | 4967 | 682 | 0 | 0 | 0.274 |
| DT-Hybrid | 4 | 15156 | 9582 | 1204 | 0 | 0 | -0.085 |
| Hestia | 4 | 18895 | 10344 | 1412 | 0 | 0 | -0.224 |
| OBM-Hybrid | 4 | 17095 | 10169 | 1412 | 0 | 0 | -2.548 |
| Occamy-Hybrid | 4 | 17925 | 10099 | 1412 | 0 | 0 | 0.088 |
| DT-Hybrid | 8 | 33707 | 19938 | 3408 | 0 | 0 | -0.440 |
| Hestia | 8 | 37804 | 21397 | 4112 | 0 | 0 | -0.451 |
| OBM-Hybrid | 8 | 36692 | 21140 | 4112 | 0 | 0 | -7.722 |
| Occamy-Hybrid | 8 | 36516 | 20850 | 3984 | 0 | 0 | -0.190 |

## 5MiB SRAM + 4GiB DDR Configuration

The full-capacity resource configuration maps large storage structures to
FPGA block memories or finite active metadata windows. The 4GiB DDR tier is a
logical address space behind the AXI interface; the design does not build an
on-chip metadata entry for every possible off-chip batch.

| Design | Ports | LUTs | FFs | LUTRAM | BRAM | URAM | WNS ns |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| DT-Hybrid | 1 | 5893 | 1325 | 0 | 391 | 160 | -0.354 |
| Hestia | 1 | 6275 | 1446 | 0 | 391 | 160 | -0.728 |
| Hybrid-Themis | 1 | 6271 | 1396 | 0 | 391 | 160 | -1.951 |
| OBM-Hybrid | 1 | 6116 | 1463 | 0 | 391 | 160 | -0.427 |
| Occamy-Hybrid | 1 | 6187 | 1463 | 0 | 391 | 160 | -0.811 |
| DT-Hybrid | 2 | 6780 | 1928 | 0 | 391 | 160 | -1.923 |
| Hestia | 2 | 7000 | 1902 | 0 | 391 | 160 | -1.748 |
| Hybrid-Themis | 2 | 7579 | 2046 | 0 | 391 | 160 | -3.241 |
| OBM-Hybrid | 2 | 6800 | 1928 | 0 | 391 | 160 | -2.299 |
| Occamy-Hybrid | 2 | 6863 | 1928 | 0 | 391 | 160 | -2.421 |
| DT-Hybrid | 4 | 8588 | 2794 | 0 | 401 | 160 | -2.197 |
| Hestia | 4 | 9238 | 2781 | 0 | 401 | 160 | -5.072 |
| Hybrid-Themis | 4 | 10338 | 3074 | 0 | 401 | 160 | -7.009 |
| OBM-Hybrid | 4 | 9104 | 2862 | 0 | 401 | 160 | -4.390 |
| Occamy-Hybrid | 4 | 9119 | 2862 | 0 | 401 | 160 | -4.543 |
| DT-Hybrid | 8 | 12664 | 4734 | 0 | 401 | 160 | -8.937 |
| Hestia | 8 | 14221 | 4548 | 0 | 401 | 160 | -11.120 |
| Hybrid-Themis | 8 | 15842 | 5124 | 0 | 401 | 160 | -13.690 |
| OBM-Hybrid | 8 | 15719 | 5147 | 0 | 401 | 160 | -9.723 |
| Occamy-Hybrid | 8 | 13127 | 4732 | 0 | 401 | 160 | -9.331 |

The full-capacity rows keep LUT and FF usage in the same order of magnitude by
moving payload SRAM, descriptor tables, and free lists into BRAM/URAM. Capacity
therefore appears primarily as block-memory usage, while LUT/FF growth is
dominated by per-port scheduling, policy, arbitration, and AXI-control logic.

## Reproduction

On Windows with Vivado 2020.2 installed in the default path:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\rerun_resource_sweeps.ps1 -Mode both
```

To rerun only one resource boundary:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\rerun_resource_sweeps.ps1 -Mode compact
powershell -ExecutionPolicy Bypass -File scripts\rerun_resource_sweeps.ps1 -Mode fullscale
```

On Linux Vivado hosts:

```bash
bash scripts/rerun_resource_sweeps.sh both
HESTIA_SWEEP_DESIGNS=hybrid_themis bash scripts/rerun_resource_sweeps.sh fullscale
```
