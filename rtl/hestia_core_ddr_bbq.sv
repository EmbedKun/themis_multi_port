`timescale 1ns/1ps

import hestia_pkg::*;

module hestia_core_ddr_bbq #(
  parameter int PORTS = 8,
  parameter int RANK_WIDTH = 10,
  parameter int SEQ_WIDTH = 32,
  parameter int PAYLOAD_WIDTH = 64,
  parameter int CELL_COUNT_WIDTH = 4,
  parameter int AXI_ADDR_WIDTH = 64,
  parameter int AXI_DATA_WIDTH = 512,
  parameter int AXI_ID_WIDTH = 4,
  parameter int SRAM_CELLS = 64,
  parameter int BATCH_SIZE = 8,
  parameter int BATCH_SLOTS = 16,
  parameter int PACKET_SLOTS = 128,
  parameter int BBQ_BITMAP_WIDTH = (RANK_WIDTH <= 8) ? 16 : 32,
  parameter int POLICY_MODE = -1,
  parameter int POLICY_ALPHA_SHIFT = 0,
  parameter int POLICY_ALPHA_SHIFT_WIDTH = 4,
  parameter bit ENABLE_DDR_META_CHECK = 1'b0,
  parameter logic [AXI_ADDR_WIDTH-1:0] DDR_BASE_ADDR = 64'h0,
  localparam int PORT_W = (PORTS <= 2) ? 1 : $clog2(PORTS),
  localparam int SRAM_SLOT_W = (SRAM_CELLS <= 2) ? 1 : $clog2(SRAM_CELLS),
  localparam int BATCH_ID_W = (BATCH_SLOTS <= 2) ? 1 : $clog2(BATCH_SLOTS),
  localparam int BATCH_OFF_W = (BATCH_SIZE <= 2) ? 1 : $clog2(BATCH_SIZE),
  localparam int DESC_W = (PACKET_SLOTS <= 2) ? 1 : $clog2(PACKET_SLOTS),
  localparam int AXI_KEEP_WIDTH = AXI_DATA_WIDTH / 8
) (
  input  logic                             clk,
  input  logic                             resetn,
  input  logic                             enable,
  input  logic [15:0]                      cfg_swap_in_threshold,
  input  logic [15:0]                      cfg_swap_out_threshold,

  input  logic                             s_pkt_valid,
  output logic                             s_pkt_ready,
  input  logic [PORT_W-1:0]                s_pkt_port,
  input  logic [RANK_WIDTH-1:0]            s_pkt_rank,
  input  logic [SEQ_WIDTH-1:0]             s_pkt_seq,
  input  logic [CELL_COUNT_WIDTH-1:0]      s_pkt_cell_count,
  input  logic [PAYLOAD_WIDTH-1:0]         s_pkt_payload,

  input  logic [PORTS-1:0]                 dequeue_enable,
  output logic [PORTS-1:0]                 m_pkt_valid,
  input  logic [PORTS-1:0]                 m_pkt_ready,
  output logic [PORTS*RANK_WIDTH-1:0]      m_pkt_rank,
  output logic [PORTS*SEQ_WIDTH-1:0]       m_pkt_seq,
  output logic [PORTS*CELL_COUNT_WIDTH-1:0] m_pkt_cell_count,
  output logic [PORTS*PAYLOAD_WIDTH-1:0]   m_pkt_payload,

  output logic [AXI_ID_WIDTH-1:0]           m_axi_awid,
  output logic [AXI_ADDR_WIDTH-1:0]         m_axi_awaddr,
  output logic [7:0]                        m_axi_awlen,
  output logic [2:0]                        m_axi_awsize,
  output logic [1:0]                        m_axi_awburst,
  output logic                              m_axi_awlock,
  output logic [3:0]                        m_axi_awcache,
  output logic [2:0]                        m_axi_awprot,
  output logic [3:0]                        m_axi_awqos,
  output logic                              m_axi_awvalid,
  input  logic                              m_axi_awready,
  output logic [AXI_DATA_WIDTH-1:0]         m_axi_wdata,
  output logic [AXI_KEEP_WIDTH-1:0]         m_axi_wstrb,
  output logic                              m_axi_wlast,
  output logic                              m_axi_wvalid,
  input  logic                              m_axi_wready,
  input  logic [AXI_ID_WIDTH-1:0]           m_axi_bid,
  input  logic [1:0]                        m_axi_bresp,
  input  logic                              m_axi_bvalid,
  output logic                              m_axi_bready,
  output logic [AXI_ID_WIDTH-1:0]           m_axi_arid,
  output logic [AXI_ADDR_WIDTH-1:0]         m_axi_araddr,
  output logic [7:0]                        m_axi_arlen,
  output logic [2:0]                        m_axi_arsize,
  output logic [1:0]                        m_axi_arburst,
  output logic                              m_axi_arlock,
  output logic [3:0]                        m_axi_arcache,
  output logic [2:0]                        m_axi_arprot,
  output logic [3:0]                        m_axi_arqos,
  output logic                              m_axi_arvalid,
  input  logic                              m_axi_arready,
  input  logic [AXI_ID_WIDTH-1:0]           m_axi_rid,
  input  logic [AXI_DATA_WIDTH-1:0]         m_axi_rdata,
  input  logic [1:0]                        m_axi_rresp,
  input  logic                              m_axi_rlast,
  input  logic                              m_axi_rvalid,
  output logic                              m_axi_rready,

  output logic [31:0]                      stat_generated,
  output logic [31:0]                      stat_dequeued,
  output logic [31:0]                      stat_sram_admit,
  output logic [31:0]                      stat_hbm_admit,
  output logic [31:0]                      stat_swap_out,
  output logic [31:0]                      stat_swap_in,
  output logic [31:0]                      stat_direct_hbm_dequeue,
  output logic [31:0]                      stat_drop,
  output logic [31:0]                      stat_batch_submit,
  output logic [31:0]                      stat_ddr_write_beats,
  output logic [31:0]                      stat_ddr_read_beats,
  output logic [31:0]                      stat_ddr_write_batches,
  output logic [31:0]                      stat_ddr_read_batches,
  output logic [15:0]                      dbg_global_sram_occupancy,
  output logic [15:0]                      dbg_global_hbm_occupancy,
  output logic [PORTS*16-1:0]              dbg_sram_count_flat,
  output logic [PORTS*16-1:0]              dbg_hbm_count_flat,
  output logic [15:0]                      dbg_open_batch_cells,
  output logic [7:0]                       dbg_ddr_state,
  output logic                             dbg_ddr_wr_error,
  output logic                             dbg_ddr_rd_error
);
  typedef enum logic [4:0] {
    ST_IDLE,
    ST_ADMISSION,
    ST_ADMIT_COMMIT_SRAM,
    ST_SWAPOUT_BUILD,
    ST_STAGE_SRAM_TO_HBM,
    ST_SWAPIN_SCAN,
    ST_SWAPIN_COMMIT,
    ST_MIGRATE_COMMIT,
    ST_SELECTOR_REFRESH,
    ST_DEQ_DDR_PREP,
    ST_DEQ_DDR_WAIT_COMMIT,
    ST_DEQ_DDR_ADDR,
    ST_DEQ_DDR_DATA,
    ST_DEQ_DDR_COMMIT,
    ST_SWAPIN_DDR_PREP,
    ST_SWAPIN_DDR_WAIT_COMMIT,
    ST_SWAPIN_DDR_ADDR,
    ST_SWAPIN_DDR_DRAIN
  } state_t;

  typedef enum logic [1:0] {
    WR_IDLE,
    WR_ADDR,
    WR_DATA,
    WR_RESP
  } wr_state_t;

  localparam int POLICY_THEMIS = -1;
  localparam int POLICY_DT = 0;
  localparam int POLICY_OCCAMY_HEAD = 1;
  localparam int POLICY_OCCAMY_MAX = 2;
  localparam int POLICY_OBM = 3;

  localparam int SELECT_REFRESH_CYCLES = PORTS + 3;
  localparam int REFRESH_COUNT_W = (SELECT_REFRESH_CYCLES <= 2) ? 1 : $clog2(SELECT_REFRESH_CYCLES);
  localparam logic [REFRESH_COUNT_W-1:0] SELECT_REFRESH_LAST = SELECT_REFRESH_CYCLES - 1;

  state_t state_q;
  state_t refresh_return_q;
  logic [REFRESH_COUNT_W-1:0] refresh_count_q;

  logic [PORT_W-1:0] action_port_q;
  logic [RANK_WIDTH-1:0] action_rank_q;
  logic [SEQ_WIDTH-1:0] action_seq_q;
  logic [CELL_COUNT_WIDTH-1:0] action_cell_count_q;
  logic [PAYLOAD_WIDTH-1:0] action_payload_q;

  logic [BATCH_ID_W-1:0] swapin_batch_q;
  logic [BATCH_OFF_W:0] swapin_offset_q;
  logic [BATCH_ID_W-1:0] swapin_commit_batch_q;
  logic [BATCH_OFF_W-1:0] swapin_commit_offset_q;
  logic [DESC_W-1:0] swapin_commit_desc_q;
  logic [15:0] swapin_commit_cells_q;

  logic desc_valid [0:PACKET_SLOTS-1];
  (* ram_style = "distributed" *) mp_loc_t desc_loc [0:PACKET_SLOTS-1];
  (* ram_style = "distributed" *) logic [PORT_W-1:0] desc_port [0:PACKET_SLOTS-1];
  (* ram_style = "distributed" *) logic [RANK_WIDTH-1:0] desc_rank [0:PACKET_SLOTS-1];
  (* ram_style = "distributed" *) logic [SEQ_WIDTH-1:0] desc_seq [0:PACKET_SLOTS-1];
  (* ram_style = "distributed" *) logic [CELL_COUNT_WIDTH-1:0] desc_cell_count [0:PACKET_SLOTS-1];
  (* ram_style = "distributed" *) logic [PAYLOAD_WIDTH-1:0] desc_payload [0:PACKET_SLOTS-1];
  (* ram_style = "distributed" *) logic [SRAM_SLOT_W-1:0] desc_sram_cell [0:PACKET_SLOTS-1][0:BATCH_SIZE-1];
  (* ram_style = "distributed" *) logic [BATCH_ID_W-1:0] desc_batch_id [0:PACKET_SLOTS-1];
  (* ram_style = "distributed" *) logic [BATCH_OFF_W-1:0] desc_batch_offset [0:PACKET_SLOTS-1];

  logic [DESC_W-1:0] desc_free_list [0:PACKET_SLOTS-1];
  logic [DESC_W-1:0] desc_free_rd_q;
  logic [DESC_W-1:0] desc_free_wr_q;
  logic [15:0] desc_free_count_q;

  logic [SRAM_SLOT_W-1:0] sram_free_list [0:SRAM_CELLS-1];
  logic [SRAM_SLOT_W-1:0] sram_free_rd_q;
  logic [SRAM_SLOT_W-1:0] sram_free_wr_q;
  logic [15:0] sram_free_count_q;

  logic batch_cell_valid [0:BATCH_SLOTS-1][0:BATCH_SIZE-1];
  (* ram_style = "distributed" *) logic [DESC_W-1:0] batch_cell_desc [0:BATCH_SLOTS-1][0:BATCH_SIZE-1];
  logic [15:0] batch_valid_count [0:BATCH_SLOTS-1];
  logic [BATCH_OFF_W:0] batch_fill_count [0:BATCH_SLOTS-1];
  logic batch_committed [0:BATCH_SLOTS-1];
  logic batch_write_pending [0:BATCH_SLOTS-1];
  logic [BATCH_ID_W-1:0] batch_free_list [0:BATCH_SLOTS-1];
  logic [BATCH_ID_W-1:0] batch_free_rd_q;
  logic [BATCH_ID_W-1:0] batch_free_wr_q;
  logic [15:0] batch_free_count_q;
  logic open_batch_valid_q;
  logic [BATCH_ID_W-1:0] open_batch_id_q;
  logic [BATCH_OFF_W:0] open_batch_fill_q;
  logic [15:0] open_batch_valid_count_q;

  logic [15:0] sram_count_q [0:PORTS-1];
  logic [15:0] hbm_count_q [0:PORTS-1];
  logic [PORTS*16-1:0] policy_sram_occ_flat_c;
  logic [POLICY_ALPHA_SHIFT_WIDTH-1:0] policy_alpha_shift_c;
  logic policy_admit_c;
  logic [15:0] policy_threshold_c;
  logic [PORTS-1:0] policy_over_threshold_c;
  logic policy_reclaim_valid_c;
  logic [PORT_W-1:0] policy_reclaim_port_c;
  logic policy_reclaim_fire_q;
  logic obm_longest_valid_c;
  logic [PORT_W-1:0] obm_longest_port_c;
  logic [15:0] obm_longest_occupancy_c;
  logic obm_pkt_targets_longest_c;

  wr_state_t wr_state_q;
  logic [BATCH_ID_W-1:0] wr_batch_q;
  logic [BATCH_OFF_W:0] wr_beat_q;
  logic [AXI_ADDR_WIDTH-1:0] wr_addr_q;
  logic [BATCH_ID_W-1:0] wr_scan_ptr_q;

  logic [PORT_W-1:0] ddr_deq_port_q;
  logic [DESC_W-1:0] ddr_deq_desc_q;
  logic [15:0] ddr_deq_cells_q;
  logic [BATCH_ID_W-1:0] ddr_deq_batch_q;
  logic [BATCH_OFF_W-1:0] ddr_deq_offset_q;
  logic [BATCH_ID_W-1:0] ddr_wait_batch_q;
  logic [BATCH_OFF_W:0] rd_beat_q;
  logic [AXI_ADDR_WIDTH-1:0] rd_addr_q;
  logic [BATCH_ID_W-1:0] rd_batch_q;
  logic ddr_wr_error_q;
  logic ddr_rd_error_q;
  logic ddr_r_direct_last_c;
  logic ddr_r_swapin_last_c;
  logic ddr_r_final_ready_c;
  logic ddr_r_accept_c;

  logic bbq_cmd_valid [0:PORTS-1];
  mp_bbq_cmd_t bbq_cmd_op [0:PORTS-1];
  logic [DESC_W-1:0] bbq_cmd_desc [0:PORTS-1];
  logic [RANK_WIDTH-1:0] bbq_cmd_rank [0:PORTS-1];
  logic [SEQ_WIDTH-1:0] bbq_cmd_seq [0:PORTS-1];
  logic [CELL_COUNT_WIDTH-1:0] bbq_cmd_cell_count [0:PORTS-1];
  logic [BATCH_ID_W-1:0] bbq_cmd_batch_id [0:PORTS-1];
  logic [BATCH_OFF_W-1:0] bbq_cmd_batch_offset [0:PORTS-1];
  logic bbq_cmd_ready [0:PORTS-1];
  logic bbq_ready_q [0:PORTS-1];
  logic all_bbq_ready_q;
  logic bbq_initialized_q;

  logic bbq_sram_min_valid [0:PORTS-1];
  logic [DESC_W-1:0] bbq_sram_min_desc [0:PORTS-1];
  logic [RANK_WIDTH-1:0] bbq_sram_min_rank [0:PORTS-1];
  logic [SEQ_WIDTH-1:0] bbq_sram_min_seq [0:PORTS-1];
  logic [CELL_COUNT_WIDTH-1:0] bbq_sram_min_cell_count [0:PORTS-1];
  logic bbq_sram_max_valid [0:PORTS-1];
  logic [DESC_W-1:0] bbq_sram_max_desc [0:PORTS-1];
  logic [RANK_WIDTH-1:0] bbq_sram_max_rank [0:PORTS-1];
  logic [SEQ_WIDTH-1:0] bbq_sram_max_seq [0:PORTS-1];
  logic [CELL_COUNT_WIDTH-1:0] bbq_sram_max_cell_count [0:PORTS-1];
  logic bbq_hbm_min_valid [0:PORTS-1];
  logic [DESC_W-1:0] bbq_hbm_min_desc [0:PORTS-1];
  logic [RANK_WIDTH-1:0] bbq_hbm_min_rank [0:PORTS-1];
  logic [SEQ_WIDTH-1:0] bbq_hbm_min_seq [0:PORTS-1];
  logic [CELL_COUNT_WIDTH-1:0] bbq_hbm_min_cell_count [0:PORTS-1];
  logic [BATCH_ID_W-1:0] bbq_hbm_min_batch_id [0:PORTS-1];
  logic [BATCH_OFF_W-1:0] bbq_hbm_min_batch_offset [0:PORTS-1];
  logic [15:0] bbq_sram_occupancy [0:PORTS-1];
  logic [15:0] bbq_hbm_occupancy [0:PORTS-1];

  logic cand_sram_min_valid_q [0:PORTS-1];
  logic [DESC_W-1:0] cand_sram_min_desc_q [0:PORTS-1];
  logic [RANK_WIDTH-1:0] cand_sram_min_rank_q [0:PORTS-1];
  logic [SEQ_WIDTH-1:0] cand_sram_min_seq_q [0:PORTS-1];
  logic cand_sram_max_valid_q [0:PORTS-1];
  logic [DESC_W-1:0] cand_sram_max_desc_q [0:PORTS-1];
  logic [RANK_WIDTH-1:0] cand_sram_max_rank_q [0:PORTS-1];
  logic [SEQ_WIDTH-1:0] cand_sram_max_seq_q [0:PORTS-1];
  logic [CELL_COUNT_WIDTH-1:0] cand_sram_max_cell_count_q [0:PORTS-1];
  logic cand_hbm_min_valid_q [0:PORTS-1];
  logic [DESC_W-1:0] cand_hbm_min_desc_q [0:PORTS-1];
  logic [RANK_WIDTH-1:0] cand_hbm_min_rank_q [0:PORTS-1];
  logic [SEQ_WIDTH-1:0] cand_hbm_min_seq_q [0:PORTS-1];
  logic [BATCH_ID_W-1:0] cand_hbm_min_batch_id_q [0:PORTS-1];
  logic [BATCH_OFF_W-1:0] cand_hbm_min_batch_offset_q [0:PORTS-1];

  logic mask_sram_min_valid_q [0:PORTS-1];
  logic [DESC_W-1:0] mask_sram_min_desc_q [0:PORTS-1];
  logic [RANK_WIDTH-1:0] mask_sram_min_rank_q [0:PORTS-1];
  logic [SEQ_WIDTH-1:0] mask_sram_min_seq_q [0:PORTS-1];
  logic mask_sram_max_valid_q [0:PORTS-1];
  logic [DESC_W-1:0] mask_sram_max_desc_q [0:PORTS-1];
  logic [RANK_WIDTH-1:0] mask_sram_max_rank_q [0:PORTS-1];
  logic [SEQ_WIDTH-1:0] mask_sram_max_seq_q [0:PORTS-1];
  logic [CELL_COUNT_WIDTH-1:0] mask_sram_max_cell_count_q [0:PORTS-1];
  logic mask_hbm_min_valid_q [0:PORTS-1];
  logic [DESC_W-1:0] mask_hbm_min_desc_q [0:PORTS-1];
  logic [RANK_WIDTH-1:0] mask_hbm_min_rank_q [0:PORTS-1];
  logic [SEQ_WIDTH-1:0] mask_hbm_min_seq_q [0:PORTS-1];
  logic [BATCH_ID_W-1:0] mask_hbm_min_batch_id_q [0:PORTS-1];

  logic sram_min_valid_c [0:PORTS-1];
  logic [DESC_W-1:0] sram_min_desc_c [0:PORTS-1];
  logic sram_max_valid_c [0:PORTS-1];
  logic [DESC_W-1:0] sram_max_desc_c [0:PORTS-1];
  logic hbm_min_valid_c [0:PORTS-1];
  logic [DESC_W-1:0] hbm_min_desc_c [0:PORTS-1];

  logic port_deq_req_valid_c [0:PORTS-1];
  logic [DESC_W-1:0] port_deq_req_desc_c [0:PORTS-1];
  logic store_read_grant_valid_c;
  logic [PORT_W-1:0] store_read_grant_port_c;
  logic [DESC_W-1:0] store_read_grant_desc_c;
  logic store_read_grant_valid_q;
  logic [PORT_W-1:0] store_read_grant_port_q;
  logic [DESC_W-1:0] store_read_grant_desc_q;
  logic [PORT_W-1:0] store_read_rr_q;

  logic [15:0] global_sram_c;
  logic [15:0] global_hbm_c;
  logic all_bbq_ready_c;
  logic water_swapout_pending_c;
  logic water_swapin_pending_c;

  logic sel_record_valid_q;
  logic [PORT_W-1:0] sel_record_port_q;
  logic [DESC_W-1:0] sel_record_desc_q;
  logic [BATCH_ID_W-1:0] sel_record_batch_q;
  logic [15:0] sel_record_first_rank_q;
  logic [RANK_WIDTH-1:0] sel_record_second_rank_q;
  logic [SEQ_WIDTH-1:0] sel_record_seq_q;
  logic sel_swapout_valid_q;
  logic [PORT_W-1:0] sel_swapout_port_q;
  logic [DESC_W-1:0] sel_swapout_desc_q;
  logic [15:0] sel_swapout_first_rank_q;
  logic [CELL_COUNT_WIDTH-1:0] sel_swapout_cell_count_q;
  logic sel_sram_max_valid_q [0:PORTS-1];
  logic [DESC_W-1:0] sel_sram_max_desc_q [0:PORTS-1];
  logic [RANK_WIDTH-1:0] sel_sram_max_rank_q [0:PORTS-1];
  logic [SEQ_WIDTH-1:0] sel_sram_max_seq_q [0:PORTS-1];
  logic [CELL_COUNT_WIDTH-1:0] sel_sram_max_cell_count_q [0:PORTS-1];
  logic sel_water_swapout_pending_q;
  logic sel_water_swapin_pending_q;

  logic [PORT_W-1:0] select_scan_port_q;
  logic select_record_valid_q;
  logic [PORT_W-1:0] select_record_port_q;
  logic [DESC_W-1:0] select_record_desc_q;
  logic [BATCH_ID_W-1:0] select_record_batch_q;
  logic [15:0] select_record_first_rank_q;
  logic [RANK_WIDTH-1:0] select_record_second_rank_q;
  logic [SEQ_WIDTH-1:0] select_record_seq_q;
  logic select_swapout_valid_q;
  logic [PORT_W-1:0] select_swapout_port_q;
  logic [DESC_W-1:0] select_swapout_desc_q;
  logic [15:0] select_swapout_first_rank_q;
  logic [CELL_COUNT_WIDTH-1:0] select_swapout_cell_count_q;
  logic [RANK_WIDTH-1:0] select_swapout_rank_q;
  logic [SEQ_WIDTH-1:0] select_swapout_seq_q;

  logic [RANK_WIDTH-1:0] out_rank_q [0:PORTS-1];
  logic [SEQ_WIDTH-1:0] out_seq_q [0:PORTS-1];
  logic [CELL_COUNT_WIDTH-1:0] out_cell_count_q [0:PORTS-1];
  logic [PAYLOAD_WIDTH-1:0] out_payload_q [0:PORTS-1];

  logic migrate_valid_q;
  logic [DESC_W-1:0] migrate_desc_q;
  logic migrate_count_as_swap_q;
  state_t migrate_return_q;

  logic [DESC_W-1:0] stage_sram_desc_q;
  logic [15:0] stage_sram_cells_q;
  logic stage_sram_count_as_swap_q;
  logic stage_sram_drop_on_fail_q;
  state_t stage_sram_return_q;

  genvar gp;
  generate
    for (gp = 0; gp < PORTS; gp = gp + 1) begin : g_out
      assign m_pkt_rank[gp*RANK_WIDTH +: RANK_WIDTH] = out_rank_q[gp];
      assign m_pkt_seq[gp*SEQ_WIDTH +: SEQ_WIDTH] = out_seq_q[gp];
      assign m_pkt_cell_count[gp*CELL_COUNT_WIDTH +: CELL_COUNT_WIDTH] = out_cell_count_q[gp];
      assign m_pkt_payload[gp*PAYLOAD_WIDTH +: PAYLOAD_WIDTH] = out_payload_q[gp];
      assign dbg_sram_count_flat[gp*16 +: 16] = sram_count_q[gp];
      assign dbg_hbm_count_flat[gp*16 +: 16] = hbm_count_q[gp];
      assign policy_sram_occ_flat_c[gp*16 +: 16] = sram_count_q[gp];

      hestia_port_bbq #(
        .RANK_WIDTH(RANK_WIDTH),
        .SEQ_WIDTH(SEQ_WIDTH),
        .CELL_COUNT_WIDTH(CELL_COUNT_WIDTH),
        .BATCH_SIZE(BATCH_SIZE),
        .BATCH_SLOTS(BATCH_SLOTS),
        .PACKET_SLOTS(PACKET_SLOTS),
        .BBQ_BITMAP_WIDTH(BBQ_BITMAP_WIDTH)
      ) port_bbq (
        .clk(clk),
        .resetn(resetn),
        .cmd_valid(bbq_cmd_valid[gp]),
        .cmd_ready(bbq_cmd_ready[gp]),
        .cmd_op(bbq_cmd_op[gp]),
        .cmd_desc(bbq_cmd_desc[gp]),
        .cmd_rank(bbq_cmd_rank[gp]),
        .cmd_seq(bbq_cmd_seq[gp]),
        .cmd_cell_count(bbq_cmd_cell_count[gp]),
        .cmd_batch_id(bbq_cmd_batch_id[gp]),
        .cmd_batch_offset(bbq_cmd_batch_offset[gp]),
        .sram_min_valid(bbq_sram_min_valid[gp]),
        .sram_min_desc(bbq_sram_min_desc[gp]),
        .sram_min_rank(bbq_sram_min_rank[gp]),
        .sram_min_seq(bbq_sram_min_seq[gp]),
        .sram_min_cell_count(bbq_sram_min_cell_count[gp]),
        .sram_max_valid(bbq_sram_max_valid[gp]),
        .sram_max_desc(bbq_sram_max_desc[gp]),
        .sram_max_rank(bbq_sram_max_rank[gp]),
        .sram_max_seq(bbq_sram_max_seq[gp]),
        .sram_max_cell_count(bbq_sram_max_cell_count[gp]),
        .hbm_min_valid(bbq_hbm_min_valid[gp]),
        .hbm_min_desc(bbq_hbm_min_desc[gp]),
        .hbm_min_rank(bbq_hbm_min_rank[gp]),
        .hbm_min_seq(bbq_hbm_min_seq[gp]),
        .hbm_min_cell_count(bbq_hbm_min_cell_count[gp]),
        .hbm_min_batch_id(bbq_hbm_min_batch_id[gp]),
        .hbm_min_batch_offset(bbq_hbm_min_batch_offset[gp]),
        .sram_occupancy(bbq_sram_occupancy[gp]),
        .hbm_occupancy(bbq_hbm_occupancy[gp])
      );
    end
  endgenerate

  assign policy_alpha_shift_c = POLICY_ALPHA_SHIFT;

  generate
    if (POLICY_MODE == POLICY_DT) begin : g_dt_policy
      hestia_policy_dt #(
        .PORTS(PORTS),
        .CELL_COUNT_WIDTH(CELL_COUNT_WIDTH),
        .OCC_WIDTH(16),
        .ALPHA_SHIFT_WIDTH(POLICY_ALPHA_SHIFT_WIDTH)
      ) policy_dt (
        .cfg_alpha_shift(policy_alpha_shift_c),
        .pkt_valid(1'b1),
        .pkt_port(action_port_q),
        .pkt_cell_count(action_cell_count_q),
        .free_cells(sram_free_count_q),
        .port_occ_flat(policy_sram_occ_flat_c),
        .pkt_admit(policy_admit_c),
        .threshold(policy_threshold_c)
      );
      assign policy_over_threshold_c = '0;
      assign policy_reclaim_valid_c = 1'b0;
      assign policy_reclaim_port_c = '0;
      assign obm_longest_valid_c = 1'b0;
      assign obm_longest_port_c = '0;
      assign obm_longest_occupancy_c = '0;
      assign obm_pkt_targets_longest_c = 1'b0;
    end else if ((POLICY_MODE == POLICY_OCCAMY_HEAD) ||
                 (POLICY_MODE == POLICY_OCCAMY_MAX)) begin : g_occamy_policy
      hestia_policy_occamy #(
        .PORTS(PORTS),
        .CELL_COUNT_WIDTH(CELL_COUNT_WIDTH),
        .OCC_WIDTH(16),
        .ALPHA_SHIFT_WIDTH(POLICY_ALPHA_SHIFT_WIDTH)
      ) policy_occamy (
        .clk(clk),
        .resetn(resetn),
        .cfg_alpha_shift(policy_alpha_shift_c),
        .reclaim_enable(enable),
        .reclaim_fire(policy_reclaim_fire_q),
        .pkt_valid(1'b1),
        .pkt_port(action_port_q),
        .pkt_cell_count(action_cell_count_q),
        .free_cells(sram_free_count_q),
        .port_occ_flat(policy_sram_occ_flat_c),
        .pkt_admit(policy_admit_c),
        .threshold(policy_threshold_c),
        .over_threshold_bitmap(policy_over_threshold_c),
        .reclaim_valid(policy_reclaim_valid_c),
        .reclaim_port(policy_reclaim_port_c)
      );
      assign obm_longest_valid_c = 1'b0;
      assign obm_longest_port_c = '0;
      assign obm_longest_occupancy_c = '0;
      assign obm_pkt_targets_longest_c = 1'b0;
    end else if (POLICY_MODE == POLICY_OBM) begin : g_obm_policy
      hestia_policy_obm #(
        .PORTS(PORTS),
        .OCC_WIDTH(16)
      ) policy_obm (
        .port_occ_flat(policy_sram_occ_flat_c),
        .pkt_port(action_port_q),
        .pkt_valid(1'b1),
        .longest_valid(obm_longest_valid_c),
        .longest_port(obm_longest_port_c),
        .longest_occupancy(obm_longest_occupancy_c),
        .pkt_targets_longest(obm_pkt_targets_longest_c)
      );
      assign policy_admit_c = 1'b1;
      assign policy_threshold_c = '0;
      assign policy_over_threshold_c = '0;
      assign policy_reclaim_valid_c = 1'b0;
      assign policy_reclaim_port_c = '0;
    end else begin : g_themis_policy
      assign policy_admit_c = 1'b1;
      assign policy_threshold_c = '0;
      assign policy_over_threshold_c = '0;
      assign policy_reclaim_valid_c = 1'b0;
      assign policy_reclaim_port_c = '0;
      assign obm_longest_valid_c = 1'b0;
      assign obm_longest_port_c = '0;
      assign obm_longest_occupancy_c = '0;
      assign obm_pkt_targets_longest_c = 1'b0;
    end
  endgenerate

  localparam logic [15:0] SRAM_CELLS_U16 = SRAM_CELLS;
  localparam logic [15:0] BATCH_SIZE_U16 = BATCH_SIZE;
  localparam logic [15:0] PACKET_SLOTS_U16 = PACKET_SLOTS;
  localparam logic [15:0] BATCH_SLOTS_U16 = BATCH_SLOTS;
  localparam logic [PORT_W-1:0] LAST_PORT = PORTS - 1;
  localparam int AXI_SIZE_WIDTH = (AXI_KEEP_WIDTH <= 2) ? 1 : $clog2(AXI_KEEP_WIDTH);
  localparam logic [2:0] AXI_BEAT_SIZE = AXI_SIZE_WIDTH;
  localparam logic [7:0] AXI_BATCH_LEN = BATCH_SIZE - 1;
  localparam logic [AXI_ADDR_WIDTH-1:0] AXI_BEAT_BYTES = AXI_KEEP_WIDTH;
  localparam logic [AXI_ADDR_WIDTH-1:0] BATCH_BYTES = BATCH_SIZE * AXI_KEEP_WIDTH;
  localparam int CELL_WORD_WIDTH = PAYLOAD_WIDTH + SEQ_WIDTH + RANK_WIDTH +
                                   PORT_W + CELL_COUNT_WIDTH + DESC_W + BATCH_OFF_W;

  if (CELL_WORD_WIDTH > AXI_DATA_WIDTH) begin : ddr_word_width_guard
    initial $error("PORT/RANK/SEQ/CELL/DESC/PAYLOAD fields must fit in one AXI beat");
  end

  if (AXI_SIZE_WIDTH > 8) begin : axi_size_guard
    initial $error("AXI data width is too large for the fixed AWSIZE/ARSIZE field");
  end

  function automatic logic rank_seq_less(
    input logic [RANK_WIDTH-1:0] rank_a,
    input logic [SEQ_WIDTH-1:0] seq_a,
    input logic [RANK_WIDTH-1:0] rank_b,
    input logic [SEQ_WIDTH-1:0] seq_b
  );
    begin
      rank_seq_less = (rank_a < rank_b) || ((rank_a == rank_b) && (seq_a < seq_b));
    end
  endfunction

  function automatic logic rank_seq_greater(
    input logic [RANK_WIDTH-1:0] rank_a,
    input logic [SEQ_WIDTH-1:0] seq_a,
    input logic [RANK_WIDTH-1:0] rank_b,
    input logic [SEQ_WIDTH-1:0] seq_b
  );
    begin
      rank_seq_greater = (rank_a > rank_b) || ((rank_a == rank_b) && (seq_a > seq_b));
    end
  endfunction

  function automatic logic [15:0] cell_count16(input logic [CELL_COUNT_WIDTH-1:0] cells_i);
    begin
      cell_count16 = {{(16-CELL_COUNT_WIDTH){1'b0}}, cells_i};
    end
  endfunction

  function automatic logic [DESC_W-1:0] desc_free_head;
    begin
      desc_free_head = desc_free_list[desc_free_rd_q];
    end
  endfunction

  function automatic logic [BATCH_ID_W-1:0] batch_free_head;
    begin
      batch_free_head = batch_free_list[batch_free_rd_q];
    end
  endfunction

  function automatic logic [SRAM_SLOT_W-1:0] sram_ptr_add(
    input logic [SRAM_SLOT_W-1:0] ptr_i,
    input logic [15:0] inc_i
  );
    int sum_v;
    begin
      sum_v = (ptr_i + inc_i) % SRAM_CELLS;
      sram_ptr_add = sum_v[SRAM_SLOT_W-1:0];
    end
  endfunction

  function automatic logic [BATCH_ID_W-1:0] batch_ptr_add(
    input logic [BATCH_ID_W-1:0] ptr_i,
    input logic [15:0] inc_i
  );
    int sum_v;
    begin
      sum_v = (ptr_i + inc_i) % BATCH_SLOTS;
      batch_ptr_add = sum_v[BATCH_ID_W-1:0];
    end
  endfunction

  function automatic logic [DESC_W-1:0] desc_ptr_add(
    input logic [DESC_W-1:0] ptr_i,
    input logic [15:0] inc_i
  );
    int sum_v;
    begin
      sum_v = (ptr_i + inc_i) % PACKET_SLOTS;
      desc_ptr_add = sum_v[DESC_W-1:0];
    end
  endfunction

  function automatic logic [AXI_ADDR_WIDTH-1:0] ddr_batch_addr(
    input logic [BATCH_ID_W-1:0] batch_i
  );
    begin
      ddr_batch_addr = DDR_BASE_ADDR + (AXI_ADDR_WIDTH'(batch_i) * BATCH_BYTES);
    end
  endfunction

  function automatic logic [AXI_ADDR_WIDTH-1:0] ddr_cell_addr(
    input logic [BATCH_ID_W-1:0] batch_i,
    input logic [BATCH_OFF_W-1:0] offset_i
  );
    begin
      ddr_cell_addr = ddr_batch_addr(batch_i) +
                      (AXI_ADDR_WIDTH'(offset_i) * AXI_BEAT_BYTES);
    end
  endfunction

  function automatic logic [7:0] ddr_cells_axi_len(input logic [15:0] cells_i);
    begin
      ddr_cells_axi_len = (cells_i == 16'd0) ? 8'd0 : (cells_i[7:0] - 8'd1);
    end
  endfunction

  function automatic logic [AXI_DATA_WIDTH-1:0] pack_ddr_desc_cell(
    input logic [DESC_W-1:0] desc_i,
    input logic [BATCH_OFF_W-1:0] cell_offset_i
  );
    int pos_v;
    begin
      pack_ddr_desc_cell = '0;
      pos_v = 0;
      pack_ddr_desc_cell[pos_v +: PAYLOAD_WIDTH] = desc_payload[desc_i];
      pos_v = pos_v + PAYLOAD_WIDTH;
      pack_ddr_desc_cell[pos_v +: SEQ_WIDTH] = desc_seq[desc_i];
      pos_v = pos_v + SEQ_WIDTH;
      pack_ddr_desc_cell[pos_v +: RANK_WIDTH] = desc_rank[desc_i];
      pos_v = pos_v + RANK_WIDTH;
      pack_ddr_desc_cell[pos_v +: PORT_W] = desc_port[desc_i];
      pos_v = pos_v + PORT_W;
      pack_ddr_desc_cell[pos_v +: CELL_COUNT_WIDTH] = desc_cell_count[desc_i];
      pos_v = pos_v + CELL_COUNT_WIDTH;
      pack_ddr_desc_cell[pos_v +: DESC_W] = desc_i;
      pos_v = pos_v + DESC_W;
      pack_ddr_desc_cell[pos_v +: BATCH_OFF_W] = cell_offset_i;
    end
  endfunction

  function automatic logic [AXI_DATA_WIDTH-1:0] pack_ddr_batch_cell(
    input logic [BATCH_ID_W-1:0] batch_i,
    input logic [BATCH_OFF_W-1:0] offset_i
  );
    begin
      if (batch_cell_valid[batch_i][offset_i]) begin
        pack_ddr_batch_cell = pack_ddr_desc_cell(batch_cell_desc[batch_i][offset_i], offset_i);
      end else begin
        pack_ddr_batch_cell = '0;
      end
    end
  endfunction

  function automatic logic [DESC_W-1:0] unpack_ddr_desc(input logic [AXI_DATA_WIDTH-1:0] word_i);
    begin
      unpack_ddr_desc = word_i[PAYLOAD_WIDTH+SEQ_WIDTH+RANK_WIDTH+PORT_W+CELL_COUNT_WIDTH +: DESC_W];
    end
  endfunction

  function automatic logic append_room_ready(input logic [15:0] cells_i);
    begin
      if (open_batch_valid_q) begin
        append_room_ready = (open_batch_fill_q + cells_i) <= BATCH_SIZE_U16;
      end else begin
        append_room_ready = (batch_free_count_q != 16'd0);
      end
    end
  endfunction

  function automatic logic append_needs_submit(input logic [15:0] cells_i);
    begin
      append_needs_submit = open_batch_valid_q &&
                            ((open_batch_fill_q + cells_i) > BATCH_SIZE_U16);
    end
  endfunction

  task automatic issue_bbq_cmd(
    input logic [PORT_W-1:0] port_i,
    input mp_bbq_cmd_t op_i,
    input logic [DESC_W-1:0] desc_i,
    input logic [RANK_WIDTH-1:0] rank_i,
    input logic [SEQ_WIDTH-1:0] seq_i,
    input logic [CELL_COUNT_WIDTH-1:0] cells_i,
    input logic [BATCH_ID_W-1:0] batch_i,
    input logic [BATCH_OFF_W-1:0] offset_i
  );
    begin
      bbq_cmd_valid[port_i] <= 1'b1;
      bbq_cmd_op[port_i] <= op_i;
      bbq_cmd_desc[port_i] <= desc_i;
      bbq_cmd_rank[port_i] <= rank_i;
      bbq_cmd_seq[port_i] <= seq_i;
      bbq_cmd_cell_count[port_i] <= cells_i;
      bbq_cmd_batch_id[port_i] <= batch_i;
      bbq_cmd_batch_offset[port_i] <= offset_i;
    end
  endtask

  task automatic refresh_then(input state_t return_i);
    begin
      refresh_return_q <= return_i;
      refresh_count_q <= '0;
      state_q <= ST_SELECTOR_REFRESH;
    end
  endtask

  task automatic submit_open_batch;
    begin
      if (open_batch_valid_q) begin
        if (open_batch_valid_count_q != 16'd0) begin
          batch_committed[open_batch_id_q] <= 1'b0;
          batch_write_pending[open_batch_id_q] <= 1'b1;
          stat_batch_submit <= stat_batch_submit + 32'd1;
        end else begin
          batch_free_list[batch_free_wr_q] <= open_batch_id_q;
          batch_free_wr_q <= batch_ptr_add(batch_free_wr_q, 16'd1);
          batch_free_count_q <= batch_free_count_q + 16'd1;
        end
        open_batch_valid_q <= 1'b0;
        open_batch_fill_q <= '0;
        open_batch_valid_count_q <= 16'd0;
      end
    end
  endtask

  task automatic allocate_sram_cells(
    input logic [DESC_W-1:0] desc_i,
    input logic [15:0] cells_i
  );
    int ai;
    logic [SRAM_SLOT_W-1:0] slot_v;
    begin
      for (ai = 0; ai < BATCH_SIZE; ai = ai + 1) begin
        if (ai < cells_i) begin
          slot_v = sram_free_list[sram_ptr_add(sram_free_rd_q, ai[15:0])];
          desc_sram_cell[desc_i][ai] <= slot_v;
        end
      end
      sram_free_rd_q <= sram_ptr_add(sram_free_rd_q, cells_i);
      sram_free_count_q <= sram_free_count_q - cells_i;
    end
  endtask

  task automatic release_sram_cells(input logic [DESC_W-1:0] desc_i);
    int ai;
    logic [15:0] cells_v;
    logic [SRAM_SLOT_W-1:0] slot_v;
    begin
      cells_v = cell_count16(desc_cell_count[desc_i]);
      for (ai = 0; ai < BATCH_SIZE; ai = ai + 1) begin
        if (ai < cells_v) begin
          slot_v = desc_sram_cell[desc_i][ai];
          sram_free_list[sram_ptr_add(sram_free_wr_q, ai[15:0])] <= slot_v;
        end
      end
      sram_free_wr_q <= sram_ptr_add(sram_free_wr_q, cells_v);
      sram_free_count_q <= sram_free_count_q + cells_v;
    end
  endtask

  task automatic free_desc(input logic [DESC_W-1:0] desc_i);
    begin
      desc_valid[desc_i] <= 1'b0;
      desc_free_list[desc_free_wr_q] <= desc_i;
      desc_free_wr_q <= desc_ptr_add(desc_free_wr_q, 16'd1);
      desc_free_count_q <= desc_free_count_q + 16'd1;
    end
  endtask

  task automatic free_batch_slot(input logic [BATCH_ID_W-1:0] batch_i);
    begin
      // Per-cell valid bits are cleared when the last live descriptor is invalidated.
      // Leaving stale descriptor values in a free batch avoids a wide dynamic clear net.
      batch_valid_count[batch_i] <= 16'd0;
      batch_fill_count[batch_i] <= '0;
      batch_write_pending[batch_i] <= 1'b0;
      if (open_batch_valid_q && (open_batch_id_q == batch_i)) begin
        open_batch_valid_q <= 1'b0;
        open_batch_fill_q <= '0;
        open_batch_valid_count_q <= 16'd0;
      end
      batch_free_list[batch_free_wr_q] <= batch_i;
      batch_free_wr_q <= batch_ptr_add(batch_free_wr_q, 16'd1);
      batch_free_count_q <= batch_free_count_q + 16'd1;
    end
  endtask

  task automatic append_desc_to_batch(
    input logic [DESC_W-1:0] desc_i,
    input logic [15:0] cells_i,
    output logic [BATCH_ID_W-1:0] batch_o,
    output logic [BATCH_OFF_W-1:0] offset_o
  );
    int ai;
    logic [BATCH_ID_W-1:0] batch_v;
    logic [BATCH_OFF_W:0] offset_v;
    logic [BATCH_OFF_W:0] next_fill_v;
    logic [15:0] valid_count_v;
    logic [15:0] next_valid_count_v;
    begin
      if (open_batch_valid_q) begin
        batch_v = open_batch_id_q;
        offset_v = open_batch_fill_q;
        valid_count_v = open_batch_valid_count_q;
      end else begin
        batch_v = batch_free_head();
        offset_v = '0;
        valid_count_v = 16'd0;
        batch_free_rd_q <= batch_ptr_add(batch_free_rd_q, 16'd1);
        batch_free_count_q <= batch_free_count_q - 16'd1;
        open_batch_valid_q <= 1'b1;
        open_batch_id_q <= batch_v;
        open_batch_fill_q <= '0;
        open_batch_valid_count_q <= 16'd0;
        batch_valid_count[batch_v] <= 16'd0;
        batch_fill_count[batch_v] <= '0;
        batch_committed[batch_v] <= 1'b0;
        batch_write_pending[batch_v] <= 1'b0;
      end

      batch_o = batch_v;
      offset_o = offset_v[BATCH_OFF_W-1:0];
      desc_batch_id[desc_i] <= batch_v;
      desc_batch_offset[desc_i] <= offset_v[BATCH_OFF_W-1:0];
      for (ai = 0; ai < BATCH_SIZE; ai = ai + 1) begin
        if (ai < cells_i) begin
          batch_cell_valid[batch_v][offset_v + ai] <= 1'b1;
          batch_cell_desc[batch_v][offset_v + ai] <= desc_i;
        end
      end
      next_fill_v = offset_v + cells_i;
      next_valid_count_v = valid_count_v + cells_i;
      batch_fill_count[batch_v] <= next_fill_v;
      batch_valid_count[batch_v] <= next_valid_count_v;
      open_batch_fill_q <= next_fill_v;
      open_batch_valid_count_q <= next_valid_count_v;

      if (next_fill_v == BATCH_SIZE_U16) begin
        batch_committed[batch_v] <= 1'b0;
        batch_write_pending[batch_v] <= 1'b1;
        open_batch_valid_q <= 1'b0;
        open_batch_fill_q <= '0;
        open_batch_valid_count_q <= 16'd0;
        stat_batch_submit <= stat_batch_submit + 32'd1;
      end
    end
  endtask

  task automatic invalidate_hbm_desc(input logic [DESC_W-1:0] desc_i);
    int ai;
    logic [15:0] cells_v;
    logic [BATCH_ID_W-1:0] batch_v;
    logic [BATCH_OFF_W:0] offset_v;
    begin
      cells_v = cell_count16(desc_cell_count[desc_i]);
      batch_v = desc_batch_id[desc_i];
      offset_v = desc_batch_offset[desc_i];
      for (ai = 0; ai < BATCH_SIZE; ai = ai + 1) begin
        if (ai < cells_v) begin
          batch_cell_valid[batch_v][offset_v + ai] <= 1'b0;
        end
      end
      if ((batch_valid_count[batch_v] == cells_v) &&
          !batch_write_pending[batch_v] &&
          !((wr_state_q != WR_IDLE) && (wr_batch_q == batch_v))) begin
        free_batch_slot(batch_v);
      end else begin
        batch_valid_count[batch_v] <= batch_valid_count[batch_v] - cells_v;
      end
    end
  endtask

  task automatic invalidate_hbm_desc_at(
    input logic [15:0] cells_i,
    input logic [BATCH_ID_W-1:0] batch_i,
    input logic [BATCH_OFF_W-1:0] offset_i
  );
    int ai;
    begin
      for (ai = 0; ai < BATCH_SIZE; ai = ai + 1) begin
        if (ai < cells_i) begin
          batch_cell_valid[batch_i][offset_i + ai] <= 1'b0;
        end
      end
      if ((batch_valid_count[batch_i] == cells_i) &&
          !batch_write_pending[batch_i] &&
          !((wr_state_q != WR_IDLE) && (wr_batch_q == batch_i))) begin
        free_batch_slot(batch_i);
      end else begin
        batch_valid_count[batch_i] <= batch_valid_count[batch_i] - cells_i;
      end
    end
  endtask

  task automatic create_sram_packet(
    input logic [PORT_W-1:0] port_i,
    input logic [RANK_WIDTH-1:0] rank_i,
    input logic [SEQ_WIDTH-1:0] seq_i,
    input logic [CELL_COUNT_WIDTH-1:0] cells_i,
    input logic [PAYLOAD_WIDTH-1:0] payload_i
  );
    logic [DESC_W-1:0] desc_v;
    logic [15:0] cells16_v;
    begin
      desc_v = desc_free_head();
      cells16_v = cell_count16(cells_i);
      desc_free_rd_q <= desc_ptr_add(desc_free_rd_q, 16'd1);
      desc_free_count_q <= desc_free_count_q - 16'd1;
      desc_valid[desc_v] <= 1'b1;
      desc_loc[desc_v] <= MP_LOC_SRAM;
      desc_port[desc_v] <= port_i;
      desc_rank[desc_v] <= rank_i;
      desc_seq[desc_v] <= seq_i;
      desc_cell_count[desc_v] <= cells_i;
      desc_payload[desc_v] <= payload_i;
      desc_batch_id[desc_v] <= '0;
      desc_batch_offset[desc_v] <= '0;
      allocate_sram_cells(desc_v, cells16_v);
      issue_bbq_cmd(port_i, MP_BBQ_CMD_ADD_SRAM, desc_v, rank_i, seq_i,
                    cells_i, '0, '0);
      sram_count_q[port_i] <= sram_count_q[port_i] + cells16_v;
      stat_generated <= stat_generated + 32'd1;
      stat_sram_admit <= stat_sram_admit + 32'd1;
    end
  endtask

  task automatic create_hbm_packet(
    input logic [PORT_W-1:0] port_i,
    input logic [RANK_WIDTH-1:0] rank_i,
    input logic [SEQ_WIDTH-1:0] seq_i,
    input logic [CELL_COUNT_WIDTH-1:0] cells_i,
    input logic [PAYLOAD_WIDTH-1:0] payload_i
  );
    logic [DESC_W-1:0] desc_v;
    logic [15:0] cells16_v;
    logic [BATCH_ID_W-1:0] batch_v;
    logic [BATCH_OFF_W-1:0] offset_v;
    begin
      desc_v = desc_free_head();
      cells16_v = cell_count16(cells_i);
      desc_free_rd_q <= desc_ptr_add(desc_free_rd_q, 16'd1);
      desc_free_count_q <= desc_free_count_q - 16'd1;
      desc_valid[desc_v] <= 1'b1;
      desc_loc[desc_v] <= MP_LOC_HBM;
      desc_port[desc_v] <= port_i;
      desc_rank[desc_v] <= rank_i;
      desc_seq[desc_v] <= seq_i;
      desc_cell_count[desc_v] <= cells_i;
      desc_payload[desc_v] <= payload_i;
      append_desc_to_batch(desc_v, cells16_v, batch_v, offset_v);
      issue_bbq_cmd(port_i, MP_BBQ_CMD_ADD_HBM, desc_v, rank_i, seq_i,
                    cells_i, batch_v, offset_v);
      hbm_count_q[port_i] <= hbm_count_q[port_i] + cells16_v;
      stat_generated <= stat_generated + 32'd1;
      stat_hbm_admit <= stat_hbm_admit + 32'd1;
    end
  endtask

  task automatic queue_sram_desc_to_hbm(
    input logic [DESC_W-1:0] desc_i,
    input logic [15:0] cells_i,
    input logic count_as_swap_i,
    input state_t return_state_i,
    input logic drop_on_fail_i
  );
    begin
      stage_sram_desc_q <= desc_i;
      stage_sram_cells_q <= cells_i;
      stage_sram_count_as_swap_q <= count_as_swap_i;
      stage_sram_return_q <= return_state_i;
      stage_sram_drop_on_fail_q <= drop_on_fail_i;
      state_q <= ST_STAGE_SRAM_TO_HBM;
    end
  endtask

  task automatic stage_sram_desc_to_hbm(
    input logic [DESC_W-1:0] desc_i,
    input logic [15:0] cells_i,
    input logic count_as_swap_i,
    input state_t return_state_i
  );
    logic [BATCH_ID_W-1:0] batch_v;
    logic [BATCH_OFF_W-1:0] offset_v;
    begin
      append_desc_to_batch(desc_i, cells_i, batch_v, offset_v);
      migrate_valid_q <= 1'b1;
      migrate_desc_q <= desc_i;
      migrate_count_as_swap_q <= count_as_swap_i;
      migrate_return_q <= return_state_i;
      state_q <= ST_MIGRATE_COMMIT;
    end
  endtask

  task automatic commit_sram_desc_to_hbm(input logic [DESC_W-1:0] desc_i, input logic count_as_swap_i);
    logic [PORT_W-1:0] port_v;
    logic [15:0] cells_v;
    begin
      port_v = desc_port[desc_i];
      cells_v = cell_count16(desc_cell_count[desc_i]);
      release_sram_cells(desc_i);
      desc_loc[desc_i] <= MP_LOC_HBM;
      issue_bbq_cmd(port_v, MP_BBQ_CMD_MOVE_SRAM_TO_HBM, desc_i,
                    desc_rank[desc_i], desc_seq[desc_i], desc_cell_count[desc_i],
                    desc_batch_id[desc_i], desc_batch_offset[desc_i]);
      sram_count_q[port_v] <= sram_count_q[port_v] - cells_v;
      hbm_count_q[port_v] <= hbm_count_q[port_v] + cells_v;
      if (count_as_swap_i) begin
        stat_swap_out <= stat_swap_out + 32'd1;
      end else begin
        stat_hbm_admit <= stat_hbm_admit + 32'd1;
      end
    end
  endtask

  task automatic dequeue_desc(
    input logic [PORT_W-1:0] port_i,
    input logic [DESC_W-1:0] desc_i
  );
    logic [15:0] cells_v;
    begin
      cells_v = cell_count16(desc_cell_count[desc_i]);
      m_pkt_valid[port_i] <= 1'b1;
      out_rank_q[port_i] <= desc_rank[desc_i];
      out_seq_q[port_i] <= desc_seq[desc_i];
      out_cell_count_q[port_i] <= desc_cell_count[desc_i];
      out_payload_q[port_i] <= desc_payload[desc_i];
      if (desc_loc[desc_i] == MP_LOC_SRAM) begin
`ifndef SYNTHESIS
        if (sram_count_q[port_i] < cells_v) begin
          $fatal(1, "SRAM count underflow before dequeue port=%0d desc=%0d cells=%0d sram_count=%0d",
                 port_i, desc_i, cells_v, sram_count_q[port_i]);
        end
