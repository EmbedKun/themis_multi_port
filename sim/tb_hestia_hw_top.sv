`timescale 1ns/1ps

module tb_hestia_hw_top;
  logic clk = 1'b0;
  logic resetn = 1'b0;
  logic enable = 1'b0;

  logic done;
  logic [767:0] dbg_bus;
  logic [31:0] dbg_generated;
  logic [31:0] dbg_dequeued;
  logic [31:0] dbg_rank_order_errors;
  logic [31:0] dbg_run_cycles;

  always #2 clk = ~clk;

  hestia_hw_top #(
    .PORTS(8),
    .RANK_WIDTH(8),
    .SEQ_WIDTH(16),
    .PAYLOAD_WIDTH(32),
    .SRAM_CELLS(32),
    .BATCH_SIZE(4),
    .BATCH_SLOTS(16),
    .PORT_QUEUE_DEPTH(128),
    .MAX_PACKETS(64),
    .GEN_PERIOD_CYCLES(1),
    .DRAIN_AFTER_GENERATION_ONLY(1),
    .DRAIN_PERIOD_CYCLES(3),
    .RANK_DIST(1),
    .HIGH_PRIORITY_PER1024(384),
    .SWAP_IN_THRESHOLD(8),
    .SWAP_OUT_THRESHOLD(24)
  ) dut (
    .clk(clk),
    .resetn(resetn),
    .enable(enable),
    .done(done),
    .dbg_bus(dbg_bus),
    .dbg_generated(dbg_generated),
    .dbg_dequeued(dbg_dequeued),
    .dbg_rank_order_errors(dbg_rank_order_errors),
    .dbg_run_cycles(dbg_run_cycles)
  );

  initial begin
    repeat (10) @(posedge clk);
    resetn = 1'b1;
    enable = 1'b1;

    fork
      begin
        wait (done);
      end
      begin
        repeat (30000) @(posedge clk);
        $fatal(1, "Timeout waiting for hardware top done");
      end
    join_any
    disable fork;

    repeat (5) @(posedge clk);
    if (dbg_generated != 32'd64) begin
      $fatal(1, "Generated mismatch got=%0d", dbg_generated);
    end
    if (dbg_dequeued != dbg_generated) begin
      $fatal(1, "Dequeued mismatch gen=%0d deq=%0d", dbg_generated, dbg_dequeued);
    end
    if (dbg_rank_order_errors != 32'd0) begin
      $fatal(1, "Rank order errors=%0d", dbg_rank_order_errors);
    end

    $display("MP_HW_TOP_STATS generated=%0d dequeued=%0d rank_errors=%0d run_cycles=%0d",
             dbg_generated, dbg_dequeued, dbg_rank_order_errors, dbg_run_cycles);
    $display("PASS: Hestia hardware generator/checker wrapper completed");
    $finish;
  end
endmodule
