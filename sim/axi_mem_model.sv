`timescale 1ns/1ps

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
