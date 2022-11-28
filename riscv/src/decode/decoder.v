`include "../utils.v"

`define OPC_RG  6: 0
`define FN3_RG 14:12
`define FN7_RG 31:25
`define  RD_RG 11: 7
`define RS1_RG 19:15
`define RS2_RG 24:20

module decoder(
    input wire [`WORD_TP] inst,
    output reg [`INST_TY_TP] ty,
    output reg [`INST_OPT_TP] opt,
    output reg [`REG_IDX_TP] rd,
    output reg [`REG_IDX_TP] rs1,
    output reg [`REG_IDX_TP] rs2,
    output reg [`WORD_TP] imm,
    output reg is_ls
);

wire [`OPC_RG] opc  = inst[`OPC_RG];
wire [`FN3_RG] fun3 = inst[`FN3_RG];
wire [`FN7_RG] fun7 = inst[`FN7_RG];

always @(*) begin
    rd  = inst[`RD_RG];
    rs1 = inst[`RS1_RG];
    rs2 = inst[`RS2_RG];
    case (opc)
        'h37: begin 
            opt = `OPT_LUI;
            ty  = `TYPE_U;
            is_ls = `FALSE; 
        end
        'h17: begin 
            opt = `OPT_AUIPC;
            ty  = `TYPE_U; 
            is_ls = `FALSE; 
        end
        'h6f: begin 
            opt = `OPT_JAL;
            ty  = `TYPE_J; 
            is_ls = `FALSE; 
        end
        'h67: begin 
            opt = `OPT_JALR;
            ty  = `TYPE_I; 
            is_ls = `FALSE; 
        end
        'h63: begin
            ty = `TYPE_B;
            case (fun3)
                'h0: opt = `OPT_BEQ;
                'h1: opt = `OPT_BNE;
                'h4: opt = `OPT_BLT;
                'h5: opt = `OPT_BGE;
                'h6: opt = `OPT_BLTU;
                'h7: opt = `OPT_BGEU;
            endcase
            is_ls = `FALSE; 
        end
        'h03: begin
            ty  = `TYPE_I;
            case (fun3)
                'h0: opt = `OPT_LB;
                'h1: opt = `OPT_LH;
                'h2: opt = `OPT_LW;
                'h4: opt = `OPT_LBU;
                'h5: opt = `OPT_LHU;
            endcase
            is_ls = `TRUE;
        end
        'h23: begin
            ty  = `TYPE_S;
            case (fun3)
                'h0: opt = `OPT_SB;
                'h1: opt = `OPT_SH;
                'h2: opt = `OPT_SW;
            endcase
            is_ls = `TRUE;
        end
        'h13: begin
            case (fun3)
                'h0: begin 
                    opt = `OPT_ADDI;
                    ty  = `TYPE_I;
                end
                'h1: begin 
                    opt = `OPT_SLLI;
                    ty  = `TYPE_I;
                end
                'h2: begin 
                    opt = `OPT_SLTI;
                    ty  = `TYPE_S;
                end
                'h3: begin 
                    opt = `OPT_SLTIU;
                    ty  = `TYPE_S;
                end
                'h4: begin 
                    opt = `OPT_XORI;
                    ty  = `TYPE_I;
                end
                'h5: begin 
                    ty  = `TYPE_I;
                    opt = fun7[30]? `OPT_SRAI: `OPT_SRLI;
                end
                'h6: begin 
                    opt = `OPT_ORI;
                    ty  = `TYPE_I;
                end
                'h7: begin 
                    opt = `OPT_ANDI;
                    ty  = `TYPE_I;
                end
            endcase
            is_ls = `FALSE; 
        end
        'h33: begin
            ty  = `TYPE_R;
            case (fun3)
                'h0: opt = fun7[30]? `OPT_SUB: `OPT_ADD;
                'h1: opt = `OPT_SLL;
                'h2: opt = `OPT_SLT;
                'h3: opt = `OPT_SLTU;
                'h4: opt = `OPT_XOR;
                'h5: opt = fun7[30]? `OPT_SRA: `OPT_SRL;
                'h6: opt = `OPT_OR;
                'h7: opt = `OPT_AND;
            endcase
            is_ls = `FALSE; 
        end        
        default: begin end        
    endcase

    case (ty)
        `TYPE_I: imm = {{20{inst[31]}}, inst[31:20]};
        `TYPE_S: imm = {{20{inst[31]}}, inst[31:25], inst[11:7]};
        `TYPE_B: imm = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
        `TYPE_U: imm = {inst[31:12], 12'b0};
        `TYPE_J: imm = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};
        default: begin end
    endcase
end

endmodule