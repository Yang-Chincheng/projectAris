`ifndef ICACHE_V
`define ICACHE_V

`include "/home/Modem514/projectAris/riscv/src/utils.v"

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
    parameter LINE_NUM = `LINE_NUM
) (
    input wire clk,
    input wire rst,
    input wire rdy,

    input wire cache_en,
    input wire cache_st,
    input wire cache_rb,

    input wire [`ADDR_TP] if_addr,
    output wire if_cache_hit,
    output wire [`WORD_TP] if_hit_word,

    output reg mc_fc_ena,
    output reg [`ADDR_TP] mc_fc_addr,
    input wire mc_fc_done,
    input wire [`LINE_TP] mc_fc_line
);

parameter IDLE = 0, FETCHING = 1;
reg cache_stat;

reg valid [LINE_NUM-1:0];
reg [`TAG_RG] tag [LINE_NUM-1:0];
reg [`LINE_TP] dat [LINE_NUM-1:0];

integer i;

wire [`IDX_RG] upd_idx = mc_fc_addr[`IDX_RG];
wire [`IDX_RG] if_idx = if_addr[`IDX_RG];
assign if_cache_hit = valid[if_idx] && tag[if_idx] == if_addr[`TAG_RG];
assign if_hit_word = (if_addr[3]? 
    (if_addr[2]? dat[if_idx][`OFF3_RG]: dat[if_idx][`OFF2_RG]):
    (if_addr[2]? dat[if_idx][`OFF1_RG]: dat[if_idx][`OFF0_RG])
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
    else if (!rdy || !cache_en || cache_st) begin
        // STALL
    end
    else begin
        if (!if_cache_hit && cache_stat == IDLE) begin
            cache_stat <= FETCHING;
            mc_fc_ena <= `TRUE;
            mc_fc_addr <= {if_addr[31:4], 4'b0};
        end
        if (cache_stat == FETCHING && mc_fc_done) begin
            cache_stat <= IDLE;
            mc_fc_ena <= `FALSE;
            valid[upd_idx] <= `TRUE;
            tag[upd_idx] <= mc_fc_addr[`TAG_RG];
            dat[upd_idx] <= mc_fc_line;
            cache_stat <= IDLE;
        end
    end
end


endmodule

`endif 