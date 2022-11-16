`include "../utils.v"

module dec_immI_sext(
           input  wire [`WORD_TP] inst,
           output wire [`WORD_TP] immI_sext
       );

assign immI_sext = {{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};

endmodule

module dec_immJ_sext(
           input  wire [`WORD_TP] inst,
           output wire [`WORD_TP] immJ_sext
       );

assign immJ_sext = {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};

endmodule