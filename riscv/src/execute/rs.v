`include "../utils.v"

`define RS_BIT 4
`define RS_SIZE (1 << `RS_BIT)
`define RS_IDX_TP (`RS_SIZE-1):0

module RS #(
    RS_BIT = `RS_BIT,
    RS_SIZE = `RS_SIZE
) (
    input wire clk,
    input wire rst,
    input wire rdy,

    input wire rs_en,
    input wire rs_st,
    input wire rs_rb,
    output wire rs_full,

    // idu   
    input wire [`INST_OPT_TP] id_opt,
    input wire [`ROB_IDX_TP] id_src1,
    input wire [`ROB_IDX_TP] id_src2,
    input wire [`WORD_TP] id_val1,
    input wire [`WORD_TP] id_val2,
    input wire [`WORD_TP] id_imm,  
    input wire [`ROB_IDX_TP] id_rob_idx,

    // alu
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

reg                busy [RS_SIZE-1:0]; 
reg [`INST_OPT_TP] opt  [RS_SIZE-1:0];
reg [`ROB_IDX_TP]  src1 [RS_SIZE-1:0];
reg [`ROB_IDX_TP]  src2 [RS_SIZE-1:0];
reg [`WORD_TP]     val1 [RS_SIZE-1:0];
reg [`WORD_TP]     val2 [RS_SIZE-1:0];
reg [`WORD_TP]     imm  [RS_SIZE-1:0];
reg [`ROB_IDX_TP]  idx  [RS_SIZE-1:0];

assign rs_full = &busy;
wire rs_empty = !(|busy);

wire idle_flag3 = busy[ 7] & busy[ 6] & busy[ 5] & busy[4] & busy[3] & busy[2] & busy[1] & busy[0];
wire idle_flag2 = busy[11] & busy[10] & busy[ 9] & busy[8] & busy[3] & busy[2] & busy[1] & busy[0];
wire idle_flag1 = busy[13] & busy[12] & busy[ 9] & busy[8] & busy[5] & busy[4] & busy[1] & busy[0];
wire idle_flag0 = busy[14] & busy[12] & busy[10] & busy[8] & busy[6] & busy[4] & busy[2] & busy[0];
wire [RS_BIT-1:0] idle_idx = 
    ({3'b0, idle_flag3} << 3) | 
    ({3'b0, idle_flag2} << 2) | 
    ({3'b0, idle_flag1} << 1) | 
    ({3'b0, idle_flag0});

wire exe_flag3 = 
    (busy[15] && src1[15] == `ZERO_ROB_IDX && src2[15] == `ZERO_ROB_IDX) |
    (busy[14] && src1[14] == `ZERO_ROB_IDX && src2[14] == `ZERO_ROB_IDX) | 
    (busy[13] && src1[13] == `ZERO_ROB_IDX && src2[13] == `ZERO_ROB_IDX) | 
    (busy[12] && src1[12] == `ZERO_ROB_IDX && src2[12] == `ZERO_ROB_IDX) | 
    (busy[11] && src1[11] == `ZERO_ROB_IDX && src2[11] == `ZERO_ROB_IDX) | 
    (busy[10] && src1[10] == `ZERO_ROB_IDX && src2[10] == `ZERO_ROB_IDX) | 
    (busy[ 9] && src1[ 9] == `ZERO_ROB_IDX && src2[ 9] == `ZERO_ROB_IDX) | 
    (busy[ 8] && src1[ 8] == `ZERO_ROB_IDX && src2[ 8] == `ZERO_ROB_IDX);
wire exe_flag2 = 
    (busy[15] && src1[15] == `ZERO_ROB_IDX && src2[15] == `ZERO_ROB_IDX) |
    (busy[14] && src1[14] == `ZERO_ROB_IDX && src2[14] == `ZERO_ROB_IDX) | 
    (busy[13] && src1[13] == `ZERO_ROB_IDX && src2[13] == `ZERO_ROB_IDX) | 
    (busy[12] && src1[12] == `ZERO_ROB_IDX && src2[12] == `ZERO_ROB_IDX) | 
    (busy[ 7] && src1[ 7] == `ZERO_ROB_IDX && src2[ 7] == `ZERO_ROB_IDX) | 
    (busy[ 6] && src1[ 6] == `ZERO_ROB_IDX && src2[ 6] == `ZERO_ROB_IDX) | 
    (busy[ 5] && src1[ 5] == `ZERO_ROB_IDX && src2[ 5] == `ZERO_ROB_IDX) | 
    (busy[ 4] && src1[ 4] == `ZERO_ROB_IDX && src2[ 4] == `ZERO_ROB_IDX);
wire exe_flag1 = 
    (busy[15] && src1[15] == `ZERO_ROB_IDX && src2[15] == `ZERO_ROB_IDX) | 
    (busy[14] && src1[14] == `ZERO_ROB_IDX && src2[14] == `ZERO_ROB_IDX) | 
    (busy[11] && src1[11] == `ZERO_ROB_IDX && src2[11] == `ZERO_ROB_IDX) | 
    (busy[10] && src1[10] == `ZERO_ROB_IDX && src2[10] == `ZERO_ROB_IDX) | 
    (busy[ 7] && src1[ 7] == `ZERO_ROB_IDX && src2[ 7] == `ZERO_ROB_IDX) | 
    (busy[ 6] && src1[ 6] == `ZERO_ROB_IDX && src2[ 6] == `ZERO_ROB_IDX) | 
    (busy[ 3] && src1[ 3] == `ZERO_ROB_IDX && src2[ 3] == `ZERO_ROB_IDX) | 
    (busy[ 2] && src1[ 2] == `ZERO_ROB_IDX && src2[ 2] == `ZERO_ROB_IDX);
wire exe_flag0 = 
    (busy[15] && src1[15] == `ZERO_ROB_IDX && src2[15] == `ZERO_ROB_IDX) |
    (busy[13] && src1[13] == `ZERO_ROB_IDX && src2[13] == `ZERO_ROB_IDX) | 
    (busy[11] && src1[11] == `ZERO_ROB_IDX && src2[11] == `ZERO_ROB_IDX) | 
    (busy[ 9] && src1[ 9] == `ZERO_ROB_IDX && src2[ 9] == `ZERO_ROB_IDX) | 
    (busy[ 7] && src1[ 7] == `ZERO_ROB_IDX && src2[ 7] == `ZERO_ROB_IDX) | 
    (busy[ 5] && src1[ 5] == `ZERO_ROB_IDX && src2[ 5] == `ZERO_ROB_IDX) | 
    (busy[ 3] && src1[ 3] == `ZERO_ROB_IDX && src2[ 3] == `ZERO_ROB_IDX) | 
    (busy[ 1] && src1[ 1] == `ZERO_ROB_IDX && src2[ 1] == `ZERO_ROB_IDX);
wire [RS_BIT-1:0] exe_idx =
    ({3'b0, exe_flag3} << 3) | 
    ({3'b0, exe_flag2} << 2) | 
    ({3'b0, exe_flag1} << 1) | 
    ({3'b0, exe_flag0});

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

    if (rst || rs_rb) begin
        for (i = 0; i < RS_SIZE; i++) begin
            busy[i] = `FALSE;
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
        if (!rs_full) begin 
            busy[idle_idx] <= `TRUE;
            opt [idle_idx] <= id_opt;
            src1[idle_idx] <= upd_src1;
            src2[idle_idx] <= upd_src2;
            val1[idle_idx] <= upd_val1;
            val2[idle_idx] <= upd_val2;
            imm [idle_idx] <= id_imm;
            idx [idle_idx] <= id_rob_idx;
        end
        // execute
        if (!rs_empty) begin
            busy[exe_idx] <= `FALSE;
            alu_ena  <= `TRUE;
            alu_opt  <= opt [exe_idx];
            alu_val1 <= val1[exe_idx];
            alu_val2 <= val2[exe_idx];
            alu_imm  <= imm [exe_idx];
            alu_rob_idx <= idx[exe_idx];
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