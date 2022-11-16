`include "../utils.v"

`define LINE_NUM 256
`define LINE_SZ 4
`define LINE_TP 127:0
`define LINE_LN 128

`define TAG_RG 31:12
`define TAG_LN 20

`define IDX_RG 11:4
`define IDX_LN 8

`define OFF_RG 3:2
`define OFF_LN 2

`define OFF3_RG 127:96
`define OFF2_RG 95:64
`define OFF1_RG 63:32
`define OFF0_RG 31:0

module icache(
           input wire clk,
           input wire rst,

           input  wire rd_ena,
           input  wire [`ADDR_TP] rd_addr,
           output wire hit,
           output wire [`WORD_TP] hit_data,

           output reg  mem_rd_ena,
           output wire [`ADDR_TP] mem_rd_addr,
           input  wire mem_rd_done,
           input  wire [`LINE_TP] mem_rd_data
       );

assign mem_rd_addr = rd_addr;

reg valid [`LINE_NUM-1 : 0];
reg [`TAG_RG]  cache_tag [`LINE_NUM-1 : 0];
reg [`LINE_TP] cache_dat [`LINE_NUM-1 : 0];

integer i;

wire [`IDX_RG] idx = rd_addr[`IDX_RG];
assign hit = valid[idx] && cache_tag[idx] == rd_addr[`TAG_RG];
assign hit_data = rd_addr[1]? 
    (rd_addr[0]? cache_dat[idx][`OFF3_RG]: cache_dat[idx][`OFF2_RG]):
    (rd_addr[0]? cache_dat[idx][`OFF1_RG]: cache_dat[idx][`OFF0_RG]);

always @(posedge clk) begin
    mem_rd_ena <= `FALSE;

    if (rst) begin
        for (i = 0; i < `LINE_NUM; i++) begin
            valid[i] = `FALSE;
            cache_tag[i] = `TAG_LN'b0;
            cache_dat[i] = `LINE_LN'b0;
        end
    end
    else if (!rd_ena) begin
        // do nothing
    end
    else if (!hit) begin
        mem_rd_ena <= `TRUE;
    end
    else if (!mem_rd_done) begin
        valid[idx] <= `TRUE;
        cache_tag[idx] <= rd_addr[`TAG_RG];
        cache_dat[idx] <= mem_rd_data;
    end

end


endmodule
