`ifndef ALU_V_ 
`define ALU_V_ 

`include "/home/Modem514/projectAris/riscv/src/utils.v"

module ALU (
    input wire clk,
    input wire rst,
    input wire rdy,

    input wire alu_en,
    input wire alu_st,
    // rs
`ifdef DEBUG
    input wire [`WORD_TP] rs_inst,
`endif
    input wire rs_valid,
    input wire [`INST_OPT_TP] rs_opt,
    input wire [`WORD_TP] rs_val1,
    input wire [`WORD_TP] rs_val2,
    input wire [`WORD_TP] rs_imm,
    input wire [`ROB_IDX_TP] rs_rob_idx,

    // cdb 
    output reg cdb_alu_valid,
    output reg [`ROB_IDX_TP] cdb_alu_src,
    output reg [`WORD_TP] cdb_alu_val,
    output reg cdb_alu_tk
);

integer cnt = 0;

always @(*) begin
    if (rst) begin
        // RESET
        cdb_alu_valid = `FALSE;
        cdb_alu_src = 0;
        cdb_alu_val = 0;
        cdb_alu_tk = 0;
    end
    else if (!rdy || !alu_en || alu_st) begin
        // STALL
        cdb_alu_valid = `FALSE;
        cdb_alu_src = 0;
        cdb_alu_val = 0;
        cdb_alu_tk = 0;
    end
    else if (rs_valid) begin
        cdb_alu_valid = rs_rob_idx != 0;
        cdb_alu_val = `ZERO_WORD;
        cdb_alu_src = rs_rob_idx;
        case (rs_opt)
            `OPT_LUI:   cdb_alu_val = rs_val1  +  rs_imm ;
            `OPT_AUIPC: cdb_alu_val = rs_val1  +  rs_imm ;
            `OPT_JAL:   cdb_alu_val = rs_val1  +  rs_val2;
            `OPT_JALR:  cdb_alu_val = rs_val1  +  rs_imm ;
            `OPT_ADD:   cdb_alu_val = rs_val1  +  rs_val2;
            `OPT_ADDI:  cdb_alu_val = rs_val1  +  rs_imm ;
            `OPT_SUB:   cdb_alu_val = rs_val1  -  rs_val2;
            `OPT_AND:   cdb_alu_val = rs_val1  &  rs_val2;
            `OPT_ANDI:  cdb_alu_val = rs_val1  &  rs_imm ;
            `OPT_OR:    cdb_alu_val = rs_val1  |  rs_val2;
            `OPT_ORI:   cdb_alu_val = rs_val1  |  rs_imm ;
            `OPT_XOR:   cdb_alu_val = rs_val1  ^  rs_val2;
            `OPT_XORI:  cdb_alu_val = rs_val1  ^  rs_imm ;
            `OPT_SLL:   cdb_alu_val = rs_val1 <<  rs_val2[4:0];
            `OPT_SLLI:  cdb_alu_val = rs_val1 <<  rs_imm [4:0];
            `OPT_SRL:   cdb_alu_val = rs_val1 >>  rs_val2[4:0];
            `OPT_SRLI:  cdb_alu_val = rs_val1 >>  rs_imm [4:0];
            `OPT_SRA:   cdb_alu_val = rs_val1 >>> rs_val2[4:0];
            `OPT_SRAI:  cdb_alu_val = rs_val1 >>> rs_imm [4:0];
            `OPT_SLT:   cdb_alu_val = {31'b0, ($signed(rs_val1) < $signed(rs_val2))};
            `OPT_SLTI:  cdb_alu_val = {31'b0, ($signed(rs_val1) < $signed(rs_imm ))};
            `OPT_SLTU:  cdb_alu_val = {31'b0, (rs_val1 < rs_val2)};
            `OPT_SLTIU: cdb_alu_val = {31'b0, (rs_val1 < rs_imm )};
            `OPT_BEQ:   cdb_alu_tk  = (rs_val1 == rs_val2);
            `OPT_BNE:   cdb_alu_tk  = (rs_val1 != rs_val2);
            `OPT_BLT:   cdb_alu_tk  = ($signed(rs_val1) <  $signed(rs_val2));
            `OPT_BGE:   cdb_alu_tk  = ($signed(rs_val1) >= $signed(rs_val2));
            `OPT_BLTU:  cdb_alu_tk  = (rs_val1 <  rs_val2);
            `OPT_BGEU:  cdb_alu_tk  = (rs_val1 >= rs_val2);
            default: begin end
        endcase
`ifdef DEBUG
    cnt++;
    if (rs_inst == 32'h00161613) begin
        // $display("alu inst = %h, opt = %h", rs_inst, rs_opt);
        // $display("alu val1 = %h, val2 = %h, imm = %h", rs_val1, rs_val2, rs_imm);
    end
`endif
        // $display("val1 = %h, val2 = %h, imm = %h", rs_val1, rs_val2, rs_imm);
        // $display("opt = %h, val = %h, src = %h", rs_opt, cdb_alu_val, cdb_alu_src);
    end
    else begin
        cdb_alu_valid = `FALSE;
        cdb_alu_src = 0;
        cdb_alu_val = 0;
        cdb_alu_tk = 0;
    end
end
    
endmodule

`endif 