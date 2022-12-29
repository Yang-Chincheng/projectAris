// RISCV32I CPU top module
// port modification allowed for debugging purposes

// `define DEBUG
`define ONLINE_JUDGE
`define LOWER_BOUND 1500 // 5000
`define UPPER_BOUND 2000 // 6000
`define PRINT_BASE 10000

`include "utils.v"
`include "fetch/fetcher.v"
`include "fetch/predictor.v"
`include "decode/decoder.v"
`include "decode/dispatcher.v"
`include "execute/alu.v"
`include "execute/regfile.v"
`include "execute/rs.v"
`include "execute/slb.v"
`include "commit/rob.v"
`include "memory/icache.v"
`include "memory/dcache.v"
`include "memory/memctrl.v"


module cpu (
           input  wire                 clk_in,			// system clock signal
           input  wire                 rst_in,			// reset signal
           input  wire				   rdy_in,			// ready signal, pause cpu when low

           input  wire [ 7:0]          mem_din,		    // data input bus
           output wire [ 7:0]          mem_dout,		// data output bus
           output wire [31:0]          mem_a,			// address bus (only 17:0 is used)
           output wire                 mem_wr,			// write/read signal (1 for write)

           input  wire                 io_buffer_full,  // 1 if uart buffer is full

           output wire [31:0]		   dbgreg_dout		// cpu register output (debugging demo)
       );

// implementation goes here

// Specifications:
// - Pause cpu(freeze pc, registers, etc.) when rdy_in is low
// - Memory read result will be returned in the next cycle. Write takes 1 cycle(no need to wait)
// - Memory is of size 128KB, with valid address ranging from 0x0 to 0x20000
// - I/O port is mapped to address higher than 0x30000 (mem_a[17:16]==2'b11)
// - 0x30000 read: read a byte from input
// - 0x30000 write: write a byte to output (write 0x00 is ignored)
// - 0x30004 read: read clocks passed since cpu starts (in dword, 4 bytes)
// - 0x30004 write: indicates program stop (will output '\0' through uart tx)

// always @(posedge clk_in) begin
//     if (io_buffer_full) begin
//         $display("nope");
//     end
// end

wire cpu_rb_signal;
wire cdb_alu_tk;
wire cdb_alu_valid;
wire [`ROB_IDX_TP] cdb_alu_src;
wire [`WORD_TP] cdb_alu_val;
wire cdb_ld_valid;
wire [`ROB_IDX_TP] cdb_ld_src;
wire [`WORD_TP] cdb_ld_val;

wire id_to_if_full;
wire [`ADDR_TP] rob_to_if_rb_pc;

wire [`ADDR_TP] if_to_icache_rd_addr;
wire if_to_icache_rd_ena;
wire icache_to_if_hit;
wire [`WORD_TP] icache_to_if_inst;

wire [`ADDR_TP] if_to_bp_pc;
wire [`WORD_TP] if_to_bp_inst;
wire bp_to_if_tk;
wire [`ADDR_TP] bp_to_if_off;

wire if_to_id_ena;
wire [`WORD_TP] if_to_id_inst;
wire [`ADDR_TP] if_to_id_cur_pc;
wire [`ADDR_TP] if_to_id_mis_pc;
wire if_to_id_tk;

