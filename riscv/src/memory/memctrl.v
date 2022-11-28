`include "../utils.v"

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
    input wire icache_rd_valid,
    input wire [`ADDR_TP] icache_rd_addr,
    output reg icache_ena,
    output reg [`LINE_TP] icache_rd_line,

    // dcache
    output reg dcache_ena,
    input wire dcache_rd_valid,
    input wire dcache_wr_valid,
    input wire [`ADDR_TP] dcache_rd_addr,
    input wire [`ADDR_TP] dcache_wr_addr,
    input wire [`LINE_TP] dcache_wr_line,
    output reg [`LINE_TP] dcache_rd_line,

    // ram
    output reg ram_ena,
    output reg ram_rw_sel,
    output reg [`ADDR_TP] ram_addr,
    output reg [`BYTE_TP] ram_wr_byte,
    input wire [`BYTE_TP] ram_rd_byte
);

parameter READ = 0, WRITE = 1;
parameter IDLE = 0, FETCHING = 1, LOADING = 2, STORING = 3;
reg [1:0] mc_stat;

reg [`BYTE_TP] rd_buff[15:0];
reg [`BYTE_TP] wr_buff[15:0];
reg [`ADDR_TP] byte_off;

integer i;

always @(posedge clk) begin

    if (rst) begin
        mc_stat <= IDLE;
    end
    else if (!rdy || !mc_en || mc_st) begin
        // STALL
    end
    else begin
        if (mc_stat == IDLE) begin
            if (icache_rd_valid) begin
                mc_stat <= FETCHING;
                ram_ena <= `TRUE;
                ram_rw_sel <= READ;
                ram_addr <= icache_rd_addr;
                byte_off <= 0;
            end
            else if (dcache_rd_valid) begin
                mc_stat <= LOADING;
                ram_ena <= `TRUE;
                ram_rw_sel <= READ;
                ram_addr <= dcache_rd_addr;
                byte_off <= 0;
            end
            else if (dcache_wr_valid) begin
                mc_stat <= STORING;
                ram_ena <= `TRUE;
                ram_rw_sel <= WRITE;

                {
                    wr_buff[15], wr_buff[14], wr_buff[13], wr_buff[11],
                    wr_buff[10], wr_buff[ 9], wr_buff[ 8], wr_buff[ 7],
                    wr_buff[ 6], wr_buff[ 5], wr_buff[ 4], wr_buff[ 3],
                    wr_buff[ 3], wr_buff[ 2], wr_buff[ 1], wr_buff[ 0]
                }
                = dcache_wr_line;
                
                ram_addr <= dcache_wr_addr;
                ram_wr_byte <= dcache_rd_line[7:0];
                byte_off <= 0;
            end
        end
        else begin
            if (byte_off == 16) begin
                mc_stat <= IDLE;
                ram_ena <= `FALSE;
                case (mc_stat)
                    FETCHING: begin
                        icache_ena <= `TRUE;
                        icache_rd_line <= {
                            rd_buff[15], rd_buff[14], rd_buff[13], rd_buff[11],
                            rd_buff[10], rd_buff[ 9], rd_buff[ 8], rd_buff[ 7],
                            rd_buff[ 6], rd_buff[ 5], rd_buff[ 4], rd_buff[ 3],
                            rd_buff[ 3], rd_buff[ 2], rd_buff[ 1], wr_buff[ 0]
                        };
                    end 
                    LOADING: begin
                        dcache_ena <= `TRUE;
                        icache_rd_line <= {
                            rd_buff[15], rd_buff[14], rd_buff[13], rd_buff[11],
                            rd_buff[10], rd_buff[ 9], rd_buff[ 8], rd_buff[ 7],
                            rd_buff[ 6], rd_buff[ 5], rd_buff[ 4], rd_buff[ 3],
                            rd_buff[ 3], rd_buff[ 2], rd_buff[ 1], wr_buff[ 0]
                        };
                    end
                    STORING: begin
                        dcache_ena <= `TRUE;
                    end
                endcase
            end
            else begin
                ram_wr_byte <= wr_buff[byte_off+1];
                rd_buff[byte_off] <= ram_rd_byte;
                ram_addr <= ram_addr + 8;
                byte_off <= byte_off + 1;
            end
        end
    end
end
    
endmodule