# Baseline Comparison Plan

This document defines how to compare Hestia against shared-buffer management
baselines while reusing the Hestia per-port BBQ.

## Goal

Compare the hardware cost and behavior of four designs under the same ports,
rank width, descriptor width, cell size, SRAM capacity, traffic generator, and
dequeue pressure:

- Hestia: per-port BBQ plus shared SRAM/DDR batch manager.
- BBQ + DT: per-port BBQ plus Dynamic Threshold admission.
- BBQ + Occamy: per-port BBQ plus DT admission and round-robin preemptive reclaim.
- BBQ + OBM: per-port BBQ plus LQD-style longest-queue push-out.
- Hybrid Themis: per-port Themis/BBQ scheduling with a DT-partitioned SRAM tier
  and shared DDR spillover.

## Resource Boundaries

Use three reporting boundaries and never mix them in one table:

1. Policy-only cost: synthesize only the buffer-management decision logic.
   This isolates the shared-buffer algorithm overhead.
2. Core subsystem cost: instantiate the common per-port BBQs, descriptor table,
   free-cell allocator, and one policy module. Exclude synthetic generator,
   checkers, ILA, and DDR4 IP.
3. Board validation cost: full U200 build with clock/reset infrastructure, DDR4,
   generator/checker, and optional ILA. This is for bring-up, not paper-style
   algorithm comparison.

The main paper table should use boundary 2. Boundary 1 explains what extra logic
each policy adds beyond the common BBQ and descriptor store.

## Remote Measured Results

The following numbers were measured on the remote U200 Vivado host with Vivado
2020.2, part `xcu200-fsgd2104-2-e`. They use the boundary-2 baseline shared
core, with `PORTS=4`, `RANK_WIDTH=6`, `SRAM_CELLS=32`, `PACKET_SLOTS=64`, and
`BBQ_BITMAP_WIDTH=8`. These are real synthesis/implementation results, not paper
projections.

Post-synthesis at 300 MHz target (`3.333 ns`):

| Baseline | LUT | FF | LUTRAM | BRAM | URAM | DSP | WNS ns |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| BBQ + DT | 2821 | 4783 | 560 | 0 | 0 | 0 | -0.476 |
| BBQ + Occamy head-drop | 3539 | 4826 | 560 | 0 | 0 | 0 | -3.321 |
| BBQ + Occamy max-rank | 3673 | 4898 | 624 | 0 | 0 | 0 | -3.321 |
| BBQ + OBM | 3800 | 4927 | 624 | 0 | 0 | 0 | -3.708 |

Hestia boundary-2 resource core, using the same `PORTS=4`, `RANK_WIDTH=6`,
`SRAM_CELLS=32`, `PACKET_SLOTS=64`, and `BBQ_BITMAP_WIDTH=8`, plus
`BATCH_SIZE=8` and `BATCH_SLOTS=32` for the DDR batch manager:

| Design | Target | LUT | FF | LUTRAM | BRAM | URAM | DSP | WNS ns | Notes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Hestia resource core | 300 MHz synth | 18895 | 10344 | 1412 | 0 | 0 | 0 | -0.224 | Raw RTL core, no generator/checker/ILA/MIG |
| Hestia resource core | 200 MHz post-route | 18707 | 10343 | 1412 | 0 | 0 | 0 | 0.354 | Routed OOC core |

### DDR-Aware Baselines

The SRAM-only baselines isolate policy logic, but they are not a full hybrid
buffer comparison against Hestia. The DDR-aware variants keep the same per-port
`hestia_port_bbq` and descriptor/batch substrate as Hestia, and change only the
SRAM-residency policy:

- DT-DDR: packets rejected by DT admission are appended to a DDR batch instead
  of being dropped.
- Occamy-DDR: packets rejected by DT admission are appended to DDR; proactive
  reclaim moves an over-threshold SRAM packet to DDR.
- OBM-DDR: push-out victims move from SRAM to DDR; an incoming packet that OBM
  would drop because it targets the longest queue is appended to DDR.
- Hybrid-Themis-DDR: each port keeps its own Themis-style rank queue, while SRAM
  admission is gated by a per-port dynamic threshold. Packets above the local
  SRAM threshold spill to DDR; over-threshold SRAM packets can be migrated out,
  and under-threshold ports can swap DDR packets back into SRAM.

