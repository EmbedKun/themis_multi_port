`timescale 1ns/1ps

import hestia_pkg::*;

(* keep_hierarchy = "yes" *)
module hestia_bram_bank_sdp #(
  parameter int DATA_W = 64,
  parameter int BANK_DEPTH = 4096,
  localparam int BANK_ADDR_W = (BANK_DEPTH <= 2) ? 1 : $clog2(BANK_DEPTH)
) (
  input  logic                         clk,
  input  logic                         we,
  input  logic [BANK_ADDR_W-1:0]       wr_addr,
  input  logic [DATA_W-1:0]            wr_data,
  input  logic [BANK_ADDR_W-1:0]       rd_addr,
  output logic [DATA_W-1:0]            rd_data
);
  (* ram_style = "block" *) logic [DATA_W-1:0] mem [0:BANK_DEPTH-1];

  always_ff @(posedge clk) begin
    if (we) begin
      mem[wr_addr] <= wr_data;
    end
    rd_data <= mem[rd_addr];
  end
endmodule

(* keep_hierarchy = "yes" *)
module hestia_uram_bank64_sdp #(
  parameter int BANK_DEPTH = 4096,
  localparam int BANK_ADDR_W = (BANK_DEPTH <= 2) ? 1 : $clog2(BANK_DEPTH)
) (
  input  logic                         clk,
  input  logic                         we,
  input  logic [BANK_ADDR_W-1:0]       wr_addr,
  input  logic [63:0]                  wr_data,
  input  logic [BANK_ADDR_W-1:0]       rd_addr,
  output logic [63:0]                  rd_data
);
  (* ram_style = "ultra" *) logic [63:0] mem [0:BANK_DEPTH-1];

  always_ff @(posedge clk) begin
    if (we) begin
      mem[wr_addr] <= wr_data;
    end
    rd_data <= mem[rd_addr];
  end
endmodule

(* keep_hierarchy = "yes" *)
module hestia_bram_banked_sdp #(
  parameter int DATA_W = 64,
  parameter int TOTAL_DEPTH = 81920,
  parameter int BANK_DEPTH = 4096,
  localparam int ADDR_W = (TOTAL_DEPTH <= 2) ? 1 : $clog2(TOTAL_DEPTH),
  localparam int BANKS = (TOTAL_DEPTH + BANK_DEPTH - 1) / BANK_DEPTH,
  localparam int BANK_W = (BANKS <= 2) ? 1 : $clog2(BANKS),
  localparam int BANK_ADDR_W = (BANK_DEPTH <= 2) ? 1 : $clog2(BANK_DEPTH)
) (
  input  logic                         clk,
  input  logic                         wr_valid,
  input  logic [ADDR_W-1:0]            wr_addr,
  input  logic [DATA_W-1:0]            wr_data,
  input  logic [ADDR_W-1:0]            rd_addr,
  output logic [DATA_W-1:0]            rd_data
);
  logic [BANK_W-1:0] wr_bank_c;
  logic [BANK_W-1:0] rd_bank_c;
  logic [BANK_W-1:0] rd_bank_q;
  logic [BANK_ADDR_W-1:0] wr_local_c;
  logic [BANK_ADDR_W-1:0] rd_local_c;
  logic [BANKS*DATA_W-1:0] bank_rd_data;

  always_comb begin
    if (BANKS <= 1) begin
      wr_bank_c = '0;
      rd_bank_c = '0;
    end else begin
      wr_bank_c = BANK_W'(int'(wr_addr) / BANK_DEPTH);
      rd_bank_c = BANK_W'(int'(rd_addr) / BANK_DEPTH);
    end
    wr_local_c = BANK_ADDR_W'(int'(wr_addr) % BANK_DEPTH);
    rd_local_c = BANK_ADDR_W'(int'(rd_addr) % BANK_DEPTH);
  end

  genvar gb;
  generate
    for (gb = 0; gb < BANKS; gb = gb + 1) begin : gen_bram_bank
      hestia_bram_bank_sdp #(
        .DATA_W(DATA_W),
        .BANK_DEPTH(BANK_DEPTH)
      ) bank (
        .clk(clk),
        .we(wr_valid && (wr_bank_c == BANK_W'(gb))),
        .wr_addr(wr_local_c),
        .wr_data(wr_data),
        .rd_addr(rd_local_c),
        .rd_data(bank_rd_data[gb*DATA_W +: DATA_W])
      );
    end
  endgenerate

  always_ff @(posedge clk) begin
    rd_bank_q <= rd_bank_c;
  end

  always_comb begin
    rd_data = '0;
    for (int bi = 0; bi < BANKS; bi = bi + 1) begin
      if (rd_bank_q == BANK_W'(bi)) begin
        rd_data = bank_rd_data[bi*DATA_W +: DATA_W];
      end
    end
  end
endmodule

(* keep_hierarchy = "yes" *)
module hestia_payload_sram_banked #(
  parameter int TOTAL_CELLS = 81920,
  parameter int CELL_W = 512,
  parameter int LANE_W = 64,
  parameter int BANK_DEPTH = 4096,
  localparam int ADDR_W = (TOTAL_CELLS <= 2) ? 1 : $clog2(TOTAL_CELLS),
  localparam int LANES = CELL_W / LANE_W,
  localparam int BANKS = (TOTAL_CELLS + BANK_DEPTH - 1) / BANK_DEPTH,
  localparam int BANK_W = (BANKS <= 2) ? 1 : $clog2(BANKS),
  localparam int BANK_ADDR_W = (BANK_DEPTH <= 2) ? 1 : $clog2(BANK_DEPTH)
) (
  input  logic                         clk,
  input  logic                         wr_valid,
  input  logic [ADDR_W-1:0]            wr_addr,
  input  logic [CELL_W-1:0]            wr_data,
  input  logic [ADDR_W-1:0]            rd_addr,
  output logic [CELL_W-1:0]            rd_data
);
  logic [BANK_W-1:0] wr_bank_c;
  logic [BANK_W-1:0] rd_bank_c;
  logic [BANK_W-1:0] rd_bank_q;
  logic [BANK_ADDR_W-1:0] wr_local_c;
  logic [BANK_ADDR_W-1:0] rd_local_c;
  logic [BANKS*CELL_W-1:0] bank_rd_data;

  always_comb begin
    if (BANKS <= 1) begin
      wr_bank_c = '0;
      rd_bank_c = '0;
    end else begin
      wr_bank_c = BANK_W'(int'(wr_addr) / BANK_DEPTH);
      rd_bank_c = BANK_W'(int'(rd_addr) / BANK_DEPTH);
    end
    wr_local_c = BANK_ADDR_W'(int'(wr_addr) % BANK_DEPTH);
    rd_local_c = BANK_ADDR_W'(int'(rd_addr) % BANK_DEPTH);
  end

  genvar gb;
  genvar gl;
  generate
    for (gb = 0; gb < BANKS; gb = gb + 1) begin : gen_payload_bank
      for (gl = 0; gl < LANES; gl = gl + 1) begin : gen_payload_lane
        hestia_uram_bank64_sdp #(
          .BANK_DEPTH(BANK_DEPTH)
        ) bank_lane (
          .clk(clk),
          .we(wr_valid && (wr_bank_c == BANK_W'(gb))),
          .wr_addr(wr_local_c),
          .wr_data(wr_data[gl*LANE_W +: LANE_W]),
          .rd_addr(rd_local_c),
          .rd_data(bank_rd_data[gb*CELL_W + gl*LANE_W +: LANE_W])
        );
      end
    end
  endgenerate

  always_ff @(posedge clk) begin
    rd_bank_q <= rd_bank_c;
  end

  always_comb begin
    rd_data = '0;
    for (int bi = 0; bi < BANKS; bi = bi + 1) begin
      if (rd_bank_q == BANK_W'(bi)) begin
        rd_data = bank_rd_data[bi*CELL_W +: CELL_W];
      end
    end
  end
endmodule

module hestia_extmeta_tables #(
  parameter int PORT_W = 1,
  parameter int RANK_WIDTH = 10,
  parameter int SEQ_WIDTH = 16,
  parameter int PAYLOAD_WIDTH = 32,
  parameter int CELL_COUNT_WIDTH = 16,
  parameter int DESC_W = 17,
  parameter int SRAM_SLOT_W = 17,
  parameter int BATCH_ID_W = 23,
  parameter int BATCH_OFF_W = 3,
  parameter int COUNT_W = 27,
  parameter int SRAM_CELLS = 81920,
  parameter int PACKET_SLOTS = 81920,
  parameter int BATCH_SIZE = 8,
  parameter int ACTIVE_BATCH_SLOTS = 4096,
  parameter int PAYLOAD_CELL_WIDTH = 512,
  localparam int DESC_WORD_W = 1 + PORT_W + RANK_WIDTH + SEQ_WIDTH +
                               CELL_COUNT_WIDTH + PAYLOAD_WIDTH +
                               SRAM_SLOT_W + BATCH_ID_W + BATCH_OFF_W,
  localparam int ACTIVE_DEPTH =
    (ACTIVE_BATCH_SLOTS > (1 << BATCH_ID_W)) ? (1 << BATCH_ID_W) : ACTIVE_BATCH_SLOTS,
  localparam int ACTIVE_IDX_W = (ACTIVE_DEPTH <= 2) ? 1 : $clog2(ACTIVE_DEPTH),
  localparam int ACTIVE_TAG_W = (BATCH_ID_W > ACTIVE_IDX_W) ? (BATCH_ID_W - ACTIVE_IDX_W) : 1,
  localparam int ACTIVE_WORD_W = ACTIVE_TAG_W + 4 + COUNT_W + (BATCH_OFF_W + 1) +
                                 BATCH_SIZE + (BATCH_SIZE * DESC_W),
  localparam int PAYLOAD_COPY_W =
    (PAYLOAD_WIDTH < PAYLOAD_CELL_WIDTH) ? PAYLOAD_WIDTH : PAYLOAD_CELL_WIDTH
) (
  input  logic                              clk,
  input  logic                              resetn,
  output logic                              ready,

  input  logic                              desc_wr_valid,
  input  logic [DESC_W-1:0]                 desc_wr_addr,
  input  logic                              desc_wr_loc,
  input  logic [PORT_W-1:0]                 desc_wr_port,
  input  logic [RANK_WIDTH-1:0]             desc_wr_rank,
  input  logic [SEQ_WIDTH-1:0]              desc_wr_seq,
  input  logic [CELL_COUNT_WIDTH-1:0]       desc_wr_cell_count,
  input  logic [PAYLOAD_WIDTH-1:0]          desc_wr_payload,
  input  logic [SRAM_SLOT_W-1:0]            desc_wr_sram_base,
  input  logic [BATCH_ID_W-1:0]             desc_wr_batch_id,
  input  logic [BATCH_OFF_W-1:0]            desc_wr_batch_offset,

  input  logic                              desc_rd_valid,
  input  logic [DESC_W-1:0]                 desc_rd_addr,
  output logic                              desc_rd_loc,
  output logic [PORT_W-1:0]                 desc_rd_port,
  output logic [RANK_WIDTH-1:0]             desc_rd_rank,
  output logic [SEQ_WIDTH-1:0]              desc_rd_seq,
  output logic [CELL_COUNT_WIDTH-1:0]       desc_rd_cell_count,
  output logic [PAYLOAD_WIDTH-1:0]          desc_rd_payload,
  output logic [SRAM_SLOT_W-1:0]            desc_rd_sram_base,
  output logic [BATCH_ID_W-1:0]             desc_rd_batch_id,
  output logic [BATCH_OFF_W-1:0]            desc_rd_batch_offset,

  input  logic                              desc_free_valid,
  input  logic [DESC_W-1:0]                 desc_free_addr,

  input  logic                              sram_alloc_valid,
  input  logic [COUNT_W-1:0]                sram_alloc_cells,
  output logic [SRAM_SLOT_W-1:0]            sram_alloc_base,
  input  logic                              sram_release_valid,
  input  logic [SRAM_SLOT_W-1:0]            sram_release_base,
  input  logic [COUNT_W-1:0]                sram_release_cells,

  input  logic                              batch_append_valid,
  input  logic [BATCH_ID_W-1:0]             batch_append_id,
  input  logic [BATCH_OFF_W-1:0]            batch_append_offset,
  input  logic [DESC_W-1:0]                 batch_append_desc,
  input  logic [COUNT_W-1:0]                batch_append_cells,
  input  logic                              batch_commit_valid,
  input  logic [BATCH_ID_W-1:0]             batch_commit_id,
  input  logic                              batch_query_valid,
  input  logic [BATCH_ID_W-1:0]             batch_query_id,
  output logic [COUNT_W-1:0]                batch_query_valid_cells,
  output logic                              batch_query_committed,
  input  logic                              batch_release_valid,
  input  logic [BATCH_ID_W-1:0]             batch_release_id,

  output logic [63:0]                       digest
);
  logic [DESC_WORD_W-1:0] desc_wr_word_c;
  logic [DESC_WORD_W-1:0] desc_rd_word;
  logic [DESC_W-1:0] desc_free_rd_data;
  logic [SRAM_SLOT_W-1:0] sram_free_rd_data;
  logic [ACTIVE_WORD_W-1:0] active_wr_word_c;
  logic [ACTIVE_WORD_W-1:0] active_rd_word;
  logic [PAYLOAD_CELL_WIDTH-1:0] payload_wr_word_c;
  logic [PAYLOAD_CELL_WIDTH-1:0] payload_rd_word;
  logic [63:0] payload_seed_c;
  logic [63:0] desc_rd_xor_c;
  logic [63:0] active_rd_xor_c;
  logic [63:0] payload_rd_xor_c;

  logic [DESC_W-1:0] desc_free_wr_ptr_q;
  logic [DESC_W-1:0] desc_free_rd_ptr_q;
  logic [SRAM_SLOT_W-1:0] sram_free_wr_ptr_q;
  logic [SRAM_SLOT_W-1:0] sram_free_rd_ptr_q;
  logic [ACTIVE_IDX_W-1:0] active_wr_idx_c;
  logic [ACTIVE_IDX_W-1:0] active_rd_idx_c;
  logic [ACTIVE_TAG_W-1:0] batch_append_tag_c;
  logic [ACTIVE_TAG_W-1:0] batch_query_tag_c;

  function automatic logic [ACTIVE_IDX_W-1:0] active_index(input logic [BATCH_ID_W-1:0] batch_i);
    begin
      active_index = ACTIVE_IDX_W'(int'(batch_i) % ACTIVE_DEPTH);
    end
  endfunction

  function automatic logic [ACTIVE_TAG_W-1:0] active_tag(input logic [BATCH_ID_W-1:0] batch_i);
    begin
      if (BATCH_ID_W > ACTIVE_IDX_W) begin
        active_tag = batch_i[BATCH_ID_W-1:ACTIVE_IDX_W];
      end else begin
        active_tag = '0;
      end
    end
  endfunction

  always_comb begin
    desc_wr_word_c = {
      desc_wr_loc,
      desc_wr_port,
      desc_wr_rank,
      desc_wr_seq,
      desc_wr_cell_count,
      desc_wr_payload,
      desc_wr_sram_base,
      desc_wr_batch_id,
      desc_wr_batch_offset
    };

    payload_seed_c = 64'(desc_wr_payload) ^
                     (64'(desc_wr_sram_base) << 7) ^
                     (64'(desc_wr_batch_id) << 13) ^
                     (64'(desc_wr_seq) << 29) ^
                     (64'(desc_wr_rank) << 45) ^
                     (64'(desc_wr_cell_count) << 3);
    payload_seed_c = payload_seed_c ^
                     {payload_seed_c[30:0], payload_seed_c[63:31]} ^
                     {payload_seed_c[46:0], payload_seed_c[63:47]};
    payload_wr_word_c = '0;
    for (int li = 0; li < (PAYLOAD_CELL_WIDTH / 64); li = li + 1) begin
      payload_wr_word_c[li*64 +: 64] = payload_seed_c ^ 64'(li);
    end

    active_wr_idx_c = active_index(batch_append_valid ? batch_append_id :
                                   (batch_commit_valid ? batch_commit_id :
                                    (batch_release_valid ? batch_release_id : batch_query_id)));
    active_rd_idx_c = active_index(batch_query_id);
    batch_append_tag_c = active_tag(batch_append_id);
    batch_query_tag_c = active_tag(batch_query_id);

    active_wr_word_c = '0;
    active_wr_word_c[0 +: ACTIVE_TAG_W] = batch_append_tag_c;
    active_wr_word_c[ACTIVE_TAG_W +: 4] = {
      batch_commit_valid,
      batch_append_valid,
      1'b0,
      !batch_release_valid
    };
    active_wr_word_c[ACTIVE_TAG_W + 4 +: COUNT_W] = batch_append_cells;
    active_wr_word_c[ACTIVE_TAG_W + 4 + COUNT_W +: (BATCH_OFF_W + 1)] =
      {1'b0, batch_append_offset} + batch_append_cells[BATCH_OFF_W:0];
    active_wr_word_c[ACTIVE_TAG_W + 4 + COUNT_W + (BATCH_OFF_W + 1) +: BATCH_SIZE] =
      {BATCH_SIZE{batch_append_valid}};
    for (int ci = 0; ci < BATCH_SIZE; ci = ci + 1) begin
      active_wr_word_c[ACTIVE_TAG_W + 4 + COUNT_W + (BATCH_OFF_W + 1) +
                       BATCH_SIZE + ci*DESC_W +: DESC_W] =
        batch_append_desc ^ DESC_W'(ci);
    end

    {desc_rd_loc,
     desc_rd_port,
     desc_rd_rank,
     desc_rd_seq,
     desc_rd_cell_count,
     desc_rd_payload,
     desc_rd_sram_base,
     desc_rd_batch_id,
     desc_rd_batch_offset} = desc_rd_word;

    sram_alloc_base = sram_free_rd_data;
    batch_query_valid_cells = active_rd_word[ACTIVE_TAG_W + 4 +: COUNT_W];
    batch_query_committed = (active_rd_word[0 +: ACTIVE_TAG_W] == batch_query_tag_c) &&
                            active_rd_word[ACTIVE_TAG_W + 3];

    desc_rd_xor_c = '0;
    for (int xi = 0; xi < DESC_WORD_W; xi = xi + 1) begin
      desc_rd_xor_c[xi % 64] = desc_rd_xor_c[xi % 64] ^ desc_rd_word[xi];
    end
    active_rd_xor_c = '0;
    for (int xi = 0; xi < ACTIVE_WORD_W; xi = xi + 1) begin
      active_rd_xor_c[xi % 64] = active_rd_xor_c[xi % 64] ^ active_rd_word[xi];
    end
    payload_rd_xor_c = '0;
    for (int xi = 0; xi < PAYLOAD_CELL_WIDTH; xi = xi + 1) begin
      payload_rd_xor_c[xi % 64] = payload_rd_xor_c[xi % 64] ^ payload_rd_word[xi];
    end
  end

  hestia_bram_banked_sdp #(
    .DATA_W(DESC_WORD_W),
    .TOTAL_DEPTH(PACKET_SLOTS),
    .BANK_DEPTH(4096)
  ) desc_table (
    .clk(clk),
    .wr_valid(desc_wr_valid),
    .wr_addr(desc_wr_addr),
    .wr_data(desc_wr_word_c),
    .rd_addr(desc_rd_addr),
    .rd_data(desc_rd_word)
  );

  hestia_bram_banked_sdp #(
    .DATA_W(DESC_W),
    .TOTAL_DEPTH(PACKET_SLOTS),
    .BANK_DEPTH(4096)
  ) desc_free_list (
    .clk(clk),
    .wr_valid(desc_free_valid),
    .wr_addr(desc_free_wr_ptr_q),
    .wr_data(desc_free_addr),
    .rd_addr(desc_free_rd_ptr_q),
    .rd_data(desc_free_rd_data)
  );

  hestia_bram_banked_sdp #(
    .DATA_W(SRAM_SLOT_W),
    .TOTAL_DEPTH(SRAM_CELLS),
    .BANK_DEPTH(4096)
  ) sram_free_list (
    .clk(clk),
    .wr_valid(sram_release_valid),
    .wr_addr(sram_free_wr_ptr_q),
    .wr_data(sram_release_base),
    .rd_addr(sram_free_rd_ptr_q),
    .rd_data(sram_free_rd_data)
  );

  hestia_bram_banked_sdp #(
    .DATA_W(ACTIVE_WORD_W),
    .TOTAL_DEPTH(ACTIVE_DEPTH),
    .BANK_DEPTH(4096)
  ) active_batch_window (
    .clk(clk),
    .wr_valid(batch_append_valid || batch_commit_valid || batch_release_valid),
    .wr_addr(active_wr_idx_c),
    .wr_data(active_wr_word_c),
    .rd_addr(active_rd_idx_c),
    .rd_data(active_rd_word)
  );

  hestia_payload_sram_banked #(
    .TOTAL_CELLS(SRAM_CELLS),
    .CELL_W(PAYLOAD_CELL_WIDTH),
    .LANE_W(64),
    .BANK_DEPTH(4096)
  ) sram_payload (
    .clk(clk),
    .wr_valid(desc_wr_valid && !desc_wr_loc),
    .wr_addr(desc_wr_sram_base),
    .wr_data(payload_wr_word_c),
    .rd_addr(sram_release_base),
    .rd_data(payload_rd_word)
  );

  always_ff @(posedge clk) begin
    if (!resetn) begin
      ready <= 1'b0;
      desc_free_wr_ptr_q <= '0;
      desc_free_rd_ptr_q <= '0;
      sram_free_wr_ptr_q <= '0;
      sram_free_rd_ptr_q <= '0;
      digest <= '0;
    end else begin
      ready <= 1'b1;
      if (desc_free_valid) begin
        desc_free_wr_ptr_q <= desc_free_wr_ptr_q + 1'b1;
      end
      if (desc_wr_valid) begin
        desc_free_rd_ptr_q <= desc_free_rd_ptr_q + 1'b1;
      end
      if (sram_release_valid) begin
        sram_free_wr_ptr_q <= sram_free_wr_ptr_q + sram_release_cells[SRAM_SLOT_W-1:0];
      end
      if (sram_alloc_valid) begin
        sram_free_rd_ptr_q <= sram_free_rd_ptr_q + sram_alloc_cells[SRAM_SLOT_W-1:0];
      end
      digest <= digest ^
                desc_rd_xor_c ^
                {{(64-DESC_W){1'b0}}, desc_free_rd_data} ^
                {{(64-SRAM_SLOT_W){1'b0}}, sram_free_rd_data} ^
                active_rd_xor_c ^
                payload_rd_xor_c;
    end
  end
endmodule

module hestia_core_ddr_bbq_extmeta #(
  parameter int PORTS = 2,
  parameter int RANK_WIDTH = 10,
  parameter int SEQ_WIDTH = 16,
  parameter int PAYLOAD_WIDTH = 32,
  parameter int CELL_COUNT_WIDTH = 16,
  parameter int AXI_ADDR_WIDTH = 64,
  parameter int AXI_DATA_WIDTH = 512,
  parameter int AXI_ID_WIDTH = 4,
  parameter int SRAM_CELLS = 81920,
  parameter int BATCH_SIZE = 8,
  parameter int BATCH_SLOTS = 8388608,
  parameter int PACKET_SLOTS = 81920,
  parameter int BBQ_BITMAP_WIDTH = 32,
  parameter int POLICY_MODE = -1,
  parameter int POLICY_ALPHA_SHIFT = 0,
  parameter int POLICY_ALPHA_SHIFT_WIDTH = 4,
  parameter bit ENABLE_DDR_META_CHECK = 1'b0,
  parameter logic [AXI_ADDR_WIDTH-1:0] DDR_BASE_ADDR = 64'h0,
  localparam int PORT_W = (PORTS <= 2) ? 1 : $clog2(PORTS),
  localparam int SRAM_SLOT_W = (SRAM_CELLS <= 2) ? 1 : $clog2(SRAM_CELLS),
  localparam int BATCH_ID_W = (BATCH_SLOTS <= 2) ? 1 : $clog2(BATCH_SLOTS),
  localparam int BATCH_OFF_W = (BATCH_SIZE <= 2) ? 1 : $clog2(BATCH_SIZE),
  localparam int DESC_W = (PACKET_SLOTS <= 2) ? 1 : $clog2(PACKET_SLOTS),
  localparam int AXI_KEEP_WIDTH = AXI_DATA_WIDTH / 8,
  localparam int SRAM_COUNT_W = $clog2(SRAM_CELLS + 1),
  localparam int DDR_CELL_CAPACITY = BATCH_SLOTS * BATCH_SIZE,
  localparam int DDR_COUNT_W = $clog2(DDR_CELL_CAPACITY + 1),
  localparam int PACKET_COUNT_W = $clog2(PACKET_SLOTS + 1),
  localparam int COUNT_BASE_W = (SRAM_COUNT_W > DDR_COUNT_W) ? SRAM_COUNT_W : DDR_COUNT_W,
  localparam int COUNT_BASE2_W = (COUNT_BASE_W > PACKET_COUNT_W) ? COUNT_BASE_W : PACKET_COUNT_W,
  localparam int COUNT_W = (COUNT_BASE2_W > CELL_COUNT_WIDTH) ? COUNT_BASE2_W : CELL_COUNT_WIDTH,
  localparam int PAYLOAD_COPY_W = (PAYLOAD_WIDTH < DESC_W) ? PAYLOAD_WIDTH : DESC_W
) (
  input  logic                              clk,
  input  logic                              resetn,
  input  logic                              enable,
  input  logic [15:0]                       cfg_swap_in_threshold,
  input  logic [15:0]                       cfg_swap_out_threshold,

  input  logic                              s_pkt_valid,
  output logic                              s_pkt_ready,
  input  logic [PORT_W-1:0]                 s_pkt_port,
  input  logic [RANK_WIDTH-1:0]             s_pkt_rank,
  input  logic [SEQ_WIDTH-1:0]              s_pkt_seq,
  input  logic [CELL_COUNT_WIDTH-1:0]       s_pkt_cell_count,
  input  logic [PAYLOAD_WIDTH-1:0]          s_pkt_payload,

  input  logic [PORTS-1:0]                  dequeue_enable,
  output logic [PORTS-1:0]                  m_pkt_valid,
  input  logic [PORTS-1:0]                  m_pkt_ready,
  output logic [PORTS*RANK_WIDTH-1:0]       m_pkt_rank,
  output logic [PORTS*SEQ_WIDTH-1:0]        m_pkt_seq,
  output logic [PORTS*CELL_COUNT_WIDTH-1:0] m_pkt_cell_count,
  output logic [PORTS*PAYLOAD_WIDTH-1:0]    m_pkt_payload,

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

  output logic [31:0]                       stat_generated,
  output logic [31:0]                       stat_dequeued,
  output logic [31:0]                       stat_sram_admit,
  output logic [31:0]                       stat_hbm_admit,
  output logic [31:0]                       stat_swap_out,
  output logic [31:0]                       stat_swap_in,
  output logic [31:0]                       stat_direct_hbm_dequeue,
  output logic [31:0]                       stat_drop,
  output logic [31:0]                       stat_batch_submit,
  output logic [31:0]                       stat_ddr_write_beats,
  output logic [31:0]                       stat_ddr_read_beats,
  output logic [31:0]                       stat_ddr_write_batches,
  output logic [31:0]                       stat_ddr_read_batches,
  output logic [15:0]                       dbg_global_sram_occupancy,
  output logic [15:0]                       dbg_global_hbm_occupancy,
  output logic [PORTS*16-1:0]               dbg_sram_count_flat,
  output logic [PORTS*16-1:0]               dbg_hbm_count_flat,
  output logic [15:0]                       dbg_open_batch_cells,
  output logic [7:0]                        dbg_ddr_state,
  output logic                              dbg_ddr_wr_error,
  output logic                              dbg_ddr_rd_error
);
  localparam int POLICY_THEMIS = -1;
  localparam int POLICY_DT = 0;
  localparam int POLICY_OCCAMY_HEAD = 1;
  localparam int POLICY_OCCAMY_MAX = 2;
  localparam int POLICY_OBM = 3;
  localparam int POLICY_HYBRID_THEMIS = 4;
  localparam logic [COUNT_W-1:0] SRAM_CELLS_COUNT = SRAM_CELLS;
  localparam logic [COUNT_W-1:0] DDR_CELL_CAPACITY_COUNT = DDR_CELL_CAPACITY;
  localparam logic [COUNT_W-1:0] PACKET_SLOTS_COUNT = PACKET_SLOTS;
  localparam logic [COUNT_W-1:0] BATCH_SLOTS_COUNT = BATCH_SLOTS;
  localparam logic [COUNT_W-1:0] BATCH_SIZE_COUNT = BATCH_SIZE;
  localparam logic [POLICY_ALPHA_SHIFT_WIDTH-1:0] POLICY_ALPHA_SHIFT_VALUE = POLICY_ALPHA_SHIFT;

  typedef enum logic [1:0] {
    WR_IDLE,
    WR_ADDR,
    WR_DATA,
    WR_RESP
  } wr_state_t;

  typedef enum logic [1:0] {
    RD_IDLE,
    RD_ADDR,
    RD_DATA
  } rd_state_t;

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
  logic [PORTS*CELL_COUNT_WIDTH-1:0] sram_min_cell_count;
  logic [PORTS-1:0] sram_max_valid;
  logic [PORTS*RANK_WIDTH-1:0] sram_max_rank;
  logic [PORTS*SEQ_WIDTH-1:0] sram_max_seq;
  logic [PORTS*DESC_W-1:0] sram_max_desc;
  logic [PORTS*CELL_COUNT_WIDTH-1:0] sram_max_cell_count;
  logic [PORTS-1:0] hbm_min_valid;
  logic [PORTS*RANK_WIDTH-1:0] hbm_min_rank;
  logic [PORTS*SEQ_WIDTH-1:0] hbm_min_seq;
  logic [PORTS*DESC_W-1:0] hbm_min_desc;
  logic [PORTS*CELL_COUNT_WIDTH-1:0] hbm_min_cell_count;
  logic [PORTS*BATCH_ID_W-1:0] hbm_min_batch_id;
  logic [PORTS*BATCH_OFF_W-1:0] hbm_min_batch_off;
  logic [PORTS*COUNT_W-1:0] sram_occ_flat;
  logic [PORTS*COUNT_W-1:0] hbm_occ_flat;
  logic [PORTS*COUNT_W-1:0] policy_sram_occ_flat_c;
  logic [PORTS*64-1:0] queue_digest_flat;

  logic [COUNT_W-1:0] sram_count_q [0:PORTS-1];
  logic [COUNT_W-1:0] hbm_count_q [0:PORTS-1];
  logic [COUNT_W-1:0] global_sram_occ_q;
  logic [COUNT_W-1:0] global_hbm_occ_q;
  logic [COUNT_W-1:0] desc_free_count_q;
  logic [COUNT_W-1:0] sram_free_count_q;
  logic [COUNT_W-1:0] batch_free_count_q;
  logic [COUNT_W-1:0] ddr_free_cell_count_q;

  logic [DESC_W-1:0] desc_alloc_head_q;
  logic [DESC_W-1:0] desc_free_tail_q;
  logic [SRAM_SLOT_W-1:0] sram_alloc_head_q;
  logic [SRAM_SLOT_W-1:0] sram_release_tail_q;
  logic [BATCH_ID_W-1:0] batch_alloc_head_q;
  logic [BATCH_ID_W-1:0] batch_release_tail_q;
  logic open_batch_valid_q;
  logic [BATCH_ID_W-1:0] open_batch_id_q;
  logic [BATCH_OFF_W:0] open_batch_fill_q;

  logic [PORTS-1:0] out_valid_q;
  logic [PORTS*RANK_WIDTH-1:0] out_rank_q;
  logic [PORTS*SEQ_WIDTH-1:0] out_seq_q;
  logic [PORTS*CELL_COUNT_WIDTH-1:0] out_cell_count_q;
  logic [PORTS*PAYLOAD_WIDTH-1:0] out_payload_q;

  logic [PORT_W-1:0] ingress_rr_q;
  logic [PORT_W-1:0] deq_rr_q;
  logic [PORT_W-1:0] swap_rr_q;
  logic [PORT_W-1:0] wr_rr_q;
  logic [PORT_W-1:0] rd_rr_q;

  logic [COUNT_W-1:0] pkt_cells_c;
  logic pkt_cells_ok_c;
  logic sram_can_fit_c;
  logic ddr_can_fit_c;
  logic policy_admit_c;
  logic [COUNT_W-1:0] policy_threshold_c;
  logic [PORTS-1:0] occamy_over_threshold_c;
  logic occamy_reclaim_valid_c;
  logic [PORT_W-1:0] occamy_reclaim_port_c;
  logic obm_longest_valid_c;
  logic [PORT_W-1:0] obm_longest_port_c;
  logic [COUNT_W-1:0] obm_longest_occ_c;
  logic obm_pkt_targets_longest_c;
  logic hybrid_policy_admit_c;
  logic [COUNT_W-1:0] hybrid_policy_threshold_c;
  logic [PORTS-1:0] hybrid_over_threshold_c;
  logic [PORTS-1:0] hybrid_under_threshold_c;
  logic hybrid_swapout_hint_valid_c;
  logic [PORT_W-1:0] hybrid_swapout_hint_port_c;
  logic hybrid_swapin_hint_valid_c;
  logic [PORT_W-1:0] hybrid_swapin_hint_port_c;
  logic [63:0] hybrid_policy_digest_c;
  logic [63:0] selected_policy_digest_c;

  logic ingress_fire_c;
  logic ingress_to_sram_c;
  logic ingress_to_hbm_c;
  logic [PORTS-1:0] deq_req_c;
  logic deq_fire_c;
  logic [PORT_W-1:0] deq_port_c;
  logic deq_from_sram_c;
  logic [DESC_W-1:0] deq_desc_c;
  logic [RANK_WIDTH-1:0] deq_rank_c;
  logic [SEQ_WIDTH-1:0] deq_seq_c;
  logic [CELL_COUNT_WIDTH-1:0] deq_cells_raw_c;
  logic [COUNT_W-1:0] deq_cells_c;
  logic [BATCH_ID_W-1:0] deq_batch_c;
  logic [BATCH_OFF_W-1:0] deq_batch_off_c;

  logic swapout_valid_c;
  logic [PORT_W-1:0] swapout_port_c;
  logic [DESC_W-1:0] swapout_desc_c;
  logic [RANK_WIDTH-1:0] swapout_rank_c;
  logic [SEQ_WIDTH-1:0] swapout_seq_c;
  logic [CELL_COUNT_WIDTH-1:0] swapout_cells_raw_c;
  logic [COUNT_W-1:0] swapout_cells_c;
  logic swapin_valid_c;
  logic [PORT_W-1:0] swapin_port_c;
  logic [DESC_W-1:0] swapin_desc_c;
  logic [RANK_WIDTH-1:0] swapin_rank_c;
  logic [SEQ_WIDTH-1:0] swapin_seq_c;
  logic [CELL_COUNT_WIDTH-1:0] swapin_cells_raw_c;
  logic [COUNT_W-1:0] swapin_cells_c;
  logic [BATCH_ID_W-1:0] swapin_batch_c;
  logic [BATCH_OFF_W-1:0] swapin_batch_off_c;

  wr_state_t wr_state_q;
  logic [BATCH_ID_W-1:0] wr_batch_q;
  logic [BATCH_OFF_W:0] wr_beat_q;
  logic wr_start_c;
  logic [BATCH_ID_W-1:0] wr_start_batch_c;
  rd_state_t rd_state_q;
  logic rd_start_c;
  logic rd_direct_q;
  logic [PORT_W-1:0] rd_port_q;
  logic [DESC_W-1:0] rd_desc_q;
  logic [RANK_WIDTH-1:0] rd_rank_q;
  logic [SEQ_WIDTH-1:0] rd_seq_q;
  logic [CELL_COUNT_WIDTH-1:0] rd_cells_raw_q;
  logic [COUNT_W-1:0] rd_cells_q;
  logic [BATCH_ID_W-1:0] rd_batch_q;
  logic [BATCH_OFF_W:0] rd_beat_q;

  logic meta_ready;
  logic [63:0] meta_digest;
  logic meta_desc_wr_valid_q;
  logic [DESC_W-1:0] meta_desc_wr_addr_q;
  logic meta_desc_wr_loc_q;
  logic [PORT_W-1:0] meta_desc_wr_port_q;
  logic [RANK_WIDTH-1:0] meta_desc_wr_rank_q;
  logic [SEQ_WIDTH-1:0] meta_desc_wr_seq_q;
  logic [CELL_COUNT_WIDTH-1:0] meta_desc_wr_cell_count_q;
  logic [PAYLOAD_WIDTH-1:0] meta_desc_wr_payload_q;
  logic [SRAM_SLOT_W-1:0] meta_desc_wr_sram_base_q;
  logic [BATCH_ID_W-1:0] meta_desc_wr_batch_id_q;
  logic [BATCH_OFF_W-1:0] meta_desc_wr_batch_offset_q;
  logic meta_desc_rd_valid_q;
  logic [DESC_W-1:0] meta_desc_rd_addr_q;
  logic meta_desc_free_valid_q;
  logic [DESC_W-1:0] meta_desc_free_addr_q;
  logic meta_sram_alloc_valid_q;
  logic [COUNT_W-1:0] meta_sram_alloc_cells_q;
  logic [SRAM_SLOT_W-1:0] meta_sram_alloc_base;
  logic meta_sram_release_valid_q;
  logic [SRAM_SLOT_W-1:0] meta_sram_release_base_q;
  logic [COUNT_W-1:0] meta_sram_release_cells_q;
  logic meta_batch_append_valid_q;
  logic [BATCH_ID_W-1:0] meta_batch_append_id_q;
  logic [BATCH_OFF_W-1:0] meta_batch_append_offset_q;
  logic [DESC_W-1:0] meta_batch_append_desc_q;
  logic [COUNT_W-1:0] meta_batch_append_cells_q;
  logic meta_batch_commit_valid_q;
  logic [BATCH_ID_W-1:0] meta_batch_commit_id_q;
  logic meta_batch_query_valid_q;
  logic [BATCH_ID_W-1:0] meta_batch_query_id_q;
  logic [COUNT_W-1:0] meta_batch_query_valid_cells;
  logic meta_batch_query_committed;
  logic meta_batch_release_valid_q;
  logic [BATCH_ID_W-1:0] meta_batch_release_id_q;

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

  function automatic logic [COUNT_W-1:0] cell_count_count(
    input logic [CELL_COUNT_WIDTH-1:0] cells_i
  );
    begin
      cell_count_count = {{(COUNT_W-CELL_COUNT_WIDTH){1'b0}}, cells_i};
    end
  endfunction

  function automatic logic count_after_add_leq(
    input logic [COUNT_W-1:0] a_i,
    input logic [COUNT_W-1:0] b_i,
    input logic [COUNT_W-1:0] limit_i
  );
    logic [COUNT_W:0] sum_v;
    begin
      sum_v = {1'b0, a_i} + {1'b0, b_i};
      count_after_add_leq = !sum_v[COUNT_W] && (sum_v[COUNT_W-1:0] <= limit_i);
    end
  endfunction

  function automatic logic [15:0] sat16(input logic [COUNT_W-1:0] value_i);
    begin
      if (COUNT_W > 16) begin
        sat16 = (|value_i[COUNT_W-1:16]) ? 16'hffff : value_i[15:0];
      end else begin
        sat16 = {{(16-COUNT_W){1'b0}}, value_i};
      end
    end
  endfunction

  function automatic logic [AXI_ADDR_WIDTH-1:0] ddr_batch_addr(
    input logic [BATCH_ID_W-1:0] batch_i
  );
    localparam int BATCH_BYTES = BATCH_SIZE * (AXI_DATA_WIDTH / 8);
    begin
      ddr_batch_addr = DDR_BASE_ADDR + (AXI_ADDR_WIDTH'(batch_i) * BATCH_BYTES);
    end
  endfunction

  function automatic logic [PAYLOAD_WIDTH-1:0] payload_from_desc(input logic [DESC_W-1:0] desc_i);
    begin
      payload_from_desc = '0;
      payload_from_desc[PAYLOAD_COPY_W-1:0] = desc_i[PAYLOAD_COPY_W-1:0];
    end
  endfunction

  function automatic logic [AXI_DATA_WIDTH-1:0] pack_axi_digest_cell(
    input logic [DESC_W-1:0] desc_i,
    input logic [RANK_WIDTH-1:0] rank_i,
    input logic [SEQ_WIDTH-1:0] seq_i,
    input logic [CELL_COUNT_WIDTH-1:0] cells_i,
    input logic [BATCH_OFF_W-1:0] off_i,
    input logic [PAYLOAD_WIDTH-1:0] payload_i
  );
    logic [AXI_DATA_WIDTH-1:0] word_v;
    int pos_v;
    begin
      word_v = '0;
      pos_v = 0;
      word_v[pos_v +: PAYLOAD_WIDTH] = payload_i;
      pos_v = pos_v + PAYLOAD_WIDTH;
      word_v[pos_v +: SEQ_WIDTH] = seq_i;
      pos_v = pos_v + SEQ_WIDTH;
      word_v[pos_v +: RANK_WIDTH] = rank_i;
      pos_v = pos_v + RANK_WIDTH;
      word_v[pos_v +: CELL_COUNT_WIDTH] = cells_i;
      pos_v = pos_v + CELL_COUNT_WIDTH;
      word_v[pos_v +: DESC_W] = desc_i;
      pos_v = pos_v + DESC_W;
      word_v[pos_v +: BATCH_OFF_W] = off_i;
      pack_axi_digest_cell = word_v;
    end
  endfunction

  genvar gp;
  generate
    for (gp = 0; gp < PORTS; gp = gp + 1) begin : gen_ext_port_queue
      hestia_paper_scale_port_queue #(
        .RANK_WIDTH(RANK_WIDTH),
        .SEQ_WIDTH(SEQ_WIDTH),
        .CELL_COUNT_WIDTH(CELL_COUNT_WIDTH),
        .DESC_W(DESC_W),
        .BATCH_ID_W(BATCH_ID_W),
        .BATCH_OFF_W(BATCH_OFF_W),
        .BBQ_BITMAP_WIDTH(BBQ_BITMAP_WIDTH),
        .OCC_WIDTH(COUNT_W)
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
        .sram_min_cell_count(sram_min_cell_count[gp*CELL_COUNT_WIDTH +: CELL_COUNT_WIDTH]),
        .sram_max_valid(sram_max_valid[gp]),
        .sram_max_rank(sram_max_rank[gp*RANK_WIDTH +: RANK_WIDTH]),
        .sram_max_seq(sram_max_seq[gp*SEQ_WIDTH +: SEQ_WIDTH]),
        .sram_max_desc(sram_max_desc[gp*DESC_W +: DESC_W]),
        .sram_max_cell_count(sram_max_cell_count[gp*CELL_COUNT_WIDTH +: CELL_COUNT_WIDTH]),
        .ddr_min_valid(hbm_min_valid[gp]),
        .ddr_min_rank(hbm_min_rank[gp*RANK_WIDTH +: RANK_WIDTH]),
        .ddr_min_seq(hbm_min_seq[gp*SEQ_WIDTH +: SEQ_WIDTH]),
        .ddr_min_desc(hbm_min_desc[gp*DESC_W +: DESC_W]),
        .ddr_min_cell_count(hbm_min_cell_count[gp*CELL_COUNT_WIDTH +: CELL_COUNT_WIDTH]),
        .ddr_min_batch_id(hbm_min_batch_id[gp*BATCH_ID_W +: BATCH_ID_W]),
        .ddr_min_batch_off(hbm_min_batch_off[gp*BATCH_OFF_W +: BATCH_OFF_W]),
        .sram_occupancy(sram_occ_flat[gp*COUNT_W +: COUNT_W]),
        .ddr_occupancy(hbm_occ_flat[gp*COUNT_W +: COUNT_W]),
        .digest(queue_digest_flat[gp*64 +: 64])
      );

      assign dbg_sram_count_flat[gp*16 +: 16] = sat16(sram_count_q[gp]);
      assign dbg_hbm_count_flat[gp*16 +: 16] = sat16(hbm_count_q[gp]);
      assign policy_sram_occ_flat_c[gp*COUNT_W +: COUNT_W] = sram_count_q[gp];
    end
  endgenerate

  hestia_policy_dt #(
    .PORTS(PORTS),
    .CELL_COUNT_WIDTH(CELL_COUNT_WIDTH),
    .OCC_WIDTH(COUNT_W),
    .ALPHA_SHIFT_WIDTH(POLICY_ALPHA_SHIFT_WIDTH)
  ) dt_policy (
    .cfg_alpha_shift(POLICY_ALPHA_SHIFT_VALUE),
    .pkt_valid(s_pkt_valid),
    .pkt_port(s_pkt_port),
    .pkt_cell_count(s_pkt_cell_count),
    .free_cells(sram_free_count_q),
    .port_occ_flat(policy_sram_occ_flat_c),
    .pkt_admit(policy_admit_c),
    .threshold(policy_threshold_c)
  );

  hestia_policy_occamy #(
    .PORTS(PORTS),
    .CELL_COUNT_WIDTH(CELL_COUNT_WIDTH),
    .OCC_WIDTH(COUNT_W),
    .ALPHA_SHIFT_WIDTH(POLICY_ALPHA_SHIFT_WIDTH)
  ) occamy_policy (
    .clk(clk),
    .resetn(resetn),
    .cfg_alpha_shift(POLICY_ALPHA_SHIFT_VALUE),
    .reclaim_enable(enable),
    .reclaim_fire(swapout_valid_c),
    .pkt_valid(s_pkt_valid),
    .pkt_port(s_pkt_port),
    .pkt_cell_count(s_pkt_cell_count),
    .free_cells(sram_free_count_q),
    .port_occ_flat(policy_sram_occ_flat_c),
    .pkt_admit(),
    .threshold(),
    .over_threshold_bitmap(occamy_over_threshold_c),
    .reclaim_valid(occamy_reclaim_valid_c),
    .reclaim_port(occamy_reclaim_port_c)
  );

  hestia_policy_obm #(
    .PORTS(PORTS),
    .OCC_WIDTH(COUNT_W)
  ) obm_policy (
    .port_occ_flat(policy_sram_occ_flat_c),
    .pkt_port(s_pkt_port),
    .pkt_valid(s_pkt_valid),
    .longest_valid(obm_longest_valid_c),
    .longest_port(obm_longest_port_c),
    .longest_occupancy(obm_longest_occ_c),
    .pkt_targets_longest(obm_pkt_targets_longest_c)
  );

  hestia_policy_hybrid_themis #(
    .PORTS(PORTS),
    .CELL_COUNT_WIDTH(CELL_COUNT_WIDTH),
    .OCC_WIDTH(COUNT_W),
    .ALPHA_SHIFT_WIDTH(POLICY_ALPHA_SHIFT_WIDTH)
  ) hybrid_themis_policy (
    .clk(clk),
    .resetn(resetn),
    .cfg_alpha_shift(POLICY_ALPHA_SHIFT_VALUE),
    .pkt_valid(s_pkt_valid),
    .pkt_port(s_pkt_port),
    .pkt_cell_count(s_pkt_cell_count),
    .free_cells(sram_free_count_q),
    .sram_occ_flat(policy_sram_occ_flat_c),
    .ddr_occ_flat(hbm_occ_flat),
    .pkt_admit(hybrid_policy_admit_c),
    .threshold(hybrid_policy_threshold_c),
    .over_threshold_bitmap(hybrid_over_threshold_c),
    .under_threshold_bitmap(hybrid_under_threshold_c),
    .swapout_hint_valid(hybrid_swapout_hint_valid_c),
    .swapout_hint_port(hybrid_swapout_hint_port_c),
    .swapin_hint_valid(hybrid_swapin_hint_valid_c),
    .swapin_hint_port(hybrid_swapin_hint_port_c),
    .digest(hybrid_policy_digest_c)
  );

  assign selected_policy_digest_c =
      (POLICY_MODE == POLICY_HYBRID_THEMIS) ? hybrid_policy_digest_c : 64'd0;

  (* dont_touch = "true" *) hestia_extmeta_tables #(
    .PORT_W(PORT_W),
    .RANK_WIDTH(RANK_WIDTH),
    .SEQ_WIDTH(SEQ_WIDTH),
    .PAYLOAD_WIDTH(PAYLOAD_WIDTH),
    .CELL_COUNT_WIDTH(CELL_COUNT_WIDTH),
    .DESC_W(DESC_W),
    .SRAM_SLOT_W(SRAM_SLOT_W),
    .BATCH_ID_W(BATCH_ID_W),
    .BATCH_OFF_W(BATCH_OFF_W),
    .COUNT_W(COUNT_W),
    .SRAM_CELLS(SRAM_CELLS),
    .PACKET_SLOTS(PACKET_SLOTS),
    .BATCH_SIZE(BATCH_SIZE),
    .ACTIVE_BATCH_SLOTS(4096),
    .PAYLOAD_CELL_WIDTH(AXI_DATA_WIDTH)
  ) meta_tables (
    .clk(clk),
    .resetn(resetn),
    .ready(meta_ready),
    .desc_wr_valid(meta_desc_wr_valid_q),
    .desc_wr_addr(meta_desc_wr_addr_q),
    .desc_wr_loc(meta_desc_wr_loc_q),
    .desc_wr_port(meta_desc_wr_port_q),
    .desc_wr_rank(meta_desc_wr_rank_q),
    .desc_wr_seq(meta_desc_wr_seq_q),
    .desc_wr_cell_count(meta_desc_wr_cell_count_q),
    .desc_wr_payload(meta_desc_wr_payload_q),
    .desc_wr_sram_base(meta_desc_wr_sram_base_q),
    .desc_wr_batch_id(meta_desc_wr_batch_id_q),
    .desc_wr_batch_offset(meta_desc_wr_batch_offset_q),
    .desc_rd_valid(meta_desc_rd_valid_q),
    .desc_rd_addr(meta_desc_rd_addr_q),
    .desc_rd_loc(),
    .desc_rd_port(),
    .desc_rd_rank(),
    .desc_rd_seq(),
    .desc_rd_cell_count(),
    .desc_rd_payload(),
    .desc_rd_sram_base(),
    .desc_rd_batch_id(),
    .desc_rd_batch_offset(),
    .desc_free_valid(meta_desc_free_valid_q),
    .desc_free_addr(meta_desc_free_addr_q),
    .sram_alloc_valid(meta_sram_alloc_valid_q),
    .sram_alloc_cells(meta_sram_alloc_cells_q),
    .sram_alloc_base(meta_sram_alloc_base),
    .sram_release_valid(meta_sram_release_valid_q),
    .sram_release_base(meta_sram_release_base_q),
    .sram_release_cells(meta_sram_release_cells_q),
    .batch_append_valid(meta_batch_append_valid_q),
    .batch_append_id(meta_batch_append_id_q),
    .batch_append_offset(meta_batch_append_offset_q),
    .batch_append_desc(meta_batch_append_desc_q),
    .batch_append_cells(meta_batch_append_cells_q),
    .batch_commit_valid(meta_batch_commit_valid_q),
    .batch_commit_id(meta_batch_commit_id_q),
    .batch_query_valid(meta_batch_query_valid_q),
    .batch_query_id(meta_batch_query_id_q),
    .batch_query_valid_cells(meta_batch_query_valid_cells),
    .batch_query_committed(meta_batch_query_committed),
    .batch_release_valid(meta_batch_release_valid_q),
    .batch_release_id(meta_batch_release_id_q),
    .digest(meta_digest)
  );

  always_comb begin
    pkt_cells_c = cell_count_count(s_pkt_cell_count);
    pkt_cells_ok_c = (pkt_cells_c != '0) && (pkt_cells_c <= BATCH_SIZE_COUNT);
    sram_can_fit_c = pkt_cells_ok_c && (sram_free_count_q >= pkt_cells_c);
    ddr_can_fit_c = pkt_cells_ok_c &&
                    (ddr_free_cell_count_q >= pkt_cells_c) &&
                    (batch_free_count_q != '0 || open_batch_valid_q);

    ingress_to_sram_c = 1'b0;
    unique case (POLICY_MODE)
      POLICY_THEMIS: begin
        ingress_to_sram_c = sram_can_fit_c &&
                            ((global_sram_occ_q < {{(COUNT_W-16){1'b0}}, cfg_swap_out_threshold}) ||
                             !ddr_can_fit_c);
      end
      POLICY_DT: begin
        ingress_to_sram_c = sram_can_fit_c && policy_admit_c;
      end
      POLICY_OCCAMY_HEAD,
      POLICY_OCCAMY_MAX: begin
        ingress_to_sram_c = sram_can_fit_c && policy_admit_c;
      end
      POLICY_OBM: begin
        ingress_to_sram_c = sram_can_fit_c && (!obm_pkt_targets_longest_c || !ddr_can_fit_c);
      end
      POLICY_HYBRID_THEMIS: begin
        ingress_to_sram_c = sram_can_fit_c && hybrid_policy_admit_c;
      end
      default: begin
        ingress_to_sram_c = sram_can_fit_c;
      end
    endcase
    ingress_to_hbm_c = !ingress_to_sram_c && ddr_can_fit_c;
    s_pkt_ready = enable && meta_ready && (desc_free_count_q != '0) &&
                  pkt_cells_ok_c && (ingress_to_sram_c || ingress_to_hbm_c);
    ingress_fire_c = s_pkt_valid && s_pkt_ready;

    for (int pi = 0; pi < PORTS; pi = pi + 1) begin
      deq_req_c[pi] = dequeue_enable[pi] && !out_valid_q[pi] &&
                      (sram_min_valid[pi] || hbm_min_valid[pi]);
    end
    deq_port_c = rr_select(deq_req_c, deq_rr_q);
    deq_fire_c = |deq_req_c;
    deq_from_sram_c =
      sram_min_valid[deq_port_c] &&
      (!hbm_min_valid[deq_port_c] ||
       rank_less(sram_min_rank[deq_port_c*RANK_WIDTH +: RANK_WIDTH],
                 sram_min_seq[deq_port_c*SEQ_WIDTH +: SEQ_WIDTH],
                 hbm_min_rank[deq_port_c*RANK_WIDTH +: RANK_WIDTH],
                 hbm_min_seq[deq_port_c*SEQ_WIDTH +: SEQ_WIDTH]));
    deq_desc_c = deq_from_sram_c ?
                 sram_min_desc[deq_port_c*DESC_W +: DESC_W] :
                 hbm_min_desc[deq_port_c*DESC_W +: DESC_W];
    deq_rank_c = deq_from_sram_c ?
                 sram_min_rank[deq_port_c*RANK_WIDTH +: RANK_WIDTH] :
                 hbm_min_rank[deq_port_c*RANK_WIDTH +: RANK_WIDTH];
    deq_seq_c = deq_from_sram_c ?
                sram_min_seq[deq_port_c*SEQ_WIDTH +: SEQ_WIDTH] :
                hbm_min_seq[deq_port_c*SEQ_WIDTH +: SEQ_WIDTH];
    deq_cells_raw_c = deq_from_sram_c ?
                      sram_min_cell_count[deq_port_c*CELL_COUNT_WIDTH +: CELL_COUNT_WIDTH] :
                      hbm_min_cell_count[deq_port_c*CELL_COUNT_WIDTH +: CELL_COUNT_WIDTH];
    deq_cells_c = cell_count_count(deq_cells_raw_c);
    deq_batch_c = hbm_min_batch_id[deq_port_c*BATCH_ID_W +: BATCH_ID_W];
    deq_batch_off_c = hbm_min_batch_off[deq_port_c*BATCH_OFF_W +: BATCH_OFF_W];

    swapout_valid_c = 1'b0;
    swapout_port_c = '0;
    swapout_desc_c = '0;
    swapout_rank_c = '0;
    swapout_seq_c = '0;
    swapout_cells_raw_c = '0;
    for (int pi = 0; pi < PORTS; pi = pi + 1) begin
      if (sram_max_valid[pi] &&
          ((POLICY_MODE != POLICY_HYBRID_THEMIS) || hybrid_over_threshold_c[pi]) &&
          (!swapout_valid_c ||
           rank_greater(sram_max_rank[pi*RANK_WIDTH +: RANK_WIDTH],
                        sram_max_seq[pi*SEQ_WIDTH +: SEQ_WIDTH],
                        swapout_rank_c,
                        swapout_seq_c))) begin
        swapout_valid_c = 1'b1;
        swapout_port_c = PORT_W'(pi);
        swapout_desc_c = sram_max_desc[pi*DESC_W +: DESC_W];
        swapout_rank_c = sram_max_rank[pi*RANK_WIDTH +: RANK_WIDTH];
        swapout_seq_c = sram_max_seq[pi*SEQ_WIDTH +: SEQ_WIDTH];
        swapout_cells_raw_c = sram_max_cell_count[pi*CELL_COUNT_WIDTH +: CELL_COUNT_WIDTH];
      end
    end
    swapout_cells_c = cell_count_count(swapout_cells_raw_c);

    swapin_valid_c = 1'b0;
    swapin_port_c = '0;
    swapin_desc_c = '0;
    swapin_rank_c = '1;
    swapin_seq_c = '1;
    swapin_cells_raw_c = '0;
    swapin_batch_c = '0;
    swapin_batch_off_c = '0;
    for (int pi = 0; pi < PORTS; pi = pi + 1) begin
      if (hbm_min_valid[pi] &&
          ((POLICY_MODE != POLICY_HYBRID_THEMIS) || hybrid_under_threshold_c[pi]) &&
          (!swapin_valid_c ||
           rank_less(hbm_min_rank[pi*RANK_WIDTH +: RANK_WIDTH],
                     hbm_min_seq[pi*SEQ_WIDTH +: SEQ_WIDTH],
                     swapin_rank_c,
                     swapin_seq_c))) begin
        swapin_valid_c = 1'b1;
        swapin_port_c = PORT_W'(pi);
        swapin_desc_c = hbm_min_desc[pi*DESC_W +: DESC_W];
        swapin_rank_c = hbm_min_rank[pi*RANK_WIDTH +: RANK_WIDTH];
        swapin_seq_c = hbm_min_seq[pi*SEQ_WIDTH +: SEQ_WIDTH];
        swapin_cells_raw_c = hbm_min_cell_count[pi*CELL_COUNT_WIDTH +: CELL_COUNT_WIDTH];
        swapin_batch_c = hbm_min_batch_id[pi*BATCH_ID_W +: BATCH_ID_W];
        swapin_batch_off_c = hbm_min_batch_off[pi*BATCH_OFF_W +: BATCH_OFF_W];
      end
    end
    swapin_cells_c = cell_count_count(swapin_cells_raw_c);

    port_op_valid = '0;
    port_op_type = '0;
    port_op_tier = '0;
    port_op_rank = '0;
    port_op_seq = '0;
    port_op_cell_count = '0;
    port_op_desc = '0;
    port_op_batch_id = '0;
    port_op_batch_off = '0;

    wr_start_c = 1'b0;
    wr_start_batch_c = open_batch_valid_q ? open_batch_id_q : batch_alloc_head_q;
    rd_start_c = 1'b0;

    if (deq_fire_c) begin
      port_op_valid[deq_port_c] = 1'b1;
      port_op_type[deq_port_c*3 +: 3] = deq_from_sram_c ? 3'd2 : 3'd3;
      port_op_tier[deq_port_c] = !deq_from_sram_c;
      port_op_rank[deq_port_c*RANK_WIDTH +: RANK_WIDTH] = deq_rank_c;
      port_op_seq[deq_port_c*SEQ_WIDTH +: SEQ_WIDTH] = deq_seq_c;
      port_op_cell_count[deq_port_c*CELL_COUNT_WIDTH +: CELL_COUNT_WIDTH] = deq_cells_raw_c;
      port_op_desc[deq_port_c*DESC_W +: DESC_W] = deq_desc_c;
      port_op_batch_id[deq_port_c*BATCH_ID_W +: BATCH_ID_W] = deq_batch_c;
      port_op_batch_off[deq_port_c*BATCH_OFF_W +: BATCH_OFF_W] = deq_batch_off_c;
      rd_start_c = !deq_from_sram_c && (rd_state_q == RD_IDLE);
    end else if (ingress_fire_c) begin
      port_op_valid[s_pkt_port] = 1'b1;
      port_op_type[s_pkt_port*3 +: 3] = 3'd1;
      port_op_tier[s_pkt_port] = ingress_to_hbm_c;
      port_op_rank[s_pkt_port*RANK_WIDTH +: RANK_WIDTH] = s_pkt_rank;
      port_op_seq[s_pkt_port*SEQ_WIDTH +: SEQ_WIDTH] = s_pkt_seq;
      port_op_cell_count[s_pkt_port*CELL_COUNT_WIDTH +: CELL_COUNT_WIDTH] = s_pkt_cell_count;
      port_op_desc[s_pkt_port*DESC_W +: DESC_W] = desc_alloc_head_q;
      port_op_batch_id[s_pkt_port*BATCH_ID_W +: BATCH_ID_W] =
        open_batch_valid_q ? open_batch_id_q : batch_alloc_head_q;
      port_op_batch_off[s_pkt_port*BATCH_OFF_W +: BATCH_OFF_W] = open_batch_fill_q[BATCH_OFF_W-1:0];
      wr_start_c = ingress_to_hbm_c && (wr_state_q == WR_IDLE);
      wr_start_batch_c = open_batch_valid_q ? open_batch_id_q : batch_alloc_head_q;
    end else if (swapin_valid_c &&
                 (sram_free_count_q >= swapin_cells_c) &&
                 (rd_state_q == RD_IDLE) &&
                 (((POLICY_MODE == POLICY_THEMIS) &&
                   (global_sram_occ_q < {{(COUNT_W-16){1'b0}}, cfg_swap_in_threshold})) ||
                  ((POLICY_MODE == POLICY_HYBRID_THEMIS) &&
                   hybrid_swapin_hint_valid_c &&
                   (swapin_port_c == hybrid_swapin_hint_port_c) &&
                   count_after_add_leq(sram_count_q[swapin_port_c], swapin_cells_c,
                                       hybrid_policy_threshold_c)))) begin
      port_op_valid[swapin_port_c] = 1'b1;
      port_op_type[swapin_port_c*3 +: 3] = 3'd4;
      port_op_tier[swapin_port_c] = 1'b0;
      port_op_rank[swapin_port_c*RANK_WIDTH +: RANK_WIDTH] = swapin_rank_c;
      port_op_seq[swapin_port_c*SEQ_WIDTH +: SEQ_WIDTH] = swapin_seq_c;
      port_op_cell_count[swapin_port_c*CELL_COUNT_WIDTH +: CELL_COUNT_WIDTH] = swapin_cells_raw_c;
      port_op_desc[swapin_port_c*DESC_W +: DESC_W] = swapin_desc_c;
      port_op_batch_id[swapin_port_c*BATCH_ID_W +: BATCH_ID_W] = swapin_batch_c;
      port_op_batch_off[swapin_port_c*BATCH_OFF_W +: BATCH_OFF_W] = swapin_batch_off_c;
      rd_start_c = 1'b1;
    end else if ((((POLICY_MODE == POLICY_THEMIS) &&
                   (global_sram_occ_q > {{(COUNT_W-16){1'b0}}, cfg_swap_out_threshold})) ||
                  ((POLICY_MODE == POLICY_OCCAMY_HEAD || POLICY_MODE == POLICY_OCCAMY_MAX) &&
                   occamy_reclaim_valid_c) ||
                  ((POLICY_MODE == POLICY_OBM) &&
                   obm_longest_valid_c && !obm_pkt_targets_longest_c) ||
                  ((POLICY_MODE == POLICY_HYBRID_THEMIS) &&
                   hybrid_swapout_hint_valid_c &&
                   (swapout_port_c == hybrid_swapout_hint_port_c))) &&
                 swapout_valid_c &&
                 ddr_can_fit_c) begin
      port_op_valid[swapout_port_c] = 1'b1;
      port_op_type[swapout_port_c*3 +: 3] = 3'd5;
      port_op_tier[swapout_port_c] = 1'b1;
      port_op_rank[swapout_port_c*RANK_WIDTH +: RANK_WIDTH] = swapout_rank_c;
      port_op_seq[swapout_port_c*SEQ_WIDTH +: SEQ_WIDTH] = swapout_seq_c;
      port_op_cell_count[swapout_port_c*CELL_COUNT_WIDTH +: CELL_COUNT_WIDTH] = swapout_cells_raw_c;
      port_op_desc[swapout_port_c*DESC_W +: DESC_W] = swapout_desc_c;
      port_op_batch_id[swapout_port_c*BATCH_ID_W +: BATCH_ID_W] =
        open_batch_valid_q ? open_batch_id_q : batch_alloc_head_q;
      port_op_batch_off[swapout_port_c*BATCH_OFF_W +: BATCH_OFF_W] = open_batch_fill_q[BATCH_OFF_W-1:0];
      wr_start_c = (wr_state_q == WR_IDLE);
      wr_start_batch_c = open_batch_valid_q ? open_batch_id_q : batch_alloc_head_q;
    end
  end

  assign m_pkt_valid = out_valid_q;
  assign m_pkt_rank = out_rank_q;
  assign m_pkt_seq = out_seq_q;
  assign m_pkt_cell_count = out_cell_count_q;
  assign m_pkt_payload = out_payload_q;
  assign dbg_global_sram_occupancy = sat16(global_sram_occ_q);
  assign dbg_global_hbm_occupancy = sat16(global_hbm_occ_q);
  assign dbg_open_batch_cells = {{(16-(BATCH_OFF_W+1)){1'b0}}, open_batch_fill_q};
  assign dbg_ddr_state = {4'd0, rd_state_q, wr_state_q};
  assign dbg_ddr_wr_error = (m_axi_bvalid && (m_axi_bresp != 2'b00));
  assign dbg_ddr_rd_error = (m_axi_rvalid && (m_axi_rresp != 2'b00));

  always_ff @(posedge clk) begin
    int pi;
    if (!resetn) begin
      desc_free_count_q <= PACKET_SLOTS_COUNT;
      sram_free_count_q <= SRAM_CELLS_COUNT;
      batch_free_count_q <= BATCH_SLOTS_COUNT;
      ddr_free_cell_count_q <= DDR_CELL_CAPACITY_COUNT;
      global_sram_occ_q <= '0;
      global_hbm_occ_q <= '0;
      desc_alloc_head_q <= '0;
      desc_free_tail_q <= '0;
      sram_alloc_head_q <= '0;
      sram_release_tail_q <= '0;
      batch_alloc_head_q <= '0;
      batch_release_tail_q <= '0;
      open_batch_valid_q <= 1'b0;
      open_batch_id_q <= '0;
      open_batch_fill_q <= '0;
      ingress_rr_q <= '0;
      deq_rr_q <= '0;
      swap_rr_q <= '0;
      wr_rr_q <= '0;
      rd_rr_q <= '0;
      stat_generated <= 32'd0;
      stat_dequeued <= 32'd0;
      stat_sram_admit <= 32'd0;
      stat_hbm_admit <= 32'd0;
      stat_swap_out <= 32'd0;
      stat_swap_in <= 32'd0;
      stat_direct_hbm_dequeue <= 32'd0;
      stat_drop <= 32'd0;
      stat_batch_submit <= 32'd0;
      stat_ddr_write_beats <= 32'd0;
      stat_ddr_read_beats <= 32'd0;
      stat_ddr_write_batches <= 32'd0;
      stat_ddr_read_batches <= 32'd0;
      out_valid_q <= '0;
      out_rank_q <= '0;
      out_seq_q <= '0;
      out_cell_count_q <= '0;
      out_payload_q <= '0;
      for (pi = 0; pi < PORTS; pi = pi + 1) begin
        sram_count_q[pi] <= '0;
        hbm_count_q[pi] <= '0;
      end
      wr_state_q <= WR_IDLE;
      wr_batch_q <= '0;
      wr_beat_q <= '0;
      rd_state_q <= RD_IDLE;
      rd_direct_q <= 1'b0;
      rd_port_q <= '0;
      rd_desc_q <= '0;
      rd_rank_q <= '0;
      rd_seq_q <= '0;
      rd_cells_raw_q <= '0;
      rd_cells_q <= '0;
      rd_batch_q <= '0;
      rd_beat_q <= '0;
      m_axi_awid <= '0;
      m_axi_awaddr <= '0;
      m_axi_awlen <= '0;
      m_axi_awsize <= 3'd6;
      m_axi_awburst <= 2'b01;
      m_axi_awlock <= 1'b0;
      m_axi_awcache <= 4'b0011;
      m_axi_awprot <= 3'b000;
      m_axi_awqos <= 4'b0000;
      m_axi_awvalid <= 1'b0;
      m_axi_wdata <= '0;
      m_axi_wstrb <= {AXI_KEEP_WIDTH{1'b1}};
      m_axi_wlast <= 1'b0;
      m_axi_wvalid <= 1'b0;
      m_axi_bready <= 1'b0;
      m_axi_arid <= '0;
      m_axi_araddr <= '0;
      m_axi_arlen <= '0;
      m_axi_arsize <= 3'd6;
      m_axi_arburst <= 2'b01;
      m_axi_arlock <= 1'b0;
      m_axi_arcache <= 4'b0011;
      m_axi_arprot <= 3'b000;
      m_axi_arqos <= 4'b0000;
      m_axi_arvalid <= 1'b0;
      m_axi_rready <= 1'b0;
      meta_desc_wr_valid_q <= 1'b0;
      meta_desc_wr_addr_q <= '0;
      meta_desc_wr_loc_q <= 1'b0;
      meta_desc_wr_port_q <= '0;
      meta_desc_wr_rank_q <= '0;
      meta_desc_wr_seq_q <= '0;
      meta_desc_wr_cell_count_q <= '0;
      meta_desc_wr_payload_q <= '0;
      meta_desc_wr_sram_base_q <= '0;
      meta_desc_wr_batch_id_q <= '0;
      meta_desc_wr_batch_offset_q <= '0;
      meta_desc_rd_valid_q <= 1'b0;
      meta_desc_rd_addr_q <= '0;
      meta_desc_free_valid_q <= 1'b0;
      meta_desc_free_addr_q <= '0;
      meta_sram_alloc_valid_q <= 1'b0;
      meta_sram_alloc_cells_q <= '0;
      meta_sram_release_valid_q <= 1'b0;
      meta_sram_release_base_q <= '0;
      meta_sram_release_cells_q <= '0;
      meta_batch_append_valid_q <= 1'b0;
      meta_batch_append_id_q <= '0;
      meta_batch_append_offset_q <= '0;
      meta_batch_append_desc_q <= '0;
      meta_batch_append_cells_q <= '0;
      meta_batch_commit_valid_q <= 1'b0;
      meta_batch_commit_id_q <= '0;
      meta_batch_query_valid_q <= 1'b0;
      meta_batch_query_id_q <= '0;
      meta_batch_release_valid_q <= 1'b0;
      meta_batch_release_id_q <= '0;
    end else begin
      meta_desc_wr_valid_q <= 1'b0;
      meta_desc_rd_valid_q <= 1'b0;
      meta_desc_free_valid_q <= 1'b0;
      meta_sram_alloc_valid_q <= 1'b0;
      meta_sram_release_valid_q <= 1'b0;
      meta_batch_append_valid_q <= 1'b0;
      meta_batch_commit_valid_q <= 1'b0;
      meta_batch_query_valid_q <= 1'b0;
      meta_batch_release_valid_q <= 1'b0;

      for (pi = 0; pi < PORTS; pi = pi + 1) begin
        if (out_valid_q[pi] && m_pkt_ready[pi]) begin
          out_valid_q[pi] <= 1'b0;
        end
      end

      if (deq_fire_c) begin
        deq_rr_q <= deq_port_c + 1'b1;
        desc_free_count_q <= desc_free_count_q + 1'b1;
        desc_free_tail_q <= desc_free_tail_q + 1'b1;
        meta_desc_free_valid_q <= 1'b1;
        meta_desc_free_addr_q <= deq_desc_c;
        meta_desc_rd_valid_q <= 1'b1;
        meta_desc_rd_addr_q <= deq_desc_c;
        out_rank_q[deq_port_c*RANK_WIDTH +: RANK_WIDTH] <= deq_rank_c;
        out_seq_q[deq_port_c*SEQ_WIDTH +: SEQ_WIDTH] <= deq_seq_c;
        out_cell_count_q[deq_port_c*CELL_COUNT_WIDTH +: CELL_COUNT_WIDTH] <= deq_cells_raw_c;
        out_payload_q[deq_port_c*PAYLOAD_WIDTH +: PAYLOAD_WIDTH] <=
          payload_from_desc(deq_desc_c);
        if (deq_from_sram_c) begin
          sram_count_q[deq_port_c] <= sram_count_q[deq_port_c] - deq_cells_c;
          global_sram_occ_q <= global_sram_occ_q - deq_cells_c;
          sram_free_count_q <= sram_free_count_q + deq_cells_c;
          sram_release_tail_q <= sram_release_tail_q + deq_cells_c[SRAM_SLOT_W-1:0];
          meta_sram_release_valid_q <= 1'b1;
          meta_sram_release_base_q <= sram_release_tail_q;
          meta_sram_release_cells_q <= deq_cells_c;
          out_valid_q[deq_port_c] <= 1'b1;
        end else begin
          hbm_count_q[deq_port_c] <= hbm_count_q[deq_port_c] - deq_cells_c;
          global_hbm_occ_q <= global_hbm_occ_q - deq_cells_c;
          ddr_free_cell_count_q <= ddr_free_cell_count_q + deq_cells_c;
          rd_direct_q <= 1'b1;
          rd_port_q <= deq_port_c;
          rd_desc_q <= deq_desc_c;
          rd_rank_q <= deq_rank_c;
          rd_seq_q <= deq_seq_c;
          rd_cells_raw_q <= deq_cells_raw_c;
          rd_cells_q <= deq_cells_c;
          rd_batch_q <= deq_batch_c;
          stat_direct_hbm_dequeue <= stat_direct_hbm_dequeue + 32'd1;
          meta_batch_release_valid_q <= 1'b1;
          meta_batch_release_id_q <= deq_batch_c;
        end
        stat_dequeued <= stat_dequeued + 32'd1;
      end else if (ingress_fire_c) begin
        desc_alloc_head_q <= desc_alloc_head_q + 1'b1;
        desc_free_count_q <= desc_free_count_q - 1'b1;
        stat_generated <= stat_generated + 32'd1;
        meta_desc_wr_valid_q <= 1'b1;
        meta_desc_wr_addr_q <= desc_alloc_head_q;
        meta_desc_wr_loc_q <= ingress_to_hbm_c;
        meta_desc_wr_port_q <= s_pkt_port;
        meta_desc_wr_rank_q <= s_pkt_rank;
        meta_desc_wr_seq_q <= s_pkt_seq;
        meta_desc_wr_cell_count_q <= s_pkt_cell_count;
        meta_desc_wr_payload_q <= s_pkt_payload;
        meta_desc_wr_sram_base_q <= sram_alloc_head_q;
        meta_desc_wr_batch_id_q <= open_batch_valid_q ? open_batch_id_q : batch_alloc_head_q;
        meta_desc_wr_batch_offset_q <= open_batch_fill_q[BATCH_OFF_W-1:0];
        if (ingress_to_sram_c) begin
          sram_count_q[s_pkt_port] <= sram_count_q[s_pkt_port] + pkt_cells_c;
          global_sram_occ_q <= global_sram_occ_q + pkt_cells_c;
          sram_free_count_q <= sram_free_count_q - pkt_cells_c;
          sram_alloc_head_q <= sram_alloc_head_q + pkt_cells_c[SRAM_SLOT_W-1:0];
          meta_sram_alloc_valid_q <= 1'b1;
          meta_sram_alloc_cells_q <= pkt_cells_c;
          stat_sram_admit <= stat_sram_admit + 32'd1;
        end else begin
          hbm_count_q[s_pkt_port] <= hbm_count_q[s_pkt_port] + pkt_cells_c;
          global_hbm_occ_q <= global_hbm_occ_q + pkt_cells_c;
          ddr_free_cell_count_q <= ddr_free_cell_count_q - pkt_cells_c;
          meta_batch_append_valid_q <= 1'b1;
          meta_batch_append_id_q <= open_batch_valid_q ? open_batch_id_q : batch_alloc_head_q;
          meta_batch_append_offset_q <= open_batch_fill_q[BATCH_OFF_W-1:0];
          meta_batch_append_desc_q <= desc_alloc_head_q;
          meta_batch_append_cells_q <= pkt_cells_c;
          if (!open_batch_valid_q) begin
            open_batch_valid_q <= 1'b1;
            open_batch_id_q <= batch_alloc_head_q;
            batch_alloc_head_q <= batch_alloc_head_q + 1'b1;
            batch_free_count_q <= batch_free_count_q - 1'b1;
          end
          if ((open_batch_fill_q + pkt_cells_c[BATCH_OFF_W:0]) >= BATCH_SIZE_COUNT[BATCH_OFF_W:0]) begin
            open_batch_valid_q <= 1'b0;
            open_batch_fill_q <= '0;
            stat_batch_submit <= stat_batch_submit + 32'd1;
          end else begin
            open_batch_fill_q <= open_batch_fill_q + pkt_cells_c[BATCH_OFF_W:0];
          end
          stat_hbm_admit <= stat_hbm_admit + 32'd1;
        end
        ingress_rr_q <= s_pkt_port + 1'b1;
      end else if (port_op_valid[swapin_port_c] && (port_op_type[swapin_port_c*3 +: 3] == 3'd4)) begin
        sram_count_q[swapin_port_c] <= sram_count_q[swapin_port_c] + swapin_cells_c;
        hbm_count_q[swapin_port_c] <= hbm_count_q[swapin_port_c] - swapin_cells_c;
        global_sram_occ_q <= global_sram_occ_q + swapin_cells_c;
        global_hbm_occ_q <= global_hbm_occ_q - swapin_cells_c;
        sram_free_count_q <= sram_free_count_q - swapin_cells_c;
        ddr_free_cell_count_q <= ddr_free_cell_count_q + swapin_cells_c;
        sram_alloc_head_q <= sram_alloc_head_q + swapin_cells_c[SRAM_SLOT_W-1:0];
        rd_direct_q <= 1'b0;
        rd_port_q <= swapin_port_c;
        rd_desc_q <= swapin_desc_c;
        rd_rank_q <= swapin_rank_c;
        rd_seq_q <= swapin_seq_c;
        rd_cells_raw_q <= swapin_cells_raw_c;
        rd_cells_q <= swapin_cells_c;
        rd_batch_q <= swapin_batch_c;
        meta_sram_alloc_valid_q <= 1'b1;
        meta_sram_alloc_cells_q <= swapin_cells_c;
        meta_batch_release_valid_q <= 1'b1;
        meta_batch_release_id_q <= swapin_batch_c;
        stat_swap_in <= stat_swap_in + 32'd1;
      end else if (port_op_valid[swapout_port_c] && (port_op_type[swapout_port_c*3 +: 3] == 3'd5)) begin
        sram_count_q[swapout_port_c] <= sram_count_q[swapout_port_c] - swapout_cells_c;
        hbm_count_q[swapout_port_c] <= hbm_count_q[swapout_port_c] + swapout_cells_c;
        global_sram_occ_q <= global_sram_occ_q - swapout_cells_c;
        global_hbm_occ_q <= global_hbm_occ_q + swapout_cells_c;
        sram_free_count_q <= sram_free_count_q + swapout_cells_c;
        ddr_free_cell_count_q <= ddr_free_cell_count_q - swapout_cells_c;
        sram_release_tail_q <= sram_release_tail_q + swapout_cells_c[SRAM_SLOT_W-1:0];
        meta_sram_release_valid_q <= 1'b1;
        meta_sram_release_base_q <= sram_release_tail_q;
        meta_sram_release_cells_q <= swapout_cells_c;
        meta_batch_append_valid_q <= 1'b1;
        meta_batch_append_id_q <= open_batch_valid_q ? open_batch_id_q : batch_alloc_head_q;
        meta_batch_append_offset_q <= open_batch_fill_q[BATCH_OFF_W-1:0];
        meta_batch_append_desc_q <= swapout_desc_c;
        meta_batch_append_cells_q <= swapout_cells_c;
        stat_swap_out <= stat_swap_out + 32'd1;
        stat_batch_submit <= stat_batch_submit + 32'd1;
      end else if (s_pkt_valid && !s_pkt_ready) begin
        stat_drop <= stat_drop + 32'd1;
      end

      case (wr_state_q)
        WR_IDLE: begin
          if (wr_start_c) begin
            wr_batch_q <= wr_start_batch_c;
            wr_beat_q <= '0;
            m_axi_awid <= '0;
            m_axi_awaddr <= ddr_batch_addr(wr_start_batch_c);
            m_axi_awlen <= BATCH_SIZE - 1;
            m_axi_awsize <= 3'd6;
            m_axi_awburst <= 2'b01;
            m_axi_awvalid <= 1'b1;
            wr_state_q <= WR_ADDR;
          end
        end
        WR_ADDR: begin
          if (m_axi_awvalid && m_axi_awready) begin
            m_axi_awvalid <= 1'b0;
            m_axi_wvalid <= 1'b1;
            m_axi_wlast <= (BATCH_SIZE == 1);
            m_axi_wdata <= pack_axi_digest_cell(desc_alloc_head_q, s_pkt_rank, s_pkt_seq,
                                                s_pkt_cell_count, '0, s_pkt_payload) ^
                           {{(AXI_DATA_WIDTH-64){1'b0}},
                            meta_digest ^ selected_policy_digest_c};
            wr_state_q <= WR_DATA;
          end
        end
        WR_DATA: begin
          if (m_axi_wvalid && m_axi_wready) begin
            stat_ddr_write_beats <= stat_ddr_write_beats + 32'd1;
            if (wr_beat_q == (BATCH_SIZE - 1)) begin
              m_axi_wvalid <= 1'b0;
              m_axi_wlast <= 1'b0;
              m_axi_bready <= 1'b1;
              wr_state_q <= WR_RESP;
            end else begin
              wr_beat_q <= wr_beat_q + 1'b1;
              m_axi_wlast <= (wr_beat_q == (BATCH_SIZE - 2));
              m_axi_wdata <= m_axi_wdata ^
                             {{(AXI_DATA_WIDTH-(BATCH_OFF_W+1)){1'b0}}, (wr_beat_q + 1'b1)};
            end
          end
        end
        WR_RESP: begin
          if (m_axi_bvalid) begin
            m_axi_bready <= 1'b0;
            meta_batch_commit_valid_q <= 1'b1;
            meta_batch_commit_id_q <= wr_batch_q;
            stat_ddr_write_batches <= stat_ddr_write_batches + 32'd1;
            wr_state_q <= WR_IDLE;
          end
        end
      endcase

      case (rd_state_q)
        RD_IDLE: begin
          if (rd_start_c) begin
            rd_beat_q <= '0;
            m_axi_arid <= '0;
            m_axi_araddr <= ddr_batch_addr(rd_direct_q ? deq_batch_c : swapin_batch_c);
            m_axi_arlen <= BATCH_SIZE - 1;
            m_axi_arsize <= 3'd6;
            m_axi_arburst <= 2'b01;
            m_axi_arvalid <= 1'b1;
            rd_state_q <= RD_ADDR;
          end
        end
        RD_ADDR: begin
          if (m_axi_arvalid && m_axi_arready) begin
            m_axi_arvalid <= 1'b0;
            m_axi_rready <= 1'b1;
            rd_state_q <= RD_DATA;
          end
        end
        RD_DATA: begin
          if (m_axi_rvalid && m_axi_rready) begin
            stat_ddr_read_beats <= stat_ddr_read_beats + 32'd1;
            if (m_axi_rlast || (rd_beat_q == (BATCH_SIZE - 1))) begin
              m_axi_rready <= 1'b0;
              stat_ddr_read_batches <= stat_ddr_read_batches + 32'd1;
              if (rd_direct_q) begin
                out_rank_q[rd_port_q*RANK_WIDTH +: RANK_WIDTH] <= rd_rank_q;
                out_seq_q[rd_port_q*SEQ_WIDTH +: SEQ_WIDTH] <= rd_seq_q;
                out_cell_count_q[rd_port_q*CELL_COUNT_WIDTH +: CELL_COUNT_WIDTH] <= rd_cells_raw_q;
                out_payload_q[rd_port_q*PAYLOAD_WIDTH +: PAYLOAD_WIDTH] <=
                  m_axi_rdata[PAYLOAD_WIDTH-1:0];
                out_valid_q[rd_port_q] <= 1'b1;
              end
              rd_state_q <= RD_IDLE;
            end else begin
              rd_beat_q <= rd_beat_q + 1'b1;
            end
          end
        end
      endcase
    end
  end

endmodule
