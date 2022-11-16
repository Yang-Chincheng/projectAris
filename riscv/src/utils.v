`define TRUE 1'b1
`define FALSE 1'b0

`define NEXT_PC_INC 4

`define INST_LN 32
`define INST_TP `INST_LN-1:0

`define ADDR_LN 32
`define ADDR_TP `ADDR_LN-1:0
`define ZERO_ADDR `ADDR_LN'b0

`define WORD_LN 32
`define WORD_TP `ADDR_LN-1:0
`define ZERO_WORD `WORD_LN'b0

`define OPC_RG  6: 0
`define FN3_RG 14:12
`define FN7_RG 31:25
`define  RD_RG 11: 7
`define RS1_RG 19:15
`define RS2_RG 24:20

// opcode
`define OPC_LUI   7'b0110111
`define OPC_AUIPC 7'b0010111
`define OPC_JAL   7'b1101111
`define OPC_JALR  7'b1100111
`define OPC_BR    7'b1100011
`define OPC_LD    7'b0000011
`define OPC_ST    7'b0100011
`define OPC_ARI   7'b0010011
`define OPC_AR    7'b0110011

`define FN3_JALR 3'b000
`define FN3_BEQ  3'b000
`define FN3_BNE  3'b001
`define FN3_BLT  3'b100
`define FN3_BGE  3'b101
`define FN3_BLTU 3'b110
`define FN3_BGEU 3'b111

`define FN3_LB  3'b000
`define FN3_LH  3'b001
`define FN3_LW  3'b010
`define FN3_LBU 3'b100
`define FN3_LHU 3'b101
`define FN3_SB  3'b000
`define FN3_SH  3'b001
`define FN3_SW  3'b010

`define FN3_ADDI  3'b000
`define FN3_SLTI  3'b010
`define FN3_SLTIU 3'b011
`define FN3_XORI  3'b100
`define FN3_ORI   3'b110
`define FN3_ANDI  3'b111
`define FN3_SLLI  3'b001
`define FN3_SRLI  3'b101
`define FN3_SRAI  3'b101

`define FN3_ADD  3'b000
`define FN3_SUB  3'b000
`define FN3_SLL  3'b001
`define FN3_SLT  3'b010
`define FN3_SLTU 3'b011
`define FN3_XOR  3'b100
`define FN3_SRL  3'b101
`define FN3_SRA  3'b101
`define FN3_OR   3'b110
`define FN3_AND  3'b111