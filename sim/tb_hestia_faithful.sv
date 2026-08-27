`timescale 1ns/1ps

module tb_hestia_faithful;
  localparam int PORTS = 4;
  localparam int RANK_WIDTH = 8;
  localparam int SEQ_WIDTH = 16;
  localparam int PAYLOAD_WIDTH = 32;
  localparam int CELL_COUNT_WIDTH = 4;
  localparam int SRAM_CELLS = 8;
  localparam int BATCH_SIZE = 4;
  localparam int BATCH_SLOTS = 8;
  localparam int PACKET_SLOTS = 32;
  localparam int PORT_W = 2;

  logic clk = 1'b0;
  logic resetn = 1'b0;
  logic enable = 1'b0;
  always #2 clk = ~clk;

  logic [15:0] cfg_swap_in_threshold;
  logic [15:0] cfg_swap_out_threshold;

  logic s_pkt_valid;
  logic s_pkt_ready;
  logic [PORT_W-1:0] s_pkt_port;
  logic [RANK_WIDTH-1:0] s_pkt_rank;
  logic [SEQ_WIDTH-1:0] s_pkt_seq;
  logic [CELL_COUNT_WIDTH-1:0] s_pkt_cell_count;
  logic [PAYLOAD_WIDTH-1:0] s_pkt_payload;

  logic [PORTS-1:0] dequeue_enable;
  logic [PORTS-1:0] m_pkt_valid;
  logic [PORTS-1:0] m_pkt_ready;
  logic [PORTS*RANK_WIDTH-1:0] m_pkt_rank;
  logic [PORTS*SEQ_WIDTH-1:0] m_pkt_seq;
  logic [PORTS*CELL_COUNT_WIDTH-1:0] m_pkt_cell_count;
  logic [PORTS*PAYLOAD_WIDTH-1:0] m_pkt_payload;

  logic [31:0] stat_generated;
  logic [31:0] stat_dequeued;
  logic [31:0] stat_sram_admit;
  logic [31:0] stat_hbm_admit;
  logic [31:0] stat_swap_out;
  logic [31:0] stat_swap_in;
  logic [31:0] stat_direct_hbm_dequeue;
  logic [31:0] stat_drop;
  logic [31:0] stat_batch_submit;
  logic [15:0] dbg_global_sram_occupancy;
  logic [15:0] dbg_global_hbm_occupancy;
  logic [PORTS*16-1:0] dbg_sram_count_flat;
  logic [PORTS*16-1:0] dbg_hbm_count_flat;
  logic [15:0] dbg_open_batch_cells;

  hestia_faithful_core #(
    .PORTS(PORTS),
    .RANK_WIDTH(RANK_WIDTH),
    .SEQ_WIDTH(SEQ_WIDTH),
    .PAYLOAD_WIDTH(PAYLOAD_WIDTH),
    .CELL_COUNT_WIDTH(CELL_COUNT_WIDTH),
    .SRAM_CELLS(SRAM_CELLS),
    .BATCH_SIZE(BATCH_SIZE),
    .BATCH_SLOTS(BATCH_SLOTS),
    .PACKET_SLOTS(PACKET_SLOTS)
  ) dut (
    .clk(clk),
    .resetn(resetn),
    .enable(enable),
    .cfg_swap_in_threshold(cfg_swap_in_threshold),
    .cfg_swap_out_threshold(cfg_swap_out_threshold),
    .s_pkt_valid(s_pkt_valid),
    .s_pkt_ready(s_pkt_ready),
    .s_pkt_port(s_pkt_port),
    .s_pkt_rank(s_pkt_rank),
    .s_pkt_seq(s_pkt_seq),
    .s_pkt_cell_count(s_pkt_cell_count),
    .s_pkt_payload(s_pkt_payload),
    .dequeue_enable(dequeue_enable),
    .m_pkt_valid(m_pkt_valid),
    .m_pkt_ready(m_pkt_ready),
    .m_pkt_rank(m_pkt_rank),
    .m_pkt_seq(m_pkt_seq),
    .m_pkt_cell_count(m_pkt_cell_count),
    .m_pkt_payload(m_pkt_payload),
    .stat_generated(stat_generated),
    .stat_dequeued(stat_dequeued),
    .stat_sram_admit(stat_sram_admit),
    .stat_hbm_admit(stat_hbm_admit),
    .stat_swap_out(stat_swap_out),
    .stat_swap_in(stat_swap_in),
    .stat_direct_hbm_dequeue(stat_direct_hbm_dequeue),
    .stat_drop(stat_drop),
    .stat_batch_submit(stat_batch_submit),
    .dbg_global_sram_occupancy(dbg_global_sram_occupancy),
    .dbg_global_hbm_occupancy(dbg_global_hbm_occupancy),
    .dbg_sram_count_flat(dbg_sram_count_flat),
    .dbg_hbm_count_flat(dbg_hbm_count_flat),
    .dbg_open_batch_cells(dbg_open_batch_cells)
  );

  function automatic logic [RANK_WIDTH-1:0] out_rank(input int port_i);
    begin
      out_rank = m_pkt_rank[port_i*RANK_WIDTH +: RANK_WIDTH];
    end
  endfunction

  function automatic logic [CELL_COUNT_WIDTH-1:0] out_cells(input int port_i);
    begin
      out_cells = m_pkt_cell_count[port_i*CELL_COUNT_WIDTH +: CELL_COUNT_WIDTH];
    end
  endfunction

  task automatic tick(input int cycles);
    int t;
    begin
      for (t = 0; t < cycles; t = t + 1) begin
        @(posedge clk);
      end
    end
  endtask

  task automatic send_pkt(
    input logic [PORT_W-1:0] port_i,
    input logic [RANK_WIDTH-1:0] rank_i,
    input logic [SEQ_WIDTH-1:0] seq_i,
    input logic [CELL_COUNT_WIDTH-1:0] cells_i
  );
    int guard;
    begin
      guard = 0;
      s_pkt_port = port_i;
      s_pkt_rank = rank_i;
      s_pkt_seq = seq_i;
      s_pkt_cell_count = cells_i;
      s_pkt_payload = {16'hcafe, seq_i};
      s_pkt_valid = 1'b1;
      while (!s_pkt_ready) begin
        @(posedge clk);
        guard = guard + 1;
        if (guard > 1000) begin
          $fatal(1, "Timeout waiting for ingress ready port=%0d rank=%0d cells=%0d state=%0d sram=%0d hbm=%0d",
                 port_i, rank_i, cells_i, dut.state_q, dbg_global_sram_occupancy,
                 dbg_global_hbm_occupancy);
        end
      end
      @(posedge clk);
      s_pkt_valid = 1'b0;
      s_pkt_port = '0;
      s_pkt_rank = '0;
      s_pkt_seq = '0;
      s_pkt_cell_count = '0;
      s_pkt_payload = '0;
      tick(1);
    end
  endtask

  task automatic deq_expect(
    input int port_i,
    input logic [RANK_WIDTH-1:0] rank_i,
    input logic [CELL_COUNT_WIDTH-1:0] cells_i
  );
    int guard;
    begin
      guard = 0;
      dequeue_enable[port_i] = 1'b1;
      while (!m_pkt_valid[port_i]) begin
        @(posedge clk);
        guard = guard + 1;
        if (guard > 2000) begin
          $fatal(1, "Timeout waiting for dequeue port=%0d rank=%0d state=%0d sram=%0d hbm=%0d",
                 port_i, rank_i, dut.state_q, dbg_global_sram_occupancy,
                 dbg_global_hbm_occupancy);
        end
      end
      if (out_rank(port_i) !== rank_i || out_cells(port_i) !== cells_i) begin
        $fatal(1, "Dequeue mismatch port=%0d exp_rank=%0d got_rank=%0d exp_cells=%0d got_cells=%0d",
               port_i, rank_i, out_rank(port_i), cells_i, out_cells(port_i));
      end
      dequeue_enable[port_i] = 1'b0;
      tick(1);
    end
  endtask

  task automatic wait_hbm_at_least(input int min_cells);
    int guard;
    begin
      guard = 0;
      while (dbg_global_hbm_occupancy < min_cells[15:0]) begin
        tick(1);
        guard = guard + 1;
        if (guard > 3000) begin
          $fatal(1, "Timeout waiting for HBM occupancy >= %0d, got %0d state=%0d",
                 min_cells, dbg_global_hbm_occupancy, dut.state_q);
        end
      end
    end
  endtask

  task automatic wait_hbm_empty;
    int guard;
    begin
      guard = 0;
      while (dbg_global_hbm_occupancy != 16'd0) begin
        tick(1);
        guard = guard + 1;
        if (guard > 5000) begin
          $fatal(1, "Timeout waiting for HBM empty, got %0d state=%0d",
                 dbg_global_hbm_occupancy, dut.state_q);
        end
      end
    end
  endtask

  initial begin
    cfg_swap_in_threshold = 16'd0;
    cfg_swap_out_threshold = 16'd100;
    s_pkt_valid = 1'b0;
    s_pkt_port = '0;
    s_pkt_rank = '0;
    s_pkt_seq = '0;
    s_pkt_cell_count = '0;
    s_pkt_payload = '0;
    dequeue_enable = '0;
    m_pkt_ready = '1;

    tick(5);
    resetn = 1'b1;
    enable = 1'b1;
    tick(5);

    // Markdown admission rule: when HBM/record is empty, the incoming packet
    // belongs in SRAM. If SRAM is full, the BM must first move a worse SRAM
    // packet to HBM instead of putting the new packet directly in HBM.
    send_pkt(2'd0, 8'd10, 16'd1, 4'd4);
    send_pkt(2'd1, 8'd20, 16'd2, 4'd4);
    send_pkt(2'd2, 8'd5,  16'd3, 4'd2);
    wait_hbm_at_least(4);
    if (stat_swap_out == 32'd0) begin
      $fatal(1, "Expected admission-forced swap-out when SRAM was full");
    end
    deq_expect(1, 8'd20, 4'd4);
    if (stat_direct_hbm_dequeue == 32'd0) begin
      $fatal(1, "Expected direct HBM dequeue for multi-cell packet");
    end
    deq_expect(2, 8'd5, 4'd2);
    deq_expect(0, 8'd10, 4'd4);
    if (dbg_global_sram_occupancy != 16'd0 || dbg_global_hbm_occupancy != 16'd0) begin
      $fatal(1, "Expected empty system after first phase, sram=%0d hbm=%0d",
             dbg_global_sram_occupancy, dbg_global_hbm_occupancy);
    end

    // Watermark swap-out must build shared batches by repeatedly selecting
    // the current max first-rank port and then that port's SRAM max rank.
    // The first selected packet has 3 cells, the next has 2, so a 4-cell batch
    // must be submitted partially instead of searching for a smaller filler.
    cfg_swap_out_threshold = 16'd100;
    cfg_swap_in_threshold = 16'd0;
    send_pkt(2'd0, 8'd30, 16'd10, 4'd3);
    send_pkt(2'd1, 8'd40, 16'd11, 4'd2);
    send_pkt(2'd2, 8'd50, 16'd12, 4'd2);
    if (dbg_global_sram_occupancy != 16'd7) begin
      $fatal(1, "Expected 7 SRAM cells before forced water swap-out, got %0d",
             dbg_global_sram_occupancy);
    end
    cfg_swap_out_threshold = 16'd1;
    wait_hbm_at_least(7);
    if (stat_batch_submit < 32'd2) begin
      $fatal(1, "Expected partial/full batch submissions, stat_batch_submit=%0d",
             stat_batch_submit);
    end

    cfg_swap_out_threshold = 16'd100;
    deq_expect(0, 8'd30, 4'd3);
    cfg_swap_in_threshold = 16'd8;
    wait_hbm_empty();
    if (stat_swap_in < 32'd2) begin
      $fatal(1, "Expected whole-batch swap-in of remaining packets, stat_swap_in=%0d",
             stat_swap_in);
    end
    deq_expect(1, 8'd40, 4'd2);
    deq_expect(2, 8'd50, 4'd2);

    if (stat_drop != 32'd0) begin
      $fatal(1, "Unexpected drops: %0d", stat_drop);
    end
    if (dbg_global_sram_occupancy != 16'd0 || dbg_global_hbm_occupancy != 16'd0) begin
      $fatal(1, "Expected empty system at end, sram=%0d hbm=%0d",
             dbg_global_sram_occupancy, dbg_global_hbm_occupancy);
    end

    $display("MP_FAITHFUL_STATS generated=%0d dequeued=%0d sram_admit=%0d hbm_admit=%0d swap_out=%0d swap_in=%0d direct_hbm=%0d drops=%0d batch_submit=%0d",
             stat_generated, stat_dequeued, stat_sram_admit, stat_hbm_admit,
             stat_swap_out, stat_swap_in, stat_direct_hbm_dequeue, stat_drop,
             stat_batch_submit);
    $display("PASS: Hestia faithful variable-cell markdown regression passed");
    $finish;
  end
endmodule
