`timescale 1ns/1ps

import hestia_pkg::*;

module hestia_port_bbq #(
  parameter int RANK_WIDTH = 8,
  parameter int SEQ_WIDTH = 16,
  parameter int CELL_COUNT_WIDTH = 4,
  parameter int BATCH_SIZE = 4,
  parameter int BATCH_SLOTS = 8,
  parameter int PACKET_SLOTS = 32,
  parameter int BBQ_BITMAP_WIDTH = 16,
  localparam int LEVEL_W = (BBQ_BITMAP_WIDTH <= 2) ? 1 : $clog2(BBQ_BITMAP_WIDTH),
  localparam int PRIORITY_W = 2 * LEVEL_W,
  localparam int NUM_PRIORITIES = BBQ_BITMAP_WIDTH * BBQ_BITMAP_WIDTH,
  localparam int DESC_W = (PACKET_SLOTS <= 2) ? 1 : $clog2(PACKET_SLOTS),
  localparam int BATCH_ID_W = (BATCH_SLOTS <= 2) ? 1 : $clog2(BATCH_SLOTS),
  localparam int BATCH_OFF_W = (BATCH_SIZE <= 2) ? 1 : $clog2(BATCH_SIZE),
  localparam int INIT_COUNT = (BBQ_BITMAP_WIDTH > PACKET_SLOTS) ? BBQ_BITMAP_WIDTH : PACKET_SLOTS,
  localparam int INIT_W = (INIT_COUNT <= 1) ? 1 : $clog2(INIT_COUNT + 1)
) (
  input  logic                              clk,
  input  logic                              resetn,

  input  logic                              cmd_valid,
  output logic                              cmd_ready,
  input  mp_bbq_cmd_t                       cmd_op,
  input  logic [DESC_W-1:0]                 cmd_desc,
  input  logic [RANK_WIDTH-1:0]             cmd_rank,
  input  logic [SEQ_WIDTH-1:0]              cmd_seq,
  input  logic [CELL_COUNT_WIDTH-1:0]       cmd_cell_count,
  input  logic [BATCH_ID_W-1:0]             cmd_batch_id,
  input  logic [BATCH_OFF_W-1:0]            cmd_batch_offset,

  output logic                              sram_min_valid,
  output logic [DESC_W-1:0]                 sram_min_desc,
  output logic [RANK_WIDTH-1:0]             sram_min_rank,
  output logic [SEQ_WIDTH-1:0]              sram_min_seq,
  output logic [CELL_COUNT_WIDTH-1:0]       sram_min_cell_count,

  output logic                              sram_max_valid,
  output logic [DESC_W-1:0]                 sram_max_desc,
  output logic [RANK_WIDTH-1:0]             sram_max_rank,
  output logic [SEQ_WIDTH-1:0]              sram_max_seq,
  output logic [CELL_COUNT_WIDTH-1:0]       sram_max_cell_count,

  output logic                              hbm_min_valid,
  output logic [DESC_W-1:0]                 hbm_min_desc,
  output logic [RANK_WIDTH-1:0]             hbm_min_rank,
  output logic [SEQ_WIDTH-1:0]              hbm_min_seq,
  output logic [CELL_COUNT_WIDTH-1:0]       hbm_min_cell_count,
  output logic [BATCH_ID_W-1:0]             hbm_min_batch_id,
  output logic [BATCH_OFF_W-1:0]            hbm_min_batch_offset,

  output logic [15:0]                       sram_occupancy,
  output logic [15:0]                       hbm_occupancy
);
  typedef logic [PRIORITY_W-1:0] priority_t;
  typedef logic [BBQ_BITMAP_WIDTH-1:0] bitmap_t;

  typedef enum logic {
    TIER_SRAM,
    TIER_HBM
  } tier_t;

  typedef enum logic [3:0] {
    S_INIT,
    S_IDLE,
    S_REMOVE_READ,
    S_REMOVE_APPLY_PREV,
    S_REMOVE_APPLY_NEXT,
    S_REMOVE_CLEAR,
    S_ADD_READ,
    S_ADD_WRITE_NODE,
    S_ADD_LINK,
    S_REFRESH_CALC,
    S_REFRESH_BUCKET,
    S_REFRESH_NODE
  } state_t;

  bitmap_t sram_l1_bitmap_q;
  bitmap_t hbm_l1_bitmap_q;
  (* ram_style = "distributed" *) bitmap_t sram_l2_bitmap_q [0:BBQ_BITMAP_WIDTH-1];
  (* ram_style = "distributed" *) bitmap_t hbm_l2_bitmap_q [0:BBQ_BITMAP_WIDTH-1];

  (* ram_style = "distributed" *) logic [DESC_W-1:0] sram_bucket_head_q [0:NUM_PRIORITIES-1];
  (* ram_style = "distributed" *) logic [DESC_W-1:0] sram_bucket_tail_q [0:NUM_PRIORITIES-1];
  (* ram_style = "distributed" *) logic [DESC_W-1:0] hbm_bucket_head_q [0:NUM_PRIORITIES-1];
  (* ram_style = "distributed" *) logic [DESC_W-1:0] hbm_bucket_tail_q [0:NUM_PRIORITIES-1];

  (* ram_style = "distributed" *) logic node_valid_q [0:PACKET_SLOTS-1];
  (* ram_style = "distributed" *) logic node_in_hbm_q [0:PACKET_SLOTS-1];
  (* ram_style = "distributed" *) priority_t node_priority_q [0:PACKET_SLOTS-1];
  (* ram_style = "distributed" *) logic [RANK_WIDTH-1:0] node_rank_q [0:PACKET_SLOTS-1];
  (* ram_style = "distributed" *) logic [SEQ_WIDTH-1:0] node_seq_q [0:PACKET_SLOTS-1];
  (* ram_style = "distributed" *) logic [CELL_COUNT_WIDTH-1:0] node_cell_count_q [0:PACKET_SLOTS-1];
  (* ram_style = "distributed" *) logic [BATCH_ID_W-1:0] node_batch_id_q [0:PACKET_SLOTS-1];
  (* ram_style = "distributed" *) logic [BATCH_OFF_W-1:0] node_batch_offset_q [0:PACKET_SLOTS-1];
  (* ram_style = "distributed" *) logic [DESC_W-1:0] node_prev_q [0:PACKET_SLOTS-1];
  (* ram_style = "distributed" *) logic [DESC_W-1:0] node_next_q [0:PACKET_SLOTS-1];
  (* ram_style = "distributed" *) logic node_prev_valid_q [0:PACKET_SLOTS-1];
  (* ram_style = "distributed" *) logic node_next_valid_q [0:PACKET_SLOTS-1];

  state_t state_q;
  logic ready_q;
  logic [INIT_W-1:0] init_idx_q;
  localparam logic [INIT_W-1:0] BBQ_BITMAP_WIDTH_INIT = BBQ_BITMAP_WIDTH;
  localparam logic [INIT_W-1:0] PACKET_SLOTS_INIT = PACKET_SLOTS;
  localparam logic [INIT_W-1:0] INIT_LAST = (INIT_COUNT - 1);

  mp_bbq_cmd_t op_q;
  logic [DESC_W-1:0] op_desc_q;
  logic [RANK_WIDTH-1:0] op_rank_q;
  logic [SEQ_WIDTH-1:0] op_seq_q;
  logic [CELL_COUNT_WIDTH-1:0] op_cell_count_q;
  logic [BATCH_ID_W-1:0] op_batch_id_q;
  logic [BATCH_OFF_W-1:0] op_batch_offset_q;
  tier_t add_tier_q;
  tier_t remove_tier_q;
  logic add_after_remove_q;

  logic remove_active_q;
  logic remove_prev_valid_q;
  logic remove_next_valid_q;
  logic [DESC_W-1:0] remove_prev_q;
  logic [DESC_W-1:0] remove_next_q;
  priority_t remove_priority_q;

  logic add_bucket_empty_q;
  logic [DESC_W-1:0] add_tail_q;
  priority_t add_priority_q;

  logic refresh_sram_min_valid_q;
  logic refresh_sram_max_valid_q;
  logic refresh_hbm_min_valid_q;
  priority_t refresh_sram_min_priority_q;
  priority_t refresh_sram_max_priority_q;
  priority_t refresh_hbm_min_priority_q;
  logic [DESC_W-1:0] refresh_sram_min_desc_q;
  logic [DESC_W-1:0] refresh_sram_max_desc_q;
  logic [DESC_W-1:0] refresh_hbm_min_desc_q;

  logic [15:0] sram_occupancy_q;
  logic [15:0] hbm_occupancy_q;

  assign cmd_ready = ready_q && (state_q == S_IDLE);
  assign sram_occupancy = sram_occupancy_q;
  assign hbm_occupancy = hbm_occupancy_q;

  function automatic priority_t priority_from_rank(input logic [RANK_WIDTH-1:0] rank_i);
    priority_t prio_v;
    begin
      prio_v = '0;
      if (RANK_WIDTH >= PRIORITY_W) begin
        prio_v = rank_i[PRIORITY_W-1:0];
      end else begin
        prio_v[RANK_WIDTH-1:0] = rank_i;
      end
      priority_from_rank = prio_v;
    end
  endfunction

  function automatic logic [LEVEL_W-1:0] find_lsb(input bitmap_t bits_i);
    int fi;
    logic found_v;
    begin
      found_v = 1'b0;
      find_lsb = '0;
      for (fi = 0; fi < BBQ_BITMAP_WIDTH; fi = fi + 1) begin
        if (!found_v && bits_i[fi]) begin
          find_lsb = fi[LEVEL_W-1:0];
          found_v = 1'b1;
        end
      end
    end
  endfunction

  function automatic logic [LEVEL_W-1:0] find_msb(input bitmap_t bits_i);
    int fi;
    logic found_v;
    begin
      found_v = 1'b0;
      find_msb = '0;
      for (fi = BBQ_BITMAP_WIDTH - 1; fi >= 0; fi = fi - 1) begin
        if (!found_v && bits_i[fi]) begin
          find_msb = fi[LEVEL_W-1:0];
          found_v = 1'b1;
        end
      end
    end
  endfunction

  function automatic logic [LEVEL_W-1:0] prio_l1(input priority_t prio_i);
    begin
      prio_l1 = prio_i[PRIORITY_W-1:LEVEL_W];
    end
  endfunction

  function automatic logic [LEVEL_W-1:0] prio_l2(input priority_t prio_i);
    begin
      prio_l2 = prio_i[LEVEL_W-1:0];
    end
  endfunction

  task automatic clear_candidate_outputs;
    begin
      sram_min_valid <= 1'b0;
      sram_min_desc <= '0;
      sram_min_rank <= '0;
      sram_min_seq <= '0;
      sram_min_cell_count <= '0;
      sram_max_valid <= 1'b0;
      sram_max_desc <= '0;
      sram_max_rank <= '0;
      sram_max_seq <= '0;
      sram_max_cell_count <= '0;
      hbm_min_valid <= 1'b0;
      hbm_min_desc <= '0;
      hbm_min_rank <= '0;
      hbm_min_seq <= '0;
      hbm_min_cell_count <= '0;
      hbm_min_batch_id <= '0;
      hbm_min_batch_offset <= '0;
    end
  endtask

  always_ff @(posedge clk) begin
    logic [LEVEL_W-1:0] l1_v;
    logic [LEVEL_W-1:0] l2_v;
    logic [LEVEL_W-1:0] min_l1_v;
    logic [LEVEL_W-1:0] min_l2_v;
    logic [LEVEL_W-1:0] max_l1_v;
    logic [LEVEL_W-1:0] max_l2_v;
    priority_t prio_v;
    bitmap_t l2_next_v;
    logic remove_last_v;
    logic tier_match_v;

    if (!resetn) begin
      state_q <= S_INIT;
      ready_q <= 1'b0;
      init_idx_q <= '0;
      sram_l1_bitmap_q <= '0;
      hbm_l1_bitmap_q <= '0;
      sram_occupancy_q <= 16'd0;
      hbm_occupancy_q <= 16'd0;
      op_q <= MP_BBQ_CMD_NONE;
      op_desc_q <= '0;
      op_rank_q <= '0;
      op_seq_q <= '0;
      op_cell_count_q <= '0;
      op_batch_id_q <= '0;
      op_batch_offset_q <= '0;
      add_tier_q <= TIER_SRAM;
      remove_tier_q <= TIER_SRAM;
      add_after_remove_q <= 1'b0;
      remove_active_q <= 1'b0;
      remove_prev_valid_q <= 1'b0;
      remove_next_valid_q <= 1'b0;
      remove_prev_q <= '0;
      remove_next_q <= '0;
      remove_priority_q <= '0;
      add_bucket_empty_q <= 1'b1;
      add_tail_q <= '0;
      add_priority_q <= '0;
      refresh_sram_min_valid_q <= 1'b0;
      refresh_sram_max_valid_q <= 1'b0;
      refresh_hbm_min_valid_q <= 1'b0;
      refresh_sram_min_priority_q <= '0;
      refresh_sram_max_priority_q <= '0;
      refresh_hbm_min_priority_q <= '0;
      refresh_sram_min_desc_q <= '0;
      refresh_sram_max_desc_q <= '0;
      refresh_hbm_min_desc_q <= '0;
      clear_candidate_outputs();
    end else begin
      unique case (state_q)
        S_INIT: begin
          if (init_idx_q < BBQ_BITMAP_WIDTH_INIT) begin
            sram_l2_bitmap_q[init_idx_q] <= '0;
            hbm_l2_bitmap_q[init_idx_q] <= '0;
          end
          if (init_idx_q < PACKET_SLOTS_INIT) begin
            node_valid_q[init_idx_q] <= 1'b0;
          end
          if (init_idx_q == INIT_LAST) begin
            ready_q <= 1'b1;
            state_q <= S_IDLE;
          end
          init_idx_q <= init_idx_q + 1'b1;
        end

        S_IDLE: begin
          if (cmd_valid) begin
            op_q <= cmd_op;
            op_desc_q <= cmd_desc;
            op_rank_q <= cmd_rank;
            op_seq_q <= cmd_seq;
            op_cell_count_q <= cmd_cell_count;
            op_batch_id_q <= cmd_batch_id;
            op_batch_offset_q <= cmd_batch_offset;
            add_after_remove_q <= 1'b0;
            add_tier_q <= TIER_SRAM;
            remove_tier_q <= TIER_SRAM;

            unique case (cmd_op)
              MP_BBQ_CMD_ADD_SRAM: begin
                add_tier_q <= TIER_SRAM;
                state_q <= S_ADD_READ;
              end
              MP_BBQ_CMD_ADD_HBM: begin
                add_tier_q <= TIER_HBM;
                state_q <= S_ADD_READ;
              end
              MP_BBQ_CMD_MOVE_SRAM_TO_HBM: begin
                remove_tier_q <= TIER_SRAM;
                add_tier_q <= TIER_HBM;
                add_after_remove_q <= 1'b1;
                state_q <= S_REMOVE_READ;
              end
              MP_BBQ_CMD_MOVE_HBM_TO_SRAM: begin
                remove_tier_q <= TIER_HBM;
                add_tier_q <= TIER_SRAM;
                add_after_remove_q <= 1'b1;
                state_q <= S_REMOVE_READ;
              end
              MP_BBQ_CMD_REMOVE_SRAM: begin
                remove_tier_q <= TIER_SRAM;
                state_q <= S_REMOVE_READ;
              end
              MP_BBQ_CMD_REMOVE_HBM: begin
                remove_tier_q <= TIER_HBM;
                state_q <= S_REMOVE_READ;
              end
              default: begin
                state_q <= S_REFRESH_CALC;
              end
            endcase
          end
        end

        S_REMOVE_READ: begin
          tier_match_v = (node_in_hbm_q[op_desc_q] == (remove_tier_q == TIER_HBM));
          remove_active_q <= node_valid_q[op_desc_q] && tier_match_v;
          remove_priority_q <= node_priority_q[op_desc_q];
          remove_prev_q <= node_prev_q[op_desc_q];
          remove_next_q <= node_next_q[op_desc_q];
          remove_prev_valid_q <= node_prev_valid_q[op_desc_q];
          remove_next_valid_q <= node_next_valid_q[op_desc_q];
          state_q <= S_REMOVE_APPLY_PREV;
        end

        S_REMOVE_APPLY_PREV: begin
          if (remove_active_q) begin
            if (remove_prev_valid_q) begin
              node_next_q[remove_prev_q] <= remove_next_q;
              node_next_valid_q[remove_prev_q] <= remove_next_valid_q;
            end else if (remove_tier_q == TIER_SRAM) begin
              sram_bucket_head_q[remove_priority_q] <= remove_next_q;
            end else begin
              hbm_bucket_head_q[remove_priority_q] <= remove_next_q;
            end
          end
          state_q <= S_REMOVE_APPLY_NEXT;
        end

        S_REMOVE_APPLY_NEXT: begin
          if (remove_active_q) begin
            l1_v = prio_l1(remove_priority_q);
            l2_v = prio_l2(remove_priority_q);
            remove_last_v = !remove_prev_valid_q && !remove_next_valid_q;

            if (remove_next_valid_q) begin
              node_prev_q[remove_next_q] <= remove_prev_q;
              node_prev_valid_q[remove_next_q] <= remove_prev_valid_q;
            end else if (remove_tier_q == TIER_SRAM) begin
              sram_bucket_tail_q[remove_priority_q] <= remove_prev_q;
            end else begin
              hbm_bucket_tail_q[remove_priority_q] <= remove_prev_q;
            end

            if (remove_last_v) begin
              if (remove_tier_q == TIER_SRAM) begin
                l2_next_v = sram_l2_bitmap_q[l1_v] & ~(bitmap_t'(1'b1) << l2_v);
                sram_l2_bitmap_q[l1_v] <= l2_next_v;
                if (l2_next_v == '0) begin
                  sram_l1_bitmap_q[l1_v] <= 1'b0;
                end
              end else begin
                l2_next_v = hbm_l2_bitmap_q[l1_v] & ~(bitmap_t'(1'b1) << l2_v);
                hbm_l2_bitmap_q[l1_v] <= l2_next_v;
                if (l2_next_v == '0) begin
                  hbm_l1_bitmap_q[l1_v] <= 1'b0;
                end
              end
            end

            if (remove_tier_q == TIER_SRAM) begin
              sram_occupancy_q <= sram_occupancy_q - 16'd1;
            end else begin
              hbm_occupancy_q <= hbm_occupancy_q - 16'd1;
            end
          end
          state_q <= S_REMOVE_CLEAR;
        end

        S_REMOVE_CLEAR: begin
          if (remove_active_q) begin
            node_valid_q[op_desc_q] <= 1'b0;
            node_prev_valid_q[op_desc_q] <= 1'b0;
            node_next_valid_q[op_desc_q] <= 1'b0;
          end
          if (add_after_remove_q) begin
            state_q <= S_ADD_READ;
          end else begin
            state_q <= S_REFRESH_CALC;
          end
        end

        S_ADD_READ: begin
          prio_v = priority_from_rank(op_rank_q);
          l1_v = prio_l1(prio_v);
          l2_v = prio_l2(prio_v);
          add_priority_q <= prio_v;
          if (add_tier_q == TIER_SRAM) begin
            add_tail_q <= sram_bucket_tail_q[prio_v];
            add_bucket_empty_q <= !sram_l2_bitmap_q[l1_v][l2_v];
          end else begin
            add_tail_q <= hbm_bucket_tail_q[prio_v];
            add_bucket_empty_q <= !hbm_l2_bitmap_q[l1_v][l2_v];
          end
          state_q <= S_ADD_WRITE_NODE;
        end

        S_ADD_WRITE_NODE: begin
          node_valid_q[op_desc_q] <= 1'b1;
          node_in_hbm_q[op_desc_q] <= (add_tier_q == TIER_HBM);
          node_priority_q[op_desc_q] <= add_priority_q;
          node_rank_q[op_desc_q] <= op_rank_q;
          node_seq_q[op_desc_q] <= op_seq_q;
          node_cell_count_q[op_desc_q] <= op_cell_count_q;
          node_batch_id_q[op_desc_q] <= op_batch_id_q;
          node_batch_offset_q[op_desc_q] <= op_batch_offset_q;
          node_prev_q[op_desc_q] <= add_tail_q;
          node_prev_valid_q[op_desc_q] <= !add_bucket_empty_q;
          node_next_q[op_desc_q] <= '0;
          node_next_valid_q[op_desc_q] <= 1'b0;
          state_q <= S_ADD_LINK;
        end

        S_ADD_LINK: begin
          l1_v = prio_l1(add_priority_q);
          l2_v = prio_l2(add_priority_q);
          if (add_tier_q == TIER_SRAM) begin
            if (add_bucket_empty_q) begin
              sram_bucket_head_q[add_priority_q] <= op_desc_q;
              sram_l1_bitmap_q[l1_v] <= 1'b1;
              sram_l2_bitmap_q[l1_v][l2_v] <= 1'b1;
            end else begin
              node_next_q[add_tail_q] <= op_desc_q;
              node_next_valid_q[add_tail_q] <= 1'b1;
            end
            sram_bucket_tail_q[add_priority_q] <= op_desc_q;
            sram_occupancy_q <= sram_occupancy_q + 16'd1;
          end else begin
            if (add_bucket_empty_q) begin
              hbm_bucket_head_q[add_priority_q] <= op_desc_q;
              hbm_l1_bitmap_q[l1_v] <= 1'b1;
              hbm_l2_bitmap_q[l1_v][l2_v] <= 1'b1;
            end else begin
              node_next_q[add_tail_q] <= op_desc_q;
              node_next_valid_q[add_tail_q] <= 1'b1;
            end
            hbm_bucket_tail_q[add_priority_q] <= op_desc_q;
            hbm_occupancy_q <= hbm_occupancy_q + 16'd1;
          end
          state_q <= S_REFRESH_CALC;
        end

        S_REFRESH_CALC: begin
          refresh_sram_min_valid_q <= (sram_l1_bitmap_q != '0);
          refresh_sram_max_valid_q <= (sram_l1_bitmap_q != '0);
          refresh_hbm_min_valid_q <= (hbm_l1_bitmap_q != '0);

          min_l1_v = find_lsb(sram_l1_bitmap_q);
          min_l2_v = find_lsb(sram_l2_bitmap_q[min_l1_v]);
          max_l1_v = find_msb(sram_l1_bitmap_q);
          max_l2_v = find_msb(sram_l2_bitmap_q[max_l1_v]);
          refresh_sram_min_priority_q <= {min_l1_v, min_l2_v};
          refresh_sram_max_priority_q <= {max_l1_v, max_l2_v};

          min_l1_v = find_lsb(hbm_l1_bitmap_q);
          min_l2_v = find_lsb(hbm_l2_bitmap_q[min_l1_v]);
          refresh_hbm_min_priority_q <= {min_l1_v, min_l2_v};
          state_q <= S_REFRESH_BUCKET;
        end

        S_REFRESH_BUCKET: begin
          if (refresh_sram_min_valid_q) begin
            refresh_sram_min_desc_q <= sram_bucket_head_q[refresh_sram_min_priority_q];
          end else begin
            refresh_sram_min_desc_q <= '0;
          end
          if (refresh_sram_max_valid_q) begin
            refresh_sram_max_desc_q <= sram_bucket_tail_q[refresh_sram_max_priority_q];
          end else begin
            refresh_sram_max_desc_q <= '0;
          end
          if (refresh_hbm_min_valid_q) begin
            refresh_hbm_min_desc_q <= hbm_bucket_head_q[refresh_hbm_min_priority_q];
          end else begin
            refresh_hbm_min_desc_q <= '0;
          end
          state_q <= S_REFRESH_NODE;
        end

        S_REFRESH_NODE: begin
          sram_min_valid <= refresh_sram_min_valid_q;
          sram_min_desc <= refresh_sram_min_desc_q;
          sram_min_rank <= node_rank_q[refresh_sram_min_desc_q];
          sram_min_seq <= node_seq_q[refresh_sram_min_desc_q];
          sram_min_cell_count <= node_cell_count_q[refresh_sram_min_desc_q];

          sram_max_valid <= refresh_sram_max_valid_q;
          sram_max_desc <= refresh_sram_max_desc_q;
          sram_max_rank <= node_rank_q[refresh_sram_max_desc_q];
          sram_max_seq <= node_seq_q[refresh_sram_max_desc_q];
          sram_max_cell_count <= node_cell_count_q[refresh_sram_max_desc_q];

          hbm_min_valid <= refresh_hbm_min_valid_q;
          hbm_min_desc <= refresh_hbm_min_desc_q;
          hbm_min_rank <= node_rank_q[refresh_hbm_min_desc_q];
          hbm_min_seq <= node_seq_q[refresh_hbm_min_desc_q];
          hbm_min_cell_count <= node_cell_count_q[refresh_hbm_min_desc_q];
          hbm_min_batch_id <= node_batch_id_q[refresh_hbm_min_desc_q];
          hbm_min_batch_offset <= node_batch_offset_q[refresh_hbm_min_desc_q];
          state_q <= S_IDLE;
        end

        default: begin
          state_q <= S_REFRESH_CALC;
        end
      endcase
    end
  end
endmodule
