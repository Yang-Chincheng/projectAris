`ifndef DISPATCHER_V_
`define DISPATCHER_V_

`ifdef ONLINE_JUDGE
    `include "utils.v"
`else
`ifdef FPGA_TEST
    `include "utils.v"
`else 
    `include "/home/Modem514/projectAris/riscv/src/utils.v"
`endif
`endif

module dispatcher(
    input wire clk, // system clock
    input wire rst, // reset signal
    input wire rdy,

    input wire id_en, // inst decode unit enabling signal
    input wire id_st, // inst decode unit stall signal
    input wire id_rb, // inst decode unit rollback signal
    output wire id_full,

    // ifu
    input wire if_valid,
    input wire [`WORD_TP] if_inst, // inst from ifu
    input wire [`ADDR_TP] if_cur_pc, // pc from ifu
    input wire [`ADDR_TP] if_mis_pc, // rollback target from ifu
    input wire if_pb_tk_stat, // predict taken status from ifu

    // dec
    output wire [`WORD_TP] dec_inst,
    input wire [`INST_TY_TP] dec_ty,
    input wire [`INST_OPT_TP] dec_opt,
    input wire [`REG_IDX_TP] dec_rd,
    input wire [`REG_IDX_TP] dec_rs1,
    input wire [`REG_IDX_TP] dec_rs2,
    input wire [`WORD_TP] dec_imm,
    input wire dec_is_ls,

    // reg
    output wire [`REG_IDX_TP] reg_rs1,
    output wire [`REG_IDX_TP] reg_rs2,
    input wire [`ROB_IDX_TP] reg_src1,
    input wire [`ROB_IDX_TP] reg_src2,
    input wire [`WORD_TP] reg_val1,
    input wire [`WORD_TP] reg_val2,
    
    output reg reg_rn_ena,
    output reg [`REG_IDX_TP] reg_rn_rd,
    output reg [`ROB_IDX_TP] reg_rn_idx,
    
    // rs
`ifdef DEBUG
    output reg [`WORD_TP] rs_inst,
    output reg [`WORD_TP] slb_inst,
`endif
    input wire rs_full,
    output reg rs_ena,
    output reg [`INST_OPT_TP] rs_opt,
    output reg [`ROB_IDX_TP] rs_src1,
    output reg [`ROB_IDX_TP] rs_src2,
    output reg [`WORD_TP] rs_val1,
    output reg [`WORD_TP] rs_val2,
    output reg [`WORD_TP] rs_imm,  
    output reg [`ROB_IDX_TP] rs_rob_idx,

    // slb
    input wire slb_full,
    output reg slb_ena,
    output reg [`INST_OPT_TP] slb_opt,
    output reg [`ROB_IDX_TP] slb_src1,
    output reg [`ROB_IDX_TP] slb_src2,
    output reg [`WORD_TP] slb_val1,
    output reg [`WORD_TP] slb_val2,
    output reg [`WORD_TP] slb_imm, 
    output reg [`ROB_IDX_TP] slb_rob_idx,
    output reg slb_isld,

    // rob
    input wire rob_full,
    input wire [`ROB_IDX_TP] rob_idx,
    
    output wire [`ROB_IDX_TP] rob_src1,
    output wire [`ROB_IDX_TP] rob_src2,
    input wire rob_src1_rdy,
    input wire rob_src2_rdy,
    input wire [`WORD_TP] rob_val1,
    input wire [`WORD_TP] rob_val2,
    
`ifdef DEBUG
    output reg [`WORD_TP] rob_inst,
`endif
    output reg rob_ena,
    output reg [`INST_OPT_TP] rob_opt,
    output reg [`REG_IDX_TP] rob_dest,
    output reg [`WORD_TP] rob_data,
    output reg [`ADDR_TP] rob_addr,
    output reg [`ADDR_TP] rob_cur_pc,
    output reg [`ADDR_TP] rob_mis_pc,
    output reg rob_pb_tk_stat,

    // cdb
    input wire cdb_alu_valid,
    input wire [`ROB_IDX_TP] cdb_alu_src,
    input wire [`WORD_TP] cdb_alu_val,
    input wire cdb_ld_valid,
    input wire [`ROB_IDX_TP] cdb_ld_src,
    input wire [`WORD_TP] cdb_ld_val
);

reg disp_ena;
reg [`WORD_TP] disp_inst;
reg [`ADDR_TP] disp_cur_pc;
reg [`ADDR_TP] disp_mis_pc;
reg disp_pb_tk_stat;

reg [`INST_TY_TP] disp_ty;
reg [`INST_OPT_TP] disp_opt;
reg [`REG_IDX_TP] disp_rd;
reg [`REG_IDX_TP] disp_rs1;
reg [`REG_IDX_TP] disp_rs2;
reg [`WORD_TP] disp_imm;
reg disp_is_ls;

assign dec_inst = if_inst;
assign reg_rs1 = disp_rs1;
assign reg_rs2 = disp_rs2;
assign rob_src1 = reg_src1;
assign rob_src2 = reg_src2;

assign id_full = rob_full | (dec_is_ls & slb_full) | (!dec_is_ls & rs_full);

