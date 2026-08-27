`timescale 1ns/1ps

import hestia_pkg::*;

module hestia_core #(
  parameter int PORTS = 8,
  parameter int RANK_WIDTH = 10,
  parameter int SEQ_WIDTH = 32,
  parameter int PAYLOAD_WIDTH = 64,
  parameter int SRAM_CELLS = 64,
  parameter int BATCH_SIZE = 4,
  parameter int BATCH_SLOTS = 16,
  parameter int PORT_QUEUE_DEPTH = 64,
  localparam int PORT_W = (PORTS <= 2) ? 1 : $clog2(PORTS),
  localparam int SRAM_SLOT_W = (SRAM_CELLS <= 2) ? 1 : $clog2(SRAM_CELLS),
  localparam int BATCH_ID_W = (BATCH_SLOTS <= 2) ? 1 : $clog2(BATCH_SLOTS),
  localparam int BATCH_OFF_W = (BATCH_SIZE <= 2) ? 1 : $clog2(BATCH_SIZE),
  localparam int PACKET_ID_WIDTH = SEQ_WIDTH
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
  input  logic [PAYLOAD_WIDTH-1:0]         s_pkt_payload,

  input  logic [PORTS-1:0]                 dequeue_enable,
  output logic [PORTS-1:0]                 m_pkt_valid,
  input  logic [PORTS-1:0]                 m_pkt_ready,
  output logic [PORTS*RANK_WIDTH-1:0]      m_pkt_rank,
  output logic [PORTS*SEQ_WIDTH-1:0]       m_pkt_seq,
  output logic [PORTS*PAYLOAD_WIDTH-1:0]   m_pkt_payload,

  output logic [31:0]                      stat_generated,
  output logic [31:0]                      stat_dequeued,
  output logic [31:0]                      stat_sram_admit,
  output logic [31:0]                      stat_hbm_admit,
  output logic [31:0]                      stat_swap_out,
  output logic [31:0]                      stat_swap_in,
  output logic [31:0]                      stat_direct_hbm_dequeue,
  output logic [31:0]                      stat_drop,
  output logic [15:0]                      dbg_global_sram_occupancy,
  output logic [15:0]                      dbg_global_hbm_occupancy,
  output logic [PORTS*16-1:0]              dbg_sram_count_flat,
  output logic [PORTS*16-1:0]              dbg_hbm_count_flat
);
  typedef enum logic [3:0] {
    ST_SELECT,
    ST_SELECT_SCAN,
    ST_IDLE,
    ST_DEQ_EXEC,
    ST_EXEC,
    ST_REPLACE_ADD_SRAM,
    ST_SWAPIN_WAIT,
    ST_SWAPIN_SCAN
  } state_t;

  typedef enum logic [2:0] {
    ACT_NONE,
    ACT_SWAP_OUT,
    ACT_START_SWAP_IN,
    ACT_INGRESS
  } action_t;

  state_t state_q;
  action_t action_q;

  logic [PORT_W-1:0] action_port_q;
  logic action_choose_replace_q;
  logic action_choose_hbm_q;
  logic [RANK_WIDTH-1:0] action_rank_q;
  logic [SEQ_WIDTH-1:0] action_seq_q;
  logic [PAYLOAD_WIDTH-1:0] action_payload_q;
  logic [BATCH_ID_W-1:0] action_batch_q;
  logic [15:0] global_sram_q;
  logic [15:0] global_hbm_q;
  logic record_valid_q;
  logic [PORT_W-1:0] record_port_q;
  logic [15:0] record_first_rank_q;
  logic [RANK_WIDTH-1:0] record_second_rank_q;
  logic [BATCH_ID_W-1:0] record_batch_q;
  logic swapout_valid_q;
  logic [PORT_W-1:0] swapout_port_q;
  logic [PORT_W:0] select_idx_q;

  logic [RANK_WIDTH-1:0] port_cmd_rank [0:PORTS-1];
  logic [SEQ_WIDTH-1:0] port_cmd_packet_id [0:PORTS-1];
  logic [SRAM_SLOT_W-1:0] port_cmd_sram_slot [0:PORTS-1];
  logic [BATCH_ID_W-1:0] port_cmd_batch_id [0:PORTS-1];
  logic [BATCH_OFF_W-1:0] port_cmd_batch_offset [0:PORTS-1];
  logic [PORTS-1:0] port_cmd_valid;
  mp_port_cmd_t port_cmd_op [0:PORTS-1];
  logic [PORTS-1:0] port_cmd_ready;
  logic [RANK_WIDTH-1:0] out_rank_q [0:PORTS-1];
  logic [SEQ_WIDTH-1:0] out_seq_q [0:PORTS-1];
  logic [PAYLOAD_WIDTH-1:0] out_payload_q [0:PORTS-1];

  logic [PORTS-1:0] sram_min_valid;
  logic [RANK_WIDTH-1:0] sram_min_rank [0:PORTS-1];
  logic [SEQ_WIDTH-1:0] sram_min_packet_id [0:PORTS-1];
  logic [SRAM_SLOT_W-1:0] sram_min_slot [0:PORTS-1];

  logic [PORTS-1:0] sram_max_valid;
  logic [RANK_WIDTH-1:0] sram_max_rank [0:PORTS-1];
  logic [SEQ_WIDTH-1:0] sram_max_packet_id [0:PORTS-1];
  logic [SRAM_SLOT_W-1:0] sram_max_slot [0:PORTS-1];

  logic [PORTS-1:0] hbm_min_valid;
  logic [RANK_WIDTH-1:0] hbm_min_rank [0:PORTS-1];
  logic [SEQ_WIDTH-1:0] hbm_min_packet_id [0:PORTS-1];
  logic [BATCH_ID_W-1:0] hbm_min_batch_id [0:PORTS-1];
  logic [BATCH_OFF_W-1:0] hbm_min_batch_offset [0:PORTS-1];
  logic [15:0] port_dbg_sram_entries [0:PORTS-1];
  logic [15:0] port_dbg_hbm_entries [0:PORTS-1];

  logic [15:0] total_count_q [0:PORTS-1];
  logic [15:0] sram_count_q [0:PORTS-1];
  logic [15:0] hbm_count_q [0:PORTS-1];

  logic sram_valid [0:SRAM_CELLS-1];
  (* ram_style = "distributed" *) logic [PORT_W-1:0] sram_port [0:SRAM_CELLS-1];
  (* ram_style = "distributed" *) logic [RANK_WIDTH-1:0] sram_rank [0:SRAM_CELLS-1];
  (* ram_style = "distributed" *) logic [SEQ_WIDTH-1:0] sram_seq [0:SRAM_CELLS-1];
  (* ram_style = "distributed" *) logic [PAYLOAD_WIDTH-1:0] sram_payload [0:SRAM_CELLS-1];
  logic [SRAM_SLOT_W-1:0] sram_free_list [0:SRAM_CELLS-1];
  logic [SRAM_SLOT_W-1:0] sram_free_rd_q;
  logic [SRAM_SLOT_W-1:0] sram_free_wr_q;
  logic [15:0] sram_free_count_q;

  logic batch_entry_valid [0:BATCH_SLOTS-1][0:BATCH_SIZE-1];
  (* ram_style = "distributed" *) logic [PORT_W-1:0] batch_port [0:BATCH_SLOTS-1][0:BATCH_SIZE-1];
  (* ram_style = "distributed" *) logic [RANK_WIDTH-1:0] batch_rank [0:BATCH_SLOTS-1][0:BATCH_SIZE-1];
  (* ram_style = "distributed" *) logic [SEQ_WIDTH-1:0] batch_seq [0:BATCH_SLOTS-1][0:BATCH_SIZE-1];
  (* ram_style = "distributed" *) logic [PAYLOAD_WIDTH-1:0] batch_payload [0:BATCH_SLOTS-1][0:BATCH_SIZE-1];
  logic [15:0] batch_valid_count [0:BATCH_SLOTS-1];
  logic [BATCH_OFF_W:0] batch_fill_count [0:BATCH_SLOTS-1];
  logic [BATCH_ID_W-1:0] batch_free_list [0:BATCH_SLOTS-1];
  logic [BATCH_ID_W-1:0] batch_free_rd_q;
  logic [BATCH_ID_W-1:0] batch_free_wr_q;
  logic [15:0] batch_free_count_q;
  logic open_batch_valid_q;
  logic [BATCH_ID_W-1:0] open_batch_id_q;

  logic [PORT_W-1:0] replace_port_q;
  logic [RANK_WIDTH-1:0] replace_rank_q;
  logic [SEQ_WIDTH-1:0] replace_seq_q;
  logic [PAYLOAD_WIDTH-1:0] replace_payload_q;
  logic [SRAM_SLOT_W-1:0] replace_slot_q;

  logic [BATCH_ID_W-1:0] swapin_batch_q;
  logic [BATCH_OFF_W:0] swapin_offset_q;

  logic record_valid_c;
  logic [PORT_W-1:0] record_port_c;
  logic [15:0] record_first_rank_c;
  logic [RANK_WIDTH-1:0] record_second_rank_c;
  logic swapout_valid_c;
  logic [PORT_W-1:0] swapout_port_c;
  logic [15:0] swapout_first_rank_c;
  logic batch_append_ready_c;
  logic [15:0] global_sram_c;
  logic [15:0] global_hbm_c;
  logic ingress_port_queue_free_c;
  logic ingress_better_record_c;
  logic water_swapout_pending_c;
  logic water_swapin_pending_c;
  logic ingress_better_record_q;
  logic water_swapout_pending_q;
  logic water_swapin_pending_q;
  logic all_ports_ready_c;
  logic deq_grant_valid_c;
  logic [PORT_W-1:0] deq_grant_port_c;
  logic deq_grant_use_hbm_c;
  logic [PORT_W-1:0] deq_rr_q;
  logic [PORT_W-1:0] deq_op_port_q;
  logic deq_op_use_hbm_q;
  logic [RANK_WIDTH-1:0] deq_op_rank_q;
  logic [SRAM_SLOT_W-1:0] deq_op_sram_slot_q;
  logic [BATCH_ID_W-1:0] deq_op_batch_q;
  logic [BATCH_OFF_W-1:0] deq_op_offset_q;

  genvar gp;
  generate
    for (gp = 0; gp < PORTS; gp = gp + 1) begin : g_ports
      hestia_port_rank_queue #(
        .RANK_WIDTH(RANK_WIDTH),
        .PACKET_ID_WIDTH(PACKET_ID_WIDTH),
        .SRAM_SLOT_WIDTH(SRAM_SLOT_W),
        .BATCH_ID_WIDTH(BATCH_ID_W),
        .BATCH_OFFSET_WIDTH(BATCH_OFF_W),
        .ENTRY_DEPTH(PORT_QUEUE_DEPTH)
      ) port_q_i (
        .clk(clk),
        .resetn(resetn),
        .cmd_valid(port_cmd_valid[gp]),
        .cmd_op(port_cmd_op[gp]),
        .cmd_rank(port_cmd_rank[gp]),
        .cmd_packet_id(port_cmd_packet_id[gp]),
        .cmd_sram_slot(port_cmd_sram_slot[gp]),
        .cmd_batch_id(port_cmd_batch_id[gp]),
        .cmd_batch_offset(port_cmd_batch_offset[gp]),
        .cmd_ready(port_cmd_ready[gp]),
        .sram_min_valid(sram_min_valid[gp]),
        .sram_min_rank(sram_min_rank[gp]),
        .sram_min_packet_id(sram_min_packet_id[gp]),
        .sram_min_slot(sram_min_slot[gp]),
        .sram_max_valid(sram_max_valid[gp]),
        .sram_max_rank(sram_max_rank[gp]),
        .sram_max_packet_id(sram_max_packet_id[gp]),
        .sram_max_slot(sram_max_slot[gp]),
        .hbm_min_valid(hbm_min_valid[gp]),
        .hbm_min_rank(hbm_min_rank[gp]),
        .hbm_min_packet_id(hbm_min_packet_id[gp]),
        .hbm_min_batch_id(hbm_min_batch_id[gp]),
        .hbm_min_batch_offset(hbm_min_batch_offset[gp]),
        .dbg_sram_entries(port_dbg_sram_entries[gp]),
        .dbg_hbm_entries(port_dbg_hbm_entries[gp])
      );

      assign m_pkt_rank[gp*RANK_WIDTH +: RANK_WIDTH] = out_rank_q[gp];
      assign m_pkt_seq[gp*SEQ_WIDTH +: SEQ_WIDTH] = out_seq_q[gp];
      assign m_pkt_payload[gp*PAYLOAD_WIDTH +: PAYLOAD_WIDTH] = out_payload_q[gp];
      assign dbg_sram_count_flat[gp*16 +: 16] = sram_count_q[gp];
      assign dbg_hbm_count_flat[gp*16 +: 16] = hbm_count_q[gp];
    end
  endgenerate

  localparam logic [15:0] SRAM_CELLS_U16 = SRAM_CELLS[15:0];
  localparam logic [15:0] BATCH_SLOTS_U16 = BATCH_SLOTS[15:0];
  localparam logic [PORT_W-1:0] LAST_PORT = PORTS - 1;

  function automatic logic [SRAM_SLOT_W-1:0] sram_free_head;
    begin
      sram_free_head = sram_free_list[sram_free_rd_q];
    end
  endfunction

  function automatic logic [BATCH_ID_W-1:0] batch_free_head;
    begin
      batch_free_head = batch_free_list[batch_free_rd_q];
    end
  endfunction

  task automatic alloc_sram_slot(output logic [SRAM_SLOT_W-1:0] slot_o);
    begin
      slot_o = sram_free_head();
      sram_free_rd_q <= (sram_free_rd_q == SRAM_CELLS-1) ? '0 : (sram_free_rd_q + 1'b1);
      sram_free_count_q <= sram_free_count_q - 16'd1;
    end
  endtask

  task automatic free_sram_slot(input logic [SRAM_SLOT_W-1:0] slot_i);
    begin
      sram_valid[slot_i] <= 1'b0;
      sram_free_list[sram_free_wr_q] <= slot_i;
      sram_free_wr_q <= (sram_free_wr_q == SRAM_CELLS-1) ? '0 : (sram_free_wr_q + 1'b1);
      sram_free_count_q <= sram_free_count_q + 16'd1;
    end
  endtask

  task automatic write_sram_cell(
    input logic [SRAM_SLOT_W-1:0] slot_i,
    input logic [PORT_W-1:0] port_i,
    input logic [RANK_WIDTH-1:0] rank_i,
    input logic [SEQ_WIDTH-1:0] seq_i,
    input logic [PAYLOAD_WIDTH-1:0] payload_i
  );
    begin
      sram_valid[slot_i] <= 1'b1;
      sram_port[slot_i] <= port_i;
      sram_rank[slot_i] <= rank_i;
      sram_seq[slot_i] <= seq_i;
      sram_payload[slot_i] <= payload_i;
    end
  endtask

  task automatic free_batch_slot(input logic [BATCH_ID_W-1:0] batch_i);
    begin
      batch_fill_count[batch_i] <= '0;
      batch_valid_count[batch_i] <= 16'd0;
      batch_free_list[batch_free_wr_q] <= batch_i;
      batch_free_wr_q <= (batch_free_wr_q == BATCH_SLOTS-1) ? '0 : (batch_free_wr_q + 1'b1);
      batch_free_count_q <= batch_free_count_q + 16'd1;
      if (open_batch_valid_q && (open_batch_id_q == batch_i)) begin
        open_batch_valid_q <= 1'b0;
      end
    end
  endtask

  task automatic append_hbm_cell(
    input logic [PORT_W-1:0] port_i,
    input logic [RANK_WIDTH-1:0] rank_i,
    input logic [SEQ_WIDTH-1:0] seq_i,
    input logic [PAYLOAD_WIDTH-1:0] payload_i,
    output logic [BATCH_ID_W-1:0] batch_o,
    output logic [BATCH_OFF_W-1:0] offset_o,
    output logic ok_o
  );
    logic use_new_batch_v;
    logic [BATCH_ID_W-1:0] batch_v;
    logic [BATCH_OFF_W-1:0] offset_v;
    begin
      ok_o = 1'b0;
      use_new_batch_v = !(open_batch_valid_q && (batch_fill_count[open_batch_id_q] < BATCH_SIZE));
      batch_v = open_batch_id_q;
      if (use_new_batch_v) begin
        if (batch_free_count_q != 16'd0) begin
          batch_v = batch_free_head();
          batch_free_rd_q <= (batch_free_rd_q == BATCH_SLOTS-1) ? '0 : (batch_free_rd_q + 1'b1);
          batch_free_count_q <= batch_free_count_q - 16'd1;
          open_batch_valid_q <= 1'b1;
          open_batch_id_q <= batch_v;
          batch_fill_count[batch_v] <= '0;
          batch_valid_count[batch_v] <= 16'd0;
        end
      end

      if ((!use_new_batch_v) || (batch_free_count_q != 16'd0)) begin
        offset_v = batch_fill_count[batch_v][BATCH_OFF_W-1:0];
        batch_entry_valid[batch_v][offset_v] <= 1'b1;
        batch_port[batch_v][offset_v] <= port_i;
        batch_rank[batch_v][offset_v] <= rank_i;
        batch_seq[batch_v][offset_v] <= seq_i;
        batch_payload[batch_v][offset_v] <= payload_i;
        batch_fill_count[batch_v] <= batch_fill_count[batch_v] + 1'b1;
        batch_valid_count[batch_v] <= batch_valid_count[batch_v] + 16'd1;
        if ((batch_fill_count[batch_v] + 1'b1) == BATCH_SIZE) begin
          open_batch_valid_q <= 1'b0;
        end
        batch_o = batch_v;
        offset_o = offset_v;
        ok_o = 1'b1;
      end else begin
        batch_o = '0;
        offset_o = '0;
      end
    end
  endtask

  task automatic invalidate_batch_cell(
    input logic [BATCH_ID_W-1:0] batch_i,
    input logic [BATCH_OFF_W-1:0] offset_i
  );
    begin
      if (batch_entry_valid[batch_i][offset_i]) begin
        batch_entry_valid[batch_i][offset_i] <= 1'b0;
        batch_valid_count[batch_i] <= batch_valid_count[batch_i] - 16'd1;
        if ((batch_valid_count[batch_i] == 16'd1) &&
            !(open_batch_valid_q && (open_batch_id_q == batch_i) &&
              (batch_fill_count[batch_i] < BATCH_SIZE))) begin
          free_batch_slot(batch_i);
        end
      end
    end
  endtask

  integer ci;
  integer di;
  integer deq_idx_i;
  always_comb begin
    global_sram_c = 16'd0;
    global_hbm_c = 16'd0;
    record_valid_c = 1'b0;
    record_port_c = '0;
    record_first_rank_c = '1;
    record_second_rank_c = '1;
    swapout_valid_c = 1'b0;
    swapout_port_c = '0;
    swapout_first_rank_c = 16'd0;
    deq_grant_valid_c = 1'b0;
    deq_grant_port_c = deq_rr_q;
    deq_grant_use_hbm_c = 1'b0;

    for (ci = 0; ci < PORTS; ci = ci + 1) begin
      global_sram_c = global_sram_c + sram_count_q[ci];
      global_hbm_c = global_hbm_c + hbm_count_q[ci];

      if ((hbm_count_q[ci] != 16'd0) && hbm_min_valid[ci]) begin
        if (!record_valid_c ||
            (sram_count_q[ci] < record_first_rank_c) ||
            ((sram_count_q[ci] == record_first_rank_c) &&
             (hbm_min_rank[ci] < record_second_rank_c))) begin
          record_valid_c = 1'b1;
          record_port_c = ci[PORT_W-1:0];
          record_first_rank_c = sram_count_q[ci];
          record_second_rank_c = hbm_min_rank[ci];
        end
      end

      if ((sram_count_q[ci] != 16'd0) && sram_max_valid[ci]) begin
        if (!swapout_valid_c ||
            (sram_count_q[ci] > swapout_first_rank_c) ||
            ((sram_count_q[ci] == swapout_first_rank_c) &&
             (sram_max_rank[ci] > sram_max_rank[swapout_port_c]))) begin
          swapout_valid_c = 1'b1;
          swapout_port_c = ci[PORT_W-1:0];
          swapout_first_rank_c = sram_count_q[ci];
        end
      end
    end

    for (di = 0; di < PORTS; di = di + 1) begin
      deq_idx_i = deq_rr_q + di;
      if (deq_idx_i >= PORTS) begin
        deq_idx_i = deq_idx_i - PORTS;
      end
      if (!deq_grant_valid_c && enable && (state_q == ST_IDLE) &&
          dequeue_enable[deq_idx_i] &&
          (!m_pkt_valid[deq_idx_i] || m_pkt_ready[deq_idx_i]) &&
          (sram_min_valid[deq_idx_i] || hbm_min_valid[deq_idx_i])) begin
        deq_grant_valid_c = 1'b1;
        deq_grant_port_c = deq_idx_i[PORT_W-1:0];
        deq_grant_use_hbm_c = hbm_min_valid[deq_idx_i] &&
                              (!sram_min_valid[deq_idx_i] ||
                               (hbm_min_rank[deq_idx_i] < sram_min_rank[deq_idx_i]));
      end
    end

    all_ports_ready_c = &(port_cmd_ready & ~port_cmd_valid);
    batch_append_ready_c = (open_batch_valid_q && (batch_fill_count[open_batch_id_q] < BATCH_SIZE)) ||
                           (batch_free_count_q != 16'd0);
    water_swapout_pending_c = enable && all_ports_ready_c &&
                              (global_sram_c > cfg_swap_out_threshold) &&
                              swapout_valid_c && batch_append_ready_c;
    water_swapin_pending_c = enable && all_ports_ready_c &&
                             (global_sram_c < cfg_swap_in_threshold) &&
                             record_valid_c &&
                             (batch_valid_count[hbm_min_batch_id[record_port_c]] <= sram_free_count_q);
    water_swapout_pending_q = enable &&
                              (global_sram_q > cfg_swap_out_threshold) &&
                              swapout_valid_q && batch_append_ready_c;
    water_swapin_pending_q = enable &&
                             (global_sram_q < cfg_swap_in_threshold) &&
                             record_valid_q &&
                             (batch_valid_count[record_batch_q] <= sram_free_count_q);
    ingress_port_queue_free_c = (port_dbg_sram_entries[s_pkt_port] +
                                 port_dbg_hbm_entries[s_pkt_port]) < PORT_QUEUE_DEPTH;
    ingress_better_record_c = !record_valid_c ||
                              (sram_count_q[s_pkt_port] < record_first_rank_c) ||
                              ((sram_count_q[s_pkt_port] == record_first_rank_c) &&
                               (s_pkt_rank < record_second_rank_c));
    ingress_better_record_q = !record_valid_q ||
                              (sram_count_q[s_pkt_port] < record_first_rank_q) ||
                              ((sram_count_q[s_pkt_port] == record_first_rank_q) &&
                               (s_pkt_rank < record_second_rank_q));
    s_pkt_ready = enable && (state_q == ST_IDLE) &&
                  !water_swapout_pending_q && !water_swapin_pending_q &&
                  !deq_grant_valid_c &&
                  ingress_port_queue_free_c &&
                  ((sram_free_count_q != 16'd0) || batch_append_ready_c ||
                   sram_max_valid[s_pkt_port]);
    dbg_global_sram_occupancy = global_sram_c;
    dbg_global_hbm_occupancy = global_hbm_c;
  end

  integer pi;
  integer bi;
  integer oi;
  always_ff @(posedge clk) begin
    logic [SRAM_SLOT_W-1:0] alloc_slot_v;
    logic [BATCH_ID_W-1:0] append_batch_v;
    logic [BATCH_OFF_W-1:0] append_offset_v;
    logic append_ok_v;
    logic [PORT_W-1:0] port_v;
    logic [PORT_W-1:0] select_port_v;
    logic choose_replace_v;
    logic choose_hbm_v;
    if (!resetn) begin
      state_q <= ST_SELECT;
      for (pi = 0; pi < PORTS; pi = pi + 1) begin
        total_count_q[pi] <= 16'd0;
        sram_count_q[pi] <= 16'd0;
        hbm_count_q[pi] <= 16'd0;
        m_pkt_valid[pi] <= 1'b0;
        out_rank_q[pi] <= '0;
        out_seq_q[pi] <= '0;
        out_payload_q[pi] <= '0;
        port_cmd_valid[pi] <= 1'b0;
        port_cmd_op[pi] <= MP_CMD_NONE;
        port_cmd_rank[pi] <= '0;
        port_cmd_packet_id[pi] <= '0;
        port_cmd_sram_slot[pi] <= '0;
        port_cmd_batch_id[pi] <= '0;
        port_cmd_batch_offset[pi] <= '0;
      end
      for (pi = 0; pi < SRAM_CELLS; pi = pi + 1) begin
        sram_valid[pi] <= 1'b0;
        sram_free_list[pi] <= pi[SRAM_SLOT_W-1:0];
      end
      sram_free_rd_q <= '0;
      sram_free_wr_q <= '0;
      sram_free_count_q <= SRAM_CELLS_U16;
      for (bi = 0; bi < BATCH_SLOTS; bi = bi + 1) begin
        batch_free_list[bi] <= bi[BATCH_ID_W-1:0];
        batch_valid_count[bi] <= 16'd0;
        batch_fill_count[bi] <= '0;
        for (oi = 0; oi < BATCH_SIZE; oi = oi + 1) begin
          batch_entry_valid[bi][oi] <= 1'b0;
        end
      end
      batch_free_rd_q <= '0;
      batch_free_wr_q <= '0;
      batch_free_count_q <= BATCH_SLOTS_U16;
      open_batch_valid_q <= 1'b0;
      open_batch_id_q <= '0;
      replace_port_q <= '0;
      replace_rank_q <= '0;
      replace_seq_q <= '0;
      replace_payload_q <= '0;
      replace_slot_q <= '0;
      swapin_batch_q <= '0;
      swapin_offset_q <= '0;
      stat_generated <= 32'd0;
      stat_dequeued <= 32'd0;
      stat_sram_admit <= 32'd0;
      stat_hbm_admit <= 32'd0;
      stat_swap_out <= 32'd0;
      stat_swap_in <= 32'd0;
      stat_direct_hbm_dequeue <= 32'd0;
      stat_drop <= 32'd0;
      action_q <= ACT_NONE;
      action_port_q <= '0;
      action_choose_replace_q <= 1'b0;
      action_choose_hbm_q <= 1'b0;
      action_rank_q <= '0;
      action_seq_q <= '0;
      action_payload_q <= '0;
      action_batch_q <= '0;
      global_sram_q <= 16'd0;
      global_hbm_q <= 16'd0;
      record_valid_q <= 1'b0;
      record_port_q <= '0;
      record_first_rank_q <= '1;
      record_second_rank_q <= '1;
      record_batch_q <= '0;
      swapout_valid_q <= 1'b0;
      swapout_port_q <= '0;
      deq_rr_q <= '0;
      deq_op_port_q <= '0;
      deq_op_use_hbm_q <= 1'b0;
      deq_op_rank_q <= '0;
      deq_op_sram_slot_q <= '0;
      deq_op_batch_q <= '0;
      deq_op_offset_q <= '0;
      select_idx_q <= '0;
    end else begin
      for (pi = 0; pi < PORTS; pi = pi + 1) begin
        if (port_cmd_valid[pi] && port_cmd_ready[pi]) begin
          port_cmd_valid[pi] <= 1'b0;
          port_cmd_op[pi] <= MP_CMD_NONE;
          port_cmd_rank[pi] <= '0;
          port_cmd_packet_id[pi] <= '0;
          port_cmd_sram_slot[pi] <= '0;
          port_cmd_batch_id[pi] <= '0;
          port_cmd_batch_offset[pi] <= '0;
        end
        if (m_pkt_valid[pi] && m_pkt_ready[pi]) begin
          m_pkt_valid[pi] <= 1'b0;
        end
      end

      unique case (state_q)
        ST_SELECT: begin
          if (all_ports_ready_c) begin
            global_sram_q <= 16'd0;
            global_hbm_q <= 16'd0;
            record_valid_q <= 1'b0;
            record_port_q <= '0;
            record_first_rank_q <= '1;
            record_second_rank_q <= '1;
            record_batch_q <= '0;
            swapout_valid_q <= 1'b0;
            swapout_port_q <= '0;
            select_idx_q <= '0;
            state_q <= ST_SELECT_SCAN;
          end
        end

        ST_SELECT_SCAN: begin
          select_port_v = select_idx_q[PORT_W-1:0];
          global_sram_q <= global_sram_q + sram_count_q[select_port_v];
          global_hbm_q <= global_hbm_q + hbm_count_q[select_port_v];

          if ((hbm_count_q[select_port_v] != 16'd0) && hbm_min_valid[select_port_v]) begin
            if (!record_valid_q ||
                (sram_count_q[select_port_v] < record_first_rank_q) ||
                ((sram_count_q[select_port_v] == record_first_rank_q) &&
                 (hbm_min_rank[select_port_v] < record_second_rank_q))) begin
              record_valid_q <= 1'b1;
              record_port_q <= select_port_v;
              record_first_rank_q <= sram_count_q[select_port_v];
              record_second_rank_q <= hbm_min_rank[select_port_v];
              record_batch_q <= hbm_min_batch_id[select_port_v];
            end
          end

          if ((sram_count_q[select_port_v] != 16'd0) && sram_max_valid[select_port_v]) begin
            if (!swapout_valid_q ||
                (sram_count_q[select_port_v] > sram_count_q[swapout_port_q]) ||
                ((sram_count_q[select_port_v] == sram_count_q[swapout_port_q]) &&
                 (sram_max_rank[select_port_v] > sram_max_rank[swapout_port_q]))) begin
              swapout_valid_q <= 1'b1;
              swapout_port_q <= select_port_v;
            end
          end

          if (select_idx_q == (PORTS - 1)) begin
            state_q <= ST_IDLE;
          end else begin
            select_idx_q <= select_idx_q + 1'b1;
          end
        end

        ST_IDLE: begin
          if (deq_grant_valid_c) begin
            port_v = deq_grant_port_c;
            if (deq_grant_use_hbm_c) begin
              deq_op_rank_q <= hbm_min_rank[port_v];
              deq_op_sram_slot_q <= '0;
              deq_op_batch_q <= hbm_min_batch_id[port_v];
              deq_op_offset_q <= hbm_min_batch_offset[port_v];
            end else begin
              deq_op_rank_q <= sram_min_rank[port_v];
              deq_op_sram_slot_q <= sram_min_slot[port_v];
              deq_op_batch_q <= '0;
              deq_op_offset_q <= '0;
            end
            deq_op_port_q <= port_v;
            deq_op_use_hbm_q <= deq_grant_use_hbm_c;
            deq_rr_q <= (port_v == LAST_PORT) ? '0 : (port_v + 1'b1);
            action_q <= ACT_NONE;
            state_q <= ST_DEQ_EXEC;
          end else if (water_swapout_pending_q) begin
            action_q <= ACT_SWAP_OUT;
            action_port_q <= swapout_port_q;
            state_q <= ST_EXEC;
          end else if (water_swapin_pending_q) begin
            action_q <= ACT_START_SWAP_IN;
            action_port_q <= record_port_q;
            action_batch_q <= record_batch_q;
            state_q <= ST_EXEC;
          end else if (enable && s_pkt_valid && s_pkt_ready) begin
            port_v = s_pkt_port;
            choose_replace_v = 1'b0;
            choose_hbm_v = 1'b0;

            if (ingress_better_record_q && (sram_free_count_q != 16'd0)) begin
              choose_hbm_v = 1'b0;
            end else if (sram_max_valid[port_v] &&
                         (s_pkt_rank < sram_max_rank[port_v]) &&
                         batch_append_ready_c) begin
              choose_replace_v = 1'b1;
            end else if (batch_append_ready_c) begin
              choose_hbm_v = 1'b1;
            end else if (sram_free_count_q != 16'd0) begin
              choose_hbm_v = 1'b0;
            end else begin
              choose_hbm_v = 1'b1;
            end

            action_q <= ACT_INGRESS;
            action_port_q <= port_v;
            action_choose_replace_q <= choose_replace_v;
            action_choose_hbm_q <= choose_hbm_v;
            action_rank_q <= s_pkt_rank;
            action_seq_q <= s_pkt_seq;
            action_payload_q <= s_pkt_payload;
            state_q <= ST_EXEC;
          end else begin
            state_q <= ST_SELECT;
          end
        end

        ST_DEQ_EXEC: begin
          port_v = deq_op_port_q;
          m_pkt_valid[port_v] <= 1'b1;
          out_rank_q[port_v] <= deq_op_rank_q;
          port_cmd_valid[port_v] <= 1'b1;

          if (deq_op_use_hbm_q) begin
            out_seq_q[port_v] <= batch_seq[deq_op_batch_q][deq_op_offset_q];
            out_payload_q[port_v] <= batch_payload[deq_op_batch_q][deq_op_offset_q];
            port_cmd_op[port_v] <= MP_CMD_REMOVE_HBM_MIN;
            invalidate_batch_cell(deq_op_batch_q, deq_op_offset_q);
            total_count_q[port_v] <= total_count_q[port_v] - 16'd1;
            hbm_count_q[port_v] <= hbm_count_q[port_v] - 16'd1;
            stat_dequeued <= stat_dequeued + 32'd1;
            stat_direct_hbm_dequeue <= stat_direct_hbm_dequeue + 32'd1;
          end else begin
            out_seq_q[port_v] <= sram_seq[deq_op_sram_slot_q];
            out_payload_q[port_v] <= sram_payload[deq_op_sram_slot_q];
            port_cmd_op[port_v] <= MP_CMD_REMOVE_SRAM_MIN;
            free_sram_slot(deq_op_sram_slot_q);
            total_count_q[port_v] <= total_count_q[port_v] - 16'd1;
            sram_count_q[port_v] <= sram_count_q[port_v] - 16'd1;
            stat_dequeued <= stat_dequeued + 32'd1;
          end

          action_q <= ACT_NONE;
          state_q <= ST_SELECT;
        end

        ST_EXEC: begin
          unique case (action_q)
            ACT_SWAP_OUT: begin
              port_v = action_port_q;
              append_hbm_cell(port_v, sram_max_rank[port_v], sram_seq[sram_max_slot[port_v]],
                              sram_payload[sram_max_slot[port_v]],
                              append_batch_v, append_offset_v, append_ok_v);
              if (append_ok_v) begin
                port_cmd_valid[port_v] <= 1'b1;
                port_cmd_op[port_v] <= MP_CMD_MOVE_SRAM_MAX_HBM;
                port_cmd_batch_id[port_v] <= append_batch_v;
                port_cmd_batch_offset[port_v] <= append_offset_v;
                free_sram_slot(sram_max_slot[port_v]);
                sram_count_q[port_v] <= sram_count_q[port_v] - 16'd1;
                hbm_count_q[port_v] <= hbm_count_q[port_v] + 16'd1;
                stat_swap_out <= stat_swap_out + 32'd1;
              end
              action_q <= ACT_NONE;
              state_q <= ST_SELECT;
            end

            ACT_START_SWAP_IN: begin
              swapin_batch_q <= action_batch_q;
              swapin_offset_q <= '0;
              action_q <= ACT_NONE;
              state_q <= ST_SWAPIN_WAIT;
            end

            ACT_INGRESS: begin
              port_v = action_port_q;
              stat_generated <= stat_generated + 32'd1;
              if (action_choose_replace_q) begin
                append_hbm_cell(port_v, sram_max_rank[port_v], sram_seq[sram_max_slot[port_v]],
                                sram_payload[sram_max_slot[port_v]],
                                append_batch_v, append_offset_v, append_ok_v);
                if (append_ok_v) begin
                  port_cmd_valid[port_v] <= 1'b1;
                  port_cmd_op[port_v] <= MP_CMD_MOVE_SRAM_MAX_HBM;
                  port_cmd_batch_id[port_v] <= append_batch_v;
                  port_cmd_batch_offset[port_v] <= append_offset_v;
                  replace_port_q <= port_v;
                  replace_rank_q <= action_rank_q;
                  replace_seq_q <= action_seq_q;
                  replace_payload_q <= action_payload_q;
                  replace_slot_q <= sram_max_slot[port_v];
                  write_sram_cell(sram_max_slot[port_v], port_v, action_rank_q, action_seq_q, action_payload_q);
                  total_count_q[port_v] <= total_count_q[port_v] + 16'd1;
                  hbm_count_q[port_v] <= hbm_count_q[port_v] + 16'd1;
                  stat_sram_admit <= stat_sram_admit + 32'd1;
                  stat_hbm_admit <= stat_hbm_admit + 32'd1;
                  state_q <= ST_REPLACE_ADD_SRAM;
                end else begin
                  stat_drop <= stat_drop + 32'd1;
                  state_q <= ST_SELECT;
                end
              end else if (action_choose_hbm_q) begin
                append_hbm_cell(port_v, action_rank_q, action_seq_q, action_payload_q,
                                append_batch_v, append_offset_v, append_ok_v);
                if (append_ok_v) begin
                  port_cmd_valid[port_v] <= 1'b1;
                  port_cmd_op[port_v] <= MP_CMD_ADD_HBM;
                  port_cmd_rank[port_v] <= action_rank_q;
                  port_cmd_packet_id[port_v] <= action_seq_q;
                  port_cmd_batch_id[port_v] <= append_batch_v;
                  port_cmd_batch_offset[port_v] <= append_offset_v;
                  total_count_q[port_v] <= total_count_q[port_v] + 16'd1;
                  hbm_count_q[port_v] <= hbm_count_q[port_v] + 16'd1;
                  stat_hbm_admit <= stat_hbm_admit + 32'd1;
                end else begin
                  stat_drop <= stat_drop + 32'd1;
                end
                state_q <= ST_SELECT;
              end else begin
                alloc_sram_slot(alloc_slot_v);
                write_sram_cell(alloc_slot_v, port_v, action_rank_q, action_seq_q, action_payload_q);
                port_cmd_valid[port_v] <= 1'b1;
                port_cmd_op[port_v] <= MP_CMD_ADD_SRAM;
                port_cmd_rank[port_v] <= action_rank_q;
                port_cmd_packet_id[port_v] <= action_seq_q;
                port_cmd_sram_slot[port_v] <= alloc_slot_v;
                total_count_q[port_v] <= total_count_q[port_v] + 16'd1;
                sram_count_q[port_v] <= sram_count_q[port_v] + 16'd1;
                stat_sram_admit <= stat_sram_admit + 32'd1;
                state_q <= ST_SELECT;
              end
              action_q <= ACT_NONE;
            end

            default: begin
              action_q <= ACT_NONE;
              state_q <= ST_SELECT;
            end
          endcase
        end

        ST_REPLACE_ADD_SRAM: begin
          if (!port_cmd_valid[replace_port_q] && port_cmd_ready[replace_port_q]) begin
            port_cmd_valid[replace_port_q] <= 1'b1;
            port_cmd_op[replace_port_q] <= MP_CMD_ADD_SRAM;
            port_cmd_rank[replace_port_q] <= replace_rank_q;
            port_cmd_packet_id[replace_port_q] <= replace_seq_q;
            port_cmd_sram_slot[replace_port_q] <= replace_slot_q;
            state_q <= ST_SELECT;
          end
        end

        ST_SWAPIN_WAIT: begin
          if (all_ports_ready_c) begin
            state_q <= ST_SWAPIN_SCAN;
          end
        end

        ST_SWAPIN_SCAN: begin
          if (swapin_offset_q == BATCH_SIZE) begin
            free_batch_slot(swapin_batch_q);
            state_q <= ST_SELECT;
          end else begin
            if (batch_entry_valid[swapin_batch_q][swapin_offset_q[BATCH_OFF_W-1:0]]) begin
              port_v = batch_port[swapin_batch_q][swapin_offset_q[BATCH_OFF_W-1:0]];
              if (sram_free_count_q != 16'd0) begin
                alloc_sram_slot(alloc_slot_v);
                write_sram_cell(alloc_slot_v, port_v,
                                batch_rank[swapin_batch_q][swapin_offset_q[BATCH_OFF_W-1:0]],
                                batch_seq[swapin_batch_q][swapin_offset_q[BATCH_OFF_W-1:0]],
                                batch_payload[swapin_batch_q][swapin_offset_q[BATCH_OFF_W-1:0]]);
                port_cmd_valid[port_v] <= 1'b1;
                port_cmd_op[port_v] <= MP_CMD_MOVE_HBM_SRAM;
                port_cmd_sram_slot[port_v] <= alloc_slot_v;
                port_cmd_batch_id[port_v] <= swapin_batch_q;
                port_cmd_batch_offset[port_v] <= swapin_offset_q[BATCH_OFF_W-1:0];
                batch_entry_valid[swapin_batch_q][swapin_offset_q[BATCH_OFF_W-1:0]] <= 1'b0;
                batch_valid_count[swapin_batch_q] <= batch_valid_count[swapin_batch_q] - 16'd1;
                sram_count_q[port_v] <= sram_count_q[port_v] + 16'd1;
                hbm_count_q[port_v] <= hbm_count_q[port_v] - 16'd1;
                stat_swap_in <= stat_swap_in + 32'd1;
                swapin_offset_q <= swapin_offset_q + 1'b1;
                state_q <= ST_SWAPIN_WAIT;
              end
            end else begin
              swapin_offset_q <= swapin_offset_q + 1'b1;
            end
          end
        end

        default: begin
          state_q <= ST_SELECT;
        end
      endcase
    end
  end
endmodule
