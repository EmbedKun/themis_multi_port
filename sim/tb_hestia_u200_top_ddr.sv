`timescale 1ns/1ps

module tb_hestia_u200_top_ddr;
  localparam int PORTS = 8;
  localparam int RANK_WIDTH = 8;
  localparam int SEQ_WIDTH = 16;
  localparam int PAYLOAD_WIDTH = 32;
  localparam int AXI_ADDR_WIDTH = 16;
  localparam int AXI_DATA_WIDTH = 128;
  localparam int AXI_ID_WIDTH = 4;
  localparam int AXI_KEEP_WIDTH = AXI_DATA_WIDTH / 8;
  localparam int MAX_PACKETS = 32;

  logic clk = 1'b0;
  logic resetn = 1'b0;
  logic enable = 1'b0;
  always #2 clk = ~clk;

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

  logic done;
  logic [767:0] dbg_bus;
  logic [511:0] dbg_light_bus;
  logic [31:0] dbg_generated;
  logic [31:0] dbg_dequeued;
  logic [31:0] dbg_sram_dequeue;
  logic [31:0] dbg_rank_order_errors;
  logic [31:0] dbg_run_cycles;
  logic [31:0] dbg_sram_admit;
  logic [31:0] dbg_ddr_admit;
  logic [31:0] dbg_swap_out;
  logic [31:0] dbg_swap_in;
  logic [31:0] dbg_direct_ddr_dequeue;
  logic [31:0] dbg_drop;
  logic [31:0] dbg_ddr_write_beats;
  logic [31:0] dbg_ddr_read_beats;
  logic [31:0] dbg_ddr_write_batches;
  logic [31:0] dbg_ddr_read_batches;
  logic [15:0] dbg_global_sram_occupancy;
  logic [15:0] dbg_global_ddr_occupancy;
  logic [7:0] dbg_ddr_state;
  logic dbg_ddr_wr_error;
  logic dbg_ddr_rd_error;

  hestia_u200_top #(
    .PORTS(PORTS),
    .RANK_WIDTH(RANK_WIDTH),
    .SEQ_WIDTH(SEQ_WIDTH),
    .PAYLOAD_WIDTH(PAYLOAD_WIDTH),
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH),
    .SRAM_CELLS(16),
    .BATCH_SIZE(8),
    .BATCH_SLOTS(16),
    .PORT_QUEUE_DEPTH(64),
    .PACKET_SLOTS(64),
    .MAX_CELL_COUNT(4),
    .CELL_COUNT_MODE(1),
    .MAX_PACKETS(MAX_PACKETS),
    .GEN_PERIOD_CYCLES(1),
    .DRAIN_AFTER_GENERATION_ONLY(1),
    .DRAIN_PERIOD_CYCLES(1),
    .RANK_DIST(0),
    .HIGH_PRIORITY_PER1024(256),
    .SWAP_IN_THRESHOLD(16),
    .SWAP_OUT_THRESHOLD(1000),
    .TEST_MODE(1),
    .ALLOW_DROPS(0)
  ) dut (
    .clk(clk),
    .resetn(resetn),
    .enable(enable),
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
    .done(done),
    .dbg_bus(dbg_bus),
    .dbg_light_bus(dbg_light_bus),
    .dbg_generated(dbg_generated),
    .dbg_dequeued(dbg_dequeued),
    .dbg_sram_dequeue(dbg_sram_dequeue),
    .dbg_rank_order_errors(dbg_rank_order_errors),
    .dbg_run_cycles(dbg_run_cycles),
    .dbg_sram_admit(dbg_sram_admit),
    .dbg_ddr_admit(dbg_ddr_admit),
    .dbg_swap_out(dbg_swap_out),
    .dbg_swap_in(dbg_swap_in),
    .dbg_direct_ddr_dequeue(dbg_direct_ddr_dequeue),
    .dbg_drop(dbg_drop),
    .dbg_ddr_write_beats(dbg_ddr_write_beats),
    .dbg_ddr_read_beats(dbg_ddr_read_beats),
    .dbg_ddr_write_batches(dbg_ddr_write_batches),
    .dbg_ddr_read_batches(dbg_ddr_read_batches),
    .dbg_global_sram_occupancy(dbg_global_sram_occupancy),
    .dbg_global_ddr_occupancy(dbg_global_ddr_occupancy),
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

  initial begin
    int hit_rate_x100;
    repeat (10) @(posedge clk);
    resetn = 1'b1;
    enable = 1'b1;

    fork
      begin
        wait (done);
      end
      begin
        repeat (50000) @(posedge clk);
        $fatal(1, "Timeout waiting for U200 DDR exercise top done generated=%0d dequeued=%0d sram_occ=%0d ddr_occ=%0d wr_batches=%0d rd_batches=%0d direct=%0d swap_in=%0d drop=%0d rank_errors=%0d state=%02x",
               dbg_generated, dbg_dequeued, dbg_global_sram_occupancy,
               dbg_global_ddr_occupancy, dbg_ddr_write_batches,
               dbg_ddr_read_batches, dbg_direct_ddr_dequeue, dbg_swap_in,
               dbg_drop, dbg_rank_order_errors, dbg_ddr_state);
      end
    join_any
    disable fork;

    repeat (5) @(posedge clk);
    if (dbg_generated != 32'(MAX_PACKETS) || dbg_dequeued != 32'(MAX_PACKETS)) begin
      $fatal(1, "Packet count mismatch generated=%0d dequeued=%0d",
             dbg_generated, dbg_dequeued);
    end
    if (dbg_drop != 32'd0 || dbg_rank_order_errors != 32'd0) begin
      $fatal(1, "Correctness failure drop=%0d rank_errors=%0d",
             dbg_drop, dbg_rank_order_errors);
    end
    if (dbg_ddr_wr_error || dbg_ddr_rd_error) begin
      $fatal(1, "DDR error flags wr=%0d rd=%0d state=%02x",
             dbg_ddr_wr_error, dbg_ddr_rd_error, dbg_ddr_state);
    end
    if (dbg_ddr_write_batches == 32'd0 || dbg_ddr_read_batches == 32'd0 ||
        dbg_direct_ddr_dequeue == 32'd0 || dbg_swap_in == 32'd0) begin
      $fatal(1, "DDR paths not covered wr_batches=%0d rd_batches=%0d direct=%0d swap_in=%0d",
             dbg_ddr_write_batches, dbg_ddr_read_batches,
             dbg_direct_ddr_dequeue, dbg_swap_in);
    end
    if ((dbg_sram_dequeue + dbg_direct_ddr_dequeue) != dbg_dequeued) begin
      $fatal(1, "SRAM hit accounting mismatch sram_deq=%0d direct=%0d deq=%0d",
             dbg_sram_dequeue, dbg_direct_ddr_dequeue, dbg_dequeued);
    end
    hit_rate_x100 = (dbg_dequeued == 32'd0) ? 0 :
                    int'((dbg_sram_dequeue * 32'd10000) / dbg_dequeued);

    $display("MP_U200_DDR_EXERCISE generated=%0d dequeued=%0d sram_dequeue=%0d direct_ddr=%0d hit_rate_percent_x100=%0d sram_admit=%0d ddr_admit=%0d swap_out=%0d swap_in=%0d drop=%0d ddr_wr_beats=%0d ddr_rd_beats=%0d ddr_wr_batches=%0d ddr_rd_batches=%0d rank_errors=%0d run_cycles=%0d",
             dbg_generated, dbg_dequeued, dbg_sram_dequeue,
             dbg_direct_ddr_dequeue, hit_rate_x100, dbg_sram_admit, dbg_ddr_admit,
             dbg_swap_out, dbg_swap_in, dbg_drop,
             dbg_ddr_write_beats, dbg_ddr_read_beats,
             dbg_ddr_write_batches, dbg_ddr_read_batches,
             dbg_rank_order_errors, dbg_run_cycles);
    $display("PASS: Hestia U200 DDR exercise top covers write-batch, whole-batch read, and direct DDR dequeue");
    $finish;
  end
endmodule
