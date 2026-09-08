`timescale 1ns/1ps

module hestia_paper_scale_port_queue #(
  parameter int RANK_WIDTH = 10,
  parameter int SEQ_WIDTH = 16,
  parameter int CELL_COUNT_WIDTH = 16,
  parameter int DESC_W = 26,
  parameter int BATCH_ID_W = 23,
  parameter int BATCH_OFF_W = 3,
  parameter int BBQ_BITMAP_WIDTH = 32,
  parameter int OCC_WIDTH = 27,
  localparam int LEVEL_W = $clog2(BBQ_BITMAP_WIDTH),
  localparam int PIPE_W = RANK_WIDTH + SEQ_WIDTH + CELL_COUNT_WIDTH +
                          DESC_W + BATCH_ID_W + BATCH_OFF_W + 8
) (
  input  logic                         clk,
  input  logic                         resetn,
  input  logic                         op_valid,
  input  logic [2:0]                   op_type,
  input  logic                         op_tier,
  input  logic [RANK_WIDTH-1:0]        op_rank,
  input  logic [SEQ_WIDTH-1:0]         op_seq,
  input  logic [CELL_COUNT_WIDTH-1:0]  op_cell_count,
  input  logic [DESC_W-1:0]            op_desc,
  input  logic [BATCH_ID_W-1:0]        op_batch_id,
  input  logic [BATCH_OFF_W-1:0]       op_batch_off,
  output logic                         sram_min_valid,
  output logic [RANK_WIDTH-1:0]        sram_min_rank,
  output logic [SEQ_WIDTH-1:0]         sram_min_seq,
  output logic [DESC_W-1:0]            sram_min_desc,
  output logic [CELL_COUNT_WIDTH-1:0]  sram_min_cell_count,
  output logic                         sram_max_valid,
  output logic [RANK_WIDTH-1:0]        sram_max_rank,
  output logic [SEQ_WIDTH-1:0]         sram_max_seq,
  output logic [DESC_W-1:0]            sram_max_desc,
  output logic [CELL_COUNT_WIDTH-1:0]  sram_max_cell_count,
  output logic                         ddr_min_valid,
  output logic [RANK_WIDTH-1:0]        ddr_min_rank,
  output logic [SEQ_WIDTH-1:0]         ddr_min_seq,
  output logic [DESC_W-1:0]            ddr_min_desc,
  output logic [CELL_COUNT_WIDTH-1:0]  ddr_min_cell_count,
  output logic [BATCH_ID_W-1:0]        ddr_min_batch_id,
  output logic [BATCH_OFF_W-1:0]       ddr_min_batch_off,
  output logic [OCC_WIDTH-1:0]         sram_occupancy,
  output logic [OCC_WIDTH-1:0]         ddr_occupancy,
  output logic [63:0]                  digest
);

  typedef logic [BBQ_BITMAP_WIDTH-1:0] bitmap_t;

  bitmap_t sram_l1_q;
  bitmap_t ddr_l1_q;
  bitmap_t sram_l2_shadow_q;
  bitmap_t ddr_l2_shadow_q;
  logic [OCC_WIDTH-1:0] sram_occ_q;
  logic [OCC_WIDTH-1:0] ddr_occ_q;

  logic [PIPE_W-1:0] pipe_q [0:10];
  logic [10:0] valid_pipe_q;
  logic [LEVEL_W-1:0] sram_l1_min_idx_q;
  logic [LEVEL_W-1:0] sram_l1_max_idx_q;
  logic [LEVEL_W-1:0] ddr_l1_min_idx_q;
  logic [LEVEL_W-1:0] ddr_l1_max_idx_q;
  logic [LEVEL_W-1:0] sram_l2_min_idx_q;
  logic [LEVEL_W-1:0] sram_l2_max_idx_q;
  logic [LEVEL_W-1:0] ddr_l2_min_idx_q;
  logic [LEVEL_W-1:0] ddr_l2_max_idx_q;

  function automatic logic [LEVEL_W-1:0] find_first(input bitmap_t bits_i);
    int i;
    logic found;
    begin
      find_first = '0;
      found = 1'b0;
      for (i = 0; i < BBQ_BITMAP_WIDTH; i = i + 1) begin
        if (!found && bits_i[i]) begin
          find_first = i[LEVEL_W-1:0];
          found = 1'b1;
        end
      end
    end
  endfunction

  function automatic logic [LEVEL_W-1:0] find_last(input bitmap_t bits_i);
    int i;
    logic found;
    begin
      find_last = '0;
      found = 1'b0;
      for (i = BBQ_BITMAP_WIDTH - 1; i >= 0; i = i - 1) begin
        if (!found && bits_i[i]) begin
          find_last = i[LEVEL_W-1:0];
          found = 1'b1;
        end
      end
    end
  endfunction

  function automatic logic rank_less(
    input logic [RANK_WIDTH-1:0] a_rank,
    input logic [SEQ_WIDTH-1:0] a_seq,
    input logic [RANK_WIDTH-1:0] b_rank,
    input logic [SEQ_WIDTH-1:0] b_seq
  );
    begin
      rank_less = (a_rank < b_rank) || ((a_rank == b_rank) && (a_seq < b_seq));
    end
  endfunction

  function automatic logic rank_greater(
    input logic [RANK_WIDTH-1:0] a_rank,
    input logic [SEQ_WIDTH-1:0] a_seq,
    input logic [RANK_WIDTH-1:0] b_rank,
    input logic [SEQ_WIDTH-1:0] b_seq
  );
    begin
      rank_greater = (a_rank > b_rank) || ((a_rank == b_rank) && (a_seq > b_seq));
    end
  endfunction

  function automatic logic [PIPE_W-1:0] pack_op;
    input logic [2:0] op_type_i;
    input logic op_tier_i;
    input logic [RANK_WIDTH-1:0] rank_i;
    input logic [SEQ_WIDTH-1:0] seq_i;
    input logic [CELL_COUNT_WIDTH-1:0] cells_i;
    input logic [DESC_W-1:0] desc_i;
    input logic [BATCH_ID_W-1:0] batch_i;
    input logic [BATCH_OFF_W-1:0] off_i;
    logic [PIPE_W-1:0] word;
    int pos;
    begin
      word = '0;
      pos = 0;
      word[pos +: RANK_WIDTH] = rank_i;
      pos = pos + RANK_WIDTH;
      word[pos +: SEQ_WIDTH] = seq_i;
      pos = pos + SEQ_WIDTH;
      word[pos +: CELL_COUNT_WIDTH] = cells_i;
      pos = pos + CELL_COUNT_WIDTH;
      word[pos +: DESC_W] = desc_i;
      pos = pos + DESC_W;
      word[pos +: BATCH_ID_W] = batch_i;
      pos = pos + BATCH_ID_W;
      word[pos +: BATCH_OFF_W] = off_i;
      pos = pos + BATCH_OFF_W;
      word[pos +: 3] = op_type_i;
      pos = pos + 3;
      word[pos] = op_tier_i;
      pack_op = word;
    end
  endfunction

  assign sram_occupancy = sram_occ_q;
  assign ddr_occupancy = ddr_occ_q;

  always_ff @(posedge clk) begin
    logic [PIPE_W-1:0] in_word;
    logic [LEVEL_W-1:0] l1_idx;
    logic [LEVEL_W-1:0] l2_idx;
    logic [OCC_WIDTH-1:0] cells_ext;
    int stage;

    in_word = pack_op(op_type, op_tier, op_rank, op_seq, op_cell_count,
                      op_desc, op_batch_id, op_batch_off);
    l1_idx = op_rank[RANK_WIDTH-1 -: LEVEL_W];
    l2_idx = op_rank[LEVEL_W-1:0];
    cells_ext = {{(OCC_WIDTH-CELL_COUNT_WIDTH){1'b0}}, op_cell_count};

    if (!resetn) begin
      sram_l1_q <= '0;
      ddr_l1_q <= '0;
      sram_l2_shadow_q <= '0;
      ddr_l2_shadow_q <= '0;
      sram_occ_q <= '0;
      ddr_occ_q <= '0;
      valid_pipe_q <= '0;
      sram_l1_min_idx_q <= '0;
      sram_l1_max_idx_q <= '0;
      ddr_l1_min_idx_q <= '0;
      ddr_l1_max_idx_q <= '0;
      sram_l2_min_idx_q <= '0;
      sram_l2_max_idx_q <= '0;
      ddr_l2_min_idx_q <= '0;
      ddr_l2_max_idx_q <= '0;
      sram_min_valid <= 1'b0;
      sram_max_valid <= 1'b0;
      ddr_min_valid <= 1'b0;
      sram_min_rank <= '0;
      sram_min_seq <= '0;
      sram_min_desc <= '0;
      sram_min_cell_count <= '0;
      sram_max_rank <= '0;
      sram_max_seq <= '0;
      sram_max_desc <= '0;
      sram_max_cell_count <= '0;
      ddr_min_rank <= '0;
      ddr_min_seq <= '0;
      ddr_min_desc <= '0;
      ddr_min_cell_count <= '0;
      ddr_min_batch_id <= '0;
      ddr_min_batch_off <= '0;
      digest <= '0;
      for (stage = 0; stage < 11; stage = stage + 1) begin
        pipe_q[stage] <= '0;
      end
    end else begin
      valid_pipe_q <= {valid_pipe_q[9:0], op_valid};
      pipe_q[0] <= in_word;
      for (stage = 1; stage < 11; stage = stage + 1) begin
        pipe_q[stage] <= pipe_q[stage-1] ^ {{(PIPE_W-64){1'b0}}, digest};
      end

      sram_l1_min_idx_q <= find_first(sram_l1_q);
      sram_l1_max_idx_q <= find_last(sram_l1_q);
      ddr_l1_min_idx_q <= find_first(ddr_l1_q);
      ddr_l1_max_idx_q <= find_last(ddr_l1_q);
      sram_l2_min_idx_q <= find_first(sram_l2_shadow_q);
      sram_l2_max_idx_q <= find_last(sram_l2_shadow_q);
      ddr_l2_min_idx_q <= find_first(ddr_l2_shadow_q);
      ddr_l2_max_idx_q <= find_last(ddr_l2_shadow_q);

      if (op_valid) begin
        unique case (op_type)
          3'd1: begin
            if (!op_tier) begin
              sram_l1_q[l1_idx] <= 1'b1;
              sram_l2_shadow_q[l2_idx] <= 1'b1;
              sram_occ_q <= sram_occ_q + cells_ext;
              if (!sram_min_valid || rank_less(op_rank, op_seq, sram_min_rank, sram_min_seq)) begin
                sram_min_valid <= 1'b1;
                sram_min_rank <= op_rank;
                sram_min_seq <= op_seq;
                sram_min_desc <= op_desc;
                sram_min_cell_count <= op_cell_count;
              end
              if (!sram_max_valid || rank_greater(op_rank, op_seq, sram_max_rank, sram_max_seq)) begin
                sram_max_valid <= 1'b1;
                sram_max_rank <= op_rank;
                sram_max_seq <= op_seq;
                sram_max_desc <= op_desc;
                sram_max_cell_count <= op_cell_count;
              end
            end else begin
              ddr_l1_q[l1_idx] <= 1'b1;
              ddr_l2_shadow_q[l2_idx] <= 1'b1;
              ddr_occ_q <= ddr_occ_q + cells_ext;
              if (!ddr_min_valid || rank_less(op_rank, op_seq, ddr_min_rank, ddr_min_seq)) begin
                ddr_min_valid <= 1'b1;
                ddr_min_rank <= op_rank;
                ddr_min_seq <= op_seq;
                ddr_min_desc <= op_desc;
                ddr_min_cell_count <= op_cell_count;
                ddr_min_batch_id <= op_batch_id;
                ddr_min_batch_off <= op_batch_off;
              end
            end
          end
          3'd2: begin
            if (sram_occ_q > cells_ext) begin
              sram_occ_q <= sram_occ_q - cells_ext;
            end else begin
              sram_occ_q <= '0;
            end
            sram_min_valid <= |sram_l1_q;
            sram_min_rank <= {sram_l1_min_idx_q, sram_l2_min_idx_q};
            sram_min_seq <= sram_min_seq + 1'b1;
            sram_min_cell_count <= op_cell_count;
          end
          3'd3: begin
            if (sram_occ_q > cells_ext) begin
              sram_occ_q <= sram_occ_q - cells_ext;
            end else begin
              sram_occ_q <= '0;
            end
            sram_max_valid <= |sram_l1_q;
            sram_max_rank <= {sram_l1_max_idx_q, sram_l2_max_idx_q};
            sram_max_seq <= sram_max_seq - 1'b1;
            sram_max_cell_count <= op_cell_count;
          end
          3'd4: begin
            if (ddr_occ_q > cells_ext) begin
              ddr_occ_q <= ddr_occ_q - cells_ext;
            end else begin
              ddr_occ_q <= '0;
            end
            if (sram_occ_q != {OCC_WIDTH{1'b1}}) begin
              sram_occ_q <= sram_occ_q + cells_ext;
            end
            sram_l1_q[l1_idx] <= 1'b1;
            sram_l2_shadow_q[l2_idx] <= 1'b1;
            ddr_min_valid <= |ddr_l1_q;
            sram_min_cell_count <= op_cell_count;
          end
          3'd5: begin
            if (sram_occ_q > cells_ext) begin
              sram_occ_q <= sram_occ_q - cells_ext;
            end else begin
              sram_occ_q <= '0;
            end
            ddr_occ_q <= ddr_occ_q + cells_ext;
            ddr_l1_q[l1_idx] <= 1'b1;
            ddr_l2_shadow_q[l2_idx] <= 1'b1;
            ddr_min_valid <= 1'b1;
            ddr_min_rank <= op_rank;
            ddr_min_seq <= op_seq;
            ddr_min_desc <= op_desc;
            ddr_min_cell_count <= op_cell_count;
            ddr_min_batch_id <= op_batch_id;
            ddr_min_batch_off <= op_batch_off;
          end
          default: begin
            digest <= digest ^ pipe_q[10][63:0] ^ {58'd0, sram_l1_min_idx_q, ddr_l1_min_idx_q};
          end
        endcase
      end

      digest <= digest ^ pipe_q[10][63:0] ^
                {{(64-RANK_WIDTH){1'b0}}, sram_min_rank} ^
                {{(64-RANK_WIDTH){1'b0}}, ddr_min_rank} ^
                {{(64-OCC_WIDTH){1'b0}}, sram_occ_q};
    end
  end

endmodule

module hestia_paper_scale_resource_core #(
  parameter int PORTS = 4,
  parameter int POLICY_MODE = -1,
  parameter int RANK_WIDTH = 10,
  parameter int SEQ_WIDTH = 16,
  parameter int CELL_COUNT_WIDTH = 16,
  parameter int CELL_BYTES = 64,
  parameter int SRAM_BYTES = 5 * 1024 * 1024,
  parameter int DDR_BYTES_LOG2 = 32,
  parameter int BATCH_SIZE = 8,
  parameter int BBQ_BITMAP_WIDTH = 32,
  parameter int ALPHA_SHIFT_WIDTH = 4,
  localparam int PORT_W = (PORTS <= 2) ? 1 : $clog2(PORTS),
  localparam int SRAM_CELLS = SRAM_BYTES / CELL_BYTES,
  localparam int SRAM_PTR_W = $clog2(SRAM_CELLS),
  localparam int DDR_CELLS_LOG2 = DDR_BYTES_LOG2 - $clog2(CELL_BYTES),
  localparam int BATCH_ID_W = DDR_CELLS_LOG2 - $clog2(BATCH_SIZE),
  localparam int BATCH_OFF_W = $clog2(BATCH_SIZE),
  localparam int DESC_W = DDR_CELLS_LOG2,
  localparam int OCC_WIDTH = DDR_CELLS_LOG2 + 1
) (
  input  logic                              clk,
  input  logic                              resetn,
  input  logic                              enable,
  input  logic [ALPHA_SHIFT_WIDTH-1:0]      cfg_alpha_shift,
  input  logic                              s_pkt_valid,
  output logic                              s_pkt_ready,
  input  logic [PORT_W-1:0]                 s_pkt_port,
  input  logic [RANK_WIDTH-1:0]             s_pkt_rank,
  input  logic [SEQ_WIDTH-1:0]              s_pkt_seq,
  input  logic [CELL_COUNT_WIDTH-1:0]       s_pkt_cell_count,
  input  logic [PORTS-1:0]                  dequeue_enable,
  output logic [PORTS-1:0]                  m_pkt_valid,
  input  logic [PORTS-1:0]                  m_pkt_ready,
  output logic [PORTS*RANK_WIDTH-1:0]       m_pkt_rank,
  output logic [PORTS*SEQ_WIDTH-1:0]        m_pkt_seq,
  output logic [127:0]                      resource_digest
);

  localparam int POLICY_THEMIS = -1;
  localparam int POLICY_DT = 0;
  localparam int POLICY_OCCAMY = 1;
  localparam int POLICY_OBM = 3;
  localparam logic [OCC_WIDTH-1:0] SRAM_CELLS_OCC = SRAM_CELLS;

  logic [PORTS-1:0] port_op_valid;
  logic [PORTS*3-1:0] port_op_type;
  logic [PORTS-1:0] port_op_tier;
  logic [PORTS*RANK_WIDTH-1:0] port_op_rank;
  logic [PORTS*SEQ_WIDTH-1:0] port_op_seq;
  logic [PORTS*CELL_COUNT_WIDTH-1:0] port_op_cell_count;
  logic [PORTS*DESC_W-1:0] port_op_desc;
  logic [PORTS*BATCH_ID_W-1:0] port_op_batch_id;
  logic [PORTS*BATCH_OFF_W-1:0] port_op_batch_off;

  logic [PORTS-1:0] sram_min_valid;
  logic [PORTS*RANK_WIDTH-1:0] sram_min_rank;
  logic [PORTS*SEQ_WIDTH-1:0] sram_min_seq;
  logic [PORTS*DESC_W-1:0] sram_min_desc;
  logic [PORTS-1:0] sram_max_valid;
  logic [PORTS*RANK_WIDTH-1:0] sram_max_rank;
  logic [PORTS*SEQ_WIDTH-1:0] sram_max_seq;
  logic [PORTS*DESC_W-1:0] sram_max_desc;
  logic [PORTS-1:0] ddr_min_valid;
  logic [PORTS*RANK_WIDTH-1:0] ddr_min_rank;
  logic [PORTS*SEQ_WIDTH-1:0] ddr_min_seq;
  logic [PORTS*DESC_W-1:0] ddr_min_desc;
  logic [PORTS*BATCH_ID_W-1:0] ddr_min_batch_id;
  logic [PORTS*BATCH_OFF_W-1:0] ddr_min_batch_off;
  logic [PORTS*OCC_WIDTH-1:0] sram_occ_flat;
  logic [PORTS*OCC_WIDTH-1:0] ddr_occ_flat;
  logic [PORTS*64-1:0] queue_digest_flat;

  logic [SRAM_PTR_W-1:0] sram_free_head_q;
  logic [SRAM_PTR_W-1:0] sram_free_tail_q;
  logic [OCC_WIDTH-1:0] global_sram_occ_q;
  logic [OCC_WIDTH-1:0] global_ddr_occ_q;
  logic [OCC_WIDTH-1:0] sram_free_cells;
  logic [BATCH_ID_W-1:0] batch_alloc_head_q;
  logic [BATCH_ID_W-1:0] batch_free_tail_q;
  logic [BATCH_ID_W-1:0] open_batch_id_q;
  logic [BATCH_OFF_W:0] open_batch_fill_q;
  logic [DESC_W-1:0] desc_alloc_q;
  logic [DESC_W-1:0] desc_release_q;
  logic [PORT_W-1:0] ingress_rr_q;
  logic [PORT_W-1:0] deq_rr_q;
  logic [PORT_W-1:0] ddr_wr_rr_q;
  logic [PORT_W-1:0] ddr_rd_rr_q;
  logic [PORT_W-1:0] reclaim_rr_q;

  logic policy_admit;
  logic [OCC_WIDTH-1:0] policy_threshold;
  logic [PORTS-1:0] occamy_over_bitmap;
  logic occamy_reclaim_valid;
  logic [PORT_W-1:0] occamy_reclaim_port;
  logic obm_longest_valid;
  logic [PORT_W-1:0] obm_longest_port;
  logic [OCC_WIDTH-1:0] obm_longest_occ;
  logic obm_pkt_targets_longest;

  logic [PORTS-1:0] sram_read_req_c;
  logic [PORTS-1:0] sram_write_req_c;
  logic [PORTS-1:0] ddr_read_req_c;
  logic [PORTS-1:0] ddr_write_req_c;
  logic [PORT_W-1:0] sram_read_grant_c;
  logic [PORT_W-1:0] sram_write_grant_c;
  logic [PORT_W-1:0] ddr_read_grant_c;
  logic [PORT_W-1:0] ddr_write_grant_c;
  logic [PORT_W-1:0] swapin_port_c;
  logic [PORT_W-1:0] swapout_port_c;
  logic swapin_valid_c;
  logic swapout_valid_c;
  logic [RANK_WIDTH-1:0] swapin_rank_c;
  logic [RANK_WIDTH-1:0] swapout_rank_c;
  logic [SEQ_WIDTH-1:0] swapin_seq_c;
  logic [SEQ_WIDTH-1:0] swapout_seq_c;
  logic [OCC_WIDTH-1:0] s_pkt_cells_occ_c;
  logic [SRAM_PTR_W-1:0] s_pkt_cells_sram_ptr_c;
  logic [BATCH_OFF_W:0] s_pkt_cells_batch_off_c;

  function automatic logic rank_less(
    input logic [RANK_WIDTH-1:0] a_rank,
    input logic [SEQ_WIDTH-1:0] a_seq,
    input logic [RANK_WIDTH-1:0] b_rank,
    input logic [SEQ_WIDTH-1:0] b_seq
  );
    begin
      rank_less = (a_rank < b_rank) || ((a_rank == b_rank) && (a_seq < b_seq));
    end
  endfunction

  function automatic logic rank_greater(
    input logic [RANK_WIDTH-1:0] a_rank,
    input logic [SEQ_WIDTH-1:0] a_seq,
    input logic [RANK_WIDTH-1:0] b_rank,
    input logic [SEQ_WIDTH-1:0] b_seq
  );
    begin
      rank_greater = (a_rank > b_rank) || ((a_rank == b_rank) && (a_seq > b_seq));
    end
  endfunction

  function automatic logic [PORT_W-1:0] rr_select(
    input logic [PORTS-1:0] req_i,
    input logic [PORT_W-1:0] base_i
  );
    int si;
    int idx;
    logic found;
    begin
      rr_select = base_i;
      found = 1'b0;
      for (si = 0; si < PORTS; si = si + 1) begin
        idx = int'(base_i) + si;
        if (idx >= PORTS) begin
          idx = idx - PORTS;
        end
        if (!found && req_i[idx]) begin
          rr_select = PORT_W'(idx);
          found = 1'b1;
        end
      end
    end
  endfunction

  function automatic logic [OCC_WIDTH-1:0] cell_count_ext(
    input logic [CELL_COUNT_WIDTH-1:0] cells_i
  );
    begin
      cell_count_ext = {{(OCC_WIDTH-CELL_COUNT_WIDTH){1'b0}}, cells_i};
    end
  endfunction

  genvar gp;
  generate
    for (gp = 0; gp < PORTS; gp = gp + 1) begin : gen_port_q
      hestia_paper_scale_port_queue #(
        .RANK_WIDTH(RANK_WIDTH),
        .SEQ_WIDTH(SEQ_WIDTH),
        .CELL_COUNT_WIDTH(CELL_COUNT_WIDTH),
        .DESC_W(DESC_W),
        .BATCH_ID_W(BATCH_ID_W),
        .BATCH_OFF_W(BATCH_OFF_W),
        .BBQ_BITMAP_WIDTH(BBQ_BITMAP_WIDTH),
        .OCC_WIDTH(OCC_WIDTH)
      ) port_q (
        .clk(clk),
        .resetn(resetn),
        .op_valid(port_op_valid[gp]),
        .op_type(port_op_type[gp*3 +: 3]),
        .op_tier(port_op_tier[gp]),
        .op_rank(port_op_rank[gp*RANK_WIDTH +: RANK_WIDTH]),
        .op_seq(port_op_seq[gp*SEQ_WIDTH +: SEQ_WIDTH]),
        .op_cell_count(port_op_cell_count[gp*CELL_COUNT_WIDTH +: CELL_COUNT_WIDTH]),
        .op_desc(port_op_desc[gp*DESC_W +: DESC_W]),
        .op_batch_id(port_op_batch_id[gp*BATCH_ID_W +: BATCH_ID_W]),
        .op_batch_off(port_op_batch_off[gp*BATCH_OFF_W +: BATCH_OFF_W]),
        .sram_min_valid(sram_min_valid[gp]),
        .sram_min_rank(sram_min_rank[gp*RANK_WIDTH +: RANK_WIDTH]),
        .sram_min_seq(sram_min_seq[gp*SEQ_WIDTH +: SEQ_WIDTH]),
        .sram_min_desc(sram_min_desc[gp*DESC_W +: DESC_W]),
        .sram_min_cell_count(),
        .sram_max_valid(sram_max_valid[gp]),
        .sram_max_rank(sram_max_rank[gp*RANK_WIDTH +: RANK_WIDTH]),
        .sram_max_seq(sram_max_seq[gp*SEQ_WIDTH +: SEQ_WIDTH]),
        .sram_max_desc(sram_max_desc[gp*DESC_W +: DESC_W]),
        .sram_max_cell_count(),
        .ddr_min_valid(ddr_min_valid[gp]),
        .ddr_min_rank(ddr_min_rank[gp*RANK_WIDTH +: RANK_WIDTH]),
        .ddr_min_seq(ddr_min_seq[gp*SEQ_WIDTH +: SEQ_WIDTH]),
        .ddr_min_desc(ddr_min_desc[gp*DESC_W +: DESC_W]),
        .ddr_min_cell_count(),
        .ddr_min_batch_id(ddr_min_batch_id[gp*BATCH_ID_W +: BATCH_ID_W]),
        .ddr_min_batch_off(ddr_min_batch_off[gp*BATCH_OFF_W +: BATCH_OFF_W]),
        .sram_occupancy(sram_occ_flat[gp*OCC_WIDTH +: OCC_WIDTH]),
        .ddr_occupancy(ddr_occ_flat[gp*OCC_WIDTH +: OCC_WIDTH]),
        .digest(queue_digest_flat[gp*64 +: 64])
      );

      assign m_pkt_rank[gp*RANK_WIDTH +: RANK_WIDTH] =
        (sram_min_valid[gp] &&
         (!ddr_min_valid[gp] ||
          rank_less(sram_min_rank[gp*RANK_WIDTH +: RANK_WIDTH],
                    sram_min_seq[gp*SEQ_WIDTH +: SEQ_WIDTH],
                    ddr_min_rank[gp*RANK_WIDTH +: RANK_WIDTH],
                    ddr_min_seq[gp*SEQ_WIDTH +: SEQ_WIDTH]))) ?
        sram_min_rank[gp*RANK_WIDTH +: RANK_WIDTH] :
        ddr_min_rank[gp*RANK_WIDTH +: RANK_WIDTH];
      assign m_pkt_seq[gp*SEQ_WIDTH +: SEQ_WIDTH] =
        (sram_min_valid[gp] &&
         (!ddr_min_valid[gp] ||
          rank_less(sram_min_rank[gp*RANK_WIDTH +: RANK_WIDTH],
                    sram_min_seq[gp*SEQ_WIDTH +: SEQ_WIDTH],
                    ddr_min_rank[gp*RANK_WIDTH +: RANK_WIDTH],
                    ddr_min_seq[gp*SEQ_WIDTH +: SEQ_WIDTH]))) ?
        sram_min_seq[gp*SEQ_WIDTH +: SEQ_WIDTH] :
        ddr_min_seq[gp*SEQ_WIDTH +: SEQ_WIDTH];
      assign m_pkt_valid[gp] = dequeue_enable[gp] &&
                               (sram_min_valid[gp] || ddr_min_valid[gp]);
    end
  endgenerate

  hestia_policy_dt #(
    .PORTS(PORTS),
    .CELL_COUNT_WIDTH(CELL_COUNT_WIDTH),
    .OCC_WIDTH(OCC_WIDTH),
    .ALPHA_SHIFT_WIDTH(ALPHA_SHIFT_WIDTH)
  ) dt_policy (
    .cfg_alpha_shift(cfg_alpha_shift),
    .pkt_valid(s_pkt_valid),
    .pkt_port(s_pkt_port),
    .pkt_cell_count(s_pkt_cell_count),
    .free_cells(sram_free_cells),
    .port_occ_flat(sram_occ_flat),
    .pkt_admit(policy_admit),
    .threshold(policy_threshold)
  );

  hestia_policy_occamy #(
    .PORTS(PORTS),
    .CELL_COUNT_WIDTH(CELL_COUNT_WIDTH),
    .OCC_WIDTH(OCC_WIDTH),
    .ALPHA_SHIFT_WIDTH(ALPHA_SHIFT_WIDTH)
  ) occamy_policy (
    .clk(clk),
    .resetn(resetn),
    .cfg_alpha_shift(cfg_alpha_shift),
    .reclaim_enable(enable),
    .reclaim_fire(occamy_reclaim_valid),
    .pkt_valid(s_pkt_valid),
    .pkt_port(s_pkt_port),
    .pkt_cell_count(s_pkt_cell_count),
    .free_cells(sram_free_cells),
    .port_occ_flat(sram_occ_flat),
    .pkt_admit(),
    .threshold(),
    .over_threshold_bitmap(occamy_over_bitmap),
    .reclaim_valid(occamy_reclaim_valid),
    .reclaim_port(occamy_reclaim_port)
  );

  hestia_policy_obm #(
    .PORTS(PORTS),
    .OCC_WIDTH(OCC_WIDTH)
  ) obm_policy (
    .port_occ_flat(sram_occ_flat),
    .pkt_port(s_pkt_port),
    .pkt_valid(s_pkt_valid),
    .longest_valid(obm_longest_valid),
    .longest_port(obm_longest_port),
    .longest_occupancy(obm_longest_occ),
    .pkt_targets_longest(obm_pkt_targets_longest)
  );

  always_comb begin
    s_pkt_cells_occ_c = cell_count_ext(s_pkt_cell_count);
    s_pkt_cells_sram_ptr_c = s_pkt_cells_occ_c[SRAM_PTR_W-1:0];
    s_pkt_cells_batch_off_c = s_pkt_cells_occ_c[BATCH_OFF_W:0];
    sram_free_cells = (SRAM_CELLS_OCC > global_sram_occ_q) ?
                      (SRAM_CELLS_OCC - global_sram_occ_q) : '0;
    s_pkt_ready = enable && (sram_free_cells != '0);

    sram_read_req_c = dequeue_enable & m_pkt_ready & sram_min_valid;
    sram_write_req_c = '0;
    ddr_read_req_c = dequeue_enable & m_pkt_ready & ddr_min_valid;
    ddr_write_req_c = '0;
    sram_write_req_c[s_pkt_port] = s_pkt_valid && s_pkt_ready && policy_admit;
    ddr_write_req_c[s_pkt_port] = s_pkt_valid && s_pkt_ready && !policy_admit;

    sram_read_grant_c = rr_select(sram_read_req_c, deq_rr_q);
    sram_write_grant_c = rr_select(sram_write_req_c, ingress_rr_q);
    ddr_read_grant_c = rr_select(ddr_read_req_c, ddr_rd_rr_q);
    ddr_write_grant_c = rr_select(ddr_write_req_c, ddr_wr_rr_q);

    swapin_valid_c = 1'b0;
    swapin_port_c = '0;
    swapin_rank_c = '1;
    swapin_seq_c = '1;
    swapout_valid_c = 1'b0;
    swapout_port_c = '0;
    swapout_rank_c = '0;
    swapout_seq_c = '0;
    for (int pi = 0; pi < PORTS; pi = pi + 1) begin
      if (ddr_min_valid[pi] &&
          (!swapin_valid_c ||
           rank_less(ddr_min_rank[pi*RANK_WIDTH +: RANK_WIDTH],
                     ddr_min_seq[pi*SEQ_WIDTH +: SEQ_WIDTH],
                     swapin_rank_c,
                     swapin_seq_c))) begin
        swapin_valid_c = 1'b1;
        swapin_port_c = PORT_W'(pi);
        swapin_rank_c = ddr_min_rank[pi*RANK_WIDTH +: RANK_WIDTH];
        swapin_seq_c = ddr_min_seq[pi*SEQ_WIDTH +: SEQ_WIDTH];
      end
      if (sram_max_valid[pi] &&
          (!swapout_valid_c ||
           rank_greater(sram_max_rank[pi*RANK_WIDTH +: RANK_WIDTH],
                        sram_max_seq[pi*SEQ_WIDTH +: SEQ_WIDTH],
                        swapout_rank_c,
                        swapout_seq_c))) begin
        swapout_valid_c = 1'b1;
        swapout_port_c = PORT_W'(pi);
        swapout_rank_c = sram_max_rank[pi*RANK_WIDTH +: RANK_WIDTH];
        swapout_seq_c = sram_max_seq[pi*SEQ_WIDTH +: SEQ_WIDTH];
      end
    end

    port_op_valid = '0;
    port_op_type = '0;
    port_op_tier = '0;
    port_op_rank = '0;
    port_op_seq = '0;
    port_op_cell_count = '0;
    port_op_desc = '0;
    port_op_batch_id = '0;
    port_op_batch_off = '0;

    if (s_pkt_valid && s_pkt_ready) begin
      port_op_valid[s_pkt_port] = 1'b1;
      port_op_type[s_pkt_port*3 +: 3] =
        (POLICY_MODE == POLICY_THEMIS) ? 3'd1 :
        ((POLICY_MODE == POLICY_DT && policy_admit) ? 3'd1 :
         (POLICY_MODE == POLICY_OCCAMY && policy_admit) ? 3'd1 :
         (POLICY_MODE == POLICY_OBM && !obm_pkt_targets_longest) ? 3'd1 : 3'd1);
      port_op_tier[s_pkt_port] =
        (POLICY_MODE == POLICY_THEMIS) ? (global_sram_occ_q >= (SRAM_CELLS_OCC - 16)) :
        ((POLICY_MODE == POLICY_DT || POLICY_MODE == POLICY_OCCAMY) ? !policy_admit :
         (POLICY_MODE == POLICY_OBM ? (obm_pkt_targets_longest || (sram_free_cells == '0)) : 1'b0));
      port_op_rank[s_pkt_port*RANK_WIDTH +: RANK_WIDTH] = s_pkt_rank;
      port_op_seq[s_pkt_port*SEQ_WIDTH +: SEQ_WIDTH] = s_pkt_seq;
      port_op_cell_count[s_pkt_port*CELL_COUNT_WIDTH +: CELL_COUNT_WIDTH] = s_pkt_cell_count;
      port_op_desc[s_pkt_port*DESC_W +: DESC_W] = desc_alloc_q;
      port_op_batch_id[s_pkt_port*BATCH_ID_W +: BATCH_ID_W] = open_batch_id_q;
      port_op_batch_off[s_pkt_port*BATCH_OFF_W +: BATCH_OFF_W] = open_batch_fill_q[BATCH_OFF_W-1:0];
    end else if ((POLICY_MODE == POLICY_THEMIS) && swapout_valid_c) begin
      port_op_valid[swapout_port_c] = 1'b1;
      port_op_type[swapout_port_c*3 +: 3] = 3'd5;
      port_op_tier[swapout_port_c] = 1'b1;
      port_op_rank[swapout_port_c*RANK_WIDTH +: RANK_WIDTH] = swapout_rank_c;
      port_op_seq[swapout_port_c*SEQ_WIDTH +: SEQ_WIDTH] = swapout_seq_c;
      port_op_cell_count[swapout_port_c*CELL_COUNT_WIDTH +: CELL_COUNT_WIDTH] = s_pkt_cell_count;
      port_op_desc[swapout_port_c*DESC_W +: DESC_W] = desc_release_q;
      port_op_batch_id[swapout_port_c*BATCH_ID_W +: BATCH_ID_W] = batch_alloc_head_q;
      port_op_batch_off[swapout_port_c*BATCH_OFF_W +: BATCH_OFF_W] = open_batch_fill_q[BATCH_OFF_W-1:0];
    end else if ((POLICY_MODE == POLICY_THEMIS) && swapin_valid_c) begin
      port_op_valid[swapin_port_c] = 1'b1;
      port_op_type[swapin_port_c*3 +: 3] = 3'd4;
      port_op_tier[swapin_port_c] = 1'b0;
      port_op_rank[swapin_port_c*RANK_WIDTH +: RANK_WIDTH] = swapin_rank_c;
      port_op_seq[swapin_port_c*SEQ_WIDTH +: SEQ_WIDTH] = swapin_seq_c;
      port_op_cell_count[swapin_port_c*CELL_COUNT_WIDTH +: CELL_COUNT_WIDTH] = s_pkt_cell_count;
      port_op_desc[swapin_port_c*DESC_W +: DESC_W] = ddr_min_desc[swapin_port_c*DESC_W +: DESC_W];
      port_op_batch_id[swapin_port_c*BATCH_ID_W +: BATCH_ID_W] =
        ddr_min_batch_id[swapin_port_c*BATCH_ID_W +: BATCH_ID_W];
      port_op_batch_off[swapin_port_c*BATCH_OFF_W +: BATCH_OFF_W] =
        ddr_min_batch_off[swapin_port_c*BATCH_OFF_W +: BATCH_OFF_W];
    end else if ((POLICY_MODE == POLICY_OCCAMY) && occamy_reclaim_valid) begin
      port_op_valid[occamy_reclaim_port] = 1'b1;
      port_op_type[occamy_reclaim_port*3 +: 3] = 3'd5;
      port_op_tier[occamy_reclaim_port] = 1'b1;
      port_op_rank[occamy_reclaim_port*RANK_WIDTH +: RANK_WIDTH] =
        sram_max_rank[occamy_reclaim_port*RANK_WIDTH +: RANK_WIDTH];
      port_op_seq[occamy_reclaim_port*SEQ_WIDTH +: SEQ_WIDTH] =
        sram_max_seq[occamy_reclaim_port*SEQ_WIDTH +: SEQ_WIDTH];
      port_op_cell_count[occamy_reclaim_port*CELL_COUNT_WIDTH +: CELL_COUNT_WIDTH] = s_pkt_cell_count;
      port_op_desc[occamy_reclaim_port*DESC_W +: DESC_W] =
        sram_max_desc[occamy_reclaim_port*DESC_W +: DESC_W];
      port_op_batch_id[occamy_reclaim_port*BATCH_ID_W +: BATCH_ID_W] = batch_alloc_head_q;
    end else if ((POLICY_MODE == POLICY_OBM) && obm_longest_valid && !obm_pkt_targets_longest) begin
      port_op_valid[obm_longest_port] = 1'b1;
      port_op_type[obm_longest_port*3 +: 3] = 3'd5;
      port_op_tier[obm_longest_port] = 1'b1;
      port_op_rank[obm_longest_port*RANK_WIDTH +: RANK_WIDTH] =
        sram_max_rank[obm_longest_port*RANK_WIDTH +: RANK_WIDTH];
      port_op_seq[obm_longest_port*SEQ_WIDTH +: SEQ_WIDTH] =
        sram_max_seq[obm_longest_port*SEQ_WIDTH +: SEQ_WIDTH];
      port_op_cell_count[obm_longest_port*CELL_COUNT_WIDTH +: CELL_COUNT_WIDTH] = s_pkt_cell_count;
      port_op_desc[obm_longest_port*DESC_W +: DESC_W] =
        sram_max_desc[obm_longest_port*DESC_W +: DESC_W];
      port_op_batch_id[obm_longest_port*BATCH_ID_W +: BATCH_ID_W] = batch_alloc_head_q;
    end
  end

  always_ff @(posedge clk) begin
    if (!resetn) begin
      sram_free_head_q <= '0;
      sram_free_tail_q <= '0;
      global_sram_occ_q <= '0;
      global_ddr_occ_q <= '0;
      batch_alloc_head_q <= '0;
      batch_free_tail_q <= '0;
      open_batch_id_q <= '0;
      open_batch_fill_q <= '0;
      desc_alloc_q <= '0;
      desc_release_q <= '0;
      ingress_rr_q <= '0;
      deq_rr_q <= '0;
      ddr_wr_rr_q <= '0;
      ddr_rd_rr_q <= '0;
      reclaim_rr_q <= '0;
      resource_digest <= '0;
    end else if (enable) begin
      if (s_pkt_valid && s_pkt_ready) begin
        desc_alloc_q <= desc_alloc_q + 1'b1;
        sram_free_head_q <= sram_free_head_q + s_pkt_cells_sram_ptr_c;
        if (port_op_tier[s_pkt_port]) begin
          global_ddr_occ_q <= global_ddr_occ_q + s_pkt_cells_occ_c;
          open_batch_fill_q <= open_batch_fill_q + s_pkt_cells_batch_off_c;
          if (open_batch_fill_q >= (BATCH_SIZE - 1)) begin
            open_batch_id_q <= open_batch_id_q + 1'b1;
            batch_alloc_head_q <= batch_alloc_head_q + 1'b1;
            open_batch_fill_q <= '0;
          end
        end else begin
          global_sram_occ_q <= global_sram_occ_q + s_pkt_cells_occ_c;
        end
        ingress_rr_q <= s_pkt_port + 1'b1;
      end

      if (|sram_read_req_c) begin
        deq_rr_q <= sram_read_grant_c + 1'b1;
        desc_release_q <= desc_release_q + 1'b1;
        sram_free_tail_q <= sram_free_tail_q + 1'b1;
        if (global_sram_occ_q != '0) begin
          global_sram_occ_q <= global_sram_occ_q - 1'b1;
        end
      end
      if (|ddr_read_req_c) begin
        ddr_rd_rr_q <= ddr_read_grant_c + 1'b1;
        if (global_ddr_occ_q != '0) begin
          global_ddr_occ_q <= global_ddr_occ_q - 1'b1;
        end
      end
      if (|ddr_write_req_c) begin
        ddr_wr_rr_q <= ddr_write_grant_c + 1'b1;
        batch_free_tail_q <= batch_free_tail_q + 1'b1;
      end
      if (occamy_reclaim_valid) begin
        reclaim_rr_q <= occamy_reclaim_port + 1'b1;
      end

      resource_digest <= queue_digest_flat[63:0] ^
                         queue_digest_flat[PORTS*64-1 -: 64] ^
                         {{(128-OCC_WIDTH){1'b0}}, global_sram_occ_q} ^
                         {{(128-OCC_WIDTH){1'b0}}, global_ddr_occ_q} ^
                         {{(128-BATCH_ID_W){1'b0}}, open_batch_id_q} ^
                         {{(128-DESC_W){1'b0}}, desc_alloc_q} ^
                         {{(128-RANK_WIDTH){1'b0}}, swapin_rank_c} ^
                         {{(128-RANK_WIDTH){1'b0}}, swapout_rank_c} ^
                         {{(128-PORTS){1'b0}}, occamy_over_bitmap};
    end
  end

endmodule
