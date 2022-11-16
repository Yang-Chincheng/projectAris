`include "../utils.v"
`include "../common/fifo/fifo.v"

`define CACHE_SZ 256
`define LINE_SZ 4

`define TAG_RG 31:10
`define TAG_LN 22

`define IDX_RG 9:2
`define IDX_LN 8

module fetcher(
           // global ctrl signal
           input wire clk,
           input wire rst,
           input wire rdy,

           input wire empty,

           input wire rb_flag, // rollback flag from rob
           input wire [`ADDR_TP] rb_pc_target, // rollback pc target from rob

           output wire inst_buf_empty

       );

reg [`WORD_TP] pc;

integer i;

always @(posedge clk) begin
    if (rst) begin
    end
    else if (!rdy) begin
        // do nothing
    end
    else begin

    end
end

endmodule