`endif
        issue_bbq_cmd(port_i, MP_BBQ_CMD_REMOVE_SRAM, desc_i,
                      desc_rank[desc_i], desc_seq[desc_i], desc_cell_count[desc_i],
                      '0, '0);
        release_sram_cells(desc_i);
        sram_count_q[port_i] <= sram_count_q[port_i] - cells_v;
      end else begin
`ifndef SYNTHESIS
        if (hbm_count_q[port_i] < cells_v) begin
          $fatal(1, "HBM count underflow before dequeue port=%0d desc=%0d cells=%0d hbm_count=%0d",
                 port_i, desc_i, cells_v, hbm_count_q[port_i]);
        end
`endif
        issue_bbq_cmd(port_i, MP_BBQ_CMD_REMOVE_HBM, desc_i,
                      desc_rank[desc_i], desc_seq[desc_i], desc_cell_count[desc_i],
                      desc_batch_id[desc_i], desc_batch_offset[desc_i]);
        invalidate_hbm_desc(desc_i);
        hbm_count_q[port_i] <= hbm_count_q[port_i] - cells_v;
        stat_direct_hbm_dequeue <= stat_direct_hbm_dequeue + 32'd1;
      end
      free_desc(desc_i);
      stat_dequeued <= stat_dequeued + 32'd1;
    end
  endtask

  task automatic dequeue_hbm_desc(
    input logic [PORT_W-1:0] port_i,
    input logic [DESC_W-1:0] desc_i,
    input logic [15:0] cells_i,
    input logic [BATCH_ID_W-1:0] batch_i,
    input logic [BATCH_OFF_W-1:0] offset_i
  );
    begin
      m_pkt_valid[port_i] <= 1'b1;
      out_rank_q[port_i] <= desc_rank[desc_i];
      out_seq_q[port_i] <= desc_seq[desc_i];
      out_cell_count_q[port_i] <= desc_cell_count[desc_i];
      out_payload_q[port_i] <= desc_payload[desc_i];
`ifndef SYNTHESIS
      if (hbm_count_q[port_i] < cells_i) begin
        $fatal(1, "HBM count underflow before direct dequeue port=%0d desc=%0d cells=%0d hbm_count=%0d",
               port_i, desc_i, cells_i, hbm_count_q[port_i]);
      end
