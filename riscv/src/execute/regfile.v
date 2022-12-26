`ifndef REGFILE_V_ 
`define REGFILE_V_ 

`include "/home/Modem514/projectAris/riscv/src/utils.v"

`define REG_BIT `REG_IDX_LN
`define REG_SIZE (1 << `REG_BIT)

/**
 * TODO:
 * (1) protect #0 register
 *
 */

module regfile #(
    parameter REG_SIZE = `REG_SIZE,
    parameter REG_BIT = `REG_BIT
) (
    input wire clk,
    input wire rst,
    input wire rdy,

    input wire reg_en,
    input wire reg_st,
    input wire reg_rb,

    // idu
    input wire [`REG_IDX_TP] id_rs1,
    input wire [`REG_IDX_TP] id_rs2,
    output wire [`ROB_IDX_TP] id_src1,
    output wire [`ROB_IDX_TP] id_src2,
    output wire [`WORD_TP] id_val1,
    output wire [`WORD_TP] id_val2,
    
    input wire id_rn_ena,
    input wire [`REG_IDX_TP] id_rn_rd,
    input wire [`ROB_IDX_TP] id_rn_idx,

`ifdef DEBUG
    // dbg
    output wire [`ROB_IDX_TP] dbg_src,
    output wire [`WORD_TP] dbg_val,
    output wire [`ROB_IDX_TP] dbg_src2,
    output wire [`WORD_TP] dbg_val2,
`endif

    // rob
    input wire rob_wr_ena,
    input wire [`REG_IDX_TP] rob_wr_rd,
    input wire [`WORD_TP] rob_wr_val,
    input wire [`ROB_IDX_TP] rob_wr_idx
);

reg [`ROB_IDX_TP] src[REG_SIZE-1:0];
reg [`WORD_TP]    val[REG_SIZE-1:0];

assign id_src1 = ((id_rn_ena && id_rn_rd == id_rs1)? id_rn_idx
    : ((rob_wr_ena && rob_wr_idx == src[id_rs1] && rob_wr_rd == id_rs1)? `ZERO_ROB_IDX: src[id_rs1])); 
assign id_src2 = ((id_rn_ena && id_rn_rd == id_rs2)? id_rn_idx
    : ((rob_wr_ena && rob_wr_idx == src[id_rs2] && rob_wr_rd == id_rs2)? `ZERO_ROB_IDX: src[id_rs2])); 
assign id_val1 = ((rob_wr_ena && rob_wr_idx == src[id_rs1] && rob_wr_rd == id_rs1)? rob_wr_val: val[id_rs1]);
assign id_val2 = ((rob_wr_ena && rob_wr_idx == src[id_rs2] && rob_wr_rd == id_rs2)? rob_wr_val: val[id_rs2]);

integer i;

`ifdef DEBUG
assign dbg_src = src[10];
assign dbg_src2 = src[12];
assign dbg_val = val[10];
assign dbg_val2 = val[12];
`endif

// wire [`ROB_IDX_TP] dbg_reg_src[1:0];
// assign {dbg_reg_src[1], dbg_reg_src[0]} = {src[10], src[0]};
// wire [`WORD_TP] dbg_reg_val[1:0];
// assign {dbg_reg_val[1], dbg_reg_val[0]} = {val[10], val[0]};


always @(posedge clk) begin
    if (rst) begin
        for (i = 0; i < REG_SIZE; i++) begin
            src[i] <= `ZERO_ROB_IDX;
            val[i] <= `ZERO_WORD;
        end
    end
    else if (reg_rb) begin
        if (rob_wr_ena) begin
            val[rob_wr_rd] <= rob_wr_val;
        end
        for (i = 0; i < REG_SIZE; i++) begin
            src[i] <= `ZERO_ROB_IDX;
        end
    end
    else if (!rdy || !reg_en || reg_st) begin
        // STALL
    end
    else begin
        if (rob_wr_ena) begin
            if (rob_wr_idx == src[rob_wr_rd]) begin
                src[rob_wr_rd] <= `ZERO_ROB_IDX;
            end
            val[rob_wr_rd] <= rob_wr_val;
`ifdef DEBUG
    // $display("[] reg = %h, val = %h", rob_wr_rd, rob_wr_val);
`endif
        end
        if (id_rn_ena) begin
            src[id_rn_rd] <= id_rn_idx;
        end
    end
end

endmodule

`endif 