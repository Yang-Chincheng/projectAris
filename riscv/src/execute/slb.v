`ifndef SLB_V_ 
`define SLB_V_ 

`include "/home/Modem514/projectAris/riscv/src/utils.v"

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
    parameter SLB_BIT = `SLB_BIT,
    parameter SLB_SIZE = `SLB_SIZE
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
    input wire id_valid,
    input wire [`INST_OPT_TP] id_opt,
    input wire [`ROB_IDX_TP] id_src1,
    input wire [`ROB_IDX_TP] id_src2,
    input wire [`WORD_TP] id_val1,
    input wire [`WORD_TP] id_val2,
    input wire [`WORD_TP] id_imm,
    input wire [`ROB_IDX_TP] id_rob_idx,
    
    // memctrl
    output reg mc_ld_ena,
    output reg [`ADDR_TP] mc_ld_addr,
    output reg [3:0] mc_ld_len,
    output reg [`ROB_IDX_TP] mc_ld_src,
    input wire mc_ld_done,
    input wire [`WORD_TP] mc_ld_data,

    // cdb
    input wire cdb_alu_valid,
    input wire [`ROB_IDX_TP] cdb_alu_src,
    input wire [`WORD_TP] cdb_alu_val,
    input wire cdb_ld_valid,
    input wire [`ROB_IDX_TP] cdb_ld_src,
    input wire [`WORD_TP] cdb_ld_val,

    // rob
    output reg rob_ena,
    output reg [`ROB_IDX_TP] rob_src,
    output reg [`WORD_TP] rob_val,
    output reg [`ADDR_TP] rob_addr,
    output wire [`ROB_IDX_TP] rob_st_idx,
    input wire rob_st_rdy
);

parameter IDLE = 0, LOADING = 1;
reg slb_stat;
reg [`ROB_IDX_TP] cache_rd_idx;

reg [SLB_BIT-1:0] lag_slb_siz;
reg slb_push_flag;
reg slb_pop_flag;

wire [SLB_BIT-1:0] slb_siz = lag_slb_siz + (slb_push_flag? 1: 0) + (slb_pop_flag? -1: 0);
assign slb_full  = (slb_siz >= SLB_SIZE - 3);
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
reg [`ROB_IDX_TP]  dest[SLB_SIZE-1:0];
reg                isld[SLB_SIZE-1:0];

integer i;

wire [`ROB_IDX_TP] upd_src1 = ((cdb_alu_valid && cdb_alu_src == id_src1)? `ZERO_ROB_IDX
    : ((cdb_ld_valid && cdb_ld_src == id_src1)? `ZERO_ROB_IDX: id_src1)); 
wire [`ROB_IDX_TP] upd_src2 = ((cdb_alu_valid && cdb_alu_src == id_src2)? `ZERO_ROB_IDX
    : ((cdb_ld_valid && cdb_ld_src == id_src2)? `ZERO_ROB_IDX: id_src2)); 
wire [`WORD_TP] upd_val1 = ((cdb_alu_valid && cdb_alu_src == id_src1)? cdb_alu_val
    : ((cdb_ld_valid && cdb_ld_src == id_src1)? cdb_ld_val: id_val1));
wire [`WORD_TP] upd_val2 = ((cdb_alu_valid && cdb_alu_src == id_src2)? cdb_alu_val
    : ((cdb_ld_valid && cdb_ld_src == id_src2)? cdb_ld_val: id_val2));


wire ld_rdy = isld[slb_head] && src1[slb_head] == `ZERO_ROB_IDX;
wire st_rdy = !isld[slb_head] && src1[slb_head] == `ZERO_ROB_IDX && src2[slb_head] == `ZERO_ROB_IDX;

always @(posedge clk) begin
    rob_ena <= `FALSE;
    slb_push_flag <= `FALSE;
    slb_pop_flag <= `FALSE;
        

    if (rst || slb_rb) begin
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
            dest[i] <= `ZERO_ROB_IDX;
        end
    end
    else if (!rdy || !slb_en || slb_st) begin
        // STALL
    end
    else begin
        slb_push_flag <= `FALSE;
        slb_pop_flag <= `FALSE;
        // issue
        if (id_valid) begin
            busy[slb_tail] <= `TRUE;
            opt [slb_tail] <= id_opt;
            src1[slb_tail] <= upd_src1;
            src2[slb_tail] <= upd_src2;
            val1[slb_tail] <= upd_val1;
            val2[slb_tail] <= upd_val2;
            imm [slb_tail] <= id_imm;
            dest[slb_tail] <= id_rob_idx;
            isld[slb_tail] <= (id_opt >= `OPT_LB && id_opt <= `OPT_LHU); 
            slb_push_flag <= `TRUE;
            slb_tail <= slb_tail + 1;
        end
        // execute
        if (!slb_empty) begin
            // load
            if (slb_stat == IDLE && ld_rdy) begin
                slb_stat <= LOADING;
                mc_ld_ena <= `TRUE;
                mc_ld_addr <= val1[slb_head] + imm[slb_head];
                mc_ld_len <= (opt[slb_head] == `OPT_LB? 0: (opt[slb_head] == `OPT_LH? 1: 3));
                slb_pop_flag <= `TRUE;
                slb_head <= slb_head + 1;
                busy[slb_head] <= `FALSE;
            end
            // store
            if (st_rdy) begin
                if (rob_st_rdy) begin
                    slb_pop_flag <= `TRUE;
                    slb_head <= slb_head + 1;
                    busy[slb_head] <= `FALSE;
                end
                else begin
                    rob_ena <= `TRUE;
                    rob_src <= src2[slb_head];
                    rob_val <= val2[slb_head];
                    rob_addr <= val1[slb_head] + imm[slb_head];
                end
            end
        end
        if (slb_stat == LOADING && mc_ld_done) begin
            slb_stat <= IDLE;
            mc_ld_ena <= `FALSE;
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

`endif 