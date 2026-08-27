`timescale 1ns/1ps

`ifndef MP_STRESS_MAX_PACKETS
`define MP_STRESS_MAX_PACKETS 4096
`endif
`ifndef MP_STRESS_PORTS
`define MP_STRESS_PORTS 8
`endif
`ifndef MP_STRESS_RANK_WIDTH
`define MP_STRESS_RANK_WIDTH 10
`endif
`ifndef MP_STRESS_BBQ_BITMAP_WIDTH
`define MP_STRESS_BBQ_BITMAP_WIDTH 32
`endif
`ifndef MP_STRESS_SRAM_CELLS
`define MP_STRESS_SRAM_CELLS 32
`endif
`ifndef MP_STRESS_BATCH_SIZE
`define MP_STRESS_BATCH_SIZE 8
`endif
`ifndef MP_STRESS_BATCH_SLOTS
`define MP_STRESS_BATCH_SLOTS 128
`endif
`ifndef MP_STRESS_PORT_QUEUE_DEPTH
`define MP_STRESS_PORT_QUEUE_DEPTH 256
`endif
`ifndef MP_STRESS_PACKET_SLOTS
`define MP_STRESS_PACKET_SLOTS 512
`endif
`ifndef MP_STRESS_CELL_COUNT_WIDTH
`define MP_STRESS_CELL_COUNT_WIDTH 4
`endif
`ifndef MP_STRESS_MAX_CELL_COUNT
`define MP_STRESS_MAX_CELL_COUNT 4
`endif
`ifndef MP_STRESS_CELL_COUNT_MODE
`define MP_STRESS_CELL_COUNT_MODE 1
`endif
`ifndef MP_STRESS_GEN_PERIOD_CYCLES
`define MP_STRESS_GEN_PERIOD_CYCLES 1
`endif
`ifndef MP_STRESS_DRAIN_START_PACKETS
`define MP_STRESS_DRAIN_START_PACKETS 512
`endif
`ifndef MP_STRESS_DRAIN_PERIOD_CYCLES
`define MP_STRESS_DRAIN_PERIOD_CYCLES 3
`endif
`ifndef MP_STRESS_RANK_DIST
`define MP_STRESS_RANK_DIST 3
`endif
`ifndef MP_STRESS_SWAP_IN_THRESHOLD
`define MP_STRESS_SWAP_IN_THRESHOLD 16
`endif
`ifndef MP_STRESS_SWAP_OUT_THRESHOLD
`define MP_STRESS_SWAP_OUT_THRESHOLD 24
`endif
`ifndef MP_STRESS_TIMEOUT_CYCLES
`define MP_STRESS_TIMEOUT_CYCLES 3000000
`endif
`ifndef MP_STRESS_MIN_DDR_WRITE_BATCHES
`define MP_STRESS_MIN_DDR_WRITE_BATCHES 8
`endif
`ifndef MP_STRESS_MIN_DIRECT_DDR_DEQUEUE
`define MP_STRESS_MIN_DIRECT_DDR_DEQUEUE 8
`endif
`ifndef MP_STRESS_MIN_DDR_WRITE_BEATS
`define MP_STRESS_MIN_DDR_WRITE_BEATS 64
`endif
`ifndef MP_STRESS_MIN_DDR_READ_BEATS
`define MP_STRESS_MIN_DDR_READ_BEATS 64
`endif

