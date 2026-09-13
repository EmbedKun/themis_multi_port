`timescale 1ns/1ps

module hestia_policy_dt #(
  parameter int PORTS = 4,
  parameter int CELL_COUNT_WIDTH = 4,
  parameter int OCC_WIDTH = 16,
  parameter int ALPHA_SHIFT_WIDTH = 4,
  parameter int STATIC_ALPHA_SHIFT = -1,
  parameter bit FAST_SMALL_CELL_COMPARE = 1'b0,
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

  function automatic logic admit_under_threshold(
    input logic [OCC_WIDTH-1:0] occ_i,
    input logic [OCC_WIDTH-1:0] cells_i,
    input logic [OCC_WIDTH-1:0] threshold_i
  );
    logic [4:0] low_sum_v;
    begin
      if ((STATIC_ALPHA_SHIFT == 0) && FAST_SMALL_CELL_COMPARE && (OCC_WIDTH > 4)) begin
        low_sum_v = {1'b0, occ_i[3:0]} + {1'b0, cells_i[3:0]};
        admit_under_threshold =
          (occ_i[OCC_WIDTH-1:4] < threshold_i[OCC_WIDTH-1:4]) ||
          ((occ_i[OCC_WIDTH-1:4] == threshold_i[OCC_WIDTH-1:4]) &&
           !low_sum_v[4] && (low_sum_v[3:0] <= threshold_i[3:0]));
      end else begin
        admit_under_threshold = ((occ_i + cells_i) <= threshold_i);
      end
    end
  endfunction

  generate
    if (STATIC_ALPHA_SHIFT >= 0) begin : gen_static_alpha_shift
      always_comb begin
        threshold_wide = {{(THRESH_W-OCC_WIDTH){1'b0}}, free_cells} << STATIC_ALPHA_SHIFT;
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
                    admit_under_threshold(port_occ, cells, threshold);
      end
    end else begin : gen_dynamic_alpha_shift
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
                    admit_under_threshold(port_occ, cells, threshold);
      end
    end
  endgenerate
endmodule
