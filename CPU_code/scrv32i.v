/*

Single Cycle データパス RV32Iプロセッサ

*/

`include "regfile.v"

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

module core(
    input        clk, 
    input        rst,
    input        dready_n, 
    input        iready_n,
    input        dbusy,
    input [31:0] idata,
    input [ 2:0] oint_n,
    output[31:0] daddr,
    output[31:0] iaddr,
    output[ 1:0] dsize,
    output       dreq,
    output       dwrite,
    output       iack_n,
    inout [31:0] ddata
);
    wire       [31:0] inst;
    wire       [ 6:0] opcode;
    wire              reg_write_n;
    wire       [ 4:0] rs1_addr, rs2_addr, rd_addr;
    wire       [31:0] rs1_data, rs2_data, rd_data;
    wire signed[31:0] alu_out, imm;
    wire       [ 3:0] ctrl;
    wire       [31:0] mem_out;
    wire signed[31:0] alu_in_1, alu_in_2;
    wire              stall;

    reg        [31:0] pc;

    assign iaddr = pc;

    assign inst = idata;

    assign opcode = inst[6:0];

    assign rs1_addr = inst[19:15];
    assign rs2_addr = inst[24:20];
    assign rd_addr  = inst[11: 7];

    assign imm = immgen(inst);

    assign mem_out = mem_load_data(inst, ddata);

    assign alu_in_1 = 
        opcode == `OP_AUIPC || opcode == `OP_JAL ? pc : 
        opcode == `OP_LUI                        ? 32'b0 : rs1_data;
    assign alu_in_2 = opcode == `OP_ALU || opcode == `OP_BRA ? rs2_data : imm;
    assign ctrl = alu_ctrl(inst);
    assign alu_out = alu(alu_in_1, alu_in_2, ctrl);


    assign rd_data = 
        opcode == `OP_JAL || opcode == `OP_JALR ? pc+4 : 
        opcode == `OP_LOAD                      ? mem_out : alu_out;

    assign reg_write_n = (opcode == `OP_STORE || opcode == `OP_BRA ? 1'b1 : 1'b0) || stall;

    assign dreq = opcode == `OP_LOAD || opcode == `OP_STORE;
    assign dwrite = opcode == `OP_STORE;
    assign daddr = alu_out;
    assign ddata = opcode == `OP_STORE ? rs2_data : 32'bz;
    assign dsize = inst[13:12];

    assign stall = iready_n || (opcode == `OP_LOAD && dready_n) || (opcode == `OP_STORE && dbusy);
    
    assign iack_n = 1'b1;

    regfile i_regfile(
        .clk(clk), .rst(rst),
        .write_n(reg_write_n),
        .rs1(rs1_addr), .rs2(rs2_addr),
        .rd(rd_addr),
        .in(rd_data),
        .out1(rs1_data), .out2(rs2_data)
    );

    always@(posedge clk or negedge rst) begin
        if(!rst) begin
            pc <= 32'h0001_0000;
        end else if(!stall) begin
            case(opcode)
                `OP_BRA:  
                    case(inst[14:12])
                        `FCT3_BEQ:  pc <= alu_out == 0 ? pc+imm : pc+4;
                        `FCT3_BNE:  pc <= alu_out == 0 ? pc+4 : pc+imm;
                        `FCT3_BLT:  pc <= alu_out < 0 ? pc+imm : pc+4;
                        `FCT3_BGE:  pc <= alu_out < 0 ? pc+4 : pc+imm;
                        `FCT3_BLTU: pc <= alu_in_1[31] == alu_in_2[31] ? alu_out < 0 ? pc+imm : pc+4 :
                                                                         alu_out > 0 ? pc+imm : pc+4;
                        `FCT3_BGEU: pc <= alu_in_1[31] == alu_in_2[31] ? alu_out < 0 ? pc+4 : pc+imm :
                                                                         alu_out > 0 ? pc+4 : pc+imm;
                        default: pc <= pc+4;
                    endcase
                `OP_JAL:  pc <= alu_out;
                `OP_JALR: pc <= alu_out;
                default:  pc <= pc+4;
            endcase
            
        end
    end

    function[31:0] mem_load_data(
        input[31:0] inst,
        input[31:0] mem_data
    );
        case(inst[14:12]) 
            `FCT3_LB : mem_load_data = {{24{mem_data[7]}}, mem_data[7:0]};
            `FCT3_LH : mem_load_data = {{16{mem_data[15]}}, mem_data[15:0]};
            `FCT3_LW : mem_load_data = mem_data;
            `FCT3_LBU: mem_load_data = {{24{1'b0}}, mem_data[7:0]};
            `FCT3_LHU: mem_load_data = {{16{1'b0}}, mem_data[15:0]};
        endcase
    endfunction

    //alu_ctrl: ALU制御信号を生成する
    function[3:0] alu_ctrl(
        input[31:0] inst
    );
        if(inst[6:0] == `OP_BRA) begin
            alu_ctrl = `ALU_SUB;
        end else if(inst[6:0] == `OP_ALU || inst[6:0] == `OP_ALUI) begin
            case(inst[14:12])
                `FCT3_ADD:  alu_ctrl = inst[6:0] == `OP_ALU && inst[30] == 1'b1 ? `ALU_SUB : `ALU_ADD;
                `FCT3_SLL:  alu_ctrl = `ALU_SLL;
                `FCT3_SLT:  alu_ctrl = `ALU_SLT;
                `FCT3_SLTU: alu_ctrl = `ALU_SLTU;
                `FCT3_XOR:  alu_ctrl = `ALU_XOR;
                `FCT3_SRL:  alu_ctrl = inst[30] == 1'b1 ? `ALU_SRA : `ALU_SRL;
                `FCT3_OR:   alu_ctrl = `ALU_OR;
                `FCT3_AND:  alu_ctrl = `ALU_AND;
            endcase
        end else begin
            alu_ctrl = `ALU_ADD;
        end
    endfunction

    //immgen: 即値を生成する
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

    //alu: ALU
    function signed [31:0] alu(
        input signed [31:0] a, 
        input signed [31:0] b,
        input [3:0] ctrl
    );
        case(ctrl)
            `ALU_ADD: alu = a + b;
            `ALU_SUB: alu = a - b;
            `ALU_AND: alu = a & b;
            `ALU_OR:  alu = a | b;
            `ALU_XOR: alu = a ^ b;
            `ALU_SLL: alu = a << b[4:0];
            `ALU_SRL: alu = a >> b[4:0];
            `ALU_SRA: alu = a >>> b[4:0];
            `ALU_SLT: alu = (a < b) ? 32'b1 : 32'b0;
            `ALU_SLTU: alu = $unsigned(a) < $unsigned(b) ? 32'b1 : 32'b0;
        endcase
    endfunction

endmodule