module tb_hestia_u200_top_ddr_stress;
  localparam int PORTS = `MP_STRESS_PORTS;
  localparam int RANK_WIDTH = `MP_STRESS_RANK_WIDTH;
  localparam int BBQ_BITMAP_WIDTH = `MP_STRESS_BBQ_BITMAP_WIDTH;
  localparam int SEQ_WIDTH = 16;
  localparam int PAYLOAD_WIDTH = 32;
  localparam int AXI_ADDR_WIDTH = 20;
  localparam int AXI_DATA_WIDTH = 128;
  localparam int AXI_ID_WIDTH = 4;
  localparam int AXI_KEEP_WIDTH = AXI_DATA_WIDTH / 8;
  localparam int MAX_PACKETS = `MP_STRESS_MAX_PACKETS;
  localparam int SRAM_CELLS = `MP_STRESS_SRAM_CELLS;
  localparam int BATCH_SIZE = `MP_STRESS_BATCH_SIZE;
  localparam int BATCH_SLOTS = `MP_STRESS_BATCH_SLOTS;
  localparam int PORT_QUEUE_DEPTH = `MP_STRESS_PORT_QUEUE_DEPTH;
  localparam int PACKET_SLOTS = `MP_STRESS_PACKET_SLOTS;
  localparam int CELL_COUNT_WIDTH = `MP_STRESS_CELL_COUNT_WIDTH;
  localparam int MAX_CELL_COUNT = `MP_STRESS_MAX_CELL_COUNT;
  localparam int CELL_COUNT_MODE = `MP_STRESS_CELL_COUNT_MODE;
  localparam int GEN_PERIOD_CYCLES = `MP_STRESS_GEN_PERIOD_CYCLES;
  localparam int DRAIN_START_PACKETS = `MP_STRESS_DRAIN_START_PACKETS;
  localparam int DRAIN_PERIOD_CYCLES = `MP_STRESS_DRAIN_PERIOD_CYCLES;
  localparam int RANK_DIST = `MP_STRESS_RANK_DIST;
  localparam int SWAP_IN_THRESHOLD = `MP_STRESS_SWAP_IN_THRESHOLD;
  localparam int SWAP_OUT_THRESHOLD = `MP_STRESS_SWAP_OUT_THRESHOLD;
  localparam int TIMEOUT_CYCLES = `MP_STRESS_TIMEOUT_CYCLES;
  localparam int MIN_DDR_WRITE_BATCHES = `MP_STRESS_MIN_DDR_WRITE_BATCHES;
  localparam int MIN_DIRECT_DDR_DEQUEUE = `MP_STRESS_MIN_DIRECT_DDR_DEQUEUE;
  localparam int MIN_DDR_WRITE_BEATS = `MP_STRESS_MIN_DDR_WRITE_BEATS;
  localparam int MIN_DDR_READ_BEATS = `MP_STRESS_MIN_DDR_READ_BEATS;

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
    .SRAM_CELLS(SRAM_CELLS),
    .BATCH_SIZE(BATCH_SIZE),
    .BATCH_SLOTS(BATCH_SLOTS),
    .PORT_QUEUE_DEPTH(PORT_QUEUE_DEPTH),
    .PACKET_SLOTS(PACKET_SLOTS),
    .BBQ_BITMAP_WIDTH(BBQ_BITMAP_WIDTH),
    .CELL_COUNT_WIDTH(CELL_COUNT_WIDTH),
    .MAX_CELL_COUNT(MAX_CELL_COUNT),
    .CELL_COUNT_MODE(CELL_COUNT_MODE),
    .MAX_PACKETS(MAX_PACKETS),
    .GEN_PERIOD_CYCLES(GEN_PERIOD_CYCLES),
    .DRAIN_AFTER_GENERATION_ONLY(0),
    .DRAIN_START_PACKETS(DRAIN_START_PACKETS),
    .DRAIN_PERIOD_CYCLES(DRAIN_PERIOD_CYCLES),
    .RANK_DIST(RANK_DIST),
    .HIGH_PRIORITY_PER1024(256),
    .SWAP_IN_THRESHOLD(SWAP_IN_THRESHOLD),
    .SWAP_OUT_THRESHOLD(SWAP_OUT_THRESHOLD),
    .TEST_MODE(0),
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
    logic [31:0] progress_q;
    logic [31:0] progress_now;
    int stall_cycles;
    int cycle_count;

    repeat (10) @(posedge clk);
    resetn = 1'b1;
    enable = 1'b1;
    progress_q = 32'd0;
    stall_cycles = 0;
    cycle_count = 0;

    while (!done) begin
      @(posedge clk);
      cycle_count++;
      progress_now = dbg_generated ^ dbg_dequeued ^ dbg_ddr_write_beats ^
                     dbg_ddr_read_beats ^ {16'd0, dbg_global_sram_occupancy} ^
                     {16'd0, dbg_global_ddr_occupancy};
      if (progress_now != progress_q) begin
        progress_q = progress_now;
        stall_cycles = 0;
      end else begin
        stall_cycles++;
      end

      if ((cycle_count % 50000) == 0) begin
        $display("MP_U200_DDR_STRESS_PROGRESS cycles=%0d generated=%0d dequeued=%0d sram_occ=%0d ddr_occ=%0d wr_batches=%0d rd_batches=%0d direct=%0d swap_in=%0d",
                 cycle_count, dbg_generated, dbg_dequeued,
                 dbg_global_sram_occupancy, dbg_global_ddr_occupancy,
                 dbg_ddr_write_batches, dbg_ddr_read_batches,
                 dbg_direct_ddr_dequeue, dbg_swap_in);
      end

      if (stall_cycles > 100000) begin
        $fatal(1, "No forward progress for %0d cycles: generated=%0d dequeued=%0d drop=%0d sram_occ=%0d ddr_occ=%0d state=%02x",
               stall_cycles, dbg_generated, dbg_dequeued,
               dbg_drop, dbg_global_sram_occupancy, dbg_global_ddr_occupancy,
               dbg_ddr_state);
      end
      if (cycle_count > TIMEOUT_CYCLES) begin
        $fatal(1, "Timeout waiting for stress done generated=%0d dequeued=%0d sram_occ=%0d ddr_occ=%0d state=%02x",
               dbg_generated, dbg_dequeued,
               dbg_global_sram_occupancy, dbg_global_ddr_occupancy,
               dbg_ddr_state);
      end
    end

    repeat (5) @(posedge clk);
    if (dbg_generated != MAX_PACKETS || dbg_dequeued != MAX_PACKETS) begin
      $fatal(1, "Packet count mismatch generated=%0d dequeued=%0d expected=%0d",
             dbg_generated, dbg_dequeued, MAX_PACKETS);
    end
    if (dbg_drop != 32'd0 || dbg_rank_order_errors != 32'd0) begin
      $fatal(1, "Correctness failure drop=%0d rank_errors=%0d",
             dbg_drop, dbg_rank_order_errors);
    end
    if (dbg_ddr_wr_error || dbg_ddr_rd_error) begin
      $fatal(1, "DDR error flags wr=%0d rd=%0d state=%02x",
             dbg_ddr_wr_error, dbg_ddr_rd_error, dbg_ddr_state);
    end
    if (dbg_ddr_write_batches < MIN_DDR_WRITE_BATCHES ||
        dbg_direct_ddr_dequeue < MIN_DIRECT_DDR_DEQUEUE ||
        dbg_ddr_write_beats < MIN_DDR_WRITE_BEATS ||
        dbg_ddr_read_beats < MIN_DDR_READ_BEATS) begin
      $fatal(1, "Insufficient DDR stress wr_batches=%0d direct=%0d wr_beats=%0d rd_beats=%0d",
             dbg_ddr_write_batches, dbg_direct_ddr_dequeue,
             dbg_ddr_write_beats, dbg_ddr_read_beats);
    end
    if ((dbg_sram_dequeue + dbg_direct_ddr_dequeue) != dbg_dequeued) begin
      $fatal(1, "SRAM hit accounting mismatch sram_deq=%0d direct=%0d deq=%0d",
             dbg_sram_dequeue, dbg_direct_ddr_dequeue, dbg_dequeued);
    end

    hit_rate_x100 = (dbg_dequeued == 32'd0) ? 0 :
                    int'((dbg_sram_dequeue * 32'd10000) / dbg_dequeued);
    $display("MP_U200_DDR_STRESS generated=%0d dequeued=%0d sram_dequeue=%0d direct_ddr=%0d hit_rate_percent_x100=%0d sram_admit=%0d ddr_admit=%0d swap_out=%0d swap_in=%0d drop=%0d ddr_wr_beats=%0d ddr_rd_beats=%0d ddr_wr_batches=%0d ddr_rd_batches=%0d rank_errors=%0d run_cycles=%0d",
             dbg_generated, dbg_dequeued, dbg_sram_dequeue,
             dbg_direct_ddr_dequeue, hit_rate_x100, dbg_sram_admit, dbg_ddr_admit,
             dbg_swap_out, dbg_swap_in, dbg_drop,
             dbg_ddr_write_beats, dbg_ddr_read_beats,
             dbg_ddr_write_batches, dbg_ddr_read_batches,
             dbg_rank_order_errors, dbg_run_cycles);
    $display("PASS: Hestia U200 DDR stress sustained %0d packets with no drops, no rank errors, and active DDR traffic",
             MAX_PACKETS);
    $finish;
  end
endmodule
