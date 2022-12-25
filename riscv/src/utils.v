`ifndef UTILS_V_
`define UTILS_V_

`define TRUE  (1'b1)
`define FALSE (1'b0)

`define NEXT_PC_INC 4

`define INST_LN 32
`define INST_TP (`INST_LN-1):0

`define ADDR_LN 32
`define ADDR_TP (`ADDR_LN-1):0
`define ZERO_ADDR (`ADDR_LN'b0)

`define WORD_LN 32
`define WORD_TP (`WORD_LN-1):0
`define ZERO_WORD (`WORD_LN'b0)

`define HWORD_LN 16
`define HWORD_TP (`HWORD_LN-1):0
`define ZERO_HWORD (`HWORD_LN'b0)

`define BYTE_LN 8
`define BYTE_TP (`BYTE_LN-1):0
`define ZERO_BYTE (`BYTE_LN'b0)



`define INST_OPT_TP 5:0
`define INST_TY_TP 2:0

`define TYPE_R (3'b000)
`define TYPE_B (3'b001)
`define TYPE_U (3'b010)
`define TYPE_J (3'b011)
`define TYPE_I (3'b100)
`define TYPE_S (3'b101)

`define OPT_NONE  (6'h00)
`define OPT_LUI   (6'h01)
`define OPT_AUIPC (6'h02)
`define OPT_JAL   (6'h03)
`define OPT_JALR  (6'h04)
`define OPT_BEQ   (6'h05)
`define OPT_BNE   (6'h06)
`define OPT_BLT   (6'h07)
`define OPT_BGE   (6'h08)
`define OPT_BLTU  (6'h09)
`define OPT_BGEU  (6'h0a)
`define OPT_LB    (6'h0b)
`define OPT_LH    (6'h0c)
`define OPT_LW    (6'h0d)
`define OPT_LBU   (6'h0e)
`define OPT_LHU   (6'h0f)
`define OPT_SB    (6'h10)
`define OPT_SH    (6'h11)
`define OPT_SW    (6'h12)
`define OPT_ADDI  (6'h13)
`define OPT_SLTI  (6'h14)
`define OPT_SLTIU (6'h15)
`define OPT_XORI  (6'h16)
`define OPT_ORI   (6'h17)
`define OPT_ANDI  (6'h18)
`define OPT_SLLI  (6'h19)
`define OPT_SRLI  (6'h1a)
`define OPT_SRAI  (6'h1b)
`define OPT_ADD   (6'h1c)
`define OPT_SUB   (6'h1d)
`define OPT_SLL   (6'h1e)
`define OPT_SLT   (6'h1f)
`define OPT_SLTU  (6'h20)
`define OPT_SRL   (6'h21)
`define OPT_SRA   (6'h22)
`define OPT_XOR   (6'h23)
`define OPT_OR    (6'h24)
`define OPT_AND   (6'h25)

`define OPT_BR_BEG `OPT_BEQ
`define OPT_BR_END `OPT_BGEU
`define OPT_LD_BEG `OPT_LB
`define OPT_LD_END `OPT_LHU
`define OPT_ST_BEG `OPT_SB
`define OPT_ST_END `OPT_SW
`define OPT_IM_BEG `OPT_ADDI
`define OPT_IM_END `OPT_SRAI
`define OPT_AL_BEG `OPT_ADD
`define OPT_AL_END `OPT_AND  

// `define OPC_LUI   (7'b0110111)
// `define OPC_AUIPC (7'b0010111)
// `define OPC_JAL   (7'b1101111)
// `define OPC_JALR  (7'b1100111)
// `define OPC_BR    (7'b1100011)
// `define OPC_LD    (7'b0000011)
// `define OPC_ST    (7'b0100011)
// `define OPC_ARI   (7'b0010011)
// `define OPC_AR    (7'b0110011)

// `define FN3_JALR (3'b000)
// `define FN3_BEQ  (3'b000)
// `define FN3_BNE  (3'b001)
// `define FN3_BLT  (3'b100)
// `define FN3_BGE  (3'b101)
// `define FN3_BLTU (3'b110)
// `define FN3_BGEU (3'b111)

// `define FN3_LB  (3'b000)
// `define FN3_LH  (3'b001)
// `define FN3_LW  (3'b010)
// `define FN3_LBU (3'b100)
// `define FN3_LHU (3'b101)
// `define FN3_SB  (3'b000)
// `define FN3_SH  (3'b001)
// `define FN3_SW  (3'b010)

// `define FN3_ADDI  (3'b000)
// `define FN3_SLTI  (3'b010)
// `define FN3_SLTIU (3'b011)
// `define FN3_XORI  (3'b100)
// `define FN3_ORI   (3'b110)
// `define FN3_ANDI  (3'b111)
// `define FN3_SLLI  (3'b001)
// `define FN3_SRLI  (3'b101)
// `define FN3_SRAI  (3'b101)

// `define FN3_ADD  (3'b000)
// `define FN3_SUB  (3'b000)
// `define FN3_SLL  (3'b001)
// `define FN3_SLT  (3'b010)
// `define FN3_SLTU (3'b011)
// `define FN3_XOR  (3'b100)
// `define FN3_SRL  (3'b101)
// `define FN3_SRA  (3'b101)
// `define FN3_OR   (3'b110)
// `define FN3_AND  (3'b111)

`define ROB_IDX_LN 5
`define ROB_IDX_TP (`ROB_IDX_LN-1):0
`define ZERO_ROB_IDX (`ROB_IDX_LN'b0)

`define REG_IDX_LN 5
`define REG_IDX_TP (`REG_IDX_LN-1):0
`define ZERO_REG_IDX (`REG_IDX_LN'b0)

`endif