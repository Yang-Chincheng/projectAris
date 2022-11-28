`include "../utils.v"

/**
 * TODO:
 * (1) full&empty signal: current/next cycle
 * (2) cache_ena signal: interaction with dcache (& eliminate cycle gap bewteen reads?)
 * (3) use parameter to represent current status: IDLE, LOADING, ...
 * (4) load&store d-cache management
 */

`define SLB_BIT 4
`define SLB_SIZE (1 << `SLB_BIT)

module SLB #(
    SLB_BIT = `SLB_BIT,
    SLB_SIZE = `SLB_SIZE
) (
    input wire clk,
    input wire rst,
    input wire rdy,

    input wire slb_en,
    input wire slb_st,
    input wire slb_rb,
    output wire slb_full,
    output wire slb_empty,

    // idu
    input wire id_ena,
    input wire [`INST_OPT_TP] id_opt,
    input wire [`ROB_IDX_TP] id_src1,
    input wire [`ROB_IDX_TP] id_src2,
    input wire [`WORD_TP] id_val1,
    input wire [`WORD_TP] id_val2,
    input wire [`WORD_TP] id_imm,
    input wire [`ROB_IDX_TP] id_rob_idx,
    
    // dcache
    output reg cache_rd_ena,
    output reg [`ADDR_TP] cache_rd_addr,
    output reg [`INST_OPT_TP] cache_rd_opt,  
    input wire cache_rd_hit,
    input wire [`WORD_TP] cache_rd_hit_dat,

    // cdb
    input wire cdb_alu_valid,
    input wire [`ROB_IDX_TP] cdb_alu_src,
    input wire [`WORD_TP] cdb_alu_val,
    output reg cdb_ld_valid,
    output reg [`ROB_IDX_TP] cdb_ld_src,
    output reg [`WORD_TP] cdb_ld_val,

    // rob
    output reg rob_ena,
    output reg [`ROB_IDX_TP] rob_src,
    output reg [`WORD_TP] rob_val,
    output reg [`ADDR_TP] rob_addr
);

parameter IDLE = 0, LOADING = 1;
reg slb_stat;
reg [`ROB_IDX_TP] cache_rd_idx;

reg [SLB_BIT-1:0] lag_slb_siz;
reg slb_push_flag;
reg slb_pop_flag;

wire [SLB_BIT-1:0] slb_siz = lag_slb_siz + (slb_push_flag? 1: 0) + (slb_pop_flag? -1: 0);
assign slb_full  = (slb_siz == SLB_SIZE);
assign slb_empty = (slb_siz == 0);

reg [SLB_BIT-1:0] slb_head; // queue element index [slb_head, slb_tail) 
reg [SLB_BIT-1:0] slb_tail;

reg                busy[SLB_SIZE-1:0];
reg [`INST_OPT_TP] opt [SLB_SIZE-1:0];
reg [`ROB_IDX_TP]  src1[SLB_SIZE-1:0];
reg [`ROB_IDX_TP]  src2[SLB_SIZE-1:0];
reg [`WORD_TP]     val1[SLB_SIZE-1:0];
reg [`WORD_TP]     val2[SLB_SIZE-1:0];
reg [`WORD_TP]     imm [SLB_SIZE-1:0];
reg [`ROB_IDX_TP]  idx [SLB_SIZE-1:0];

integer i;

wire [`ROB_IDX_TP] upd_src1 = (cdb_alu_valid && cdb_alu_src == id_src1? `ZERO_ROB_IDX
    : (cdb_ld_valid && cdb_ld_src == id_src1? `ZERO_ROB_IDX: id_src1)); 
