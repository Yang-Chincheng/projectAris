`ifndef SLB_V_ 
`define SLB_V_ 

`ifdef ONLINE_JUDGE
    `include "utils.v"
`else
`ifdef FPGA_TEST
    `include "utils.v"
`else 
    `include "/home/Modem514/projectAris/riscv/src/utils.v"
`endif
`endif

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
    
`ifdef DEBUG
    input wire [`WORD_TP] id_inst, 
    output wire [`WORD_TP] dbg_inst,   
    output wire [`ROB_IDX_TP] dbg_src1,
    output wire dbg_isld,
    input wire [`WORD_TP] mc_ld_data,
`endif

    // memctrl
    output reg mc_ld_ena,
    output reg [`ADDR_TP] mc_ld_addr,
    output reg [3:0] mc_ld_len,
    output reg mc_ld_sext,
    output reg [`ROB_IDX_TP] mc_ld_src,
    input wire mc_ld_done,

    output reg mc_st_ena,
    output reg [`ADDR_TP] mc_st_addr,
    output reg [3:0] mc_st_len,
    output reg [`WORD_TP] mc_st_data,
    input wire mc_st_done,
    
    // cdb
    input wire cdb_alu_valid,
    input wire [`ROB_IDX_TP] cdb_alu_src,
    input wire [`WORD_TP] cdb_alu_val,
    input wire cdb_ld_valid,
    input wire [`ROB_IDX_TP] cdb_ld_src,
    input wire [`WORD_TP] cdb_ld_val,

    // rob
    output wire [`ROB_IDX_TP] rob_ld_idx,
    output wire [`ROB_IDX_TP] rob_st_idx,
    output wire rob_st_exec_rdy,
    input wire rob_ld_commit_rdy,
    input wire rob_st_commit_rdy
);

localparam IDLE = 0, LOADING = 1, STORING = 2;
reg [1:0] slb_stat;
reg [`ROB_IDX_TP] cache_rd_idx;

reg [SLB_BIT-1:0] q_slb_siz;
reg slb_push_flag;
reg slb_pop_flag;

wire [SLB_BIT-1:0] d_slb_siz = q_slb_siz + (slb_push_flag? 1: 0) + (slb_pop_flag? -1: 0);
assign slb_full  = (d_slb_siz >= SLB_SIZE - 3);
assign slb_empty = (d_slb_siz == 0);

reg [SLB_BIT-1:0] slb_head; // queue element index [slb_head, slb_tail) 
reg [SLB_BIT-1:0] slb_tail;

`ifdef DEBUG
reg [`WORD_TP] inst[SLB_SIZE-1:0];
assign dbg_inst = inst[slb_head];
assign dbg_src1 = src1[slb_head];
assign dbg_isld = isld[slb_head];
`endif 
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
wire [`ADDR_TP] ls_addr = val1[slb_head] + imm[slb_head];

assign rob_ld_idx = isld[slb_head]? dest[slb_head]: `ZERO_ROB_IDX;
assign rob_st_idx = isld[slb_head]? `ZERO_ROB_IDX: dest[slb_head];
assign rob_st_exec_rdy = !rst && rdy && !slb_rb && !slb_empty && st_rdy && slb_stat == IDLE;

always @(posedge clk) begin
    slb_push_flag <= `FALSE;
    slb_pop_flag <= `FALSE;
    q_slb_siz <= d_slb_siz;

    if (rst) begin
        mc_ld_ena <= `FALSE;
        mc_st_ena <= `FALSE;
        q_slb_siz <= 0;
        slb_push_flag <= `FALSE;
        slb_pop_flag <= `FALSE;
        slb_head <= 0;
        slb_tail <= 0;
        slb_stat <= IDLE;
        for (i = 0; i < SLB_SIZE; i = i + 1) begin
