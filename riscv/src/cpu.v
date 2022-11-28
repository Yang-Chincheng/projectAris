// RISCV32I CPU top module
// port modification allowed for debugging purposes
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

wire icache_rd_en;
wire [`ADDR_TP] icache_rd_addr;
wire bp_ena;
wire [`ADDR_TP] bp_pb_pc;
wire [`WORD_TP] bp_pb_inst;
wire id_ena; // inst decode unit enable signal
wire [`WORD_TP] id_inst; // inst sent to idu
wire [`ADDR_TP] id_cur_pc; // pc sent to idu
wire [`ADDR_TP] id_mis_pc; // rollback pc target when mispredicted
wire id_pd_tk; // reserved predict result for feedback

fetcher cpu_fetcher(
    .clk(clk_in),
    .rst(rst_in),
    .rdy(rdy_in),

    .if_en(`TRUE),
    .if_st(rob_full || slb_full || rs_full),
    .if_rb(rob_rb_ena),

    .cache_rd_en(icache_rd_en),
    .cache_rd_addr(icache_rd_addr),
    .cache_hit(if_cache_hit),
    .cache_hit_inst(if_hit_word),

    .bp_ena(bp_ena),
    .bp_pd_pc(bp_pb_pc),
    .bp_pb_inst(bp_pb_inst),
    .bp_pd_tk(pb_tk),
    .bp_pd_off(pd_off),

    .id_ena(id_ena),
    .id_inst(id_inst),
    .id_cur_pc(id_cur_pc),
    .id_mis_pc(id_mis_pc),
    .id_pd_tk(id_pd_tk),

    .rob_rb_pc(if_rb_pc)
);

wire pd_tk;
wire [`WORD_TP] pd_off;

predictor cpu_predictor(
    .clk(clk_in),
    .rst(rst_in),

    .pd_valid(bp_ena),
    .pd_pc(bp_pb_pc),
    .pd_inst(bp_pb_inst),
    
    .pd_tk(pd_tk),
    .pd_off(pd_off),

    .fb_ena(bp_fb_ena),
    .fb_tk(bp_fb_tk),
    .fb_pc(bp_fb_pc)
);

wire [`WORD_TP] dec_inst;
wire [`REG_IDX_TP] reg_rs1;
wire [`REG_IDX_TP] reg_rs2;
wire reg_rn_ena;
wire [`REG_IDX_TP] reg_rn_rd;
wire [`ROB_IDX_TP] reg_rn_idx;
wire rs_ena;
wire [`INST_OPT_TP] rs_opt;
wire [`ROB_IDX_TP] rs_src1;
wire [`ROB_IDX_TP] rs_src2;
wire [`WORD_TP] rs_val1;
wire [`WORD_TP] rs_val2;
wire [`WORD_TP] rs_imm;
wire [`ROB_IDX_TP] rs_rob_idx;
wire lsb_ena;
wire [`INST_OPT_TP] lsb_opt;
wire [`ROB_IDX_TP] lsb_src1;
wire [`ROB_IDX_TP] lsb_src2;
wire [`WORD_TP] lsb_val1;
wire [`WORD_TP] lsb_val2;
wire [`WORD_TP] lsb_imm;
wire [`ROB_IDX_TP] rob_src1;
wire [`ROB_IDX_TP] rob_src2;
wire rob_ena;
wire [`INST_OPT_TP] rob_opt;
wire [`REG_IDX_TP] rob_dest;
wire [`WORD_TP] rob_data;
wire [`ADDR_TP] rob_addr;
wire [`ADDR_TP] rob_cur_pc;
wire [`ADDR_TP] rob_mis_pc;
wire rob_pb_tk_stat;

dispatcher cpu_dispatcher(
    .clk(clk_in), // system clock
    .rst(rst_in), // reset signal
    .rdy(rdy_in),

    .id_en(`TRUE), // inst decode unit enabling signal
    .id_st(`FALSE), // inst decode unit stall signal
    .id_rb(rob_rb_ena), // inst decode unit rollback signal

    // ifu
    .if_inst(id_inst), // inst from ifu
    .if_cur_pc(id_cur_pc), // pc from ifu
    .if_mis_pc(id_mis_pc), // rollback target from ifu
    .if_pb_tk_stat(id_pb_tk), // predict taken status from ifu

    // dec
    .dec_inst(dec_inst),
    .dec_ty(dec_ty),
    .dec_opt(dec_opt),
    .dec_rd(dec_rd),
    .dec_rs1(dec_rs1),
    .dec_rs2(dec_rs2),
    .dec_imm(dec_imm),
    .dec_is_ls(),

    // reg
    .reg_rs1(reg_rs1),
    .reg_rs2(reg_rs2),
    .reg_src1(id_src1),
    .reg_src2(id_src2),
    .reg_val1(id_val1),
    .reg_val2(id_val2),
    
    .reg_rn_ena(reg_rn_ena),
    .reg_rn_rd(reg_rn_rd),
    .reg_rn_idx(reg_rn_idx),
    
    // rs
    .rs_full(rs_full),
    .rs_ena(rs_ena),
    .rs_opt(rs_opt),
    .rs_src1(rs_src1),
    .rs_src2(rs_src2),
    .rs_val1(rs_val1),
    .rs_val2(rs_val2),
    .rs_imm(rs_imm),  
    .rs_rob_idx(rs_rob_idx),

    // lsb
    .lsb_full(lsb_full),
    .lsb_ena(lsb_ena),
    .lsb_opt(lsb_opt),
    .lsb_src1(lsb_src1),
    .lsb_src2(lsb_src2),
    .lsb_val1(lsb_val1),
    .lsb_val2(lsb_val2),
    .lsb_imm(lsb_imm), 
    .lsb_rob_idx(lsb_rob_idx),

    // rob
    .rob_full(rob_full),
    .rob_idx(rob_idx),
    .rob_src1(rob_src1),
    .rob_src2(rob_src2),
    .rob_src1_rdy(id_src1_rdy),
    .rob_src2_rdy(id_src2_rdy),
    .rob_val1(id_val1),
    .rob_val2(id_val2),
    .rob_ena(rob_ena),
    .rob_opt(rob_opt),
    .rob_dest(rob_dest),
    .rob_data(rob_data),
    .rob_addr(rob_addr),
    .rob_cur_pc(rob_cur_pc),
    .rob_mis_pc(rob_mis_pc),
    .rob_pb_tk_stat(rob_pb_tk_stat),

    // cdb
    .cdb_alu_valid(cdb_alu_valid),
    .cdb_alu_src(cdb_alu_src),
    .cdb_alu_val(cdb_alu_val),
    .cdb_ld_valid(cdb_ld_valid),
    .cdb_ld_src(cdb_ld_src),
    .cdb_ld_val(cdb_ld_val)
);

wire [`INST_TY_TP] dec_ty;
wire [`INST_OPT_TP] dec_opt;
wire [`REG_IDX_TP] dec_rd;
wire [`REG_IDX_TP] dec_rs1;
wire [`REG_IDX_TP] dec_rs2;
wire [`WORD_TP] dec_imm;

decoder cpu_decoder(
    .inst(bp_pb_inst),
    .ty(dec_ty),
    .opt(dec_opt),
    .rd(dec_rd),
    .rs1(dec_rs1),
    .rs2(dec_rs2),
    .imm(dec_imm),
    .is_ls()
);

wire rs_full;
wire alu_ena;
wire [`INST_OPT_TP] alu_opt;
wire [`WORD_TP] alu_val1;
wire [`WORD_TP] alu_val2;
wire [`WORD_TP] alu_imm;
wire [`ROB_IDX_TP] alu_rob_idx;

RS cpu_rs(
    .clk(clk_in),
    .rst(rst_in),
    .rdy(rdy_in),

    .rs_en(),
    .rs_st(),
    .rs_rb(),
    .rs_full(rs_full),

    // idu   
    .id_opt(rs_opt),
    .id_src1(rs_src1),
    .id_src2(rs_src2),
    .id_val1(rs_val1),
    .id_val2(rs_val2),
    .id_imm(rs_imm),  
    .id_rob_idx(rs_rob_idx),

    // alu
    .alu_ena(alu_ena),
    .alu_opt(alu_opt),
    .alu_val1(alu_val1),
    .alu_val2(alu_val2),
    .alu_imm(alu_imm),
    .alu_rob_idx(alu_rob_idx),

    // cdb
    .cdb_alu_valid(cdb_alu_valid),
    .cdb_alu_src(cdb_alu_src),
    .cdb_alu_val(cdb_alu_val),
    .cdb_ld_valid(cdb_ld_valid),
    .cdb_ld_src(cdb_ld_src),
    .cdb_ld_val(cdb_ld_val)
);

wire slb_full;
wire slb_empty;
wire dcache_rd_ena;
wire [`ADDR_TP] dcache_rd_addr;
wire [`INST_OPT_TP] dcache_rd_opt;
wire cdb_ld_valid;
wire [`ROB_IDX_TP] cdb_ld_src;
wire [`WORD_TP] cdb_ld_val;
wire rob_en;
wire [`ROB_IDX_TP] rob_sr;
wire [`WORD_TP] rob_va;
wire [`ADDR_TP] rob_add;

SLB cpu_slb(
    .clk(clk_in),
    .rst(rst_in),
    .rdy(rdy_in),

    .slb_en(),
    .slb_st(),
    .slb_rb(),
    .slb_full(slb_full),
    .slb_empty(slb_empty),

    // idu
    .id_ena(slb_valid),
    .id_opt(slb_opt),
    .id_src1(slb_src1),
    .id_src2(slb_src2),
    .id_val1(slb_val1),
    .id_val2(slb_val2),
    .id_imm(slb_imm),
    .id_rob_idx(slb_rob_idx),
    
    // dcache
    .cache_rd_ena(dcache_rd_ena),
    .cache_rd_addr(dcache_rd_addr),
    .cache_rd_opt(dcache_rd_opt),  
    .cache_rd_hit(cache_),
    .cache_rd_hit_dat(),

    // cdb
    .cdb_alu_valid(cdb_alu_valid),
    .cdb_alu_src(cdb_alu_src),
    .cdb_alu_val(cdb_alu_val),
    .cdb_ld_valid(cdb_ld_valid),
    .cdb_ld_src(cdb_ld_src),
    .cdb_ld_val(cdb_ld_val),

    // rob
    .rob_ena(rob_ena),
    .rob_src(rob_src),
    .rob_val(rob_val),
    .rob_addr(rob_addr)
);

wire [`ROB_IDX_TP] id_src1;
wire [`ROB_IDX_TP] id_src2;
wire [`WORD_TP] id_val1;
wire [`WORD_TP] id_val2;

regfile cpu_regfile(
    .clk(clk_in),
    .rst(rst_in),
    .rsy(rsy_in),

    .reg_en(),
    .reg_st(),
    .reg_rb(),

    // idu
    .id_rs1(reg_rs1),
    .id_rs2(reg_rs2),
    .id_src1(id_src1),
    .id_src2(id_src2),
    .id_val1(id_val1),
    .id_val2(id_val2),
    
    .id_rn_ena(reg_rn_ena),
    .id_rn_rd(reg_rn_rd),
    .id_rn_idx(reg_rn_idx),

    // rob
    .rob_wr_ena(reg_wr_ena),
    .rob_wr_rd(reg_wr_rd),
    .rob_wr_val(reg_wr_val)
);

wire cdb_alu_valid;
wire [`ROB_IDX_TP] cdb_alu_src;
wire [`WORD_TP] cdb_alu_val;
wire cdb_alu_tk;

ALU cpu_alu(
    .clk(clk_in),
    .rst(rst_in),
    .rdy(rdy_in),

    .alu_en(),
    .alu_st(),
    // rs
    .rs_opt(alu_opt),
    .rs_val1(alu_val1),
    .rs_val2(alu_val2),
    .rs_imm(alu_imm),
    .rs_rob_idx(alu_rob_idx),

    // cdb 
    .cdb_alu_valid(cdb_alu_valid),
    .cdb_alu_src(cdb_alu_src),
    .cdb_alu_val(cdb_alu_val),
    .cdb_alu_tk(cdb_alu_tk)
);

wire rob_empty;
wire rob_full;
wire [`ROB_IDX_TP] rob_idx;
wire rob_rb_ena;
wire [`ADDR_TP] if_rb_pc;
wire id_src1_rdy;
wire id_src2_rdy;
wire [`WORD_TP] id_val1;
wire [`WORD_TP] id_val2;
wire reg_wr_ena;
wire [`REG_IDX_TP] reg_wr_rd;
wire [`WORD_TP] reg_wr_val;
wire reg_wr_ena;
wire [`REG_IDX_TP] reg_wr_rd;
wire [`WORD_TP] reg_wr_val;
wire bp_fb_ena;
wire bp_fb_tk;
wire [`ADDR_TP] bp_fb_pc;

ROB cpu_rob(
    .clk(clk_in),
    .rst(rst_in),
    .rdy(rdy_in),

    .rob_en(),
    .rob_st(),
    .rob_empty(),
    .rob_full(rob_full),
    .rob_idx(rob_idx),
    .rob_rb_ena(rob_rb_ena),

    // if
    .if_rb_pc(if_rb_pc),

    // id
    .id_src1(rob_src1),
    .id_src2(rob_src2),
    .id_src1_rdy(id_src1_rdy),
    .id_src2_rdy(id_src2_rdy),
    .id_val1(id_val1),
    .id_val2(id_val2),
    
    .id_valid(rob_ena),
    .id_opt(rob_opt),
    .id_dest(rob_dest),
    .id_data(rob_data),
    .id_addr(rob_addr),
    .id_cur_pc(rob_cur_pc),
    .id_mis_pc(rob_mis_pc),
    .id_pb_tk(rob_pb_tk_stat),

    // reg
    .reg_wr_ena(rob_wr_ena),
    .reg_wr_rd(reg_wr_rd),
    .reg_wr_val(reg_wr_val),
    
    // slb
    .slb_valid(rob_ena),
    .slb_src(rob_src),
    .slb_val(rob_val),
    .slb_addr(rob_addr),

    // cdb
    .cdb_alu_valid(cdb_alu_valid),
    .cdb_alu_tk(cdb_alu_tk),
    .cdb_alu_src(cdb_alu_src),
    .cdb_alu_val(cdb_alu_val),
    .cdb_ld_valid(cdb_ld_valid),
    .cdb_ld_src(cdb_ld_src),
    .cdb_ld_val(cdb_ld_val),

    // dcache
    .cache_wr_ena(cache_wr_ena),
    .cache_wr_addr(cache_wr_addr),
    .cache_wr_opt(cache_wr_opt),
    .cache_wr_data(cache_wr_data),
    .cache_wr_hit(cache_wr_hit),

    // bp
    .bp_fb_ena(bp_fb_ena),
    .bp_fb_tk(bp_fb_tk),
    .bp_fb_pc(bp_fb_pc)
);

wire if_cache_hit;
wire [`WORD_TP] if_hit_word;
wire mem_ena;
wire [`ADDR_TP] mem_addr;

icache cpu_icache(
    .clk(clk_in),
    .rst(rst_in),
    .rsy(rsy_in),

    .cache_en(),
    .cache_st(),
    .cache_rb(rob_rb_ena),

    .if_addr(),
    .if_cache_hit(if_cache_hit),
    .if_hit_word(if_hit_word),

    .mem_ena(mem_ena),
    .mem_addr(mem_addr),
    .mem_valid(),
    .mem_line()
);

wire slb_cache_hit;
wire [`WORD_TP] slb_hit_word;
wire rob_cache_hit;
wire mem_wr_ena;
wire [`ADDR_TP] mem_wr_addr;
wire [`LINE_TP] mem_wr_line;
wire mem_rd_ena;
wire [`ADDR_TP] mem_rd_addr;

dcache cpu_dcache(
    .clk(clk_in),
    .rst(rst_in),
    .rdy(rdy_in),

    .cache_en(),
    .cache_st(),
    .cache_rb(rob_rb_ena),

    // slb
    .slb_rd_valid(),
    .slb_rd_addr(),
    .slb_rd_opt(),
    .slb_cache_hit(slb_cache_hit),
    .slb_hit_word(slb_hit_word),

    // rob
    .rob_wr_valid(),
    .rob_wr_addr(),
    .rob_wr_opt(),
    .rob_wr_data(),
    .rob_cache_hit(rob_cache_hit), 
    
    // memctrl
    .mem_valid(),
    .mem_wr_ena(mem_wr_ena),
    .mem_wr_addr(mem_wr_addr),
    .mem_wr_line(mem_wr_line),
    .mem_rd_ena(mem_rd_ena),
    .mem_rd_addr(mem_rd_addr),
    .mem_rd_line()
);

wire icache_ena;
wire [`LINE_TP] icache_rd_line;
wire dcache_ena;
wire [`LINE_TP] dcache_rd_line;
wire ram_ena;
wire ram_rw_sel;
wire [`ADDR_TP] ram_addr;
wire [`BYTE_TP] ram_wr_byte;

memctrl cpu_memctrl(
    .clk(clk_in),
    .rst(rst_in),
    .rdy(rdy_in),

    .mc_en(),
    .mc_st(),
    .mc_rb(rob_rb_ena),

    // icache
    .icache_rd_valid(),
    .icache_rd_addr(),
    .icache_ena(icache_ena),
    .icache_rd_line(icache_rd_line),

    // dcache
    .dcache_ena(dcache_ena),
    .dcache_rd_valid(mem_rd_ena),
    .dcache_wr_valid(mem_wr_ena),
    .dcache_rd_addr(mem_rd_addr),
    .dcache_wr_addr(mem_wr_addr),
    .dcache_wr_line(mem_wr_line),
    .dcache_rd_line(dcache_rd_line),

    // ram
    .ram_ena(ram_ena),
    .ram_rw_sel(ram_rw_sel),
    .ram_addr(ram_addr),
    .ram_wr_byte(ram_wr_byte),
    .ram_rd_byte()
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
