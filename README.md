# Hestia Shared Buffer

This repository contains an FPGA-oriented multi-port extension of Themis-style
scheduling-aware buffer management. The design targets a Xilinx Alveo U200-class
FPGA and uses DDR4 as the off-chip packet-buffer tier.

The repository is self-contained for RTL simulation, stripped synthesis, and a
U200 DDR-backed self-test build. No host packet injector is required: the U200
top includes an FPGA-side synthetic packet generator and rank-order checker.

## Repository Layout

```text
rtl/
  Multi-port buffer-manager RTL, per-port queues, U200 top, and AXI wrapper cell.

sim/
  Self-checking SystemVerilog testbenches.

scripts/
  Vivado simulation, stripped synthesis, U200 build, checkpoint reporting, and
  optional ILA validation scripts.
```

## Architecture

The design separates **per-port scheduling state** from **global shared storage
state**.

- Each output port owns an independent rank-ordered queue. The default DDR-backed
  core uses `hestia_port_bbq`, a two-level bitmap/bucket queue with linked
  nodes. It tracks SRAM min/max candidates and off-chip min candidates per port.
- A global buffer manager owns the shared SRAM-cell free list, DDR batch pool,
  packet descriptor table, batch metadata, and AXI DDR transaction path.
- Packets are represented by descriptors. A descriptor stores port, rank,
  sequence number, cell count, payload metadata, and either SRAM cell locations
  or `{batch_id, batch_offset}` for the DDR tier.
- Variable-size packets are represented by `cell_count`; the current U200 test
  configuration exercises packets up to `MAX_CELL_COUNT` cells.
- DDR storage is batch-oriented. The global manager fills a batch, writes it over
  AXI, reads whole batches for swap-in, and can also directly dequeue a packet
  from DDR when it is the selected per-port head.
- Output ordering is checked independently per port. There is no global rank
  arbitration between ports; shared SRAM/DDR resources are arbitrated by the
  global buffer manager.

Some signal names still use `hbm` for the off-chip tier because the original
Themis terminology was HBM-oriented. In this U200 build those paths map to DDR4.

## Main RTL Entry Points

| File | Purpose |
| --- | --- |
| `rtl/hestia_core_ddr_bbq.sv` | Main descriptor-based, DDR-backed shared-buffer core with per-port BBQ queues. |
| `rtl/hestia_port_bbq.sv` | Per-port two-level bitmap queue for SRAM/off-chip min/max selection. |
| `rtl/hestia_u200_top.sv` | U200 self-test top with synthetic generator, checker, statistics, and AXI DDR master. |
| `rtl/hestia_u200_bd_cell.v` | Block-design wrapper cell used by the Vivado U200 build script. |
| `rtl/hestia_synthetic_packet_gen.sv` | FPGA-side synthetic packet generator with configurable rank and packet-size patterns. |
| `rtl/hestia_core.sv` | Older abstract single-cell shared-buffer model. |
| `rtl/hestia_faithful_core.sv` | Markdown-faithful reference model used for algorithm-level comparison. |

## Quick Start

Vivado 2020.2 or newer with U200 board files is expected. On Windows, set
`XILINX_VIVADO` to the Vivado install root before running simulation scripts.

Run a focused per-port BBQ regression:

```bash
vivado -mode batch -source scripts/run_port_bbq_sim.tcl
```

Run the descriptor-based faithful regression:

```bash
vivado -mode batch -source scripts/run_multiport_faithful_sim.tcl
```

Run the U200 DDR exercise top:

```bash
vivado -mode batch -source scripts/run_u200_top_ddr_sim.tcl
```

Run a U200 DDR stress smoke simulation:

```bash
export HESTIA_STRESS_MAX_PACKETS=4096
export HESTIA_STRESS_SRAM_CELLS=32
export HESTIA_STRESS_BATCH_SIZE=8
export HESTIA_STRESS_BATCH_SLOTS=32
export HESTIA_STRESS_PORT_QUEUE_DEPTH=64
export HESTIA_STRESS_RANK_DIST=3
export HESTIA_STRESS_DRAIN_START_PACKETS=64
export HESTIA_STRESS_DRAIN_PERIOD_CYCLES=3
export HESTIA_STRESS_SWAP_IN_THRESHOLD=16
export HESTIA_STRESS_SWAP_OUT_THRESHOLD=24
vivado -mode batch -source scripts/run_u200_top_ddr_stress_light_sim.tcl
```

Run stripped synthesis for the DDR-backed BBQ core:

```bash
vivado -mode batch -source scripts/synth_multiport_ddr_bbq_stripped.tcl
```

Build the U200 DDR self-test bitstream:

```bash
export HESTIA_ENABLE_ILA=1
export HESTIA_ILA_LIGHT=1
export HESTIA_VIVADO_JOBS=4
vivado -mode batch -source scripts/build_u200_ddr.tcl
```

