`ifndef RS_V_ 
`define RS_V_ 

`ifdef ONLINE_JUDGE
    `include "utils.v"
`else 
    `include "/home/Modem514/projectAris/riscv/src/utils.v"
`endif

`define RS_BIT 4
`define RS_SIZE (1 << `RS_BIT)
`define RS_IDX_TP (`RS_SIZE-1):0

module RS #(
    parameter RS_BIT = `RS_BIT,
    parameter RS_SIZE = `RS_SIZE
) (
    input wire clk,
    input wire rst,
    input wire rdy,

    input wire rs_en,
    input wire rs_st,
    input wire rs_rb,
    output wire rs_full,
    output wire rs_empty,

    // idu
`ifdef DEBUG
    input wire [`WORD_TP] id_inst,
`endif
    input wire id_valid, 
    input wire [`INST_OPT_TP] id_opt,
    input wire [`ROB_IDX_TP] id_src1,
    input wire [`ROB_IDX_TP] id_src2,
    input wire [`WORD_TP] id_val1,
    input wire [`WORD_TP] id_val2,
    input wire [`WORD_TP] id_imm,  
    input wire [`ROB_IDX_TP] id_rob_idx,

    // alu
`ifdef DEBUG
    output reg [`WORD_TP] alu_inst,
`endif
    output reg alu_ena,
    output reg [`INST_OPT_TP] alu_opt,
    output reg [`WORD_TP] alu_val1,
    output reg [`WORD_TP] alu_val2,
    output reg [`WORD_TP] alu_imm,
    output reg [`ROB_IDX_TP] alu_rob_idx,

    // cdb
    input wire cdb_alu_valid,
    input wire [`ROB_IDX_TP] cdb_alu_src,
    input wire [`WORD_TP] cdb_alu_val,
    input wire cdb_ld_valid,
    input wire [`ROB_IDX_TP] cdb_ld_src,
    input wire [`WORD_TP] cdb_ld_val
);

`ifdef DEBUG
reg [`WORD_TP] inst[RS_SIZE-1:0];
`endif 
reg                busy [RS_SIZE-1:0]; 
reg [`INST_OPT_TP] opt  [RS_SIZE-1:0];
reg [`ROB_IDX_TP]  src1 [RS_SIZE-1:0];
reg [`ROB_IDX_TP]  src2 [RS_SIZE-1:0];
reg [`WORD_TP]     val1 [RS_SIZE-1:0];
reg [`WORD_TP]     val2 [RS_SIZE-1:0];
reg [`WORD_TP]     imm  [RS_SIZE-1:0];
reg [`ROB_IDX_TP]  idx  [RS_SIZE-1:0];

reg [RS_BIT-1:0] lag_rs_siz;
reg rs_push_flag, rs_pop_flag;
wire [RS_BIT-1:0] rs_siz = lag_rs_siz + (rs_push_flag? 1: 0) + (rs_pop_flag? -1: 0);

assign rs_full = rs_siz >= RS_SIZE - 3;
assign rs_empty = rs_siz == 0;

wire [RS_BIT-1:0] idle_idx = 
    (!busy[ 0]?  0: (!busy[ 1]?  1: (!busy[ 2]?  2: (!busy[ 3]?  3:
    (!busy[ 4]?  4: (!busy[ 5]?  5: (!busy[ 6]?  6: (!busy[ 7]?  7:
    (!busy[ 8]?  8: (!busy[ 9]?  9: (!busy[10]? 10: (!busy[11]? 11:
    (!busy[12]? 12: (!busy[13]? 13: (!busy[14]? 14: (!busy[15]? 15: 4'bxxxx
    ))))))))))))))));
wire exec_rdy = 
    (busy[ 0] && src1[ 0] == 0 && src2[ 0] == 0) ||
    (busy[ 1] && src1[ 1] == 0 && src2[ 1] == 0) ||
    (busy[ 2] && src1[ 2] == 0 && src2[ 2] == 0) ||
    (busy[ 3] && src1[ 3] == 0 && src2[ 3] == 0) ||
    (busy[ 4] && src1[ 4] == 0 && src2[ 4] == 0) ||
    (busy[ 5] && src1[ 5] == 0 && src2[ 5] == 0) ||
    (busy[ 6] && src1[ 6] == 0 && src2[ 6] == 0) ||
    (busy[ 7] && src1[ 7] == 0 && src2[ 7] == 0) ||
    (busy[ 8] && src1[ 8] == 0 && src2[ 8] == 0) ||
    (busy[ 9] && src1[ 9] == 0 && src2[ 9] == 0) ||
    (busy[10] && src1[10] == 0 && src2[10] == 0) ||
    (busy[11] && src1[11] == 0 && src2[11] == 0) ||
    (busy[12] && src1[12] == 0 && src2[12] == 0) ||
    (busy[13] && src1[13] == 0 && src2[13] == 0) ||
    (busy[14] && src1[14] == 0 && src2[14] == 0) ||
    (busy[15] && src1[15] == 0 && src2[15] == 0);

