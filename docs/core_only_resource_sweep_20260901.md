# Core-Only Resource Sweep, 2026-09-01

This note records the real Vivado out-of-context synthesis results for the
Hestia resource core and DDR-aware shared-buffer baselines.

## Methodology

- Host: `user@172.22.5.106`
- Remote work directory: `/home/user/hestia_baseline_work_20260831_2320`
- Result directory: `build/core_only_port_sweep_20260901_142736`
- Tool: Vivado 2020.2
- Part: `xcu200-fsgd2104-2-e`
- Timing target: 3.333 ns, 300 MHz
- Top: `hestia_resource_core`
- Flow: out-of-context synthesis
- Counted logic: core BM/scheduler/descriptor/DDR-transaction logic
- Excluded logic: ILA, U200 shell, DDR4 IP, synthetic traffic generator,
  checkers, board-level debug harness

Capacity scales linearly with port count:

| Ports | SRAM cells | DDR batch slots | Packet descriptors |
| ---: | ---: | ---: | ---: |
| 1 | 8 | 8 | 16 |
| 2 | 16 | 16 | 32 |
| 4 | 32 | 32 | 64 |
| 8 | 64 | 64 | 128 |

## Hestia

| Design | Ports | CLB LUTs | CLB Registers | WNS @ 300 MHz |
| --- | ---: | ---: | ---: | ---: |
| Hestia | 1 | 4,791 | 2,528 | +0.710 ns |
| Hestia | 2 | 9,496 | 5,081 | +0.182 ns |
| Hestia | 4 | 18,895 | 10,344 | -0.224 ns |
| Hestia | 8 | 37,804 | 21,397 | -0.451 ns |

## DDR-Aware Baselines

All baselines use the same DDR-backed descriptor core and the same per-port
BBQ implementation. They differ only in the buffer-management policy selected
by `POLICY_MODE`.

| Design | Ports | CLB LUTs | CLB Registers | WNS @ 300 MHz |
| --- | ---: | ---: | ---: | ---: |
| DT-Hybrid | 1 | 3,972 | 2,321 | +0.560 ns |
| DT-Hybrid | 2 | 6,860 | 4,663 | +0.393 ns |
| DT-Hybrid | 4 | 15,074 | 9,575 | +0.186 ns |
| DT-Hybrid | 8 | 33,741 | 19,971 | -0.181 ns |
| Occamy-head-Hybrid | 1 | 4,379 | 2,383 | +0.570 ns |
| Occamy-head-Hybrid | 2 | 7,699 | 4,968 | +0.209 ns |
| Occamy-head-Hybrid | 4 | 17,850 | 10,128 | +0.094 ns |
| Occamy-head-Hybrid | 8 | 37,233 | 21,059 | -0.271 ns |
| Occamy-max-Hybrid | 1 | 4,219 | 2,385 | +0.414 ns |
| Occamy-max-Hybrid | 2 | 7,468 | 4,801 | +0.223 ns |
| Occamy-max-Hybrid | 4 | 18,086 | 10,196 | +0.097 ns |
| Occamy-max-Hybrid | 8 | 34,654 | 21,096 | -0.657 ns |
| OBM-Hybrid | 1 | 4,370 | 2,395 | +0.877 ns |
| OBM-Hybrid | 2 | 7,531 | 4,798 | -0.289 ns |
| OBM-Hybrid | 4 | 17,095 | 10,169 | -2.548 ns |
| OBM-Hybrid | 8 | 36,692 | 21,140 | -7.722 ns |

## Themis DDR Source Baseline

This table reports the DDR version from the upstream Themis repository:
`ddr/rtl/themis_core_stripped_top.sv`. The wrapper instantiates independent
copies of the original single-port DDR Themis core. Each copy uses
`RANK_WIDTH=6`, `SEQ_WIDTH=16`, `SRAM_DEPTH=8`, `DDR_BATCH_SIZE=8`,
`DDR_BATCH_SLOTS=8`, and `BBQ_BITMAP_WIDTH=8`, matching the per-port capacity
used in the Hestia sweep above. The run directory is
`/home/user/themis_source_eval_20260901/build/themis_ddr_source_core_sweep_20260901_181343`.

