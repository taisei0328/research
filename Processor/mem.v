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

module mem(
    input clk,
    input stop,
    input rst,
    input [31:0] inst_EXM,
    input [31:0] alu_res_M,
    input [31:0] rdata2_M,
    input [31:0] pc_in,
    input [31:0] imm_M,
    input [4:0] rd_M,
    input [1:0] mem_command,
    input [1:0] mem_command_M,
    input jump,
    input branch_taken,
    output [31:0] in_ddata,
    output [6:0] opcode,
    input [31:0] out_ddata,
    output reg [31:0] alu_out_M,
    output reg [4:0] rd_out,
    output reg [31:0] inst_MW,
    output reg [31:0] imm_out,
    output reg [31:0] mem_out_M,
    output reg [31:0] pc_out,
    input dready_n,
    input dbusy,
    output [31:0] daddr,
    output [1:0] dsize,
    output dreq,
    output dwrite
);
    assign opcode = inst_EXM[6:0];
    wire [2:0] funct3 = inst_EXM[14:12];

    assign daddr = alu_res_M;
    assign dreq = (opcode == `OP_LOAD || opcode == `OP_STORE);
    assign dwrite = (opcode == `OP_STORE);
    assign dsize = (funct3[1:0] == 2'b00) ? 2'b00 :
                   (funct3[1:0] == 2'b01) ? 2'b01 :
                   (funct3[1:0] == 2'b10) ? 2'b10 :
                   2'b10;
    assign in_ddata = (opcode == `OP_STORE) ? rdata2_M : 32'bz;

    reg [31:0] mem_out;

    always @(*) begin
        case (funct3)
            `FCT3_LB:  mem_out = {{24{out_ddata[7]}},  out_ddata[7:0]};
            `FCT3_LH:  mem_out = {{16{out_ddata[15]}}, out_ddata[15:0]};
            `FCT3_LW:  mem_out = out_ddata;
            `FCT3_LBU: mem_out = {{24{1'b0}}, out_ddata[7:0]};
            `FCT3_LHU: mem_out = {{16{1'b0}}, out_ddata[15:0]};
            default:   mem_out = 32'b0;
        endcase
    end

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            imm_out <= 32'b0;
            rd_out  <= 5'b0;
            inst_MW <= 32'b0;
            mem_out_M <= 32'b0;
            alu_out_M <= 32'b0;
            pc_out <= 32'b0;
        end else if (inst_EXM == 32'b0) begin
            inst_MW <= 32'b0;
            imm_out <= 32'b0;
            mem_out_M <= 32'b0;
            rd_out <= 5'b0;
            alu_out_M <= 32'b0;
            pc_out <= 32'b0;
        end else if (opcode == `OP_LOAD && !dready_n) begin
            mem_out_M <= mem_out;
            inst_MW <= inst_EXM;
            imm_out <= imm_M;
            alu_out_M <= alu_res_M;
            rd_out <= rd_M;
            pc_out <= pc_in;
        end else if (opcode != `OP_LOAD) begin
            mem_out_M <= 32'b0;
            inst_MW <= inst_EXM;
            imm_out <= imm_M;
            alu_out_M <= alu_res_M;
            rd_out <= rd_M;
            pc_out <= pc_in;
        end
    end
endmodule