wire [`ROB_IDX_TP] org_src1 = (reg_src1 == 0 || rob_src1_rdy)? `ZERO_ROB_IDX: reg_src1;
wire [`ROB_IDX_TP] org_src2 = (reg_src2 == 0 || rob_src2_rdy)? `ZERO_ROB_IDX: reg_src2;
wire [`WORD_TP] org_val1 = (reg_src1 == 0)? reg_val1: (rob_src1_rdy? rob_val1: `ZERO_WORD);
wire [`WORD_TP] org_val2 = (reg_src2 == 0)? reg_val2: (rob_src2_rdy? rob_val2: `ZERO_WORD);

wire [`ROB_IDX_TP] upd_src1 = (cdb_alu_valid && cdb_alu_src == org_src1)? `ZERO_ROB_IDX
    : ((cdb_ld_valid && cdb_ld_src == org_src1)? `ZERO_ROB_IDX: org_src1);
wire [`ROB_IDX_TP] upd_src2 = (cdb_alu_valid && cdb_alu_src == org_src2)? `ZERO_ROB_IDX
    : ((cdb_ld_valid && cdb_ld_src == org_src2)? `ZERO_ROB_IDX: org_src2);
wire [`WORD_TP] upd_val1 = (cdb_alu_valid && cdb_alu_src == org_src1)? cdb_alu_val
    : ((cdb_ld_valid && cdb_ld_src == org_src1)? cdb_ld_val: org_val1);
wire [`WORD_TP] upd_val2 = (cdb_alu_valid && cdb_alu_src == org_src2)? cdb_alu_val
    : ((cdb_ld_valid && cdb_ld_src == org_src2)? cdb_ld_val: org_val2);

always @(posedge clk) begin
    rs_ena <= `FALSE;
    slb_ena <= `FALSE;
    rob_ena <= `FALSE;
    reg_rn_ena <= `FALSE;
    disp_ena <= `FALSE;
    
    if (rst) begin 
        // RESET
    end
    else if (!id_en || id_st || !rdy) begin
        // STALL
    end
    else if (id_rb) begin
        // ROLLBACK
    end
    else begin
    if (if_valid) begin
        disp_ena <= `TRUE;
        disp_inst <= if_inst;
        disp_cur_pc <= if_cur_pc;
        disp_mis_pc <= if_mis_pc;
        disp_pb_tk_stat <= if_pb_tk_stat;
        disp_ty <= dec_ty;
        disp_opt <= dec_opt;
        disp_rd <= dec_rd;
        disp_rs1 <= dec_rs1;
        disp_rs2 <= dec_rs2;
        disp_imm <= dec_imm;
        disp_is_ls <= dec_is_ls;
    end
    if (disp_ena) begin
        // issue to slb
        if (disp_is_ls) begin
`ifdef DEBUG
    slb_inst <= disp_inst;
`endif
            slb_ena <= `TRUE;
            slb_opt <= disp_opt;
            slb_imm <= disp_imm;
            slb_rob_idx <= rob_idx;
            case (disp_ty)
                `TYPE_S: begin
                    slb_src1 <= upd_src1;
                    slb_val1 <= upd_val1;
                    slb_src2 <= upd_src2;
                    slb_val2 <= upd_val2;
                    slb_isld <= `FALSE;
                end
                `TYPE_I: begin
                    slb_src1 <= upd_src1;
                    slb_val1 <= upd_val1;
                    slb_src2 <= `ZERO_ROB_IDX;
                    slb_val2 <= `ZERO_WORD;
                    slb_isld <= `TRUE;
                end
                default: begin end 
            endcase
        end
        // issue to rs
        else begin
`ifdef DEBUG
    rs_inst <= disp_inst;
`endif
            rs_ena <= `TRUE;
            rs_opt <= disp_opt;
            rs_imm <= disp_imm;
            rs_rob_idx <= rob_idx;
            case (disp_ty)
                `TYPE_R, `TYPE_B, `TYPE_S: begin
                    rs_src1 <= upd_src1;
                    rs_val1 <= upd_val1;
                    rs_src2 <= upd_src2;
                    rs_val2 <= upd_val2;   
                end
                `TYPE_I: begin
                    rs_src1 <= upd_src1;
                    rs_val1 <= upd_val1;
                    rs_src2 <= `ZERO_ROB_IDX;
                    rs_val2 <= `ZERO_WORD;
                end
                `TYPE_U: begin
                    rs_src1 <= `ZERO_ROB_IDX;
                    rs_val1 <= (disp_opt == `OPT_LUI)? `ZERO_WORD: disp_cur_pc;
                    rs_src2 <= `ZERO_ROB_IDX;
                    rs_val2 <= `ZERO_WORD;
                end
                `TYPE_J: begin
                    rs_src1 <= `ZERO_ROB_IDX;
                    rs_val1 <= disp_cur_pc;
                    rs_src2 <= `ZERO_ROB_IDX;
                    rs_val2 <= `NEXT_PC_INC;
                end
                default: begin end
            endcase
        end

        // issue to rob
`ifdef DEBUG
    rob_inst <= disp_inst;
`endif
        rob_ena <= `TRUE;
        rob_opt <= disp_opt;
        rob_cur_pc <= disp_cur_pc;
        rob_mis_pc <= disp_mis_pc;
        rob_pb_tk_stat <= disp_pb_tk_stat;
        rob_data <= `ZERO_WORD;
        rob_addr <= `ZERO_ADDR;
        case (disp_ty)
            `TYPE_B, `TYPE_S: begin
                rob_dest <= `ZERO_REG_IDX;
            end
            `TYPE_R, `TYPE_J, `TYPE_U, `TYPE_I: begin
                rob_dest <= disp_rd;
                if (disp_rd != 0) begin
                    reg_rn_ena <= `TRUE;
                    reg_rn_rd <= disp_rd;
                    reg_rn_idx <= rob_idx;
                end
            end
            default: begin end
        endcase
    end
    end
end
    
endmodule

`endif