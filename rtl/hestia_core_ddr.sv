`timescale 1ns/1ps

import hestia_pkg::*;

module hestia_core_ddr #(
  parameter int PORTS = 8,
  parameter int RANK_WIDTH = 10,
  parameter int SEQ_WIDTH = 32,
  parameter int PAYLOAD_WIDTH = 64,
  parameter int AXI_ADDR_WIDTH = 64,
  parameter int AXI_DATA_WIDTH = 512,
  parameter int AXI_ID_WIDTH = 4,
  parameter int SRAM_CELLS = 64,
  parameter int BATCH_SIZE = 4,
  parameter int BATCH_SLOTS = 16,
  parameter int PORT_QUEUE_DEPTH = 64,
  parameter bit ENABLE_DDR_META_CHECK = 1'b0,
  parameter logic [AXI_ADDR_WIDTH-1:0] DDR_BASE_ADDR = 64'h0,
  localparam int PORT_W = (PORTS <= 2) ? 1 : $clog2(PORTS),
  localparam int SRAM_SLOT_W = (SRAM_CELLS <= 2) ? 1 : $clog2(SRAM_CELLS),
  localparam int BATCH_ID_W = (BATCH_SLOTS <= 2) ? 1 : $clog2(BATCH_SLOTS),
  localparam int BATCH_OFF_W = (BATCH_SIZE <= 2) ? 1 : $clog2(BATCH_SIZE),
  localparam int PACKET_ID_WIDTH = SEQ_WIDTH,
  localparam int AXI_KEEP_WIDTH = AXI_DATA_WIDTH / 8
) (
  input  logic                             clk,
  input  logic                             resetn,
  input  logic                             enable,
  input  logic [15:0]                      cfg_swap_in_threshold,
  input  logic [15:0]                      cfg_swap_out_threshold,

  input  logic                             s_pkt_valid,
  output logic                             s_pkt_ready,
  input  logic [PORT_W-1:0]                s_pkt_port,
  input  logic [RANK_WIDTH-1:0]            s_pkt_rank,
  input  logic [SEQ_WIDTH-1:0]             s_pkt_seq,
  input  logic [PAYLOAD_WIDTH-1:0]         s_pkt_payload,

  input  logic [PORTS-1:0]                 dequeue_enable,
  output logic [PORTS-1:0]                 m_pkt_valid,
  input  logic [PORTS-1:0]                 m_pkt_ready,
  output logic [PORTS*RANK_WIDTH-1:0]      m_pkt_rank,
  output logic [PORTS*SEQ_WIDTH-1:0]       m_pkt_seq,
  output logic [PORTS*PAYLOAD_WIDTH-1:0]   m_pkt_payload,

  output logic [AXI_ID_WIDTH-1:0]           m_axi_awid,
  output logic [AXI_ADDR_WIDTH-1:0]         m_axi_awaddr,
  output logic [7:0]                        m_axi_awlen,
  output logic [2:0]                        m_axi_awsize,
  output logic [1:0]                        m_axi_awburst,
  output logic                              m_axi_awlock,
  output logic [3:0]                        m_axi_awcache,
  output logic [2:0]                        m_axi_awprot,
  output logic [3:0]                        m_axi_awqos,
  output logic                              m_axi_awvalid,
  input  logic                              m_axi_awready,
  output logic [AXI_DATA_WIDTH-1:0]         m_axi_wdata,
  output logic [AXI_KEEP_WIDTH-1:0]         m_axi_wstrb,
  output logic                              m_axi_wlast,
  output logic                              m_axi_wvalid,
  input  logic                              m_axi_wready,
  input  logic [AXI_ID_WIDTH-1:0]           m_axi_bid,
  input  logic [1:0]                        m_axi_bresp,
  input  logic                              m_axi_bvalid,
  output logic                              m_axi_bready,
  output logic [AXI_ID_WIDTH-1:0]           m_axi_arid,
  output logic [AXI_ADDR_WIDTH-1:0]         m_axi_araddr,
  output logic [7:0]                        m_axi_arlen,
  output logic [2:0]                        m_axi_arsize,
  output logic [1:0]                        m_axi_arburst,
  output logic                              m_axi_arlock,
  output logic [3:0]                        m_axi_arcache,
  output logic [2:0]                        m_axi_arprot,
  output logic [3:0]                        m_axi_arqos,
  output logic                              m_axi_arvalid,
  input  logic                              m_axi_arready,
  input  logic [AXI_ID_WIDTH-1:0]           m_axi_rid,
  input  logic [AXI_DATA_WIDTH-1:0]         m_axi_rdata,
  input  logic [1:0]                        m_axi_rresp,
  input  logic                              m_axi_rlast,
  input  logic                              m_axi_rvalid,
  output logic                              m_axi_rready,

  output logic [31:0]                      stat_generated,
  output logic [31:0]                      stat_dequeued,
  output logic [31:0]                      stat_sram_admit,
  output logic [31:0]                      stat_hbm_admit,
  output logic [31:0]                      stat_swap_out,
  output logic [31:0]                      stat_swap_in,
  output logic [31:0]                      stat_direct_hbm_dequeue,
  output logic [31:0]                      stat_drop,
  output logic [31:0]                      stat_ddr_write_beats,
  output logic [31:0]                      stat_ddr_read_beats,
  output logic [31:0]                      stat_ddr_write_batches,
  output logic [31:0]                      stat_ddr_read_batches,
  output logic [15:0]                      dbg_global_sram_occupancy,
  output logic [15:0]                      dbg_global_hbm_occupancy,
  output logic [PORTS*16-1:0]              dbg_sram_count_flat,
  output logic [PORTS*16-1:0]              dbg_hbm_count_flat,
  output logic [7:0]                       dbg_ddr_state,
  output logic                             dbg_ddr_wr_error,
  output logic                             dbg_ddr_rd_error
);
  typedef enum logic [3:0] {
    ST_SELECT,
    ST_SELECT_SCAN,
    ST_IDLE,
    ST_DEQ_EXEC,
    ST_DEQ_DDR_ADDR,
    ST_DEQ_DDR_DATA,
    ST_EXEC,
    ST_APPEND_EXEC,
    ST_REPLACE_ADD_SRAM,
    ST_SWAPIN_WAIT,
    ST_SWAPIN_SCAN,
    ST_SWAPIN_DDR_ADDR,
    ST_SWAPIN_DDR_DATA
  } state_t;

  typedef enum logic [1:0] {
    WR_IDLE,
    WR_ADDR,
    WR_DATA,
    WR_RESP
  } wr_state_t;

  typedef enum logic [2:0] {
    ACT_NONE,
    ACT_SWAP_OUT,
    ACT_START_SWAP_IN,
    ACT_INGRESS
  } action_t;

  state_t state_q;
  action_t action_q;

  logic [PORT_W-1:0] action_port_q;
  logic action_choose_replace_q;
  logic action_choose_hbm_q;
  logic [RANK_WIDTH-1:0] action_rank_q;
  logic [SEQ_WIDTH-1:0] action_seq_q;
  logic [PAYLOAD_WIDTH-1:0] action_payload_q;
  logic [BATCH_ID_W-1:0] action_batch_q;
  logic [15:0] global_sram_q;
  logic [15:0] global_hbm_q;
  logic record_valid_q;
  logic [PORT_W-1:0] record_port_q;
  logic [15:0] record_first_rank_q;
  logic [RANK_WIDTH-1:0] record_second_rank_q;
  logic [BATCH_ID_W-1:0] record_batch_q;
  logic swapout_valid_q;
  logic [PORT_W-1:0] swapout_port_q;
  logic [PORT_W:0] select_idx_q;

  logic [RANK_WIDTH-1:0] port_cmd_rank [0:PORTS-1];
  logic [SEQ_WIDTH-1:0] port_cmd_packet_id [0:PORTS-1];
  logic [SRAM_SLOT_W-1:0] port_cmd_sram_slot [0:PORTS-1];
  logic [BATCH_ID_W-1:0] port_cmd_batch_id [0:PORTS-1];
  logic [BATCH_OFF_W-1:0] port_cmd_batch_offset [0:PORTS-1];
  logic [PORTS-1:0] port_cmd_valid;
  mp_port_cmd_t port_cmd_op [0:PORTS-1];
  logic [PORTS-1:0] port_cmd_ready;
  logic [PORTS-1:0] port_idle_ready;
  logic [RANK_WIDTH-1:0] out_rank_q [0:PORTS-1];
  logic [SEQ_WIDTH-1:0] out_seq_q [0:PORTS-1];
  logic [PAYLOAD_WIDTH-1:0] out_payload_q [0:PORTS-1];
  logic [PORTS-1:0] out_from_hbm_q;

  logic [PORTS-1:0] sram_min_valid;
  logic [RANK_WIDTH-1:0] sram_min_rank [0:PORTS-1];
  logic [SEQ_WIDTH-1:0] sram_min_packet_id [0:PORTS-1];
  logic [SRAM_SLOT_W-1:0] sram_min_slot [0:PORTS-1];

  logic [PORTS-1:0] sram_max_valid;
  logic [RANK_WIDTH-1:0] sram_max_rank [0:PORTS-1];
  logic [SEQ_WIDTH-1:0] sram_max_packet_id [0:PORTS-1];
  logic [SRAM_SLOT_W-1:0] sram_max_slot [0:PORTS-1];

  logic [PORTS-1:0] hbm_min_valid;
  logic [RANK_WIDTH-1:0] hbm_min_rank [0:PORTS-1];
  logic [SEQ_WIDTH-1:0] hbm_min_packet_id [0:PORTS-1];
  logic [BATCH_ID_W-1:0] hbm_min_batch_id [0:PORTS-1];
  logic [BATCH_OFF_W-1:0] hbm_min_batch_offset [0:PORTS-1];
  logic [15:0] port_dbg_sram_entries [0:PORTS-1];
  logic [15:0] port_dbg_hbm_entries [0:PORTS-1];

  logic [15:0] total_count_q [0:PORTS-1];
  logic [15:0] sram_count_q [0:PORTS-1];
  logic [15:0] hbm_count_q [0:PORTS-1];

  logic sram_valid [0:SRAM_CELLS-1];
  (* ram_style = "distributed" *) logic [PORT_W-1:0] sram_port [0:SRAM_CELLS-1];
  (* ram_style = "distributed" *) logic [RANK_WIDTH-1:0] sram_rank [0:SRAM_CELLS-1];
  (* ram_style = "distributed" *) logic [SEQ_WIDTH-1:0] sram_seq [0:SRAM_CELLS-1];
  (* ram_style = "distributed" *) logic [PAYLOAD_WIDTH-1:0] sram_payload [0:SRAM_CELLS-1];
  logic [SRAM_SLOT_W-1:0] sram_free_list [0:SRAM_CELLS-1];
  logic [SRAM_SLOT_W-1:0] sram_free_rd_q;
  logic [SRAM_SLOT_W-1:0] sram_free_wr_q;
  logic [15:0] sram_free_count_q;
  logic sram_wr_valid_q;
  logic [SRAM_SLOT_W-1:0] sram_wr_slot_q;
  logic [PORT_W-1:0] sram_wr_port_q;
  logic [RANK_WIDTH-1:0] sram_wr_rank_q;
  logic [SEQ_WIDTH-1:0] sram_wr_seq_q;
  logic [PAYLOAD_WIDTH-1:0] sram_wr_payload_q;

  logic batch_entry_valid [0:BATCH_SLOTS-1][0:BATCH_SIZE-1];
  (* ram_style = "distributed" *) logic [PORT_W-1:0] batch_port [0:BATCH_SLOTS-1][0:BATCH_SIZE-1];
  (* ram_style = "distributed" *) logic [RANK_WIDTH-1:0] batch_rank [0:BATCH_SLOTS-1][0:BATCH_SIZE-1];
  (* ram_style = "distributed" *) logic [SEQ_WIDTH-1:0] batch_seq [0:BATCH_SLOTS-1][0:BATCH_SIZE-1];
  (* ram_style = "distributed" *) logic [PAYLOAD_WIDTH-1:0] batch_payload [0:BATCH_SLOTS-1][0:BATCH_SIZE-1];
  logic batch_committed [0:BATCH_SLOTS-1];
  logic batch_write_pending [0:BATCH_SLOTS-1];
  (* ram_style = "distributed" *) logic [AXI_ADDR_WIDTH-1:0] batch_addr [0:BATCH_SLOTS-1];
  logic [15:0] batch_valid_count [0:BATCH_SLOTS-1];
  logic [BATCH_OFF_W:0] batch_fill_count [0:BATCH_SLOTS-1];
  logic [BATCH_ID_W-1:0] batch_free_list [0:BATCH_SLOTS-1];
  logic [BATCH_ID_W-1:0] batch_free_rd_q;
  logic [BATCH_ID_W-1:0] batch_free_wr_q;
  logic [15:0] batch_free_count_q;
  logic open_batch_valid_q;
  logic [BATCH_ID_W-1:0] open_batch_id_q;
  logic append_new_batch_q;
  logic append_last_q;
  logic [BATCH_ID_W-1:0] append_batch_q;
  logic [BATCH_OFF_W-1:0] append_offset_q;

  logic [PORT_W-1:0] replace_port_q;
  logic [RANK_WIDTH-1:0] replace_rank_q;
  logic [SEQ_WIDTH-1:0] replace_seq_q;
  logic [PAYLOAD_WIDTH-1:0] replace_payload_q;
  logic [SRAM_SLOT_W-1:0] replace_slot_q;

  logic [BATCH_ID_W-1:0] swapin_batch_q;
  logic [BATCH_OFF_W:0] swapin_offset_q;

  logic record_valid_c;
  logic [PORT_W-1:0] record_port_c;
  logic [15:0] record_first_rank_c;
  logic [RANK_WIDTH-1:0] record_second_rank_c;
  logic swapout_valid_c;
  logic [PORT_W-1:0] swapout_port_c;
  logic [15:0] swapout_first_rank_c;
  logic batch_append_ready_c;
  logic append_existing_open_c;
  logic append_new_batch_c;
  logic append_possible_c;
  logic append_last_c;
  logic [BATCH_ID_W-1:0] append_batch_c;
  logic [BATCH_OFF_W-1:0] append_offset_c;
  logic [15:0] global_sram_c;
  logic [15:0] global_hbm_c;
  logic ingress_port_queue_free_c;
  logic ingress_better_record_c;
  logic water_swapout_pending_c;
  logic water_swapin_pending_c;
  logic ingress_better_record_q;
  logic water_swapout_pending_q;
  logic water_swapin_pending_q;
  logic all_ports_ready_c;
  logic deq_grant_valid_c;
  logic [PORT_W-1:0] deq_grant_port_c;
  logic deq_grant_use_hbm_c;
  logic [PORT_W-1:0] deq_rr_q;
  logic [PORT_W-1:0] deq_op_port_q;
  logic deq_op_use_hbm_q;
  logic [RANK_WIDTH-1:0] deq_op_rank_q;
  logic [SRAM_SLOT_W-1:0] deq_op_sram_slot_q;
  logic [BATCH_ID_W-1:0] deq_op_batch_q;
  logic [BATCH_OFF_W-1:0] deq_op_offset_q;

  wr_state_t wr_state_q;
  logic [BATCH_ID_W-1:0] wr_batch_q;
  logic [BATCH_OFF_W:0] wr_beat_q;
  logic [AXI_ADDR_WIDTH-1:0] wr_addr_q;
  logic [BATCH_ID_W-1:0] wr_scan_ptr_q;

  logic [BATCH_OFF_W:0] rd_beat_q;
  logic [AXI_ADDR_WIDTH-1:0] rd_addr_q;
  logic rd_stage_valid_q;
  logic [AXI_DATA_WIDTH-1:0] rd_stage_data_q;
  logic [1:0] rd_stage_resp_q;
  logic rd_stage_last_q;
  logic [BATCH_OFF_W:0] rd_stage_beat_q;
  logic rd_stage_entry_valid_q;
  logic [PORT_W-1:0] rd_stage_port_q;
  logic [RANK_WIDTH-1:0] rd_stage_rank_q;
  logic [SEQ_WIDTH-1:0] rd_stage_seq_q;
  logic ddr_r_accept_c;
  logic ddr_rd_fire_c;
  logic ddr_rd_direct_ready_c;
  logic ddr_rd_swapin_ready_c;
  logic ddr_wr_error_q;
  logic ddr_rd_error_q;

  genvar gp;
  generate
    for (gp = 0; gp < PORTS; gp = gp + 1) begin : g_ports
      hestia_port_rank_queue #(
        .RANK_WIDTH(RANK_WIDTH),
        .PACKET_ID_WIDTH(PACKET_ID_WIDTH),
        .SRAM_SLOT_WIDTH(SRAM_SLOT_W),
        .BATCH_ID_WIDTH(BATCH_ID_W),
        .BATCH_OFFSET_WIDTH(BATCH_OFF_W),
        .ENTRY_DEPTH(PORT_QUEUE_DEPTH)
      ) port_q_i (
        .clk(clk),
        .resetn(resetn),
        .cmd_valid(port_cmd_valid[gp]),
        .cmd_op(port_cmd_op[gp]),
        .cmd_rank(port_cmd_rank[gp]),
        .cmd_packet_id(port_cmd_packet_id[gp]),
        .cmd_sram_slot(port_cmd_sram_slot[gp]),
        .cmd_batch_id(port_cmd_batch_id[gp]),
        .cmd_batch_offset(port_cmd_batch_offset[gp]),
        .cmd_ready(port_cmd_ready[gp]),
        .idle_ready(port_idle_ready[gp]),
        .sram_min_valid(sram_min_valid[gp]),
        .sram_min_rank(sram_min_rank[gp]),
        .sram_min_packet_id(sram_min_packet_id[gp]),
        .sram_min_slot(sram_min_slot[gp]),
        .sram_max_valid(sram_max_valid[gp]),
        .sram_max_rank(sram_max_rank[gp]),
        .sram_max_packet_id(sram_max_packet_id[gp]),
        .sram_max_slot(sram_max_slot[gp]),
        .hbm_min_valid(hbm_min_valid[gp]),
        .hbm_min_rank(hbm_min_rank[gp]),
        .hbm_min_packet_id(hbm_min_packet_id[gp]),
        .hbm_min_batch_id(hbm_min_batch_id[gp]),
        .hbm_min_batch_offset(hbm_min_batch_offset[gp]),
        .dbg_sram_entries(port_dbg_sram_entries[gp]),
        .dbg_hbm_entries(port_dbg_hbm_entries[gp])
      );

      assign m_pkt_rank[gp*RANK_WIDTH +: RANK_WIDTH] = out_rank_q[gp];
      assign m_pkt_seq[gp*SEQ_WIDTH +: SEQ_WIDTH] = out_seq_q[gp];
      assign m_pkt_payload[gp*PAYLOAD_WIDTH +: PAYLOAD_WIDTH] = out_payload_q[gp];
      assign dbg_sram_count_flat[gp*16 +: 16] = sram_count_q[gp];
      assign dbg_hbm_count_flat[gp*16 +: 16] = hbm_count_q[gp];
    end
  endgenerate

  localparam logic [15:0] SRAM_CELLS_U16 = SRAM_CELLS[15:0];
  localparam logic [15:0] BATCH_SLOTS_U16 = BATCH_SLOTS[15:0];
  localparam logic [PORT_W-1:0] LAST_PORT = PORTS - 1;
  localparam int AXI_SIZE_WIDTH = (AXI_KEEP_WIDTH <= 2) ? 1 : $clog2(AXI_KEEP_WIDTH);
  localparam logic [2:0] AXI_BEAT_SIZE = AXI_SIZE_WIDTH;
  localparam logic [7:0] AXI_BATCH_LEN = BATCH_SIZE - 1;
  localparam logic [AXI_ADDR_WIDTH-1:0] AXI_BEAT_BYTES = AXI_KEEP_WIDTH;
  localparam logic [AXI_ADDR_WIDTH-1:0] BATCH_BYTES = BATCH_SIZE * AXI_KEEP_WIDTH;
  localparam int CELL_WORD_WIDTH = PORT_W + RANK_WIDTH + SEQ_WIDTH + PAYLOAD_WIDTH;

  if (CELL_WORD_WIDTH > AXI_DATA_WIDTH) begin : ddr_word_width_guard
    initial $error("PORT/RANK/SEQ/PAYLOAD fields must fit in one AXI beat");
  end

  if (AXI_SIZE_WIDTH > 8) begin : axi_size_guard
    initial $error("AXI data width is too large for the fixed AWSIZE/ARSIZE field");
  end

  function automatic logic [SRAM_SLOT_W-1:0] sram_free_head;
    begin
      sram_free_head = sram_free_list[sram_free_rd_q];
    end
  endfunction

  function automatic logic [BATCH_ID_W-1:0] batch_free_head;
    begin
      batch_free_head = batch_free_list[batch_free_rd_q];
    end
  endfunction

  function automatic logic [AXI_ADDR_WIDTH-1:0] ddr_batch_addr(
    input logic [BATCH_ID_W-1:0] batch_i
  );
    begin
      ddr_batch_addr = DDR_BASE_ADDR + (AXI_ADDR_WIDTH'(batch_i) * BATCH_BYTES);
    end
  endfunction

  function automatic logic [AXI_ADDR_WIDTH-1:0] ddr_cell_addr(
    input logic [BATCH_ID_W-1:0] batch_i,
    input logic [BATCH_OFF_W-1:0] offset_i
  );
    begin
      ddr_cell_addr = ddr_batch_addr(batch_i) +
                      (AXI_ADDR_WIDTH'(offset_i) * AXI_BEAT_BYTES);
    end
  endfunction

  function automatic logic [AXI_DATA_WIDTH-1:0] pack_ddr_cell(
    input logic [PORT_W-1:0] port_i,
    input logic [RANK_WIDTH-1:0] rank_i,
    input logic [SEQ_WIDTH-1:0] seq_i,
    input logic [PAYLOAD_WIDTH-1:0] payload_i
  );
    begin
      pack_ddr_cell = '0;
      pack_ddr_cell[PAYLOAD_WIDTH-1:0] = payload_i;
      pack_ddr_cell[PAYLOAD_WIDTH +: SEQ_WIDTH] = seq_i;
      pack_ddr_cell[PAYLOAD_WIDTH+SEQ_WIDTH +: RANK_WIDTH] = rank_i;
      pack_ddr_cell[PAYLOAD_WIDTH+SEQ_WIDTH+RANK_WIDTH +: PORT_W] = port_i;
    end
  endfunction

  function automatic logic [PORT_W-1:0] unpack_ddr_port(
    input logic [AXI_DATA_WIDTH-1:0] word_i
  );
    begin
      unpack_ddr_port = word_i[PAYLOAD_WIDTH+SEQ_WIDTH+RANK_WIDTH +: PORT_W];
    end
  endfunction

  function automatic logic [RANK_WIDTH-1:0] unpack_ddr_rank(
    input logic [AXI_DATA_WIDTH-1:0] word_i
  );
    begin
      unpack_ddr_rank = word_i[PAYLOAD_WIDTH+SEQ_WIDTH +: RANK_WIDTH];
    end
  endfunction

  function automatic logic [SEQ_WIDTH-1:0] unpack_ddr_seq(
    input logic [AXI_DATA_WIDTH-1:0] word_i
  );
    begin
      unpack_ddr_seq = word_i[PAYLOAD_WIDTH +: SEQ_WIDTH];
    end
  endfunction

  function automatic logic [PAYLOAD_WIDTH-1:0] unpack_ddr_payload(
    input logic [AXI_DATA_WIDTH-1:0] word_i
  );
    begin
      unpack_ddr_payload = word_i[PAYLOAD_WIDTH-1:0];
    end
  endfunction

  task automatic alloc_sram_slot(output logic [SRAM_SLOT_W-1:0] slot_o);
    begin
      slot_o = sram_free_head();
      sram_free_rd_q <= (sram_free_rd_q == SRAM_CELLS-1) ? '0 : (sram_free_rd_q + 1'b1);
      sram_free_count_q <= sram_free_count_q - 16'd1;
    end
  endtask

  task automatic free_sram_slot(input logic [SRAM_SLOT_W-1:0] slot_i);
    begin
      sram_valid[slot_i] <= 1'b0;
      sram_free_list[sram_free_wr_q] <= slot_i;
      sram_free_wr_q <= (sram_free_wr_q == SRAM_CELLS-1) ? '0 : (sram_free_wr_q + 1'b1);
      sram_free_count_q <= sram_free_count_q + 16'd1;
    end
  endtask

  task automatic write_sram_cell(
    input logic [SRAM_SLOT_W-1:0] slot_i,
    input logic [PORT_W-1:0] port_i,
    input logic [RANK_WIDTH-1:0] rank_i,
    input logic [SEQ_WIDTH-1:0] seq_i,
    input logic [PAYLOAD_WIDTH-1:0] payload_i
  );
    begin
      sram_wr_valid_q <= 1'b1;
      sram_wr_slot_q <= slot_i;
      sram_wr_port_q <= port_i;
      sram_wr_rank_q <= rank_i;
      sram_wr_seq_q <= seq_i;
      sram_wr_payload_q <= payload_i;
    end
  endtask

  task automatic free_batch_slot(input logic [BATCH_ID_W-1:0] batch_i);
    begin
      batch_fill_count[batch_i] <= '0;
      batch_valid_count[batch_i] <= 16'd0;
      batch_committed[batch_i] <= 1'b0;
      batch_write_pending[batch_i] <= 1'b0;
      batch_addr[batch_i] <= ddr_batch_addr(batch_i);
      batch_free_list[batch_free_wr_q] <= batch_i;
      batch_free_wr_q <= (batch_free_wr_q == BATCH_SLOTS-1) ? '0 : (batch_free_wr_q + 1'b1);
      batch_free_count_q <= batch_free_count_q + 16'd1;
      if (open_batch_valid_q && (open_batch_id_q == batch_i)) begin
        open_batch_valid_q <= 1'b0;
      end
    end
  endtask

  task automatic commit_hbm_cell(
    input logic [PORT_W-1:0] port_i,
    input logic [RANK_WIDTH-1:0] rank_i,
    input logic [SEQ_WIDTH-1:0] seq_i,
    input logic [PAYLOAD_WIDTH-1:0] payload_i
  );
    begin
      if (append_new_batch_q) begin
        batch_free_rd_q <= (batch_free_rd_q == BATCH_SLOTS-1) ? '0 : (batch_free_rd_q + 1'b1);
        batch_free_count_q <= batch_free_count_q - 16'd1;
        batch_addr[append_batch_q] <= ddr_batch_addr(append_batch_q);
        batch_committed[append_batch_q] <= 1'b0;
      end

      batch_entry_valid[append_batch_q][append_offset_q] <= 1'b1;
      batch_port[append_batch_q][append_offset_q] <= port_i;
      batch_rank[append_batch_q][append_offset_q] <= rank_i;
      batch_seq[append_batch_q][append_offset_q] <= seq_i;
      batch_payload[append_batch_q][append_offset_q] <= payload_i;
      batch_fill_count[append_batch_q] <= append_offset_q + 1'b1;
      batch_valid_count[append_batch_q] <= append_new_batch_q ?
        16'd1 : (batch_valid_count[append_batch_q] + 16'd1);

      if (append_last_q) begin
        open_batch_valid_q <= 1'b0;
        batch_write_pending[append_batch_q] <= 1'b1;
      end else begin
        open_batch_valid_q <= 1'b1;
        open_batch_id_q <= append_batch_q;
        batch_write_pending[append_batch_q] <= 1'b0;
      end
    end
  endtask

  task automatic invalidate_batch_cell(
    input logic [BATCH_ID_W-1:0] batch_i,
    input logic [BATCH_OFF_W-1:0] offset_i
  );
    begin
      if (batch_entry_valid[batch_i][offset_i]) begin
        batch_entry_valid[batch_i][offset_i] <= 1'b0;
        batch_valid_count[batch_i] <= batch_valid_count[batch_i] - 16'd1;
        if ((batch_valid_count[batch_i] == 16'd1) &&
            !(open_batch_valid_q && (open_batch_id_q == batch_i) &&
              (batch_fill_count[batch_i] < BATCH_SIZE)) &&
            !batch_write_pending[batch_i] &&
            !((wr_state_q != WR_IDLE) && (wr_batch_q == batch_i))) begin
          free_batch_slot(batch_i);
        end
      end
    end
  endtask

  integer ci;
  integer di;
  integer deq_idx_i;
  always_comb begin
    global_sram_c = 16'd0;
    global_hbm_c = 16'd0;
    record_valid_c = 1'b0;
    record_port_c = '0;
    record_first_rank_c = '1;
    record_second_rank_c = '1;
    swapout_valid_c = 1'b0;
    swapout_port_c = '0;
    swapout_first_rank_c = 16'd0;
    append_existing_open_c = open_batch_valid_q &&
                             (batch_fill_count[open_batch_id_q] < BATCH_SIZE);
    append_new_batch_c = !append_existing_open_c;
    append_possible_c = append_existing_open_c || (batch_free_count_q != 16'd0);
    append_batch_c = append_existing_open_c ? open_batch_id_q : batch_free_head();
    append_offset_c = append_existing_open_c ? batch_fill_count[open_batch_id_q][BATCH_OFF_W-1:0] : '0;
    append_last_c = append_possible_c && ((append_offset_c + 1'b1) == BATCH_SIZE);
    deq_grant_valid_c = 1'b0;
    deq_grant_port_c = deq_rr_q;
    deq_grant_use_hbm_c = 1'b0;

    for (ci = 0; ci < PORTS; ci = ci + 1) begin
      global_sram_c = global_sram_c + sram_count_q[ci];
      global_hbm_c = global_hbm_c + hbm_count_q[ci];

      if ((hbm_count_q[ci] != 16'd0) && hbm_min_valid[ci]) begin
        if (!record_valid_c ||
            (sram_count_q[ci] < record_first_rank_c) ||
            ((sram_count_q[ci] == record_first_rank_c) &&
             (hbm_min_rank[ci] < record_second_rank_c))) begin
          record_valid_c = 1'b1;
          record_port_c = ci[PORT_W-1:0];
          record_first_rank_c = sram_count_q[ci];
          record_second_rank_c = hbm_min_rank[ci];
        end
      end

      if ((sram_count_q[ci] != 16'd0) && sram_max_valid[ci]) begin
        if (!swapout_valid_c ||
            (sram_count_q[ci] > swapout_first_rank_c) ||
            ((sram_count_q[ci] == swapout_first_rank_c) &&
             (sram_max_rank[ci] > sram_max_rank[swapout_port_c]))) begin
          swapout_valid_c = 1'b1;
          swapout_port_c = ci[PORT_W-1:0];
          swapout_first_rank_c = sram_count_q[ci];
        end
      end
    end

    for (di = 0; di < PORTS; di = di + 1) begin
      deq_idx_i = deq_rr_q + di;
      if (deq_idx_i >= PORTS) begin
        deq_idx_i = deq_idx_i - PORTS;
      end
      if (!deq_grant_valid_c && enable && (state_q == ST_IDLE) &&
          dequeue_enable[deq_idx_i] &&
          (!m_pkt_valid[deq_idx_i] || m_pkt_ready[deq_idx_i]) &&
          (sram_min_valid[deq_idx_i] || hbm_min_valid[deq_idx_i])) begin
        deq_grant_valid_c = 1'b1;
        deq_grant_port_c = deq_idx_i[PORT_W-1:0];
        deq_grant_use_hbm_c = hbm_min_valid[deq_idx_i] &&
                              (!sram_min_valid[deq_idx_i] ||
                               (hbm_min_rank[deq_idx_i] < sram_min_rank[deq_idx_i]));
      end
    end

    all_ports_ready_c = &(port_idle_ready & ~port_cmd_valid);
    batch_append_ready_c = append_possible_c;
    water_swapout_pending_c = enable && all_ports_ready_c &&
                              (global_sram_c > cfg_swap_out_threshold) &&
                              swapout_valid_c && batch_append_ready_c;
    water_swapin_pending_c = enable && all_ports_ready_c &&
                             (global_sram_c < cfg_swap_in_threshold) &&
                             record_valid_c &&
                             (batch_valid_count[hbm_min_batch_id[record_port_c]] <= sram_free_count_q);
    water_swapout_pending_q = enable &&
                              (global_sram_q > cfg_swap_out_threshold) &&
                              swapout_valid_q && batch_append_ready_c;
    water_swapin_pending_q = enable &&
                             (global_sram_q < cfg_swap_in_threshold) &&
                             record_valid_q &&
                             (batch_valid_count[record_batch_q] <= sram_free_count_q);
    ingress_port_queue_free_c = (port_dbg_sram_entries[s_pkt_port] +
                                 port_dbg_hbm_entries[s_pkt_port]) < PORT_QUEUE_DEPTH;
    ingress_better_record_c = !record_valid_c ||
                              (sram_count_q[s_pkt_port] < record_first_rank_c) ||
                              ((sram_count_q[s_pkt_port] == record_first_rank_c) &&
                               (s_pkt_rank < record_second_rank_c));
    ingress_better_record_q = !record_valid_q ||
                              (sram_count_q[s_pkt_port] < record_first_rank_q) ||
                              ((sram_count_q[s_pkt_port] == record_first_rank_q) &&
                               (s_pkt_rank < record_second_rank_q));
    s_pkt_ready = enable && (state_q == ST_IDLE) &&
                  !water_swapout_pending_q && !water_swapin_pending_q &&
                  !deq_grant_valid_c &&
                  ingress_port_queue_free_c &&
                  ((sram_free_count_q != 16'd0) || batch_append_ready_c);

    ddr_rd_direct_ready_c = (state_q == ST_DEQ_DDR_DATA) &&
                            rd_stage_valid_q &&
                            (!m_pkt_valid[deq_op_port_q] || m_pkt_ready[deq_op_port_q]) &&
                            !port_cmd_valid[deq_op_port_q] &&
                            port_idle_ready[deq_op_port_q];
    ddr_rd_swapin_ready_c = (state_q == ST_SWAPIN_DDR_DATA) &&
                            rd_stage_valid_q &&
                            (rd_stage_beat_q < BATCH_SIZE) &&
                            (!rd_stage_entry_valid_q ||
                             (!port_cmd_valid[rd_stage_port_q] &&
                              port_idle_ready[rd_stage_port_q] &&
                              (sram_free_count_q != 16'd0)));
    ddr_rd_fire_c = ddr_rd_direct_ready_c || ddr_rd_swapin_ready_c;

    m_axi_awid = '0;
    m_axi_awaddr = wr_addr_q;
    m_axi_awlen = AXI_BATCH_LEN;
    m_axi_awsize = AXI_BEAT_SIZE;
    m_axi_awburst = 2'b01;
    m_axi_awlock = 1'b0;
    m_axi_awcache = 4'b0011;
    m_axi_awprot = 3'b000;
    m_axi_awqos = 4'b0000;
    m_axi_wstrb = {AXI_KEEP_WIDTH{1'b1}};
    m_axi_wlast = (wr_beat_q + 1'b1) == BATCH_SIZE;
    m_axi_bready = (wr_state_q == WR_RESP);
    m_axi_arid = '0;
    m_axi_araddr = rd_addr_q;
    m_axi_arlen = (state_q == ST_SWAPIN_DDR_ADDR) ? AXI_BATCH_LEN : 8'd0;
    m_axi_arsize = AXI_BEAT_SIZE;
    m_axi_arburst = 2'b01;
    m_axi_arlock = 1'b0;
    m_axi_arcache = 4'b0011;
    m_axi_arprot = 3'b000;
    m_axi_arqos = 4'b0000;
    m_axi_rready = ((state_q == ST_DEQ_DDR_DATA) ||
                    (state_q == ST_SWAPIN_DDR_DATA)) &&
                   !rd_stage_valid_q;
    ddr_r_accept_c = m_axi_rvalid && m_axi_rready;

    dbg_ddr_state = {wr_state_q, state_q};
    dbg_ddr_wr_error = ddr_wr_error_q;
    dbg_ddr_rd_error = ddr_rd_error_q;
    dbg_global_sram_occupancy = global_sram_c;
    dbg_global_hbm_occupancy = global_hbm_c;
  end

  integer pi;
  integer bi;
  integer oi;
  always_ff @(posedge clk) begin
    logic [SRAM_SLOT_W-1:0] alloc_slot_v;
    logic [PORT_W-1:0] port_v;
    logic [PORT_W-1:0] select_port_v;
    logic choose_replace_v;
    logic choose_hbm_v;
    logic ddr_rd_error_v;
    logic [31:0] deq_fire_count_v;
    logic [31:0] direct_deq_fire_count_v;
    if (!resetn) begin
      state_q <= ST_SELECT;
      for (pi = 0; pi < PORTS; pi = pi + 1) begin
        total_count_q[pi] <= 16'd0;
        sram_count_q[pi] <= 16'd0;
        hbm_count_q[pi] <= 16'd0;
        m_pkt_valid[pi] <= 1'b0;
        out_from_hbm_q[pi] <= 1'b0;
        out_rank_q[pi] <= '0;
        out_seq_q[pi] <= '0;
        out_payload_q[pi] <= '0;
        port_cmd_valid[pi] <= 1'b0;
        port_cmd_op[pi] <= MP_CMD_NONE;
        port_cmd_rank[pi] <= '0;
        port_cmd_packet_id[pi] <= '0;
        port_cmd_sram_slot[pi] <= '0;
        port_cmd_batch_id[pi] <= '0;
        port_cmd_batch_offset[pi] <= '0;
      end
      for (pi = 0; pi < SRAM_CELLS; pi = pi + 1) begin
        sram_valid[pi] <= 1'b0;
        sram_free_list[pi] <= pi[SRAM_SLOT_W-1:0];
      end
      sram_free_rd_q <= '0;
      sram_free_wr_q <= '0;
      sram_free_count_q <= SRAM_CELLS_U16;
      sram_wr_valid_q <= 1'b0;
      sram_wr_slot_q <= '0;
      sram_wr_port_q <= '0;
      sram_wr_rank_q <= '0;
      sram_wr_seq_q <= '0;
      sram_wr_payload_q <= '0;
      for (bi = 0; bi < BATCH_SLOTS; bi = bi + 1) begin
        batch_free_list[bi] <= bi[BATCH_ID_W-1:0];
        batch_valid_count[bi] <= 16'd0;
        batch_fill_count[bi] <= '0;
        batch_committed[bi] <= 1'b0;
        batch_write_pending[bi] <= 1'b0;
        batch_addr[bi] <= ddr_batch_addr(bi[BATCH_ID_W-1:0]);
        for (oi = 0; oi < BATCH_SIZE; oi = oi + 1) begin
          batch_entry_valid[bi][oi] <= 1'b0;
        end
      end
      batch_free_rd_q <= '0;
      batch_free_wr_q <= '0;
      batch_free_count_q <= BATCH_SLOTS_U16;
      open_batch_valid_q <= 1'b0;
      open_batch_id_q <= '0;
      append_new_batch_q <= 1'b0;
      append_last_q <= 1'b0;
      append_batch_q <= '0;
      append_offset_q <= '0;
      replace_port_q <= '0;
      replace_rank_q <= '0;
      replace_seq_q <= '0;
      replace_payload_q <= '0;
      replace_slot_q <= '0;
      swapin_batch_q <= '0;
      swapin_offset_q <= '0;
      stat_generated <= 32'd0;
      stat_dequeued <= 32'd0;
      stat_sram_admit <= 32'd0;
      stat_hbm_admit <= 32'd0;
      stat_swap_out <= 32'd0;
      stat_swap_in <= 32'd0;
      stat_direct_hbm_dequeue <= 32'd0;
      stat_drop <= 32'd0;
      action_q <= ACT_NONE;
      action_port_q <= '0;
      action_choose_replace_q <= 1'b0;
      action_choose_hbm_q <= 1'b0;
      action_rank_q <= '0;
      action_seq_q <= '0;
      action_payload_q <= '0;
      action_batch_q <= '0;
      global_sram_q <= 16'd0;
      global_hbm_q <= 16'd0;
      record_valid_q <= 1'b0;
      record_port_q <= '0;
      record_first_rank_q <= '1;
      record_second_rank_q <= '1;
      record_batch_q <= '0;
      swapout_valid_q <= 1'b0;
      swapout_port_q <= '0;
      deq_rr_q <= '0;
      deq_op_port_q <= '0;
      deq_op_use_hbm_q <= 1'b0;
      deq_op_rank_q <= '0;
      deq_op_sram_slot_q <= '0;
      deq_op_batch_q <= '0;
      deq_op_offset_q <= '0;
      wr_state_q <= WR_IDLE;
      wr_batch_q <= '0;
      wr_beat_q <= '0;
      wr_addr_q <= '0;
      wr_scan_ptr_q <= '0;
      rd_beat_q <= '0;
      rd_addr_q <= '0;
      rd_stage_valid_q <= 1'b0;
      rd_stage_data_q <= '0;
      rd_stage_resp_q <= 2'b00;
      rd_stage_last_q <= 1'b0;
      rd_stage_beat_q <= '0;
      rd_stage_entry_valid_q <= 1'b0;
      rd_stage_port_q <= '0;
      rd_stage_rank_q <= '0;
      rd_stage_seq_q <= '0;
      m_axi_awvalid <= 1'b0;
      m_axi_wvalid <= 1'b0;
      m_axi_wdata <= '0;
      m_axi_arvalid <= 1'b0;
      stat_ddr_write_beats <= 32'd0;
      stat_ddr_read_beats <= 32'd0;
      stat_ddr_write_batches <= 32'd0;
      stat_ddr_read_batches <= 32'd0;
      ddr_wr_error_q <= 1'b0;
      ddr_rd_error_q <= 1'b0;
      select_idx_q <= '0;
    end else begin
      deq_fire_count_v = 32'd0;
      direct_deq_fire_count_v = 32'd0;

      if (sram_wr_valid_q) begin
        sram_valid[sram_wr_slot_q] <= 1'b1;
        sram_port[sram_wr_slot_q] <= sram_wr_port_q;
        sram_rank[sram_wr_slot_q] <= sram_wr_rank_q;
        sram_seq[sram_wr_slot_q] <= sram_wr_seq_q;
        sram_payload[sram_wr_slot_q] <= sram_wr_payload_q;
      end
      sram_wr_valid_q <= 1'b0;

      if (ddr_rd_fire_c) begin
        rd_stage_valid_q <= 1'b0;
      end

      if (ddr_r_accept_c) begin
        rd_stage_valid_q <= 1'b1;
        rd_stage_data_q <= m_axi_rdata;
        rd_stage_resp_q <= m_axi_rresp;
        rd_stage_last_q <= m_axi_rlast;
        rd_stage_beat_q <= rd_beat_q;
        if (state_q == ST_SWAPIN_DDR_DATA) begin
          rd_stage_entry_valid_q <= batch_entry_valid[swapin_batch_q][rd_beat_q[BATCH_OFF_W-1:0]];
          rd_stage_port_q <= batch_port[swapin_batch_q][rd_beat_q[BATCH_OFF_W-1:0]];
          rd_stage_rank_q <= batch_rank[swapin_batch_q][rd_beat_q[BATCH_OFF_W-1:0]];
          rd_stage_seq_q <= batch_seq[swapin_batch_q][rd_beat_q[BATCH_OFF_W-1:0]];
        end else begin
          rd_stage_entry_valid_q <= 1'b1;
          rd_stage_port_q <= deq_op_port_q;
          rd_stage_rank_q <= deq_op_rank_q;
          rd_stage_seq_q <= '0;
        end
        rd_beat_q <= rd_beat_q + 1'b1;
      end

      for (pi = 0; pi < PORTS; pi = pi + 1) begin
        if (port_cmd_valid[pi] && port_cmd_ready[pi]) begin
          port_cmd_valid[pi] <= 1'b0;
          port_cmd_op[pi] <= MP_CMD_NONE;
          port_cmd_rank[pi] <= '0;
          port_cmd_packet_id[pi] <= '0;
          port_cmd_sram_slot[pi] <= '0;
          port_cmd_batch_id[pi] <= '0;
          port_cmd_batch_offset[pi] <= '0;
        end
        if (m_pkt_valid[pi] && m_pkt_ready[pi]) begin
          m_pkt_valid[pi] <= 1'b0;
          out_from_hbm_q[pi] <= 1'b0;
          deq_fire_count_v = deq_fire_count_v + 32'd1;
          if (out_from_hbm_q[pi]) begin
            direct_deq_fire_count_v = direct_deq_fire_count_v + 32'd1;
          end
        end
      end

      if (deq_fire_count_v != 32'd0) begin
        stat_dequeued <= stat_dequeued + deq_fire_count_v;
      end
      if (direct_deq_fire_count_v != 32'd0) begin
        stat_direct_hbm_dequeue <= stat_direct_hbm_dequeue + direct_deq_fire_count_v;
      end

      unique case (wr_state_q)
        WR_IDLE: begin
          if (enable && batch_write_pending[wr_scan_ptr_q] &&
              !batch_committed[wr_scan_ptr_q] &&
              (batch_valid_count[wr_scan_ptr_q] != 16'd0)) begin
            wr_batch_q <= wr_scan_ptr_q;
            wr_addr_q <= ddr_batch_addr(wr_scan_ptr_q);
            wr_beat_q <= '0;
            m_axi_awvalid <= 1'b1;
            wr_state_q <= WR_ADDR;
          end else if (enable) begin
            wr_scan_ptr_q <= (wr_scan_ptr_q == BATCH_SLOTS-1) ? '0 : (wr_scan_ptr_q + 1'b1);
          end
        end

        WR_ADDR: begin
          if (m_axi_awvalid && m_axi_awready) begin
            m_axi_awvalid <= 1'b0;
            m_axi_wvalid <= 1'b1;
            m_axi_wdata <= pack_ddr_cell(
              batch_port[wr_batch_q][0],
              batch_rank[wr_batch_q][0],
              batch_seq[wr_batch_q][0],
              batch_payload[wr_batch_q][0]
            );
            wr_state_q <= WR_DATA;
          end
        end

        WR_DATA: begin
          if (m_axi_wvalid && m_axi_wready) begin
            stat_ddr_write_beats <= stat_ddr_write_beats + 32'd1;
            if ((wr_beat_q + 1'b1) == BATCH_SIZE) begin
              m_axi_wvalid <= 1'b0;
              wr_state_q <= WR_RESP;
            end else begin
              wr_beat_q <= wr_beat_q + 1'b1;
              m_axi_wdata <= pack_ddr_cell(
                batch_port[wr_batch_q][wr_beat_q[BATCH_OFF_W-1:0] + 1'b1],
                batch_rank[wr_batch_q][wr_beat_q[BATCH_OFF_W-1:0] + 1'b1],
                batch_seq[wr_batch_q][wr_beat_q[BATCH_OFF_W-1:0] + 1'b1],
                batch_payload[wr_batch_q][wr_beat_q[BATCH_OFF_W-1:0] + 1'b1]
              );
            end
          end
        end

        WR_RESP: begin
          if (m_axi_bvalid) begin
            ddr_wr_error_q <= ddr_wr_error_q | (m_axi_bresp != 2'b00);
            batch_write_pending[wr_batch_q] <= 1'b0;
            batch_committed[wr_batch_q] <= 1'b1;
            stat_ddr_write_batches <= stat_ddr_write_batches + 32'd1;
            wr_scan_ptr_q <= (wr_batch_q == BATCH_SLOTS-1) ? '0 : (wr_batch_q + 1'b1);
            wr_state_q <= WR_IDLE;
          end
        end

        default: begin
          m_axi_awvalid <= 1'b0;
          m_axi_wvalid <= 1'b0;
          wr_state_q <= WR_IDLE;
        end
      endcase

      unique case (state_q)
        ST_SELECT: begin
          if (all_ports_ready_c) begin
            global_sram_q <= 16'd0;
            global_hbm_q <= 16'd0;
            record_valid_q <= 1'b0;
            record_port_q <= '0;
            record_first_rank_q <= '1;
            record_second_rank_q <= '1;
            record_batch_q <= '0;
            swapout_valid_q <= 1'b0;
            swapout_port_q <= '0;
            select_idx_q <= '0;
            state_q <= ST_SELECT_SCAN;
          end
        end

        ST_SELECT_SCAN: begin
          select_port_v = select_idx_q[PORT_W-1:0];
          global_sram_q <= global_sram_q + sram_count_q[select_port_v];
          global_hbm_q <= global_hbm_q + hbm_count_q[select_port_v];

          if ((hbm_count_q[select_port_v] != 16'd0) && hbm_min_valid[select_port_v]) begin
            if (!record_valid_q ||
                (sram_count_q[select_port_v] < record_first_rank_q) ||
                ((sram_count_q[select_port_v] == record_first_rank_q) &&
                 (hbm_min_rank[select_port_v] < record_second_rank_q))) begin
              record_valid_q <= 1'b1;
              record_port_q <= select_port_v;
              record_first_rank_q <= sram_count_q[select_port_v];
              record_second_rank_q <= hbm_min_rank[select_port_v];
              record_batch_q <= hbm_min_batch_id[select_port_v];
            end
          end

          if ((sram_count_q[select_port_v] != 16'd0) && sram_max_valid[select_port_v]) begin
            if (!swapout_valid_q ||
                (sram_count_q[select_port_v] > sram_count_q[swapout_port_q]) ||
                ((sram_count_q[select_port_v] == sram_count_q[swapout_port_q]) &&
                 (sram_max_rank[select_port_v] > sram_max_rank[swapout_port_q]))) begin
              swapout_valid_q <= 1'b1;
              swapout_port_q <= select_port_v;
            end
          end

          if (select_idx_q == (PORTS - 1)) begin
            state_q <= ST_IDLE;
          end else begin
            select_idx_q <= select_idx_q + 1'b1;
          end
        end

        ST_IDLE: begin
          if (deq_grant_valid_c) begin
            port_v = deq_grant_port_c;
            if (deq_grant_use_hbm_c) begin
              deq_op_rank_q <= hbm_min_rank[port_v];
              deq_op_sram_slot_q <= '0;
              deq_op_batch_q <= hbm_min_batch_id[port_v];
              deq_op_offset_q <= hbm_min_batch_offset[port_v];
            end else begin
              deq_op_rank_q <= sram_min_rank[port_v];
              deq_op_sram_slot_q <= sram_min_slot[port_v];
              deq_op_batch_q <= '0;
              deq_op_offset_q <= '0;
            end
            deq_op_port_q <= port_v;
            deq_op_use_hbm_q <= deq_grant_use_hbm_c;
            deq_rr_q <= (port_v == LAST_PORT) ? '0 : (port_v + 1'b1);
            action_q <= ACT_NONE;
            state_q <= ST_DEQ_EXEC;
          end else if (water_swapout_pending_q) begin
            action_q <= ACT_SWAP_OUT;
            action_port_q <= swapout_port_q;
            state_q <= ST_EXEC;
          end else if (water_swapin_pending_q) begin
            action_q <= ACT_START_SWAP_IN;
            action_port_q <= record_port_q;
            action_batch_q <= record_batch_q;
            state_q <= ST_EXEC;
          end else if (enable && s_pkt_valid && s_pkt_ready) begin
            port_v = s_pkt_port;
            choose_replace_v = 1'b0;
            choose_hbm_v = 1'b0;

            if (ingress_better_record_q && (sram_free_count_q != 16'd0)) begin
              choose_hbm_v = 1'b0;
            end else if (sram_max_valid[port_v] &&
                         (s_pkt_rank < sram_max_rank[port_v]) &&
                         batch_append_ready_c) begin
              choose_replace_v = 1'b1;
            end else if (batch_append_ready_c) begin
              choose_hbm_v = 1'b1;
            end else if (sram_free_count_q != 16'd0) begin
              choose_hbm_v = 1'b0;
            end else begin
              choose_hbm_v = 1'b1;
            end

            action_q <= ACT_INGRESS;
            action_port_q <= port_v;
            action_choose_replace_q <= choose_replace_v;
            action_choose_hbm_q <= choose_hbm_v;
            action_rank_q <= s_pkt_rank;
            action_seq_q <= s_pkt_seq;
            action_payload_q <= s_pkt_payload;
            state_q <= ST_EXEC;
          end else begin
            state_q <= ST_SELECT;
          end
        end

        ST_DEQ_EXEC: begin
          port_v = deq_op_port_q;
          if (deq_op_use_hbm_q) begin
            if (batch_committed[deq_op_batch_q]) begin
              rd_addr_q <= ddr_cell_addr(deq_op_batch_q, deq_op_offset_q);
              rd_beat_q <= '0;
              rd_stage_valid_q <= 1'b0;
              m_axi_arvalid <= 1'b1;
              state_q <= ST_DEQ_DDR_ADDR;
            end else if (batch_write_pending[deq_op_batch_q] ||
                         ((wr_state_q != WR_IDLE) && (wr_batch_q == deq_op_batch_q))) begin
              state_q <= ST_DEQ_EXEC;
            end else begin
              m_pkt_valid[port_v] <= 1'b1;
              out_from_hbm_q[port_v] <= 1'b1;
              out_rank_q[port_v] <= deq_op_rank_q;
              out_seq_q[port_v] <= batch_seq[deq_op_batch_q][deq_op_offset_q];
              out_payload_q[port_v] <= batch_payload[deq_op_batch_q][deq_op_offset_q];
              port_cmd_valid[port_v] <= 1'b1;
              port_cmd_op[port_v] <= MP_CMD_REMOVE_HBM_MIN;
              invalidate_batch_cell(deq_op_batch_q, deq_op_offset_q);
              total_count_q[port_v] <= total_count_q[port_v] - 16'd1;
              hbm_count_q[port_v] <= hbm_count_q[port_v] - 16'd1;
              state_q <= ST_SELECT;
            end
          end else begin
            m_pkt_valid[port_v] <= 1'b1;
            out_from_hbm_q[port_v] <= 1'b0;
            out_rank_q[port_v] <= deq_op_rank_q;
            out_seq_q[port_v] <= sram_seq[deq_op_sram_slot_q];
            out_payload_q[port_v] <= sram_payload[deq_op_sram_slot_q];
            port_cmd_valid[port_v] <= 1'b1;
            port_cmd_op[port_v] <= MP_CMD_REMOVE_SRAM_MIN;
            free_sram_slot(deq_op_sram_slot_q);
            total_count_q[port_v] <= total_count_q[port_v] - 16'd1;
            sram_count_q[port_v] <= sram_count_q[port_v] - 16'd1;
            state_q <= ST_SELECT;
          end
          action_q <= ACT_NONE;
        end

        ST_DEQ_DDR_ADDR: begin
          if (m_axi_arvalid && m_axi_arready) begin
            m_axi_arvalid <= 1'b0;
            state_q <= ST_DEQ_DDR_DATA;
          end
        end

        ST_DEQ_DDR_DATA: begin
          port_v = deq_op_port_q;
          if (ddr_rd_fire_c) begin
            ddr_rd_error_q <= ddr_rd_error_q | (rd_stage_resp_q != 2'b00) | !rd_stage_last_q;
            m_pkt_valid[port_v] <= 1'b1;
            out_from_hbm_q[port_v] <= 1'b1;
            out_rank_q[port_v] <= unpack_ddr_rank(rd_stage_data_q);
            out_seq_q[port_v] <= unpack_ddr_seq(rd_stage_data_q);
            out_payload_q[port_v] <= unpack_ddr_payload(rd_stage_data_q);
            port_cmd_valid[port_v] <= 1'b1;
            port_cmd_op[port_v] <= MP_CMD_REMOVE_HBM_MIN;
            invalidate_batch_cell(deq_op_batch_q, deq_op_offset_q);
            total_count_q[port_v] <= total_count_q[port_v] - 16'd1;
            hbm_count_q[port_v] <= hbm_count_q[port_v] - 16'd1;
            stat_ddr_read_beats <= stat_ddr_read_beats + 32'd1;
            action_q <= ACT_NONE;
            state_q <= ST_SELECT;
          end
        end

        ST_EXEC: begin
          unique case (action_q)
            ACT_SWAP_OUT: begin
              if (append_possible_c) begin
                append_new_batch_q <= append_new_batch_c;
                append_last_q <= append_last_c;
                append_batch_q <= append_batch_c;
                append_offset_q <= append_offset_c;
                state_q <= ST_APPEND_EXEC;
              end else begin
                action_q <= ACT_NONE;
                state_q <= ST_SELECT;
              end
            end

            ACT_START_SWAP_IN: begin
              swapin_batch_q <= action_batch_q;
              swapin_offset_q <= '0;
              action_q <= ACT_NONE;
              state_q <= ST_SWAPIN_WAIT;
            end

            ACT_INGRESS: begin
              port_v = action_port_q;
              if (action_choose_replace_q || action_choose_hbm_q) begin
                if (append_possible_c) begin
                  append_new_batch_q <= append_new_batch_c;
                  append_last_q <= append_last_c;
                  append_batch_q <= append_batch_c;
                  append_offset_q <= append_offset_c;
                  state_q <= ST_APPEND_EXEC;
                end else begin
                  stat_generated <= stat_generated + 32'd1;
                  stat_drop <= stat_drop + 32'd1;
                  action_q <= ACT_NONE;
                  state_q <= ST_SELECT;
                end
              end else begin
                stat_generated <= stat_generated + 32'd1;
                alloc_sram_slot(alloc_slot_v);
                write_sram_cell(alloc_slot_v, port_v, action_rank_q, action_seq_q, action_payload_q);
                port_cmd_valid[port_v] <= 1'b1;
                port_cmd_op[port_v] <= MP_CMD_ADD_SRAM;
                port_cmd_rank[port_v] <= action_rank_q;
                port_cmd_packet_id[port_v] <= action_seq_q;
                port_cmd_sram_slot[port_v] <= alloc_slot_v;
                total_count_q[port_v] <= total_count_q[port_v] + 16'd1;
                sram_count_q[port_v] <= sram_count_q[port_v] + 16'd1;
                stat_sram_admit <= stat_sram_admit + 32'd1;
                action_q <= ACT_NONE;
                state_q <= ST_SELECT;
              end
            end

            default: begin
              action_q <= ACT_NONE;
              state_q <= ST_SELECT;
            end
          endcase
        end

        ST_APPEND_EXEC: begin
          unique case (action_q)
            ACT_SWAP_OUT: begin
              port_v = action_port_q;
              commit_hbm_cell(port_v, sram_max_rank[port_v], sram_seq[sram_max_slot[port_v]],
                              sram_payload[sram_max_slot[port_v]]);
              port_cmd_valid[port_v] <= 1'b1;
              port_cmd_op[port_v] <= MP_CMD_MOVE_SRAM_MAX_HBM;
              port_cmd_batch_id[port_v] <= append_batch_q;
              port_cmd_batch_offset[port_v] <= append_offset_q;
              free_sram_slot(sram_max_slot[port_v]);
              sram_count_q[port_v] <= sram_count_q[port_v] - 16'd1;
              hbm_count_q[port_v] <= hbm_count_q[port_v] + 16'd1;
              stat_swap_out <= stat_swap_out + 32'd1;
              action_q <= ACT_NONE;
              state_q <= ST_SELECT;
            end

            ACT_INGRESS: begin
              port_v = action_port_q;
              stat_generated <= stat_generated + 32'd1;
              if (action_choose_replace_q) begin
                commit_hbm_cell(port_v, sram_max_rank[port_v], sram_seq[sram_max_slot[port_v]],
                                sram_payload[sram_max_slot[port_v]]);
                port_cmd_valid[port_v] <= 1'b1;
                port_cmd_op[port_v] <= MP_CMD_MOVE_SRAM_MAX_HBM;
                port_cmd_batch_id[port_v] <= append_batch_q;
                port_cmd_batch_offset[port_v] <= append_offset_q;
                replace_port_q <= port_v;
                replace_rank_q <= action_rank_q;
                replace_seq_q <= action_seq_q;
                replace_payload_q <= action_payload_q;
                replace_slot_q <= sram_max_slot[port_v];
                write_sram_cell(sram_max_slot[port_v], port_v, action_rank_q, action_seq_q, action_payload_q);
                total_count_q[port_v] <= total_count_q[port_v] + 16'd1;
                hbm_count_q[port_v] <= hbm_count_q[port_v] + 16'd1;
                stat_sram_admit <= stat_sram_admit + 32'd1;
                stat_hbm_admit <= stat_hbm_admit + 32'd1;
                state_q <= ST_REPLACE_ADD_SRAM;
              end else begin
                commit_hbm_cell(port_v, action_rank_q, action_seq_q, action_payload_q);
                port_cmd_valid[port_v] <= 1'b1;
                port_cmd_op[port_v] <= MP_CMD_ADD_HBM;
                port_cmd_rank[port_v] <= action_rank_q;
                port_cmd_packet_id[port_v] <= action_seq_q;
                port_cmd_batch_id[port_v] <= append_batch_q;
                port_cmd_batch_offset[port_v] <= append_offset_q;
                total_count_q[port_v] <= total_count_q[port_v] + 16'd1;
                hbm_count_q[port_v] <= hbm_count_q[port_v] + 16'd1;
                stat_hbm_admit <= stat_hbm_admit + 32'd1;
                state_q <= ST_SELECT;
              end
              action_q <= ACT_NONE;
            end

            default: begin
              action_q <= ACT_NONE;
              state_q <= ST_SELECT;
            end
          endcase
        end

        ST_REPLACE_ADD_SRAM: begin
          if (!port_cmd_valid[replace_port_q] && port_cmd_ready[replace_port_q]) begin
            port_cmd_valid[replace_port_q] <= 1'b1;
            port_cmd_op[replace_port_q] <= MP_CMD_ADD_SRAM;
            port_cmd_rank[replace_port_q] <= replace_rank_q;
            port_cmd_packet_id[replace_port_q] <= replace_seq_q;
            port_cmd_sram_slot[replace_port_q] <= replace_slot_q;
            state_q <= ST_SELECT;
          end
        end

        ST_SWAPIN_WAIT: begin
          if (all_ports_ready_c) begin
            if (batch_committed[swapin_batch_q]) begin
              rd_addr_q <= batch_addr[swapin_batch_q];
              rd_beat_q <= '0;
              rd_stage_valid_q <= 1'b0;
              m_axi_arvalid <= 1'b1;
              state_q <= ST_SWAPIN_DDR_ADDR;
            end else if (batch_write_pending[swapin_batch_q] ||
                         ((wr_state_q != WR_IDLE) && (wr_batch_q == swapin_batch_q))) begin
              state_q <= ST_SWAPIN_WAIT;
            end else begin
              state_q <= ST_SWAPIN_SCAN;
            end
          end
        end

        ST_SWAPIN_SCAN: begin
          if (swapin_offset_q == BATCH_SIZE) begin
            free_batch_slot(swapin_batch_q);
            state_q <= ST_SELECT;
          end else begin
            if (batch_entry_valid[swapin_batch_q][swapin_offset_q[BATCH_OFF_W-1:0]]) begin
              port_v = batch_port[swapin_batch_q][swapin_offset_q[BATCH_OFF_W-1:0]];
              if (sram_free_count_q != 16'd0) begin
                alloc_sram_slot(alloc_slot_v);
                write_sram_cell(alloc_slot_v, port_v,
                                batch_rank[swapin_batch_q][swapin_offset_q[BATCH_OFF_W-1:0]],
                                batch_seq[swapin_batch_q][swapin_offset_q[BATCH_OFF_W-1:0]],
                                batch_payload[swapin_batch_q][swapin_offset_q[BATCH_OFF_W-1:0]]);
                port_cmd_valid[port_v] <= 1'b1;
                port_cmd_op[port_v] <= MP_CMD_MOVE_HBM_SRAM;
                port_cmd_sram_slot[port_v] <= alloc_slot_v;
                port_cmd_batch_id[port_v] <= swapin_batch_q;
                port_cmd_batch_offset[port_v] <= swapin_offset_q[BATCH_OFF_W-1:0];
                batch_entry_valid[swapin_batch_q][swapin_offset_q[BATCH_OFF_W-1:0]] <= 1'b0;
                batch_valid_count[swapin_batch_q] <= batch_valid_count[swapin_batch_q] - 16'd1;
                sram_count_q[port_v] <= sram_count_q[port_v] + 16'd1;
                hbm_count_q[port_v] <= hbm_count_q[port_v] - 16'd1;
                stat_swap_in <= stat_swap_in + 32'd1;
                swapin_offset_q <= swapin_offset_q + 1'b1;
                state_q <= ST_SWAPIN_WAIT;
              end
            end else begin
              swapin_offset_q <= swapin_offset_q + 1'b1;
            end
          end
        end

        ST_SWAPIN_DDR_ADDR: begin
          if (m_axi_arvalid && m_axi_arready) begin
            m_axi_arvalid <= 1'b0;
            state_q <= ST_SWAPIN_DDR_DATA;
          end
        end

        ST_SWAPIN_DDR_DATA: begin
          if (ddr_rd_fire_c) begin
            ddr_rd_error_v = (rd_stage_resp_q != 2'b00) |
                             (rd_stage_last_q != ((rd_stage_beat_q + 1'b1) == BATCH_SIZE));
            stat_ddr_read_beats <= stat_ddr_read_beats + 32'd1;
            if (rd_stage_entry_valid_q) begin
              port_v = rd_stage_port_q;
              if (ENABLE_DDR_META_CHECK) begin
                ddr_rd_error_v = ddr_rd_error_v |
                                 (unpack_ddr_port(rd_stage_data_q) != port_v) |
                                 (unpack_ddr_rank(rd_stage_data_q) != rd_stage_rank_q) |
                                 (unpack_ddr_seq(rd_stage_data_q) != rd_stage_seq_q);
              end
              alloc_sram_slot(alloc_slot_v);
              write_sram_cell(alloc_slot_v, port_v,
                              unpack_ddr_rank(rd_stage_data_q),
                              unpack_ddr_seq(rd_stage_data_q),
                              unpack_ddr_payload(rd_stage_data_q));
              port_cmd_valid[port_v] <= 1'b1;
              port_cmd_op[port_v] <= MP_CMD_MOVE_HBM_SRAM;
              port_cmd_sram_slot[port_v] <= alloc_slot_v;
              port_cmd_batch_id[port_v] <= swapin_batch_q;
              port_cmd_batch_offset[port_v] <= rd_stage_beat_q[BATCH_OFF_W-1:0];
              batch_entry_valid[swapin_batch_q][rd_stage_beat_q[BATCH_OFF_W-1:0]] <= 1'b0;
              batch_valid_count[swapin_batch_q] <= batch_valid_count[swapin_batch_q] - 16'd1;
              sram_count_q[port_v] <= sram_count_q[port_v] + 16'd1;
              hbm_count_q[port_v] <= hbm_count_q[port_v] - 16'd1;
              stat_swap_in <= stat_swap_in + 32'd1;
            end
            ddr_rd_error_q <= ddr_rd_error_q | ddr_rd_error_v;

            if ((rd_stage_beat_q + 1'b1) == BATCH_SIZE) begin
              free_batch_slot(swapin_batch_q);
              stat_ddr_read_batches <= stat_ddr_read_batches + 32'd1;
              state_q <= ST_SELECT;
            end else begin
              state_q <= ST_SWAPIN_DDR_DATA;
            end
          end
        end

        default: begin
          state_q <= ST_SELECT;
        end
      endcase
    end
  end

  logic unused_axi_ids;
  assign unused_axi_ids = ^m_axi_bid ^ ^m_axi_rid;
endmodule