fetcher cpu_fetcher(
    .clk(clk_in),
    .rst(rst_in),
    .rdy(rdy_in),

    .if_en(`TRUE),
    .if_st(id_to_if_full),
    .if_rb(cpu_rb_signal),

    .cache_rd_en(if_to_icache_rd_ena),
    .cache_rd_addr(if_to_icache_rd_addr),
    .cache_hit(icache_to_if_hit),
    .cache_hit_inst(icache_to_if_inst),

    .bp_pb_pc(if_to_bp_pc),
    .bp_pb_inst(if_to_bp_inst),
    .bp_pd_tk(bp_to_if_tk),
    .bp_pd_off(bp_to_if_off),

    .id_ena(if_to_id_ena),
    .id_inst(if_to_id_inst),
    .id_cur_pc(if_to_id_cur_pc),
    .id_mis_pc(if_to_id_mis_pc),
    .id_pd_tk(if_to_id_tk),

    .rob_rb_pc(rob_to_if_rb_pc)
);

wire rob_to_bp_fb_ena;
wire rob_to_bp_fb_tk;
wire [`WORD_TP] rob_to_bp_fb_pc;

predictor cpu_predictor(
    .clk(clk_in),
    .rst(rst_in),
    .rdy(rdy_in),

    .pd_pc(if_to_bp_pc),
    .pd_inst(if_to_bp_inst),
    
    .pd_tk(bp_to_if_tk),
    .pd_off(bp_to_if_off),

    .fb_ena(rob_to_bp_fb_ena),
    .fb_tk(rob_to_bp_fb_tk),
    .fb_pc(rob_to_bp_fb_pc)
);

wire [`WORD_TP] id_to_dec_inst;
wire [`INST_TY_TP] dec_to_id_ty;
wire [`INST_OPT_TP] dec_to_id_opt;
wire [`REG_IDX_TP] dec_to_id_rd;
wire [`REG_IDX_TP] dec_to_id_rs1;
wire [`REG_IDX_TP] dec_to_id_rs2;
wire [`WORD_TP] dec_to_id_imm;
wire dec_to_id_isls;

wire [`REG_IDX_TP] id_to_reg_rs1;
wire [`REG_IDX_TP] id_to_reg_rs2;
wire [`ROB_IDX_TP] reg_to_id_src1;
wire [`ROB_IDX_TP] reg_to_id_src2;
wire [`WORD_TP] reg_to_id_val1;
wire [`WORD_TP] reg_to_id_val2;

wire id_to_reg_rn_ena;
wire [`REG_IDX_TP] id_to_reg_rn_rd;
wire [`ROB_IDX_TP] id_to_reg_rn_idx;

wire rs_to_id_full;
wire id_to_rs_ena;
wire [`INST_OPT_TP] id_to_rs_opt;
wire [`ROB_IDX_TP] id_to_rs_src1;
wire [`ROB_IDX_TP] id_to_rs_src2;
wire [`WORD_TP] id_to_rs_val1;
wire [`WORD_TP] id_to_rs_val2;
wire [`WORD_TP] id_to_rs_imm;
wire [`ROB_IDX_TP] id_to_rs_rob_idx;

wire slb_to_id_full;
wire id_to_slb_ena;
wire [`INST_OPT_TP] id_to_slb_opt;
wire [`ROB_IDX_TP] id_to_slb_src1;
wire [`ROB_IDX_TP] id_to_slb_src2;
wire [`WORD_TP] id_to_slb_val1;
wire [`WORD_TP] id_to_slb_val2;
wire [`WORD_TP] id_to_slb_imm;
wire [`ROB_IDX_TP] id_to_slb_rob_idx;
wire id_to_slb_isld;

wire rob_to_id_full;
wire [`ROB_IDX_TP] rob_to_id_idx;

wire [`ROB_IDX_TP] id_to_rob_src1;
wire [`ROB_IDX_TP] id_to_rob_src2;
wire rob_to_id_src1_rdy;
wire rob_to_id_src2_rdy;
wire [`WORD_TP] rob_to_id_val1;
wire [`WORD_TP] rob_to_id_val2;

wire id_to_rob_ena;
wire [`INST_OPT_TP] id_to_rob_opt;
wire [`REG_IDX_TP] id_to_rob_dest;
wire [`WORD_TP] id_to_rob_data;
wire [`ADDR_TP] id_to_rob_addr;
wire [`ADDR_TP] id_to_rob_cur_pc;
wire [`ADDR_TP] id_to_rob_mis_pc;
wire id_to_rob_pb_tk_stat;

`ifdef DEBUG
wire [`WORD_TP] id_to_rob_inst, id_to_rs_inst, id_to_slb_inst;
`endif

dispatcher cpu_dispatcher(
    .clk(clk_in), // system clock
    .rst(rst_in), // reset signal
    .rdy(rdy_in),

    .id_en(`TRUE), // inst decode unit enabling signal
    .id_st(`FALSE), // inst decode unit stall signal
    .id_rb(cpu_rb_signal), // inst decode unit rollback signal
    .id_full(id_to_if_full),

    // ifu
    .if_valid(if_to_id_ena),
    .if_inst(if_to_id_inst), // inst from ifu
    .if_cur_pc(if_to_id_cur_pc), // pc from ifu
    .if_mis_pc(if_to_id_mis_pc), // rollback target from ifu
    .if_pb_tk_stat(if_to_id_tk), // predict taken status from ifu

    // dec
    .dec_inst(id_to_dec_inst),
    .dec_ty(dec_to_id_ty),
    .dec_opt(dec_to_id_opt),
    .dec_rd(dec_to_id_rd),
    .dec_rs1(dec_to_id_rs1),
    .dec_rs2(dec_to_id_rs2),
    .dec_imm(dec_to_id_imm),
    .dec_is_ls(dec_to_id_isls),

    // reg
    .reg_rs1(id_to_reg_rs1),
    .reg_rs2(id_to_reg_rs2),
    .reg_src1(reg_to_id_src1),
    .reg_src2(reg_to_id_src2),
    .reg_val1(reg_to_id_val1),
    .reg_val2(reg_to_id_val2),
    
    .reg_rn_ena(id_to_reg_rn_ena),
    .reg_rn_rd(id_to_reg_rn_rd),
    .reg_rn_idx(id_to_reg_rn_idx),
    
    // rs
`ifdef DEBUG
    .rs_inst(id_to_rs_inst),
    .slb_inst(id_to_slb_inst),
`endif
    .rs_full(rs_to_id_full),
    .rs_ena(id_to_rs_ena),
    .rs_opt(id_to_rs_opt),
    .rs_src1(id_to_rs_src1),
    .rs_src2(id_to_rs_src2),
    .rs_val1(id_to_rs_val1),
    .rs_val2(id_to_rs_val2),
    .rs_imm(id_to_rs_imm),  
    .rs_rob_idx(id_to_rs_rob_idx),

    // slb
    .slb_full(slb_to_id_full),
    .slb_ena(id_to_slb_ena),
    .slb_opt(id_to_slb_opt),
    .slb_src1(id_to_slb_src1),
    .slb_src2(id_to_slb_src2),
    .slb_val1(id_to_slb_val1),
    .slb_val2(id_to_slb_val2),
    .slb_imm(id_to_slb_imm), 
    .slb_rob_idx(id_to_slb_rob_idx),
    .slb_isld(id_to_slb_isld),

    // rob
`ifdef DEBUG
    .rob_inst(id_to_rob_inst),
`endif
    .rob_full(rob_to_id_full),
    .rob_idx(rob_to_id_idx),
    .rob_src1(id_to_rob_src1),
    .rob_src2(id_to_rob_src2),
    .rob_src1_rdy(rob_to_id_src1_rdy),
    .rob_src2_rdy(rob_to_id_src2_rdy),
    .rob_val1(rob_to_id_val1),
    .rob_val2(rob_to_id_val2),
    .rob_ena(id_to_rob_ena),
    .rob_opt(id_to_rob_opt),
    .rob_dest(id_to_rob_dest),
    .rob_data(id_to_rob_data),
    .rob_addr(id_to_rob_addr),
    .rob_cur_pc(id_to_rob_cur_pc),
    .rob_mis_pc(id_to_rob_mis_pc),
    .rob_pb_tk_stat(id_to_rob_pb_tk_stat),

    // cdb
    .cdb_alu_valid(cdb_alu_valid),
    .cdb_alu_src(cdb_alu_src),
    .cdb_alu_val(cdb_alu_val),
    .cdb_ld_valid(cdb_ld_valid),
    .cdb_ld_src(cdb_ld_src),
    .cdb_ld_val(cdb_ld_val)
);

decoder cpu_decoder(
    .inst(id_to_dec_inst),
    .ty(dec_to_id_ty),
    .opt(dec_to_id_opt),
    .rd(dec_to_id_rd),
    .rs1(dec_to_id_rs1),
    .rs2(dec_to_id_rs2),
    .imm(dec_to_id_imm),
    .is_ls(dec_to_id_isls)
);

wire rs_to_alu_ena;
wire [`INST_OPT_TP] rs_to_alu_opt;
wire [`WORD_TP] rs_to_alu_val1;
wire [`WORD_TP] rs_to_alu_val2;
wire [`WORD_TP] rs_to_alu_imm;
wire [`ROB_IDX_TP] rs_to_alu_rob_idx;

