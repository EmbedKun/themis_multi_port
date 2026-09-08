# Memory Macro Boundary

The ASIC handoff flow sets `USE_ASIC_MEMORY_MACROS=1` through the
`hestia_asic_core` top. In that mode, large SRAM-like structures instantiate the
black-box module `hestia_asic_sram_1r1w` declared in
`rtl/hestia_core_ddr_bbq_extmeta.sv`.

The black-box port contract is:

```systemverilog
module hestia_asic_sram_1r1w #(
  parameter int DATA_W,
  parameter int ADDR_W,
  parameter int DEPTH
) (
  input  logic              clk,
  input  logic              we,
  input  logic [ADDR_W-1:0] wr_addr,
  input  logic [DATA_W-1:0] wr_data,
  input  logic [ADDR_W-1:0] rd_addr,
  output logic [DATA_W-1:0] rd_data
);
endmodule
```

For logic-only area/timing, leave this module as a black box. For full macro
PPA, replace it with SRAM compiler macro instances and add the macro `.lib` and
power models in the ASIC synthesis/signoff flow.
