`ifndef ROB_V_ 
`define ROB_V_

`ifdef ONLINE_JUDGE
    `include "utils.v"
`else
`ifdef FPGA_TEST
    `include "utils.v"
`else 
    `include "/home/Modem514/projectAris/riscv/src/utils.v"
`endif
`endif

`define ROB_BIT `ROB_IDX_LN
`define ROB_SIZE (1 << `ROB_BIT)

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
    input wire [`ROB_IDX_TP] slb_ld_idx,
    input wire [`ROB_IDX_TP] slb_st_idx,
    input wire slb_st_exec_rdy,
    output wire slb_ld_commit_rdy,
    output wire slb_st_commit_rdy,

    // cdb
    input wire cdb_alu_valid,
    input wire cdb_alu_tk,
    input wire [`ROB_IDX_TP] cdb_alu_src,
    input wire [`WORD_TP] cdb_alu_val,
    input wire cdb_ld_valid,
    input wire [`ROB_IDX_TP] cdb_ld_src,
    input wire [`WORD_TP] cdb_ld_val,

`ifdef DEBUG
    output wire head_rdy,
    output reg [31:0] commit_cnt,
    output reg [31:0] commit_inst,
    output reg [31:0] commit_print_cnt,
    output wire [`WORD_TP] dbg_data,
    output wire dbg_src1_rdy,
    output wire [`WORD_TP] dbg_inst,
`endif

    // bp
    output reg bp_fb_ena,
    output reg bp_fb_tk,
    output reg [`ADDR_TP] bp_fb_pc

);

reg [ROB_BIT-1:0] q_rob_siz;
reg rob_push_flag, rob_pop_flag;
wire [ROB_BIT-1:0] d_rob_siz = q_rob_siz + (rob_push_flag? 1: 0) + (rob_pop_flag? -1: 0);
assign rob_full = (d_rob_siz >= ROB_SIZE - 5);
assign rob_empty = (d_rob_siz == 0);
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
reg [`ADDR_TP]     cur_pc [ROB_SIZE-1:0];
reg [`ADDR_TP]     mis_pc [ROB_SIZE-1:0];
reg                pb_tk  [ROB_SIZE-1:0];
reg                rl_tk  [ROB_SIZE-1:0];

assign rob_idx = (id_valid? (rob_tail == ROB_SIZE-1? 1: rob_tail + 1): rob_tail); 

assign id_src1_rdy = ((cdb_alu_valid && cdb_alu_src == id_src1)? `TRUE
    : ((cdb_ld_valid && cdb_ld_src == id_src1)? `TRUE: inque[id_src1] && !busy[id_src1]));
assign id_src2_rdy = ((cdb_alu_valid && cdb_alu_src == id_src2)? `TRUE
    : ((cdb_ld_valid && cdb_ld_src == id_src2)? `TRUE: inque[id_src2] && !busy[id_src2]));
assign id_val1 = ((cdb_alu_valid && cdb_alu_src == id_src1)? cdb_alu_val
    : ((cdb_ld_valid && cdb_ld_src == id_src1)? cdb_ld_val: data[id_src1]));
assign id_val2 = ((cdb_alu_valid && cdb_alu_src == id_src2)? cdb_alu_val
    : ((cdb_ld_valid && cdb_ld_src == id_src2)? cdb_ld_val: data[id_src2]));

assign slb_ld_commit_rdy = inque[slb_ld_idx] && rob_head == slb_ld_idx;
assign slb_st_commit_rdy = inque[slb_st_idx] && rob_head == slb_st_idx;

integer i;
integer cnt = 0; 

`ifdef DEBUG
assign head_rdy = inque[rob_head] && !busy[rob_head];
assign dbg_data = data['h1f];
assign dbg_src1_rdy = inque[rob_head] && !busy[6];
`endif

always @(posedge clk) begin
    reg_wr_ena <= `FALSE;
    bp_fb_ena <= `FALSE;
    rob_rb_ena <= `FALSE;
    q_rob_siz <= d_rob_siz;
    rob_push_flag <= `FALSE;
    rob_pop_flag <= `FALSE;

    if (rst) begin
        q_rob_siz <= 0;
        rob_head <= 1;
        rob_tail <= 1;
        for (i = 0; i < ROB_SIZE; i = i + 1) begin
            busy [i] <= `FALSE;
            inque[i] <= `FALSE;
            opt  [i] <= `OPT_NONE;
