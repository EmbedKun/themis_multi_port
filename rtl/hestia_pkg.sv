`timescale 1ns/1ps

package hestia_pkg;
  typedef enum logic {
    MP_LOC_SRAM = 1'b0,
    MP_LOC_HBM  = 1'b1
  } mp_loc_t;

  typedef enum logic [2:0] {
    MP_CMD_NONE              = 3'd0,
    MP_CMD_ADD_SRAM          = 3'd1,
    MP_CMD_ADD_HBM           = 3'd2,
    MP_CMD_MOVE_SRAM_MAX_HBM = 3'd3,
    MP_CMD_REMOVE_SRAM_MIN   = 3'd4,
    MP_CMD_REMOVE_HBM_MIN    = 3'd5,
    MP_CMD_MOVE_HBM_SRAM     = 3'd6
  } mp_port_cmd_t;

  typedef enum logic [2:0] {
    MP_BBQ_CMD_NONE             = 3'd0,
    MP_BBQ_CMD_ADD_SRAM         = 3'd1,
    MP_BBQ_CMD_ADD_HBM          = 3'd2,
    MP_BBQ_CMD_MOVE_SRAM_TO_HBM = 3'd3,
    MP_BBQ_CMD_MOVE_HBM_TO_SRAM = 3'd4,
    MP_BBQ_CMD_REMOVE_SRAM      = 3'd5,
    MP_BBQ_CMD_REMOVE_HBM       = 3'd6
  } mp_bbq_cmd_t;
endpackage
