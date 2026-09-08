`timescale 1ns/1ps

module hestia_policy_obm #(
  parameter int PORTS = 4,
  parameter int OCC_WIDTH = 16,
  localparam int PORT_W = (PORTS <= 2) ? 1 : $clog2(PORTS)
) (
  input  logic [PORTS*OCC_WIDTH-1:0] port_occ_flat,
  input  logic [PORT_W-1:0]          pkt_port,
  input  logic                       pkt_valid,
  output logic                       longest_valid,
  output logic [PORT_W-1:0]          longest_port,
  output logic [OCC_WIDTH-1:0]       longest_occupancy,
  output logic                       pkt_targets_longest
);
  function automatic logic [OCC_WIDTH-1:0] get_occ(input int port_i);
    begin
      get_occ = port_occ_flat[port_i*OCC_WIDTH +: OCC_WIDTH];
    end
  endfunction

  integer pi;
  logic [OCC_WIDTH-1:0] occ_v;
  always_comb begin
    longest_valid = 1'b0;
    longest_port = '0;
    longest_occupancy = '0;

    for (pi = 0; pi < PORTS; pi = pi + 1) begin
      occ_v = get_occ(pi);
      if (occ_v != '0 && (!longest_valid || occ_v > longest_occupancy)) begin
        longest_valid = 1'b1;
        longest_port = PORT_W'(pi);
        longest_occupancy = occ_v;
      end
    end

    pkt_targets_longest = pkt_valid && longest_valid && (pkt_port == longest_port);
  end
endmodule
