

`define ALU_ADD  4'b0000
`define ALU_SUB  4'b1000
`define ALU_AND  4'b0001
`define ALU_OR   4'b0010
`define ALU_XOR  4'b0100
`define ALU_SLL  4'b0101
`define ALU_SRL  4'b0110
`define ALU_SRA  4'b1110
`define ALU_SLT  4'b1001
`define ALU_SLTU 4'b1010

`define OP_LOAD  7'b0000011
`define OP_ALUI  7'b0010011
`define OP_STORE 7'b0100011
`define OP_ALU   7'b0110011
`define OP_BRA   7'b1100011
`define OP_AUIPC 7'b0010111
`define OP_LUI   7'b0110111
`define OP_JALR  7'b1100111
`define OP_JAL   7'b1101111

`define FCT3_LB  3'b000
`define FCT3_LH  3'b001
`define FCT3_LW  3'b010
`define FCT3_LBU 3'b100
`define FCT3_LHU 3'b101

`define FCT3_SB  3'b000
`define FCT3_SH  3'b001
`define FCT3_SW  3'b010

`define FCT3_ADD  3'b000
`define FCT3_SLL  3'b001
`define FCT3_SLT  3'b010
`define FCT3_SLTU 3'b011
`define FCT3_XOR  3'b100
`define FCT3_SRL  3'b101
`define FCT3_OR   3'b110
`define FCT3_AND  3'b111

`define FCT3_BEQ  3'b000
`define FCT3_BNE  3'b001
`define FCT3_BLT  3'b100
`define FCT3_BGE  3'b101
`define FCT3_BLTU 3'b110
`define FCT3_BGEU 3'b111


module writeback(
    input clk,
    input rst,
    input stop,
    input jump,
    input [4:0] reg_d,
    input [31:0] inst_MW,
    input [31:0] in_wb_data,
    input [31:0] alu_res_W,
    input [31:0] mem_out_W,
    input [31:0]pc_in,
    input [31:0] rddata_W, 
    input [31:0] imm_W,
    input [4:0] rd_W, 
    output [6:0] opcode,
    output  r_wn, 
    output [4:0] rd_out,
    output [4:0] out_wb_addr,
    output  [31:0] wd_val
);

assign rd_out = rd_W;
assign opcode = inst_MW[6:0];       // opcode
wire [2:0] funct3 = inst_MW[14:12];     // funct3
wire [6:0] funct7 = inst_MW[31:25];


//クロック制御せず書き込ませるか
/*always @(*) begin
    case (opcode)
        `OP_LOAD  : wd_val = mem_out_W;        // LOAD なら　メモリの出力
        `OP_ALUI  : wd_val = alu_res_W;        // ALUI
        `OP_ALU   : wd_val = alu_res_W;        // ALU
        `OP_AUIPC : wd_val = pc_in+ imm_W;   // AUIPC
        `OP_LUI   : wd_val = imm_W;            // LUI
        `OP_JAL,
        `OP_JALR  : wd_val = pc_in + 4;       // JAL/JALR: 次のPCを保存
        default   : wd_val = 32'b0;
    endcase
    */

assign wd_val = (opcode == `OP_LOAD ) ? mem_out_W: 
(opcode == `OP_ALUI ) ? alu_res_W: 
 (opcode == `OP_ALU  ) ? alu_res_W: 
 (opcode == `OP_AUIPC) ? pc_in+ imm_W: 
(opcode == `OP_LUI  ) ? imm_W: 
(opcode == `OP_JAL || opcode == `OP_JALR ) ?  pc_in + 4:32'b0;


assign r_wn =(opcode == `OP_STORE || opcode == `OP_BRA ? 1'b1 : 1'b0) ;
endmodule
