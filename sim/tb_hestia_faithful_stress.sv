`timescale 1ns/1ps

module tb_hestia_faithful_stress;
  localparam int PORTS = 4;
  localparam int RANK_WIDTH = 8;
  localparam int SEQ_WIDTH = 16;
  localparam int PAYLOAD_WIDTH = 32;
  localparam int CELL_COUNT_WIDTH = 4;
  localparam int SRAM_CELLS = 12;
  localparam int BATCH_SIZE = 4;
  localparam int BATCH_SLOTS = 16;
  localparam int PACKET_SLOTS = 64;
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

  int seen_count [0:PORTS-1];
  logic [RANK_WIDTH-1:0] seen_rank [0:PORTS-1];
  logic [CELL_COUNT_WIDTH-1:0] seen_cells [0:PORTS-1];

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

  always_ff @(posedge clk) begin
    int mi;
    if (!resetn) begin
      for (mi = 0; mi < PORTS; mi = mi + 1) begin
        seen_count[mi] <= 0;
        seen_rank[mi] <= '0;
        seen_cells[mi] <= '0;
      end
    end else begin
      for (mi = 0; mi < PORTS; mi = mi + 1) begin
        if (m_pkt_valid[mi] && m_pkt_ready[mi]) begin
          seen_count[mi] <= seen_count[mi] + 1;
          seen_rank[mi] <= out_rank(mi);
          seen_cells[mi] <= out_cells(mi);
        end
      end
    end
  end

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
      s_pkt_payload = {16'h5100, seq_i};
      s_pkt_valid = 1'b1;
      while (!s_pkt_ready) begin
        @(posedge clk);
        guard = guard + 1;
        if (guard > 4000) begin
          $fatal(1, "Ingress timeout port=%0d rank=%0d cells=%0d state=%0d sram=%0d hbm=%0d",
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

  task automatic wait_seen(input int port_i, input int count_i);
    int guard;
    begin
      guard = 0;
      while (seen_count[port_i] < count_i) begin
        tick(1);
        guard = guard + 1;
        if (guard > 6000) begin
          $fatal(1, "Timeout waiting seen port=%0d count=%0d got=%0d state=%0d sram=%0d hbm=%0d",
                 port_i, count_i, seen_count[port_i], dut.state_q,
                 dbg_global_sram_occupancy, dbg_global_hbm_occupancy);
        end
      end
    end
  endtask

  task automatic wait_hbm_at_least(input int min_cells);
    int guard;
    begin
      guard = 0;
      while (dbg_global_hbm_occupancy < min_cells[15:0]) begin
        tick(1);
        guard = guard + 1;
        if (guard > 8000) begin
          $fatal(1, "Timeout waiting HBM >= %0d got=%0d state=%0d",
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
        if (guard > 8000) begin
          $fatal(1, "Timeout waiting HBM empty got=%0d state=%0d",
                 dbg_global_hbm_occupancy, dut.state_q);
        end
      end
    end
  endtask

  task automatic deq_one_expect(
    input int port_i,
    input int next_seen_i,
    input logic [RANK_WIDTH-1:0] rank_i,
    input logic [CELL_COUNT_WIDTH-1:0] cells_i
  );
    begin
      dequeue_enable[port_i] = 1'b1;
      wait_seen(port_i, next_seen_i);
      dequeue_enable[port_i] = 1'b0;
      if (seen_rank[port_i] !== rank_i || seen_cells[port_i] !== cells_i) begin
        $fatal(1, "Dequeue mismatch port=%0d exp_rank=%0d got_rank=%0d exp_cells=%0d got_cells=%0d",
               port_i, rank_i, seen_rank[port_i], cells_i, seen_cells[port_i]);
      end
      tick(1);
    end
  endtask

  initial begin
    int start_cycle;
    int end_cycle;
    int sram_dequeues;
    int hit_rate_x100;

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
    tick(8);
    start_cycle = $time / 4;

    send_pkt(2'd0, 8'd30, 16'd1, 4'd1);
    send_pkt(2'd1, 8'd20, 16'd2, 4'd1);
    send_pkt(2'd2, 8'd10, 16'd3, 4'd1);
    send_pkt(2'd3, 8'd40, 16'd4, 4'd1);

    m_pkt_ready = '0;
    dequeue_enable = '1;
    while (m_pkt_valid !== 4'b1111) begin
      tick(1);
      if (($time / 4) - start_cycle > 4000) begin
        $fatal(1, "Concurrent dequeue timeout valid=%b state=%0d", m_pkt_valid, dut.state_q);
      end
    end
    if (out_rank(0) !== 8'd30 || out_rank(1) !== 8'd20 ||
        out_rank(2) !== 8'd10 || out_rank(3) !== 8'd40) begin
      $fatal(1, "Concurrent port dequeue rank mismatch p0=%0d p1=%0d p2=%0d p3=%0d",
             out_rank(0), out_rank(1), out_rank(2), out_rank(3));
    end
    dequeue_enable = '0;
    m_pkt_ready = '1;
    wait_seen(0, 1);
    wait_seen(1, 1);
    wait_seen(2, 1);
    wait_seen(3, 1);

    send_pkt(2'd0, 8'd60, 16'd10, 4'd1);
    send_pkt(2'd1, 8'd15, 16'd11, 4'd1);
    send_pkt(2'd2, 8'd25, 16'd12, 4'd1);
    send_pkt(2'd3, 8'd35, 16'd13, 4'd1);

    m_pkt_ready = 4'b1101;
    dequeue_enable = '1;
    wait_seen(0, 2);
    wait_seen(2, 2);
    wait_seen(3, 2);
    if (!m_pkt_valid[1] || out_rank(1) !== 8'd15 || seen_count[1] !== 1) begin
      $fatal(1, "Backpressure did not hold port 1 output correctly valid=%0b rank=%0d seen=%0d",
             m_pkt_valid[1], out_rank(1), seen_count[1]);
    end
    m_pkt_ready[1] = 1'b1;
    wait_seen(1, 2);
    dequeue_enable = '0;

    cfg_swap_out_threshold = 16'd100;
    cfg_swap_in_threshold = 16'd0;
    send_pkt(2'd0, 8'd100, 16'd20, 4'd3);
    send_pkt(2'd0, 8'd90,  16'd21, 4'd2);
    send_pkt(2'd1, 8'd80,  16'd22, 4'd4);
    send_pkt(2'd2, 8'd70,  16'd23, 4'd3);
    if (dbg_global_sram_occupancy != 16'd12) begin
      $fatal(1, "Expected 12 SRAM cells before pressure phase, got %0d",
             dbg_global_sram_occupancy);
    end

    cfg_swap_out_threshold = 16'd4;
    wait_hbm_at_least(8);
    cfg_swap_out_threshold = 16'd100;

    deq_one_expect(0, 3, 8'd90, 4'd2);
    deq_one_expect(0, 4, 8'd100, 4'd3);
    if (stat_direct_hbm_dequeue == 32'd0) begin
      $fatal(1, "Expected at least one direct HBM/DDR dequeue");
    end

    cfg_swap_in_threshold = 16'd12;
    wait_hbm_empty();
    deq_one_expect(2, 3, 8'd70, 4'd3);
    deq_one_expect(1, 3, 8'd80, 4'd4);

    end_cycle = $time / 4;
    sram_dequeues = stat_dequeued - stat_direct_hbm_dequeue;
    hit_rate_x100 = (stat_dequeued == 0) ? 0 : ((sram_dequeues * 10000) / stat_dequeued);

    if (stat_drop != 32'd0) begin
      $fatal(1, "Unexpected drops during stress: %0d", stat_drop);
    end
    if (stat_swap_out < 32'd3 || stat_swap_in < 32'd2 || stat_batch_submit < 32'd2) begin
      $fatal(1, "Expected swap activity, swap_out=%0d swap_in=%0d batch_submit=%0d",
             stat_swap_out, stat_swap_in, stat_batch_submit);
    end
    if (dbg_global_sram_occupancy != 16'd0 || dbg_global_hbm_occupancy != 16'd0) begin
      $fatal(1, "Expected empty system at end, sram=%0d hbm=%0d",
             dbg_global_sram_occupancy, dbg_global_hbm_occupancy);
    end

    $display("MP_FAITHFUL_STRESS_STATS cycles=%0d generated=%0d dequeued=%0d sram_dequeue=%0d direct_hbm=%0d hit_rate_percent_x100=%0d swap_out=%0d swap_in=%0d drops=%0d batch_submit=%0d",
             end_cycle - start_cycle, stat_generated, stat_dequeued, sram_dequeues,
             stat_direct_hbm_dequeue, hit_rate_x100, stat_swap_out, stat_swap_in,
             stat_drop, stat_batch_submit);
    $display("PASS: Hestia faithful stress regression passed");
    $finish;
  end
endmodule
