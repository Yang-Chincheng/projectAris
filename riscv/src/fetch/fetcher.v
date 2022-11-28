`include "../utils.v"


module fetcher(
           input wire clk, // system clock
           input wire rst, // reset signal
           input wire rdy,

           input wire if_en, // inst fetch unit enable signal
           input wire if_st, // inst fetch unit stall signal
           input wire if_rb, // inst fetch unit rollback signal

            // icache
           output wire cache_rd_en,
           output wire [`ADDR_TP] cache_rd_addr,
           input wire cache_hit,
           input wire [`WORD_TP] cache_hit_inst,

           // bp
           output wire bp_ena,
           output wire [`ADDR_TP] bp_pb_pc,
           output wire [`WORD_TP] bp_pb_inst,
           input wire bp_pd_tk,
           input wire [`ADDR_TP] bp_pd_off,

            // idu
           output reg id_ena, // inst decode unit enable signal
           output reg [`WORD_TP] id_inst, // inst sent to idu
           output reg [`ADDR_TP] id_cur_pc, // pc sent to idu
           output reg [`ADDR_TP] id_mis_pc, // rollback pc target when mispredicted
           output reg id_pd_tk, // reserved predict result for feedback

            // rob
           input wire [`ADDR_TP] rob_rb_pc // rollbacl pc target
       );

reg [`WORD_TP] pc;

integer i;

assign cache_rd_en = if_en;
assign cache_rd_addr = pc;

assign bp_ena = if_en;
assign bp_pb_pc = pc;
assign bp_pb_inst = cache_hit_inst;

wire [`ADDR_TP] succ_pc = pc + `NEXT_PC_INC;
wire [`ADDR_TP] jump_pc = pc + bp_pd_off;

always @(posedge clk) begin
    id_ena <= `FALSE;

    if (rst) begin
        pc <= `ZERO_ADDR;
    end
    else if (!if_en || if_st) begin
        // STALL
    end
    else if (if_rb) begin
        pc <= rob_rb_pc;
    end
    else if (cache_hit) begin
        // send inst to idu
        id_inst <= cache_hit_inst;
        id_cur_pc <= pc;
        // id_nex_pc <= (bp_pd_tk? jump_pc: succ_pc);
        // TODO: special case for JALR
        id_mis_pc <= (bp_pd_tk? succ_pc: jump_pc);
        id_pd_tk <= bp_pd_tk;
        id_ena <= `TRUE;

        // next pc
        pc <= (bp_pd_tk? jump_pc: succ_pc);
    end
end

endmodule

