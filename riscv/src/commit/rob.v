`include "../utils.v"

`define ROB_BIT `ROB_IDX_LN
`define ROB_SIZE (1 << `ROB_BIT)

/**
 * TODO:
 * (1) JALR: stall before result is calculated (which part of function is stalled?)
 * (2) load&store d-cache management
 */

module ROB #(
    ROB_BIT = `ROB_BIT,
    ROB_SIZE = `ROB_SIZE
) (
    input wire clk,
    input wire rst,
    input wire rdy,

    input wire rob_en,
    input wire rob_st,
    output wire rob_empty,
    output wire rob_full,
    output wire [`ROB_IDX_TP] rob_idx,
    output reg rob_rb_ena,

    // if
    output reg [`ADDR_TP] if_rb_pc,

    // id
    input wire [`ROB_IDX_TP] id_src1,
    input wire [`ROB_IDX_TP] id_src2,
    output wire id_src1_rdy,
    output wire id_src2_rdy,
    output wire [`WORD_TP] id_val1,
    output wire [`WORD_TP] id_val2,
    
    input wire id_valid,
    input wire [`INST_OPT_TP] id_opt,
    input wire [`REG_IDX_TP] id_dest,
    input wire [`WORD_TP] id_data,
    input wire [`ADDR_TP] id_addr,
    input wire [`ADDR_TP] id_cur_pc,
    input wire [`ADDR_TP] id_mis_pc,
    input wire id_pb_tk,

    // reg
    output reg reg_wr_ena,
    output reg [`REG_IDX_TP] reg_wr_rd,
    output reg [`WORD_TP] reg_wr_val,
    
    // slb
    input wire slb_valid,
    input wire [`ROB_IDX_TP] slb_src,
    input wire [`WORD_TP] slb_val,
    input wire [`ADDR_TP] slb_addr,

    // cdb
    input wire cdb_alu_valid,
    input wire cdb_alu_tk,
    input wire [`ROB_IDX_TP] cdb_alu_src,
    input wire [`WORD_TP] cdb_alu_val,
    input wire cdb_ld_valid,
    input wire [`ROB_IDX_TP] cdb_ld_src,
    input wire [`WORD_TP] cdb_ld_val,

    // dcache
    output reg cache_wr_ena,
    output reg [`ADDR_TP] cache_wr_addr,
    output reg [`INST_OPT_TP] cache_wr_opt,
    output reg [`WORD_TP] cache_wr_data,
    input wire cache_wr_hit,

    // bp
    output reg bp_fb_ena,
    output reg bp_fb_tk,
    output reg [`ADDR_TP] bp_fb_pc
);

parameter IDLE = 0, STORING = 1;
reg rob_stat;

reg [ROB_BIT-1:0] lag_rob_siz;
reg rob_push_flag, rob_pop_flag;
wire [ROB_BIT-1:0] rob_siz = lag_rob_siz + (rob_push_flag? 1: 0) + (rob_pop_flag? -1: 0);
assign rob_full = (rob_siz == ROB_SIZE);
assign rob_empty = (rob_siz == 0);
reg [ROB_BIT-1:0] rob_head;
reg [ROB_BIT-1:0] rob_tail;

