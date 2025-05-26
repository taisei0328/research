
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

module fetch (
    input clk,
    input rst,
    input stop,
    input bubble,
    input r_wn,
    input branch_taken,
    input [31:0]pc_branch,
    input [31:0]imm_E,
    input jump,
    input [31:0] idata,
    input wb_pc_f_hazard,
    input [31:0] alu_res,
    output reg [31:0] inst_IFID,
    output reg [31:0] iaddr,
    output reg [31:0] now_pc
);
    wire  is_nop = (stop  | !rst);
   
      always @(posedge clk) begin
        if (!rst) begin
            iaddr  <= 32'h0001_0000;
            now_pc <= 32'h0001_0000;
            inst_IFID <= 32'b0;
        
        end  else if(bubble) begin 
            now_pc <= now_pc;
         //   inst_IFID <= 32'b0; // 追加
            if(jump) begin
                iaddr <= alu_res;
                inst_IFID <= 32'b0;
                if(branch_taken)begin
                iaddr <= pc_branch + imm_E;
                inst_IFID <= 32'b0;
                end
            end
            else begin
                iaddr <= iaddr;
            end 
        end  else if (stop) begin
            if(jump) begin // stopにも追加
                iaddr <= alu_res;
                inst_IFID <= 32'b0;
                if(branch_taken)begin
                iaddr <= pc_branch + imm_E;
                inst_IFID <= 32'b0;
                end
            end
            else begin 
                now_pc <= now_pc;
                iaddr <= iaddr;
                inst_IFID <= inst_IFID;

            end
        end

        else begin // 通常処理
                now_pc <= iaddr;
                iaddr <= iaddr + 32'd4;
                if(is_nop) begin
                    inst_IFID <= 32'b0;
                end
                else begin
                    inst_IFID <= idata;
                end
                 
    end
    end
    
 
endmodule