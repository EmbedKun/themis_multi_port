`timescale 1ns/1ps

import hestia_pkg::*;

module tb_hestia_baseline_shared;
`ifndef BASELINE_POLICY_MODE
`define BASELINE_POLICY_MODE 0
`endif

  localparam int POLICY_MODE = `BASELINE_POLICY_MODE;
  localparam int PORTS = 4;
  localparam int RANK_WIDTH = 6;
  localparam int SEQ_WIDTH = 16;
  localparam int PAYLOAD_WIDTH = 32;
  localparam int CELL_COUNT_WIDTH = 4;
  localparam int SRAM_CELLS = 32;
  localparam int PACKET_SLOTS = 64;
  localparam int BBQ_BITMAP_WIDTH = 8;
  localparam int ALPHA_SHIFT_WIDTH = 4;
  localparam int MAX_PACKETS = 96;
  localparam int PORT_W = $clog2(PORTS);

  logic clk = 1'b0;
  logic resetn = 1'b0;
  always #2 clk = ~clk;

  logic enable;
  logic [ALPHA_SHIFT_WIDTH-1:0] cfg_alpha_shift;
  logic cfg_reclaim_enable;
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
  logic [31:0] stat_generated;
  logic [31:0] stat_admitted;
  logic [31:0] stat_dequeued;
  logic [31:0] stat_drop;
  logic [31:0] stat_evicted;
  logic [31:0] stat_reclaim;
  logic [31:0] stat_obm_pushout;
  logic [31:0] stat_dt_drop;
  logic [15:0] dbg_global_occupancy;
  logic [15:0] dbg_free_cells;
  logic [PORTS*16-1:0] dbg_port_occupancy_flat;

  hestia_baseline_shared_core #(
    .POLICY_MODE(POLICY_MODE),
    .PORTS(PORTS),
    .RANK_WIDTH(RANK_WIDTH),
    .SEQ_WIDTH(SEQ_WIDTH),
    .PAYLOAD_WIDTH(PAYLOAD_WIDTH),
    .CELL_COUNT_WIDTH(CELL_COUNT_WIDTH),
    .SRAM_CELLS(SRAM_CELLS),
    .PACKET_SLOTS(PACKET_SLOTS),
    .BBQ_BITMAP_WIDTH(BBQ_BITMAP_WIDTH),
    .ALPHA_SHIFT_WIDTH(ALPHA_SHIFT_WIDTH)
  ) dut (
    .clk(clk),
    .resetn(resetn),
    .enable(enable),
    .cfg_alpha_shift(cfg_alpha_shift),
    .cfg_reclaim_enable(cfg_reclaim_enable),
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
    .stat_generated(stat_generated),
    .stat_admitted(stat_admitted),
    .stat_dequeued(stat_dequeued),
    .stat_drop(stat_drop),
    .stat_evicted(stat_evicted),
    .stat_reclaim(stat_reclaim),
    .stat_obm_pushout(stat_obm_pushout),
    .stat_dt_drop(stat_dt_drop),
    .dbg_global_occupancy(dbg_global_occupancy),
    .dbg_free_cells(dbg_free_cells),
    .dbg_port_occupancy_flat(dbg_port_occupancy_flat)
  );

  logic seen_q [0:PORTS-1];
  logic [RANK_WIDTH-1:0] last_rank_q [0:PORTS-1];
  logic [SEQ_WIDTH-1:0] last_seq_q [0:PORTS-1];
  logic [31:0] observed_dequeue_q;

  task automatic tick(input int cycles);
    int ti;
    begin
      for (ti = 0; ti < cycles; ti = ti + 1) begin
        @(posedge clk);
      end
    end
  endtask

  task automatic send_pkt(
    input int port_i,
    input int rank_i,
    input int seq_i,
    input int cells_i
  );
    int guard;
    begin
      guard = 0;
      while (!s_pkt_ready) begin
        tick(1);
        guard = guard + 1;
        if (guard > 5000) begin
          $fatal(1, "Timeout waiting for s_pkt_ready at seq=%0d", seq_i);
        end
      end

      s_pkt_port = port_i[PORT_W-1:0];
      s_pkt_rank = rank_i[RANK_WIDTH-1:0];
      s_pkt_seq = seq_i[SEQ_WIDTH-1:0];
      s_pkt_cell_count = cells_i[CELL_COUNT_WIDTH-1:0];
      s_pkt_payload = {16'hb500, seq_i[15:0]};
      s_pkt_valid = 1'b1;
      tick(1);
      while (!s_pkt_ready) begin
        tick(1);
      end
      s_pkt_valid = 1'b0;
      s_pkt_port = '0;
      s_pkt_rank = '0;
      s_pkt_seq = '0;
      s_pkt_cell_count = '0;
      s_pkt_payload = '0;
    end
  endtask

  integer mi;
  logic [RANK_WIDTH-1:0] out_rank_v;
  logic [SEQ_WIDTH-1:0] out_seq_v;
  always_ff @(posedge clk) begin
    if (!resetn) begin
      observed_dequeue_q <= 32'd0;
      for (mi = 0; mi < PORTS; mi = mi + 1) begin
        seen_q[mi] <= 1'b0;
        last_rank_q[mi] <= '0;
        last_seq_q[mi] <= '0;
      end
    end else begin
      for (mi = 0; mi < PORTS; mi = mi + 1) begin
        if (m_pkt_valid[mi] && m_pkt_ready[mi]) begin
          out_rank_v = m_pkt_rank[mi*RANK_WIDTH +: RANK_WIDTH];
          out_seq_v = m_pkt_seq[mi*SEQ_WIDTH +: SEQ_WIDTH];
          if (seen_q[mi]) begin
            if ((out_rank_v < last_rank_q[mi]) ||
                ((out_rank_v == last_rank_q[mi]) && (out_seq_v < last_seq_q[mi]))) begin
              $fatal(1, "Rank order violation policy=%0d port=%0d rank=%0d last=%0d seq=%0d last_seq=%0d",
                     POLICY_MODE, mi, out_rank_v, last_rank_q[mi],
                     out_seq_v, last_seq_q[mi]);
            end
          end
          seen_q[mi] <= 1'b1;
          last_rank_q[mi] <= out_rank_v;
          last_seq_q[mi] <= out_seq_v;
          observed_dequeue_q <= observed_dequeue_q + 32'd1;
        end
      end
    end
  end

  integer si;
  integer port_v;
  integer rank_v;
  integer cells_v;
  integer wait_i;
  initial begin
    enable = 1'b0;
    cfg_alpha_shift = 4'd3;
    cfg_reclaim_enable = 1'b1;
    s_pkt_valid = 1'b0;
    s_pkt_port = '0;
    s_pkt_rank = '0;
    s_pkt_seq = '0;
    s_pkt_cell_count = '0;
    s_pkt_payload = '0;
    dequeue_enable = '0;
    m_pkt_ready = '1;

    tick(5);
    resetn = 1'b1;
    enable = 1'b1;
    while (!s_pkt_ready) begin
      tick(1);
    end

    for (si = 0; si < MAX_PACKETS; si = si + 1) begin
      if (si < 36) begin
        port_v = 0;
      end else begin
        port_v = 1 + (si % (PORTS-1));
      end
      rank_v = (si * 11 + port_v * 7) % (1 << RANK_WIDTH);
      cells_v = (si % 4) + 1;
      send_pkt(port_v, rank_v, si, cells_v);
    end

    tick(800);
    dequeue_enable = '1;

    for (wait_i = 0; wait_i < 50000; wait_i = wait_i + 1) begin
      tick(1);
      if ((stat_generated == MAX_PACKETS) &&
          ((stat_admitted + stat_drop) == stat_generated) &&
          ((stat_dequeued + stat_evicted) == stat_admitted) &&
          (observed_dequeue_q == stat_dequeued) &&
          (dbg_global_occupancy == 16'd0)) begin
        wait_i = 50000;
      end
    end

    if (stat_generated !== 32'(MAX_PACKETS)) begin
      $fatal(1, "Generated mismatch policy=%0d got=%0d expected=%0d",
             POLICY_MODE, stat_generated, MAX_PACKETS);
    end
    if ((stat_admitted + stat_drop) !== stat_generated) begin
      $fatal(1, "Admission accounting mismatch policy=%0d admitted=%0d drop=%0d generated=%0d",
             POLICY_MODE, stat_admitted, stat_drop, stat_generated);
    end
    if ((stat_dequeued + stat_evicted) !== stat_admitted) begin
      $fatal(1, "Departure accounting mismatch policy=%0d dequeued=%0d evicted=%0d admitted=%0d",
             POLICY_MODE, stat_dequeued, stat_evicted, stat_admitted);
    end
    if (observed_dequeue_q !== stat_dequeued) begin
      $fatal(1, "Observed dequeue mismatch policy=%0d observed=%0d stat=%0d",
             POLICY_MODE, observed_dequeue_q, stat_dequeued);
    end
    if (dbg_global_occupancy !== 16'd0 || dbg_free_cells !== 16'(SRAM_CELLS)) begin
      $fatal(1, "Buffer not empty policy=%0d occ=%0d free=%0d",
             POLICY_MODE, dbg_global_occupancy, dbg_free_cells);
    end
    if ((POLICY_MODE == 0) && (stat_dt_drop == 32'd0)) begin
      $fatal(1, "DT baseline did not exercise threshold drops");
    end
    if (((POLICY_MODE == 1) || (POLICY_MODE == 2)) && (stat_reclaim == 32'd0)) begin
      $fatal(1, "Occamy baseline did not exercise reclaim");
    end
    if ((POLICY_MODE == 3) && (stat_obm_pushout == 32'd0)) begin
      $fatal(1, "OBM baseline did not exercise push-out");
    end

    $display("BASELINE_RESULT policy=%0d generated=%0d admitted=%0d dequeued=%0d drop=%0d evicted=%0d reclaim=%0d obm_pushout=%0d dt_drop=%0d",
             POLICY_MODE, stat_generated, stat_admitted, stat_dequeued,
             stat_drop, stat_evicted, stat_reclaim, stat_obm_pushout, stat_dt_drop);
    $display("PASS: Hestia baseline shared-buffer regression policy=%0d", POLICY_MODE);
    $finish;
  end
endmodule