In all DDR-aware baseline cases the BBQ is updated with `ADD_SRAM`, `ADD_HBM`,
`MOVE_SRAM_TO_HBM`, `REMOVE_SRAM`, or `REMOVE_HBM`, so dequeue can select the
minimum-rank packet across SRAM and DDR for each port. The current baseline DDR
mode disables Hestia's watermark-driven swap-in/swap-out policy, leaving direct
DDR dequeue as the DDR read path.

Functional simulation, with `PORTS=4`, `SRAM_CELLS=8`, `BATCH_SIZE=4`,
`BATCH_SLOTS=128`, `PACKET_SLOTS=128`, 96 variable-size packets, and all ports
drained after the pressure phase:

| Baseline | Generated | Dequeued | SRAM Admit | DDR Admit | SRAM->DDR | Direct DDR Deq | Drop | DDR Write Batches | DDR Read Beats |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| DT-DDR | 96 | 96 | 6 | 90 | 0 | 90 | 0 | 62 | 184 |
| Occamy head-DDR | 96 | 96 | 6 | 90 | 2 | 92 | 0 | 63 | 187 |
| Occamy max-DDR | 96 | 96 | 6 | 90 | 2 | 92 | 0 | 63 | 187 |
| OBM-DDR | 96 | 96 | 74 | 22 | 70 | 92 | 0 | 84 | 185 |

DDR-aware post-synthesis at 300 MHz target (`3.333 ns`), using the same
paper-boundary configuration as the Hestia resource core:

| Baseline | LUT | FF | LUTRAM | BRAM | URAM | DSP | WNS ns |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| DT-DDR | 15074 | 9575 | 1204 | 0 | 0 | 0 | 0.186 |
| Occamy head-DDR | 17850 | 10128 | 1412 | 0 | 0 | 0 | 0.094 |
| Occamy max-DDR | 18086 | 10196 | 1412 | 0 | 0 | 0 | 0.097 |
| OBM-DDR | 17095 | 10169 | 1412 | 0 | 0 | 0 | -2.548 |

Post-route at 200 MHz target (`5.000 ns`):

| Baseline | LUT | FF | LUTRAM | BRAM | URAM | DSP | Post-route WNS ns |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| BBQ + DT | 2765 | 4783 | 560 | 0 | 0 | 0 | 0.354 |
| BBQ + Occamy head-drop | 3578 | 4828 | 560 | 0 | 0 | 0 | -0.449 |
| BBQ + Occamy max-rank | 3688 | 4906 | 624 | 0 | 0 | 0 | -0.603 |
| BBQ + OBM | 3827 | 4927 | 624 | 0 | 0 | 0 | -0.839 |

Post-route at 166.7 MHz target (`6.000 ns`) for the non-DT baselines:

| Baseline | LUT | FF | LUTRAM | BRAM | URAM | DSP | Post-route WNS ns |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| BBQ + Occamy head-drop | 3553 | 4826 | 560 | 0 | 0 | 0 | 0.083 |
| BBQ + Occamy max-rank | 3663 | 4898 | 624 | 0 | 0 | 0 | 0.057 |
| BBQ + OBM | 3784 | 4927 | 624 | 0 | 0 | 0 | 0.047 |

Full-board U200 validation boundary, including DDR4 MIG, JTAG AXI, reset/clock
infrastructure, synthetic generator/checker, and light ILA:

| Design | Configuration | LUT | FF | LUTRAM | BRAM | URAM | DSP | WNS ns | Board Result |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Hestia DDR+ILA | 4 ports, `SRAM_CELLS=32`, `BATCH_SIZE=4`, `BATCH_SLOTS=16`, `DRAIN_START_PACKETS=30`, `RANK_DIST=3`, 188 MHz | 40207 | 40943 | 4807 | 48.5 | 0 | 3 | 0.124 | ILA `done` captured `generated=128`, `dequeued=128`, `sram_dequeue=107`, `direct_ddr=21`, `rank_errors=0`, `drop=0` |

## Common Hardware Shell

All baselines should share:

- `hestia_port_bbq` as the per-port rank-ordered queue.
- One descriptor table storing port, rank, sequence, cell count, payload, and
  SRAM cell list head/base metadata.
