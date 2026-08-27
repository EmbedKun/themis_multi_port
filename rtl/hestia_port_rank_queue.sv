`timescale 1ns/1ps

import hestia_pkg::*;

module hestia_port_rank_queue #(
  parameter int RANK_WIDTH = 10,
  parameter int PACKET_ID_WIDTH = 32,
  parameter int SRAM_SLOT_WIDTH = 8,
  parameter int BATCH_ID_WIDTH = 4,
  parameter int BATCH_OFFSET_WIDTH = 3,
  parameter int ENTRY_DEPTH = 64,
  localparam int ENTRY_IDX_WIDTH = (ENTRY_DEPTH <= 2) ? 1 : $clog2(ENTRY_DEPTH),
  localparam int HANDLE_WIDTH = BATCH_ID_WIDTH + BATCH_OFFSET_WIDTH,
  localparam int HANDLE_DEPTH = (1 << HANDLE_WIDTH),
  localparam logic [ENTRY_IDX_WIDTH:0] ENTRY_DEPTH_COUNT = ENTRY_DEPTH
) (
  input  logic                            clk,
  input  logic                            resetn,

  input  logic                            cmd_valid,
  input  mp_port_cmd_t                    cmd_op,
  input  logic [RANK_WIDTH-1:0]           cmd_rank,
  input  logic [PACKET_ID_WIDTH-1:0]      cmd_packet_id,
  input  logic [SRAM_SLOT_WIDTH-1:0]      cmd_sram_slot,
  input  logic [BATCH_ID_WIDTH-1:0]       cmd_batch_id,
  input  logic [BATCH_OFFSET_WIDTH-1:0]   cmd_batch_offset,
  output logic                            cmd_ready,

  output logic                            sram_min_valid,
  output logic [RANK_WIDTH-1:0]           sram_min_rank,
  output logic [PACKET_ID_WIDTH-1:0]      sram_min_packet_id,
  output logic [SRAM_SLOT_WIDTH-1:0]      sram_min_slot,

  output logic                            sram_max_valid,
  output logic [RANK_WIDTH-1:0]           sram_max_rank,
  output logic [PACKET_ID_WIDTH-1:0]      sram_max_packet_id,
  output logic [SRAM_SLOT_WIDTH-1:0]      sram_max_slot,

  output logic                            hbm_min_valid,
  output logic [RANK_WIDTH-1:0]           hbm_min_rank,
  output logic [PACKET_ID_WIDTH-1:0]      hbm_min_packet_id,
  output logic [BATCH_ID_WIDTH-1:0]       hbm_min_batch_id,
  output logic [BATCH_OFFSET_WIDTH-1:0]   hbm_min_batch_offset,

  output logic                            idle_ready,
  output logic [15:0]                     dbg_sram_entries,
  output logic [15:0]                     dbg_hbm_entries
);
  logic entry_valid [0:ENTRY_DEPTH-1];
  (* ram_style = "distributed" *) mp_loc_t entry_loc [0:ENTRY_DEPTH-1];
  (* ram_style = "distributed" *) logic [RANK_WIDTH-1:0] entry_rank [0:ENTRY_DEPTH-1];
  (* ram_style = "distributed" *) logic [PACKET_ID_WIDTH-1:0] entry_packet_id [0:ENTRY_DEPTH-1];
  (* ram_style = "distributed" *) logic [SRAM_SLOT_WIDTH-1:0] entry_sram_slot [0:ENTRY_DEPTH-1];
  (* ram_style = "distributed" *) logic [BATCH_ID_WIDTH-1:0] entry_batch_id [0:ENTRY_DEPTH-1];
  (* ram_style = "distributed" *) logic [BATCH_OFFSET_WIDTH-1:0] entry_batch_offset [0:ENTRY_DEPTH-1];

  logic [ENTRY_IDX_WIDTH-1:0] free_stack [0:ENTRY_DEPTH-1];
  logic [ENTRY_IDX_WIDTH:0] free_count_q;

  logic handle_valid [0:HANDLE_DEPTH-1];
  (* ram_style = "distributed" *) logic [ENTRY_IDX_WIDTH-1:0] handle_entry [0:HANDLE_DEPTH-1];

  logic cmd_pending_q;
  mp_port_cmd_t cmd_op_q;
  logic [RANK_WIDTH-1:0] cmd_rank_q;
  logic [PACKET_ID_WIDTH-1:0] cmd_packet_id_q;
  logic [SRAM_SLOT_WIDTH-1:0] cmd_sram_slot_q;
  logic [BATCH_ID_WIDTH-1:0] cmd_batch_id_q;
  logic [BATCH_OFFSET_WIDTH-1:0] cmd_batch_offset_q;
  logic [ENTRY_IDX_WIDTH-1:0] cmd_free_idx_q;

  logic rebuild_active_q;
  logic [ENTRY_IDX_WIDTH:0] rebuild_idx_q;
  logic sram_min_valid_next_q;
  logic [RANK_WIDTH-1:0] sram_min_rank_next_q;
  logic [PACKET_ID_WIDTH-1:0] sram_min_packet_id_next_q;
  logic [SRAM_SLOT_WIDTH-1:0] sram_min_slot_next_q;
  logic [ENTRY_IDX_WIDTH-1:0] sram_min_idx_next_q;
  logic sram_max_valid_next_q;
  logic [RANK_WIDTH-1:0] sram_max_rank_next_q;
  logic [PACKET_ID_WIDTH-1:0] sram_max_packet_id_next_q;
  logic [SRAM_SLOT_WIDTH-1:0] sram_max_slot_next_q;
  logic [ENTRY_IDX_WIDTH-1:0] sram_max_idx_next_q;
  logic hbm_min_valid_next_q;
  logic [RANK_WIDTH-1:0] hbm_min_rank_next_q;
  logic [PACKET_ID_WIDTH-1:0] hbm_min_packet_id_next_q;
  logic [BATCH_ID_WIDTH-1:0] hbm_min_batch_id_next_q;
  logic [BATCH_OFFSET_WIDTH-1:0] hbm_min_batch_offset_next_q;
  logic [ENTRY_IDX_WIDTH-1:0] hbm_min_idx_next_q;
  logic [15:0] dbg_sram_entries_next_q;
  logic [15:0] dbg_hbm_entries_next_q;

  logic [ENTRY_IDX_WIDTH-1:0] sram_min_idx_q;
  logic [ENTRY_IDX_WIDTH-1:0] sram_max_idx_q;
  logic [ENTRY_IDX_WIDTH-1:0] hbm_min_idx_q;

  wire [HANDLE_WIDTH-1:0] cmd_handle = {cmd_batch_id, cmd_batch_offset};
  wire [HANDLE_WIDTH-1:0] cmd_handle_q = {cmd_batch_id_q, cmd_batch_offset_q};
  wire [ENTRY_IDX_WIDTH-1:0] free_head = (free_count_q == '0) ? '0 : free_stack[free_count_q - 1'b1];

  assign idle_ready = !rebuild_active_q && !cmd_pending_q;

  always_comb begin
    if (rebuild_active_q || cmd_pending_q) begin
      cmd_ready = 1'b0;
    end else begin
      unique case (cmd_op)
        MP_CMD_ADD_SRAM,
        MP_CMD_ADD_HBM: begin
          cmd_ready = (free_count_q != '0);
        end
        MP_CMD_MOVE_SRAM_MAX_HBM: begin
          cmd_ready = sram_max_valid;
        end
        MP_CMD_REMOVE_SRAM_MIN: begin
          cmd_ready = sram_min_valid;
        end
        MP_CMD_REMOVE_HBM_MIN: begin
          cmd_ready = hbm_min_valid;
        end
        MP_CMD_MOVE_HBM_SRAM: begin
          cmd_ready = handle_valid[cmd_handle];
        end
        default: begin
          cmd_ready = 1'b1;
        end
      endcase
    end
  end

  task automatic begin_rebuild;
    begin
      rebuild_active_q <= 1'b1;
      rebuild_idx_q <= '0;
      sram_min_valid_next_q <= 1'b0;
      sram_min_rank_next_q <= '1;
      sram_min_packet_id_next_q <= '1;
      sram_min_slot_next_q <= '0;
      sram_min_idx_next_q <= '0;
      sram_max_valid_next_q <= 1'b0;
      sram_max_rank_next_q <= '0;
      sram_max_packet_id_next_q <= '0;
      sram_max_slot_next_q <= '0;
      sram_max_idx_next_q <= '0;
      hbm_min_valid_next_q <= 1'b0;
      hbm_min_rank_next_q <= '1;
      hbm_min_packet_id_next_q <= '1;
      hbm_min_batch_id_next_q <= '0;
      hbm_min_batch_offset_next_q <= '0;
      hbm_min_idx_next_q <= '0;
      dbg_sram_entries_next_q <= 16'd0;
      dbg_hbm_entries_next_q <= 16'd0;
    end
  endtask

  integer init_i;
  integer handle_i;
  always_ff @(posedge clk) begin
    logic [ENTRY_IDX_WIDTH-1:0] idx_v;
    logic [HANDLE_WIDTH-1:0] handle_v;
    logic sram_min_better_v;
    logic sram_max_better_v;
    logic hbm_min_better_v;
    logic tmp_sram_min_valid_v;
    logic [RANK_WIDTH-1:0] tmp_sram_min_rank_v;
    logic [PACKET_ID_WIDTH-1:0] tmp_sram_min_packet_id_v;
    logic [SRAM_SLOT_WIDTH-1:0] tmp_sram_min_slot_v;
    logic [ENTRY_IDX_WIDTH-1:0] tmp_sram_min_idx_v;
    logic tmp_sram_max_valid_v;
    logic [RANK_WIDTH-1:0] tmp_sram_max_rank_v;
    logic [PACKET_ID_WIDTH-1:0] tmp_sram_max_packet_id_v;
    logic [SRAM_SLOT_WIDTH-1:0] tmp_sram_max_slot_v;
    logic [ENTRY_IDX_WIDTH-1:0] tmp_sram_max_idx_v;
    logic tmp_hbm_min_valid_v;
    logic [RANK_WIDTH-1:0] tmp_hbm_min_rank_v;
    logic [PACKET_ID_WIDTH-1:0] tmp_hbm_min_packet_id_v;
    logic [BATCH_ID_WIDTH-1:0] tmp_hbm_min_batch_id_v;
    logic [BATCH_OFFSET_WIDTH-1:0] tmp_hbm_min_batch_offset_v;
    logic [ENTRY_IDX_WIDTH-1:0] tmp_hbm_min_idx_v;
    logic [15:0] tmp_dbg_sram_entries_v;
    logic [15:0] tmp_dbg_hbm_entries_v;
    if (!resetn) begin
      for (init_i = 0; init_i < ENTRY_DEPTH; init_i = init_i + 1) begin
        entry_valid[init_i] <= 1'b0;
        free_stack[init_i] <= init_i[ENTRY_IDX_WIDTH-1:0];
      end
      for (handle_i = 0; handle_i < HANDLE_DEPTH; handle_i = handle_i + 1) begin
        handle_valid[handle_i] <= 1'b0;
      end
      free_count_q <= ENTRY_DEPTH_COUNT;
      cmd_pending_q <= 1'b0;
      cmd_op_q <= MP_CMD_NONE;
      cmd_rank_q <= '0;
      cmd_packet_id_q <= '0;
      cmd_sram_slot_q <= '0;
      cmd_batch_id_q <= '0;
      cmd_batch_offset_q <= '0;
      cmd_free_idx_q <= '0;
      rebuild_active_q <= 1'b0;
      rebuild_idx_q <= '0;
      sram_min_valid <= 1'b0;
      sram_min_rank <= '1;
      sram_min_packet_id <= '1;
      sram_min_slot <= '0;
      sram_min_idx_q <= '0;
      sram_max_valid <= 1'b0;
      sram_max_rank <= '0;
      sram_max_packet_id <= '0;
      sram_max_slot <= '0;
      sram_max_idx_q <= '0;
      hbm_min_valid <= 1'b0;
      hbm_min_rank <= '1;
      hbm_min_packet_id <= '1;
      hbm_min_batch_id <= '0;
      hbm_min_batch_offset <= '0;
      hbm_min_idx_q <= '0;
      dbg_sram_entries <= 16'd0;
      dbg_hbm_entries <= 16'd0;
      begin_rebuild();
    end else if (rebuild_active_q) begin
      idx_v = rebuild_idx_q[ENTRY_IDX_WIDTH-1:0];
      tmp_sram_min_valid_v = sram_min_valid_next_q;
      tmp_sram_min_rank_v = sram_min_rank_next_q;
      tmp_sram_min_packet_id_v = sram_min_packet_id_next_q;
      tmp_sram_min_slot_v = sram_min_slot_next_q;
      tmp_sram_min_idx_v = sram_min_idx_next_q;
      tmp_sram_max_valid_v = sram_max_valid_next_q;
      tmp_sram_max_rank_v = sram_max_rank_next_q;
      tmp_sram_max_packet_id_v = sram_max_packet_id_next_q;
      tmp_sram_max_slot_v = sram_max_slot_next_q;
      tmp_sram_max_idx_v = sram_max_idx_next_q;
      tmp_hbm_min_valid_v = hbm_min_valid_next_q;
      tmp_hbm_min_rank_v = hbm_min_rank_next_q;
      tmp_hbm_min_packet_id_v = hbm_min_packet_id_next_q;
      tmp_hbm_min_batch_id_v = hbm_min_batch_id_next_q;
      tmp_hbm_min_batch_offset_v = hbm_min_batch_offset_next_q;
      tmp_hbm_min_idx_v = hbm_min_idx_next_q;
      tmp_dbg_sram_entries_v = dbg_sram_entries_next_q;
      tmp_dbg_hbm_entries_v = dbg_hbm_entries_next_q;

      if ((rebuild_idx_q < ENTRY_DEPTH) && entry_valid[idx_v]) begin
        if (entry_loc[idx_v] == MP_LOC_SRAM) begin
          tmp_dbg_sram_entries_v = tmp_dbg_sram_entries_v + 16'd1;
          sram_min_better_v = !tmp_sram_min_valid_v ||
                              (entry_rank[idx_v] < tmp_sram_min_rank_v) ||
                              ((entry_rank[idx_v] == tmp_sram_min_rank_v) &&
                               (entry_packet_id[idx_v] < tmp_sram_min_packet_id_v));
          sram_max_better_v = !tmp_sram_max_valid_v ||
                              (entry_rank[idx_v] > tmp_sram_max_rank_v) ||
                              ((entry_rank[idx_v] == tmp_sram_max_rank_v) &&
                               (entry_packet_id[idx_v] > tmp_sram_max_packet_id_v));
          if (sram_min_better_v) begin
            tmp_sram_min_valid_v = 1'b1;
            tmp_sram_min_rank_v = entry_rank[idx_v];
            tmp_sram_min_packet_id_v = entry_packet_id[idx_v];
            tmp_sram_min_slot_v = entry_sram_slot[idx_v];
            tmp_sram_min_idx_v = idx_v;
          end
          if (sram_max_better_v) begin
            tmp_sram_max_valid_v = 1'b1;
            tmp_sram_max_rank_v = entry_rank[idx_v];
            tmp_sram_max_packet_id_v = entry_packet_id[idx_v];
            tmp_sram_max_slot_v = entry_sram_slot[idx_v];
            tmp_sram_max_idx_v = idx_v;
          end
        end else begin
          tmp_dbg_hbm_entries_v = tmp_dbg_hbm_entries_v + 16'd1;
          hbm_min_better_v = !tmp_hbm_min_valid_v ||
                             (entry_rank[idx_v] < tmp_hbm_min_rank_v) ||
                             ((entry_rank[idx_v] == tmp_hbm_min_rank_v) &&
                              (entry_packet_id[idx_v] < tmp_hbm_min_packet_id_v));
          if (hbm_min_better_v) begin
            tmp_hbm_min_valid_v = 1'b1;
            tmp_hbm_min_rank_v = entry_rank[idx_v];
            tmp_hbm_min_packet_id_v = entry_packet_id[idx_v];
            tmp_hbm_min_batch_id_v = entry_batch_id[idx_v];
            tmp_hbm_min_batch_offset_v = entry_batch_offset[idx_v];
            tmp_hbm_min_idx_v = idx_v;
          end
        end
      end

      if (rebuild_idx_q == (ENTRY_DEPTH - 1)) begin
        sram_min_valid <= tmp_sram_min_valid_v;
        sram_min_rank <= tmp_sram_min_rank_v;
        sram_min_packet_id <= tmp_sram_min_packet_id_v;
        sram_min_slot <= tmp_sram_min_slot_v;
        sram_min_idx_q <= tmp_sram_min_idx_v;
        sram_max_valid <= tmp_sram_max_valid_v;
        sram_max_rank <= tmp_sram_max_rank_v;
        sram_max_packet_id <= tmp_sram_max_packet_id_v;
        sram_max_slot <= tmp_sram_max_slot_v;
        sram_max_idx_q <= tmp_sram_max_idx_v;
        hbm_min_valid <= tmp_hbm_min_valid_v;
        hbm_min_rank <= tmp_hbm_min_rank_v;
        hbm_min_packet_id <= tmp_hbm_min_packet_id_v;
        hbm_min_batch_id <= tmp_hbm_min_batch_id_v;
        hbm_min_batch_offset <= tmp_hbm_min_batch_offset_v;
        hbm_min_idx_q <= tmp_hbm_min_idx_v;
        dbg_sram_entries <= tmp_dbg_sram_entries_v;
        dbg_hbm_entries <= tmp_dbg_hbm_entries_v;
        rebuild_active_q <= 1'b0;
      end else begin
        sram_min_valid_next_q <= tmp_sram_min_valid_v;
        sram_min_rank_next_q <= tmp_sram_min_rank_v;
        sram_min_packet_id_next_q <= tmp_sram_min_packet_id_v;
        sram_min_slot_next_q <= tmp_sram_min_slot_v;
        sram_min_idx_next_q <= tmp_sram_min_idx_v;
        sram_max_valid_next_q <= tmp_sram_max_valid_v;
        sram_max_rank_next_q <= tmp_sram_max_rank_v;
        sram_max_packet_id_next_q <= tmp_sram_max_packet_id_v;
        sram_max_slot_next_q <= tmp_sram_max_slot_v;
        sram_max_idx_next_q <= tmp_sram_max_idx_v;
        hbm_min_valid_next_q <= tmp_hbm_min_valid_v;
        hbm_min_rank_next_q <= tmp_hbm_min_rank_v;
        hbm_min_packet_id_next_q <= tmp_hbm_min_packet_id_v;
        hbm_min_batch_id_next_q <= tmp_hbm_min_batch_id_v;
        hbm_min_batch_offset_next_q <= tmp_hbm_min_batch_offset_v;
        hbm_min_idx_next_q <= tmp_hbm_min_idx_v;
        dbg_sram_entries_next_q <= tmp_dbg_sram_entries_v;
        dbg_hbm_entries_next_q <= tmp_dbg_hbm_entries_v;
        rebuild_idx_q <= rebuild_idx_q + 1'b1;
      end
    end else if (cmd_pending_q) begin
      cmd_pending_q <= 1'b0;
      unique case (cmd_op_q)
        MP_CMD_ADD_SRAM: begin
          idx_v = cmd_free_idx_q;
          free_count_q <= free_count_q - 1'b1;
          entry_valid[idx_v] <= 1'b1;
          entry_loc[idx_v] <= MP_LOC_SRAM;
          entry_rank[idx_v] <= cmd_rank_q;
          entry_packet_id[idx_v] <= cmd_packet_id_q;
          entry_sram_slot[idx_v] <= cmd_sram_slot_q;
          entry_batch_id[idx_v] <= '0;
          entry_batch_offset[idx_v] <= '0;
          begin_rebuild();
        end
        MP_CMD_ADD_HBM: begin
          idx_v = cmd_free_idx_q;
          handle_v = cmd_handle_q;
          free_count_q <= free_count_q - 1'b1;
          entry_valid[idx_v] <= 1'b1;
          entry_loc[idx_v] <= MP_LOC_HBM;
          entry_rank[idx_v] <= cmd_rank_q;
          entry_packet_id[idx_v] <= cmd_packet_id_q;
          entry_sram_slot[idx_v] <= '0;
          entry_batch_id[idx_v] <= cmd_batch_id_q;
          entry_batch_offset[idx_v] <= cmd_batch_offset_q;
          handle_valid[handle_v] <= 1'b1;
          handle_entry[handle_v] <= idx_v;
          begin_rebuild();
        end
        MP_CMD_MOVE_SRAM_MAX_HBM: begin
          handle_v = cmd_handle_q;
          entry_loc[sram_max_idx_q] <= MP_LOC_HBM;
          entry_batch_id[sram_max_idx_q] <= cmd_batch_id_q;
          entry_batch_offset[sram_max_idx_q] <= cmd_batch_offset_q;
          handle_valid[handle_v] <= 1'b1;
          handle_entry[handle_v] <= sram_max_idx_q;
          begin_rebuild();
        end
        MP_CMD_REMOVE_SRAM_MIN: begin
          entry_valid[sram_min_idx_q] <= 1'b0;
          free_stack[free_count_q] <= sram_min_idx_q;
          free_count_q <= free_count_q + 1'b1;
          begin_rebuild();
        end
        MP_CMD_REMOVE_HBM_MIN: begin
          handle_v = {hbm_min_batch_id, hbm_min_batch_offset};
          entry_valid[hbm_min_idx_q] <= 1'b0;
          handle_valid[handle_v] <= 1'b0;
          free_stack[free_count_q] <= hbm_min_idx_q;
          free_count_q <= free_count_q + 1'b1;
          begin_rebuild();
        end
        MP_CMD_MOVE_HBM_SRAM: begin
          handle_v = cmd_handle_q;
          idx_v = handle_entry[handle_v];
          entry_loc[idx_v] <= MP_LOC_SRAM;
          entry_sram_slot[idx_v] <= cmd_sram_slot_q;
          entry_batch_id[idx_v] <= '0;
          entry_batch_offset[idx_v] <= '0;
          handle_valid[handle_v] <= 1'b0;
          begin_rebuild();
        end
        default: begin
        end
      endcase
    end else if (cmd_valid && cmd_ready) begin
      cmd_pending_q <= 1'b1;
      cmd_op_q <= cmd_op;
      cmd_rank_q <= cmd_rank;
      cmd_packet_id_q <= cmd_packet_id;
      cmd_sram_slot_q <= cmd_sram_slot;
      cmd_batch_id_q <= cmd_batch_id;
      cmd_batch_offset_q <= cmd_batch_offset;
      cmd_free_idx_q <= free_head;
    end
  end
endmodule
