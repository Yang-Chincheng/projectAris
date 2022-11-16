`include "../utils.v"

`define ADDR_HASH 9:2

module predictor #(
           BHT_BIT = 2,
           BHT_SIZE = 256
       ) (
           input wire clk,
           input wire rst,

           input wire pd_ena,

           input wire [`ADDR_TP] pd_pc,
           input wire [`WORD_TP] pd_inst,

           output wire pd_taken_stat,
           output wire [`WORD_TP] pd_off,

           input wire fb_ena,
           input wire fb_taken_stat,
           input wire [`ADDR_TP] fb_pc
       );

localparam STR_TK = 2'b11, WEK_TK = 2'b10;
localparam STR_NT = 2'b00, WEK_NT = 2'b01;

reg [BHT_BIT-1: 0] bht[BHT_SIZE-1: 0];

integer i;

wire [`ADDR_HASH] pd_pc_hash = pd_pc[`ADDR_HASH];
wire [`ADDR_HASH] fb_pc_hash = fb_pc[`ADDR_HASH];

wire [`OPC_RG] opc = pd_pc[`OPC_RG];
assign pd_taken_stat = (opc == `OPC_BR)? 
    (bht[pd_pc_hash] >= WEK_TK) :
    ((opc == `OPC_JAL)? `TRUE: `FALSE);

assign pd_off = (opc == `OPC_BR)? 
    ({{20{pd_inst[31]}}, pd_inst[7], pd_inst[30:25], pd_inst[11:8], 1'b0}):
    ((opc != `OPC_JAL)? `ZERO_WORD:
    {{12{pd_inst[31]}}, pd_inst[19:12], pd_inst[20], pd_inst[30:21], 1'b0});

always @(posedge clk) begin
    if (rst) begin
        for (i = 0; i < BHT_SIZE; i++) begin
            bht[i] = 2'b0;
        end
    end
    else if (!pd_ena) begin
        // do nothing
    end
    else if (fb_ena) begin
        if (fb_taken_stat) begin
            bht[fb_pc_hash] <= (bht[fb_pc_hash] < STR_TK)? bht[fb_pc_hash] + 1: STR_TK;
        end
        else begin
            bht[fb_pc_hash] <= (bht[fb_pc_hash] > STR_NT)? bht[fb_pc_hash] - 1: STR_NT;
        end
    end
end

endmodule