`ifdef DEBUG
wire [`WORD_TP] rs_to_alu_inst;
`endif

RS cpu_rs(
    .clk(clk_in),
    .rst(rst_in),
    .rdy(rdy_in),

    .rs_en(`TRUE),
    .rs_st(`FALSE),
    .rs_rb(cpu_rb_signal),
    .rs_empty(),
    .rs_full(rs_to_id_full),

    // idu 
`ifdef DEBUG
    .id_inst(id_to_rs_inst),
`endif 
    .id_valid(id_to_rs_ena), 
    .id_opt(id_to_rs_opt),
    .id_src1(id_to_rs_src1),
    .id_src2(id_to_rs_src2),
    .id_val1(id_to_rs_val1),
    .id_val2(id_to_rs_val2),
    .id_imm(id_to_rs_imm),  
    .id_rob_idx(id_to_rs_rob_idx),

    // alu
`ifdef DEBUG
    .alu_inst(rs_to_alu_inst),
`endif
    .alu_ena(rs_to_alu_ena),
    .alu_opt(rs_to_alu_opt),
    .alu_val1(rs_to_alu_val1),
    .alu_val2(rs_to_alu_val2),
    .alu_imm(rs_to_alu_imm),
    .alu_rob_idx(rs_to_alu_rob_idx),

    // cdb
    .cdb_alu_valid(cdb_alu_valid),
    .cdb_alu_src(cdb_alu_src),
    .cdb_alu_val(cdb_alu_val),
    .cdb_ld_valid(cdb_ld_valid),
    .cdb_ld_src(cdb_ld_src),
    .cdb_ld_val(cdb_ld_val)
);

wire [`ROB_IDX_TP] slb_to_rob_st_idx;
wire slb_to_rob_st_rdy;
wire rob_to_slb_commit_rdy;