wire [RS_BIT-1:0] exec_idx = 
    (busy[ 0] && src1[ 0] == 0 && src2[ 0] == 0?  0: 
    (busy[ 1] && src1[ 1] == 0 && src2[ 1] == 0?  1: 
    (busy[ 2] && src1[ 2] == 0 && src2[ 2] == 0?  2: 
    (busy[ 3] && src1[ 3] == 0 && src2[ 3] == 0?  3:
    (busy[ 4] && src1[ 4] == 0 && src2[ 4] == 0?  4: 
    (busy[ 5] && src1[ 5] == 0 && src2[ 5] == 0?  5: 
    (busy[ 6] && src1[ 6] == 0 && src2[ 6] == 0?  6: 
    (busy[ 7] && src1[ 7] == 0 && src2[ 7] == 0?  7:
    (busy[ 8] && src1[ 8] == 0 && src2[ 8] == 0?  8: 
    (busy[ 9] && src1[ 9] == 0 && src2[ 9] == 0?  9: 
    (busy[10] && src1[10] == 0 && src2[10] == 0? 10: 
    (busy[11] && src1[11] == 0 && src2[11] == 0? 11:
    (busy[12] && src1[12] == 0 && src2[12] == 0? 12: 
    (busy[13] && src1[13] == 0 && src2[13] == 0? 13: 
    (busy[14] && src1[14] == 0 && src2[14] == 0? 14: 
    (busy[15] && src1[15] == 0 && src2[15] == 0? 15: 4'bxxxx
    ))))))))))))))));

wire [`ROB_IDX_TP] upd_src1 = (cdb_alu_valid && cdb_alu_src == id_src1)? `ZERO_ROB_IDX
    : ((cdb_ld_valid && cdb_ld_src == id_src1)? `ZERO_ROB_IDX: id_src1);
wire [`ROB_IDX_TP] upd_src2 = (cdb_alu_valid && cdb_alu_src == id_src2)? `ZERO_ROB_IDX
    : ((cdb_ld_valid && cdb_ld_src == id_src2)? `ZERO_ROB_IDX: id_src2);
wire [`WORD_TP] upd_val1 = (cdb_alu_valid && cdb_alu_src == id_src1)? cdb_alu_val
    : ((cdb_ld_valid && cdb_ld_src == id_src1)? cdb_ld_val: id_val1);
wire [`WORD_TP] upd_val2 = (cdb_alu_valid && cdb_alu_src == id_src2)? cdb_alu_val
    : ((cdb_ld_valid && cdb_ld_src == id_src2)? cdb_ld_val: id_val2);
    
integer i;

always @(posedge clk) begin
    alu_ena <= `FALSE;
    rs_push_flag <= `FALSE;
    rs_pop_flag <= `FALSE;
    lag_rs_siz <= rs_siz;

    if (rst || rs_rb) begin
        lag_rs_siz <= 0;
        for (i = 0; i < RS_SIZE; i++) begin
            busy[i] = `FALSE;
`ifdef DEBUG
    inst[i] = 0;
`endif
            opt [i] = `OPT_NONE;
            src1[i] = `ZERO_ROB_IDX;
            src2[i] = `ZERO_ROB_IDX;
            val1[i] = `ZERO_WORD;
            val2[i] = `ZERO_WORD;
            imm [i] = `ZERO_WORD;
            idx [i] = `ZERO_ROB_IDX;
        end
    end
    else if (!rdy || !rs_en || rs_st) begin
        // STALL
    end
    else begin
        // issue
        if (id_valid) begin 
            busy[idle_idx] <= `TRUE;
`ifdef DEBUG
    inst[idle_idx] <= id_inst;
`endif 
            opt [idle_idx] <= id_opt;
            src1[idle_idx] <= upd_src1;
            src2[idle_idx] <= upd_src2;
            val1[idle_idx] <= upd_val1;
            val2[idle_idx] <= upd_val2;
            imm [idle_idx] <= id_imm;
            idx [idle_idx] <= id_rob_idx;
            rs_push_flag <= `TRUE;
        end
        // execute
        if (exec_rdy) begin
`ifdef DEBUG
    alu_inst <= inst[exec_idx];
`endif
            alu_ena <= `TRUE;
            busy[exec_idx] <= `FALSE;
            alu_ena  <= `TRUE;
            alu_opt  <= opt [exec_idx];
            alu_val1 <= val1[exec_idx];
            alu_val2 <= val2[exec_idx];
            alu_imm  <= imm [exec_idx];
            alu_rob_idx <= idx[exec_idx];
            rs_pop_flag <= `TRUE;
        end
        // update
        if (cdb_alu_valid) begin
            for (i = 0; i < RS_SIZE; i++) begin
                if (busy[i] && src1[i] == cdb_alu_src) begin
                    src1[i] <= `ZERO_ROB_IDX;
                    val1[i] <= cdb_alu_val;
                end
                if (busy[i] && src2[i] == cdb_alu_src) begin
                    src2[i] <= `ZERO_ROB_IDX;
                    val2[i] <= cdb_alu_val;
                end
            end
        end
        if (cdb_ld_valid) begin
            for (i = 0; i < RS_SIZE; i++) begin
                if (busy[i] && src1[i] == cdb_ld_src) begin
                    src1[i] <= `ZERO_ROB_IDX;
                    val1[i] <= cdb_ld_val;
                end
                if (busy[i] && src2[i] == cdb_ld_src) begin
                    src2[i] <= `ZERO_ROB_IDX;
                    val2[i] <= cdb_ld_val;
                end
            end
        end
    end
end
    
endmodule

`endif 