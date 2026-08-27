`timescale 1ns/1ps

import hestia_pkg::*;

module tb_hestia_port_bbq;
  localparam int RANK_WIDTH = 8;
  localparam int SEQ_WIDTH = 16;
  localparam int CELL_COUNT_WIDTH = 4;
  localparam int BATCH_SIZE = 4;
  localparam int BATCH_SLOTS = 8;
  localparam int PACKET_SLOTS = 32;
  localparam int BBQ_BITMAP_WIDTH = 16;
  localparam int DESC_W = $clog2(PACKET_SLOTS);
  localparam int BATCH_ID_W = $clog2(BATCH_SLOTS);
  localparam int BATCH_OFF_W = $clog2(BATCH_SIZE);

  logic clk = 1'b0;
  logic resetn = 1'b0;
  always #2 clk = ~clk;

  logic cmd_valid;
  logic cmd_ready;
  mp_bbq_cmd_t cmd_op;
  logic [DESC_W-1:0] cmd_desc;
  logic [RANK_WIDTH-1:0] cmd_rank;
  logic [SEQ_WIDTH-1:0] cmd_seq;
  logic [CELL_COUNT_WIDTH-1:0] cmd_cell_count;
  logic [BATCH_ID_W-1:0] cmd_batch_id;
  logic [BATCH_OFF_W-1:0] cmd_batch_offset;

  logic sram_min_valid;
  logic [DESC_W-1:0] sram_min_desc;
  logic [RANK_WIDTH-1:0] sram_min_rank;
  logic [SEQ_WIDTH-1:0] sram_min_seq;
  logic [CELL_COUNT_WIDTH-1:0] sram_min_cell_count;
  logic sram_max_valid;
  logic [DESC_W-1:0] sram_max_desc;
  logic [RANK_WIDTH-1:0] sram_max_rank;
  logic [SEQ_WIDTH-1:0] sram_max_seq;
  logic [CELL_COUNT_WIDTH-1:0] sram_max_cell_count;
  logic hbm_min_valid;
  logic [DESC_W-1:0] hbm_min_desc;
  logic [RANK_WIDTH-1:0] hbm_min_rank;
  logic [SEQ_WIDTH-1:0] hbm_min_seq;
  logic [CELL_COUNT_WIDTH-1:0] hbm_min_cell_count;
  logic [BATCH_ID_W-1:0] hbm_min_batch_id;
  logic [BATCH_OFF_W-1:0] hbm_min_batch_offset;
  logic [15:0] sram_occupancy;
  logic [15:0] hbm_occupancy;

  hestia_port_bbq #(
    .RANK_WIDTH(RANK_WIDTH),
    .SEQ_WIDTH(SEQ_WIDTH),
    .CELL_COUNT_WIDTH(CELL_COUNT_WIDTH),
    .BATCH_SIZE(BATCH_SIZE),
    .BATCH_SLOTS(BATCH_SLOTS),
    .PACKET_SLOTS(PACKET_SLOTS),
    .BBQ_BITMAP_WIDTH(BBQ_BITMAP_WIDTH)
  ) dut (
    .clk(clk),
    .resetn(resetn),
    .cmd_valid(cmd_valid),
    .cmd_ready(cmd_ready),
    .cmd_op(cmd_op),
    .cmd_desc(cmd_desc),
    .cmd_rank(cmd_rank),
    .cmd_seq(cmd_seq),
    .cmd_cell_count(cmd_cell_count),
    .cmd_batch_id(cmd_batch_id),
    .cmd_batch_offset(cmd_batch_offset),
    .sram_min_valid(sram_min_valid),
    .sram_min_desc(sram_min_desc),
    .sram_min_rank(sram_min_rank),
    .sram_min_seq(sram_min_seq),
    .sram_min_cell_count(sram_min_cell_count),
    .sram_max_valid(sram_max_valid),
    .sram_max_desc(sram_max_desc),
    .sram_max_rank(sram_max_rank),
    .sram_max_seq(sram_max_seq),
    .sram_max_cell_count(sram_max_cell_count),
    .hbm_min_valid(hbm_min_valid),
    .hbm_min_desc(hbm_min_desc),
    .hbm_min_rank(hbm_min_rank),
    .hbm_min_seq(hbm_min_seq),
    .hbm_min_cell_count(hbm_min_cell_count),
    .hbm_min_batch_id(hbm_min_batch_id),
    .hbm_min_batch_offset(hbm_min_batch_offset),
    .sram_occupancy(sram_occupancy),
    .hbm_occupancy(hbm_occupancy)
  );

  task automatic tick(input int cycles);
    int ti;
    begin
      for (ti = 0; ti < cycles; ti = ti + 1) begin
        @(posedge clk);
      end
    end
  endtask

  task automatic issue(
    input mp_bbq_cmd_t op_i,
    input int desc_i,
    input int rank_i,
    input int seq_i,
    input int cells_i,
    input int batch_i,
    input int off_i
  );
    begin
      while (!cmd_ready) begin
        tick(1);
      end
      cmd_op = op_i;
      cmd_desc = desc_i[DESC_W-1:0];
      cmd_rank = rank_i[RANK_WIDTH-1:0];
      cmd_seq = seq_i[SEQ_WIDTH-1:0];
      cmd_cell_count = cells_i[CELL_COUNT_WIDTH-1:0];
      cmd_batch_id = batch_i[BATCH_ID_W-1:0];
      cmd_batch_offset = off_i[BATCH_OFF_W-1:0];
      cmd_valid = 1'b1;
      tick(1);
      cmd_valid = 1'b0;
      cmd_op = MP_BBQ_CMD_NONE;
      while (!cmd_ready) begin
        tick(1);
      end
      tick(1);
    end
  endtask

  task automatic expect_sram(input int min_desc_i, input int max_desc_i);
    begin
      if (!sram_min_valid || !sram_max_valid) begin
        $fatal(1, "Expected SRAM candidates, min_valid=%0d max_valid=%0d",
               sram_min_valid, sram_max_valid);
      end
      if (sram_min_desc !== min_desc_i[DESC_W-1:0] ||
          sram_max_desc !== max_desc_i[DESC_W-1:0]) begin
        $fatal(1, "SRAM candidate mismatch exp_min=%0d got=%0d exp_max=%0d got=%0d",
               min_desc_i, sram_min_desc, max_desc_i, sram_max_desc);
      end
    end
  endtask

  task automatic expect_hbm_min(input int desc_i, input int batch_i, input int off_i);
    begin
      if (!hbm_min_valid) begin
        $fatal(1, "Expected HBM candidate");
      end
      if (hbm_min_desc !== desc_i[DESC_W-1:0] ||
          hbm_min_batch_id !== batch_i[BATCH_ID_W-1:0] ||
          hbm_min_batch_offset !== off_i[BATCH_OFF_W-1:0]) begin
        $fatal(1, "HBM min mismatch exp_desc=%0d got=%0d exp_batch=%0d got=%0d exp_off=%0d got=%0d",
               desc_i, hbm_min_desc, batch_i, hbm_min_batch_id,
               off_i, hbm_min_batch_offset);
      end
    end
  endtask

  initial begin
    cmd_valid = 1'b0;
    cmd_op = MP_BBQ_CMD_NONE;
    cmd_desc = '0;
    cmd_rank = '0;
    cmd_seq = '0;
    cmd_cell_count = '0;
    cmd_batch_id = '0;
    cmd_batch_offset = '0;

    tick(3);
    resetn = 1'b1;
    while (!cmd_ready) begin
      tick(1);
    end

    issue(MP_BBQ_CMD_ADD_SRAM, 3, 5, 30, 2, 0, 0);
    issue(MP_BBQ_CMD_ADD_SRAM, 4, 2, 40, 1, 0, 0);
    issue(MP_BBQ_CMD_ADD_SRAM, 5, 9, 50, 3, 0, 0);
    expect_sram(4, 5);

    issue(MP_BBQ_CMD_ADD_HBM, 8, 7, 80, 1, 2, 1);
    issue(MP_BBQ_CMD_ADD_HBM, 9, 1, 90, 2, 3, 0);
    expect_hbm_min(9, 3, 0);

    issue(MP_BBQ_CMD_MOVE_SRAM_TO_HBM, 5, 9, 50, 3, 4, 0);
    expect_sram(4, 3);
    expect_hbm_min(9, 3, 0);

    issue(MP_BBQ_CMD_REMOVE_HBM, 9, 1, 90, 2, 3, 0);
    expect_hbm_min(8, 2, 1);

    issue(MP_BBQ_CMD_MOVE_HBM_TO_SRAM, 5, 9, 50, 3, 4, 0);
    expect_sram(4, 5);

    issue(MP_BBQ_CMD_ADD_SRAM, 6, 3, 60, 1, 0, 0);
    issue(MP_BBQ_CMD_ADD_SRAM, 7, 3, 70, 1, 0, 0);
    expect_sram(4, 5);

    issue(MP_BBQ_CMD_REMOVE_SRAM, 4, 2, 40, 1, 0, 0);
    if (sram_min_desc !== 6 || sram_max_desc !== 5) begin
      $fatal(1, "Same-rank FIFO/head-tail behavior mismatch min=%0d max=%0d",
             sram_min_desc, sram_max_desc);
    end

    if (sram_occupancy !== 16'd4 || hbm_occupancy !== 16'd1) begin
      $fatal(1, "Occupancy mismatch sram=%0d hbm=%0d", sram_occupancy, hbm_occupancy);
    end

    $display("PASS: hestia_port_bbq bitmap/list queue regression passed");
    $finish;
  end
endmodule
