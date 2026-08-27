`timescale 1ns/1ps

module hestia_u200_top #(
  parameter int PORTS = 8,
  parameter int RANK_WIDTH = 10,
  parameter int SEQ_WIDTH = 32,
  parameter int PAYLOAD_WIDTH = 64,
  parameter int AXI_ADDR_WIDTH = 34,
  parameter int AXI_DATA_WIDTH = 512,
  parameter int AXI_ID_WIDTH = 4,
  parameter int CELL_COUNT_WIDTH = 4,
  parameter int SRAM_CELLS = 64,
  parameter int BATCH_SIZE = 4,
  parameter int BATCH_SLOTS = 16,
  parameter int PORT_QUEUE_DEPTH = 64,
  parameter int PACKET_SLOTS = PORT_QUEUE_DEPTH * PORTS,
  parameter int BBQ_BITMAP_WIDTH = (RANK_WIDTH <= 8) ? 16 : 32,
  parameter int MAX_CELL_COUNT = 4,
  parameter int CELL_COUNT_MODE = 1,
  parameter int MAX_PACKETS = 256,
  parameter int GEN_PERIOD_CYCLES = 1,
  parameter int DRAIN_AFTER_GENERATION_ONLY = 1,
  parameter int DRAIN_START_PACKETS = 0,
  parameter int DRAIN_PERIOD_CYCLES = 1,
  parameter int RANK_DIST = 0,
  parameter int HIGH_PRIORITY_PER1024 = 256,
  parameter int SWAP_IN_THRESHOLD = 16,
  parameter int SWAP_OUT_THRESHOLD = 48,
  parameter int TEST_MODE = 0,
  parameter int ALLOW_DROPS = 0,
  localparam int PORT_W = (PORTS <= 2) ? 1 : $clog2(PORTS),
  localparam int AXI_KEEP_WIDTH = AXI_DATA_WIDTH / 8
) (
  input  logic                         clk,
  input  logic                         resetn,
  input  logic                         enable,

  output logic [AXI_ID_WIDTH-1:0]      m_axi_awid,
  output logic [AXI_ADDR_WIDTH-1:0]    m_axi_awaddr,
  output logic [7:0]                   m_axi_awlen,
  output logic [2:0]                   m_axi_awsize,
  output logic [1:0]                   m_axi_awburst,
  output logic                         m_axi_awlock,
  output logic [3:0]                   m_axi_awcache,
  output logic [2:0]                   m_axi_awprot,
  output logic [3:0]                   m_axi_awqos,
  output logic                         m_axi_awvalid,
  input  logic                         m_axi_awready,
  output logic [AXI_DATA_WIDTH-1:0]    m_axi_wdata,
  output logic [AXI_KEEP_WIDTH-1:0]    m_axi_wstrb,
  output logic                         m_axi_wlast,
  output logic                         m_axi_wvalid,
  input  logic                         m_axi_wready,
  input  logic [AXI_ID_WIDTH-1:0]      m_axi_bid,
  input  logic [1:0]                   m_axi_bresp,
  input  logic                         m_axi_bvalid,
  output logic                         m_axi_bready,
  output logic [AXI_ID_WIDTH-1:0]      m_axi_arid,
  output logic [AXI_ADDR_WIDTH-1:0]    m_axi_araddr,
  output logic [7:0]                   m_axi_arlen,
  output logic [2:0]                   m_axi_arsize,
  output logic [1:0]                   m_axi_arburst,
  output logic                         m_axi_arlock,
  output logic [3:0]                   m_axi_arcache,
  output logic [2:0]                   m_axi_arprot,
  output logic [3:0]                   m_axi_arqos,
  output logic                         m_axi_arvalid,
  input  logic                         m_axi_arready,
  input  logic [AXI_ID_WIDTH-1:0]      m_axi_rid,
  input  logic [AXI_DATA_WIDTH-1:0]    m_axi_rdata,
  input  logic [1:0]                   m_axi_rresp,
  input  logic                         m_axi_rlast,
  input  logic                         m_axi_rvalid,
  output logic                         m_axi_rready,

  output logic                         done,
  output logic [767:0]                 dbg_bus,
  output logic [511:0]                 dbg_light_bus,
  output logic [31:0]                  dbg_generated,
  output logic [31:0]                  dbg_dequeued,
  output logic [31:0]                  dbg_sram_dequeue,
  output logic [31:0]                  dbg_rank_order_errors,
  output logic [31:0]                  dbg_run_cycles,
  output logic [31:0]                  dbg_sram_admit,
  output logic [31:0]                  dbg_ddr_admit,
  output logic [31:0]                  dbg_swap_out,
  output logic [31:0]                  dbg_swap_in,
  output logic [31:0]                  dbg_direct_ddr_dequeue,
  output logic [31:0]                  dbg_drop,
  output logic [31:0]                  dbg_ddr_write_beats,
  output logic [31:0]                  dbg_ddr_read_beats,
  output logic [31:0]                  dbg_ddr_write_batches,
  output logic [31:0]                  dbg_ddr_read_batches,
  output logic [15:0]                  dbg_global_sram_occupancy,
  output logic [15:0]                  dbg_global_ddr_occupancy,
  output logic [7:0]                   dbg_ddr_state,
  output logic                         dbg_ddr_wr_error,
  output logic                         dbg_ddr_rd_error
);
  localparam int DRAIN_PERIOD_W = (DRAIN_PERIOD_CYCLES <= 1) ? 1 : $clog2(DRAIN_PERIOD_CYCLES);

  logic gen_valid;
  logic gen_ready;
  logic [PORT_W-1:0] gen_port;
  logic [RANK_WIDTH-1:0] gen_rank;
  logic [SEQ_WIDTH-1:0] gen_seq;
  logic [CELL_COUNT_WIDTH-1:0] gen_cell_count;
  logic [PAYLOAD_WIDTH-1:0] gen_payload;
  logic gen_done;

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
  logic [31:0] stat_ddr_write_beats;
  logic [31:0] stat_ddr_read_beats;
  logic [31:0] stat_ddr_write_batches;
  logic [31:0] stat_ddr_read_batches;
  logic [31:0] stat_sram_dequeue;
  logic [15:0] core_sram_occupancy;
  logic [15:0] core_hbm_occupancy;
  logic [PORTS*16-1:0] dbg_sram_count_flat;
  logic [PORTS*16-1:0] dbg_hbm_count_flat;
  logic [7:0] core_dbg_ddr_state;
  logic core_dbg_ddr_wr_error;
  logic core_dbg_ddr_rd_error;

  logic [DRAIN_PERIOD_W-1:0] drain_period_q;
  logic drain_period_ready;
  logic [31:0] run_cycles_q;
  logic [31:0] output_fire_cycles_q;
  logic [31:0] drain_ready_cycles_q;
  logic [31:0] rank_order_errors_q;
  logic [PORTS-1:0] rank_prev_valid_q;
  logic [RANK_WIDTH-1:0] last_rank_q [0:PORTS-1];
  logic [7:0] last_seq_low_q [0:PORTS-1];
  logic [31:0] port_dequeued_q [0:PORTS-1];
  logic gen_enable;
  logic [15:0] cfg_swap_in_threshold;
  logic [15:0] cfg_swap_out_threshold;
  logic drop_ok;
  logic done_ready;
  logic [PORTS*RANK_WIDTH-1:0] last_rank_flat;
  logic [PORTS*8-1:0] last_seq_low_flat;

  typedef enum logic [2:0] {
    TM_FILL_A,
    TM_WAIT_A,
    TM_DIRECT,
    TM_SWAPIN,
    TM_DRAIN
  } test_mode_state_t;
  test_mode_state_t test_mode_q;

  hestia_synthetic_packet_gen #(
    .PORTS(PORTS),
    .RANK_WIDTH(RANK_WIDTH),
    .SEQ_WIDTH(SEQ_WIDTH),
    .PAYLOAD_WIDTH(PAYLOAD_WIDTH),
    .CELL_COUNT_WIDTH(CELL_COUNT_WIDTH),
    .MAX_CELL_COUNT(MAX_CELL_COUNT),
    .CELL_COUNT_MODE(CELL_COUNT_MODE),
    .MAX_PACKETS(MAX_PACKETS),
    .PERIOD_CYCLES(GEN_PERIOD_CYCLES),
    .RANK_DIST(RANK_DIST),
    .HIGH_PRIORITY_PER1024(HIGH_PRIORITY_PER1024)
  ) gen_i (
    .clk(clk),
    .resetn(resetn),
    .enable(gen_enable),
    .ready(gen_ready),
    .valid(gen_valid),
    .port(gen_port),
    .rank(gen_rank),
    .seq(gen_seq),
    .cell_count(gen_cell_count),
    .payload(gen_payload),
    .done(gen_done)
  );

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
    .ENABLE_DDR_META_CHECK(1'b1)
  ) core_i (
    .clk(clk),
    .resetn(resetn),
    .enable(enable),
    .cfg_swap_in_threshold(cfg_swap_in_threshold),
    .cfg_swap_out_threshold(cfg_swap_out_threshold),
    .s_pkt_valid(gen_valid),
    .s_pkt_ready(gen_ready),
    .s_pkt_port(gen_port),
    .s_pkt_rank(gen_rank),
    .s_pkt_seq(gen_seq),
    .s_pkt_cell_count(gen_cell_count),
    .s_pkt_payload(gen_payload),
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
    .dbg_global_sram_occupancy(core_sram_occupancy),
    .dbg_global_hbm_occupancy(core_hbm_occupancy),
    .dbg_sram_count_flat(dbg_sram_count_flat),
    .dbg_hbm_count_flat(dbg_hbm_count_flat),
    .dbg_ddr_state(core_dbg_ddr_state),
    .dbg_ddr_wr_error(core_dbg_ddr_wr_error),
    .dbg_ddr_rd_error(core_dbg_ddr_rd_error)
  );

  assign drain_period_ready = (DRAIN_PERIOD_CYCLES <= 1) ? 1'b1 : (drain_period_q == '0);
  assign m_pkt_ready = {PORTS{drain_period_ready}};
  assign drop_ok = (ALLOW_DROPS != 0) || (stat_drop == 32'd0);
  assign stat_sram_dequeue = stat_dequeued - stat_direct_hbm_dequeue;
  assign done_ready = gen_done && !gen_valid && (stat_generated == 32'(MAX_PACKETS)) &&
                      (m_pkt_valid == '0) &&
                      ((stat_dequeued + stat_drop) == stat_generated) &&
                      (core_sram_occupancy == 16'd0) &&
                      (core_hbm_occupancy == 16'd0) &&
                      (stat_ddr_write_batches != 32'd0) &&
                      (stat_ddr_read_beats != 32'd0) &&
                      drop_ok &&
                      ((TEST_MODE == 0) ||
                       ((test_mode_q == TM_DRAIN) &&
                        (stat_direct_hbm_dequeue != 32'd0) &&
                        (stat_ddr_read_batches != 32'd0) &&
                        (stat_swap_in != 32'd0)));

  always_comb begin
    gen_enable = enable;
    cfg_swap_in_threshold = 16'(SWAP_IN_THRESHOLD);
    cfg_swap_out_threshold = 16'(SWAP_OUT_THRESHOLD);
    dequeue_enable = (DRAIN_AFTER_GENERATION_ONLY != 0) ? {PORTS{gen_done}} :
                     {PORTS{enable && (stat_generated >= 32'(DRAIN_START_PACKETS))}};

    if (TEST_MODE != 0) begin
      gen_enable = 1'b0;
      cfg_swap_in_threshold = 16'd0;
      cfg_swap_out_threshold = 16'd0;
      dequeue_enable = '0;

      unique case (test_mode_q)
        TM_FILL_A: begin
          gen_enable = enable && !gen_done;
        end

        TM_DIRECT: begin
          cfg_swap_out_threshold = 16'd1000;
          dequeue_enable = {PORTS{enable}};
        end

        TM_SWAPIN: begin
          cfg_swap_in_threshold = 16'(SWAP_IN_THRESHOLD);
          cfg_swap_out_threshold = 16'(SWAP_OUT_THRESHOLD);
        end

        TM_DRAIN: begin
          cfg_swap_out_threshold = 16'(SWAP_OUT_THRESHOLD);
          dequeue_enable = {PORTS{enable}};
        end

        default: begin
        end
      endcase
    end
  end

  function automatic logic [RANK_WIDTH-1:0] out_rank(input int port_i);
    begin
      out_rank = m_pkt_rank[port_i*RANK_WIDTH +: RANK_WIDTH];
    end
  endfunction

  genvar dbg_gi;
  generate
    for (dbg_gi = 0; dbg_gi < PORTS; dbg_gi = dbg_gi + 1) begin : g_dbg_flat
      assign last_rank_flat[dbg_gi*RANK_WIDTH +: RANK_WIDTH] = last_rank_q[dbg_gi];
      assign last_seq_low_flat[dbg_gi*8 +: 8] = last_seq_low_q[dbg_gi];
    end
  endgenerate

  integer pi;
  always_ff @(posedge clk) begin
    logic [31:0] fire_count_v;
    logic [31:0] rank_error_count_v;
    if (!resetn) begin
      drain_period_q <= '0;
      run_cycles_q <= 32'd0;
      output_fire_cycles_q <= 32'd0;
      drain_ready_cycles_q <= 32'd0;
      rank_order_errors_q <= 32'd0;
      rank_prev_valid_q <= '0;
      test_mode_q <= TM_FILL_A;
      done <= 1'b0;
      for (pi = 0; pi < PORTS; pi = pi + 1) begin
        last_rank_q[pi] <= '0;
        last_seq_low_q[pi] <= 8'd0;
        port_dequeued_q[pi] <= 32'd0;
      end
    end else begin
      if (DRAIN_PERIOD_CYCLES > 1) begin
        if (drain_period_q == DRAIN_PERIOD_CYCLES-1) begin
          drain_period_q <= '0;
        end else begin
          drain_period_q <= drain_period_q + 1'b1;
        end
      end else begin
        drain_period_q <= '0;
      end

      if (enable && !done) begin
        fire_count_v = 32'd0;
        rank_error_count_v = 32'd0;
        run_cycles_q <= run_cycles_q + 32'd1;
        if (drain_period_ready) begin
          drain_ready_cycles_q <= drain_ready_cycles_q + 32'd1;
        end
        for (pi = 0; pi < PORTS; pi = pi + 1) begin
          if (m_pkt_valid[pi] && m_pkt_ready[pi]) begin
            fire_count_v = fire_count_v + 32'd1;
            port_dequeued_q[pi] <= port_dequeued_q[pi] + 32'd1;
            if (rank_prev_valid_q[pi] && (out_rank(pi) < last_rank_q[pi])) begin
              rank_error_count_v = rank_error_count_v + 32'd1;
            end
            rank_prev_valid_q[pi] <= 1'b1;
            last_rank_q[pi] <= out_rank(pi);
            last_seq_low_q[pi] <= m_pkt_seq[pi*SEQ_WIDTH +: 8];
          end
        end
        output_fire_cycles_q <= output_fire_cycles_q + fire_count_v;
        rank_order_errors_q <= rank_order_errors_q + rank_error_count_v;

        if (TEST_MODE != 0) begin
          unique case (test_mode_q)
            TM_FILL_A: begin
              if (gen_done && !gen_valid) begin
                test_mode_q <= TM_WAIT_A;
              end
            end

            TM_WAIT_A: begin
              if ((core_hbm_occupancy != 16'd0) && (stat_ddr_write_batches != 32'd0)) begin
                test_mode_q <= TM_DIRECT;
              end
            end

            TM_DIRECT: begin
              if ((stat_direct_hbm_dequeue != 32'd0) && (stat_ddr_read_beats != 32'd0)) begin
                test_mode_q <= TM_SWAPIN;
              end
            end

            TM_SWAPIN: begin
              if ((stat_ddr_read_batches != 32'd0) && (stat_swap_in != 32'd0)) begin
                test_mode_q <= TM_DRAIN;
              end
            end

            default: begin
              test_mode_q <= TM_DRAIN;
            end
          endcase
        end

        if (done_ready) begin
          done <= 1'b1;
        end
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!resetn) begin
      dbg_generated <= 32'd0;
      dbg_dequeued <= 32'd0;
      dbg_sram_dequeue <= 32'd0;
      dbg_rank_order_errors <= 32'd0;
      dbg_run_cycles <= 32'd0;
      dbg_sram_admit <= 32'd0;
      dbg_ddr_admit <= 32'd0;
      dbg_swap_out <= 32'd0;
      dbg_swap_in <= 32'd0;
      dbg_direct_ddr_dequeue <= 32'd0;
      dbg_drop <= 32'd0;
      dbg_ddr_write_beats <= 32'd0;
      dbg_ddr_read_beats <= 32'd0;
      dbg_ddr_write_batches <= 32'd0;
      dbg_ddr_read_batches <= 32'd0;
      dbg_global_sram_occupancy <= 16'd0;
      dbg_global_ddr_occupancy <= 16'd0;
      dbg_ddr_state <= 8'd0;
      dbg_ddr_wr_error <= 1'b0;
      dbg_ddr_rd_error <= 1'b0;
      dbg_bus <= 768'd0;
      dbg_light_bus <= 512'd0;
    end else begin
      dbg_generated <= stat_generated;
      dbg_dequeued <= stat_dequeued;
      dbg_sram_dequeue <= stat_sram_dequeue;
      dbg_rank_order_errors <= rank_order_errors_q;
      dbg_run_cycles <= run_cycles_q;
      dbg_sram_admit <= stat_sram_admit;
      dbg_ddr_admit <= stat_hbm_admit;
      dbg_swap_out <= stat_swap_out;
      dbg_swap_in <= stat_swap_in;
      dbg_direct_ddr_dequeue <= stat_direct_hbm_dequeue;
      dbg_drop <= stat_drop;
      dbg_ddr_write_beats <= stat_ddr_write_beats;
      dbg_ddr_read_beats <= stat_ddr_read_beats;
      dbg_ddr_write_batches <= stat_ddr_write_batches;
      dbg_ddr_read_batches <= stat_ddr_read_batches;
      dbg_global_sram_occupancy <= core_sram_occupancy;
      dbg_global_ddr_occupancy <= core_hbm_occupancy;
      dbg_ddr_state <= core_dbg_ddr_state;
      dbg_ddr_wr_error <= core_dbg_ddr_wr_error;
      dbg_ddr_rd_error <= core_dbg_ddr_rd_error;

      dbg_bus <= {
        8'd0,
        dbg_sram_count_flat,
        last_seq_low_flat,
        last_rank_flat,
        4'd0,
        gen_done,
        core_dbg_ddr_rd_error,
        core_dbg_ddr_wr_error,
        done,
        dequeue_enable,
        m_pkt_ready,
        m_pkt_valid,
        core_dbg_ddr_state,
        core_hbm_occupancy,
        core_sram_occupancy,
        run_cycles_q,
        stat_ddr_read_beats,
        stat_ddr_write_beats,
        stat_ddr_read_batches,
        stat_ddr_write_batches,
        stat_swap_in,
        stat_swap_out,
        stat_drop,
        rank_order_errors_q,
        stat_direct_hbm_dequeue,
        stat_sram_dequeue,
        stat_dequeued,
        stat_generated
      };

      dbg_light_bus <= {
        16'd0,
        last_rank_flat,
        4'd0,
        gen_done,
        core_dbg_ddr_rd_error,
        core_dbg_ddr_wr_error,
        done,
        m_pkt_ready,
        m_pkt_valid,
        core_dbg_ddr_state,
        core_hbm_occupancy,
        core_sram_occupancy,
        run_cycles_q,
        stat_ddr_read_batches,
        stat_ddr_write_batches,
        stat_swap_in,
        stat_swap_out,
        stat_drop,
        rank_order_errors_q,
        stat_direct_hbm_dequeue,
        stat_sram_dequeue,
        stat_dequeued,
        stat_generated
      };
    end
  end

  logic unused_payload_reduce;
  assign unused_payload_reduce = ^m_pkt_seq ^ ^m_pkt_cell_count ^ ^m_pkt_payload ^ ^stat_batch_submit;
endmodule
