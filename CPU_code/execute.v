
`ifndef EXECUTE_V
`define EXECUTE_V
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

module execute(
    input clk,
    input rst,
    input stop,
    input [31:0] inst_IDEX,
    input [31:0] rdata1_E,
    input [31:0] rdata2_E,
    input [31:0] pc_in,
    input [31:0] imm_E,
    input [4:0] rd_E, 
    input wb_pc_f_hazard,
    input [1:0] mem_command_E,
    input bubble,
    output branch_taken,
    
    output jump,
    output reg [31:0] inst_EXM,
    output reg [31:0] pc_out,
    output reg [4:0] rd_out,
    output reg [31:0] imm_out,
    output reg [31:0] alu_out,
    output  [31:0] alu_res,
    output reg [1:0] mem_command_out,
    output [6:0] opcode,
    output reg [31:0] rdata2_out
);
    wire [3:0] ctrl;
    assign opcode = inst_IDEX[6:0];
    wire [2:0] funct3 = inst_IDEX[14:12];
    wire [6:0] funct7 = inst_IDEX[31:25];

    wire signed [31:0] in_a, in_b;
    
    assign in_a =
        (opcode == `OP_AUIPC || opcode == `OP_JAL) ? pc_in :
        (opcode == `OP_LUI) ? 32'b0 : rdata1_E;

    assign in_b =
        (opcode == `OP_ALU || opcode == `OP_BRA) ? rdata2_E : imm_E;
    
    function   [3:0]  ctrl_sel(
        input [6:0] opcode,
        input [2:0] funct
    );
        case (opcode)
            `OP_BRA: begin 
                case(funct3)
                `FCT3_BEQ: ctrl_sel = `ALU_SUB;
                `FCT3_BNE: ctrl_sel = `ALU_SUB;
                `FCT3_BLT: ctrl_sel = `ALU_SLT;
                `FCT3_BLTU: ctrl_sel = `ALU_SLTU;
                `FCT3_BGE : ctrl_sel = `ALU_SLT;
                `FCT3_BGEU : ctrl_sel = `ALU_SLTU;
                endcase
                
            end 
            `OP_ALU, `OP_ALUI: begin
                case (funct3)
                    `FCT3_ADD:  ctrl_sel = (opcode == `OP_ALU && inst_IDEX[30]) ? `ALU_SUB : `ALU_ADD;
                    `FCT3_SLL:  ctrl_sel = `ALU_SLL;
                    `FCT3_SLT:  ctrl_sel = `ALU_SLT;
                    `FCT3_SLTU: ctrl_sel= `ALU_SLTU;
                    `FCT3_XOR:  ctrl_sel = `ALU_XOR;
                    `FCT3_SRL:  ctrl_sel = inst_IDEX[30] ? `ALU_SRA : `ALU_SRL;
                    `FCT3_OR:   ctrl_sel= `ALU_OR;
                    `FCT3_AND:  ctrl_sel = `ALU_AND;
                    default:    ctrl_sel = `ALU_ADD;
                endcase
            end
            default: ctrl_sel = `ALU_ADD;
        endcase
    endfunction

    assign ctrl = ctrl_sel(opcode, funct3);


    function signed [31:0] alu(
        input signed [31:0] a,
        input signed [31:0] b,
        input [3:0] ctrl
    );
        case (ctrl)
            `ALU_ADD:  alu = a + b;
            `ALU_SUB:  alu = a - b;
            `ALU_AND:  alu = a & b;
            `ALU_OR:   alu = a | b;
            `ALU_XOR:  alu = a ^ b;
            `ALU_SLL:  alu = a << b[4:0];
            `ALU_SRL:  alu = a >> b[4:0];
            `ALU_SRA:  alu = a >>> b[4:0];
            `ALU_SLT:  alu = (a < b) ? 32'b1 : 32'b0;
            `ALU_SLTU: alu = ($unsigned(a) < $unsigned(b)) ? 32'b1 : 32'b0;
            default:   alu = 32'b0;
        endcase
    endfunction
   
    assign alu_res = alu(in_a, in_b, ctrl);


    always @(posedge clk or negedge rst) begin
        if (!rst) begin

            inst_EXM <= 32'b0;
            rd_out <= 5'b0;
            pc_out <= 32'b0;
            alu_out <= 32'b0;
            mem_command_out <= 2'b00;
            rdata2_out <= 32'b0;
            imm_out <= 32'b0;

        end else  if(!stop) begin
            // 正常な命令処理
            inst_EXM<= inst_IDEX;
            imm_out <= imm_E;
            rd_out <= rd_E;
            pc_out <= pc_in;
            alu_out <= alu_res;     
            mem_command_out<= mem_command_E;
            rdata2_out <= rdata2_E;
        end

    end
    
 assign jump = (opcode == `OP_JAL || opcode == `OP_JALR || branch_taken);

    assign branch_taken = (opcode == `OP_BRA) && (
        (funct3 == `FCT3_BEQ  && alu_res==0) ||
        (funct3 == `FCT3_BNE  && alu_res !=0) ||
        (funct3 == `FCT3_BLT  && alu_res !=0) ||
        (funct3 == `FCT3_BGE  && alu_res ==0) ||
        (funct3 == `FCT3_BLTU && alu_res !=0) ||
        (funct3 == `FCT3_BGEU && alu_res ==0)
    );

endmodule


`endif // EXECUTE_V