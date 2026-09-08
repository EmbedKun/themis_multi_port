# Hestia Memory-Backed Full-Scale Resource Sweep

Date: 2026-09-04

This sweep uses the memory-backed Hestia resource core. The total shared buffer capacity is fixed for every port count, so the results show the incremental cost of adding ports rather than scaling the memory capacity.

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
| Counted | Hestia resource core only |
| Excluded | DDR4 IP, U200 shell, ILA, generator, software checker |

## Raw Vivado Results

| Ports | CLB LUTs | CLB Registers | LUTRAM | BRAM Tile | RAMB36 | RAMB18 | URAM288 | DSP | WNS @ 300MHz |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 6275 | 1446 | 0 | 391 | 381 | 20 | 160 | 0 | -0.728 ns |
| 2 | 7000 | 1902 | 0 | 391 | 381 | 20 | 160 | 0 | -1.748 ns |
| 4 | 9238 | 2781 | 0 | 401 | 401 | 0 | 160 | 0 | -5.072 ns |
| 8 | 14221 | 4548 | 0 | 401 | 401 | 0 | 160 | 0 | -11.120 ns |

Summary CSV:

- `C:/Users/mkxue/Desktop/hestia/build/membacked_fullscale_sweep_local_20260904_094429/hestia_membacked_fullscale_sweep_summary.csv`

Run directories:

- `C:/Users/mkxue/Desktop/hestia/build/membacked_fullscale_sweep_local_20260904_094429/1p`
- `C:/Users/mkxue/Desktop/hestia/build/membacked_fullscale_sweep_local_20260904_094429/2p`
- `C:/Users/mkxue/Desktop/hestia/build/membacked_fullscale_sweep_local_20260904_094429/4p`
- `C:/Users/mkxue/Desktop/hestia/build/membacked_fullscale_sweep_local_20260904_094429/8p`

## Interpretation

The URAM count is fixed at 160 for all port counts because the 5 MiB SRAM payload store is shared: 20 banks x 8 lanes. The BRAM count is also mostly fixed because the descriptor table, descriptor free-list, SRAM free-cell list, and active DDR batch window are global structures. The jump from 391 to 401 BRAM tiles at 4P happens because the packed descriptor word widens when `PORT_W` grows beyond one bit, changing BRAM packing for the descriptor table.

The LUT and FF counts grow with port count because each port adds a scheduling queue and contributes to global arbitration, rank comparison, and per-port occupancy/control paths. The timing numbers are post-synthesis out-of-context estimates. The current resource core intentionally keeps wide memory outputs observable for resource accounting, and that digest/selection logic hurts WNS; implementation-oriented builds should pipeline the URAM/BRAM read paths and split cross-port selection trees.