## Representative Results

The following numbers are representative results for the current RTL and scripts
on an Alveo U200 target. They are intended as reproducibility anchors; exact
timing and area can move with Vivado version, board files, constraints, and
parameter choices.

| Check | Configuration | Result |
| --- | --- | --- |
| U200 DDR exercise simulation | 8 ports, DDR AXI model, forced direct DDR dequeue and swap-in | `generated=32`, `dequeued=32`, `sram_dequeue=1`, `direct_ddr=31`, SRAM dequeue hit rate `3.12%`, `rank_errors=0`, `drop=0` |
| U200 DDR stress smoke | 4,096 packets, `SRAM_CELLS=32`, `BATCH_SIZE=8`, drain starts after 64 packets | `dequeued=4096`, `sram_dequeue=4042`, `direct_ddr_dequeue=54`, SRAM dequeue hit rate `98.68%`, `rank_errors=0`, `drop=0` |
| Stress DDR traffic | same stress-smoke run | `ddr_write_batches=23`, `ddr_read_batches=0`, `ddr_write_beats=184`, `ddr_read_beats=139`, `swap_out=5`, `swap_in=0` |
| DDR-BBQ stripped core | 4 ports, `SRAM_CELLS=16`, `BATCH_SIZE=8`, `PACKET_SLOTS=64`, OOC synthesis at 8.000 ns | `26966` CLB LUTs, `10919` CLB registers, `1380` LUTRAM, `0` BRAM, `0` URAM, `0` DSP, WNS `2.295 ns` |
| U200 DDR+ILA build | full block design with DDR4 IP and debug | `write_bitstream Complete`, routed timing met, representative full-design area `58851` CLB LUTs, `72535` CLB registers, `48.5` BRAM tiles, `0` URAM, `3` DSP |
| 4-port faithful stripped core | OOC synthesis, 5.000 ns | `9416` CLB LUTs, `5595` CLB registers, `0` BRAM, `0` URAM, `0` DSP, WNS `0.264 ns` |
| Abstract 8-port stripped core | OOC synthesis, 3.333 ns | `19623` CLB LUTs, `22169` CLB registers, `0` BRAM, `0` URAM, `0` DSP, WNS `0.215 ns` |
| Generator/checker wrapper | OOC synthesis, 3.333 ns | `11919` CLB LUTs, `8764` CLB registers, `0` BRAM, `0` URAM, `0` DSP, WNS `0.493 ns` |

The most important functional counters are:

```text
SRAM dequeue hit rate = sram_dequeue / dequeued
Correct output order  = rank_errors == 0
Packet loss           = drop == 0 for lossless test configurations
DDR activity          = ddr_write_batches/read_batches and ddr_write_beats/read_beats
```

## Tunable Parameters

The U200 DDR top and stress testbench expose the main architectural parameters:

| Parameter | Meaning |
| --- | --- |
| `PORTS` | Number of output ports. The default U200 top is 8-port. |
| `SRAM_CELLS` | Shared on-chip SRAM cell capacity. |
| `BATCH_SIZE` | Number of cells per DDR batch. |
| `BATCH_SLOTS` | Number of global DDR batch descriptors. |
| `PACKET_SLOTS` | Descriptor-table capacity. |
| `BBQ_BITMAP_WIDTH` | Width of each BBQ bitmap level. |
| `SWAP_IN_THRESHOLD` | Global SRAM occupancy threshold that enables off-chip-to-SRAM migration. |
| `SWAP_OUT_THRESHOLD` | Global SRAM occupancy threshold that triggers SRAM-to-DDR migration. |
| `MAX_CELL_COUNT` | Maximum packet size in cells for synthetic tests. |
| `RANK_DIST` | Synthetic rank distribution mode used by the generator/testbench. |
| `DRAIN_PERIOD_CYCLES` | Output drain throttling interval for congestion tests. |

The stress simulation maps these to environment variables prefixed with
`HESTIA_STRESS_`, for example `HESTIA_STRESS_MAX_PACKETS` and
`HESTIA_STRESS_DRAIN_PERIOD_CYCLES`.

## ILA Validation

After building with `HESTIA_ENABLE_ILA=1`, program the U200 and capture the
debug bus with:

```bash
export HESTIA_BUILD_ROOT=build/hestia_u200_ddr
vivado -mode batch -source scripts/hw_ila_validate_u200.tcl
```

The ILA path reports packet-generation/dequeue counters, SRAM dequeue hits,
direct DDR dequeues, rank-order errors, drops, swap counts, DDR batch counters,
and a decoded SRAM hit rate.

## Status

The current tree is a research FPGA prototype. The core paths are self-checking
in RTL simulation, and the U200 top is designed for standalone board validation
with synthetic traffic and ILA counters.