reg                busy   [ROB_SIZE-1:0];
reg [`INST_OPT_TP] opt    [ROB_SIZE-1:0];
reg [`REG_IDX_TP]  dest   [ROB_SIZE-1:0];
reg [`WORD_TP]     data   [ROB_SIZE-1:0];
reg [`ADDR_TP]     addr   [ROB_SIZE-1:0];
reg [`ADDR_TP]     cur_pc [ROB_SIZE-1:0];
reg [`ADDR_TP]     nex_pc [ROB_SIZE-1:0];
reg [`ADDR_TP]     mis_pc [ROB_SIZE-1:0];
reg                pb_tk  [ROB_SIZE-1:0];
reg                rl_tk  [ROB_SIZE-1:0];

assign rob_idx = rob_tail;
assign id_src1_rdy = ((cdb_alu_valid && cdb_alu_src == id_src1)? `TRUE
    : ((cdb_ld_valid && cdb_ld_src == id_src1)? `TRUE: busy[id_src1]));
assign id_src2_rdy = ((cdb_alu_valid && cdb_alu_src == id_src2)? `TRUE
    : ((cdb_ld_valid && cdb_ld_src == id_src2)? `TRUE: busy[id_src2]));
assign id_val1 = ((cdb_alu_valid && cdb_alu_src == id_src1)? cdb_alu_val
    : ((cdb_ld_valid && cdb_ld_src == id_src1)? cdb_ld_val: data[id_src1]));
assign id_val2 = ((cdb_alu_valid && cdb_alu_src == id_src2)? cdb_alu_val
    : ((cdb_ld_valid && cdb_ld_src == id_src2)? cdb_ld_val: data[id_src2]));

integer i;

always @(posedge clk) begin
    reg_wr_ena <= `FALSE;
    bp_fb_ena <= `FALSE;
    rob_rb_ena <= `FALSE;

    if (rst) begin
        for (i = 0; i < ROB_SIZE; i++) begin
            busy[i] <= `FALSE;
            opt [i] <= `OPT_NONE;
            dest[i] <= `ZERO_REG_IDX;
            data[i] <= `ZERO_WORD;
            addr[i] <= `ZERO_ADDR;
            cur_pc[i] <= `ZERO_ADDR; 
            nex_pc[i] <= `ZERO_ADDR; 
            mis_pc[i] <= `ZERO_ADDR;
            pb_tk [i] <= `FALSE; 
            rl_tk [i] <= `FALSE;
        end
    end 
    else if (!rdy || !rob_en || rob_st) begin
        // STALL
    end
    else begin
        // issue
        if (id_valid && !rob_full) begin
            busy[rob_tail] <= `TRUE;
            opt[rob_tail] <= id_opt;
            dest[rob_tail] <= id_dest;
            data[rob_tail] <= id_data;
            addr[rob_tail] <= id_addr;
            cur_pc[rob_tail] <= id_cur_pc;
            // nex_pc[rob_tail] <= id_nex_pc;
            mis_pc[rob_tail] <= id_mis_pc;
            pb_tk [rob_tail] <= id_pb_tk;
            rl_tk [rob_tail] <= `FALSE;
            rob_tail <= rob_tail + 1;
            rob_push_flag <= `TRUE;
        end
        // commit
        if (!rob_empty) begin
            case (opt[rob_head])
                // branch
                `OPT_BEQ, `OPT_BNE, `OPT_BLT, `OPT_BGE, `OPT_BLTU, `OPT_BGEU: begin
                    bp_fb_ena <= `TRUE;
                    bp_fb_pc <= cur_pc[rob_head];
                    bp_fb_tk <= rl_tk [rob_head];
                    if (rl_tk[rob_head] != pb_tk[rob_head]) begin
                        rob_rb_ena <= `TRUE;
                        if_rb_pc <= mis_pc[rob_head];
                    end
                    rob_pop_flag <= `FALSE;
                end
                `OPT_SB, `OPT_SH, `OPT_SW: begin
                    if (rob_stat == IDLE) begin
                        cache_wr_ena <= `TRUE;
                        cache_wr_opt <= opt[rob_head];
                        cache_wr_addr <= addr[rob_head];
                        cache_wr_data <= data[rob_head];
                        rob_stat <= STORING;
                        rob_pop_flag <= `TRUE;
                    end
                end
                `OPT_JALR: begin
                    // TODO
                end
                default: begin
                    reg_wr_ena <= `TRUE;
                    reg_wr_rd <= dest[rob_head];
                    reg_wr_val <= data[rob_head];
                end
            endcase
        end
        // update
        if (rob_stat == STORING && cache_wr_hit) begin
            rob_stat <= IDLE;
            cache_wr_ena <= `FALSE;
        end
        if (cdb_alu_valid) begin
            data[cdb_alu_src] <= cdb_alu_val;
            rl_tk[cdb_alu_src] <= cdb_alu_tk;
            busy[cdb_alu_src] <= `FALSE;
        end
        if (cdb_ld_valid) begin
            data[cdb_ld_src] <= cdb_ld_val;
            busy[cdb_ld_src] <= `FALSE;
        end
        if (slb_valid) begin
            data[slb_src] <= slb_val;
            addr[slb_src] <= slb_addr;
            busy[slb_src] <= `FALSE;
        end
        
    end
end

endmodule