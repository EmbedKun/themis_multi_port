`timescale 1ns/1ps

module hestia_synthetic_packet_gen #(
  parameter int PORTS = 8,
  parameter int RANK_WIDTH = 10,
  parameter int SEQ_WIDTH = 32,
  parameter int PAYLOAD_WIDTH = 64,
  parameter int CELL_COUNT_WIDTH = 4,
  parameter int MAX_CELL_COUNT = 1,
  parameter int CELL_COUNT_MODE = 0,
  parameter int MAX_PACKETS = 256,
  parameter int PERIOD_CYCLES = 1,
  parameter int RANK_DIST = 0,
  parameter int HIGH_PRIORITY_PER1024 = 256,
  localparam int PORT_W = (PORTS <= 2) ? 1 : $clog2(PORTS)
) (
  input  logic                         clk,
  input  logic                         resetn,
  input  logic                         enable,
  input  logic                         ready,
  output logic                         valid,
  output logic [PORT_W-1:0]            port,
  output logic [RANK_WIDTH-1:0]        rank,
  output logic [SEQ_WIDTH-1:0]         seq,
  output logic [CELL_COUNT_WIDTH-1:0]  cell_count,
  output logic [PAYLOAD_WIDTH-1:0]     payload,
  output logic                         done
);
  localparam int PERIOD_W = (PERIOD_CYCLES <= 1) ? 1 : $clog2(PERIOD_CYCLES);
  localparam int SAFE_MAX_CELL_COUNT = (MAX_CELL_COUNT <= 1) ? 1 : MAX_CELL_COUNT;
  logic [PERIOD_W-1:0] period_q;
  logic [31:0] lfsr_q;
  logic [SEQ_WIDTH-1:0] seq_q;

  function automatic logic [31:0] xorshift32(input logic [31:0] x);
    logic [31:0] y;
    begin
      y = x ^ (x << 13);
      y = y ^ (y >> 17);
      y = y ^ (y << 5);
      xorshift32 = y;
    end
  endfunction

  function automatic logic [RANK_WIDTH-1:0] make_rank(
    input logic [31:0] rnd_i,
    input logic [SEQ_WIDTH-1:0] seq_i
  );
    logic [RANK_WIDTH-1:0] rank_v;
    begin
      unique case (RANK_DIST)
        1: begin
          if (rnd_i[9:0] < 10'(HIGH_PRIORITY_PER1024)) begin
            rank_v = rnd_i[RANK_WIDTH-1:0] & RANK_WIDTH'(16'h000f);
          end else begin
            rank_v = rnd_i[RANK_WIDTH-1:0];
          end
        end
        2: begin
          rank_v = ~seq_i[RANK_WIDTH-1:0];
        end
        3: begin
          if (SEQ_WIDTH > RANK_WIDTH) begin
            rank_v = (|seq_i[SEQ_WIDTH-1:RANK_WIDTH]) ? '1 : seq_i[RANK_WIDTH-1:0];
          end else begin
            rank_v = RANK_WIDTH'(seq_i);
          end
        end
        default: begin
          rank_v = rnd_i[RANK_WIDTH-1:0];
        end
      endcase
      make_rank = rank_v;
    end
  endfunction

  function automatic logic [CELL_COUNT_WIDTH-1:0] make_cell_count(
    input logic [31:0] rnd_i,
    input logic [SEQ_WIDTH-1:0] seq_i
  );
    int cells_v;
    begin
      unique case (CELL_COUNT_MODE)
        1: begin
          cells_v = (int'(seq_i) % SAFE_MAX_CELL_COUNT) + 1;
        end
        2: begin
          cells_v = (int'(rnd_i[15:0]) % SAFE_MAX_CELL_COUNT) + 1;
        end
        default: begin
          cells_v = 1;
        end
      endcase
      make_cell_count = CELL_COUNT_WIDTH'(cells_v);
    end
  endfunction

  function automatic logic [PAYLOAD_WIDTH-1:0] make_payload(
    input logic [PORT_W-1:0] port_i,
    input logic [RANK_WIDTH-1:0] rank_i,
    input logic [SEQ_WIDTH-1:0] seq_i,
    input logic [31:0] rnd_i
  );
    logic [127:0] mix;
    int bi;
    begin
      mix = {32'h54484d50, rnd_i, 32'(seq_i), 16'(rank_i), 16'(port_i)};
      for (bi = 0; bi < PAYLOAD_WIDTH; bi = bi + 1) begin
        make_payload[bi] = mix[bi % 128];
      end
    end
  endfunction

  wire fire = valid && ready;
  wire period_ready = (PERIOD_CYCLES <= 1) ? 1'b1 : (period_q == '0);
  wire can_start = enable && !done && !valid && period_ready;
  wire [31:0] next_lfsr = xorshift32(lfsr_q);
  wire [PORT_W-1:0] next_port = next_lfsr[PORT_W-1:0];
  wire [RANK_WIDTH-1:0] next_rank = make_rank(next_lfsr, seq_q);
  wire [CELL_COUNT_WIDTH-1:0] next_cell_count = make_cell_count(next_lfsr, seq_q);

  always_ff @(posedge clk) begin
    if (!resetn) begin
      period_q <= '0;
      lfsr_q <= 32'h1ace_b00c;
      seq_q <= '0;
      valid <= 1'b0;
      port <= '0;
      rank <= '0;
      seq <= '0;
      cell_count <= CELL_COUNT_WIDTH'(1);
      payload <= '0;
      done <= 1'b0;
    end else begin
      if (PERIOD_CYCLES > 1) begin
        if (period_q == PERIOD_CYCLES-1) begin
          period_q <= '0;
        end else begin
          period_q <= period_q + 1'b1;
        end
      end else begin
        period_q <= '0;
      end

      if (fire) begin
        valid <= 1'b0;
        seq_q <= seq_q + 1'b1;
        if ((seq_q + 1'b1) == SEQ_WIDTH'(MAX_PACKETS)) begin
          done <= 1'b1;
        end
      end

      if (can_start) begin
        lfsr_q <= next_lfsr;
        valid <= 1'b1;
        port <= next_port;
        rank <= next_rank;
        seq <= seq_q;
        cell_count <= next_cell_count;
        payload <= make_payload(next_port, next_rank, seq_q, next_lfsr);
      end
    end
  end
endmodule