`ifdef DEBUG
    inst[i] <= 0;
`endif
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
    else if (slb_rb) begin
        q_slb_siz <= 0;
        slb_push_flag <= `FALSE;
        slb_pop_flag <= `FALSE;
        slb_head <= 0;
        slb_tail <= 0;
        mc_ld_ena <= `FALSE;
        slb_stat <= (slb_stat != STORING? IDLE: slb_stat);
        if (slb_stat == STORING && mc_st_done) begin
            slb_stat <= IDLE;
            mc_st_ena <= `FALSE;
        end
        for (i = 0; i < SLB_SIZE; i = i + 1) begin
`ifdef DEBUG
    inst[i] <= 0;
`endif
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
        // issue
        if (id_valid) begin
`ifdef DEBUG
    inst[slb_tail] <= id_inst;
`endif
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
        if (!slb_empty && slb_stat == IDLE) begin
            // load
            if (ld_rdy && (ls_addr[17:16] != 2'b11 || rob_ld_commit_rdy)) begin
                slb_stat <= LOADING;
                mc_ld_ena <= `TRUE;
                mc_ld_src <= dest[slb_head];
                mc_ld_addr <= ls_addr;
                case (opt[slb_head])
                    `OPT_LB: begin
                        mc_ld_len <= 0;
                        mc_ld_sext <= `TRUE;
                    end
                    `OPT_LBU: begin
                        mc_ld_len <= 0;
                        mc_ld_sext <= `FALSE;
                    end
                    `OPT_LH: begin
                        mc_ld_len <= 1;
                        mc_ld_sext <= `TRUE;
                    end
                    `OPT_LHU: begin
                        mc_ld_len <= 1;
                        mc_ld_sext <= `FALSE;
                    end
                    default: begin
                        mc_ld_len <= 3;
                        mc_ld_sext <= `FALSE;
                    end
                endcase
                slb_pop_flag <= `TRUE;
                slb_head <= slb_head + 1;
                busy[slb_head] <= `FALSE;
            end
            // store
            if (st_rdy && rob_st_commit_rdy) begin
                slb_stat <= STORING;
                slb_pop_flag <= `TRUE;
                slb_head <= slb_head + 1;
                busy[slb_head] <= `FALSE;
                mc_st_ena <= `TRUE;
                mc_st_data <= val2[slb_head];
                mc_st_addr <= ls_addr;
                mc_st_len <= (opt[slb_head] == `OPT_SB? 0: (opt[slb_head] == `OPT_SH? 1: 3));
            end
        end
        if (slb_stat == LOADING && mc_ld_done) begin
            slb_stat <= IDLE;
            mc_ld_ena <= `FALSE;
            mc_ld_addr <= `ZERO_ADDR;
        end
        if (slb_stat == STORING && mc_st_done) begin
            slb_stat <= IDLE;
            mc_st_ena <= `FALSE;
            mc_st_addr <= `ZERO_ADDR;
        end
        // update
        if (cdb_alu_valid && !slb_empty) begin
            for (i = 0; i < SLB_SIZE; i = i + 1) begin
                if (busy[i] && src1[i] == cdb_alu_src) begin
                    src1[i] <= `ZERO_ROB_IDX;
                    val1[i] <= cdb_alu_val;
                end
                if (busy[i] && src2[i] == cdb_alu_src) begin
                    src2[i] <= `ZERO_ROB_IDX;
                    val2[i] <= cdb_alu_val;
                end
            end
        end
        if (cdb_ld_valid && !slb_empty) begin
            for (i = 0; i < SLB_SIZE; i = i + 1) begin
                if (busy[i] && src1[i] == cdb_ld_src) begin
                    src1[i] <= `ZERO_ROB_IDX;
                    val1[i] <= cdb_ld_val;
                end
                if (busy[i] && src2[i] == cdb_ld_src) begin
                    src2[i] <= `ZERO_ROB_IDX;
                    val2[i] <= cdb_ld_val;
                end
            end
        end
    end
end
    
endmodule

`endif 