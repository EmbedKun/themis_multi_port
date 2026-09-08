# Hestia ASIC Handoff

This directory packages the logic-only handoff flow for 28nm PPA evaluation.
It is intended for ASIC synthesis/timing/power estimation of the Hestia shared
buffer manager and the baseline policies under a common interface.

## Scope

The synthesis top is:

```text
rtl/hestia_asic_core.sv
```

Included in the logic-only core:

- per-port rank scheduler/BBQ control
- Hestia shared SRAM/DDR buffer-management control
- descriptor allocation and release control
- SRAM free-cell allocation and release control
- active DDR batch-window control
- DDR address generation and AXI-style read/write transaction FSMs
- policy logic for Hestia, DT-Hybrid, Occamy-Hybrid, OBM-Hybrid, and
  Hybrid-Themis

Excluded from logic-only synthesis:

- packet payload SRAM bit cells
- descriptor table SRAM bit cells
- descriptor free-list SRAM bit cells
- SRAM free-cell-list bit cells
- active DDR batch-window SRAM bit cells
- external DDR controller, PHY, and DRAM array
- U200 shell, DDR4 IP, ILA, synthetic packet generator, and checkers

Large on-chip tables instantiate `hestia_asic_sram_1r1w` black boxes when using
`hestia_asic_core`. For a full macro-inclusive PPA run, replace that black-box
module with 28nm SRAM compiler macros and include the macro timing/power `.lib`
files in the ASIC flow.

## Default Configuration

The default handoff configuration matches the paper-scale FPGA resource setup:

| Parameter | Value |
| --- | ---: |
| SRAM payload capacity | 5 MiB |
| Cell size | 64 B / 512 bit |
| SRAM cells | 81,920 |
| DDR logical capacity | 4 GiB |
| DDR batch size | 8 cells |
| DDR batch slots | 8,388,608 |
| Packet descriptors | 81,920 |
| Rank width | 10 bit |
| Sequence width | 16 bit |
| Cell-count width | 27 bit |
| Payload tag width in control RTL | 32 bit |

## Policy Selection

Use `POLICY_MODE` to select the design under the same top-level interface:

| Design | `POLICY_MODE` |
| --- | ---: |
| Hestia | -1 |
| DT-Hybrid | 0 |
| Occamy-Hybrid | 1 |
| OBM-Hybrid | 3 |
| Hybrid-Themis | 4 |

## Quick Logic-Only Sweep With Vivado

This is a reproducibility smoke flow, not the final ASIC PPA flow. It checks
that the RTL elaborates with SRAM black boxes and that no FPGA BRAM/URAM payload
memories are synthesized.

Run from the repository root:

```bash
VIVADO_BIN=/tools/Xilinx/Vivado/2020.2/bin/vivado \
bash asic_handoff/scripts/run_vivado_logic_only_sweep.sh
```

Useful options:

```bash
# Sweep only 4-port Hestia and Hybrid-Themis at 300 MHz target.
HESTIA_ASIC_PORTS_LIST="4" \
HESTIA_ASIC_SWEEP_DESIGNS="hestia,hybrid_themis" \
VIVADO_BIN=/tools/Xilinx/Vivado/2020.2/bin/vivado \
bash asic_handoff/scripts/run_vivado_logic_only_sweep.sh

# Use a 200 MHz target.
HESTIA_ASIC_CLK_PERIOD_NS=5.000 \
VIVADO_BIN=/tools/Xilinx/Vivado/2020.2/bin/vivado \
bash asic_handoff/scripts/run_vivado_logic_only_sweep.sh
```

The sweep writes:

```text
build/asic_logic_only_<timestamp>/resource_summary.csv
build/asic_logic_only_<timestamp>/resource_summary.md
```

The expected logic-only memory columns are `BRAM=0` and `URAM=0`, with several
black-box `hestia_asic_sram_1r1w` instances left in the netlist.

On Windows:

```powershell
powershell -ExecutionPolicy Bypass -File asic_handoff\scripts\run_vivado_logic_only_sweep.ps1
```

## Synopsys DC Template

The ASIC team should set the 28nm standard-cell and SRAM macro libraries before
running the DC template. Run from the repository root:

```bash
export TARGET_LIBRARY="/path/to/stdcell_tt_0p9v_25c.db"
export LINK_LIBRARY="* /path/to/stdcell_tt_0p9v_25c.db /path/to/sram_macros.db"
export HESTIA_ASIC_PORTS=4
export HESTIA_ASIC_POLICY_MODE=-1
export HESTIA_ASIC_SDC="asic_handoff/constraints/hestia_300mhz.sdc"
export HESTIA_ASIC_REPORT_DIR="build/dc_hestia_4p_300mhz"
dc_shell -f asic_handoff/scripts/run_dc_logic_only.tcl | tee build/dc_hestia_4p_300mhz.log
```

For a 200 MHz fallback run:

```bash
export HESTIA_ASIC_SDC="asic_handoff/constraints/hestia_200mhz.sdc"
export HESTIA_ASIC_REPORT_DIR="build/dc_hestia_4p_200mhz"
dc_shell -f asic_handoff/scripts/run_dc_logic_only.tcl | tee build/dc_hestia_4p_200mhz.log
```

## What To Run

Recommended PPA matrix:

| Axis | Values |
| --- | --- |
| Design | Hestia, DT-Hybrid, Occamy-Hybrid, OBM-Hybrid, Hybrid-Themis |
| Ports | 1, 2, 4, 8 |
| Clock | 300 MHz primary, 200 MHz fallback |
| PVT | ASIC team's normal TT/SS/FF corners |
| Area mode | logic-only first; macro-inclusive as a separate table |
| Power mode | vectorless first; SAIF/VCD annotated after RTL workloads are selected |

For power, use representative RTL workloads before gate-level annotation:

- uniform-rank traffic
- skewed-rank traffic
- high SRAM-pressure traffic
- output-port congestion
- DDR-heavy traffic
- SRAM-hit-heavy traffic

Functional simulations should be run with the normal RTL memories and DDR model
before generating SAIF/VCD. The black-box ASIC top is for synthesis PPA only.

## Files

| File | Purpose |
| --- | --- |
| `filelists/hestia_asic_logic_only.f` | RTL filelist for the ASIC handoff top |
| `constraints/hestia_300mhz.sdc` | Primary 300 MHz timing constraint |
| `constraints/hestia_200mhz.sdc` | Fallback 200 MHz timing constraint |
| `scripts/run_vivado_logic_only_synth.tcl` | Single Vivado logic-only synthesis run |
| `scripts/run_vivado_logic_only_sweep.sh` | Vivado sweep over designs and port counts |
| `scripts/run_dc_logic_only.tcl` | Synopsys DC template for 28nm PPA |
| `memory_wrappers/README.md` | SRAM black-box interface contract |
