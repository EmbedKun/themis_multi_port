`timescale 1ns/1ps

module hestia_hw_top #(
  parameter int PORTS = 8,
  parameter int RANK_WIDTH = 10,
  parameter int SEQ_WIDTH = 32,
  parameter int PAYLOAD_WIDTH = 64,
  parameter int SRAM_CELLS = 64,
  parameter int BATCH_SIZE = 4,
  parameter int BATCH_SLOTS = 16,
  parameter int PORT_QUEUE_DEPTH = 64,
  parameter int MAX_PACKETS = 256,
  parameter int GEN_PERIOD_CYCLES = 1,
  parameter int DRAIN_AFTER_GENERATION_ONLY = 1,
  parameter int DRAIN_PERIOD_CYCLES = 1,
  parameter int RANK_DIST = 0,
  parameter int HIGH_PRIORITY_PER1024 = 256,
  parameter int SWAP_IN_THRESHOLD = 16,
  parameter int SWAP_OUT_THRESHOLD = 48,
  localparam int PORT_W = (PORTS <= 2) ? 1 : $clog2(PORTS)
) (
  input  logic                         clk,
  input  logic                         resetn,
  input  logic                         enable,
  output logic                         done,
  output logic [767:0]                 dbg_bus,
  output logic [31:0]                  dbg_generated,
  output logic [31:0]                  dbg_dequeued,
  output logic [31:0]                  dbg_rank_order_errors,
  output logic [31:0]                  dbg_run_cycles
);
  localparam int DRAIN_PERIOD_W = (DRAIN_PERIOD_CYCLES <= 1) ? 1 : $clog2(DRAIN_PERIOD_CYCLES);

  logic gen_valid;
  logic gen_ready;
  logic [PORT_W-1:0] gen_port;
  logic [RANK_WIDTH-1:0] gen_rank;
  logic [SEQ_WIDTH-1:0] gen_seq;
  logic [PAYLOAD_WIDTH-1:0] gen_payload;
  logic gen_done;

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

  logic [DRAIN_PERIOD_W-1:0] drain_period_q;
  logic drain_period_ready;
  logic [31:0] run_cycles_q;
  logic [31:0] output_fire_cycles_q;
  logic [31:0] drain_ready_cycles_q;
  logic [31:0] rank_order_errors_q;
  logic [PORTS-1:0] rank_prev_valid_q;
  logic [RANK_WIDTH-1:0] last_rank_q [0:PORTS-1];
  logic [31:0] port_dequeued_q [0:PORTS-1];

  hestia_synthetic_packet_gen #(
    .PORTS(PORTS),
    .RANK_WIDTH(RANK_WIDTH),
    .SEQ_WIDTH(SEQ_WIDTH),
    .PAYLOAD_WIDTH(PAYLOAD_WIDTH),
    .MAX_PACKETS(MAX_PACKETS),
    .PERIOD_CYCLES(GEN_PERIOD_CYCLES),
    .RANK_DIST(RANK_DIST),
    .HIGH_PRIORITY_PER1024(HIGH_PRIORITY_PER1024)
  ) gen_i (
    .clk(clk),
    .resetn(resetn),
    .enable(enable),
    .ready(gen_ready),
    .valid(gen_valid),
    .port(gen_port),
    .rank(gen_rank),
    .seq(gen_seq),
    .payload(gen_payload),
    .done(gen_done)
  );

  hestia_core #(
    .PORTS(PORTS),
    .RANK_WIDTH(RANK_WIDTH),
    .SEQ_WIDTH(SEQ_WIDTH),
    .PAYLOAD_WIDTH(PAYLOAD_WIDTH),
    .SRAM_CELLS(SRAM_CELLS),
    .BATCH_SIZE(BATCH_SIZE),
    .BATCH_SLOTS(BATCH_SLOTS),
    .PORT_QUEUE_DEPTH(PORT_QUEUE_DEPTH)
  ) core_i (
    .clk(clk),
    .resetn(resetn),
    .enable(enable),
    .cfg_swap_in_threshold(16'(SWAP_IN_THRESHOLD)),
    .cfg_swap_out_threshold(16'(SWAP_OUT_THRESHOLD)),
    .s_pkt_valid(gen_valid),
    .s_pkt_ready(gen_ready),
    .s_pkt_port(gen_port),
    .s_pkt_rank(gen_rank),
    .s_pkt_seq(gen_seq),
    .s_pkt_payload(gen_payload),
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

  assign drain_period_ready = (DRAIN_PERIOD_CYCLES <= 1) ? 1'b1 : (drain_period_q == '0);
  assign dequeue_enable = (DRAIN_AFTER_GENERATION_ONLY != 0) ? {PORTS{gen_done}} : {PORTS{enable}};
  assign m_pkt_ready = {PORTS{drain_period_ready}};

  function automatic logic [RANK_WIDTH-1:0] out_rank(input int port_i);
    begin
      out_rank = m_pkt_rank[port_i*RANK_WIDTH +: RANK_WIDTH];
    end
  endfunction

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
      done <= 1'b0;
      for (pi = 0; pi < PORTS; pi = pi + 1) begin
        last_rank_q[pi] <= '0;
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
          end
        end
        output_fire_cycles_q <= output_fire_cycles_q + fire_count_v;
        rank_order_errors_q <= rank_order_errors_q + rank_error_count_v;

        if (gen_done && !gen_valid && (m_pkt_valid == '0) &&
            ((stat_dequeued + stat_drop) == stat_generated) &&
            (dbg_global_sram_occupancy == 16'd0) &&
            (dbg_global_hbm_occupancy == 16'd0)) begin
          done <= 1'b1;
        end
      end
    end
  end

  assign dbg_generated = stat_generated;
  assign dbg_dequeued = stat_dequeued;
  assign dbg_rank_order_errors = rank_order_errors_q;
  assign dbg_run_cycles = run_cycles_q;

  assign dbg_bus = {
    272'd0,
    rank_order_errors_q,
    drain_ready_cycles_q,
    output_fire_cycles_q,
    run_cycles_q,
    port_dequeued_q[7],
    port_dequeued_q[6],
    port_dequeued_q[5],
    port_dequeued_q[4],
    port_dequeued_q[3],
    port_dequeued_q[2],
    port_dequeued_q[1],
    port_dequeued_q[0],
    15'd0,
    done,
    dbg_hbm_count_flat,
    dbg_sram_count_flat,
    dbg_global_hbm_occupancy,
    dbg_global_sram_occupancy,
    stat_drop,
    stat_direct_hbm_dequeue,
    stat_swap_in,
    stat_swap_out,
    stat_hbm_admit,
    stat_sram_admit,
    stat_dequeued,
    stat_generated
  };

  logic unused_payload_reduce;
  assign unused_payload_reduce = ^m_pkt_seq ^ ^m_pkt_payload;
endmodule
