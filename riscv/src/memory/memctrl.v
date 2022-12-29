`ifndef MEMCTRL_V_ 
`define MEMCTRL_V_ 

`ifdef ONLINE_JUDGE
    `include "utils.v"
`else 
    `include "/home/Modem514/projectAris/riscv/src/utils.v"
`endif

`define LINE_TP 127:0
`define OFF3_RG 127:96
`define OFF2_RG 95:64
`define OFF1_RG 63:32
`define OFF0_RG 31:0

module memctrl(
    input wire clk,
    input wire rst,
    input wire rdy,

    input wire mc_en,
    input wire mc_st,
    input wire mc_rb,

    // icache
    input wire icache_fc_valid,
    input wire [`ADDR_TP] icache_fc_addr,
    output reg icache_fc_done,
    output reg [`LINE_TP] icache_fc_line,

    // slb
    input wire [1:0] slb_st_cnt,
    input wire slb_st_valid, 
    input wire [`ADDR_TP] slb_st_addr,
    input wire [`WORD_TP] slb_st_data,
    input wire [3:0] slb_st_len,
    output reg slb_st_done,

    input wire [1:0] slb_ld_cnt,
    input wire slb_ld_valid,
    input wire [`ADDR_TP] slb_ld_addr,
    input wire [3:0] slb_ld_len,
    input wire slb_ld_sext,
    input wire [`ROB_IDX_TP] slb_ld_src,
    output reg slb_ld_done,
    output wire [`WORD_TP] slb_ld_data,
    
    // cdb
    output reg cdb_ld_ena,
    output reg [`ROB_IDX_TP] cdb_ld_src,
    output reg [`WORD_TP] cdb_ld_val,

    // ram
    output reg ram_rw_sel,
    output reg [`ADDR_TP] ram_addr,
    output reg [`BYTE_TP] ram_wr_byte,
    input wire [`BYTE_TP] ram_rd_byte
);

wire [`BYTE_TP] st_bytes[3:0];
assign {st_bytes[3], st_bytes[2], st_bytes[1], st_bytes[0]} = slb_st_data;

parameter READ = 0, WRITE = 1;
parameter IDLE = 0, FETCHING = 1, LOADING = 2, STORING = 3;
reg [1:0] mc_stat;
reg [3:0] counter;

reg ram_rw_start;
reg [`BYTE_TP] rd_buff[15:0];

integer i;

`ifdef DEBUG
assign slb_ld_data =                     
    (slb_ld_len == 0? {{24{rd_buff[0][7]}}, rd_buff[0]} :
    (slb_ld_len == 1? {{16{rd_buff[1][7]}}, rd_buff[1], rd_buff[0]} :
    {rd_buff[3], rd_buff[2], rd_buff[1], rd_buff[0]}));
`endif 

always @(posedge clk) begin
    cdb_ld_ena <= `FALSE;
    slb_st_done <= `FALSE;
    slb_ld_done <= `FALSE;
    icache_fc_done <= `FALSE;

    if (rst) begin
        mc_stat <= IDLE;
        ram_rw_sel <= READ;
        ram_addr <= `ZERO_ADDR;
        ram_rw_start <= `FALSE;
        for (i = 0; i < 16; ++i) begin
            rd_buff[i] <= `ZERO_BYTE;
        end
    end
    else if (!rdy || !mc_en || mc_st) begin
        // STALL
    end
    else begin
        // launch a r/w procedure (st > ld > fetch)
        if (mc_stat == IDLE) begin
            // $display("+ %d %d %d", slb_st_cnt, slb_ld_cnt, icache_fc_valid);
            // $display("- %d %d %d", slb_st_cnt-slb_st_done, slb_ld_cnt-slb_ld_done, icache_fc_valid-icache_fc_done);
            if (slb_st_valid && !slb_st_done) begin
                mc_stat <= STORING;
                ram_rw_start <= `TRUE;
                counter <= 0;
                ram_rw_sel <= WRITE;
                ram_addr <= slb_st_addr;
                ram_wr_byte <= st_bytes[0];
            end
            else if (slb_ld_valid && !slb_ld_done && !mc_rb) begin
                    mc_stat <= LOADING;
                    ram_rw_start <= `TRUE;
                    counter <= 15;
                    ram_rw_sel <= READ;
                    ram_addr <= slb_ld_addr;
                    for (i = 0; i < 4; i++) begin
                        rd_buff[i] <= `ZERO_BYTE;
                    end
            end
            else if (icache_fc_valid && !icache_fc_done) begin
                mc_stat <= FETCHING;
                ram_rw_start <= `TRUE;
                counter <= 15;
                ram_rw_sel <= READ;
                ram_addr <= icache_fc_addr;
            end
        end
        // storing data from rob
        else if (mc_stat == STORING) begin
            ram_rw_start <= `FALSE;
            if (counter == slb_st_len) begin
                mc_stat <= IDLE;
                ram_rw_sel <= READ;
                ram_addr <= `ZERO_ADDR;
                counter <= 0;
                slb_st_done <= `TRUE;
            end
            else begin
                ram_rw_sel <= WRITE;
                counter <= counter + 1;
                ram_addr <= ram_addr + 1;
                ram_wr_byte <= st_bytes[counter + 1];
            end
        end
        // loading data to cdb
        else if (mc_stat == LOADING) begin
            if (mc_rb) begin
                mc_stat <= IDLE;
                counter <= 0;
                ram_rw_sel <= READ;
                ram_addr <= `ZERO_ADDR;
            end
            else begin
                ram_rw_start <= `FALSE;
                rd_buff[counter] <= ram_rd_byte;
                if (counter == slb_ld_len) begin
                    mc_stat <= IDLE;
                    ram_rw_sel <= READ;
                    ram_addr <= `ZERO_ADDR;
                    counter <= 0;
                    slb_ld_done <= `TRUE;
                    cdb_ld_ena <= `TRUE;
                    cdb_ld_src <= slb_ld_src;
                    cdb_ld_val <= 
                        (slb_ld_len == 0? {{24{(slb_ld_sext? ram_rd_byte[7]: 1'b0)}}, ram_rd_byte} :
                        (slb_ld_len == 1? {{16{(slb_ld_sext? ram_rd_byte[7]: 1'b0)}}, ram_rd_byte, rd_buff[0]} :
                        {ram_rd_byte, rd_buff[2], rd_buff[1], rd_buff[0]}));
                end
                else begin
                    ram_rw_sel <= READ;
                    counter <= counter + 1;
                    ram_addr <= ram_addr + 1;
                end
            end
        end
        // fetching data to icache
        else if (mc_stat == FETCHING) begin
            ram_rw_start <= `FALSE;
            rd_buff[counter] <= ram_rd_byte;
            if (!ram_rw_start && counter == 15) begin
                mc_stat <= IDLE;
                ram_rw_sel <= READ;
                ram_addr <= `ZERO_ADDR;
                counter <= 0;
                icache_fc_done <= `TRUE;
                icache_fc_line <= {
                    ram_rd_byte, rd_buff[14], rd_buff[13], rd_buff[12],
                    rd_buff[11], rd_buff[10], rd_buff[ 9], rd_buff[ 8],
                    rd_buff[ 7], rd_buff[ 6], rd_buff[ 5], rd_buff[ 4],
                    rd_buff[ 3], rd_buff[ 2], rd_buff[ 1], rd_buff[ 0]
                };
            end
            else begin
                ram_rw_sel <= READ;
                counter <= counter + 1;
                ram_addr <= ram_addr + 1;
            end
        end
    end
end
    
endmodule

`endif 