wire slb_to_mc_ld_ena;
wire [`ADDR_TP] slb_to_mc_ld_addr;
wire [3:0] slb_to_mc_ld_len;
wire slb_to_mc_ld_sext;
wire [`ROB_IDX_TP] slb_to_mc_ld_src;
wire mc_to_slb_ld_done;
wire [`WORD_TP] mc_to_slb_ld_data;

wire slb_to_mc_st_ena;
wire [`ADDR_TP] slb_to_mc_st_addr;
wire [3:0] slb_to_mc_st_len;
wire [`WORD_TP] slb_to_mc_st_data;
wire mc_to_slb_st_done; 

SLB cpu_slb(
    .clk(clk_in),
    .rst(rst_in),
    .rdy(rdy_in),

    .slb_en(`TRUE),
    .slb_st(`FALSE),
    .slb_rb(cpu_rb_signal),
    .slb_full(slb_to_id_full),
    .slb_empty(),

    // idu
`ifdef DEBUG
    .id_inst(id_to_slb_inst),
`endif
    .id_valid(id_to_slb_ena),
    .id_opt(id_to_slb_opt),
    .id_src1(id_to_slb_src1),
    .id_src2(id_to_slb_src2),
    .id_val1(id_to_slb_val1),
    .id_val2(id_to_slb_val2),
    .id_imm(id_to_slb_imm),
    .id_rob_idx(id_to_slb_rob_idx),

    // memctrl
    .mc_ld_ena(slb_to_mc_ld_ena),
    .mc_ld_addr(slb_to_mc_ld_addr),
    .mc_ld_len(slb_to_mc_ld_len),
    .mc_ld_sext(slb_to_mc_ld_sext),
    .mc_ld_src(slb_to_mc_ld_src),
    .mc_ld_done(mc_to_slb_ld_done),
    .mc_ld_data(mc_to_slb_ld_data),

    .mc_st_ena(slb_to_mc_st_ena),
    .mc_st_addr(slb_to_mc_st_addr),
    .mc_st_data(slb_to_mc_st_data),
    .mc_st_len(slb_to_mc_st_len),
    .mc_st_done(mc_to_slb_st_done),

    // cdb
    .cdb_alu_valid(cdb_alu_valid),
    .cdb_alu_src(cdb_alu_src),
    .cdb_alu_val(cdb_alu_val),
    .cdb_ld_valid(cdb_ld_valid),
    .cdb_ld_src(cdb_ld_src),
    .cdb_ld_val(cdb_ld_val),

    // rob
    .rob_st_idx(slb_to_rob_st_idx),
    .rob_st_rdy(slb_to_rob_st_rdy),
    .rob_commit_rdy(rob_to_slb_commit_rdy)
);

wire [`ROB_IDX_TP] id_src1;
wire [`ROB_IDX_TP] id_src2;
wire [`WORD_TP] id_val1;
wire [`WORD_TP] id_val2;

wire rob_to_reg_wr_ena;
wire [`REG_IDX_TP] rob_to_reg_wr_rd;
wire [`WORD_TP] rob_to_reg_wr_val;
wire [`ROB_IDX_TP] rob_to_reg_wr_idx;

