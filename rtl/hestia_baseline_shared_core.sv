`timescale 1ns/1ps

import hestia_pkg::*;

module hestia_baseline_shared_core #(
  parameter int POLICY_MODE = 0,
  parameter int PORTS = 4,
  parameter int RANK_WIDTH = 8,
  parameter int SEQ_WIDTH = 16,
  parameter int PAYLOAD_WIDTH = 32,
  parameter int CELL_COUNT_WIDTH = 4,
  parameter int SRAM_CELLS = 32,
  parameter int PACKET_SLOTS = 64,
  parameter int BBQ_BITMAP_WIDTH = 8,
  parameter int ALPHA_SHIFT_WIDTH = 4,
  localparam int PORT_W = (PORTS <= 2) ? 1 : $clog2(PORTS),
  localparam int DESC_W = (PACKET_SLOTS <= 2) ? 1 : $clog2(PACKET_SLOTS)
) (
  input  logic                              clk,
  input  logic                              resetn,
  input  logic                              enable,
  input  logic [ALPHA_SHIFT_WIDTH-1:0]      cfg_alpha_shift,
  input  logic                              cfg_reclaim_enable,

  input  logic                              s_pkt_valid,
  output logic                              s_pkt_ready,
  input  logic [PORT_W-1:0]                 s_pkt_port,
  input  logic [RANK_WIDTH-1:0]             s_pkt_rank,
  input  logic [SEQ_WIDTH-1:0]              s_pkt_seq,
  input  logic [CELL_COUNT_WIDTH-1:0]       s_pkt_cell_count,
  input  logic [PAYLOAD_WIDTH-1:0]          s_pkt_payload,

  input  logic [PORTS-1:0]                  dequeue_enable,
  output logic [PORTS-1:0]                  m_pkt_valid,
  input  logic [PORTS-1:0]                  m_pkt_ready,
  output logic [PORTS*RANK_WIDTH-1:0]       m_pkt_rank,
  output logic [PORTS*SEQ_WIDTH-1:0]        m_pkt_seq,
  output logic [PORTS*CELL_COUNT_WIDTH-1:0] m_pkt_cell_count,
  output logic [PORTS*PAYLOAD_WIDTH-1:0]    m_pkt_payload,

  output logic [31:0]                       stat_generated,
  output logic [31:0]                       stat_admitted,
  output logic [31:0]                       stat_dequeued,
  output logic [31:0]                       stat_drop,
  output logic [31:0]                       stat_evicted,
  output logic [31:0]                       stat_reclaim,
  output logic [31:0]                       stat_obm_pushout,
  output logic [31:0]                       stat_dt_drop,
  output logic [15:0]                       dbg_global_occupancy,
  output logic [15:0]                       dbg_free_cells,
  output logic [PORTS*16-1:0]               dbg_port_occupancy_flat
);
  localparam int POLICY_DT = 0;
  localparam int POLICY_OCCAMY_HEAD = 1;
  localparam int POLICY_OCCAMY_MAX = 2;
  localparam int POLICY_OBM = 3;
  localparam int DUMMY_BATCH_SIZE = 2;
  localparam int DUMMY_BATCH_SLOTS = 2;
  localparam int DUMMY_BATCH_ID_W = 1;
  localparam int DUMMY_BATCH_OFF_W = 1;
  localparam logic [15:0] SRAM_CELLS_U16 = 16'(SRAM_CELLS);

  typedef enum logic [1:0] {
    ST_IDLE,
    ST_WAIT_BBQ
  } state_t;

  state_t state_q;
  logic [PORT_W-1:0] deq_rr_q;

  (* ram_style = "distributed" *) logic desc_valid [0:PACKET_SLOTS-1];
  (* ram_style = "distributed" *) logic [PORT_W-1:0] desc_port [0:PACKET_SLOTS-1];
  (* ram_style = "distributed" *) logic [RANK_WIDTH-1:0] desc_rank [0:PACKET_SLOTS-1];
  (* ram_style = "distributed" *) logic [SEQ_WIDTH-1:0] desc_seq [0:PACKET_SLOTS-1];
  (* ram_style = "distributed" *) logic [CELL_COUNT_WIDTH-1:0] desc_cell_count [0:PACKET_SLOTS-1];
  (* ram_style = "distributed" *) logic [PAYLOAD_WIDTH-1:0] desc_payload [0:PACKET_SLOTS-1];

  logic [15:0] global_occupancy_q;
  logic [15:0] port_occupancy_q [0:PORTS-1];

  logic out_valid_q [0:PORTS-1];
  logic [RANK_WIDTH-1:0] out_rank_q [0:PORTS-1];
  logic [SEQ_WIDTH-1:0] out_seq_q [0:PORTS-1];
  logic [CELL_COUNT_WIDTH-1:0] out_cell_count_q [0:PORTS-1];
  logic [PAYLOAD_WIDTH-1:0] out_payload_q [0:PORTS-1];

  logic pending_valid_q;
  logic [PORT_W-1:0] pending_port_q;
  logic [RANK_WIDTH-1:0] pending_rank_q;
  logic [SEQ_WIDTH-1:0] pending_seq_q;
  logic [CELL_COUNT_WIDTH-1:0] pending_cell_count_q;
  logic [PAYLOAD_WIDTH-1:0] pending_payload_q;

  logic bbq_cmd_valid [0:PORTS-1];
  mp_bbq_cmd_t bbq_cmd_op [0:PORTS-1];
  logic [DESC_W-1:0] bbq_cmd_desc [0:PORTS-1];
  logic [RANK_WIDTH-1:0] bbq_cmd_rank [0:PORTS-1];
  logic [SEQ_WIDTH-1:0] bbq_cmd_seq [0:PORTS-1];
  logic [CELL_COUNT_WIDTH-1:0] bbq_cmd_cell_count [0:PORTS-1];
  logic [DUMMY_BATCH_ID_W-1:0] bbq_cmd_batch_id [0:PORTS-1];
  logic [DUMMY_BATCH_OFF_W-1:0] bbq_cmd_batch_offset [0:PORTS-1];
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
  logic [DUMMY_BATCH_ID_W-1:0] bbq_hbm_min_batch_id [0:PORTS-1];
  logic [DUMMY_BATCH_OFF_W-1:0] bbq_hbm_min_batch_offset [0:PORTS-1];
  logic [15:0] bbq_sram_occupancy [0:PORTS-1];
  logic [15:0] bbq_hbm_occupancy [0:PORTS-1];

  logic [PORTS*16-1:0] port_occ_flat_c;
  logic [15:0] free_cells_c;
  logic all_bbq_ready_c;
  logic free_desc_valid_c;
  logic [DESC_W-1:0] free_desc_c;
  logic deq_req_valid_c;
  logic [PORT_W-1:0] deq_req_port_c;
  logic [DESC_W-1:0] deq_req_desc_c;

  logic policy_admit_c;
  logic [15:0] policy_threshold_c;
  logic [PORTS-1:0] occamy_over_bitmap_c;
  logic occamy_reclaim_valid_c;
  logic [PORT_W-1:0] occamy_reclaim_port_c;
  logic occamy_reclaim_fire_q;
  logic obm_longest_valid_c;
  logic [PORT_W-1:0] obm_longest_port_c;
  logic [15:0] obm_longest_occupancy_c;
  logic obm_pkt_targets_longest_c;

  genvar gp;
  generate
    for (gp = 0; gp < PORTS; gp = gp + 1) begin : gen_ports
      assign m_pkt_valid[gp] = out_valid_q[gp];
      assign m_pkt_rank[gp*RANK_WIDTH +: RANK_WIDTH] = out_rank_q[gp];
      assign m_pkt_seq[gp*SEQ_WIDTH +: SEQ_WIDTH] = out_seq_q[gp];
      assign m_pkt_cell_count[gp*CELL_COUNT_WIDTH +: CELL_COUNT_WIDTH] = out_cell_count_q[gp];
      assign m_pkt_payload[gp*PAYLOAD_WIDTH +: PAYLOAD_WIDTH] = out_payload_q[gp];
      assign port_occ_flat_c[gp*16 +: 16] = port_occupancy_q[gp];
      assign dbg_port_occupancy_flat[gp*16 +: 16] = port_occupancy_q[gp];

      hestia_port_bbq #(
        .RANK_WIDTH(RANK_WIDTH),
        .SEQ_WIDTH(SEQ_WIDTH),
        .CELL_COUNT_WIDTH(CELL_COUNT_WIDTH),
        .BATCH_SIZE(DUMMY_BATCH_SIZE),
        .BATCH_SLOTS(DUMMY_BATCH_SLOTS),
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

    if (POLICY_MODE == POLICY_DT) begin : gen_dt_policy
      hestia_policy_dt #(
        .PORTS(PORTS),
        .CELL_COUNT_WIDTH(CELL_COUNT_WIDTH),
        .OCC_WIDTH(16),
        .ALPHA_SHIFT_WIDTH(ALPHA_SHIFT_WIDTH)
      ) policy_dt (
        .cfg_alpha_shift(cfg_alpha_shift),
        .pkt_valid(s_pkt_valid),
        .pkt_port(s_pkt_port),
        .pkt_cell_count(s_pkt_cell_count),
        .free_cells(free_cells_c),
        .port_occ_flat(port_occ_flat_c),
        .pkt_admit(policy_admit_c),
        .threshold(policy_threshold_c)
      );
      assign occamy_over_bitmap_c = '0;
      assign occamy_reclaim_valid_c = 1'b0;
      assign occamy_reclaim_port_c = '0;
      assign obm_longest_valid_c = 1'b0;
      assign obm_longest_port_c = '0;
      assign obm_longest_occupancy_c = '0;
      assign obm_pkt_targets_longest_c = 1'b0;
    end else if ((POLICY_MODE == POLICY_OCCAMY_HEAD) ||
                 (POLICY_MODE == POLICY_OCCAMY_MAX)) begin : gen_occamy_policy
      hestia_policy_occamy #(
        .PORTS(PORTS),
        .CELL_COUNT_WIDTH(CELL_COUNT_WIDTH),
        .OCC_WIDTH(16),
        .ALPHA_SHIFT_WIDTH(ALPHA_SHIFT_WIDTH)
      ) policy_occamy (
        .clk(clk),
        .resetn(resetn),
        .cfg_alpha_shift(cfg_alpha_shift),
        .reclaim_enable(cfg_reclaim_enable),
        .reclaim_fire(occamy_reclaim_fire_q),
        .pkt_valid(s_pkt_valid),
        .pkt_port(s_pkt_port),
        .pkt_cell_count(s_pkt_cell_count),
        .free_cells(free_cells_c),
        .port_occ_flat(port_occ_flat_c),
        .pkt_admit(policy_admit_c),
        .threshold(policy_threshold_c),
        .over_threshold_bitmap(occamy_over_bitmap_c),
        .reclaim_valid(occamy_reclaim_valid_c),
        .reclaim_port(occamy_reclaim_port_c)
      );
      assign obm_longest_valid_c = 1'b0;
      assign obm_longest_port_c = '0;
      assign obm_longest_occupancy_c = '0;
      assign obm_pkt_targets_longest_c = 1'b0;
    end else begin : gen_obm_policy
      hestia_policy_obm #(
        .PORTS(PORTS),
        .OCC_WIDTH(16)
      ) policy_obm (
        .port_occ_flat(port_occ_flat_c),
        .pkt_port(pending_valid_q ? pending_port_q : s_pkt_port),
        .pkt_valid(pending_valid_q ? pending_valid_q : s_pkt_valid),
        .longest_valid(obm_longest_valid_c),
        .longest_port(obm_longest_port_c),
        .longest_occupancy(obm_longest_occupancy_c),
        .pkt_targets_longest(obm_pkt_targets_longest_c)
      );
      assign policy_admit_c = (pending_valid_q ? pending_cell_count_q : s_pkt_cell_count) != '0;
      assign policy_threshold_c = '0;
      assign occamy_over_bitmap_c = '0;
      assign occamy_reclaim_valid_c = 1'b0;
      assign occamy_reclaim_port_c = '0;
    end
  endgenerate

  assign dbg_global_occupancy = global_occupancy_q;
  assign dbg_free_cells = free_cells_c;

  function automatic logic [15:0] cell_count16(input logic [CELL_COUNT_WIDTH-1:0] cells_i);
    begin
      cell_count16 = {{(16-CELL_COUNT_WIDTH){1'b0}}, cells_i};
    end
  endfunction

  function automatic logic port_has_valid_min(input int port_i);
    begin
      port_has_valid_min = bbq_sram_min_valid[port_i];
    end
  endfunction

  function automatic logic port_has_valid_max(input int port_i);
    begin
      port_has_valid_max = bbq_sram_max_valid[port_i];
    end
  endfunction

  task automatic issue_bbq_cmd(
    input int port_i,
    input mp_bbq_cmd_t op_i,
    input logic [DESC_W-1:0] desc_i,
    input logic [RANK_WIDTH-1:0] rank_i,
    input logic [SEQ_WIDTH-1:0] seq_i,
    input logic [CELL_COUNT_WIDTH-1:0] cells_i
  );
    begin
      bbq_cmd_valid[port_i] <= 1'b1;
      bbq_cmd_op[port_i] <= op_i;
      bbq_cmd_desc[port_i] <= desc_i;
      bbq_cmd_rank[port_i] <= rank_i;
      bbq_cmd_seq[port_i] <= seq_i;
      bbq_cmd_cell_count[port_i] <= cells_i;
      bbq_cmd_batch_id[port_i] <= '0;
      bbq_cmd_batch_offset[port_i] <= '0;
    end
  endtask

  task automatic drop_packet(input logic count_dt_drop_i);
    begin
      stat_drop <= stat_drop + 32'd1;
      if (count_dt_drop_i) begin
        stat_dt_drop <= stat_dt_drop + 32'd1;
      end
    end
  endtask

  task automatic admit_packet(
    input logic [PORT_W-1:0] port_i,
    input logic [RANK_WIDTH-1:0] rank_i,
    input logic [SEQ_WIDTH-1:0] seq_i,
    input logic [CELL_COUNT_WIDTH-1:0] cells_i,
    input logic [PAYLOAD_WIDTH-1:0] payload_i,
    input logic [DESC_W-1:0] desc_i
  );
    logic [15:0] cells_v;
    begin
      cells_v = cell_count16(cells_i);
      desc_valid[desc_i] <= 1'b1;
      desc_port[desc_i] <= port_i;
      desc_rank[desc_i] <= rank_i;
      desc_seq[desc_i] <= seq_i;
      desc_cell_count[desc_i] <= cells_i;
      desc_payload[desc_i] <= payload_i;
      global_occupancy_q <= global_occupancy_q + cells_v;
      port_occupancy_q[port_i] <= port_occupancy_q[port_i] + cells_v;
      issue_bbq_cmd(int'(port_i), MP_BBQ_CMD_ADD_SRAM, desc_i, rank_i, seq_i, cells_i);
      stat_admitted <= stat_admitted + 32'd1;
      state_q <= ST_WAIT_BBQ;
    end
  endtask

  task automatic remove_desc(
    input logic [DESC_W-1:0] desc_i,
    input logic emit_packet_i,
    input logic count_reclaim_i,
    input logic count_obm_i
  );
    logic [PORT_W-1:0] port_v;
    logic [15:0] cells_v;
    begin
      port_v = desc_port[desc_i];
      cells_v = cell_count16(desc_cell_count[desc_i]);

      if (emit_packet_i) begin
        out_valid_q[port_v] <= 1'b1;
        out_rank_q[port_v] <= desc_rank[desc_i];
        out_seq_q[port_v] <= desc_seq[desc_i];
        out_cell_count_q[port_v] <= desc_cell_count[desc_i];
        out_payload_q[port_v] <= desc_payload[desc_i];
        stat_dequeued <= stat_dequeued + 32'd1;
      end else begin
        stat_evicted <= stat_evicted + 32'd1;
        if (count_reclaim_i) begin
          stat_reclaim <= stat_reclaim + 32'd1;
        end
        if (count_obm_i) begin
          stat_obm_pushout <= stat_obm_pushout + 32'd1;
        end
      end

      if (global_occupancy_q >= cells_v) begin
        global_occupancy_q <= global_occupancy_q - cells_v;
      end else begin
        global_occupancy_q <= 16'd0;
      end
      if (port_occupancy_q[port_v] >= cells_v) begin
        port_occupancy_q[port_v] <= port_occupancy_q[port_v] - cells_v;
      end else begin
        port_occupancy_q[port_v] <= 16'd0;
      end

      issue_bbq_cmd(int'(port_v), MP_BBQ_CMD_REMOVE_SRAM, desc_i,
                    desc_rank[desc_i], desc_seq[desc_i], desc_cell_count[desc_i]);
      desc_valid[desc_i] <= 1'b0;
      state_q <= ST_WAIT_BBQ;
    end
  endtask

  integer pi;
  integer di;
  integer si;
  integer idx;
  always_comb begin
    if (global_occupancy_q >= SRAM_CELLS_U16) begin
      free_cells_c = 16'd0;
    end else begin
      free_cells_c = SRAM_CELLS_U16 - global_occupancy_q;
    end

    all_bbq_ready_c = 1'b1;
    for (pi = 0; pi < PORTS; pi = pi + 1) begin
      all_bbq_ready_c = all_bbq_ready_c && bbq_cmd_ready[pi];
    end

    free_desc_valid_c = 1'b0;
    free_desc_c = '0;
    for (di = 0; di < PACKET_SLOTS; di = di + 1) begin
      if (!free_desc_valid_c && !desc_valid[di]) begin
        free_desc_valid_c = 1'b1;
        free_desc_c = DESC_W'(di);
      end
    end

    deq_req_valid_c = 1'b0;
    deq_req_port_c = deq_rr_q;
    deq_req_desc_c = '0;
    for (si = 0; si < PORTS; si = si + 1) begin
      idx = int'(deq_rr_q) + si;
      if (idx >= PORTS) begin
        idx = idx - PORTS;
      end
      if (!deq_req_valid_c &&
          dequeue_enable[idx] &&
          !out_valid_q[idx] &&
          port_has_valid_min(idx)) begin
        deq_req_valid_c = 1'b1;
        deq_req_port_c = PORT_W'(idx);
        deq_req_desc_c = bbq_sram_min_desc[idx];
      end
    end

    s_pkt_ready = enable &&
                  (state_q == ST_IDLE) &&
                  all_bbq_ready_c &&
                  !pending_valid_q &&
                  !deq_req_valid_c;
  end

  integer ri;
  integer evict_port_v;
  logic [DESC_W-1:0] victim_desc_v;
  logic [15:0] action_cells_v;
  always_ff @(posedge clk) begin
    if (!resetn) begin
      state_q <= ST_IDLE;
      deq_rr_q <= '0;
      global_occupancy_q <= 16'd0;
      pending_valid_q <= 1'b0;
      pending_port_q <= '0;
      pending_rank_q <= '0;
      pending_seq_q <= '0;
      pending_cell_count_q <= '0;
      pending_payload_q <= '0;
      stat_generated <= 32'd0;
      stat_admitted <= 32'd0;
      stat_dequeued <= 32'd0;
      stat_drop <= 32'd0;
      stat_evicted <= 32'd0;
      stat_reclaim <= 32'd0;
      stat_obm_pushout <= 32'd0;
      stat_dt_drop <= 32'd0;
      occamy_reclaim_fire_q <= 1'b0;
      for (ri = 0; ri < PORTS; ri = ri + 1) begin
        port_occupancy_q[ri] <= 16'd0;
        out_valid_q[ri] <= 1'b0;
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
      end
      for (ri = 0; ri < PACKET_SLOTS; ri = ri + 1) begin
        desc_valid[ri] <= 1'b0;
        desc_port[ri] <= '0;
        desc_rank[ri] <= '0;
        desc_seq[ri] <= '0;
        desc_cell_count[ri] <= '0;
        desc_payload[ri] <= '0;
      end
    end else begin
      occamy_reclaim_fire_q <= 1'b0;
      for (ri = 0; ri < PORTS; ri = ri + 1) begin
        bbq_cmd_valid[ri] <= 1'b0;
        bbq_cmd_op[ri] <= MP_BBQ_CMD_NONE;
        if (out_valid_q[ri] && m_pkt_ready[ri]) begin
          out_valid_q[ri] <= 1'b0;
        end
      end

      case (state_q)
        ST_IDLE: begin
          if (enable && all_bbq_ready_c) begin
            if (pending_valid_q) begin
              action_cells_v = cell_count16(pending_cell_count_q);
              if ((action_cells_v != 16'd0) &&
                  (free_cells_c >= action_cells_v) &&
                  free_desc_valid_c) begin
                admit_packet(pending_port_q, pending_rank_q, pending_seq_q,
                             pending_cell_count_q, pending_payload_q, free_desc_c);
                pending_valid_q <= 1'b0;
              end else if (obm_longest_valid_c &&
                           !obm_pkt_targets_longest_c &&
                           port_has_valid_max(int'(obm_longest_port_c))) begin
                victim_desc_v = bbq_sram_max_desc[int'(obm_longest_port_c)];
                remove_desc(victim_desc_v, 1'b0, 1'b0, 1'b1);
              end else begin
                drop_packet(1'b0);
                pending_valid_q <= 1'b0;
              end
            end else if (deq_req_valid_c) begin
              remove_desc(deq_req_desc_c, 1'b1, 1'b0, 1'b0);
              if (deq_req_port_c == PORT_W'(PORTS-1)) begin
                deq_rr_q <= '0;
              end else begin
                deq_rr_q <= deq_req_port_c + 1'b1;
              end
            end else if (s_pkt_valid) begin
              stat_generated <= stat_generated + 32'd1;
              action_cells_v = cell_count16(s_pkt_cell_count);
              if (POLICY_MODE == POLICY_OBM) begin
                if ((action_cells_v != 16'd0) &&
                    (free_cells_c >= action_cells_v) &&
                    free_desc_valid_c) begin
                  admit_packet(s_pkt_port, s_pkt_rank, s_pkt_seq,
                               s_pkt_cell_count, s_pkt_payload, free_desc_c);
                end else if (obm_longest_valid_c &&
                             !obm_pkt_targets_longest_c &&
                             port_has_valid_max(int'(obm_longest_port_c))) begin
                  pending_valid_q <= 1'b1;
                  pending_port_q <= s_pkt_port;
                  pending_rank_q <= s_pkt_rank;
                  pending_seq_q <= s_pkt_seq;
                  pending_cell_count_q <= s_pkt_cell_count;
                  pending_payload_q <= s_pkt_payload;
                  victim_desc_v = bbq_sram_max_desc[int'(obm_longest_port_c)];
                  remove_desc(victim_desc_v, 1'b0, 1'b0, 1'b1);
                end else begin
                  drop_packet(1'b0);
                end
              end else begin
                if (policy_admit_c && free_desc_valid_c) begin
                  admit_packet(s_pkt_port, s_pkt_rank, s_pkt_seq,
                               s_pkt_cell_count, s_pkt_payload, free_desc_c);
                end else begin
                  drop_packet(1'b1);
                end
              end
            end else if (((POLICY_MODE == POLICY_OCCAMY_HEAD) ||
                          (POLICY_MODE == POLICY_OCCAMY_MAX)) &&
                         occamy_reclaim_valid_c) begin
              evict_port_v = int'(occamy_reclaim_port_c);
              if ((POLICY_MODE == POLICY_OCCAMY_HEAD) &&
                  port_has_valid_min(evict_port_v)) begin
                victim_desc_v = bbq_sram_min_desc[evict_port_v];
                remove_desc(victim_desc_v, 1'b0, 1'b1, 1'b0);
                occamy_reclaim_fire_q <= 1'b1;
              end else if ((POLICY_MODE == POLICY_OCCAMY_MAX) &&
                           port_has_valid_max(evict_port_v)) begin
                victim_desc_v = bbq_sram_max_desc[evict_port_v];
                remove_desc(victim_desc_v, 1'b0, 1'b1, 1'b0);
                occamy_reclaim_fire_q <= 1'b1;
              end
            end
          end
        end

        ST_WAIT_BBQ: begin
          if (all_bbq_ready_c) begin
            state_q <= ST_IDLE;
          end
        end

        default: begin
          state_q <= ST_IDLE;
        end
      endcase
    end
  end
endmodule