- One global free-cell allocator.
- Variable-size packets represented by `cell_count`.
- Per-port independent dequeue with rank-order checking.
- The same synthetic workloads and backpressure model.

Normal dequeue always removes the minimum rank from that port. Eviction should
remove the maximum rank when adapting a BM policy to a rank-scheduled queue,
because dropping the minimum rank would preferentially discard the packet that
should leave first.

## Baseline Semantics

### BBQ + DT

DT is non-preemptive. It admits a packet for port `p` only when enough free cells
exist and the port occupancy remains below a dynamic threshold:

```text
threshold = alpha * free_cells
admit = free_cells >= cell_count &&
        port_occ[p] + cell_count <= threshold
```

For synthesis, `alpha` should be a power-of-two shift. For performance
experiments, sweep `alpha`.

### BBQ + Occamy

Occamy uses DT for admission, with a larger `alpha`, and adds a reactive reclaim
path:

- Compare every port occupancy with the DT threshold.
- Build an over-threshold bitmap.
- Pick one over-threshold port by round-robin.
- Use a fixed-priority arbiter so normal dequeue wins over reclaim.
- Reclaim one packet from the selected port when spare memory access bandwidth
  exists.

The Occamy-faithful action is head drop. For a rank-scheduled BBQ, also implement
and test the rank-aware variant that drops the maximum-rank packet. The latter is
the fairer comparison against Hestia because it preserves the rank scheduler's
semantic preference.

### BBQ + OBM

OBM is LQD-style push-out. With one priority class:

- If enough free cells exist, admit the incoming packet.
- If the buffer is full or cannot fit the packet, find the port with the largest
  occupancy.
- If the incoming packet targets that longest port, drop the incoming packet.
- Otherwise evict enough cells from the longest port and admit the incoming
  packet.

For the Hestia-compatible rank queue, the victim should be the maximum-rank
descriptor in the longest port. A more paper-faithful OBM variant can add a
pipelined demand tree and address-assignment tree for `PORTS` parallel ingress
lanes, but the first hardware baseline can use the same ingress concurrency as
Hestia so the comparison is not biased by different front-end widths.

## Experiments

Run the same regression matrix for every design:

- Ports: 2, 4, 8.
- SRAM capacity: small, default, and pressure-heavy settings.
- Packet size: fixed 1-cell, bimodal, and random variable-cell packets.
- Rank distributions: uniform, skewed, Zipf-like, monotonic/adversarial.
- Load: underload, line-rate pressure, and oversubscription.
- Egress congestion: per-port backpressure and long blocked-output episodes.
- DT/Occamy alpha sweep.

Collect:

- LUT, FF, LUTRAM, BRAM, URAM, DSP, WNS/Fmax.
- Generated, admitted, dropped, dequeued.
- Per-port rank errors.
- Per-port and global occupancy.
- Eviction/reclaim/push-out count.
- SRAM dequeue hit rate for Hestia.
- DDR write/read batches and beats for Hestia.
- Admission stall cycles and dequeue stall cycles.
- Jain fairness over admitted cells and dropped cells.

## Implementation Order

1. Factor a common SRAM-only descriptor/free-cell shell for baselines.
2. Implement `hestia_policy_dt`.
3. Implement `hestia_policy_occamy` with faithful head-drop and rank-aware
   max-rank reclaim modes.
4. Implement `hestia_policy_obm` with longest-port selection and max-rank victim
   eviction.
5. Implement `hestia_policy_hybrid_themis` with DT-partitioned SRAM and
   Themis-style per-port queueing.
6. Add common testbench and Python/Tcl report parser.
7. Run simulations first, then OOC synthesis for policy-only and core-subsystem
   boundaries.

## Open Decisions

- Whether the main paper comparison should use one ingress packet per cycle, as
  in the current Hestia RTL, or `PORTS` parallel ingress lanes, as in OBM's switch
  pipeline model.
- Whether Occamy should be reported in strict head-drop mode, rank-aware
  max-rank mode, or both.
- Whether DT/Occamy/OBM should remain SRAM-only baselines or also receive a
  shared DDR spillover adapter. The SRAM-only version is cleaner for comparing
  shared-buffer algorithms; the DDR-adapted version is closer to Hestia's board
  artifact but less faithful to those papers.
