# Full-Scale External-Metadata Functional Core, 2026-09-02

This note records the first full-scale Hestia functional stripped synthesis run
after moving large metadata structures out of inline RTL arrays.

## What Changed

- Added `hestia_core_ddr_bbq_extmeta`, a functional stripped core variant that
  keeps ingress/dequeue control, per-port BBQ-style scheduling, widened
  occupancy accounting, SRAM/DDR placement decisions, migration control, and
  DDR AXI read/write transaction state machines.
- Added `hestia_extmeta_tables`, an external/abstract metadata table interface
  for:
  - descriptor table;
  - SRAM free-cell allocation/release list;
  - DDR batch append/commit/query/release metadata.
- Added `EXTERNAL_METADATA` to `hestia_resource_core`. When set to `1`, the
  wrapper instantiates the external-metadata core; when set to `0`, it keeps the
  original inline-metadata functional core.
- Widened the external-metadata path's counters to paper-scale capacity widths:
  descriptor/free counters, SRAM occupancy/free-cell counters, DDR occupancy,
  DDR free-cell counters, and per-port occupancy counters use `COUNT_W` rather
  than fixed 16-bit counters.

## Capacity

| Parameter | Value |
| --- | ---: |
| Ports | 2 |
| SRAM cells | 81,920 |
| DDR batch slots | 8,388,608 |
| DDR cells | 67,108,864 |
| Batch size | 8 cells |
| Packet descriptors | 81,920 |
| Rank width | 10 bits |
| Sequence width | 16 bits |
| Cell-count width | 16 bits |
| BBQ bitmap width | 32 bits |

The large descriptor/batch/free-cell storage itself is modeled as an external
metadata table and is not counted as core logic.

## Vivado Result

- Host: `user@172.22.5.106`
- Remote work directory: `/home/user/hestia_baseline_work_20260831_2320`
- Remote run directory:
  `build/fullscale_extmeta_functional_2p_20260902_112934`
- Local copy:
  `build/fullscale_extmeta_functional_2p_20260902_112934`
- Tool: Vivado 2020.2
- Part: `xcu200-fsgd2104-2-e`
- Flow: out-of-context synthesis
- Clock target: 3.333 ns, 300 MHz
- Top: `hestia_resource_core`
- Generic: `EXTERNAL_METADATA=1`

| Design | Ports | CLB LUTs | CLB Registers | LUTRAM | BRAM tiles | URAM | DSP | WNS @ 300 MHz |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Hestia full-scale extmeta functional stripped | 2 | 1,982 | 1,398 | 0 | 0 | 0 | 0 | -1.765 ns |

Vivado completed synthesis with 0 errors, 0 critical warnings, and 0 warnings.
The run includes one `hestia_extmeta_tables` black box, representing the
external/abstract descriptor, batch metadata, and free-cell stores.

## Interpretation

This run confirms that the full-scale `5 MiB SRAM + 4 GiB DDR` addressing
configuration is now synthesizable when large metadata structures are not
expanded into inline RTL arrays. The resource number is therefore the core
control cost around the external metadata tables, not the cost of implementing
those tables themselves in BRAM/URAM.

The 300 MHz target does not close in this first version. The failing timing
comes from unpipelined full-scale control paths; adding pipeline stages around
cross-port candidate selection, policy comparison, and metadata request issue
would be needed before using this as a timing-closed FPGA implementation.