`endif
      issue_bbq_cmd(port_i, MP_BBQ_CMD_REMOVE_HBM, desc_i,
                    desc_rank[desc_i], desc_seq[desc_i], desc_cell_count[desc_i],
                    batch_i, offset_i);
      invalidate_hbm_desc_at(cells_i, batch_i, offset_i);
      hbm_count_q[port_i] <= hbm_count_q[port_i] - cells_i;
      stat_direct_hbm_dequeue <= stat_direct_hbm_dequeue + 32'd1;
      free_desc(desc_i);
      stat_dequeued <= stat_dequeued + 32'd1;
    end
  endtask

  task automatic swapin_desc_to_sram(input logic [DESC_W-1:0] desc_i);
    logic [15:0] cells_v;
    logic [PORT_W-1:0] port_v;
    begin
      cells_v = cell_count16(desc_cell_count[desc_i]);
      port_v = desc_port[desc_i];
      allocate_sram_cells(desc_i, cells_v);
      desc_loc[desc_i] <= MP_LOC_SRAM;
      desc_batch_id[desc_i] <= '0;
      desc_batch_offset[desc_i] <= '0;
      issue_bbq_cmd(port_v, MP_BBQ_CMD_MOVE_HBM_TO_SRAM, desc_i,
                    desc_rank[desc_i], desc_seq[desc_i], desc_cell_count[desc_i],
                    '0, '0);
      sram_count_q[port_v] <= sram_count_q[port_v] + cells_v;
      hbm_count_q[port_v] <= hbm_count_q[port_v] - cells_v;
      stat_swap_in <= stat_swap_in + 32'd1;
    end
  endtask

  task automatic drop_action_packet;
    begin
      stat_generated <= stat_generated + 32'd1;
      stat_drop <= stat_drop + 32'd1;
    end
  endtask

  integer ci;
  integer di;
  integer pi;
  integer deq_i;
  integer deq_idx_i;
  always_comb begin
    global_sram_c = SRAM_CELLS_U16 - sram_free_count_q;
    global_hbm_c = 16'd0;
    all_bbq_ready_c = 1'b1;
    store_read_grant_valid_c = 1'b0;
    store_read_grant_port_c = store_read_rr_q;
    store_read_grant_desc_c = '0;

    for (pi = 0; pi < PORTS; pi = pi + 1) begin
      global_hbm_c = global_hbm_c + hbm_count_q[pi];
      all_bbq_ready_c = all_bbq_ready_c && bbq_cmd_ready[pi];
      sram_min_valid_c[pi] = mask_sram_min_valid_q[pi];
      sram_min_desc_c[pi] = mask_sram_min_desc_q[pi];
      sram_max_valid_c[pi] = mask_sram_max_valid_q[pi];
      sram_max_desc_c[pi] = mask_sram_max_desc_q[pi];
      hbm_min_valid_c[pi] = mask_hbm_min_valid_q[pi];
      hbm_min_desc_c[pi] = mask_hbm_min_desc_q[pi];
      port_deq_req_valid_c[pi] = enable && (state_q == ST_IDLE) &&
                                 dequeue_enable[pi] &&
                                 (!m_pkt_valid[pi] || m_pkt_ready[pi]) &&
                                 (sram_min_valid_c[pi] || hbm_min_valid_c[pi]);
      if (hbm_min_valid_c[pi] &&
          (!sram_min_valid_c[pi] ||
           rank_seq_less(mask_hbm_min_rank_q[pi], mask_hbm_min_seq_q[pi],
                         mask_sram_min_rank_q[pi], mask_sram_min_seq_q[pi]))) begin
        port_deq_req_desc_c[pi] = hbm_min_desc_c[pi];
      end else begin
        port_deq_req_desc_c[pi] = sram_min_desc_c[pi];
      end
    end

    for (deq_i = 0; deq_i < PORTS; deq_i = deq_i + 1) begin
      deq_idx_i = store_read_rr_q + deq_i;
      if (deq_idx_i >= PORTS) begin
        deq_idx_i = deq_idx_i - PORTS;
      end
      if (!store_read_grant_valid_c && all_bbq_ready_q && port_deq_req_valid_c[deq_idx_i]) begin
        store_read_grant_valid_c = 1'b1;
        store_read_grant_port_c = deq_idx_i[PORT_W-1:0];
        store_read_grant_desc_c = port_deq_req_desc_c[deq_idx_i];
      end
    end

    water_swapout_pending_c = enable && (POLICY_MODE == POLICY_THEMIS) &&
                              (global_sram_c > cfg_swap_out_threshold) &&
                              sel_swapout_valid_q;
    water_swapin_pending_c = enable && (POLICY_MODE == POLICY_THEMIS) &&
                             (global_sram_c < cfg_swap_in_threshold) &&
                             sel_record_valid_q &&
                             (batch_valid_count[sel_record_batch_q] <= sram_free_count_q);

    s_pkt_ready = enable && bbq_initialized_q && (state_q == ST_IDLE) &&
                  !store_read_grant_valid_c &&
                  !store_read_grant_valid_q &&
                  !sel_water_swapout_pending_q &&
                  !sel_water_swapin_pending_q;

    m_axi_awid = '0;
    m_axi_awaddr = wr_addr_q;
    m_axi_awlen = AXI_BATCH_LEN;
    m_axi_awsize = AXI_BEAT_SIZE;
    m_axi_awburst = 2'b01;
    m_axi_awlock = 1'b0;
    m_axi_awcache = 4'b0011;
    m_axi_awprot = 3'b000;
    m_axi_awqos = 4'b0000;
    m_axi_wstrb = {AXI_KEEP_WIDTH{1'b1}};
    m_axi_wlast = (wr_beat_q + 1'b1) == BATCH_SIZE;
    m_axi_bready = (wr_state_q == WR_RESP);

    m_axi_arid = '0;
    m_axi_araddr = rd_addr_q;
    if (state_q == ST_SWAPIN_DDR_ADDR) begin
      m_axi_arlen = AXI_BATCH_LEN;
    end else if (state_q == ST_DEQ_DDR_ADDR) begin
      m_axi_arlen = ddr_cells_axi_len(ddr_deq_cells_q);
    end else begin
      m_axi_arlen = 8'd0;
    end
    m_axi_arsize = AXI_BEAT_SIZE;
    m_axi_arburst = 2'b01;
    m_axi_arlock = 1'b0;
    m_axi_arcache = 4'b0011;
    m_axi_arprot = 3'b000;
    m_axi_arqos = 4'b0000;

    ddr_r_direct_last_c = (state_q == ST_DEQ_DDR_DATA) &&
                          ((rd_beat_q + 1'b1) >= ddr_deq_cells_q);
    ddr_r_swapin_last_c = (state_q == ST_SWAPIN_DDR_DRAIN) &&
                          ((rd_beat_q + 1'b1) == BATCH_SIZE_U16);
    ddr_r_final_ready_c = !ddr_r_direct_last_c ||
                          ((!m_pkt_valid[ddr_deq_port_q] || m_pkt_ready[ddr_deq_port_q]) &&
                           bbq_ready_q[ddr_deq_port_q]);
    m_axi_rready = ((state_q == ST_SWAPIN_DDR_DRAIN) ||
                    (state_q == ST_DEQ_DDR_DATA)) &&
                   ddr_r_final_ready_c;
    ddr_r_accept_c = m_axi_rvalid && m_axi_rready;

    dbg_ddr_state = {1'b0, wr_state_q, state_q};
    dbg_ddr_wr_error = ddr_wr_error_q;
    dbg_ddr_rd_error = ddr_rd_error_q;
    dbg_global_sram_occupancy = global_sram_c;
    dbg_global_hbm_occupancy = global_hbm_c;
    dbg_open_batch_cells = open_batch_valid_q ? open_batch_fill_q : 16'd0;
  end

  integer ri;
  integer bi;
  integer oi;
  always_ff @(posedge clk) begin
    logic [15:0] action_cells_v;
    logic new_better_record_v;
    logic [DESC_W-1:0] old_desc_v;
    logic [15:0] old_cells_v;
    logic ddr_rd_error_v;
    logic [PORT_W-1:0] scan_port_v;
    logic scan_record_valid_v;
    logic [PORT_W-1:0] scan_record_port_v;
    logic [DESC_W-1:0] scan_record_desc_v;
    logic [BATCH_ID_W-1:0] scan_record_batch_v;
    logic [15:0] scan_record_first_rank_v;
    logic [RANK_WIDTH-1:0] scan_record_second_rank_v;
    logic [SEQ_WIDTH-1:0] scan_record_seq_v;
    logic scan_swapout_valid_v;
    logic [PORT_W-1:0] scan_swapout_port_v;
    logic [DESC_W-1:0] scan_swapout_desc_v;
    logic [15:0] scan_swapout_first_rank_v;
    logic [CELL_COUNT_WIDTH-1:0] scan_swapout_cell_count_v;
    logic [RANK_WIDTH-1:0] scan_swapout_rank_v;
    logic [SEQ_WIDTH-1:0] scan_swapout_seq_v;
    if (!resetn) begin
      state_q <= ST_IDLE;
      refresh_return_q <= ST_IDLE;
      refresh_count_q <= '0;
      action_port_q <= '0;
      action_rank_q <= '0;
      action_seq_q <= '0;
      action_cell_count_q <= '0;
      action_payload_q <= '0;
      swapin_batch_q <= '0;
      swapin_offset_q <= '0;
      swapin_commit_batch_q <= '0;
      swapin_commit_offset_q <= '0;
      swapin_commit_desc_q <= '0;
      swapin_commit_cells_q <= 16'd0;
      all_bbq_ready_q <= 1'b0;
      bbq_initialized_q <= 1'b0;
      store_read_grant_valid_q <= 1'b0;
      store_read_grant_port_q <= '0;
      store_read_grant_desc_q <= '0;
      store_read_rr_q <= '0;
      migrate_valid_q <= 1'b0;
      migrate_desc_q <= '0;
      migrate_count_as_swap_q <= 1'b0;
      migrate_return_q <= ST_IDLE;
      stage_sram_desc_q <= '0;
      stage_sram_cells_q <= 16'd0;
      stage_sram_count_as_swap_q <= 1'b0;
      stage_sram_drop_on_fail_q <= 1'b0;
      stage_sram_return_q <= ST_IDLE;
      sel_record_valid_q <= 1'b0;
      sel_record_port_q <= '0;
      sel_record_desc_q <= '0;
      sel_record_batch_q <= '0;
      sel_record_first_rank_q <= '0;
      sel_record_second_rank_q <= '0;
      sel_record_seq_q <= '0;
      sel_swapout_valid_q <= 1'b0;
      sel_swapout_port_q <= '0;
      sel_swapout_desc_q <= '0;
      sel_swapout_first_rank_q <= '0;
      sel_swapout_cell_count_q <= '0;
      sel_water_swapout_pending_q <= 1'b0;
      sel_water_swapin_pending_q <= 1'b0;
      select_scan_port_q <= '0;
      select_record_valid_q <= 1'b0;
      select_record_port_q <= '0;
      select_record_desc_q <= '0;
      select_record_batch_q <= '0;
      select_record_first_rank_q <= '1;
      select_record_second_rank_q <= '1;
      select_record_seq_q <= '1;
      select_swapout_valid_q <= 1'b0;
      select_swapout_port_q <= '0;
      select_swapout_desc_q <= '0;
      select_swapout_first_rank_q <= '0;
      select_swapout_cell_count_q <= '0;
      select_swapout_rank_q <= '0;
      select_swapout_seq_q <= '0;
      for (ri = 0; ri < PORTS; ri = ri + 1) begin
        sram_count_q[ri] <= 16'd0;
        hbm_count_q[ri] <= 16'd0;
        m_pkt_valid[ri] <= 1'b0;
        out_rank_q[ri] <= '0;
        out_seq_q[ri] <= '0;
        out_cell_count_q[ri] <= '0;
        out_payload_q[ri] <= '0;
        bbq_cmd_valid[ri] <= 1'b0;
        bbq_cmd_op[ri] <= MP_BBQ_CMD_NONE;
        bbq_cmd_desc[ri] <= '0;
        bbq_cmd_rank[ri] <= '0;
        bbq_cmd_seq[ri] <= '0;
        bbq_cmd_cell_count[ri] <= '0;
        bbq_cmd_batch_id[ri] <= '0;
        bbq_cmd_batch_offset[ri] <= '0;
        bbq_ready_q[ri] <= 1'b0;
        cand_sram_min_valid_q[ri] <= 1'b0;
        cand_sram_min_desc_q[ri] <= '0;
        cand_sram_min_rank_q[ri] <= '0;
        cand_sram_min_seq_q[ri] <= '0;
        cand_sram_max_valid_q[ri] <= 1'b0;
        cand_sram_max_desc_q[ri] <= '0;
        cand_sram_max_rank_q[ri] <= '0;
        cand_sram_max_seq_q[ri] <= '0;
        cand_sram_max_cell_count_q[ri] <= '0;
        cand_hbm_min_valid_q[ri] <= 1'b0;
        cand_hbm_min_desc_q[ri] <= '0;
        cand_hbm_min_rank_q[ri] <= '0;
        cand_hbm_min_seq_q[ri] <= '0;
        cand_hbm_min_batch_id_q[ri] <= '0;
        cand_hbm_min_batch_offset_q[ri] <= '0;
        mask_sram_min_valid_q[ri] <= 1'b0;
        mask_sram_min_desc_q[ri] <= '0;
        mask_sram_min_rank_q[ri] <= '0;
        mask_sram_min_seq_q[ri] <= '0;
        mask_sram_max_valid_q[ri] <= 1'b0;
        mask_sram_max_desc_q[ri] <= '0;
        mask_sram_max_rank_q[ri] <= '0;
        mask_sram_max_seq_q[ri] <= '0;
        mask_sram_max_cell_count_q[ri] <= '0;
        mask_hbm_min_valid_q[ri] <= 1'b0;
        mask_hbm_min_desc_q[ri] <= '0;
        mask_hbm_min_rank_q[ri] <= '0;
        mask_hbm_min_seq_q[ri] <= '0;
        mask_hbm_min_batch_id_q[ri] <= '0;
        sel_sram_max_valid_q[ri] <= 1'b0;
        sel_sram_max_desc_q[ri] <= '0;
        sel_sram_max_rank_q[ri] <= '0;
        sel_sram_max_seq_q[ri] <= '0;
        sel_sram_max_cell_count_q[ri] <= '0;
      end
      for (ri = 0; ri < PACKET_SLOTS; ri = ri + 1) begin
        desc_valid[ri] <= 1'b0;
        desc_free_list[ri] <= ri[DESC_W-1:0];
        desc_loc[ri] <= MP_LOC_SRAM;
        desc_port[ri] <= '0;
        desc_rank[ri] <= '0;
        desc_seq[ri] <= '0;
        desc_cell_count[ri] <= '0;
        desc_payload[ri] <= '0;
        desc_batch_id[ri] <= '0;
        desc_batch_offset[ri] <= '0;
      end
      desc_free_rd_q <= '0;
      desc_free_wr_q <= '0;
      desc_free_count_q <= PACKET_SLOTS_U16;
      for (ri = 0; ri < SRAM_CELLS; ri = ri + 1) begin
        sram_free_list[ri] <= ri[SRAM_SLOT_W-1:0];
      end
      sram_free_rd_q <= '0;
      sram_free_wr_q <= '0;
      sram_free_count_q <= SRAM_CELLS_U16;
      for (bi = 0; bi < BATCH_SLOTS; bi = bi + 1) begin
        batch_free_list[bi] <= bi[BATCH_ID_W-1:0];
        batch_valid_count[bi] <= 16'd0;
        batch_fill_count[bi] <= '0;
        batch_committed[bi] <= 1'b0;
        batch_write_pending[bi] <= 1'b0;
        for (oi = 0; oi < BATCH_SIZE; oi = oi + 1) begin
          batch_cell_valid[bi][oi] <= 1'b0;
          batch_cell_desc[bi][oi] <= '0;
        end
      end
      batch_free_rd_q <= '0;
      batch_free_wr_q <= '0;
      batch_free_count_q <= BATCH_SLOTS_U16;
      open_batch_valid_q <= 1'b0;
      open_batch_id_q <= '0;
      open_batch_fill_q <= '0;
      open_batch_valid_count_q <= 16'd0;
      stat_generated <= 32'd0;
      stat_dequeued <= 32'd0;
      stat_sram_admit <= 32'd0;
      stat_hbm_admit <= 32'd0;
      stat_swap_out <= 32'd0;
      stat_swap_in <= 32'd0;
      stat_direct_hbm_dequeue <= 32'd0;
      stat_drop <= 32'd0;
      stat_batch_submit <= 32'd0;
      stat_ddr_write_beats <= 32'd0;
      stat_ddr_read_beats <= 32'd0;
      stat_ddr_write_batches <= 32'd0;
      stat_ddr_read_batches <= 32'd0;
      policy_reclaim_fire_q <= 1'b0;
      wr_state_q <= WR_IDLE;
      wr_batch_q <= '0;
      wr_beat_q <= '0;
      wr_addr_q <= '0;
      wr_scan_ptr_q <= '0;
      ddr_deq_port_q <= '0;
      ddr_deq_desc_q <= '0;
      ddr_deq_cells_q <= 16'd0;
      ddr_deq_batch_q <= '0;
      ddr_deq_offset_q <= '0;
      ddr_wait_batch_q <= '0;
      rd_beat_q <= '0;
      rd_addr_q <= '0;
      rd_batch_q <= '0;
      m_axi_awvalid <= 1'b0;
      m_axi_wvalid <= 1'b0;
      m_axi_wdata <= '0;
      m_axi_arvalid <= 1'b0;
      ddr_wr_error_q <= 1'b0;
      ddr_rd_error_q <= 1'b0;
    end else begin
      all_bbq_ready_q <= all_bbq_ready_c;
      policy_reclaim_fire_q <= 1'b0;
      if (all_bbq_ready_c) begin
        bbq_initialized_q <= 1'b1;
      end

      for (ri = 0; ri < PORTS; ri = ri + 1) begin
        bbq_cmd_valid[ri] <= 1'b0;
        bbq_cmd_op[ri] <= MP_BBQ_CMD_NONE;
        bbq_ready_q[ri] <= bbq_cmd_ready[ri];
        cand_sram_min_valid_q[ri] <= bbq_sram_min_valid[ri];
        cand_sram_min_desc_q[ri] <= bbq_sram_min_desc[ri];
        cand_sram_min_rank_q[ri] <= bbq_sram_min_rank[ri];
        cand_sram_min_seq_q[ri] <= bbq_sram_min_seq[ri];
        cand_sram_max_valid_q[ri] <= bbq_sram_max_valid[ri];
        cand_sram_max_desc_q[ri] <= bbq_sram_max_desc[ri];
        cand_sram_max_rank_q[ri] <= bbq_sram_max_rank[ri];
        cand_sram_max_seq_q[ri] <= bbq_sram_max_seq[ri];
        cand_sram_max_cell_count_q[ri] <= bbq_sram_max_cell_count[ri];
        cand_hbm_min_valid_q[ri] <= bbq_hbm_min_valid[ri];
        cand_hbm_min_desc_q[ri] <= bbq_hbm_min_desc[ri];
        cand_hbm_min_rank_q[ri] <= bbq_hbm_min_rank[ri];
        cand_hbm_min_seq_q[ri] <= bbq_hbm_min_seq[ri];
        cand_hbm_min_batch_id_q[ri] <= bbq_hbm_min_batch_id[ri];
        cand_hbm_min_batch_offset_q[ri] <= bbq_hbm_min_batch_offset[ri];
        mask_sram_min_valid_q[ri] <= cand_sram_min_valid_q[ri] &&
                                     desc_valid[cand_sram_min_desc_q[ri]] &&
                                     (desc_port[cand_sram_min_desc_q[ri]] == ri[PORT_W-1:0]) &&
                                     (desc_loc[cand_sram_min_desc_q[ri]] == MP_LOC_SRAM);
        mask_sram_min_desc_q[ri] <= cand_sram_min_desc_q[ri];
        mask_sram_min_rank_q[ri] <= cand_sram_min_rank_q[ri];
        mask_sram_min_seq_q[ri] <= cand_sram_min_seq_q[ri];
        mask_sram_max_valid_q[ri] <= cand_sram_max_valid_q[ri] &&
                                     desc_valid[cand_sram_max_desc_q[ri]] &&
                                     (desc_port[cand_sram_max_desc_q[ri]] == ri[PORT_W-1:0]) &&
                                     (desc_loc[cand_sram_max_desc_q[ri]] == MP_LOC_SRAM);
        mask_sram_max_desc_q[ri] <= cand_sram_max_desc_q[ri];
        mask_sram_max_rank_q[ri] <= cand_sram_max_rank_q[ri];
        mask_sram_max_seq_q[ri] <= cand_sram_max_seq_q[ri];
        mask_sram_max_cell_count_q[ri] <= cand_sram_max_cell_count_q[ri];
        mask_hbm_min_valid_q[ri] <= cand_hbm_min_valid_q[ri] &&
                                    desc_valid[cand_hbm_min_desc_q[ri]] &&
                                    (desc_port[cand_hbm_min_desc_q[ri]] == ri[PORT_W-1:0]) &&
                                    (desc_loc[cand_hbm_min_desc_q[ri]] == MP_LOC_HBM);
        mask_hbm_min_desc_q[ri] <= cand_hbm_min_desc_q[ri];
        mask_hbm_min_rank_q[ri] <= cand_hbm_min_rank_q[ri];
        mask_hbm_min_seq_q[ri] <= cand_hbm_min_seq_q[ri];
        mask_hbm_min_batch_id_q[ri] <= cand_hbm_min_batch_id_q[ri];
        sel_sram_max_valid_q[ri] <= sram_max_valid_c[ri];
        sel_sram_max_desc_q[ri] <= sram_max_desc_c[ri];
        sel_sram_max_rank_q[ri] <= mask_sram_max_rank_q[ri];
        sel_sram_max_seq_q[ri] <= mask_sram_max_seq_q[ri];
        sel_sram_max_cell_count_q[ri] <= mask_sram_max_cell_count_q[ri];
        if (m_pkt_valid[ri] && m_pkt_ready[ri]) begin
          m_pkt_valid[ri] <= 1'b0;
        end
      end

      scan_port_v = select_scan_port_q;
      scan_record_valid_v = select_record_valid_q;
      scan_record_port_v = select_record_port_q;
      scan_record_desc_v = select_record_desc_q;
      scan_record_batch_v = select_record_batch_q;
      scan_record_first_rank_v = select_record_first_rank_q;
      scan_record_second_rank_v = select_record_second_rank_q;
      scan_record_seq_v = select_record_seq_q;
      scan_swapout_valid_v = select_swapout_valid_q;
      scan_swapout_port_v = select_swapout_port_q;
      scan_swapout_desc_v = select_swapout_desc_q;
      scan_swapout_first_rank_v = select_swapout_first_rank_q;
      scan_swapout_cell_count_v = select_swapout_cell_count_q;
      scan_swapout_rank_v = select_swapout_rank_q;
      scan_swapout_seq_v = select_swapout_seq_q;

      if (mask_hbm_min_valid_q[scan_port_v]) begin
        if (!scan_record_valid_v ||
            (sram_count_q[scan_port_v] < scan_record_first_rank_v) ||
            ((sram_count_q[scan_port_v] == scan_record_first_rank_v) &&
             rank_seq_less(mask_hbm_min_rank_q[scan_port_v],
                           mask_hbm_min_seq_q[scan_port_v],
                           scan_record_second_rank_v,
                           scan_record_seq_v))) begin
          scan_record_valid_v = 1'b1;
          scan_record_port_v = scan_port_v;
          scan_record_desc_v = mask_hbm_min_desc_q[scan_port_v];
          scan_record_batch_v = mask_hbm_min_batch_id_q[scan_port_v];
          scan_record_first_rank_v = sram_count_q[scan_port_v];
          scan_record_second_rank_v = mask_hbm_min_rank_q[scan_port_v];
          scan_record_seq_v = mask_hbm_min_seq_q[scan_port_v];
        end
      end

      if (mask_sram_max_valid_q[scan_port_v]) begin
        if (!scan_swapout_valid_v ||
            (sram_count_q[scan_port_v] > scan_swapout_first_rank_v) ||
            ((sram_count_q[scan_port_v] == scan_swapout_first_rank_v) &&
             rank_seq_greater(mask_sram_max_rank_q[scan_port_v],
                              mask_sram_max_seq_q[scan_port_v],
                              scan_swapout_rank_v,
                              scan_swapout_seq_v))) begin
          scan_swapout_valid_v = 1'b1;
          scan_swapout_port_v = scan_port_v;
          scan_swapout_desc_v = mask_sram_max_desc_q[scan_port_v];
          scan_swapout_first_rank_v = sram_count_q[scan_port_v];
          scan_swapout_cell_count_v = mask_sram_max_cell_count_q[scan_port_v];
          scan_swapout_rank_v = mask_sram_max_rank_q[scan_port_v];
          scan_swapout_seq_v = mask_sram_max_seq_q[scan_port_v];
        end
      end

      if (select_scan_port_q == LAST_PORT) begin
        sel_record_valid_q <= scan_record_valid_v;
        sel_record_port_q <= scan_record_port_v;
        sel_record_desc_q <= scan_record_desc_v;
        sel_record_batch_q <= scan_record_batch_v;
        sel_record_first_rank_q <= scan_record_first_rank_v;
        sel_record_second_rank_q <= scan_record_second_rank_v;
        sel_record_seq_q <= scan_record_seq_v;
        sel_swapout_valid_q <= scan_swapout_valid_v;
        sel_swapout_port_q <= scan_swapout_port_v;
        sel_swapout_desc_q <= scan_swapout_desc_v;
        sel_swapout_first_rank_q <= scan_swapout_first_rank_v;
        sel_swapout_cell_count_q <= scan_swapout_cell_count_v;
        select_record_valid_q <= 1'b0;
        select_record_port_q <= '0;
        select_record_desc_q <= '0;
        select_record_batch_q <= '0;
        select_record_first_rank_q <= '1;
        select_record_second_rank_q <= '1;
        select_record_seq_q <= '1;
        select_swapout_valid_q <= 1'b0;
        select_swapout_port_q <= '0;
        select_swapout_desc_q <= '0;
        select_swapout_first_rank_q <= '0;
        select_swapout_cell_count_q <= '0;
        select_swapout_rank_q <= '0;
        select_swapout_seq_q <= '0;
        select_scan_port_q <= '0;
      end else begin
        select_record_valid_q <= scan_record_valid_v;
        select_record_port_q <= scan_record_port_v;
        select_record_desc_q <= scan_record_desc_v;
        select_record_batch_q <= scan_record_batch_v;
        select_record_first_rank_q <= scan_record_first_rank_v;
        select_record_second_rank_q <= scan_record_second_rank_v;
        select_record_seq_q <= scan_record_seq_v;
        select_swapout_valid_q <= scan_swapout_valid_v;
        select_swapout_port_q <= scan_swapout_port_v;
        select_swapout_desc_q <= scan_swapout_desc_v;
        select_swapout_first_rank_q <= scan_swapout_first_rank_v;
        select_swapout_cell_count_q <= scan_swapout_cell_count_v;
        select_swapout_rank_q <= scan_swapout_rank_v;
        select_swapout_seq_q <= scan_swapout_seq_v;
        select_scan_port_q <= select_scan_port_q + 1'b1;
      end

      if ((state_q == ST_IDLE) && !store_read_grant_valid_q && store_read_grant_valid_c) begin
        store_read_grant_valid_q <= 1'b1;
        store_read_grant_port_q <= store_read_grant_port_c;
        store_read_grant_desc_q <= store_read_grant_desc_c;
      end

      unique case (wr_state_q)
        WR_IDLE: begin
          if (enable && batch_write_pending[wr_scan_ptr_q] &&
              !batch_committed[wr_scan_ptr_q] &&
              (batch_valid_count[wr_scan_ptr_q] != 16'd0)) begin
            wr_batch_q <= wr_scan_ptr_q;
            wr_addr_q <= ddr_batch_addr(wr_scan_ptr_q);
            wr_beat_q <= '0;
            m_axi_awvalid <= 1'b1;
            wr_state_q <= WR_ADDR;
          end else if (enable) begin
            wr_scan_ptr_q <= (wr_scan_ptr_q == BATCH_SLOTS-1) ? '0 : (wr_scan_ptr_q + 1'b1);
          end
        end

        WR_ADDR: begin
          if (m_axi_awvalid && m_axi_awready) begin
            m_axi_awvalid <= 1'b0;
            m_axi_wvalid <= 1'b1;
            m_axi_wdata <= pack_ddr_batch_cell(wr_batch_q, '0);
            wr_state_q <= WR_DATA;
          end
        end

        WR_DATA: begin
          if (m_axi_wvalid && m_axi_wready) begin
            stat_ddr_write_beats <= stat_ddr_write_beats + 32'd1;
            if ((wr_beat_q + 1'b1) == BATCH_SIZE_U16) begin
              m_axi_wvalid <= 1'b0;
              wr_state_q <= WR_RESP;
            end else begin
              wr_beat_q <= wr_beat_q + 1'b1;
              m_axi_wdata <= pack_ddr_batch_cell(
                wr_batch_q,
                (wr_beat_q[BATCH_OFF_W-1:0] + 1'b1)
              );
            end
          end
        end

        WR_RESP: begin
          if (m_axi_bvalid) begin
            ddr_wr_error_q <= ddr_wr_error_q | (m_axi_bresp != 2'b00);
            batch_write_pending[wr_batch_q] <= 1'b0;
            batch_committed[wr_batch_q] <= 1'b1;
            stat_ddr_write_batches <= stat_ddr_write_batches + 32'd1;
            wr_scan_ptr_q <= (wr_batch_q == BATCH_SLOTS-1) ? '0 : (wr_batch_q + 1'b1);
            wr_state_q <= WR_IDLE;
          end
        end

        default: begin
          m_axi_awvalid <= 1'b0;
          m_axi_wvalid <= 1'b0;
          wr_state_q <= WR_IDLE;
        end
      endcase

      sel_water_swapout_pending_q <= water_swapout_pending_c;
      sel_water_swapin_pending_q <= water_swapin_pending_c;

      unique case (state_q)
        ST_IDLE: begin
          if (store_read_grant_valid_q) begin
            store_read_grant_valid_q <= 1'b0;
            if (desc_loc[store_read_grant_desc_q] == MP_LOC_HBM) begin
              ddr_deq_port_q <= store_read_grant_port_q;
              ddr_deq_desc_q <= store_read_grant_desc_q;
              ddr_deq_cells_q <= cell_count16(desc_cell_count[store_read_grant_desc_q]);
              ddr_deq_batch_q <= desc_batch_id[store_read_grant_desc_q];
              ddr_deq_offset_q <= desc_batch_offset[store_read_grant_desc_q];
              ddr_wait_batch_q <= desc_batch_id[store_read_grant_desc_q];
              state_q <= ST_DEQ_DDR_PREP;
            end else begin
              dequeue_desc(store_read_grant_port_q, store_read_grant_desc_q);
              store_read_rr_q <= (store_read_grant_port_q == LAST_PORT) ? '0 : (store_read_grant_port_q + 1'b1);
              refresh_then(ST_IDLE);
            end
          end else if (store_read_grant_valid_c) begin
            state_q <= ST_IDLE;
          end else if (sel_water_swapout_pending_q) begin
            state_q <= ST_SWAPOUT_BUILD;
          end else if (sel_water_swapin_pending_q) begin
            swapin_batch_q <= sel_record_batch_q;
            swapin_offset_q <= '0;
            ddr_wait_batch_q <= sel_record_batch_q;
            state_q <= ST_SWAPIN_DDR_PREP;
          end else if (s_pkt_valid && s_pkt_ready) begin
            action_port_q <= s_pkt_port;
            action_rank_q <= s_pkt_rank;
            action_seq_q <= s_pkt_seq;
            action_cell_count_q <= s_pkt_cell_count;
            action_payload_q <= s_pkt_payload;
            state_q <= ST_ADMISSION;
          end else if (((POLICY_MODE == POLICY_OCCAMY_HEAD) ||
                        (POLICY_MODE == POLICY_OCCAMY_MAX)) &&
                       policy_reclaim_valid_c &&
                       (POLICY_MODE == POLICY_OCCAMY_HEAD ?
                        mask_sram_min_valid_q[policy_reclaim_port_c] :
                        sel_sram_max_valid_q[policy_reclaim_port_c])) begin
            if (POLICY_MODE == POLICY_OCCAMY_HEAD) begin
              old_desc_v = mask_sram_min_desc_q[policy_reclaim_port_c];
              old_cells_v = cell_count16(desc_cell_count[old_desc_v]);
            end else begin
              old_desc_v = sel_sram_max_desc_q[policy_reclaim_port_c];
              old_cells_v = cell_count16(sel_sram_max_cell_count_q[policy_reclaim_port_c]);
            end
            if (append_room_ready(old_cells_v) || append_needs_submit(old_cells_v)) begin
              policy_reclaim_fire_q <= 1'b1;
              queue_sram_desc_to_hbm(old_desc_v, old_cells_v, 1'b1, ST_IDLE, 1'b0);
            end
          end
        end

        ST_ADMISSION: begin
          if (!bbq_ready_q[action_port_q]) begin
            state_q <= ST_ADMISSION;
          end else begin
          action_cells_v = cell_count16(action_cell_count_q);

          if ((action_cells_v == 16'd0) || (action_cells_v > BATCH_SIZE_U16) ||
              (desc_free_count_q == 16'd0)) begin
            drop_action_packet();
            state_q <= ST_IDLE;
          end else if (POLICY_MODE == POLICY_DT ||
                       POLICY_MODE == POLICY_OCCAMY_HEAD ||
                       POLICY_MODE == POLICY_OCCAMY_MAX) begin
            if (policy_admit_c && (sram_free_count_q >= action_cells_v)) begin
              create_sram_packet(action_port_q, action_rank_q, action_seq_q,
                                 action_cell_count_q, action_payload_q);
              refresh_then(ST_IDLE);
            end else if (append_room_ready(action_cells_v)) begin
              create_hbm_packet(action_port_q, action_rank_q, action_seq_q,
                                action_cell_count_q, action_payload_q);
              refresh_then(ST_IDLE);
            end else if (append_needs_submit(action_cells_v)) begin
              submit_open_batch();
              state_q <= ST_ADMISSION;
            end else begin
              drop_action_packet();
              state_q <= ST_IDLE;
            end
          end else if (POLICY_MODE == POLICY_OBM) begin
            if (sram_free_count_q >= action_cells_v) begin
              create_sram_packet(action_port_q, action_rank_q, action_seq_q,
                                 action_cell_count_q, action_payload_q);
              refresh_then(ST_IDLE);
            end else if (obm_longest_valid_c &&
                         !obm_pkt_targets_longest_c &&
                         sel_sram_max_valid_q[obm_longest_port_c]) begin
              old_desc_v = sel_sram_max_desc_q[obm_longest_port_c];
              old_cells_v = cell_count16(sel_sram_max_cell_count_q[obm_longest_port_c]);
              if (append_room_ready(old_cells_v) || append_needs_submit(old_cells_v)) begin
                queue_sram_desc_to_hbm(old_desc_v, old_cells_v, 1'b1, ST_ADMISSION, 1'b1);
              end else begin
                drop_action_packet();
                state_q <= ST_IDLE;
              end
            end else if (append_room_ready(action_cells_v)) begin
              create_hbm_packet(action_port_q, action_rank_q, action_seq_q,
                                action_cell_count_q, action_payload_q);
              refresh_then(ST_IDLE);
            end else if (append_needs_submit(action_cells_v)) begin
              submit_open_batch();
              state_q <= ST_ADMISSION;
            end else begin
              drop_action_packet();
              state_q <= ST_IDLE;
            end
          end else begin
            new_better_record_v = !sel_record_valid_q ||
                                  (sram_count_q[action_port_q] < sel_record_first_rank_q) ||
                                  ((sram_count_q[action_port_q] == sel_record_first_rank_q) &&
                                   rank_seq_less(action_rank_q, action_seq_q,
                                                 sel_record_second_rank_q, sel_record_seq_q));

            if (new_better_record_v) begin
              if (sram_free_count_q >= action_cells_v) begin
                create_sram_packet(action_port_q, action_rank_q, action_seq_q,
                                   action_cell_count_q, action_payload_q);
                refresh_then(ST_IDLE);
              end else if (sel_swapout_valid_q) begin
                old_desc_v = sel_swapout_desc_q;
                old_cells_v = cell_count16(sel_swapout_cell_count_q);
                if (append_room_ready(old_cells_v) || append_needs_submit(old_cells_v)) begin
                  queue_sram_desc_to_hbm(old_desc_v, old_cells_v, 1'b1, ST_ADMISSION, 1'b1);
                end else begin
                  drop_action_packet();
                  state_q <= ST_IDLE;
                end
              end else begin
                drop_action_packet();
                state_q <= ST_IDLE;
              end
            end else if (sel_sram_max_valid_q[action_port_q] &&
                         rank_seq_less(action_rank_q, action_seq_q,
                                       sel_sram_max_rank_q[action_port_q],
                                       sel_sram_max_seq_q[action_port_q])) begin
              old_desc_v = sel_sram_max_desc_q[action_port_q];
              old_cells_v = cell_count16(sel_sram_max_cell_count_q[action_port_q]);
              if ((sram_free_count_q + old_cells_v) >= action_cells_v) begin
                if (append_room_ready(old_cells_v) || append_needs_submit(old_cells_v)) begin
                  queue_sram_desc_to_hbm(old_desc_v, old_cells_v, 1'b0, ST_ADMIT_COMMIT_SRAM, 1'b1);
                end else begin
                  drop_action_packet();
                  state_q <= ST_IDLE;
                end
              end else if (sel_swapout_valid_q && (sel_swapout_desc_q != old_desc_v)) begin
                old_desc_v = sel_swapout_desc_q;
                old_cells_v = cell_count16(sel_swapout_cell_count_q);
                if (append_room_ready(old_cells_v) || append_needs_submit(old_cells_v)) begin
                  queue_sram_desc_to_hbm(old_desc_v, old_cells_v, 1'b1, ST_ADMISSION, 1'b1);
                end else begin
                  drop_action_packet();
                  state_q <= ST_IDLE;
                end
              end else begin
                drop_action_packet();
                state_q <= ST_IDLE;
              end
            end else begin
              if (append_room_ready(action_cells_v)) begin
                create_hbm_packet(action_port_q, action_rank_q, action_seq_q,
                                  action_cell_count_q, action_payload_q);
                refresh_then(ST_IDLE);
              end else if (append_needs_submit(action_cells_v)) begin
                submit_open_batch();
                state_q <= ST_ADMISSION;
              end else begin
                drop_action_packet();
                state_q <= ST_IDLE;
              end
            end
          end
          end
        end

        ST_ADMIT_COMMIT_SRAM: begin
          action_cells_v = cell_count16(action_cell_count_q);
          if ((desc_free_count_q != 16'd0) && (sram_free_count_q >= action_cells_v)) begin
            create_sram_packet(action_port_q, action_rank_q, action_seq_q,
                               action_cell_count_q, action_payload_q);
            refresh_then(ST_IDLE);
          end else begin
            drop_action_packet();
            state_q <= ST_IDLE;
          end
        end

        ST_SWAPOUT_BUILD: begin
          if (!sel_swapout_valid_q || !sel_water_swapout_pending_q) begin
            if (open_batch_valid_q && (open_batch_valid_count_q != 16'd0)) begin
              submit_open_batch();
              state_q <= ST_IDLE;
            end else begin
              state_q <= ST_IDLE;
            end
          end else begin
            old_desc_v = sel_swapout_desc_q;
            old_cells_v = cell_count16(sel_swapout_cell_count_q);
            if (append_room_ready(old_cells_v) || append_needs_submit(old_cells_v)) begin
              queue_sram_desc_to_hbm(old_desc_v, old_cells_v, 1'b1, ST_SWAPOUT_BUILD, 1'b0);
            end else begin
              state_q <= ST_IDLE;
            end
          end
        end

        ST_STAGE_SRAM_TO_HBM: begin
          if (append_room_ready(stage_sram_cells_q)) begin
            stage_sram_desc_to_hbm(stage_sram_desc_q, stage_sram_cells_q,
                                   stage_sram_count_as_swap_q, stage_sram_return_q);
          end else if (append_needs_submit(stage_sram_cells_q)) begin
            submit_open_batch();
            state_q <= ST_STAGE_SRAM_TO_HBM;
          end else begin
            if (stage_sram_drop_on_fail_q) begin
              drop_action_packet();
            end
            state_q <= ST_IDLE;
          end
        end

        ST_SWAPIN_SCAN: begin
          if (swapin_offset_q == BATCH_SIZE) begin
            free_batch_slot(swapin_batch_q);
            state_q <= ST_IDLE;
          end else if (!batch_cell_valid[swapin_batch_q][swapin_offset_q[BATCH_OFF_W-1:0]]) begin
            swapin_offset_q <= swapin_offset_q + 1'b1;
          end else begin
            old_desc_v = batch_cell_desc[swapin_batch_q][swapin_offset_q[BATCH_OFF_W-1:0]];
            old_cells_v = cell_count16(desc_cell_count[old_desc_v]);
            swapin_commit_batch_q <= swapin_batch_q;
            swapin_commit_offset_q <= swapin_offset_q[BATCH_OFF_W-1:0];
            swapin_commit_desc_q <= old_desc_v;
            swapin_commit_cells_q <= old_cells_v;
            state_q <= ST_SWAPIN_COMMIT;
          end
        end

        ST_SWAPIN_COMMIT: begin
          if (sram_free_count_q >= swapin_commit_cells_q) begin
            for (oi = 0; oi < BATCH_SIZE; oi = oi + 1) begin
              if (oi < swapin_commit_cells_q) begin
                batch_cell_valid[swapin_commit_batch_q][swapin_commit_offset_q + oi] <= 1'b0;
              end
            end
            batch_valid_count[swapin_commit_batch_q] <=
              batch_valid_count[swapin_commit_batch_q] - swapin_commit_cells_q;
            swapin_desc_to_sram(swapin_commit_desc_q);
            swapin_offset_q <= swapin_commit_offset_q + swapin_commit_cells_q;
            refresh_then(ST_SWAPIN_SCAN);
          end else begin
            state_q <= ST_IDLE;
          end
        end

        ST_MIGRATE_COMMIT: begin
          if (migrate_valid_q) begin
            ddr_wait_batch_q <= desc_batch_id[migrate_desc_q];
            if (batch_committed[desc_batch_id[migrate_desc_q]] && bbq_ready_q[desc_port[migrate_desc_q]]) begin
              commit_sram_desc_to_hbm(migrate_desc_q, migrate_count_as_swap_q);
              migrate_valid_q <= 1'b0;
              refresh_then(migrate_return_q);
            end else if (open_batch_valid_q &&
                         (open_batch_id_q == desc_batch_id[migrate_desc_q]) &&
                         !batch_write_pending[desc_batch_id[migrate_desc_q]]) begin
              submit_open_batch();
              state_q <= ST_MIGRATE_COMMIT;
            end
          end else begin
            state_q <= ST_IDLE;
          end
        end

        ST_SELECTOR_REFRESH: begin
          if (!all_bbq_ready_q) begin
            refresh_count_q <= '0;
          end else if (refresh_count_q == SELECT_REFRESH_LAST) begin
            refresh_count_q <= '0;
            state_q <= refresh_return_q;
          end else begin
            refresh_count_q <= refresh_count_q + 1'b1;
          end
        end

        ST_DEQ_DDR_PREP: begin
          if (batch_committed[ddr_wait_batch_q]) begin
            rd_addr_q <= ddr_cell_addr(ddr_deq_batch_q, ddr_deq_offset_q);
            rd_beat_q <= '0;
            m_axi_arvalid <= 1'b1;
            state_q <= ST_DEQ_DDR_ADDR;
          end else begin
            if (open_batch_valid_q &&
                (open_batch_id_q == ddr_wait_batch_q) &&
                !batch_write_pending[ddr_wait_batch_q]) begin
              submit_open_batch();
              state_q <= ST_DEQ_DDR_WAIT_COMMIT;
            end else begin
              state_q <= ST_DEQ_DDR_WAIT_COMMIT;
            end
          end
        end

        ST_DEQ_DDR_WAIT_COMMIT: begin
          if (batch_committed[ddr_wait_batch_q]) begin
            rd_addr_q <= ddr_cell_addr(ddr_deq_batch_q, ddr_deq_offset_q);
            rd_beat_q <= '0;
            m_axi_arvalid <= 1'b1;
            state_q <= ST_DEQ_DDR_ADDR;
          end else if (open_batch_valid_q &&
                       (open_batch_id_q == ddr_wait_batch_q) &&
                       !batch_write_pending[ddr_wait_batch_q]) begin
            submit_open_batch();
            state_q <= ST_DEQ_DDR_WAIT_COMMIT;
          end
        end

        ST_DEQ_DDR_ADDR: begin
          if (m_axi_arvalid && m_axi_arready) begin
            m_axi_arvalid <= 1'b0;
            state_q <= ST_DEQ_DDR_DATA;
          end
        end

        ST_DEQ_DDR_DATA: begin
          if (ddr_r_accept_c) begin
            ddr_rd_error_v = (m_axi_rresp != 2'b00) |
                             (m_axi_rlast != ddr_r_direct_last_c);
            if (ENABLE_DDR_META_CHECK && (rd_beat_q == '0)) begin
              ddr_rd_error_v = ddr_rd_error_v |
                               (unpack_ddr_desc(m_axi_rdata) != ddr_deq_desc_q);
            end
            stat_ddr_read_beats <= stat_ddr_read_beats + 32'd1;
            ddr_rd_error_q <= ddr_rd_error_q | ddr_rd_error_v;
            if (ddr_r_direct_last_c) begin
              state_q <= ST_DEQ_DDR_COMMIT;
            end
            rd_beat_q <= rd_beat_q + 1'b1;
          end
        end

        ST_DEQ_DDR_COMMIT: begin
          dequeue_hbm_desc(ddr_deq_port_q, ddr_deq_desc_q, ddr_deq_cells_q,
                           ddr_deq_batch_q, ddr_deq_offset_q);
          store_read_rr_q <= (ddr_deq_port_q == LAST_PORT) ? '0 : (ddr_deq_port_q + 1'b1);
          refresh_then(ST_IDLE);
        end

        ST_SWAPIN_DDR_PREP: begin
          if (batch_committed[swapin_batch_q]) begin
            rd_batch_q <= swapin_batch_q;
            rd_addr_q <= ddr_batch_addr(swapin_batch_q);
            rd_beat_q <= '0;
            m_axi_arvalid <= 1'b1;
            state_q <= ST_SWAPIN_DDR_ADDR;
          end else begin
            if (open_batch_valid_q &&
                (open_batch_id_q == swapin_batch_q) &&
                !batch_write_pending[swapin_batch_q]) begin
              submit_open_batch();
              state_q <= ST_SWAPIN_DDR_WAIT_COMMIT;
            end else begin
              state_q <= ST_SWAPIN_DDR_WAIT_COMMIT;
            end
          end
        end

        ST_SWAPIN_DDR_WAIT_COMMIT: begin
          if (batch_committed[swapin_batch_q]) begin
            rd_batch_q <= swapin_batch_q;
            rd_addr_q <= ddr_batch_addr(swapin_batch_q);
            rd_beat_q <= '0;
            m_axi_arvalid <= 1'b1;
            state_q <= ST_SWAPIN_DDR_ADDR;
          end else if (open_batch_valid_q &&
                       (open_batch_id_q == swapin_batch_q) &&
                       !batch_write_pending[swapin_batch_q]) begin
            submit_open_batch();
            state_q <= ST_SWAPIN_DDR_WAIT_COMMIT;
          end
        end

        ST_SWAPIN_DDR_ADDR: begin
          if (m_axi_arvalid && m_axi_arready) begin
            m_axi_arvalid <= 1'b0;
            state_q <= ST_SWAPIN_DDR_DRAIN;
          end
        end

        ST_SWAPIN_DDR_DRAIN: begin
          if (ddr_r_accept_c) begin
            ddr_rd_error_v = (m_axi_rresp != 2'b00) |
                             (m_axi_rlast != ddr_r_swapin_last_c);
            if (ENABLE_DDR_META_CHECK &&
                batch_cell_valid[rd_batch_q][rd_beat_q[BATCH_OFF_W-1:0]]) begin
              ddr_rd_error_v = ddr_rd_error_v |
                               (unpack_ddr_desc(m_axi_rdata) !=
                                batch_cell_desc[rd_batch_q][rd_beat_q[BATCH_OFF_W-1:0]]);
            end
            stat_ddr_read_beats <= stat_ddr_read_beats + 32'd1;
            ddr_rd_error_q <= ddr_rd_error_q | ddr_rd_error_v;
            if (ddr_r_swapin_last_c) begin
              stat_ddr_read_batches <= stat_ddr_read_batches + 32'd1;
              swapin_offset_q <= '0;
              state_q <= ST_SWAPIN_SCAN;
            end
            rd_beat_q <= rd_beat_q + 1'b1;
          end
        end

        default: begin
          state_q <= ST_IDLE;
        end
      endcase
    end
  end
endmodule