| Design | Independent cores | Total SRAM cells | Total DDR batch slots | CLB LUTs | CLB Registers | BRAM tiles | WNS @ 300 MHz |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Themis-DDR-source | 1 | 8 | 8 | 7,957 | 7,316 | 8 | +0.363 ns |
| Themis-DDR-source | 2 | 16 | 16 | 15,913 | 14,632 | 17 | +0.363 ns |
| Themis-DDR-source | 4 | 32 | 32 | 31,825 | 29,264 | 34 | +0.363 ns |
| Themis-DDR-source | 8 | 64 | 64 | 63,649 | 58,528 | 68 | +0.363 ns |

Compared with this DDR-source baseline, Hestia uses fewer LUTs and FFs in this
small OOC configuration. The main reason is that the current Hestia
resource-core is a compact descriptor-controller implementation, while the
upstream Themis-DDR core keeps a fuller single-port control path and infers BRAM
for per-core storage. At 4P and 8P, the gap also reflects Hestia's shared
multi-port design: DDR transaction logic, batch metadata, and shared buffer
accounting are amortized instead of fully replicated per port.

## Raw CSV

```csv
design,policy_mode,ports,sram_cells,batch_slots,packet_slots,clb_luts,clb_registers,wns_ns,status,log
Hestia,-1,1,8,8,16,4791,2528,0.710,ok,build/core_only_port_sweep_20260901_142736/hestia_1p/vivado.log
Hestia,-1,2,16,16,32,9496,5081,0.182,ok,build/core_only_port_sweep_20260901_142736/hestia_2p/vivado.log
Hestia,-1,4,32,32,64,18895,10344,-0.224,ok,build/core_only_port_sweep_20260901_142736/hestia_4p/vivado.log
Hestia,-1,8,64,64,128,37804,21397,-0.451,ok,build/core_only_port_sweep_20260901_142736/hestia_8p/vivado.log
DT-Hybrid,0,1,8,8,16,3972,2321,0.560,ok,build/core_only_port_sweep_20260901_142736/baseline_p0_1p/vivado.log
DT-Hybrid,0,2,16,16,32,6860,4663,0.393,ok,build/core_only_port_sweep_20260901_142736/baseline_p0_2p/vivado.log
DT-Hybrid,0,4,32,32,64,15074,9575,0.186,ok,build/core_only_port_sweep_20260901_142736/baseline_p0_4p/vivado.log
DT-Hybrid,0,8,64,64,128,33741,19971,-0.181,ok,build/core_only_port_sweep_20260901_142736/baseline_p0_8p/vivado.log
Occamy-head-Hybrid,1,1,8,8,16,4379,2383,0.570,ok,build/core_only_port_sweep_20260901_142736/baseline_p1_1p/vivado.log
Occamy-head-Hybrid,1,2,16,16,32,7699,4968,0.209,ok,build/core_only_port_sweep_20260901_142736/baseline_p1_2p/vivado.log
Occamy-head-Hybrid,1,4,32,32,64,17850,10128,0.094,ok,build/core_only_port_sweep_20260901_142736/baseline_p1_4p/vivado.log
Occamy-head-Hybrid,1,8,64,64,128,37233,21059,-0.271,ok,build/core_only_port_sweep_20260901_142736/baseline_p1_8p/vivado.log
Occamy-max-Hybrid,2,1,8,8,16,4219,2385,0.414,ok,build/core_only_port_sweep_20260901_142736/baseline_p2_1p/vivado.log
Occamy-max-Hybrid,2,2,16,16,32,7468,4801,0.223,ok,build/core_only_port_sweep_20260901_142736/baseline_p2_2p/vivado.log
Occamy-max-Hybrid,2,4,32,32,64,18086,10196,0.097,ok,build/core_only_port_sweep_20260901_142736/baseline_p2_4p/vivado.log
Occamy-max-Hybrid,2,8,64,64,128,34654,21096,-0.657,ok,build/core_only_port_sweep_20260901_142736/baseline_p2_8p/vivado.log
OBM-Hybrid,3,1,8,8,16,4370,2395,0.877,ok,build/core_only_port_sweep_20260901_142736/baseline_p3_1p/vivado.log
OBM-Hybrid,3,2,16,16,32,7531,4798,-0.289,ok,build/core_only_port_sweep_20260901_142736/baseline_p3_2p/vivado.log
OBM-Hybrid,3,4,32,32,64,17095,10169,-2.548,ok,build/core_only_port_sweep_20260901_142736/baseline_p3_4p/vivado.log
OBM-Hybrid,3,8,64,64,128,36692,21140,-7.722,ok,build/core_only_port_sweep_20260901_142736/baseline_p3_8p/vivado.log
```
