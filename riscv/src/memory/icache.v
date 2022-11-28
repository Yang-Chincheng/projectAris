`include "../utils.v"

`define LINE_NUM 256
`define LINE_SZ 4
`define LINE_TP 127:0
`define LINE_LN 128
`define ZERO_LINE (`LINE_LN'b0)

`define TAG_RG 31:12
`define TAG_LN 20
`define ZERO_TAG (`TAG_LN'b0)

`define IDX_RG 11:4
`define IDX_LN 8
`define ZERO_IDX (`IDX_LN'b0)

`define OFF_RG 3:2
`define OFF_LN 2

`define OFF3_RG 127:96
`define OFF2_RG 95:64
`define OFF1_RG 63:32
`define OFF0_RG 31:0

module icache #(
    LINE_NUM = `LINE_NUM
) (
    input wire clk,
    input wire rst,
    input wire rsy,

    input wire cache_en,
    input wire cache_st,
    input wire cache_rb,

    input wire [`ADDR_TP] if_addr,
    output wire if_cache_hit,
    output wire [`WORD_TP] if_hit_word,

    output reg mem_ena,
    output reg [`ADDR_TP] mem_addr,
    input wire mem_valid,
    input wire [`LINE_TP] mem_line
);

parameter IDLE = 0, BUSY = 1;
reg cache_stat;

reg valid [LINE_NUM-1:0];
reg [`TAG_RG] tag [LINE_NUM-1:0];
reg [`LINE_TP] dat [LINE_NUM-1:0];

integer i;

wire [`IDX_RG] if_idx = if_addr[`IDX_RG];
assign if_cache_hit = valid[if_idx] && tag[if_idx] == if_addr[`TAG_RG];
assign if_hit_word = (if_addr[1]? 
    (if_addr[0]? dat[if_idx][`OFF3_RG]: dat[if_idx][`OFF2_RG]):
    (if_addr[0]? dat[if_idx][`OFF1_RG]: dat[if_idx][`OFF0_RG])
);

always @(posedge clk) begin
    if (rst) begin
        cache_stat <= IDLE;
        for (i = 0; i < `LINE_NUM; i++) begin
            valid[i] = `FALSE;
            tag[i] = `ZERO_TAG;
            dat[i] = `ZERO_LINE;
        end
    end
    else if (!cache_en || cache_st) begin
        // STALL
    end
    else begin
        if (!if_cache_hit && cache_stat == IDLE) begin
            mem_ena <= `TRUE;
            mem_addr <= {if_addr[31:4], 4'b0};
            cache_stat <= BUSY;
        end
        if (cache_stat == BUSY && mem_valid) begin
            mem_ena <= `FALSE;
            valid[if_idx] <= `TRUE;
            tag[if_idx] <= mem_addr[`TAG_RG];
            dat[if_idx] <= mem_line;
            cache_stat <= IDLE;
        end
    end
end


endmodule
