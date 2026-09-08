# Hestia 2P Memory-Backed Resource Run

Date: 2026-09-04

This run measures the resource-core path after moving the large storage structures out of registers/LUTs and into FPGA memories. It is a core-only out-of-context synthesis run for U200 and excludes DDR4 IP, shell logic, ILA, synthetic traffic generators, and software-side checkers.

## Configuration

| Item | Value |
| --- | ---: |
| FPGA part | `xcu200-fsgd2104-2-e` |
| Vivado | 2020.2 |
| Ports | 2 |
| Target clock | 3.333 ns, 300 MHz |
| SRAM payload cells | 81920 |
| Cell width | 512 bits, 64 B |
| SRAM payload capacity | 5 MiB |
| DDR logical batch slots | 8388608 |
| DDR logical capacity | 4 GiB |
| Batch size | 8 cells |
| Packet descriptor slots | 81920 |
| Active batch metadata window | 4096 batches |

## Measured Result

| Metric | Value |
| --- | ---: |
| CLB LUTs | 7000 |
| CLB Registers | 1902 |
| LUTRAM | 0 |
| RAMB36 | 381 |
| RAMB18 | 20 |
| Block RAM Tile | 391 |
| URAM288 | 160 |
| DSP | 0 |
| WNS at 300 MHz OOC | -1.748 ns |

Report paths:

- `C:/Users/mkxue/Desktop/hestia/build/membacked_fullscale_2p_local_20260904_093508/resource_core_utilization_synth.rpt`
- `C:/Users/mkxue/Desktop/hestia/build/membacked_fullscale_2p_local_20260904_093508/resource_core_utilization_hier_synth.rpt`
- `C:/Users/mkxue/Desktop/hestia/build/membacked_fullscale_2p_local_20260904_093508/resource_core_timing_summary_synth.rpt`

## Memory Mapping

The 5 MiB SRAM payload store is implemented as 20 banks, each bank holding 4096 cells. A 512-bit cell is split into eight 64-bit lanes, so the store maps to 20 x 8 = 160 URAM288 instances.

The descriptor table is a packed wide-word BRAM table. The descriptor free-list and SRAM free-cell list are BRAM-backed memories. The DDR batch metadata no longer allocates one on-chip entry for every 4 GiB batch slot; it keeps only a finite active/open/dirty/in-flight metadata window of 4096 batches on chip. Cold metadata is treated as external/off-chip state in this resource-core accounting.

## Notes

The resource-core currently uses a synthesis-friendly paper-scale port queue model for the per-port scheduling path. The memory-backed structures are real inferred FPGA memories, not black boxes and not large register arrays. The 300 MHz timing report is post-synthesis OOC timing only; the unpipelined URAM/BRAM read paths are the dominant timing issue and should be pipelined for an implementation-frequency target.