regfile cpu_regfile(
    .clk(clk_in),
    .rst(rst_in),
    .rdy(rdy_in),

    .reg_en(`TRUE),
    .reg_st(`FALSE),
    .reg_rb(cpu_rb_signal),

    // idu
    .id_rs1(id_to_reg_rs1),
    .id_rs2(id_to_reg_rs2),
    .id_src1(reg_to_id_src1),
    .id_src2(reg_to_id_src2),
    .id_val1(reg_to_id_val1),
    .id_val2(reg_to_id_val2),

`ifdef DEBUG
    .dbg_val(),
    .dbg_src(),
`endif
    
    .id_rn_ena(id_to_reg_rn_ena),
    .id_rn_rd(id_to_reg_rn_rd),
    .id_rn_idx(id_to_reg_rn_idx),

    // rob
    .rob_wr_ena(rob_to_reg_wr_ena),
    .rob_wr_rd(rob_to_reg_wr_rd),
    .rob_wr_val(rob_to_reg_wr_val),
    .rob_wr_idx(rob_to_reg_wr_idx)
);

ALU cpu_alu(
    .clk(clk_in),
    .rst(rst_in),
    .rdy(rdy_in),

    .alu_en(`TRUE),
    .alu_st(`FALSE),
    
    // rs
`ifdef DEBUG
    .rs_inst(rs_to_alu_inst),
`endif 
    .rs_valid(rs_to_alu_ena),
    .rs_opt(rs_to_alu_opt),
    .rs_val1(rs_to_alu_val1),
    .rs_val2(rs_to_alu_val2),
    .rs_imm(rs_to_alu_imm),
    .rs_rob_idx(rs_to_alu_rob_idx),

    // cdb 
    .cdb_alu_valid(cdb_alu_valid),
    .cdb_alu_src(cdb_alu_src),
    .cdb_alu_val(cdb_alu_val),
    .cdb_alu_tk(cdb_alu_tk)
);

