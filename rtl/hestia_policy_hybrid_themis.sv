`timescale 1ns/1ps

module hestia_policy_hybrid_themis #(
  parameter int PORTS = 4,
  parameter int CELL_COUNT_WIDTH = 4,
  parameter int OCC_WIDTH = 16,
  parameter int ALPHA_SHIFT_WIDTH = 4,
  localparam int PORT_W = (PORTS <= 2) ? 1 : $clog2(PORTS)
) (
  input  logic                         clk,
  input  logic                         resetn,
  input  logic [ALPHA_SHIFT_WIDTH-1:0] cfg_alpha_shift,
  input  logic                         pkt_valid,
  input  logic [PORT_W-1:0]            pkt_port,
  input  logic [CELL_COUNT_WIDTH-1:0]  pkt_cell_count,
  input  logic [OCC_WIDTH-1:0]         free_cells,
  input  logic [PORTS*OCC_WIDTH-1:0]   sram_occ_flat,
  input  logic [PORTS*OCC_WIDTH-1:0]   ddr_occ_flat,
  output logic                         pkt_admit,
  output logic [OCC_WIDTH-1:0]         threshold,
  output logic [PORTS-1:0]             over_threshold_bitmap,
  output logic [PORTS-1:0]             under_threshold_bitmap,
  output logic                         swapout_hint_valid,
  output logic [PORT_W-1:0]            swapout_hint_port,
  output logic                         swapin_hint_valid,
  output logic [PORT_W-1:0]            swapin_hint_port,
  output logic [63:0]                  digest
);
  localparam int THRESH_W = OCC_WIDTH + ALPHA_SHIFT_WIDTH + 1;
  logic [PORT_W-1:0] rr_ptr_q;
  logic [THRESH_W-1:0] threshold_wide;
  logic [OCC_WIDTH-1:0] cells;
  logic [OCC_WIDTH-1:0] pkt_sram_occ;
  logic [OCC_WIDTH-1:0] pkt_effective_threshold;
  logic [OCC_WIDTH-1:0] sram_occ_v [0:PORTS-1];
  logic [OCC_WIDTH-1:0] ddr_occ_v [0:PORTS-1];
  logic [OCC_WIDTH-1:0] local_target_q [0:PORTS-1];
  logic [OCC_WIDTH-1:0] local_total_q [0:PORTS-1];
  logic [PORTS-1:0] local_pressure_q;
  logic [PORTS-1:0] local_has_ddr_q;

  function automatic logic [OCC_WIDTH-1:0] cell_count_occ(
    input logic [CELL_COUNT_WIDTH-1:0] cells_i
  );
    begin
      cell_count_occ = {{(OCC_WIDTH-CELL_COUNT_WIDTH){1'b0}}, cells_i};
    end
  endfunction

  function automatic logic [OCC_WIDTH-1:0] sat_add_occ(
    input logic [OCC_WIDTH-1:0] a,
    input logic [OCC_WIDTH-1:0] b
  );
    logic [OCC_WIDTH:0] sum_v;
    begin
      sum_v = {1'b0, a} + {1'b0, b};
      sat_add_occ = sum_v[OCC_WIDTH] ? {OCC_WIDTH{1'b1}} : sum_v[OCC_WIDTH-1:0];
    end
  endfunction

  function automatic logic [15:0] low16_occ(
    input logic [OCC_WIDTH-1:0] value_i
  );
    begin
      if (OCC_WIDTH >= 16) begin
        low16_occ = value_i[15:0];
      end else begin
        low16_occ = {{(16-OCC_WIDTH){1'b0}}, value_i};
      end
    end
  endfunction

  integer pi;
  integer si;
  integer idx;
  always_comb begin
    threshold_wide = {{(THRESH_W-OCC_WIDTH){1'b0}}, free_cells} << cfg_alpha_shift;
    if (|threshold_wide[THRESH_W-1:OCC_WIDTH]) begin
      threshold = '1;
    end else begin
      threshold = threshold_wide[OCC_WIDTH-1:0];
    end

    for (pi = 0; pi < PORTS; pi = pi + 1) begin
      sram_occ_v[pi] = sram_occ_flat[pi*OCC_WIDTH +: OCC_WIDTH];
      ddr_occ_v[pi] = ddr_occ_flat[pi*OCC_WIDTH +: OCC_WIDTH];
      over_threshold_bitmap[pi] = sram_occ_v[pi] > threshold;
      under_threshold_bitmap[pi] = (sram_occ_v[pi] < threshold) && (ddr_occ_v[pi] != '0);
    end

    swapout_hint_valid = 1'b0;
    swapout_hint_port = rr_ptr_q;
    swapin_hint_valid = 1'b0;
    swapin_hint_port = rr_ptr_q;
    for (si = 0; si < PORTS; si = si + 1) begin
      idx = int'(rr_ptr_q) + si;
      if (idx >= PORTS) begin
        idx = idx - PORTS;
      end
      if (!swapout_hint_valid && over_threshold_bitmap[idx]) begin
        swapout_hint_valid = 1'b1;
        swapout_hint_port = PORT_W'(idx);
      end
      if (!swapin_hint_valid && under_threshold_bitmap[idx]) begin
        swapin_hint_valid = 1'b1;
        swapin_hint_port = PORT_W'(idx);
      end
    end

    cells = cell_count_occ(pkt_cell_count);
    pkt_sram_occ = sram_occ_v[int'(pkt_port)];
    pkt_effective_threshold = (local_target_q[int'(pkt_port)] == '0) ?
                              threshold : local_target_q[int'(pkt_port)];
    pkt_admit = pkt_valid &&
                (pkt_cell_count != '0) &&
                (free_cells >= cells) &&
                (sat_add_occ(pkt_sram_occ, cells) <= pkt_effective_threshold);

    digest = {48'd0, low16_occ(threshold)};
    for (pi = 0; pi < PORTS; pi = pi + 1) begin
      digest = digest ^
               ({48'd0, low16_occ(sram_occ_v[pi])} << (pi % 8)) ^
               ({48'd0, low16_occ(ddr_occ_v[pi])} << ((pi + 3) % 8)) ^
               ({48'd0, low16_occ(local_target_q[pi])} << ((pi + 5) % 8)) ^
               ({48'd0, low16_occ(local_total_q[pi])} << ((pi + 7) % 8)) ^
               (64'(pi) << 2) ^
               {62'd0, local_pressure_q[pi], local_has_ddr_q[pi]};
    end
  end

  always_ff @(posedge clk) begin
    if (!resetn) begin
      rr_ptr_q <= '0;
      local_pressure_q <= '0;
      local_has_ddr_q <= '0;
      for (int qi = 0; qi < PORTS; qi = qi + 1) begin
        local_target_q[qi] <= '0;
        local_total_q[qi] <= '0;
      end
    end else begin
      if (swapout_hint_valid) begin
        rr_ptr_q <= (swapout_hint_port == PORT_W'(PORTS-1)) ? '0 : (swapout_hint_port + 1'b1);
      end else if (swapin_hint_valid) begin
        rr_ptr_q <= (swapin_hint_port == PORT_W'(PORTS-1)) ? '0 : (swapin_hint_port + 1'b1);
      end

      for (int qi = 0; qi < PORTS; qi = qi + 1) begin
        local_target_q[qi] <= threshold;
        local_total_q[qi] <= sat_add_occ(sram_occ_v[qi], ddr_occ_v[qi]);
        local_pressure_q[qi] <= over_threshold_bitmap[qi];
        local_has_ddr_q[qi] <= (ddr_occ_v[qi] != '0);
      end
    end
  end
endmodule
