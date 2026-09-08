# Shared-Buffer Baseline Resource Sweep

Date: 2026-09-04

This sweep evaluates three DDR-aware shared-buffer baselines using the same memory-backed Hestia resource-core substrate. Only the buffer-management policy is changed across DT, Occamy, and OBM. The large storage structures, per-port scheduling substrate, descriptor format, DDR logical address space, and synthesis settings are kept identical.

## Common Configuration

| Item | Value |
| --- | ---: |
| FPGA part | `xcu200-fsgd2104-2-e` |
| Vivado | 2020.2 |
| Target clock | 3.333 ns, 300 MHz |
| SRAM payload cells | 81920 |
| Cell width | 512 bits, 64 B |
| SRAM payload capacity | 5 MiB |
| DDR logical capacity | 4 GiB |
| DDR batch slots | 8388608 |
| Batch size | 8 cells |
| Packet descriptor slots | 81920 |
| Active batch metadata window | 4096 batches |
| Counted | Core logic and inferred memory macros |
| Excluded | DDR4 IP, U200 shell, ILA, generator, software checker |

## Baseline Results

| Baseline | Ports | CLB LUTs | CLB Registers | LUTRAM | BRAM Tile | URAM288 | DSP | WNS @ 300MHz |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| DT | 1 | 5893 | 1325 | 0 | 391 | 160 | 0 | -0.354 ns |
| DT | 2 | 6780 | 1928 | 0 | 391 | 160 | 0 | -1.923 ns |
| DT | 4 | 8588 | 2794 | 0 | 401 | 160 | 0 | -2.197 ns |
| DT | 8 | 12664 | 4734 | 0 | 401 | 160 | 0 | -8.937 ns |
| Occamy | 1 | 6187 | 1463 | 0 | 391 | 160 | 0 | -0.811 ns |
| Occamy | 2 | 6863 | 1928 | 0 | 391 | 160 | 0 | -2.421 ns |
| Occamy | 4 | 9119 | 2862 | 0 | 401 | 160 | 0 | -4.543 ns |
| Occamy | 8 | 13127 | 4732 | 0 | 401 | 160 | 0 | -9.331 ns |
| OBM | 1 | 6116 | 1463 | 0 | 391 | 160 | 0 | -0.427 ns |
| OBM | 2 | 6800 | 1928 | 0 | 391 | 160 | 0 | -2.299 ns |
| OBM | 4 | 9104 | 2862 | 0 | 401 | 160 | 0 | -4.390 ns |
| OBM | 8 | 15719 | 5147 | 0 | 401 | 160 | 0 | -9.723 ns |

## Baselines and Hestia

| Design | Ports | CLB LUTs | CLB Registers | BRAM Tile | URAM288 | WNS @ 300MHz |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| DT | 1 | 5893 | 1325 | 391 | 160 | -0.354 ns |
| Occamy | 1 | 6187 | 1463 | 391 | 160 | -0.811 ns |
| OBM | 1 | 6116 | 1463 | 391 | 160 | -0.427 ns |
| Hestia | 1 | 6275 | 1446 | 391 | 160 | -0.728 ns |
| DT | 2 | 6780 | 1928 | 391 | 160 | -1.923 ns |
| Occamy | 2 | 6863 | 1928 | 391 | 160 | -2.421 ns |
| OBM | 2 | 6800 | 1928 | 391 | 160 | -2.299 ns |
| Hestia | 2 | 7000 | 1902 | 391 | 160 | -1.748 ns |
| DT | 4 | 8588 | 2794 | 401 | 160 | -2.197 ns |
| Occamy | 4 | 9119 | 2862 | 401 | 160 | -4.543 ns |
| OBM | 4 | 9104 | 2862 | 401 | 160 | -4.390 ns |
| Hestia | 4 | 9238 | 2781 | 401 | 160 | -5.072 ns |
| DT | 8 | 12664 | 4734 | 401 | 160 | -8.937 ns |
| Occamy | 8 | 13127 | 4732 | 401 | 160 | -9.331 ns |
| OBM | 8 | 15719 | 5147 | 401 | 160 | -9.723 ns |
| Hestia | 8 | 14221 | 4548 | 401 | 160 | -11.120 ns |

## Artifacts

Summary CSV:

- `C:/Users/mkxue/Desktop/hestia/build/baseline_membacked_fullscale_sweep_local_20260904_095727/baseline_vs_hestia_membacked_fullscale_summary.csv`

Baseline run root:

- `C:/Users/mkxue/Desktop/hestia/build/baseline_membacked_fullscale_sweep_local_20260904_095727`

Hestia comparison run root:

- `C:/Users/mkxue/Desktop/hestia/build/membacked_fullscale_sweep_local_20260904_094429`

## Notes

All rows use the same memory-backed payload/metadata substrate, so URAM stays fixed at 160 and BRAM stays fixed except for descriptor-word packing changes when the port-id width grows. The LUT/FF differences therefore mainly reflect policy logic and port-scaling control: DT is the lightest threshold policy, Occamy adds over-threshold/reclaim selection, and OBM adds longest-queue pushout selection. The measured WNS values are post-synthesis out-of-context estimates and are not final implementation timing.
