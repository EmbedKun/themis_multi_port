`timescale 1ns/1ps

module themis_replicated_eval_top #(
  parameter int CORES = 1,
  parameter int DATA_WIDTH = 512,
  parameter int KEEP_WIDTH = DATA_WIDTH / 8,
  parameter int CELL_PTR_WIDTH = 3,
  parameter int HEAP_BITMAP_WIDTH = 8,
  localparam int HEAP_NUM_LEVELS = 2,
  localparam int HEAP_NUM_PRIORITIES = HEAP_BITMAP_WIDTH ** HEAP_NUM_LEVELS,
  localparam int HEAP_PRIORITY_WIDTH = $clog2(HEAP_NUM_PRIORITIES)
) (
  input  logic                                      clk,
  input  logic                                      rst,

  input  logic [CORES*DATA_WIDTH-1:0]               s_axis_pkt_tdata,
  input  logic [CORES-1:0]                          s_axis_pkt_tvalid,
  input  logic [CORES-1:0]                          s_axis_pkt_tlast,
  input  logic [CORES*KEEP_WIDTH-1:0]               s_axis_pkt_tkeep,
  input  logic [CORES*HEAP_PRIORITY_WIDTH-1:0]      s_axis_pkt_rank,
  output logic [CORES-1:0]                          s_axis_pkt_tready,

  output logic [CORES*DATA_WIDTH-1:0]               m_axis_pkt_tdata,
  output logic [CORES-1:0]                          m_axis_pkt_tvalid,
  output logic [CORES-1:0]                          m_axis_pkt_tlast,
  output logic [CORES*KEEP_WIDTH-1:0]               m_axis_pkt_tkeep,
  input  logic [CORES-1:0]                          m_axis_pkt_tready,

  output logic [CORES-1:0]                          bbq_ready,
  output logic [CORES*32-1:0]                       dbg_free_cells,
  output logic [CORES*32-1:0]                       dbg_queued_packets,
  output logic [CORES*32-1:0]                       dbg_completed_packets
);

  genvar g;
  generate
    for (g = 0; g < CORES; g = g + 1) begin : gen_themis_core
      themis_linked_buffer_manager #(
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH),
        .CELL_PTR_WIDTH(CELL_PTR_WIDTH),
        .HEAP_BITMAP_WIDTH(HEAP_BITMAP_WIDTH),
        .HEAP_MAX_NUM_ENTRIES((1 << CELL_PTR_WIDTH) - 1)
      ) core_i (
        .clk(clk),
        .rst(rst),
        .s_axis_pkt_tdata(s_axis_pkt_tdata[g*DATA_WIDTH +: DATA_WIDTH]),
        .s_axis_pkt_tvalid(s_axis_pkt_tvalid[g]),
        .s_axis_pkt_tlast(s_axis_pkt_tlast[g]),
        .s_axis_pkt_tkeep(s_axis_pkt_tkeep[g*KEEP_WIDTH +: KEEP_WIDTH]),
        .s_axis_pkt_rank(s_axis_pkt_rank[g*HEAP_PRIORITY_WIDTH +: HEAP_PRIORITY_WIDTH]),
        .s_axis_pkt_tready(s_axis_pkt_tready[g]),
        .m_axis_pkt_tdata(m_axis_pkt_tdata[g*DATA_WIDTH +: DATA_WIDTH]),
        .m_axis_pkt_tvalid(m_axis_pkt_tvalid[g]),
        .m_axis_pkt_tlast(m_axis_pkt_tlast[g]),
        .m_axis_pkt_tkeep(m_axis_pkt_tkeep[g*KEEP_WIDTH +: KEEP_WIDTH]),
        .m_axis_pkt_tready(m_axis_pkt_tready[g]),
        .bbq_ready(bbq_ready[g]),
        .dbg_free_cells(dbg_free_cells[g*32 +: 32]),
        .dbg_queued_packets(dbg_queued_packets[g*32 +: 32]),
        .dbg_completed_packets(dbg_completed_packets[g*32 +: 32])
      );
    end
  endgenerate

endmodule
