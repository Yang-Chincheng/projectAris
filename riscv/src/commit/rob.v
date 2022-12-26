`ifndef ROB_V_ 
`define ROB_V_

`include "/home/Modem514/projectAris/riscv/src/utils.v"

`define ROB_BIT `ROB_IDX_LN
`define ROB_SIZE (1 << `ROB_BIT)

/**
 * TODO:
 * (1) JALR: stall before result is calculated (which part of function is stalled?)
 * (2) load&store d-cache management
 */

module ROB #(
    parameter ROB_BIT = `ROB_BIT,
    parameter ROB_SIZE = `ROB_SIZE
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

`ifdef DEBUG
    input wire [`WORD_TP] id_inst,
`endif
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
    output reg [`ROB_IDX_TP] reg_wr_idx,
    
    // slb
    input wire slb_valid,
    input wire [`ROB_IDX_TP] slb_src,
    input wire [`WORD_TP] slb_val,
    input wire [`ADDR_TP] slb_addr,
    input wire [`ROB_IDX_TP] slb_st_idx,
    output wire slb_st_rdy,

    // cdb
    input wire cdb_alu_valid,
    input wire cdb_alu_tk,
    input wire [`ROB_IDX_TP] cdb_alu_src,
    input wire [`WORD_TP] cdb_alu_val,
    input wire cdb_ld_valid,
    input wire [`ROB_IDX_TP] cdb_ld_src,
    input wire [`WORD_TP] cdb_ld_val,

    // memctrl
    output reg mc_st_ena,
    output reg [`ADDR_TP] mc_st_addr,
    output reg [`WORD_TP] mc_st_data,
    output reg [3:0] mc_st_len,
    input wire mc_st_done,

`ifdef DEBUG
    output wire head_rdy,
    output reg [31:0] commit_cnt,
    output reg [31:0] commit_inst,
    output wire [`WORD_TP] dbg_data,
    output wire dbg_src1_rdy,
    output wire [`WORD_TP] dbg_inst,
`endif

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
assign rob_full = (rob_siz >= ROB_SIZE - 5);
assign rob_empty = (rob_siz == 0);
reg [ROB_BIT-1:0] rob_head;
reg [ROB_BIT-1:0] rob_tail;

`ifdef DEBUG
reg [`WORD_TP]     inst   [ROB_SIZE-1:0];
assign dbg_inst = inst[rob_head];
`endif
reg                inque  [ROB_SIZE-1:0];
reg                busy   [ROB_SIZE-1:0];
reg [`INST_OPT_TP] opt    [ROB_SIZE-1:0];
reg [`REG_IDX_TP]  dest   [ROB_SIZE-1:0];
reg [`WORD_TP]     data   [ROB_SIZE-1:0];
reg [`ADDR_TP]     addr   [ROB_SIZE-1:0];
reg [`ADDR_TP]     cur_pc [ROB_SIZE-1:0];
reg [`ADDR_TP]     mis_pc [ROB_SIZE-1:0];
reg                pb_tk  [ROB_SIZE-1:0];
reg                rl_tk  [ROB_SIZE-1:0];

assign rob_idx = (id_valid? (rob_tail == ROB_SIZE-1? 1: rob_tail + 1): rob_tail); 

// always @(*) begin
//     if (cdb_alu_valid) begin
//         if (cdb_alu_src == id_src1) begin
//             id_src1_rdy = `TRUE;
//             id_val1 = cdb_alu_val;
//         end
//         if (cdb_ld_src == id_src2) begin
//             id_src2_rdy = `TRUE;
//             id_val2 = cdb_alu_val;
//         end
//     end
//     else if (cdb_ld_valid) begin
//         if (cdb_ld_src == id_src1) begin
//             id_src1_rdy = `TRUE;
//             id_val1 = cdb_ld_val;
//         end
//         if (cdb_ld_src == id_src2) begin
//             id_src2_rdy = `TRUE;
//             id_val2 = cdb_ld_val;
//         end
//     end
//     else begin
//         id_src1_rdy = inque[id_src1] && !busy[id_src1];
//         id_val1 = data[id_src1];
//         id_src2_rdy = inque[id_src2] && !busy[id_src2];
//         id_val2 = data[id_src2];
//     end
// end
assign id_src1_rdy = ((cdb_alu_valid && cdb_alu_src == id_src1)? `TRUE
    : ((cdb_ld_valid && cdb_ld_src == id_src1)? `TRUE: inque[id_src1] && !busy[id_src1]));
assign id_src2_rdy = ((cdb_alu_valid && cdb_alu_src == id_src2)? `TRUE
    : ((cdb_ld_valid && cdb_ld_src == id_src2)? `TRUE: inque[id_src2] && !busy[id_src2]));
assign id_val1 = ((cdb_alu_valid && cdb_alu_src == id_src1)? cdb_alu_val
    : ((cdb_ld_valid && cdb_ld_src == id_src1)? cdb_ld_val: data[id_src1]));
assign id_val2 = ((cdb_alu_valid && cdb_alu_src == id_src2)? cdb_alu_val
    : ((cdb_ld_valid && cdb_ld_src == id_src2)? cdb_ld_val: data[id_src2]));

assign slb_st_rdy = inque[slb_st_idx] && !busy[slb_st_idx] && rob_head == slb_st_idx;

integer i, cnt = 0;

`ifdef DEBUG
assign head_rdy = inque[rob_head] && !busy[rob_head];
assign dbg_data = data['h1f];
assign dbg_src1_rdy = inque[rob_head] && !busy[6];
`endif

always @(posedge clk) begin
    reg_wr_ena <= `FALSE;
    bp_fb_ena <= `FALSE;
    rob_rb_ena <= `FALSE;
    lag_rob_siz <= rob_siz;
    rob_push_flag <= `FALSE;
    rob_pop_flag <= `FALSE;

    if (rst) begin
        rob_stat <= IDLE;
        mc_st_ena <= `FALSE;
        lag_rob_siz <= 0;
        rob_head <= 1;
        rob_tail <= 1;
        for (i = 0; i < ROB_SIZE; i++) begin
            busy [i] <= `FALSE;
            inque[i] <= `FALSE;
            opt  [i] <= `OPT_NONE;
`ifdef DEBUG
    inst[i] <= `ZERO_WORD;
`endif
            dest[i] <= `ZERO_REG_IDX;
            data[i] <= `ZERO_WORD;
            addr[i] <= `ZERO_ADDR;
            cur_pc[i] <= `ZERO_ADDR; 
            mis_pc[i] <= `ZERO_ADDR;
            pb_tk [i] <= `FALSE; 
            rl_tk [i] <= `FALSE;
        end
    end 
    else if (rob_rb_ena) begin
        lag_rob_siz <= 0;
        rob_head <= 1;
        rob_tail <= 1;
        for (i = 0; i < ROB_SIZE; i++) begin
            busy[i] = `FALSE;
            opt [i] = `OPT_NONE;
            dest[i] = `ZERO_REG_IDX;
            data[i] = `ZERO_WORD;
            addr[i] = `ZERO_ADDR;
            inque [i] = `FALSE;
            cur_pc[i] = `ZERO_ADDR; 
            mis_pc[i] = `ZERO_ADDR;
            pb_tk [i] = `FALSE; 
            rl_tk [i] = `FALSE;
        end
    end
    else if (!rdy || !rob_en || rob_st) begin
        // STALL
    end
    else begin
        // issue
        if (id_valid) begin
            busy[rob_tail] <= `TRUE;
            inque[rob_tail] <= `TRUE;
            opt[rob_tail] <= id_opt;
`ifdef DEBUG
            inst[rob_tail] <= id_inst;
`endif
            dest[rob_tail] <= id_dest;
            data[rob_tail] <= id_data;
            addr[rob_tail] <= id_addr;
            cur_pc[rob_tail] <= id_cur_pc;
            mis_pc[rob_tail] <= id_mis_pc;
            pb_tk [rob_tail] <= id_pb_tk;
            rl_tk [rob_tail] <= `FALSE;
            rob_tail <= ((rob_tail == ROB_SIZE-1)? 1: rob_tail + 1);
            rob_push_flag <= `TRUE;
        end
        // commit
        if (!rob_empty && !busy[rob_head]) begin
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
                    inque[rob_head] <= `FALSE;
                    rob_pop_flag <= `TRUE;
                    rob_head <= ((rob_head == ROB_SIZE-1)? 1: rob_head + 1);
`ifdef DEBUG
    cnt++;
    if (cnt >= `LOWER_BOUND && cnt < `UPPER_BOUND) begin
        $display("%d. inst = %h @%h", cnt, inst[rob_head], cur_pc[rob_head]);
        commit_cnt <= cnt;
        commit_inst <= inst[rob_head];
        if (rl_tk[rob_head] != pb_tk[rob_head]) begin
            // $display("idx = %h", rob_head);
            // $display("rollback, pb = %b, rl = %b, %h", pb_tk[rob_head], rl_tk[rob_head], mis_pc[rob_head]);
        end
    end
`endif
                end
                `OPT_SB, `OPT_SH, `OPT_SW: begin
                    // if (addr[rob_head][17:16] == 2'b11) begin
                    //     rob_pop_flag <= `TRUE;
                    //     rob_head <= ((rob_head == ROB_SIZE-1)? 1: rob_head + 1);    
                    // end
                    // else 
                    if (rob_stat == IDLE) begin
                        mc_st_ena <= `TRUE;
                        rob_stat <= STORING;
                        mc_st_addr <= addr[rob_head];
                        mc_st_data <= data[rob_head];
                        mc_st_len <= (opt[rob_head] == `OPT_SB? 0: (opt[rob_head] == `OPT_SH? 1: 3));
                        inque[rob_head] <= `FALSE;
                        rob_pop_flag <= `TRUE;
                        rob_head <= ((rob_head == ROB_SIZE-1)? 1: rob_head + 1);
`ifdef DEBUG
    cnt++;
    if (cnt >= `LOWER_BOUND && cnt < `UPPER_BOUND) begin 
        $display("%d. inst = %h @%h", cnt, inst[rob_head], cur_pc[rob_head]);
        commit_cnt <= cnt;
        commit_inst <= inst[rob_head];
    end
`endif
                    end
                end
                `OPT_JALR: begin
                    if (dest[rob_head] != 0) begin
                        reg_wr_ena <= `TRUE;
                        reg_wr_rd <= dest[rob_head];
                        reg_wr_val <= cur_pc[rob_head] + `NEXT_PC_INC;
                        reg_wr_idx <= rob_head; 
                    end
                    rob_rb_ena <= `TRUE;
                    if_rb_pc <= {data[rob_head][31:1], 1'b0}; 
                    inque[rob_head] <= `FALSE;
                    rob_pop_flag <= `TRUE;
                    rob_head <= ((rob_head == ROB_SIZE-1)? 1: rob_head + 1);
`ifdef DEBUG
    cnt++;
    if (cnt >= `LOWER_BOUND && cnt < `UPPER_BOUND) begin 
        $display("%d. inst = %h @%h", cnt, inst[rob_head], cur_pc[rob_head]);
        commit_cnt <= cnt;
        commit_inst <= inst[rob_head];
    end
`endif
                end
                default: begin
                    if (dest[rob_head] != 0) begin
                        reg_wr_ena <= `TRUE;
                        reg_wr_rd <= dest[rob_head];
                        reg_wr_val <= data[rob_head];
                        reg_wr_idx <= rob_head;
                    end
                    inque[rob_head] <= `FALSE;
                    rob_pop_flag <= `TRUE;
                    rob_head <= ((rob_head == ROB_SIZE-1)? 1: rob_head + 1);
`ifdef DEBUG
    cnt++;
    if (cnt >= `LOWER_BOUND && cnt < `UPPER_BOUND) begin
        // $display("reg = %h, val = %h", dest[rob_head], data[rob_head]);
        $display("%d. inst = %h @%h", cnt, inst[rob_head], cur_pc[rob_head]);
        commit_cnt <= cnt;
        commit_inst <= inst[rob_head];
    end
`endif
                end
            endcase
        end
        // update
        if (rob_stat == STORING && mc_st_done) begin
            rob_stat <= IDLE;
            mc_st_ena <= `FALSE;
        end
        if (cdb_alu_valid) begin
            data[cdb_alu_src] <= cdb_alu_val;
            rl_tk[cdb_alu_src] <= cdb_alu_tk;
            busy[cdb_alu_src] <= `FALSE;
`ifdef DEBUG
if (cnt < 300) begin
    // $display("upd from alu, %h %h", cdb_alu_src, cdb_alu_val);
end
`endif
        end
        if (cdb_ld_valid) begin
            data[cdb_ld_src] <= cdb_ld_val;
            busy[cdb_ld_src] <= `FALSE;
            // $display("upd from ld, %h", cdb_ld_src);
        end
        if (slb_valid) begin
            data[slb_src] <= slb_val;
            addr[slb_src] <= slb_addr;
            busy[slb_src] <= `FALSE;
            // $display("upd from slb, %h", slb_src);
        end
        
    end
end

endmodule

`endif 