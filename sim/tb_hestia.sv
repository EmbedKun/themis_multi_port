`timescale 1ns/1ps

module tb_hestia;
  localparam int PORTS = 8;
  localparam int RANK_WIDTH = 8;
  localparam int SEQ_WIDTH = 16;
  localparam int PAYLOAD_WIDTH = 32;
  localparam int SRAM_CELLS = 8;
  localparam int BATCH_SIZE = 4;
  localparam int BATCH_SLOTS = 8;
  localparam int PORT_W = 3;

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
  logic [PAYLOAD_WIDTH-1:0] s_pkt_payload;

  logic [PORTS-1:0] dequeue_enable;
  logic [PORTS-1:0] m_pkt_valid;
  logic [PORTS-1:0] m_pkt_ready;
  logic [PORTS*RANK_WIDTH-1:0] m_pkt_rank;
  logic [PORTS*SEQ_WIDTH-1:0] m_pkt_seq;
  logic [PORTS*PAYLOAD_WIDTH-1:0] m_pkt_payload;

  logic [31:0] stat_generated;
  logic [31:0] stat_dequeued;
  logic [31:0] stat_sram_admit;
  logic [31:0] stat_hbm_admit;
  logic [31:0] stat_swap_out;
  logic [31:0] stat_swap_in;
  logic [31:0] stat_direct_hbm_dequeue;
  logic [31:0] stat_drop;
  logic [15:0] dbg_global_sram_occupancy;
  logic [15:0] dbg_global_hbm_occupancy;
  logic [PORTS*16-1:0] dbg_sram_count_flat;
  logic [PORTS*16-1:0] dbg_hbm_count_flat;

  hestia_core #(
    .PORTS(PORTS),
    .RANK_WIDTH(RANK_WIDTH),
    .SEQ_WIDTH(SEQ_WIDTH),
    .PAYLOAD_WIDTH(PAYLOAD_WIDTH),
    .SRAM_CELLS(SRAM_CELLS),
    .BATCH_SIZE(BATCH_SIZE),
    .BATCH_SLOTS(BATCH_SLOTS),
    .PORT_QUEUE_DEPTH(32)
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
    .s_pkt_payload(s_pkt_payload),
    .dequeue_enable(dequeue_enable),
    .m_pkt_valid(m_pkt_valid),
    .m_pkt_ready(m_pkt_ready),
    .m_pkt_rank(m_pkt_rank),
    .m_pkt_seq(m_pkt_seq),
    .m_pkt_payload(m_pkt_payload),
    .stat_generated(stat_generated),
    .stat_dequeued(stat_dequeued),
    .stat_sram_admit(stat_sram_admit),
    .stat_hbm_admit(stat_hbm_admit),
    .stat_swap_out(stat_swap_out),
    .stat_swap_in(stat_swap_in),
    .stat_direct_hbm_dequeue(stat_direct_hbm_dequeue),
    .stat_drop(stat_drop),
    .dbg_global_sram_occupancy(dbg_global_sram_occupancy),
    .dbg_global_hbm_occupancy(dbg_global_hbm_occupancy),
    .dbg_sram_count_flat(dbg_sram_count_flat),
    .dbg_hbm_count_flat(dbg_hbm_count_flat)
  );

  function automatic logic [RANK_WIDTH-1:0] out_rank(input int port_i);
    begin
      out_rank = m_pkt_rank[port_i*RANK_WIDTH +: RANK_WIDTH];
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
    input logic [SEQ_WIDTH-1:0] seq_i
  );
    int guard;
    begin
      guard = 0;
      s_pkt_port = port_i;
      s_pkt_rank = rank_i;
      s_pkt_seq = seq_i;
      s_pkt_payload = {16'hcafe, seq_i};
      s_pkt_valid = 1'b1;
      while (!s_pkt_ready) begin
        @(posedge clk);
        guard = guard + 1;
        if (guard > 200) begin
          $fatal(1, "Timeout waiting for s_pkt_ready port=%0d rank=%0d seq=%0d", port_i, rank_i, seq_i);
        end
      end
      @(posedge clk);
      s_pkt_valid = 1'b0;
      s_pkt_port = '0;
      s_pkt_rank = '0;
      s_pkt_seq = '0;
      s_pkt_payload = '0;
    end
  endtask

  task automatic deq_expect(
    input int port_i,
    input logic [RANK_WIDTH-1:0] expected_rank
  );
    int guard;
    begin
      guard = 0;
      m_pkt_ready[port_i] = 1'b0;
      dequeue_enable[port_i] = 1'b1;
      while (!m_pkt_valid[port_i]) begin
        @(posedge clk);
        guard = guard + 1;
        if (guard > 300) begin
          $fatal(1, "Timeout waiting for dequeue port=%0d expected_rank=%0d", port_i, expected_rank);
        end
      end
      if (out_rank(port_i) !== expected_rank) begin
        $display("DEBUG_DEQ port=%0d sram_valid=%0d sram_min=%0d sram_count=%0d hbm_valid=%0d hbm_min=%0d hbm_count=%0d deq_use_hbm=%0d state=%0d",
                 port_i,
                 dut.sram_min_valid[port_i], dut.sram_min_rank[port_i],
                 dbg_sram_count_flat[port_i*16 +: 16],
                 dut.hbm_min_valid[port_i], dut.hbm_min_rank[port_i],
                 dbg_hbm_count_flat[port_i*16 +: 16],
                 dut.deq_grant_valid_c && (dut.deq_grant_port_c == port_i[PORT_W-1:0]) &&
                 dut.deq_grant_use_hbm_c, dut.state_q);
        $fatal(1, "Rank mismatch port=%0d expected=%0d got=%0d", port_i, expected_rank, out_rank(port_i));
      end
      dequeue_enable[port_i] = 1'b0;
      m_pkt_ready[port_i] = 1'b1;
      tick(1);
    end
  endtask

  task automatic deq_all_ports_expect_base(input int base_rank);
    int guard;
    int p;
    logic [PORTS-1:0] seen;
    begin
      guard = 0;
      seen = '0;
      m_pkt_ready = '1;
      dequeue_enable = '1;
      while (seen != {PORTS{1'b1}}) begin
        @(posedge clk);
        #1;
        for (p = 0; p < PORTS; p = p + 1) begin
          if (m_pkt_valid[p] && m_pkt_ready[p]) begin
            if (out_rank(p) !== RANK_WIDTH'(base_rank + p)) begin
              $fatal(1, "All-port rank mismatch port=%0d expected=%0d got=%0d",
                     p, base_rank + p, out_rank(p));
            end
            seen[p] = 1'b1;
          end
        end
        guard = guard + 1;
        if (guard > 2000) begin
          $fatal(1, "Timeout waiting for all ports to dequeue, seen=%b valid=%b", seen, m_pkt_valid);
        end
      end
      dequeue_enable = '0;
      tick(1);
    end
  endtask

  task automatic wait_hbm_at_least(input int min_count);
    int guard;
    begin
      guard = 0;
      while (dbg_global_hbm_occupancy < min_count[15:0]) begin
        tick(1);
        guard = guard + 1;
        if (guard > 1000) begin
          $fatal(1, "Timeout waiting for HBM occupancy >= %0d, got %0d",
                 min_count, dbg_global_hbm_occupancy);
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
        if (guard > 3000) begin
          $fatal(1, "Timeout waiting for HBM empty, got %0d", dbg_global_hbm_occupancy);
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
    s_pkt_payload = '0;
    dequeue_enable = '0;
    m_pkt_ready = '1;

    tick(5);
    resetn = 1'b1;
    enable = 1'b1;
    tick(5);

    // Phase 1: force a packet into HBM, then prove a port can dequeue directly
    // from HBM when that port has no better SRAM packet.
    cfg_swap_in_threshold = 16'd0;
    cfg_swap_out_threshold = 16'd0;
    send_pkt(3'd0, 8'd0, 16'd1);
    wait_hbm_at_least(1);
    if (dbg_global_hbm_occupancy == 16'd0) begin
      $fatal(1, "Expected forced swap-out to create HBM occupancy");
    end
    deq_expect(0, 8'd0);
    if (stat_direct_hbm_dequeue == 32'd0) begin
      $fatal(1, "Expected at least one direct HBM dequeue");
    end

    // Phase 2: disable water migration and check per-port rank order from SRAM.
    cfg_swap_out_threshold = 16'd100;
    cfg_swap_in_threshold = 16'd0;
    send_pkt(3'd2, 8'd10, 16'd10);
    send_pkt(3'd2, 8'd3, 16'd11);
    send_pkt(3'd2, 8'd7, 16'd12);
    tick(5);
    deq_expect(2, 8'd3);
    deq_expect(2, 8'd7);
    deq_expect(2, 8'd10);

    // Phase 2b: markdown requires normal dequeue requests to remain per-port.
    // All ports request service concurrently; the shared store grants them with
    // a small RR arbiter while preserving each port's own rank order.
    for (int p = 0; p < PORTS; p = p + 1) begin
      send_pkt(p[PORT_W-1:0], RANK_WIDTH'(40 + p), SEQ_WIDTH'(40 + p));
    end
    deq_all_ports_expect_base(40);

    // Phase 3: force a shared batch in HBM, then enable swap-in and verify the
    // whole batch returns to SRAM before normal per-port dequeue.
    cfg_swap_out_threshold = 16'd0;
    cfg_swap_in_threshold = 16'd0;
    send_pkt(3'd3, 8'd20, 16'd20);
    send_pkt(3'd4, 8'd21, 16'd21);
    send_pkt(3'd3, 8'd22, 16'd22);
    send_pkt(3'd4, 8'd23, 16'd23);
    wait_hbm_at_least(4);
    if (dbg_global_hbm_occupancy < 16'd4) begin
      $fatal(1, "Expected at least four HBM cells before swap-in, got %0d", dbg_global_hbm_occupancy);
    end
    cfg_swap_out_threshold = 16'd100;
    cfg_swap_in_threshold = 16'd8;
    wait_hbm_empty();
    if (stat_swap_in < 32'd4) begin
      $fatal(1, "Expected whole-batch swap-in activity, stat_swap_in=%0d", stat_swap_in);
    end
    deq_expect(3, 8'd20);
    deq_expect(3, 8'd22);
    deq_expect(4, 8'd21);
    deq_expect(4, 8'd23);

    if (stat_drop != 32'd0) begin
      $fatal(1, "Unexpected drops: %0d", stat_drop);
    end

    $display("MP_STATS generated=%0d dequeued=%0d sram_admit=%0d hbm_admit=%0d swap_out=%0d swap_in=%0d direct_hbm=%0d drop=%0d sram_occ=%0d hbm_occ=%0d",
             stat_generated, stat_dequeued, stat_sram_admit, stat_hbm_admit,
             stat_swap_out, stat_swap_in, stat_direct_hbm_dequeue, stat_drop,
             dbg_global_sram_occupancy, dbg_global_hbm_occupancy);
    $display("PASS: Hestia shared buffer supports per-port rank queues, shared batches, and direct HBM dequeue");
    $finish;
  end
endmodule
