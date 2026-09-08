`timescale 1ns/1ps

module hestia_policy_occamy #(
  parameter int PORTS = 4,
  parameter int CELL_COUNT_WIDTH = 4,
  parameter int OCC_WIDTH = 16,
  parameter int ALPHA_SHIFT_WIDTH = 4,
  localparam int PORT_W = (PORTS <= 2) ? 1 : $clog2(PORTS)
) (
  input  logic                         clk,
  input  logic                         resetn,
  input  logic [ALPHA_SHIFT_WIDTH-1:0] cfg_alpha_shift,
  input  logic                         reclaim_enable,
  input  logic                         reclaim_fire,
  input  logic                         pkt_valid,
  input  logic [PORT_W-1:0]            pkt_port,
  input  logic [CELL_COUNT_WIDTH-1:0]  pkt_cell_count,
  input  logic [OCC_WIDTH-1:0]         free_cells,
  input  logic [PORTS*OCC_WIDTH-1:0]   port_occ_flat,
  output logic                         pkt_admit,
  output logic [OCC_WIDTH-1:0]         threshold,
  output logic [PORTS-1:0]             over_threshold_bitmap,
  output logic                         reclaim_valid,
  output logic [PORT_W-1:0]            reclaim_port
);
  logic [PORT_W-1:0] rr_ptr_q;

  function automatic logic [OCC_WIDTH-1:0] get_occ(input int port_i);
    begin
      get_occ = port_occ_flat[port_i*OCC_WIDTH +: OCC_WIDTH];
    end
  endfunction

  function automatic logic [OCC_WIDTH-1:0] cell_count_occ(
    input logic [CELL_COUNT_WIDTH-1:0] cells_i
  );
    begin
      cell_count_occ = {{(OCC_WIDTH-CELL_COUNT_WIDTH){1'b0}}, cells_i};
    end
  endfunction

  localparam int THRESH_W = OCC_WIDTH + ALPHA_SHIFT_WIDTH + 1;

  logic [THRESH_W-1:0] threshold_wide;
  logic [OCC_WIDTH-1:0] cells;
  logic [OCC_WIDTH-1:0] pkt_port_occ;

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

    over_threshold_bitmap = '0;
    for (pi = 0; pi < PORTS; pi = pi + 1) begin
      over_threshold_bitmap[pi] = (get_occ(pi) > threshold);
    end

    reclaim_valid = 1'b0;
    reclaim_port = rr_ptr_q;
    for (si = 0; si < PORTS; si = si + 1) begin
      idx = int'(rr_ptr_q) + si;
      if (idx >= PORTS) begin
        idx = idx - PORTS;
      end
      if (!reclaim_valid && over_threshold_bitmap[idx]) begin
        reclaim_valid = reclaim_enable;
        reclaim_port = PORT_W'(idx);
      end
    end

    cells = cell_count_occ(pkt_cell_count);
    pkt_port_occ = get_occ(int'(pkt_port));
    pkt_admit = pkt_valid &&
                (pkt_cell_count != '0) &&
                (free_cells >= cells) &&
                ((pkt_port_occ + cells) <= threshold);
  end

  always_ff @(posedge clk) begin
    if (!resetn) begin
      rr_ptr_q <= '0;
    end else if (reclaim_fire) begin
      if (reclaim_port == PORT_W'(PORTS-1)) begin
        rr_ptr_q <= '0;
      end else begin
        rr_ptr_q <= reclaim_port + 1'b1;
      end
    end
  end
endmodule
