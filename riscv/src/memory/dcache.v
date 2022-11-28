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

module dcache #(
    LINE_NUM = `LINE_NUM
) (
    input wire clk,
    input wire rst,
    input wire rdy,

    input wire cache_en,
    input wire cache_st,
    input wire cache_rb,

    // slb
    input wire slb_rd_valid,
    input wire [`ADDR_TP] slb_rd_addr,
    input wire [`INST_OPT_TP] slb_rd_opt,
    output wire slb_cache_hit,
    output wire [`WORD_TP] slb_hit_word,

    // rob
    input wire rob_wr_valid,
    input wire [`ADDR_TP] rob_wr_addr,
    input wire [`INST_OPT_TP] rob_wr_opt,
    input wire [`WORD_TP] rob_wr_data,
    output wire rob_cache_hit, 
    
    // memctrl
    input wire mem_valid,
    output reg mem_wr_ena,
    output reg [`ADDR_TP] mem_wr_addr,
    output reg [`LINE_TP] mem_wr_line,
    output reg mem_rd_ena,
    output reg [`ADDR_TP] mem_rd_addr,
    input wire [`LINE_TP] mem_rd_line
);

parameter IDLE = 0, WRITING = 1, READING = 2;
reg [1:0] cache_stat;

reg dirty[LINE_NUM-1:0];
reg valid[LINE_NUM-1:0];
reg [`TAG_RG] tag[LINE_NUM-1:0];
reg [`LINE_TP] dat[LINE_NUM-1:0];

wire [`IDX_RG] slb_rd_idx = slb_rd_addr[`IDX_RG];
wire [`IDX_RG] rob_wr_idx = rob_wr_addr[`IDX_RG];
wire [`IDX_RG] mem_rd_idx = mem_rd_addr[`IDX_RG];
wire [`IDX_RG] mem_wr_idx = mem_wr_addr[`IDX_RG];

assign slb_cache_hit = (valid[slb_rd_idx] && tag[slb_rd_idx] == slb_rd_addr[`TAG_RG]);
assign rob_cache_hit = (valid[rob_wr_idx] && tag[rob_wr_idx] == rob_wr_addr[`TAG_RG]);

assign slb_hit_word = (slb_rd_addr[1]?
    (slb_rd_addr[0]? dat[slb_rd_idx][`OFF3_RG]: dat[slb_rd_idx][`OFF2_RG]):
    (slb_rd_addr[0]? dat[slb_rd_idx][`OFF1_RG]: dat[slb_rd_idx][`OFF0_RG])
);
wire [`WORD_TP] rob_hit_word = (rob_wr_addr[1]?
    (rob_wr_addr[0]? dat[rob_wr_idx][`OFF3_RG]: dat[rob_wr_idx][`OFF2_RG]):
    (rob_wr_addr[0]? dat[rob_wr_idx][`OFF1_RG]: dat[rob_wr_idx][`OFF0_RG])
);

integer i;

always @(posedge clk) begin

    if (rst) begin
        cache_stat <= IDLE;
        for (i = 0; i < LINE_NUM; i++) begin
            dirty[i] = `FALSE;
            valid[i] = `FALSE;
            tag[i] = `ZERO_TAG;
            dat[i] = `ZERO_LINE;
        end
    end
    else if (!rdy || !cache_en || cache_st) begin
        // STALL
    end
    else if (cache_rb) begin
        // ROLLBACK
    end
    else begin
        if (slb_rd_valid) begin
            if (!slb_cache_hit && cache_stat == IDLE) begin
                mem_wr_line <= dat[slb_rd_idx];
                mem_wr_addr <= {tag[slb_rd_idx], slb_rd_idx, 4'b0};
                mem_rd_addr <= {slb_rd_addr[31:4], 4'b0};
                if (valid[slb_rd_idx] && dirty[slb_rd_idx]) begin
                    mem_wr_ena <= `TRUE;
                    cache_stat <= WRITING;
                end
                else begin
                    mem_rd_ena <= `TRUE;
                    cache_stat <= READING;
                end
            end 
        end
        if (rob_wr_valid) begin
            if (rob_cache_hit) begin
                dirty[rob_wr_idx] <= `TRUE;
                case (rob_wr_opt)
                    `OPT_SB: rob_hit_word[`BYTE_TP ] <= rob_wr_data[`BYTE_TP ];
                    `OPT_SH: rob_hit_word[`HWORD_TP] <= rob_wr_data[`HWORD_TP];
                    `OPT_SW: rob_hit_word[`WORD_TP ] <= rob_wr_data[`WORD_TP ];
                    default: begin end
                endcase
            end
            else if (cache_stat == IDLE) begin
                mem_wr_line <= dat[rob_wr_idx];
                mem_wr_addr <= {tag[rob_wr_idx], rob_wr_idx, 4'b0};
                mem_rd_addr <= {rob_wr_addr[31:4], 4'b0};
                if (valid[rob_wr_idx] && dirty[rob_wr_idx]) begin
                    mem_wr_ena <= `TRUE;
                    cache_stat <= WRITING;
                end
                else begin
                    mem_rd_ena <= `TRUE;
                    cache_stat <= READING;
                end
            end
        end

        if (mem_valid) begin
            if (cache_stat == WRITING) begin
                mem_wr_ena <= `FALSE;
                mem_rd_ena <= `TRUE;
                cache_stat <= READING;
            end
            if (cache_stat == READING) begin
                dirty[mem_rd_idx] <= `FALSE;
                valid[mem_rd_idx] <= `TRUE;
                mem_rd_ena <= `FALSE;
                cache_stat <= IDLE;
            end
        end
    end

end


endmodule
