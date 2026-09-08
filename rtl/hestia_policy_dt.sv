`timescale 1ns/1ps

module hestia_policy_dt #(
  parameter int PORTS = 4,
  parameter int CELL_COUNT_WIDTH = 4,
  parameter int OCC_WIDTH = 16,
  parameter int ALPHA_SHIFT_WIDTH = 4,
  localparam int PORT_W = (PORTS <= 2) ? 1 : $clog2(PORTS)
) (
  input  logic [ALPHA_SHIFT_WIDTH-1:0] cfg_alpha_shift,
  input  logic                         pkt_valid,
  input  logic [PORT_W-1:0]            pkt_port,
  input  logic [CELL_COUNT_WIDTH-1:0]  pkt_cell_count,
  input  logic [OCC_WIDTH-1:0]         free_cells,
  input  logic [PORTS*OCC_WIDTH-1:0]   port_occ_flat,
  output logic                         pkt_admit,
  output logic [OCC_WIDTH-1:0]         threshold
);
  function automatic logic [OCC_WIDTH-1:0] get_occ(input logic [PORT_W-1:0] port_i);
    begin
      get_occ = port_occ_flat[int'(port_i)*OCC_WIDTH +: OCC_WIDTH];
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
  logic [OCC_WIDTH-1:0] port_occ;
  logic [OCC_WIDTH-1:0] cells;

  always_comb begin
    threshold_wide = {{(THRESH_W-OCC_WIDTH){1'b0}}, free_cells} << cfg_alpha_shift;
    if (|threshold_wide[THRESH_W-1:OCC_WIDTH]) begin
      threshold = '1;
    end else begin
      threshold = threshold_wide[OCC_WIDTH-1:0];
    end

    port_occ = get_occ(pkt_port);
    cells = cell_count_occ(pkt_cell_count);
    pkt_admit = pkt_valid &&
                (pkt_cell_count != '0) &&
                (free_cells >= cells) &&
                ((port_occ + cells) <= threshold);
  end
endmodule
