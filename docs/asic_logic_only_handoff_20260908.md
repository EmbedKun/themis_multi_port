# ASIC Logic-Only Handoff Smoke

Date: 2026-09-08

This note records the local smoke checks for the ASIC handoff flow. The ASIC
handoff top is `rtl/hestia_asic_core.sv`.

## Synthesis Boundary

The logic-only top includes the Hestia/shared-buffer control plane, per-port
BBQ scheduling logic, policy logic, descriptor/free-list control, active DDR
batch-window control, and AXI-style DDR transaction FSMs.

The following storage bodies are intentionally excluded from synthesis:

- packet payload SRAM
- descriptor table SRAM
- descriptor free-list SRAM
- SRAM free-cell-list SRAM
- active DDR batch-window SRAM
- DDR controller, DDR PHY, and DRAM array

When `hestia_asic_core` is used, these on-chip tables instantiate
`hestia_asic_sram_1r1w` black boxes. Macro-inclusive ASIC PPA should replace
that wrapper with 28nm SRAM compiler macros and include the corresponding
timing/power libraries.

## Vivado Logic-Only Smoke

Command:

```powershell
powershell -ExecutionPolicy Bypass -File asic_handoff\scripts\run_vivado_logic_only_sweep.ps1 -ClockPeriodNs 1.000
```

Output directory:

```text
build/asic_logic_only_20260908_202647
```

Results:

| Design | Ports | CLB LUTs | CLB Registers | LUTRAM | BRAM | URAM | DSP | WNS ns | Black-box memories |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| DT-Hybrid | 4 | 4272 | 2789 | 0 | 0 | 0 | 0 | -4.646 | 5 |
| Hestia | 4 | 4948 | 2708 | 0 | 0 | 0 | 0 | -7.182 | 5 |
| Hybrid-Themis | 4 | 6105 | 2998 | 0 | 0 | 0 | 0 | -9.123 | 5 |
| OBM-Hybrid | 4 | 4343 | 2789 | 0 | 0 | 0 | 0 | -6.354 | 5 |
| Occamy-Hybrid | 4 | 4358 | 2789 | 0 | 0 | 0 | 0 | -5.628 | 5 |

The unresolved-memory critical warning in this smoke run is expected: the
memory instances are deliberately left as black boxes. The Vivado WNS values
are an FPGA out-of-context smoke signal only and should not be reported as ASIC
timing.

## FPGA Memory Branch Regression

The normal resource-core path was also synthesized once with RTL memories
enabled to confirm the ASIC black-box option did not break the FPGA memory
branch.

Command:

```powershell
$env:HESTIA_RESOURCE_PORTS='1'
$env:HESTIA_RESOURCE_POLICY_MODE='-1'
$env:HESTIA_RESOURCE_DESIGN_NAME='Hestia'
$env:HESTIA_RESOURCE_EXTERNAL_METADATA='1'
D:\Xilinx\Vivado\2020.2\bin\vivado.bat -mode batch -source scripts\synth_hestia_resource_core.tcl -tclargs build\fpga_memory_branch_smoke_1p 3.333
```

Result:

```text
Hestia-1P raw resource-core: LUT=818 FF=571 LUTRAM=0 BRAM=14 URAM=8 DSP=0 WNS=-1.326
```

This regression intentionally uses the FPGA memory implementation, so BRAM/URAM
are nonzero there. It is a sanity check for the non-ASIC path, not the ASIC
handoff accounting mode.