ROB cpu_rob(
    .clk(clk_in),
    .rst(rst_in),
    .rdy(rdy_in),

    .rob_en(`TRUE),
    .rob_st(`FALSE),
    .rob_empty(),
    .rob_full(rob_to_id_full),
    .rob_idx(rob_to_id_idx),
    .rob_rb_ena(cpu_rb_signal),

    // if
    .if_rb_pc(rob_to_if_rb_pc),

    // id
    .id_src1(id_to_rob_src1),
    .id_src2(id_to_rob_src2),
    .id_src1_rdy(rob_to_id_src1_rdy),
    .id_src2_rdy(rob_to_id_src2_rdy),
    .id_val1(rob_to_id_val1),
    .id_val2(rob_to_id_val2),
    
`ifdef DEBUG
    .id_inst(id_to_rob_inst),
    .head_rdy(),
    .commit_cnt(),
    .commit_inst(),
    .commit_print_cnt(),
`endif
    .id_valid(id_to_rob_ena),
    .id_opt(id_to_rob_opt),
    .id_dest(id_to_rob_dest),
    .id_data(id_to_rob_data),
    .id_addr(id_to_rob_addr),
    .id_cur_pc(id_to_rob_cur_pc),
    .id_mis_pc(id_to_rob_mis_pc),
    .id_pb_tk(id_to_rob_pb_tk_stat),

    // reg
    .reg_wr_ena(rob_to_reg_wr_ena),
    .reg_wr_rd(rob_to_reg_wr_rd),
    .reg_wr_val(rob_to_reg_wr_val),
    .reg_wr_idx(rob_to_reg_wr_idx),
    
    // slb
    .slb_st_idx(slb_to_rob_st_idx),
    .slb_st_rdy(slb_to_rob_st_rdy),
    .slb_commit_rdy(rob_to_slb_commit_rdy),

    // cdb
    .cdb_alu_valid(cdb_alu_valid),
    .cdb_alu_tk(cdb_alu_tk),
    .cdb_alu_src(cdb_alu_src),
    .cdb_alu_val(cdb_alu_val),
    .cdb_ld_valid(cdb_ld_valid),
    .cdb_ld_src(cdb_ld_src),
    .cdb_ld_val(cdb_ld_val),

    // bp
    .bp_fb_ena(rob_to_bp_fb_ena),
    .bp_fb_tk(rob_to_bp_fb_tk),
    .bp_fb_pc(rob_to_bp_fb_pc)
);

wire icache_to_mc_ena;
wire [`ADDR_TP] icache_to_mc_fc_addr;
wire mc_to_icache_fc_done;
wire [`LINE_TP] mc_to_icache_fc_line;

icache cpu_icache(
    .clk(clk_in),
    .rst(rst_in),
    .rdy(rdy_in),

    .cache_en(`TRUE),
    .cache_st(`FALSE),
    .cache_rb(cpu_rb_signal),

    .if_addr(if_to_icache_rd_addr),
    .if_cache_hit(icache_to_if_hit),
    .if_hit_word(icache_to_if_inst),

    .mc_fc_ena(icache_to_mc_ena),
    .mc_fc_addr(icache_to_mc_fc_addr),
    .mc_fc_done(mc_to_icache_fc_done),
    .mc_fc_line(mc_to_icache_fc_line)
);

memctrl cpu_memctrl(
    .clk(clk_in),
    .rst(rst_in),
    .rdy(rdy_in),

    .mc_en(`TRUE),
    .mc_st(`FALSE),
    .mc_rb(cpu_rb_signal),

    // icache
    .icache_fc_valid(icache_to_mc_ena),
    .icache_fc_addr(icache_to_mc_fc_addr),
    .icache_fc_done(mc_to_icache_fc_done),
    .icache_fc_line(mc_to_icache_fc_line),

    // slb
    .slb_ld_valid(slb_to_mc_ld_ena),
    .slb_ld_addr(slb_to_mc_ld_addr),
    .slb_ld_len(slb_to_mc_ld_len),
    .slb_ld_sext(slb_to_mc_ld_sext),
    .slb_ld_src(slb_to_mc_ld_src),
    .slb_ld_done(mc_to_slb_ld_done),
    .slb_ld_data(mc_to_slb_ld_data),

    .slb_st_valid(slb_to_mc_st_ena),
    .slb_st_addr(slb_to_mc_st_addr),
    .slb_st_data(slb_to_mc_st_data),
    .slb_st_len(slb_to_mc_st_len),
    .slb_st_done(mc_to_slb_st_done),

    // cdb
    .cdb_ld_ena(cdb_ld_valid),
    .cdb_ld_src(cdb_ld_src),
    .cdb_ld_val(cdb_ld_val),
    
    // ram
    .ram_rw_sel(mem_wr),
    .ram_addr(mem_a),
    .ram_wr_byte(mem_dout),
    .ram_rd_byte(mem_din)
);

always @(posedge clk_in) begin
    if (rst_in) begin

    end
    else if (!rdy_in) begin

    end
    else begin

    end
end

endmodule