`ifdef DEBUG
    inst[i] <= `ZERO_WORD;
`endif
            dest[i] <= `ZERO_REG_IDX;
            data[i] <= `ZERO_WORD;
            cur_pc[i] <= `ZERO_ADDR; 
            mis_pc[i] <= `ZERO_ADDR;
            pb_tk [i] <= `FALSE; 
            rl_tk [i] <= `FALSE;
        end
    end 
    else if (rob_rb_ena) begin
        q_rob_siz <= 0;
        rob_head <= 1;
        rob_tail <= 1;
        for (i = 0; i < ROB_SIZE; i = i + 1) begin
            busy[i] = `FALSE;
            opt [i] = `OPT_NONE;
            dest[i] = `ZERO_REG_IDX;
            data[i] = `ZERO_WORD;
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
            cur_pc[rob_tail] <= id_cur_pc;
            mis_pc[rob_tail] <= id_mis_pc;
            pb_tk [rob_tail] <= id_pb_tk;
            rl_tk [rob_tail] <= `FALSE;
            rob_tail <= ((rob_tail == ROB_SIZE-1)? 1: rob_tail + 1);
            rob_push_flag <= `TRUE;
        end
        // commit
        if (!rob_empty) begin
            case (opt[rob_head])
                // branch
                `OPT_BEQ, `OPT_BNE, `OPT_BLT, `OPT_BGE, `OPT_BLTU, `OPT_BGEU: begin
                    if (!busy[rob_head]) begin 
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
    cnt = cnt + 1;
    if (cnt >= `LOWER_BOUND && cnt < `UPPER_BOUND) begin
        $display("%d. inst = %h @%h", cnt, inst[rob_head], cur_pc[rob_head]);
    end
    commit_cnt <= cnt;
    commit_inst <= inst[rob_head];
`endif
                    end
                end
                `OPT_SB, `OPT_SH, `OPT_SW: begin
                    if (slb_st_exec_rdy) begin
                        inque[rob_head] <= `FALSE;
                        rob_pop_flag <= `TRUE;
                        rob_head <= ((rob_head == ROB_SIZE-1)? 1: rob_head + 1);
`ifdef DEBUG
    cnt = cnt + 1;
    if (cnt >= `LOWER_BOUND && cnt < `UPPER_BOUND) begin 
        $display("%d. inst = %h @%h", cnt, inst[rob_head], cur_pc[rob_head]);
    end
    commit_cnt <= cnt;
    commit_inst <= inst[rob_head];
`endif
                    end
                end
                `OPT_JALR: begin
                    if (!busy[rob_head]) begin
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
    cnt = cnt + 1;
    if (cnt >= `LOWER_BOUND && cnt < `UPPER_BOUND) begin 
        $display("%d. inst = %h @%h", cnt, inst[rob_head], cur_pc[rob_head]);
    end
    commit_cnt <= cnt;
    commit_inst <= inst[rob_head];
`endif
                    end
                end
                default: begin
                    if (!busy[rob_head]) begin
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
    cnt = cnt + 1;
    if (cnt >= `LOWER_BOUND && cnt < `UPPER_BOUND) begin
        $display("%d. inst = %h @%h", cnt, inst[rob_head], cur_pc[rob_head]);
    end
    commit_cnt <= cnt;
    commit_inst <= inst[rob_head];
`endif
                    end
                end
            endcase
        end
        // update
        if (cdb_alu_valid) begin
            data[cdb_alu_src] <= cdb_alu_val;
            rl_tk[cdb_alu_src] <= cdb_alu_tk;
            busy[cdb_alu_src] <= `FALSE;
        end
        if (cdb_ld_valid) begin
            data[cdb_ld_src] <= cdb_ld_val;
            busy[cdb_ld_src] <= `FALSE;
        end
    end
end

endmodule

`endif 