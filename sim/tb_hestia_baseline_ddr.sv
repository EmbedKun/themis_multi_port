`timescale 1ns/1ps

`ifndef BASELINE_DDR_POLICY_MODE
`define BASELINE_DDR_POLICY_MODE 0
`endif
`ifndef BASELINE_DDR_POLICY_ALPHA_SHIFT
`define BASELINE_DDR_POLICY_ALPHA_SHIFT 0
`endif
`ifndef BASELINE_DDR_MAX_PACKETS
`define BASELINE_DDR_MAX_PACKETS 96
`endif

module tb_hestia_baseline_ddr;
  localparam int POLICY_MODE = `BASELINE_DDR_POLICY_MODE;
  localparam int POLICY_ALPHA_SHIFT = `BASELINE_DDR_POLICY_ALPHA_SHIFT;
  localparam int MAX_PACKETS = `BASELINE_DDR_MAX_PACKETS;
  localparam int PORTS = 4;
  localparam int RANK_WIDTH = 6;
  localparam int SEQ_WIDTH = 16;
  localparam int PAYLOAD_WIDTH = 32;
  localparam int CELL_COUNT_WIDTH = 4;
  localparam int AXI_ADDR_WIDTH = 18;
  localparam int AXI_DATA_WIDTH = 128;
  localparam int AXI_ID_WIDTH = 4;
  localparam int AXI_KEEP_WIDTH = AXI_DATA_WIDTH / 8;
  localparam int SRAM_CELLS = 8;
  localparam int BATCH_SIZE = 4;
  localparam int BATCH_SLOTS = 128;
  localparam int PACKET_SLOTS = 128;
  localparam int BBQ_BITMAP_WIDTH = 8;
  localparam int PORT_W = (PORTS <= 2) ? 1 : $clog2(PORTS);
  localparam logic [31:0] MAX_PACKETS_U32 = MAX_PACKETS;

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
  logic [31:0] stat_batch_submit;
  logic [31:0] stat_ddr_write_beats;
  logic [31:0] stat_ddr_read_beats;
  logic [31:0] stat_ddr_write_batches;
  logic [31:0] stat_ddr_read_batches;
  logic [15:0] dbg_global_sram_occupancy;
  logic [15:0] dbg_global_hbm_occupancy;
  logic [PORTS*16-1:0] dbg_sram_count_flat;
  logic [PORTS*16-1:0] dbg_hbm_count_flat;
  logic [15:0] dbg_open_batch_cells;
  logic [7:0] dbg_ddr_state;
  logic dbg_ddr_wr_error;
  logic dbg_ddr_rd_error;

  int seq_counter;
  int dequeued_seen;
  logic last_valid [0:PORTS-1];
  logic [RANK_WIDTH-1:0] last_rank [0:PORTS-1];
  logic [SEQ_WIDTH-1:0] last_seq [0:PORTS-1];

  hestia_core_ddr_bbq #(
    .PORTS(PORTS),
    .RANK_WIDTH(RANK_WIDTH),
    .SEQ_WIDTH(SEQ_WIDTH),
    .PAYLOAD_WIDTH(PAYLOAD_WIDTH),
    .CELL_COUNT_WIDTH(CELL_COUNT_WIDTH),
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH),
    .SRAM_CELLS(SRAM_CELLS),
    .BATCH_SIZE(BATCH_SIZE),
    .BATCH_SLOTS(BATCH_SLOTS),
    .PACKET_SLOTS(PACKET_SLOTS),
    .BBQ_BITMAP_WIDTH(BBQ_BITMAP_WIDTH),
    .POLICY_MODE(POLICY_MODE),
    .POLICY_ALPHA_SHIFT(POLICY_ALPHA_SHIFT),
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
    .s_pkt_cell_count(s_pkt_cell_count),
    .s_pkt_payload(s_pkt_payload),
    .dequeue_enable(dequeue_enable),
    .m_pkt_valid(m_pkt_valid),
    .m_pkt_ready(m_pkt_ready),
    .m_pkt_rank(m_pkt_rank),
    .m_pkt_seq(m_pkt_seq),
    .m_pkt_cell_count(m_pkt_cell_count),
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
    .stat_batch_submit(stat_batch_submit),
    .stat_ddr_write_beats(stat_ddr_write_beats),
    .stat_ddr_read_beats(stat_ddr_read_beats),
    .stat_ddr_write_batches(stat_ddr_write_batches),
    .stat_ddr_read_batches(stat_ddr_read_batches),
    .dbg_global_sram_occupancy(dbg_global_sram_occupancy),
    .dbg_global_hbm_occupancy(dbg_global_hbm_occupancy),
    .dbg_sram_count_flat(dbg_sram_count_flat),
    .dbg_hbm_count_flat(dbg_hbm_count_flat),
    .dbg_open_batch_cells(dbg_open_batch_cells),
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

  function automatic logic [SEQ_WIDTH-1:0] out_seq(input int port_i);
    begin
      out_seq = m_pkt_seq[port_i*SEQ_WIDTH +: SEQ_WIDTH];
    end
  endfunction

  function automatic logic rank_seq_less_than_last(input int port_i);
    begin
      rank_seq_less_than_last =
        (out_rank(port_i) < last_rank[port_i]) ||
        ((out_rank(port_i) == last_rank[port_i]) &&
         (out_seq(port_i) < last_seq[port_i]));
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

  task automatic send_pkt(input int port_i, input int rank_i, input int cells_i);
    int guard;
    begin
      guard = 0;
      s_pkt_port = port_i[PORT_W-1:0];
      s_pkt_rank = rank_i[RANK_WIDTH-1:0];
      s_pkt_seq = seq_counter[SEQ_WIDTH-1:0];
      s_pkt_cell_count = cells_i[CELL_COUNT_WIDTH-1:0];
      s_pkt_payload = {16'hbace, seq_counter[15:0]};
      s_pkt_valid = 1'b1;
      while (!s_pkt_ready) begin
        @(posedge clk);
        guard = guard + 1;
        if (guard > 12000) begin
          $fatal(1, "Timeout waiting for ingress ready policy=%0d state=%0d",
                 POLICY_MODE, dut.state_q);
        end
      end
      @(posedge clk);
      s_pkt_valid = 1'b0;
      s_pkt_port = '0;
      s_pkt_rank = '0;
      s_pkt_seq = '0;
      s_pkt_cell_count = '0;
      s_pkt_payload = '0;
      seq_counter = seq_counter + 1;
      tick(1);
    end
  endtask

  task automatic check_invariants;
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
        $fatal(1, "DDR occupancy mismatch sum=%0d dbg=%0d", sum_hbm, dbg_global_hbm_occupancy);
      end
      if (dbg_ddr_wr_error || dbg_ddr_rd_error) begin
        $fatal(1, "DDR error flags wr=%0d rd=%0d state=%02x",
               dbg_ddr_wr_error, dbg_ddr_rd_error, dbg_ddr_state);
      end
    end
  endtask

  always @(posedge clk) begin
    if (resetn) begin
      #1;
      for (int p = 0; p < PORTS; p = p + 1) begin
        if (m_pkt_valid[p] && m_pkt_ready[p]) begin
          if (last_valid[p] && rank_seq_less_than_last(p)) begin
            $fatal(1, "Rank order error policy=%0d port=%0d last=(%0d,%0d) got=(%0d,%0d)",
                   POLICY_MODE, p, last_rank[p], last_seq[p], out_rank(p), out_seq(p));
          end
          last_valid[p] = 1'b1;
          last_rank[p] = out_rank(p);
          last_seq[p] = out_seq(p);
          dequeued_seen = dequeued_seen + 1;
        end
      end
    end
  end

  initial begin
    cfg_swap_in_threshold = 16'd0;
    cfg_swap_out_threshold = 16'd65535;
    s_pkt_valid = 1'b0;
    s_pkt_port = '0;
    s_pkt_rank = '0;
    s_pkt_seq = '0;
    s_pkt_cell_count = '0;
    s_pkt_payload = '0;
    dequeue_enable = '0;
    m_pkt_ready = '1;
    seq_counter = 0;
    dequeued_seen = 0;
    for (int p = 0; p < PORTS; p = p + 1) begin
      last_valid[p] = 1'b0;
      last_rank[p] = '0;
      last_seq[p] = '0;
    end

    tick(8);
    resetn = 1'b1;
    enable = 1'b1;
    tick(20);

    for (int i = 0; i < MAX_PACKETS; i = i + 1) begin
      int port_v;
      int rank_v;
      int cells_v;
      port_v = (i < 24) ? 0 : ((i - 24) % PORTS);
      rank_v = ((MAX_PACKETS - i) + (port_v * 11) + ((i % 5) * 3)) % (1 << RANK_WIDTH);
      cells_v = 1 + (i % 3);
      send_pkt(port_v, rank_v, cells_v);
      if ((i % 8) == 7) begin
        check_invariants();
      end
    end

    tick(400);
    check_invariants();
    if (stat_drop != 32'd0) begin
      $fatal(1, "DDR-aware baseline should not drop under this capacity, drop=%0d", stat_drop);
    end
    if ((stat_hbm_admit + stat_swap_out) == 32'd0) begin
      $fatal(1, "Expected DDR fallback or SRAM-to-DDR migration");
    end
    if ((POLICY_MODE == 3) && (stat_swap_out == 32'd0)) begin
      $fatal(1, "Expected OBM push-out to move an SRAM packet into DDR");
    end

    dequeue_enable = '1;
    while (dequeued_seen < MAX_PACKETS) begin
      tick(1);
      if (stat_ddr_write_batches > 32'd0 && stat_direct_hbm_dequeue > 32'd0) begin
        check_invariants();
      end
      if ($time > 20000000) begin
        $fatal(1, "Timeout draining packets generated=%0d dequeued_seen=%0d stat_dequeued=%0d ddr_occ=%0d state=%0d",
               stat_generated, dequeued_seen, stat_dequeued, dbg_global_hbm_occupancy, dut.state_q);
      end
    end

    dequeue_enable = '0;
    tick(40);
    check_invariants();
    if (stat_generated != MAX_PACKETS_U32) begin
      $fatal(1, "Generated mismatch got=%0d expected=%0d", stat_generated, MAX_PACKETS);
    end
    if (stat_dequeued != MAX_PACKETS_U32) begin
      $fatal(1, "Dequeued mismatch got=%0d expected=%0d", stat_dequeued, MAX_PACKETS);
    end
    if (stat_direct_hbm_dequeue == 32'd0 ||
        stat_ddr_write_batches == 32'd0 ||
        stat_ddr_read_beats == 32'd0) begin
      $fatal(1, "Expected DDR read/write/direct-dequeue activity write_batches=%0d direct=%0d read_beats=%0d",
             stat_ddr_write_batches, stat_direct_hbm_dequeue, stat_ddr_read_beats);
    end

    $display("BASELINE_DDR_RESULT policy=%0d generated=%0d dequeued=%0d sram_admit=%0d ddr_admit=%0d swap_out=%0d swap_in=%0d direct_ddr=%0d drop=%0d ddr_write_batches=%0d ddr_read_batches=%0d ddr_write_beats=%0d ddr_read_beats=%0d sram_occ=%0d ddr_occ=%0d",
             POLICY_MODE, stat_generated, stat_dequeued, stat_sram_admit,
             stat_hbm_admit, stat_swap_out, stat_swap_in, stat_direct_hbm_dequeue,
             stat_drop, stat_ddr_write_batches, stat_ddr_read_batches,
             stat_ddr_write_beats, stat_ddr_read_beats,
             dbg_global_sram_occupancy, dbg_global_hbm_occupancy);
    $display("PASS: DDR-aware shared-buffer baseline policy=%0d preserves per-port rank order", POLICY_MODE);
    $finish;
  end

  logic unused_outputs;
  assign unused_outputs = ^m_pkt_cell_count ^ ^m_pkt_payload ^ ^stat_batch_submit;
endmodule
