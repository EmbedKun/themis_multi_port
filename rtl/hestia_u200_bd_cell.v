`timescale 1ns/1ps

module hestia_u200_bd_cell #(
  parameter integer PORTS = 8,
  parameter integer RANK_WIDTH = 10,
  parameter integer SEQ_WIDTH = 32,
  parameter integer PAYLOAD_WIDTH = 64,
  parameter integer SRAM_CELLS = 64,
  parameter integer BATCH_SIZE = 4,
  parameter integer BATCH_SLOTS = 16,
  parameter integer PORT_QUEUE_DEPTH = 64,
  parameter integer PACKET_SLOTS = 512,
  parameter integer BBQ_BITMAP_WIDTH = (RANK_WIDTH <= 8) ? 16 : 32,
  parameter integer CELL_COUNT_WIDTH = 4,
  parameter integer MAX_CELL_COUNT = 4,
  parameter integer CELL_COUNT_MODE = 1,
  parameter integer MAX_PACKETS = 128,
  parameter integer GEN_PERIOD_CYCLES = 1,
  parameter integer DRAIN_AFTER_GENERATION_ONLY = 1,
  parameter integer DRAIN_START_PACKETS = 0,
  parameter integer DRAIN_PERIOD_CYCLES = 1,
  parameter integer RANK_DIST = 0,
  parameter integer HIGH_PRIORITY_PER1024 = 256,
  parameter integer SWAP_IN_THRESHOLD = 16,
  parameter integer SWAP_OUT_THRESHOLD = 48,
  parameter integer TEST_MODE = 0,
  parameter integer ALLOW_DROPS = 0
) (
  input  wire         clk,
  input  wire         resetn,
  input  wire         calib_done,

  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWID" *)
  output wire [3:0]   m_axi_awid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWADDR" *)
  output wire [33:0]  m_axi_awaddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWLEN" *)
  output wire [7:0]   m_axi_awlen,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWSIZE" *)
  output wire [2:0]   m_axi_awsize,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWBURST" *)
  output wire [1:0]   m_axi_awburst,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWLOCK" *)
  output wire         m_axi_awlock,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWCACHE" *)
  output wire [3:0]   m_axi_awcache,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWPROT" *)
  output wire [2:0]   m_axi_awprot,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWQOS" *)
  output wire [3:0]   m_axi_awqos,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWVALID" *)
  output wire         m_axi_awvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWREADY" *)
  input  wire         m_axi_awready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WDATA" *)
  output wire [511:0] m_axi_wdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WSTRB" *)
  output wire [63:0]  m_axi_wstrb,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WLAST" *)
  output wire         m_axi_wlast,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WVALID" *)
  output wire         m_axi_wvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WREADY" *)
  input  wire         m_axi_wready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BID" *)
  input  wire [3:0]   m_axi_bid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BRESP" *)
  input  wire [1:0]   m_axi_bresp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BVALID" *)
  input  wire         m_axi_bvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BREADY" *)
  output wire         m_axi_bready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARID" *)
  output wire [3:0]   m_axi_arid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARADDR" *)
  output wire [33:0]  m_axi_araddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARLEN" *)
  output wire [7:0]   m_axi_arlen,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARSIZE" *)
  output wire [2:0]   m_axi_arsize,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARBURST" *)
  output wire [1:0]   m_axi_arburst,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARLOCK" *)
  output wire         m_axi_arlock,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARCACHE" *)
  output wire [3:0]   m_axi_arcache,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARPROT" *)
  output wire [2:0]   m_axi_arprot,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARQOS" *)
  output wire [3:0]   m_axi_arqos,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARVALID" *)
  output wire         m_axi_arvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARREADY" *)
  input  wire         m_axi_arready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RID" *)
  input  wire [3:0]   m_axi_rid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RDATA" *)
  input  wire [511:0] m_axi_rdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RRESP" *)
  input  wire [1:0]   m_axi_rresp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RLAST" *)
  input  wire         m_axi_rlast,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RVALID" *)
  input  wire         m_axi_rvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RREADY" *)
  (* X_INTERFACE_PARAMETER = "PROTOCOL AXI4, DATA_WIDTH 512, ADDR_WIDTH 34, ID_WIDTH 4, HAS_BURST 1, HAS_LOCK 1, HAS_PROT 1, HAS_CACHE 1, HAS_QOS 1, SUPPORTS_NARROW_BURST 0, MAX_BURST_LENGTH 256" *)
  output wire         m_axi_rready,

  output wire [767:0] dbg_bus,
  output wire [511:0] dbg_light_bus,
  output wire [31:0]  dbg_generated,
  output wire [31:0]  dbg_dequeued,
  output wire [31:0]  dbg_sram_dequeue,
  output wire [31:0]  dbg_rank_order_errors,
  output wire [31:0]  dbg_run_cycles,
  output wire [31:0]  dbg_sram_admit,
  output wire [31:0]  dbg_ddr_admit,
  output wire [31:0]  dbg_swap_out,
  output wire [31:0]  dbg_swap_in,
  output wire [31:0]  dbg_direct_ddr_dequeue,
  output wire [31:0]  dbg_drop,
  output wire [31:0]  dbg_ddr_write_beats,
  output wire [31:0]  dbg_ddr_read_beats,
  output wire [31:0]  dbg_ddr_write_batches,
  output wire [31:0]  dbg_ddr_read_batches,
  output wire [15:0]  dbg_global_sram_occupancy,
  output wire [15:0]  dbg_global_ddr_occupancy,
  output wire [7:0]   dbg_ddr_state,
  output wire         dbg_ddr_wr_error,
  output wire         dbg_ddr_rd_error,
  output wire         calib_done_sync_dbg,
  output wire         done
);
  (* ASYNC_REG = "TRUE" *) reg calib_done_meta;
  (* ASYNC_REG = "TRUE" *) reg calib_done_sync;

  always @(posedge clk) begin
    if (!resetn) begin
      calib_done_meta <= 1'b0;
      calib_done_sync <= 1'b0;
    end else begin
      calib_done_meta <= calib_done;
      calib_done_sync <= calib_done_meta;
    end
  end

  wire core_resetn = resetn & calib_done_sync;
  assign calib_done_sync_dbg = calib_done_sync;

  hestia_u200_top #(
    .PORTS(PORTS),
    .RANK_WIDTH(RANK_WIDTH),
    .SEQ_WIDTH(SEQ_WIDTH),
    .PAYLOAD_WIDTH(PAYLOAD_WIDTH),
    .AXI_ADDR_WIDTH(34),
    .AXI_DATA_WIDTH(512),
    .AXI_ID_WIDTH(4),
    .CELL_COUNT_WIDTH(CELL_COUNT_WIDTH),
    .SRAM_CELLS(SRAM_CELLS),
    .BATCH_SIZE(BATCH_SIZE),
    .BATCH_SLOTS(BATCH_SLOTS),
    .PORT_QUEUE_DEPTH(PORT_QUEUE_DEPTH),
    .PACKET_SLOTS(PACKET_SLOTS),
    .BBQ_BITMAP_WIDTH(BBQ_BITMAP_WIDTH),
    .MAX_CELL_COUNT(MAX_CELL_COUNT),
    .CELL_COUNT_MODE(CELL_COUNT_MODE),
    .MAX_PACKETS(MAX_PACKETS),
    .GEN_PERIOD_CYCLES(GEN_PERIOD_CYCLES),
    .DRAIN_AFTER_GENERATION_ONLY(DRAIN_AFTER_GENERATION_ONLY),
    .DRAIN_START_PACKETS(DRAIN_START_PACKETS),
    .DRAIN_PERIOD_CYCLES(DRAIN_PERIOD_CYCLES),
    .RANK_DIST(RANK_DIST),
    .HIGH_PRIORITY_PER1024(HIGH_PRIORITY_PER1024),
    .SWAP_IN_THRESHOLD(SWAP_IN_THRESHOLD),
    .SWAP_OUT_THRESHOLD(SWAP_OUT_THRESHOLD),
    .TEST_MODE(TEST_MODE),
    .ALLOW_DROPS(ALLOW_DROPS)
  ) top_i (
    .clk(clk),
    .resetn(core_resetn),
    .enable(1'b1),
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
endmodule