wire [`ROB_IDX_TP] upd_src2 = (cdb_alu_valid && cdb_alu_src == id_src2? `ZERO_ROB_IDX
    : (cdb_ld_valid && cdb_ld_src == id_src2? `ZERO_ROB_IDX: id_src2)); 
wire [`WORD_TP] upd_val1 = (cdb_alu_valid && cdb_alu_src == id_src1? cdb_alu_val
    : (cdb_ld_valid && cdb_ld_src == id_src1? cdb_ld_val: id_val1));
wire [`WORD_TP] upd_val2 = (cdb_alu_valid && cdb_alu_src == id_src2? cdb_alu_val
    : (cdb_ld_valid && cdb_ld_src == id_src2? cdb_ld_val: id_val2));

always @(posedge clk) begin
    cdb_ld_valid <= `FALSE;
    rob_ena <= `FALSE;
  
    if (rst || slb_rb) begin
        cache_rd_ena <= `FALSE;
        lag_slb_siz <= 0;
        slb_push_flag <= `FALSE;
        slb_pop_flag <= `FALSE;
        slb_head <= 0;
        slb_tail <= 0;
        slb_stat <= IDLE;
        for (i = 0; i < SLB_SIZE; i++) begin
            busy[i] <= `FALSE;
            opt [i] <= `OPT_NONE;
            src1[i] <= `ZERO_ROB_IDX;
            src2[i] <= `ZERO_ROB_IDX;
            val1[i] <= `ZERO_WORD;
            val2[i] <= `ZERO_WORD;
            imm [i] <= `ZERO_WORD;
            idx [i] <= `ZERO_ROB_IDX;
        end
    end
    else if (!rdy || !slb_en || slb_st) begin
        // STALL
    end
    else begin
        slb_push_flag <= `FALSE;
        slb_pop_flag <= `FALSE;
        // issue
        if (!slb_full) begin
            slb_push_flag <= `TRUE;
            busy[slb_tail] <= `TRUE;
            opt [slb_tail] <= id_opt;
            src1[slb_tail] <= upd_src1;
            src2[slb_tail] <= upd_src2;
            val1[slb_tail] <= upd_val1;
            val2[slb_tail] <= upd_val2;
            imm [slb_tail] <= id_imm;
            idx [slb_tail] <= id_rob_idx;
            slb_tail <= slb_tail + 1;
        end
        // execute
        if (!slb_empty) begin
            // load
            if (slb_stat == IDLE && opt[slb_head] >= `OPT_LB && opt[slb_head] <= `OPT_LHU) begin
                slb_pop_flag <= `TRUE;
                slb_stat <= LOADING;
                slb_head <= slb_head + 1;
                cache_rd_ena  <= `TRUE;
                cache_rd_addr <= val1[slb_head] + imm[slb_head];
                cache_rd_opt  <= opt[slb_head];
                cache_rd_idx  <= idx[slb_head];
                busy[slb_head] <= `FALSE;
            end
            // store
            if (opt[slb_head] >= `OPT_SB && opt[slb_head] <= `OPT_SW) begin
                slb_pop_flag <= `TRUE;
                rob_ena <= `TRUE;
                rob_src <= src2[slb_head];
                rob_addr <= val1[slb_head] + imm[slb_head];
            end
        end
        if (slb_stat == LOADING && cache_rd_hit) begin
            cache_rd_ena <= `FALSE;
            cdb_ld_valid <= `TRUE;
            cdb_ld_src <= cache_rd_idx;
            cdb_ld_val <= cache_rd_hit_dat;
            slb_stat <= IDLE;
        end
        // update
        if (cdb_alu_valid && !slb_empty) begin
            for (i = 0; i < SLB_SIZE; i++) begin
                if (busy[i] && src1[i] == cdb_alu_src) val1[i] <= cdb_alu_val;
                if (busy[i] && src2[i] == cdb_alu_src) val2[i] <= cdb_alu_val;
            end
        end
        if (cdb_ld_valid && !slb_empty) begin
            for (i = 0; i < SLB_SIZE; i++) begin
                if (busy[i] && src1[i] == cdb_ld_src) val1[i] <= cdb_ld_val;
                if (busy[i] && src2[i] == cdb_ld_src) val2[i] <= cdb_ld_val;
            end
        end

    end
    lag_slb_siz <= slb_siz;
end
    
endmodule