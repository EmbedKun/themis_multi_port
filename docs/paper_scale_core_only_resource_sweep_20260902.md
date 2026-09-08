# Paper-Scale Core-Only Resource Sweep, 2026-09-02

This note records the real Vivado out-of-context synthesis results for Hestia
and three DDR-aware shared-buffer baselines under the paper-scale capacity
configuration.

## Methodology

- Host: `user@172.22.5.106`
- Remote work directory: `/home/user/hestia_baseline_work_20260831_2320`
- Result directory: `build/paper_scale_core_only_sweep_20260902_101759`
- Local copy: `build/paper_scale_core_only_sweep_20260902_101759`
- Tool: Vivado 2020.2
- Part: `xcu200-fsgd2104-2-e`
- Flow: out-of-context synthesis
- Clock target: 3.333 ns, 300 MHz
- Top: `hestia_paper_scale_resource_core`
- Counted logic: per-port BBQ-style scheduler control, descriptor address
  widths, occupancy accounting, shared SRAM/DDR buffer-management control,
  policy logic, and request arbiters
- Excluded logic: payload SRAM arrays, DDR4 IP/controller, ILA, U200 shell,
  synthetic traffic generator, checkers, and debug/stat counters

## Capacity

The sweep fixes the buffer capacity to the paper-style scale:

| Parameter | Value |
| --- | ---: |
| Cell size | 64 B |
| SRAM capacity | 5 MiB |
| SRAM cells | 81,920 |
| Off-chip capacity | 4 GiB |
| Off-chip cells | 67,108,864 |
| DDR batch size | 8 cells |
| DDR batch slots | 8,388,608 |
| Rank width | 10 bits |
| BBQ bitmap width | 32 bits |
| Sequence width | 16 bits |
| Packet cell-count width | 16 bits |

The 5 MiB/4 GiB capacity is reflected in pointer, descriptor, batch, and
occupancy widths. The storage arrays themselves are not synthesized in this
core-only run.

## Results

| Design | Ports | CLB LUTs | CLB Registers | LUTRAM | BRAM tiles | URAM | DSP | WNS @ 300 MHz |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Hestia | 1 | 752 | 348 | 0 | 0 | 0 | 0 | -0.232 ns |
| Hestia | 2 | 2,067 | 2,201 | 0 | 0 | 0 | 0 | -0.298 ns |
| Hestia | 4 | 3,309 | 2,641 | 0 | 0 | 0 | 0 | -3.219 ns |
| Hestia | 8 | 7,031 | 3,733 | 0 | 0 | 0 | 0 | -10.467 ns |
| DT-Hybrid | 1 | 746 | 348 | 0 | 0 | 0 | 0 | -0.198 ns |
| DT-Hybrid | 2 | 1,937 | 2,135 | 0 | 0 | 0 | 0 | -0.158 ns |
| DT-Hybrid | 4 | 2,267 | 2,267 | 0 | 0 | 0 | 0 | -1.224 ns |
| DT-Hybrid | 8 | 4,460 | 3,083 | 0 | 0 | 0 | 0 | -7.037 ns |
| Occamy-Hybrid | 1 | 833 | 348 | 0 | 0 | 0 | 0 | -1.841 ns |
| Occamy-Hybrid | 2 | 2,152 | 2,180 | 0 | 0 | 0 | 0 | -1.763 ns |
| Occamy-Hybrid | 4 | 2,995 | 2,484 | 0 | 0 | 0 | 0 | -3.091 ns |
| Occamy-Hybrid | 8 | 7,229 | 3,710 | 0 | 0 | 0 | 0 | -7.261 ns |
| OBM-Hybrid | 1 | 788 | 348 | 0 | 0 | 0 | 0 | +0.015 ns |
| OBM-Hybrid | 2 | 2,135 | 2,179 | 0 | 0 | 0 | 0 | -0.831 ns |
| OBM-Hybrid | 4 | 2,761 | 2,347 | 0 | 0 | 0 | 0 | -3.450 ns |
| OBM-Hybrid | 8 | 7,386 | 3,707 | 0 | 0 | 0 | 0 | -8.954 ns |

## Notes

- These are real Vivado synthesis results, not estimates.
- These numbers should not be mixed with a full U200 build that includes DDR4
  IP, shell logic, ILA, traffic generation, and correctness checkers.
- The current paper-scale core model is intentionally storage-abstracted. It is
  useful for comparing control overhead under the same 5 MiB/4 GiB addressing
  scale, but it is not a replacement for full functional end-to-end synthesis.
- The 4P and 8P WNS results show that this paper-scale control model needs more
  pipeline stages before claiming 300 MHz timing closure. The most likely paths
  are cross-port rank/occupancy comparison, dynamic port-indexed muxing, and
  shared request arbitration.

## Raw CSV

```csv
design,policy_mode,ports,sram_bytes,sram_cells,ddr_bytes_log2,ddr_cells,batch_size,batch_slots,rank_width,seq_width,cell_count_width,bbq_bitmap_width,clb_luts,clb_registers,lutram,bram_tiles,uram,dsps,wns_ns,status
hestia,-1,1,5242880,81920,32,67108864,8,8388608,10,16,16,32,752,348,0,0,0,0,-0.232,ok
hestia,-1,2,5242880,81920,32,67108864,8,8388608,10,16,16,32,2067,2201,0,0,0,0,-0.298,ok
hestia,-1,4,5242880,81920,32,67108864,8,8388608,10,16,16,32,3309,2641,0,0,0,0,-3.219,ok
hestia,-1,8,5242880,81920,32,67108864,8,8388608,10,16,16,32,7031,3733,0,0,0,0,-10.467,ok
dt_hybrid,0,1,5242880,81920,32,67108864,8,8388608,10,16,16,32,746,348,0,0,0,0,-0.198,ok
dt_hybrid,0,2,5242880,81920,32,67108864,8,8388608,10,16,16,32,1937,2135,0,0,0,0,-0.158,ok
dt_hybrid,0,4,5242880,81920,32,67108864,8,8388608,10,16,16,32,2267,2267,0,0,0,0,-1.224,ok
dt_hybrid,0,8,5242880,81920,32,67108864,8,8388608,10,16,16,32,4460,3083,0,0,0,0,-7.037,ok
occamy_hybrid,1,1,5242880,81920,32,67108864,8,8388608,10,16,16,32,833,348,0,0,0,0,-1.841,ok
occamy_hybrid,1,2,5242880,81920,32,67108864,8,8388608,10,16,16,32,2152,2180,0,0,0,0,-1.763,ok
occamy_hybrid,1,4,5242880,81920,32,67108864,8,8388608,10,16,16,32,2995,2484,0,0,0,0,-3.091,ok
occamy_hybrid,1,8,5242880,81920,32,67108864,8,8388608,10,16,16,32,7229,3710,0,0,0,0,-7.261,ok
obm_hybrid,3,1,5242880,81920,32,67108864,8,8388608,10,16,16,32,788,348,0,0,0,0,0.015,ok
obm_hybrid,3,2,5242880,81920,32,67108864,8,8388608,10,16,16,32,2135,2179,0,0,0,0,-0.831,ok
obm_hybrid,3,4,5242880,81920,32,67108864,8,8388608,10,16,16,32,2761,2347,0,0,0,0,-3.450,ok
obm_hybrid,3,8,5242880,81920,32,67108864,8,8388608,10,16,16,32,7386,3707,0,0,0,0,-8.954,ok
```
