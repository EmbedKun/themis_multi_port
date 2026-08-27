`timescale 1ns/1ps

module tb_hestia_ddr;
  localparam int PORTS = 8;
  localparam int RANK_WIDTH = 8;
  localparam int SEQ_WIDTH = 16;
  localparam int PAYLOAD_WIDTH = 32;
  localparam int AXI_ADDR_WIDTH = 16;
  localparam int AXI_DATA_WIDTH = 128;
  localparam int AXI_ID_WIDTH = 4;
  localparam int AXI_KEEP_WIDTH = AXI_DATA_WIDTH / 8;
  localparam int SRAM_CELLS = 16;
  localparam int BATCH_SIZE = 4;
  localparam int BATCH_SLOTS = 8;
  localparam int MODEL_DEPTH = 64;
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

  logic [AXI_ID_WIDTH-1:0] m_axi_awid;
  logic [AXI_ADDR_WIDTH-1:0] m_axi_awaddr;
  logic [7:0] m_axi_awlen;
  logic [2:0] m_axi_awsize;
  logic [1:0] m_axi_awburst;
  logic m_axi_awlock;
  logic [3:0] m_axi_awcache;
  logic [2:0] m_axi_awprot;
  logic [3:0] m_axi_awqos;
  logic m_axi_awvalid;
  logic m_axi_awready;
  logic [AXI_DATA_WIDTH-1:0] m_axi_wdata;
  logic [AXI_KEEP_WIDTH-1:0] m_axi_wstrb;
  logic m_axi_wlast;
  logic m_axi_wvalid;
  logic m_axi_wready;
  logic [AXI_ID_WIDTH-1:0] m_axi_bid;
  logic [1:0] m_axi_bresp;
  logic m_axi_bvalid;
  logic m_axi_bready;
  logic [AXI_ID_WIDTH-1:0] m_axi_arid;
  logic [AXI_ADDR_WIDTH-1:0] m_axi_araddr;
  logic [7:0] m_axi_arlen;
  logic [2:0] m_axi_arsize;
  logic [1:0] m_axi_arburst;
  logic m_axi_arlock;
  logic [3:0] m_axi_arcache;
  logic [2:0] m_axi_arprot;
  logic [3:0] m_axi_arqos;
  logic m_axi_arvalid;
  logic m_axi_arready;
  logic [AXI_ID_WIDTH-1:0] m_axi_rid;
  logic [AXI_DATA_WIDTH-1:0] m_axi_rdata;
  logic [1:0] m_axi_rresp;
  logic m_axi_rlast;
  logic m_axi_rvalid;
  logic m_axi_rready;

  logic [31:0] stat_generated;
  logic [31:0] stat_dequeued;
  logic [31:0] stat_sram_admit;
  logic [31:0] stat_hbm_admit;
  logic [31:0] stat_swap_out;
  logic [31:0] stat_swap_in;
  logic [31:0] stat_direct_hbm_dequeue;
  logic [31:0] stat_drop;
  logic [31:0] stat_ddr_write_beats;
  logic [31:0] stat_ddr_read_beats;
  logic [31:0] stat_ddr_write_batches;
  logic [31:0] stat_ddr_read_batches;
  logic [15:0] dbg_global_sram_occupancy;
  logic [15:0] dbg_global_hbm_occupancy;
  logic [PORTS*16-1:0] dbg_sram_count_flat;
  logic [PORTS*16-1:0] dbg_hbm_count_flat;
  logic [7:0] dbg_ddr_state;
  logic dbg_ddr_wr_error;
  logic dbg_ddr_rd_error;

  int model_rank [0:PORTS-1][0:MODEL_DEPTH-1];
  int model_count [0:PORTS-1];
  int seq_counter;

  hestia_core_ddr #(
    .PORTS(PORTS),
    .RANK_WIDTH(RANK_WIDTH),
    .SEQ_WIDTH(SEQ_WIDTH),
    .PAYLOAD_WIDTH(PAYLOAD_WIDTH),
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH),
    .SRAM_CELLS(SRAM_CELLS),
    .BATCH_SIZE(BATCH_SIZE),
    .BATCH_SLOTS(BATCH_SLOTS),
    .PORT_QUEUE_DEPTH(MODEL_DEPTH),
    .ENABLE_DDR_META_CHECK(1'b1)
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
    .m_axi_awid(m_axi_awid),
    .m_axi_awaddr(m_axi_awaddr),
    .m_axi_awlen(m_axi_awlen),
    .m_axi_awsize(m_axi_awsize),
    .m_axi_awburst(m_axi_awburst),
    .m_axi_awlock(m_axi_awlock),
    .m_axi_awcache(m_axi_awcache),
    .m_axi_awprot(m_axi_awprot),
    .m_axi_awqos(m_axi_awqos),
    .m_axi_awvalid(m_axi_awvalid),
    .m_axi_awready(m_axi_awready),
    .m_axi_wdata(m_axi_wdata),
    .m_axi_wstrb(m_axi_wstrb),
    .m_axi_wlast(m_axi_wlast),
    .m_axi_wvalid(m_axi_wvalid),
    .m_axi_wready(m_axi_wready),
    .m_axi_bid(m_axi_bid),
    .m_axi_bresp(m_axi_bresp),
    .m_axi_bvalid(m_axi_bvalid),
    .m_axi_bready(m_axi_bready),
    .m_axi_arid(m_axi_arid),
    .m_axi_araddr(m_axi_araddr),
    .m_axi_arlen(m_axi_arlen),
    .m_axi_arsize(m_axi_arsize),
    .m_axi_arburst(m_axi_arburst),
    .m_axi_arlock(m_axi_arlock),
    .m_axi_arcache(m_axi_arcache),
    .m_axi_arprot(m_axi_arprot),
    .m_axi_arqos(m_axi_arqos),
    .m_axi_arvalid(m_axi_arvalid),
    .m_axi_arready(m_axi_arready),
    .m_axi_rid(m_axi_rid),
    .m_axi_rdata(m_axi_rdata),
    .m_axi_rresp(m_axi_rresp),
    .m_axi_rlast(m_axi_rlast),
    .m_axi_rvalid(m_axi_rvalid),
    .m_axi_rready(m_axi_rready),
    .stat_generated(stat_generated),
    .stat_dequeued(stat_dequeued),
    .stat_sram_admit(stat_sram_admit),
    .stat_hbm_admit(stat_hbm_admit),
    .stat_swap_out(stat_swap_out),
    .stat_swap_in(stat_swap_in),
    .stat_direct_hbm_dequeue(stat_direct_hbm_dequeue),
    .stat_drop(stat_drop),
    .stat_ddr_write_beats(stat_ddr_write_beats),
    .stat_ddr_read_beats(stat_ddr_read_beats),
    .stat_ddr_write_batches(stat_ddr_write_batches),
    .stat_ddr_read_batches(stat_ddr_read_batches),
    .dbg_global_sram_occupancy(dbg_global_sram_occupancy),
    .dbg_global_hbm_occupancy(dbg_global_hbm_occupancy),
    .dbg_sram_count_flat(dbg_sram_count_flat),
    .dbg_hbm_count_flat(dbg_hbm_count_flat),
    .dbg_ddr_state(dbg_ddr_state),
    .dbg_ddr_wr_error(dbg_ddr_wr_error),
    .dbg_ddr_rd_error(dbg_ddr_rd_error)
  );

  axi_mem_model #(
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH)
  ) mem_i (
    .clk(clk),
    .resetn(resetn),
    .s_axi_awid(m_axi_awid),
    .s_axi_awaddr(m_axi_awaddr),
    .s_axi_awlen(m_axi_awlen),
    .s_axi_awsize(m_axi_awsize),
    .s_axi_awburst(m_axi_awburst),
    .s_axi_awlock(m_axi_awlock),
    .s_axi_awcache(m_axi_awcache),
    .s_axi_awprot(m_axi_awprot),
    .s_axi_awqos(m_axi_awqos),
    .s_axi_awvalid(m_axi_awvalid),
    .s_axi_awready(m_axi_awready),
    .s_axi_wdata(m_axi_wdata),
    .s_axi_wstrb(m_axi_wstrb),
    .s_axi_wlast(m_axi_wlast),
    .s_axi_wvalid(m_axi_wvalid),
    .s_axi_wready(m_axi_wready),
    .s_axi_bid(m_axi_bid),
    .s_axi_bresp(m_axi_bresp),
    .s_axi_bvalid(m_axi_bvalid),
    .s_axi_bready(m_axi_bready),
    .s_axi_arid(m_axi_arid),
    .s_axi_araddr(m_axi_araddr),
    .s_axi_arlen(m_axi_arlen),
    .s_axi_arsize(m_axi_arsize),
    .s_axi_arburst(m_axi_arburst),
    .s_axi_arlock(m_axi_arlock),
    .s_axi_arcache(m_axi_arcache),
    .s_axi_arprot(m_axi_arprot),
    .s_axi_arqos(m_axi_arqos),
    .s_axi_arvalid(m_axi_arvalid),
    .s_axi_arready(m_axi_arready),
    .s_axi_rid(m_axi_rid),
    .s_axi_rdata(m_axi_rdata),
    .s_axi_rresp(m_axi_rresp),
    .s_axi_rlast(m_axi_rlast),
    .s_axi_rvalid(m_axi_rvalid),
    .s_axi_rready(m_axi_rready)
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
      model_rank[port_i][model_count[port_i]] = rank_i;
      model_count[port_i] = model_count[port_i] + 1;
    end
  endtask

  task automatic model_pop_min(input int port_i, output int rank_o);
    int i;
    int min_idx;
    begin
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
        $fatal(1, "SRAM count mismatch sum=%0d dbg=%0d", sum_sram, dbg_global_sram_occupancy);
      end
      if (sum_hbm !== dbg_global_hbm_occupancy) begin
        $fatal(1, "DDR count mismatch sum=%0d dbg=%0d", sum_hbm, dbg_global_hbm_occupancy);
      end
      if ((dbg_global_sram_occupancy + dbg_global_hbm_occupancy) !==
          (stat_generated - stat_dequeued - stat_drop)) begin
        $fatal(1, "Live count mismatch live=%0d expected=%0d",
               dbg_global_sram_occupancy + dbg_global_hbm_occupancy,
               stat_generated - stat_dequeued - stat_drop);
      end
      if (dbg_ddr_wr_error || dbg_ddr_rd_error) begin
        $fatal(1, "DDR error flags wr=%0d rd=%0d state=%02x",
               dbg_ddr_wr_error, dbg_ddr_rd_error, dbg_ddr_state);
      end
    end
  endtask

  task automatic send_pkt(input int port_i, input int rank_i);
    int guard;
    begin
      guard = 0;
      s_pkt_port = port_i[PORT_W-1:0];
      s_pkt_rank = rank_i[RANK_WIDTH-1:0];
      s_pkt_seq = seq_counter[SEQ_WIDTH-1:0];
      s_pkt_payload = {16'hcafe, seq_counter[15:0]};
      s_pkt_valid = 1'b1;
      while (!s_pkt_ready) begin
        @(posedge clk);
        guard = guard + 1;
        if (guard > 4000) begin
          $fatal(1, "Timeout waiting for ingress ready");
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
      tick(2);
      check_count_invariants();
    end
  endtask

  task automatic wait_ddr_write_batches(input int min_batches);
    int guard;
    begin
      guard = 0;
      while (stat_ddr_write_batches < min_batches[31:0]) begin
        tick(1);
        guard = guard + 1;
        if (guard > 12000) begin
          $fatal(1, "Timeout waiting for DDR writes, got %0d need %0d",
                 stat_ddr_write_batches, min_batches);
        end
      end
      check_count_invariants();
    end
  endtask

  task automatic wait_hbm_at_least(input int min_count);
    int guard;
    begin
      guard = 0;
      while (dbg_global_hbm_occupancy < min_count[15:0]) begin
        tick(1);
        guard = guard + 1;
        if (guard > 12000) begin
          $fatal(1, "Timeout waiting for HBM occupancy");
        end
      end
      check_count_invariants();
    end
  endtask

  task automatic wait_hbm_empty;
    int guard;
    begin
      guard = 0;
      while (dbg_global_hbm_occupancy != 16'd0) begin
        tick(1);
        guard = guard + 1;
        if (guard > 20000) begin
          $fatal(1, "Timeout waiting for HBM empty, got %0d", dbg_global_hbm_occupancy);
        end
      end
      check_count_invariants();
    end
  endtask

  task automatic deq_one_expected(input int port_i);
    int expected_rank;
    int guard;
    begin
      model_pop_min(port_i, expected_rank);
      guard = 0;
      dequeue_enable[port_i] = 1'b1;
      while (!m_pkt_valid[port_i]) begin
        @(posedge clk);
        guard = guard + 1;
        if (guard > 12000) begin
          $fatal(1, "Timeout waiting for dequeue port=%0d valid=%b ready=%b deq=%b sram=%0d hbm=%0d p_sram=%0d p_hbm=%0d stats deq=%0d direct=%0d rd_beats=%0d wr_batches=%0d state=%02x ar=%0d/%0d r=%0d/%0d pcmd=%0d/%0d hmin=%0d batch0 committed=%0d pending=%0d",
                 port_i, m_pkt_valid, m_pkt_ready, dequeue_enable,
                 dbg_global_sram_occupancy, dbg_global_hbm_occupancy,
                 dbg_sram_count_flat[port_i*16 +: 16],
                 dbg_hbm_count_flat[port_i*16 +: 16],
                 stat_dequeued, stat_direct_hbm_dequeue,
                 stat_ddr_read_beats, stat_ddr_write_batches, dbg_ddr_state,
                 m_axi_arvalid, m_axi_arready, m_axi_rvalid, m_axi_rready,
                 dut.port_cmd_valid[port_i], dut.port_cmd_ready[port_i],
                 dut.hbm_min_valid[port_i],
                 dut.batch_committed[0], dut.batch_write_pending[0]);
        end
      end
      if (out_rank(port_i) !== expected_rank[RANK_WIDTH-1:0]) begin
        $fatal(1, "Rank mismatch port=%0d expected=%0d got=%0d",
               port_i, expected_rank, out_rank(port_i));
      end
      dequeue_enable[port_i] = 1'b0;
      tick(2);
      check_count_invariants();
    end
  endtask

  task automatic drain_remaining;
    int p;
    int loops;
    int total_left;
    begin
      loops = 0;
      total_left = 1;
      while (total_left != 0) begin
        total_left = 0;
        for (p = 0; p < PORTS; p = p + 1) begin
          if (model_count[p] != 0) begin
            deq_one_expected(p);
          end
          total_left = total_left + model_count[p];
        end
        loops = loops + 1;
        if (loops > MODEL_DEPTH) begin
          $fatal(1, "Drain guard expired");
        end
      end
    end
  endtask

  initial begin
    int direct_before;
    int ddr_read_before;
    int swapin_before;
    cfg_swap_in_threshold = 16'd0;
    cfg_swap_out_threshold = 16'd0;
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

    send_pkt(0, 10);
    send_pkt(1, 11);
    send_pkt(2, 12);
    send_pkt(3, 13);
    wait_hbm_at_least(4);
    wait_ddr_write_batches(1);

    cfg_swap_out_threshold = 16'd1000;
    direct_before = stat_direct_hbm_dequeue;
    ddr_read_before = stat_ddr_read_beats;
    deq_one_expected(0);
    if (stat_direct_hbm_dequeue == direct_before) begin
      $fatal(1, "Expected direct DDR dequeue");
    end
    if (stat_ddr_read_beats == ddr_read_before) begin
      $fatal(1, "Expected direct dequeue to consume an AXI read beat");
    end

    send_pkt(4, 20);
    send_pkt(5, 21);
    send_pkt(6, 22);
    send_pkt(7, 23);
    wait_hbm_at_least(7);
    wait_ddr_write_batches(2);

    swapin_before = stat_swap_in;
    cfg_swap_in_threshold = 16'd16;
    wait_hbm_empty();
    if (stat_swap_in == swapin_before) begin
      $fatal(1, "Expected DDR whole-batch swap-in");
    end
    if (stat_ddr_read_batches == 32'd0) begin
      $fatal(1, "Expected at least one whole-batch DDR read");
    end

    drain_remaining();
    if (stat_drop != 32'd0) begin
      $fatal(1, "Unexpected drops: %0d", stat_drop);
    end
    if (dbg_global_sram_occupancy != 16'd0 || dbg_global_hbm_occupancy != 16'd0) begin
      $fatal(1, "System not empty sram=%0d hbm=%0d",
             dbg_global_sram_occupancy, dbg_global_hbm_occupancy);
    end

    $display("MP_DDR_STATS generated=%0d dequeued=%0d sram_admit=%0d hbm_admit=%0d swap_out=%0d swap_in=%0d direct_hbm=%0d drop=%0d ddr_wr_beats=%0d ddr_rd_beats=%0d ddr_wr_batches=%0d ddr_rd_batches=%0d",
             stat_generated, stat_dequeued, stat_sram_admit, stat_hbm_admit,
             stat_swap_out, stat_swap_in, stat_direct_hbm_dequeue, stat_drop,
             stat_ddr_write_beats, stat_ddr_read_beats,
             stat_ddr_write_batches, stat_ddr_read_batches);
    $display("PASS: Hestia DDR-backed shared batch regression passed");
    $finish;
  end
endmodule

module axi_mem_model #(
  parameter int AXI_ADDR_WIDTH = 16,
  parameter int AXI_DATA_WIDTH = 128,
  parameter int AXI_ID_WIDTH = 4,
  localparam int AXI_KEEP_WIDTH = AXI_DATA_WIDTH / 8,
  localparam int ADDR_SHIFT = $clog2(AXI_KEEP_WIDTH),
  localparam int MEM_DEPTH = 4096
) (
  input  logic                         clk,
  input  logic                         resetn,
  input  logic [AXI_ID_WIDTH-1:0]      s_axi_awid,
  input  logic [AXI_ADDR_WIDTH-1:0]    s_axi_awaddr,
  input  logic [7:0]                   s_axi_awlen,
  input  logic [2:0]                   s_axi_awsize,
  input  logic [1:0]                   s_axi_awburst,
  input  logic                         s_axi_awlock,
  input  logic [3:0]                   s_axi_awcache,
  input  logic [2:0]                   s_axi_awprot,
  input  logic [3:0]                   s_axi_awqos,
  input  logic                         s_axi_awvalid,
  output logic                         s_axi_awready,
  input  logic [AXI_DATA_WIDTH-1:0]    s_axi_wdata,
  input  logic [AXI_KEEP_WIDTH-1:0]    s_axi_wstrb,
  input  logic                         s_axi_wlast,
  input  logic                         s_axi_wvalid,
  output logic                         s_axi_wready,
  output logic [AXI_ID_WIDTH-1:0]      s_axi_bid,
  output logic [1:0]                   s_axi_bresp,
  output logic                         s_axi_bvalid,
  input  logic                         s_axi_bready,
  input  logic [AXI_ID_WIDTH-1:0]      s_axi_arid,
  input  logic [AXI_ADDR_WIDTH-1:0]    s_axi_araddr,
  input  logic [7:0]                   s_axi_arlen,
  input  logic [2:0]                   s_axi_arsize,
  input  logic [1:0]                   s_axi_arburst,
  input  logic                         s_axi_arlock,
  input  logic [3:0]                   s_axi_arcache,
  input  logic [2:0]                   s_axi_arprot,
  input  logic [3:0]                   s_axi_arqos,
  input  logic                         s_axi_arvalid,
  output logic                         s_axi_arready,
  output logic [AXI_ID_WIDTH-1:0]      s_axi_rid,
  output logic [AXI_DATA_WIDTH-1:0]    s_axi_rdata,
  output logic [1:0]                   s_axi_rresp,
  output logic                         s_axi_rlast,
  output logic                         s_axi_rvalid,
  input  logic                         s_axi_rready
);
  logic [AXI_DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];
  logic wr_active_q;
  logic [AXI_ADDR_WIDTH-1:0] wr_addr_q;
  logic [7:0] wr_len_q;
  logic [7:0] wr_beat_q;
  logic rd_active_q;
  logic [AXI_ADDR_WIDTH-1:0] rd_addr_q;
  logic [7:0] rd_len_q;
  logic [7:0] rd_beat_q;

  assign s_axi_awready = resetn && !wr_active_q && !s_axi_bvalid;
  assign s_axi_wready = resetn && wr_active_q;
  assign s_axi_arready = resetn && !rd_active_q && !s_axi_rvalid;
  assign s_axi_bid = '0;
  assign s_axi_bresp = 2'b00;
  assign s_axi_rid = '0;
  assign s_axi_rresp = 2'b00;

  function automatic int addr_index(input logic [AXI_ADDR_WIDTH-1:0] addr_i);
    begin
      addr_index = int'(addr_i >> ADDR_SHIFT);
    end
  endfunction

  always_ff @(posedge clk) begin
    if (!resetn) begin
      wr_active_q <= 1'b0;
      wr_addr_q <= '0;
      wr_len_q <= '0;
      wr_beat_q <= '0;
      s_axi_bvalid <= 1'b0;
      rd_active_q <= 1'b0;
      rd_addr_q <= '0;
      rd_len_q <= '0;
      rd_beat_q <= '0;
      s_axi_rvalid <= 1'b0;
      s_axi_rdata <= '0;
      s_axi_rlast <= 1'b0;
    end else begin
      if (s_axi_awvalid && s_axi_awready) begin
        wr_active_q <= 1'b1;
        wr_addr_q <= s_axi_awaddr;
        wr_len_q <= s_axi_awlen;
        wr_beat_q <= 8'd0;
      end

      if (s_axi_wvalid && s_axi_wready) begin
        mem[addr_index(wr_addr_q) + wr_beat_q] <= s_axi_wdata;
        if (s_axi_wlast || (wr_beat_q == wr_len_q)) begin
          wr_active_q <= 1'b0;
          s_axi_bvalid <= 1'b1;
        end else begin
          wr_beat_q <= wr_beat_q + 8'd1;
        end
      end

      if (s_axi_bvalid && s_axi_bready) begin
        s_axi_bvalid <= 1'b0;
      end

      if (s_axi_arvalid && s_axi_arready) begin
        rd_active_q <= 1'b1;
        rd_addr_q <= s_axi_araddr;
        rd_len_q <= s_axi_arlen;
        rd_beat_q <= 8'd0;
        s_axi_rvalid <= 1'b1;
        s_axi_rdata <= mem[addr_index(s_axi_araddr)];
        s_axi_rlast <= (s_axi_arlen == 8'd0);
      end else if (s_axi_rvalid && s_axi_rready) begin
        if (rd_beat_q == rd_len_q) begin
          s_axi_rvalid <= 1'b0;
          s_axi_rlast <= 1'b0;
          rd_active_q <= 1'b0;
        end else begin
          rd_beat_q <= rd_beat_q + 8'd1;
          s_axi_rdata <= mem[addr_index(rd_addr_q) + rd_beat_q + 1];
          s_axi_rlast <= ((rd_beat_q + 1) == rd_len_q);
        end
      end
    end
  end

  logic unused_inputs;
  assign unused_inputs = ^s_axi_awid ^ ^s_axi_awsize ^ ^s_axi_awburst ^
                         s_axi_awlock ^ ^s_axi_awcache ^ ^s_axi_awprot ^
                         ^s_axi_awqos ^ ^s_axi_wstrb ^ ^s_axi_arid ^
                         ^s_axi_arsize ^ ^s_axi_arburst ^ s_axi_arlock ^
                         ^s_axi_arcache ^ ^s_axi_arprot ^ ^s_axi_arqos;
endmodule
