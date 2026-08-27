`timescale 1ns/1ps

module tb_hestia_random;
  localparam int PORTS = 8;
  localparam int RANK_WIDTH = 8;
  localparam int SEQ_WIDTH = 16;
  localparam int PAYLOAD_WIDTH = 32;
  localparam int SRAM_CELLS = 32;
  localparam int BATCH_SIZE = 4;
  localparam int BATCH_SLOTS = 16;
  localparam int MODEL_DEPTH = 128;
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

  int model_rank [0:PORTS-1][0:MODEL_DEPTH-1];
  int model_count [0:PORTS-1];
  int seq_counter;

  hestia_core #(
    .PORTS(PORTS),
    .RANK_WIDTH(RANK_WIDTH),
    .SEQ_WIDTH(SEQ_WIDTH),
    .PAYLOAD_WIDTH(PAYLOAD_WIDTH),
    .SRAM_CELLS(SRAM_CELLS),
    .BATCH_SIZE(BATCH_SIZE),
    .BATCH_SLOTS(BATCH_SLOTS),
    .PORT_QUEUE_DEPTH(MODEL_DEPTH)
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

  task automatic clear_model;
    int p;
    int i;
    begin
      for (p = 0; p < PORTS; p = p + 1) begin
        model_count[p] = 0;
        for (i = 0; i < MODEL_DEPTH; i = i + 1) begin
          model_rank[p][i] = 0;
        end
      end
    end
  endtask

  task automatic model_add(input int port_i, input int rank_i);
    begin
      if (model_count[port_i] >= MODEL_DEPTH) begin
        $fatal(1, "Model overflow port=%0d", port_i);
      end
      model_rank[port_i][model_count[port_i]] = rank_i;
      model_count[port_i] = model_count[port_i] + 1;
    end
  endtask

  task automatic model_pop_min(input int port_i, output int rank_o);
    int i;
    int min_idx;
    begin
      if (model_count[port_i] == 0) begin
        $fatal(1, "Model underflow port=%0d", port_i);
      end
      min_idx = 0;
      for (i = 1; i < model_count[port_i]; i = i + 1) begin
        if (model_rank[port_i][i] < model_rank[port_i][min_idx]) begin
          min_idx = i;
        end
      end
      rank_o = model_rank[port_i][min_idx];
      for (i = min_idx; i < model_count[port_i]-1; i = i + 1) begin
        model_rank[port_i][i] = model_rank[port_i][i+1];
      end
      model_count[port_i] = model_count[port_i] - 1;
    end
  endtask

  task automatic check_count_invariants;
    int p;
    int sum_sram;
    int sum_hbm;
    begin
      sum_sram = 0;
      sum_hbm = 0;
      for (p = 0; p < PORTS; p = p + 1) begin
        sum_sram = sum_sram + dbg_sram_count_flat[p*16 +: 16];
        sum_hbm = sum_hbm + dbg_hbm_count_flat[p*16 +: 16];
      end
      if (sum_sram !== dbg_global_sram_occupancy) begin
        $fatal(1, "SRAM occupancy mismatch sum=%0d dbg=%0d", sum_sram, dbg_global_sram_occupancy);
      end
      if (sum_hbm !== dbg_global_hbm_occupancy) begin
        $fatal(1, "HBM occupancy mismatch sum=%0d dbg=%0d", sum_hbm, dbg_global_hbm_occupancy);
      end
      if ((dbg_global_sram_occupancy + dbg_global_hbm_occupancy) !==
          (stat_generated - stat_dequeued - stat_drop)) begin
        $fatal(1, "Live count mismatch live=%0d gen-deq-drop=%0d",
               dbg_global_sram_occupancy + dbg_global_hbm_occupancy,
               stat_generated - stat_dequeued - stat_drop);
      end
    end
  endtask

  task automatic send_pkt(
    input int port_i,
    input int rank_i
  );
    int guard;
    begin
      guard = 0;
      s_pkt_port = port_i[PORT_W-1:0];
      s_pkt_rank = rank_i[RANK_WIDTH-1:0];
      s_pkt_seq = seq_counter[SEQ_WIDTH-1:0];
      s_pkt_payload = {16'h55aa, seq_counter[15:0]};
      s_pkt_valid = 1'b1;
      while (!s_pkt_ready) begin
        @(posedge clk);
        guard = guard + 1;
        if (guard > 1000) begin
          $fatal(1, "Timeout waiting for s_pkt_ready port=%0d rank=%0d", port_i, rank_i);
        end
      end
      @(posedge clk);
      s_pkt_valid = 1'b0;
      s_pkt_port = '0;
      s_pkt_rank = '0;
      s_pkt_seq = '0;
      s_pkt_payload = '0;
      model_add(port_i, rank_i);
      seq_counter = seq_counter + 1;
      tick(1);
      check_count_invariants();
    end
  endtask

  task automatic deq_one_expected(input int port_i);
    int expected_rank;
    int guard;
    begin
      model_pop_min(port_i, expected_rank);
      guard = 0;
      m_pkt_ready[port_i] = 1'b0;
      dequeue_enable[port_i] = 1'b1;
      while (!m_pkt_valid[port_i]) begin
        @(posedge clk);
        guard = guard + 1;
        if (guard > 1000) begin
          $fatal(1, "Timeout waiting for dequeue port=%0d expected_rank=%0d", port_i, expected_rank);
        end
      end
      if (out_rank(port_i) !== expected_rank[RANK_WIDTH-1:0]) begin
        $fatal(1, "Rank mismatch port=%0d expected=%0d got=%0d", port_i, expected_rank, out_rank(port_i));
      end
      dequeue_enable[port_i] = 1'b0;
      m_pkt_ready[port_i] = 1'b1;
      tick(2);
      check_count_invariants();
    end
  endtask

  task automatic drain_all_model_packets;
    int p;
    int guard;
    int total_left;
    begin
      guard = 0;
      total_left = 0;
      for (p = 0; p < PORTS; p = p + 1) begin
        total_left = total_left + model_count[p];
      end
      while (total_left != 0) begin
        for (p = 0; p < PORTS; p = p + 1) begin
          if (model_count[p] != 0) begin
            deq_one_expected(p);
          end
        end
        total_left = 0;
        for (p = 0; p < PORTS; p = p + 1) begin
          total_left = total_left + model_count[p];
        end
        guard = guard + 1;
        if (guard > MODEL_DEPTH) begin
          $fatal(1, "Drain loop guard expired");
        end
      end
    end
  endtask

  task automatic wait_for_hbm_occupancy(input int min_hbm);
    int guard;
    begin
      guard = 0;
      while (dbg_global_hbm_occupancy < min_hbm[15:0]) begin
        tick(1);
        guard = guard + 1;
        if (guard > 2000) begin
          $fatal(1, "Timeout waiting for HBM occupancy >= %0d, got %0d", min_hbm, dbg_global_hbm_occupancy);
        end
      end
      check_count_invariants();
    end
  endtask

  task automatic wait_for_hbm_empty;
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
      check_count_invariants();
    end
  endtask

  initial begin
    int k;
    int port_v;
    int rank_v;
    int direct_before;
    int swapin_before;

    cfg_swap_in_threshold = 16'd0;
    cfg_swap_out_threshold = 16'd1000;
    s_pkt_valid = 1'b0;
    s_pkt_port = '0;
    s_pkt_rank = '0;
    s_pkt_seq = '0;
    s_pkt_payload = '0;
    dequeue_enable = '0;
    m_pkt_ready = '1;
    seq_counter = 1;
    clear_model();

    tick(5);
    resetn = 1'b1;
    enable = 1'b1;
    tick(5);

    // Scenario A: force SRAM pressure into HBM, then drain with swap-in disabled.
    // This should exercise direct HBM dequeue while preserving per-port rank order.
    cfg_swap_in_threshold = 16'd0;
    cfg_swap_out_threshold = 16'd6;
    for (k = 0; k < 40; k = k + 1) begin
      port_v = (k * 5 + 3) % PORTS;
      rank_v = ((k * 37) + (port_v * 11) + 19) % 251;
      send_pkt(port_v, rank_v);
    end
    wait_for_hbm_occupancy(8);
    cfg_swap_out_threshold = 16'd1000;
    direct_before = stat_direct_hbm_dequeue;
    drain_all_model_packets();
    if (stat_direct_hbm_dequeue == direct_before) begin
      $fatal(1, "Expected direct HBM dequeue activity in Scenario A");
    end
    if (stat_drop != 32'd0) begin
      $fatal(1, "Unexpected drops after Scenario A: %0d", stat_drop);
    end
    clear_model();

    // Scenario B: create shared HBM batches, enable swap-in, and then drain from SRAM.
    cfg_swap_in_threshold = 16'd0;
    cfg_swap_out_threshold = 16'd4;
    for (k = 0; k < 24; k = k + 1) begin
      port_v = (k * 3 + 1) % PORTS;
      rank_v = ((k * 29) + (port_v * 7) + 5) % 239;
      send_pkt(port_v, rank_v);
    end
    wait_for_hbm_occupancy(8);
    cfg_swap_out_threshold = 16'd1000;
    cfg_swap_in_threshold = 16'd40;
    swapin_before = stat_swap_in;
    wait_for_hbm_empty();
    if (stat_swap_in == swapin_before) begin
      $fatal(1, "Expected swap-in activity in Scenario B");
    end
    drain_all_model_packets();

    if (stat_drop != 32'd0) begin
      $fatal(1, "Unexpected drops: %0d", stat_drop);
    end
    if (dbg_global_sram_occupancy != 16'd0 || dbg_global_hbm_occupancy != 16'd0) begin
      $fatal(1, "Expected empty system, sram=%0d hbm=%0d",
             dbg_global_sram_occupancy, dbg_global_hbm_occupancy);
    end

    $display("MP_RANDOM_STATS generated=%0d dequeued=%0d sram_admit=%0d hbm_admit=%0d swap_out=%0d swap_in=%0d direct_hbm=%0d drop=%0d",
             stat_generated, stat_dequeued, stat_sram_admit, stat_hbm_admit,
             stat_swap_out, stat_swap_in, stat_direct_hbm_dequeue, stat_drop);
    $display("PASS: Hestia randomized shared-buffer regression passed");
    $finish;
  end
endmodule
