`timescale 1ns/1ps

import hestia_pkg::*;

module hestia_faithful_core #(
  parameter int PORTS = 8,
  parameter int RANK_WIDTH = 10,
  parameter int SEQ_WIDTH = 32,
  parameter int PAYLOAD_WIDTH = 64,
  parameter int CELL_COUNT_WIDTH = 4,
  parameter int SRAM_CELLS = 64,
  parameter int BATCH_SIZE = 8,
  parameter int BATCH_SLOTS = 16,
  parameter int PACKET_SLOTS = 128,
  parameter int BBQ_BITMAP_WIDTH = (RANK_WIDTH <= 8) ? 16 : 32,
  localparam int PORT_W = (PORTS <= 2) ? 1 : $clog2(PORTS),
  localparam int SRAM_SLOT_W = (SRAM_CELLS <= 2) ? 1 : $clog2(SRAM_CELLS),
  localparam int BATCH_ID_W = (BATCH_SLOTS <= 2) ? 1 : $clog2(BATCH_SLOTS),
  localparam int BATCH_OFF_W = (BATCH_SIZE <= 2) ? 1 : $clog2(BATCH_SIZE),
  localparam int DESC_W = (PACKET_SLOTS <= 2) ? 1 : $clog2(PACKET_SLOTS)
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

  output logic [31:0]                      stat_generated,
  output logic [31:0]                      stat_dequeued,
  output logic [31:0]                      stat_sram_admit,
  output logic [31:0]                      stat_hbm_admit,
  output logic [31:0]                      stat_swap_out,
  output logic [31:0]                      stat_swap_in,
  output logic [31:0]                      stat_direct_hbm_dequeue,
  output logic [31:0]                      stat_drop,
  output logic [31:0]                      stat_batch_submit,
  output logic [15:0]                      dbg_global_sram_occupancy,
  output logic [15:0]                      dbg_global_hbm_occupancy,
  output logic [PORTS*16-1:0]              dbg_sram_count_flat,
  output logic [PORTS*16-1:0]              dbg_hbm_count_flat,
  output logic [15:0]                      dbg_open_batch_cells
);
  typedef enum logic [2:0] {
    ST_IDLE,
    ST_ADMISSION,
    ST_ADMIT_COMMIT_SRAM,
    ST_SWAPOUT_BUILD,
    ST_SWAPIN_SCAN,
    ST_MIGRATE_COMMIT,
    ST_SELECTOR_REFRESH
  } state_t;

  state_t state_q;
  state_t refresh_return_q;
  logic [1:0] refresh_count_q;

  logic [PORT_W-1:0] action_port_q;
  logic [RANK_WIDTH-1:0] action_rank_q;
  logic [SEQ_WIDTH-1:0] action_seq_q;
  logic [CELL_COUNT_WIDTH-1:0] action_cell_count_q;
  logic [PAYLOAD_WIDTH-1:0] action_payload_q;

  logic [BATCH_ID_W-1:0] swapin_batch_q;
  logic [BATCH_OFF_W:0] swapin_offset_q;

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

  logic sram_cell_valid [0:SRAM_CELLS-1];
  (* ram_style = "distributed" *) logic [DESC_W-1:0] sram_cell_desc [0:SRAM_CELLS-1];
  logic [SRAM_SLOT_W-1:0] sram_free_list [0:SRAM_CELLS-1];
  logic [SRAM_SLOT_W-1:0] sram_free_rd_q;
  logic [SRAM_SLOT_W-1:0] sram_free_wr_q;
  logic [15:0] sram_free_count_q;

  logic batch_cell_valid [0:BATCH_SLOTS-1][0:BATCH_SIZE-1];
  (* ram_style = "distributed" *) logic [DESC_W-1:0] batch_cell_desc [0:BATCH_SLOTS-1][0:BATCH_SIZE-1];
  logic [15:0] batch_valid_count [0:BATCH_SLOTS-1];
  logic [BATCH_OFF_W:0] batch_fill_count [0:BATCH_SLOTS-1];
  logic batch_committed [0:BATCH_SLOTS-1];
  logic [BATCH_ID_W-1:0] batch_free_list [0:BATCH_SLOTS-1];
  logic [BATCH_ID_W-1:0] batch_free_rd_q;
  logic [BATCH_ID_W-1:0] batch_free_wr_q;
  logic [15:0] batch_free_count_q;
  logic open_batch_valid_q;
  logic [BATCH_ID_W-1:0] open_batch_id_q;

  logic [15:0] total_count_q [0:PORTS-1];
  logic [15:0] sram_count_q [0:PORTS-1];
  logic [15:0] hbm_count_q [0:PORTS-1];

  logic bbq_cmd_valid [0:PORTS-1];
  mp_bbq_cmd_t bbq_cmd_op [0:PORTS-1];
  logic [DESC_W-1:0] bbq_cmd_desc [0:PORTS-1];
  logic [RANK_WIDTH-1:0] bbq_cmd_rank [0:PORTS-1];
  logic [SEQ_WIDTH-1:0] bbq_cmd_seq [0:PORTS-1];
  logic [CELL_COUNT_WIDTH-1:0] bbq_cmd_cell_count [0:PORTS-1];
  logic [BATCH_ID_W-1:0] bbq_cmd_batch_id [0:PORTS-1];
  logic [BATCH_OFF_W-1:0] bbq_cmd_batch_offset [0:PORTS-1];
  logic bbq_cmd_ready [0:PORTS-1];

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

  logic record_valid_c;
  logic [PORT_W-1:0] record_port_c;
  logic [DESC_W-1:0] record_desc_c;
  logic [BATCH_ID_W-1:0] record_batch_c;
  logic [15:0] record_first_rank_c;
  logic [RANK_WIDTH-1:0] record_second_rank_c;
  logic [SEQ_WIDTH-1:0] record_seq_c;

  logic swapout_valid_c;
  logic [PORT_W-1:0] swapout_port_c;
  logic [DESC_W-1:0] swapout_desc_c;
  logic [15:0] swapout_first_rank_c;
  logic [RANK_WIDTH-1:0] swapout_rank_c;
  logic [SEQ_WIDTH-1:0] swapout_seq_c;

  logic port_deq_req_valid_c [0:PORTS-1];
  logic [DESC_W-1:0] port_deq_req_desc_c [0:PORTS-1];
  logic store_read_grant_valid_c;
  logic [PORT_W-1:0] store_read_grant_port_c;
  logic [DESC_W-1:0] store_read_grant_desc_c;
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
  logic sel_sram_max_valid_q [0:PORTS-1];
  logic [DESC_W-1:0] sel_sram_max_desc_q [0:PORTS-1];
  logic [RANK_WIDTH-1:0] sel_sram_max_rank_q [0:PORTS-1];
  logic [SEQ_WIDTH-1:0] sel_sram_max_seq_q [0:PORTS-1];
  logic sel_water_swapout_pending_q;
  logic sel_water_swapin_pending_q;

  logic [RANK_WIDTH-1:0] out_rank_q [0:PORTS-1];
  logic [SEQ_WIDTH-1:0] out_seq_q [0:PORTS-1];
  logic [CELL_COUNT_WIDTH-1:0] out_cell_count_q [0:PORTS-1];
  logic [PAYLOAD_WIDTH-1:0] out_payload_q [0:PORTS-1];

  logic migrate_valid_q;
  logic [DESC_W-1:0] migrate_desc_q;
  logic migrate_count_as_swap_q;
  state_t migrate_return_q;

  genvar gp;
  generate
    for (gp = 0; gp < PORTS; gp = gp + 1) begin : g_out
      assign m_pkt_rank[gp*RANK_WIDTH +: RANK_WIDTH] = out_rank_q[gp];
      assign m_pkt_seq[gp*SEQ_WIDTH +: SEQ_WIDTH] = out_seq_q[gp];
      assign m_pkt_cell_count[gp*CELL_COUNT_WIDTH +: CELL_COUNT_WIDTH] = out_cell_count_q[gp];
      assign m_pkt_payload[gp*PAYLOAD_WIDTH +: PAYLOAD_WIDTH] = out_payload_q[gp];
      assign dbg_sram_count_flat[gp*16 +: 16] = sram_count_q[gp];
      assign dbg_hbm_count_flat[gp*16 +: 16] = hbm_count_q[gp];

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

  localparam logic [15:0] SRAM_CELLS_U16 = SRAM_CELLS;
  localparam logic [15:0] BATCH_SIZE_U16 = BATCH_SIZE;
  localparam logic [15:0] PACKET_SLOTS_U16 = PACKET_SLOTS;
  localparam logic [15:0] BATCH_SLOTS_U16 = BATCH_SLOTS;
  localparam logic [PORT_W-1:0] LAST_PORT = PORTS - 1;

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

  function automatic logic append_room_ready(input logic [15:0] cells_i);
    begin
      if (open_batch_valid_q) begin
        append_room_ready = (batch_fill_count[open_batch_id_q] + cells_i) <= BATCH_SIZE_U16;
      end else begin
        append_room_ready = (batch_free_count_q != 16'd0);
      end
    end
  endfunction

  function automatic logic append_needs_submit(input logic [15:0] cells_i);
    begin
      append_needs_submit = open_batch_valid_q &&
                            ((batch_fill_count[open_batch_id_q] + cells_i) > BATCH_SIZE_U16);
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
      refresh_count_q <= 2'd0;
      state_q <= ST_SELECTOR_REFRESH;
    end
  endtask

  task automatic submit_open_batch;
    begin
      if (open_batch_valid_q) begin
        if (batch_valid_count[open_batch_id_q] != 16'd0) begin
          batch_committed[open_batch_id_q] <= 1'b1;
          stat_batch_submit <= stat_batch_submit + 32'd1;
        end else begin
          batch_free_list[batch_free_wr_q] <= open_batch_id_q;
          batch_free_wr_q <= batch_ptr_add(batch_free_wr_q, 16'd1);
          batch_free_count_q <= batch_free_count_q + 16'd1;
        end
        open_batch_valid_q <= 1'b0;
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
          sram_cell_valid[slot_v] <= 1'b1;
          sram_cell_desc[slot_v] <= desc_i;
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
          sram_cell_valid[slot_v] <= 1'b0;
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
    int fi;
    begin
      for (fi = 0; fi < BATCH_SIZE; fi = fi + 1) begin
        batch_cell_valid[batch_i][fi] <= 1'b0;
        batch_cell_desc[batch_i][fi] <= '0;
      end
      batch_valid_count[batch_i] <= 16'd0;
      batch_fill_count[batch_i] <= '0;
      batch_committed[batch_i] <= 1'b0;
      if (open_batch_valid_q && (open_batch_id_q == batch_i)) begin
        open_batch_valid_q <= 1'b0;
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
    begin
      if (open_batch_valid_q) begin
        batch_v = open_batch_id_q;
        offset_v = batch_fill_count[open_batch_id_q];
      end else begin
        batch_v = batch_free_head();
        offset_v = '0;
        batch_free_rd_q <= batch_ptr_add(batch_free_rd_q, 16'd1);
        batch_free_count_q <= batch_free_count_q - 16'd1;
        open_batch_valid_q <= 1'b1;
        open_batch_id_q <= batch_v;
        batch_valid_count[batch_v] <= 16'd0;
        batch_fill_count[batch_v] <= '0;
        batch_committed[batch_v] <= 1'b0;
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
      batch_fill_count[batch_v] <= offset_v + cells_i;
      batch_valid_count[batch_v] <= batch_valid_count[batch_v] + cells_i;

      if ((offset_v + cells_i) == BATCH_SIZE_U16) begin
        batch_committed[batch_v] <= 1'b1;
        open_batch_valid_q <= 1'b0;
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
      if (batch_valid_count[batch_v] == cells_v) begin
        free_batch_slot(batch_v);
      end else begin
        batch_valid_count[batch_v] <= batch_valid_count[batch_v] - cells_v;
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
      total_count_q[port_i] <= total_count_q[port_i] + cells16_v;
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
      total_count_q[port_i] <= total_count_q[port_i] + cells16_v;
      hbm_count_q[port_i] <= hbm_count_q[port_i] + cells16_v;
      stat_generated <= stat_generated + 32'd1;
      stat_hbm_admit <= stat_hbm_admit + 32'd1;
    end
  endtask

  task automatic stage_sram_desc_to_hbm(
    input logic [DESC_W-1:0] desc_i,
    input logic count_as_swap_i,
    input state_t return_state_i
  );
    logic [15:0] cells_v;
    logic [BATCH_ID_W-1:0] batch_v;
    logic [BATCH_OFF_W-1:0] offset_v;
    begin
      cells_v = cell_count16(desc_cell_count[desc_i]);
      append_desc_to_batch(desc_i, cells_v, batch_v, offset_v);
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

  task automatic replace_sram_desc_with_new(
    input logic [DESC_W-1:0] old_desc_i,
    input logic [PORT_W-1:0] port_i,
    input logic [RANK_WIDTH-1:0] rank_i,
    input logic [SEQ_WIDTH-1:0] seq_i,
    input logic [CELL_COUNT_WIDTH-1:0] cells_i,
    input logic [PAYLOAD_WIDTH-1:0] payload_i
  );
    int ri;
    int extra_alloc_i;
    int extra_free_i;
    logic [DESC_W-1:0] new_desc_v;
    logic [15:0] old_cells_v;
    logic [15:0] new_cells_v;
    logic [15:0] extra_alloc_v;
    logic [15:0] extra_free_v;
    logic [BATCH_ID_W-1:0] batch_v;
    logic [BATCH_OFF_W-1:0] offset_v;
    logic [SRAM_SLOT_W-1:0] slot_v;
    begin
      new_desc_v = desc_free_head();
      old_cells_v = cell_count16(desc_cell_count[old_desc_i]);
      new_cells_v = cell_count16(cells_i);
      extra_alloc_v = (new_cells_v > old_cells_v) ? (new_cells_v - old_cells_v) : 16'd0;
      extra_free_v = (old_cells_v > new_cells_v) ? (old_cells_v - new_cells_v) : 16'd0;

      append_desc_to_batch(old_desc_i, old_cells_v, batch_v, offset_v);
      desc_loc[old_desc_i] <= MP_LOC_HBM;
      desc_free_rd_q <= desc_ptr_add(desc_free_rd_q, 16'd1);
      desc_free_count_q <= desc_free_count_q - 16'd1;

      desc_valid[new_desc_v] <= 1'b1;
      desc_loc[new_desc_v] <= MP_LOC_SRAM;
      desc_port[new_desc_v] <= port_i;
      desc_rank[new_desc_v] <= rank_i;
      desc_seq[new_desc_v] <= seq_i;
      desc_cell_count[new_desc_v] <= cells_i;
      desc_payload[new_desc_v] <= payload_i;
      desc_batch_id[new_desc_v] <= '0;
      desc_batch_offset[new_desc_v] <= '0;

      for (ri = 0; ri < BATCH_SIZE; ri = ri + 1) begin
        if (ri < new_cells_v) begin
          if (ri < old_cells_v) begin
            slot_v = desc_sram_cell[old_desc_i][ri];
          end else begin
            slot_v = sram_free_list[sram_ptr_add(sram_free_rd_q, ri - old_cells_v)];
          end
          desc_sram_cell[new_desc_v][ri] <= slot_v;
          sram_cell_valid[slot_v] <= 1'b1;
          sram_cell_desc[slot_v] <= new_desc_v;
        end
      end

      for (extra_free_i = 0; extra_free_i < BATCH_SIZE; extra_free_i = extra_free_i + 1) begin
        if (extra_free_i < extra_free_v) begin
          slot_v = desc_sram_cell[old_desc_i][new_cells_v + extra_free_i];
          sram_cell_valid[slot_v] <= 1'b0;
          sram_free_list[sram_ptr_add(sram_free_wr_q, extra_free_i[15:0])] <= slot_v;
        end
      end

      if (extra_alloc_v != 16'd0) begin
        sram_free_rd_q <= sram_ptr_add(sram_free_rd_q, extra_alloc_v);
        sram_free_count_q <= sram_free_count_q - extra_alloc_v;
      end else if (extra_free_v != 16'd0) begin
        sram_free_wr_q <= sram_ptr_add(sram_free_wr_q, extra_free_v);
        sram_free_count_q <= sram_free_count_q + extra_free_v;
      end

      total_count_q[port_i] <= total_count_q[port_i] + new_cells_v;
      sram_count_q[port_i] <= sram_count_q[port_i] + new_cells_v - old_cells_v;
      hbm_count_q[port_i] <= hbm_count_q[port_i] + old_cells_v;
      stat_generated <= stat_generated + 32'd1;
      stat_sram_admit <= stat_sram_admit + 32'd1;
      stat_hbm_admit <= stat_hbm_admit + 32'd1;
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
      total_count_q[port_i] <= total_count_q[port_i] - cells_v;
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
    global_sram_c = 16'd0;
    global_hbm_c = 16'd0;
    record_valid_c = 1'b0;
    record_port_c = '0;
    record_desc_c = '0;
    record_batch_c = '0;
    record_first_rank_c = '1;
    record_second_rank_c = '1;
    record_seq_c = '1;
    all_bbq_ready_c = 1'b1;
    swapout_valid_c = 1'b0;
    swapout_port_c = '0;
    swapout_desc_c = '0;
    swapout_first_rank_c = 16'd0;
    swapout_rank_c = '0;
    swapout_seq_c = '0;
    store_read_grant_valid_c = 1'b0;
    store_read_grant_port_c = store_read_rr_q;
    store_read_grant_desc_c = '0;

    for (pi = 0; pi < PORTS; pi = pi + 1) begin
      global_sram_c = global_sram_c + sram_count_q[pi];
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

    for (pi = 0; pi < PORTS; pi = pi + 1) begin
      if (hbm_min_valid_c[pi]) begin
        if (!record_valid_c ||
            (sram_count_q[pi] < record_first_rank_c) ||
            ((sram_count_q[pi] == record_first_rank_c) &&
             rank_seq_less(mask_hbm_min_rank_q[pi], mask_hbm_min_seq_q[pi],
                           record_second_rank_c, record_seq_c))) begin
          record_valid_c = 1'b1;
          record_port_c = pi[PORT_W-1:0];
          record_desc_c = hbm_min_desc_c[pi];
          record_batch_c = mask_hbm_min_batch_id_q[pi];
          record_first_rank_c = sram_count_q[pi];
          record_second_rank_c = mask_hbm_min_rank_q[pi];
          record_seq_c = mask_hbm_min_seq_q[pi];
        end
      end

      if (sram_max_valid_c[pi]) begin
        if (!swapout_valid_c ||
            (sram_count_q[pi] > swapout_first_rank_c) ||
            ((sram_count_q[pi] == swapout_first_rank_c) &&
             rank_seq_greater(mask_sram_max_rank_q[pi], mask_sram_max_seq_q[pi],
                              swapout_rank_c, swapout_seq_c))) begin
          swapout_valid_c = 1'b1;
          swapout_port_c = pi[PORT_W-1:0];
          swapout_desc_c = sram_max_desc_c[pi];
          swapout_first_rank_c = sram_count_q[pi];
          swapout_rank_c = mask_sram_max_rank_q[pi];
          swapout_seq_c = mask_sram_max_seq_q[pi];
        end
      end
    end

    for (deq_i = 0; deq_i < PORTS; deq_i = deq_i + 1) begin
      deq_idx_i = store_read_rr_q + deq_i;
      if (deq_idx_i >= PORTS) begin
        deq_idx_i = deq_idx_i - PORTS;
      end
      if (!store_read_grant_valid_c && all_bbq_ready_c && port_deq_req_valid_c[deq_idx_i]) begin
        store_read_grant_valid_c = 1'b1;
        store_read_grant_port_c = deq_idx_i[PORT_W-1:0];
        store_read_grant_desc_c = port_deq_req_desc_c[deq_idx_i];
      end
    end

    water_swapout_pending_c = enable && (global_sram_c > cfg_swap_out_threshold) &&
                              swapout_valid_c;
    water_swapin_pending_c = enable && (global_sram_c < cfg_swap_in_threshold) &&
                             record_valid_c &&
                             (batch_valid_count[record_batch_c] <= sram_free_count_q);

    s_pkt_ready = enable && all_bbq_ready_c && (state_q == ST_IDLE) &&
                  !store_read_grant_valid_c &&
                  !sel_water_swapout_pending_q &&
                  !sel_water_swapin_pending_q &&
                  (desc_free_count_q != 16'd0) &&
                  (s_pkt_cell_count != '0) &&
                  (cell_count16(s_pkt_cell_count) <= BATCH_SIZE_U16);

    dbg_global_sram_occupancy = global_sram_c;
    dbg_global_hbm_occupancy = global_hbm_c;
    dbg_open_batch_cells = open_batch_valid_q ? batch_fill_count[open_batch_id_q] : 16'd0;
  end

  integer ri;
  integer bi;
  integer oi;
  always_ff @(posedge clk) begin
    logic [15:0] action_cells_v;
    logic new_better_record_v;
    logic [DESC_W-1:0] old_desc_v;
    logic [15:0] old_cells_v;
    if (!resetn) begin
      state_q <= ST_IDLE;
      refresh_return_q <= ST_IDLE;
      refresh_count_q <= 2'd0;
      action_port_q <= '0;
      action_rank_q <= '0;
      action_seq_q <= '0;
      action_cell_count_q <= '0;
      action_payload_q <= '0;
      swapin_batch_q <= '0;
      swapin_offset_q <= '0;
      store_read_rr_q <= '0;
      migrate_valid_q <= 1'b0;
      migrate_desc_q <= '0;
      migrate_count_as_swap_q <= 1'b0;
      migrate_return_q <= ST_IDLE;
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
      sel_water_swapout_pending_q <= 1'b0;
      sel_water_swapin_pending_q <= 1'b0;
      for (ri = 0; ri < PORTS; ri = ri + 1) begin
        total_count_q[ri] <= 16'd0;
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
        cand_sram_min_valid_q[ri] <= 1'b0;
        cand_sram_min_desc_q[ri] <= '0;
        cand_sram_min_rank_q[ri] <= '0;
        cand_sram_min_seq_q[ri] <= '0;
        cand_sram_max_valid_q[ri] <= 1'b0;
        cand_sram_max_desc_q[ri] <= '0;
        cand_sram_max_rank_q[ri] <= '0;
        cand_sram_max_seq_q[ri] <= '0;
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
        mask_hbm_min_valid_q[ri] <= 1'b0;
        mask_hbm_min_desc_q[ri] <= '0;
        mask_hbm_min_rank_q[ri] <= '0;
        mask_hbm_min_seq_q[ri] <= '0;
        mask_hbm_min_batch_id_q[ri] <= '0;
        sel_sram_max_valid_q[ri] <= 1'b0;
        sel_sram_max_desc_q[ri] <= '0;
        sel_sram_max_rank_q[ri] <= '0;
        sel_sram_max_seq_q[ri] <= '0;
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
        sram_cell_valid[ri] <= 1'b0;
        sram_cell_desc[ri] <= '0;
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
      stat_generated <= 32'd0;
      stat_dequeued <= 32'd0;
      stat_sram_admit <= 32'd0;
      stat_hbm_admit <= 32'd0;
      stat_swap_out <= 32'd0;
      stat_swap_in <= 32'd0;
      stat_direct_hbm_dequeue <= 32'd0;
      stat_drop <= 32'd0;
      stat_batch_submit <= 32'd0;
    end else begin
      for (ri = 0; ri < PORTS; ri = ri + 1) begin
        bbq_cmd_valid[ri] <= 1'b0;
        bbq_cmd_op[ri] <= MP_BBQ_CMD_NONE;
        cand_sram_min_valid_q[ri] <= bbq_sram_min_valid[ri];
        cand_sram_min_desc_q[ri] <= bbq_sram_min_desc[ri];
        cand_sram_min_rank_q[ri] <= bbq_sram_min_rank[ri];
        cand_sram_min_seq_q[ri] <= bbq_sram_min_seq[ri];
        cand_sram_max_valid_q[ri] <= bbq_sram_max_valid[ri];
        cand_sram_max_desc_q[ri] <= bbq_sram_max_desc[ri];
        cand_sram_max_rank_q[ri] <= bbq_sram_max_rank[ri];
        cand_sram_max_seq_q[ri] <= bbq_sram_max_seq[ri];
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
        if (m_pkt_valid[ri] && m_pkt_ready[ri]) begin
          m_pkt_valid[ri] <= 1'b0;
        end
      end

      sel_record_valid_q <= record_valid_c;
      sel_record_port_q <= record_port_c;
      sel_record_desc_q <= record_desc_c;
      sel_record_batch_q <= record_batch_c;
      sel_record_first_rank_q <= record_first_rank_c;
      sel_record_second_rank_q <= record_second_rank_c;
      sel_record_seq_q <= record_seq_c;
      sel_swapout_valid_q <= swapout_valid_c;
      sel_swapout_port_q <= swapout_port_c;
      sel_swapout_desc_q <= swapout_desc_c;
      sel_swapout_first_rank_q <= swapout_first_rank_c;
      sel_water_swapout_pending_q <= enable && (global_sram_c > cfg_swap_out_threshold) &&
                                      sel_swapout_valid_q;
      sel_water_swapin_pending_q <= enable && (global_sram_c < cfg_swap_in_threshold) &&
                                    sel_record_valid_q &&
                                    (batch_valid_count[sel_record_batch_q] <= sram_free_count_q);

      unique case (state_q)
        ST_IDLE: begin
          if (store_read_grant_valid_c) begin
            dequeue_desc(store_read_grant_port_c, store_read_grant_desc_c);
            store_read_rr_q <= (store_read_grant_port_c == LAST_PORT) ? '0 : (store_read_grant_port_c + 1'b1);
            refresh_then(ST_IDLE);
          end else if (sel_water_swapout_pending_q) begin
            state_q <= ST_SWAPOUT_BUILD;
          end else if (sel_water_swapin_pending_q) begin
            swapin_batch_q <= sel_record_batch_q;
            swapin_offset_q <= '0;
            state_q <= ST_SWAPIN_SCAN;
          end else if (s_pkt_valid && s_pkt_ready) begin
            action_port_q <= s_pkt_port;
            action_rank_q <= s_pkt_rank;
            action_seq_q <= s_pkt_seq;
            action_cell_count_q <= s_pkt_cell_count;
            action_payload_q <= s_pkt_payload;
            state_q <= ST_ADMISSION;
          end
        end

        ST_ADMISSION: begin
          action_cells_v = cell_count16(action_cell_count_q);
          new_better_record_v = !sel_record_valid_q ||
                                (sram_count_q[action_port_q] < sel_record_first_rank_q) ||
                                ((sram_count_q[action_port_q] == sel_record_first_rank_q) &&
                                 rank_seq_less(action_rank_q, action_seq_q,
                                               sel_record_second_rank_q, sel_record_seq_q));

          if ((action_cells_v == 16'd0) || (action_cells_v > BATCH_SIZE_U16) ||
              (desc_free_count_q == 16'd0)) begin
            drop_action_packet();
            state_q <= ST_IDLE;
          end else if (new_better_record_v) begin
            if (sram_free_count_q >= action_cells_v) begin
              create_sram_packet(action_port_q, action_rank_q, action_seq_q,
                                 action_cell_count_q, action_payload_q);
              refresh_then(ST_IDLE);
            end else if (sel_swapout_valid_q) begin
              old_desc_v = sel_swapout_desc_q;
              old_cells_v = cell_count16(desc_cell_count[old_desc_v]);
              if (append_room_ready(old_cells_v)) begin
                stage_sram_desc_to_hbm(old_desc_v, 1'b1, ST_ADMISSION);
              end else if (append_needs_submit(old_cells_v)) begin
                submit_open_batch();
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
            old_cells_v = cell_count16(desc_cell_count[old_desc_v]);
            if ((sram_free_count_q + old_cells_v) >= action_cells_v) begin
              if (append_room_ready(old_cells_v)) begin
                stage_sram_desc_to_hbm(old_desc_v, 1'b0, ST_ADMIT_COMMIT_SRAM);
              end else if (append_needs_submit(old_cells_v)) begin
                submit_open_batch();
              end else begin
                drop_action_packet();
                state_q <= ST_IDLE;
              end
            end else if (sel_swapout_valid_q && (sel_swapout_desc_q != old_desc_v)) begin
              old_desc_v = sel_swapout_desc_q;
              old_cells_v = cell_count16(desc_cell_count[old_desc_v]);
              if (append_room_ready(old_cells_v)) begin
                stage_sram_desc_to_hbm(old_desc_v, 1'b1, ST_ADMISSION);
              end else if (append_needs_submit(old_cells_v)) begin
                submit_open_batch();
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
            end else begin
              drop_action_packet();
              state_q <= ST_IDLE;
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
          if (!sel_swapout_valid_q || (global_sram_c <= cfg_swap_out_threshold)) begin
            if (open_batch_valid_q && (batch_valid_count[open_batch_id_q] != 16'd0)) begin
              submit_open_batch();
            end
            state_q <= ST_IDLE;
          end else begin
            old_desc_v = sel_swapout_desc_q;
            old_cells_v = cell_count16(desc_cell_count[old_desc_v]);
            if (append_room_ready(old_cells_v)) begin
              stage_sram_desc_to_hbm(old_desc_v, 1'b1, ST_SWAPOUT_BUILD);
            end else if (append_needs_submit(old_cells_v)) begin
              submit_open_batch();
              state_q <= ST_IDLE;
            end else begin
              state_q <= ST_IDLE;
            end
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
            if (sram_free_count_q >= old_cells_v) begin
              for (oi = 0; oi < BATCH_SIZE; oi = oi + 1) begin
                if (oi < old_cells_v) begin
                  batch_cell_valid[swapin_batch_q][desc_batch_offset[old_desc_v] + oi] <= 1'b0;
                end
              end
              batch_valid_count[swapin_batch_q] <= batch_valid_count[swapin_batch_q] - old_cells_v;
              swapin_desc_to_sram(old_desc_v);
              swapin_offset_q <= desc_batch_offset[old_desc_v] + old_cells_v;
              refresh_then(ST_SWAPIN_SCAN);
            end else begin
              state_q <= ST_IDLE;
            end
          end
        end

        ST_MIGRATE_COMMIT: begin
          if (migrate_valid_q) begin
            commit_sram_desc_to_hbm(migrate_desc_q, migrate_count_as_swap_q);
            migrate_valid_q <= 1'b0;
            refresh_then(migrate_return_q);
          end else begin
            state_q <= ST_IDLE;
          end
        end

        ST_SELECTOR_REFRESH: begin
          if (!all_bbq_ready_c) begin
            refresh_count_q <= 2'd0;
          end else if (refresh_count_q == 2'd3) begin
            refresh_count_q <= 2'd0;
            state_q <= refresh_return_q;
          end else begin
            refresh_count_q <= refresh_count_q + 2'd1;
          end
        end

        default: begin
          state_q <= ST_IDLE;
        end
      endcase
    end
  end
endmodule
