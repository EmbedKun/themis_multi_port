# Resource Accounting

Hestia uses two resource-accounting views because the project has two different
hardware artifacts.

The U200 validation artifact includes DDR4 IP, reset/clock infrastructure,
synthetic packet generation, rank-order checking, ILA debug, and counters.  It is
the right artifact for board bring-up and correctness validation.

The paper-comparison artifact is `hestia_resource_core`.  It keeps only the
functional ingress, egress, per-port BBQ scheduling state, shared descriptor /
SRAM / DDR-batch manager, and AXI DDR transaction interface.  Debug counters and
test generators are intentionally excluded from this top.

## Paper-Style Projection

The Themis paper reports the following FPGA core cost for one single-port
Themis core:

| Design | CLB LUTs | CLB Registers |
| --- | ---: | ---: |
| Themis paper 1P | 7,157 | 7,435 |

One paper-style projection treats Hestia as a linear per-port
Themis-equivalent cost plus a small shared-buffer overlay:

```text
Hestia_NP_LUT = N * 7157 + shared_lut(N)
Hestia_NP_FF  = N * 7435 + shared_ff(N)
shared_lut(N) = 240 + 403 * N, for N >= 2
shared_ff(N)  = 480 + 335 * N, for N >= 2
```

This model gives the following concise table:

| Design | CLB LUTs | CLB Registers | Extra Over N x Themis |
| --- | ---: | ---: | ---: |
| Themis 1P | 7,157 | 7,435 | 0 |
| Hestia 2P | 15,360 | 16,020 | +1,046 LUTs / +1,150 FFs |
| Hestia 4P | 30,480 | 31,560 | +1,852 LUTs / +1,820 FFs |
| Hestia 8P | 60,720 | 62,640 | +3,464 LUTs / +3,160 FFs |

The extra resources are the shared SRAM free-cell manager, DDR batch allocator,
descriptor ownership tables, per-port storage arbitration, and global migration
control.  They grow much more slowly than duplicating complete per-port Themis
cores.

These rows are a projection model, not Vivado-measured utilization for the
current descriptor RTL.

## Measured Resource Sweep

The following rows were produced by Vivado OOC synthesis of
`hestia_resource_core` on `xcu200-fsgd2104-2-e` with a 3.333 ns target.  This
compact sweep uses `RANK_WIDTH=6`, `SEQ_WIDTH=16`, `BBQ_BITMAP_WIDTH=8`,
`SRAM_CELLS_PER_PORT=8`, `PACKETS_PER_PORT=16`, `BATCH_SLOTS_PER_PORT=8`,
`BATCH_SIZE=8`, and `PAYLOAD_WIDTH=32`.

| Ports | CLB LUTs | CLB Registers | LUTRAM | BRAM | WNS ns | Estimated Fmax MHz | Delta vs N x Themis |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | 4,791 | 2,528 | 341 | 0 | +0.710 | 381 | -2,366 LUTs / -4,907 FFs |
| 2 | 9,496 | 5,081 | 682 | 0 | +0.182 | 317 | -4,818 LUTs / -9,789 FFs |
| 4 | 18,895 | 10,344 | 1,412 | 0 | -0.224 | 281 | -9,733 LUTs / -19,396 FFs |
| 8 | 37,804 | 21,397 | 4,112 | 0 | -0.451 | 264 | -19,452 LUTs / -38,083 FFs |

This compact configuration is smaller than `N x Themis` because it is not an
equal-capacity reimplementation of every structure in the original Themis FPGA
core.

A wider pilot configuration was also synthesized with `RANK_WIDTH=10`,
`SEQ_WIDTH=32`, `BBQ_BITMAP_WIDTH=32`, `SRAM_CELLS_PER_PORT=32`,
`PACKETS_PER_PORT=64`, `BATCH_SLOTS_PER_PORT=16`, `BATCH_SIZE=8`, and
`PAYLOAD_WIDTH=32`.

| Ports | CLB LUTs | CLB Registers | LUTRAM | BRAM | WNS ns | Estimated Fmax MHz | Delta vs N x Themis |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | 16,458 | 8,784 | 2,145 | 0 | +0.272 | 327 | +9,301 LUTs / +1,349 FFs |
| 2 | 33,062 | 17,931 | 4,788 | 0 | -0.453 | 264 | +18,748 LUTs / +3,061 FFs |

The wider pilot shows that the current descriptor RTL scales up quickly when
large bucket memories are inferred as distributed LUTRAM.  To make measured
numbers land near `N x Themis + small overlay`, the large queue tables should be
mapped to BRAM/SRAM-style memories and the per-port queue should be refactored
closer to the original Themis pipeline.

## Reproducing The Raw RTL Number

Run the core-only synthesis flow:

```bash
vivado -mode batch -source scripts/synth_hestia_resource_core.tcl
```

Then generate the paper-style projection table from the Vivado reports:

```bash
python scripts/report_paper_resources.py \
  --ports 2 \
  --clock-period-ns 3.333 \
  --util-report build/hestia_resource_core_2p/resource_core_utilization_synth.rpt \
  --timing-report build/hestia_resource_core_2p/resource_core_timing_summary_synth.rpt \
  --output-dir build/hestia_resource_core_2p
```

Do not compare the full U200 DDR+ILA build directly against the Themis paper
table; that full build is a validation system, not the paper-cost core.
