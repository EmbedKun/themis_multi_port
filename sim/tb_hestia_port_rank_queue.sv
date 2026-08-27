`timescale 1ns/1ps

import hestia_pkg::*;

module tb_hestia_port_rank_queue;
  localparam int RANK_WIDTH = 8;
  localparam int PACKET_ID_WIDTH = 16;
  localparam int SRAM_SLOT_WIDTH = 5;
  localparam int BATCH_ID_WIDTH = 3;
  localparam int BATCH_OFFSET_WIDTH = 2;
  localparam int ENTRY_DEPTH = 32;

  logic clk = 1'b0;
  logic resetn = 1'b0;
  always #2 clk = ~clk;

  logic cmd_valid;
  mp_port_cmd_t cmd_op;
  logic [RANK_WIDTH-1:0] cmd_rank;
  logic [PACKET_ID_WIDTH-1:0] cmd_packet_id;
  logic [SRAM_SLOT_WIDTH-1:0] cmd_sram_slot;
  logic [BATCH_ID_WIDTH-1:0] cmd_batch_id;
  logic [BATCH_OFFSET_WIDTH-1:0] cmd_batch_offset;
  logic cmd_ready;

  logic sram_min_valid;
  logic [RANK_WIDTH-1:0] sram_min_rank;
  logic [PACKET_ID_WIDTH-1:0] sram_min_packet_id;
  logic [SRAM_SLOT_WIDTH-1:0] sram_min_slot;
  logic sram_max_valid;
  logic [RANK_WIDTH-1:0] sram_max_rank;
  logic [PACKET_ID_WIDTH-1:0] sram_max_packet_id;
  logic [SRAM_SLOT_WIDTH-1:0] sram_max_slot;
  logic hbm_min_valid;
  logic [RANK_WIDTH-1:0] hbm_min_rank;
  logic [PACKET_ID_WIDTH-1:0] hbm_min_packet_id;
  logic [BATCH_ID_WIDTH-1:0] hbm_min_batch_id;
  logic [BATCH_OFFSET_WIDTH-1:0] hbm_min_batch_offset;
  logic [15:0] dbg_sram_entries;
  logic [15:0] dbg_hbm_entries;

  hestia_port_rank_queue #(
    .RANK_WIDTH(RANK_WIDTH),
    .PACKET_ID_WIDTH(PACKET_ID_WIDTH),
    .SRAM_SLOT_WIDTH(SRAM_SLOT_WIDTH),
    .BATCH_ID_WIDTH(BATCH_ID_WIDTH),
    .BATCH_OFFSET_WIDTH(BATCH_OFFSET_WIDTH),
    .ENTRY_DEPTH(ENTRY_DEPTH)
  ) dut (
    .clk(clk),
    .resetn(resetn),
    .cmd_valid(cmd_valid),
    .cmd_op(cmd_op),
    .cmd_rank(cmd_rank),
    .cmd_packet_id(cmd_packet_id),
    .cmd_sram_slot(cmd_sram_slot),
    .cmd_batch_id(cmd_batch_id),
    .cmd_batch_offset(cmd_batch_offset),
    .cmd_ready(cmd_ready),
    .sram_min_valid(sram_min_valid),
    .sram_min_rank(sram_min_rank),
    .sram_min_packet_id(sram_min_packet_id),
    .sram_min_slot(sram_min_slot),
    .sram_max_valid(sram_max_valid),
    .sram_max_rank(sram_max_rank),
    .sram_max_packet_id(sram_max_packet_id),
    .sram_max_slot(sram_max_slot),
    .hbm_min_valid(hbm_min_valid),
    .hbm_min_rank(hbm_min_rank),
    .hbm_min_packet_id(hbm_min_packet_id),
    .hbm_min_batch_id(hbm_min_batch_id),
    .hbm_min_batch_offset(hbm_min_batch_offset),
    .dbg_sram_entries(dbg_sram_entries),
    .dbg_hbm_entries(dbg_hbm_entries)
  );

  task automatic tick(input int cycles);
    int i;
    begin
      for (i = 0; i < cycles; i = i + 1) begin
        @(posedge clk);
      end
    end
  endtask

  task automatic wait_ready;
    int guard;
    begin
      guard = 0;
      while (!cmd_ready) begin
        tick(1);
        guard = guard + 1;
        if (guard > 200) begin
          $fatal(1, "Timeout waiting for queue ready");
        end
      end
    end
  endtask

  task automatic issue_add_sram(
    input logic [RANK_WIDTH-1:0] rank_i,
    input logic [PACKET_ID_WIDTH-1:0] packet_i,
    input logic [SRAM_SLOT_WIDTH-1:0] slot_i
  );
    begin
      wait_ready();
      cmd_rank = rank_i;
      cmd_packet_id = packet_i;
      cmd_sram_slot = slot_i;
      cmd_batch_id = '0;
      cmd_batch_offset = '0;
      cmd_op = MP_CMD_ADD_SRAM;
      cmd_valid = 1'b1;
      tick(1);
      cmd_valid = 1'b0;
      cmd_op = MP_CMD_NONE;
      cmd_rank = '0;
      cmd_packet_id = '0;
      cmd_sram_slot = '0;
    end
  endtask

  task automatic remove_min;
    begin
      wait_ready();
      cmd_op = MP_CMD_REMOVE_SRAM_MIN;
      cmd_valid = 1'b1;
      tick(1);
      cmd_valid = 1'b0;
      cmd_op = MP_CMD_NONE;
    end
  endtask

  task automatic expect_min(input int expected_rank);
    begin
      wait_ready();
      if (!sram_min_valid || sram_min_rank !== expected_rank[RANK_WIDTH-1:0]) begin
        $fatal(1, "Expected SRAM min rank %0d, got valid=%0d rank=%0d count=%0d",
               expected_rank, sram_min_valid, sram_min_rank, dbg_sram_entries);
      end
    end
  endtask

  initial begin
    cmd_valid = 1'b0;
    cmd_op = MP_CMD_NONE;
    cmd_rank = '0;
    cmd_packet_id = '0;
    cmd_sram_slot = '0;
    cmd_batch_id = '0;
    cmd_batch_offset = '0;

    tick(5);
    resetn = 1'b1;
    wait_ready();

    issue_add_sram(8'd10, 16'd10, 5'd1);
    issue_add_sram(8'd3, 16'd11, 5'd2);
    issue_add_sram(8'd7, 16'd12, 5'd3);
    expect_min(3);
    if (!sram_max_valid || sram_max_rank !== 8'd10 || dbg_sram_entries !== 16'd3) begin
      $fatal(1, "Unexpected SRAM max/count max_valid=%0d max=%0d count=%0d",
             sram_max_valid, sram_max_rank, dbg_sram_entries);
    end

    remove_min();
    expect_min(7);
    remove_min();
    expect_min(10);
    remove_min();
    wait_ready();
    if (sram_min_valid || dbg_sram_entries !== 16'd0) begin
      $fatal(1, "Expected empty SRAM queue, valid=%0d count=%0d", sram_min_valid, dbg_sram_entries);
    end

    $display("PASS: port rank queue summary rebuild preserves SRAM rank order");
    $finish;
  end
endmodule
