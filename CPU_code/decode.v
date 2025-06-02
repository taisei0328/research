`ifndef DECODE_V
`define DECODE_V

`include "regfile.v"

// ALU操作コード
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

// 命令オペコード
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

module decode (
    input clk,
    input rst,
    input stop,
    input bubble,
    input jump, // 分岐確定時のflush
    input [31:0] inst_IFID,
    input [31:0] pc_in,
    input [31:0] wd_val,
    input [4:0] rd_W,
    input [31:0] rdata1,
    input [31:0] rdata2,
    input wb_pc_f_hazard,
    input r_wn,
    output reg [31:0] rs1,
    output  [4:0] rs1_wire,
    output  [4:0] rs2_wire,
    output reg [31:0] rs2,
    output reg [4:0] rd_out,
    output reg [31:0] pc_out,
    output reg [31:0] inst_IDEX,
    output reg [31:0] imm_out,
    output reg [1:0] mem_command_out,
    output  [6:0] opcode
);
    assign opcode = inst_IFID[6:0];
    wire [4:0] rd     = inst_IFID[11:7];
    wire [2:0] funct3 = inst_IFID[14:12];
    assign rs1_wire   = inst_IFID[19:15];
    assign rs2_wire   = inst_IFID[24:20];


    // 即値生成
   function[31:0] immgen(
        input[31:0] inst
    );
        case(inst[6:0])
            `OP_LOAD:  immgen = {{20{inst[31]}}, inst[31:20]};
            `OP_ALUI:  immgen = inst[14:12] == `FCT3_SRL ? {{27{1'b0}}, inst[24:20]} : {{20{inst[31]}}, inst[31:20]};
            `OP_STORE: immgen = {{20{inst[31]}}, inst[31:25], inst[11:7]};
            `OP_BRA:   immgen = {{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};
            `OP_AUIPC: immgen = {inst[31:12], 12'b0};
            `OP_LUI:   immgen = {inst[31:12], 12'b0};
            `OP_JALR:  immgen = {{20{inst[31]}}, inst[31:20]};
            `OP_JAL:   immgen = {{20{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};
            default:   immgen = 32'b0;
        endcase
    endfunction

    wire [31:0] imm;

    assign imm = immgen(inst_IFID);
    
    wire  [1:0] mem_command_D;
    

    // メモリアクセス判定
    assign mem_command_D = (opcode == `OP_LOAD)  ? 2'b01 :
                           (opcode == `OP_STORE) ? 2'b11 :
                                                    2'b00;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            rd_out  <= 0;
            pc_out  <= 0;
            inst_IDEX <= 0;
            imm_out <=0;
            rs1     <= 0;
            rs2     <= 0;
            mem_command_out <=0;
        
        end 

        else if(stop) begin
            
        end

        else if(bubble) begin
            rd_out  <= 0;
            inst_IDEX <= 0;
            imm_out <=0;
            rs1     <= 0;
            rs2     <= 0;
            mem_command_out <=0;
            end

        else if (!wb_pc_f_hazard && !stop) begin //メモリがビジーでないかつデータハザード起きていない
            // 通常動作時：次段に値を渡す
           inst_IDEX  <= inst_IFID;
           if(rs1_wire == rd_W && !r_wn && rd_W !=0) begin 
                rs1 <= wd_val;
           end else begin 
                rs1 <= rdata1;
           end
           if(rs2_wire == rd_W && !r_wn && rd_W != 0) begin
                rs2 <= wd_val;
           end else begin
               rs2 <= rdata2;
           end
            
            imm_out <=imm;
            pc_out  <= pc_in;
            rd_out <= rd;
            mem_command_out <= mem_command_D;
        end
    
    end
endmodule

`endif // DECODE_V

