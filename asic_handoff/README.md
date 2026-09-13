# Hestia ASIC PPA Handoff

## Task

Please evaluate 28nm ASIC PPA for the Hestia shared-buffer core and four
baseline schemes.

Report these data:

- Area: combinational area, sequential area, total cell area.
- Timing: WNS/TNS and achieved frequency.
- Power: internal, switching, leakage, and total power.
- Matrix: five schemes x 4 ports.

Default target clock: `1.000 ns` / `1 GHz`.

Core-only rule: synthesize only scheduler/buffer-management/control logic.
Do not synthesize SRAM bit cells, the DDR controller, the DDR PHY, or DRAM.

## Synthesis Top

Top:

```text
rtl/hestia_asic_core.sv
```

Filelist:

```text
asic_handoff/filelists/hestia_asic_logic_only.f
```

Default SDC:

```text
asic_handoff/constraints/hestia_1ghz.sdc
```

The top leaves five SRAM-like storage blocks as `hestia_asic_sram_1r1w`
black boxes. The default logical capacity is `5 MiB` SRAM payload and `4 GiB`
off-chip buffer address space.

## Schemes

Use `HESTIA_ASIC_POLICY_MODE` to select the scheme:

| Scheme | Mode |
| --- | ---: |
| Hestia | -1 |
| DT-Hybrid | 0 |
| Occamy-Hybrid | 1 |
| OBM-Hybrid | 3 |
| Hybrid-Themis | 4 |

## Run One DC Job

Run from the repository root:

```bash
export TARGET_LIBRARY="/path/to/stdcell_28nm.db"
export LINK_LIBRARY="* /path/to/stdcell_28nm.db"
export HESTIA_ASIC_PORTS=4
export HESTIA_ASIC_POLICY_MODE=-1
export HESTIA_ASIC_SDC="asic_handoff/constraints/hestia_1ghz.sdc"
export HESTIA_ASIC_REPORT_DIR="build/dc_hestia_4p_1ghz"

dc_shell -f asic_handoff/scripts/run_dc_logic_only.tcl | tee build/dc_hestia_4p_1ghz.log
```

Outputs:

```text
build/dc_hestia_4p_1ghz/check_design.rpt
build/dc_hestia_4p_1ghz/area_hier.rpt
build/dc_hestia_4p_1ghz/timing.rpt
build/dc_hestia_4p_1ghz/power.rpt
build/dc_hestia_4p_1ghz/hestia_asic_core_mapped.v
```

## Run All Schemes

Run the default 4-port comparison:

```bash
export TARGET_LIBRARY="/path/to/stdcell_28nm.db"
export LINK_LIBRARY="* /path/to/stdcell_28nm.db"

bash asic_handoff/scripts/run_dc_logic_only_sweep.sh
```

Useful overrides:

```bash
# Only run Hestia and Hybrid-Themis.
HESTIA_ASIC_SWEEP_DESIGNS="hestia,hybrid_themis" \
bash asic_handoff/scripts/run_dc_logic_only_sweep.sh

# Run a relaxed 300 MHz sweep if 1 GHz does not close.
HESTIA_ASIC_SDC="asic_handoff/constraints/hestia_300mhz.sdc" \
HESTIA_ASIC_CLOCK_TAG="300mhz" \
bash asic_handoff/scripts/run_dc_logic_only_sweep.sh
```

Sweep outputs are placed under:

```text
build/dc_logic_only_<clock>_<timestamp>/<scheme>_<ports>p/
```

Each run directory contains `check_design.rpt`, `area_hier.rpt`, `timing.rpt`,
`power.rpt`, and `hestia_asic_core_mapped.v`.

## Vivado Smoke Check

This is only for RTL/filelist sanity checking. It is not ASIC PPA.

```bash
VIVADO_BIN=/tools/Xilinx/Vivado/2020.2/bin/vivado \
bash asic_handoff/scripts/run_vivado_logic_only_sweep.sh
```

Expected memory result in Vivado smoke: `LUTRAM=0`, `BRAM=0`, `URAM=0`, and
five `hestia_asic_sram_1r1w` black boxes.
