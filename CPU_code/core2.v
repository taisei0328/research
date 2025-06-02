

`include "fetch.v"
`include "decode.v"
`include "execute.v"
`include "mem.v"
`include "writeback.v"
`include "regfile.v"
`include "bubble.v"

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
    input clk,
    input rst,
    input [31:0] idata,
    output [31:0] iaddr,
    input [31:0] mem_rdata,
    output [31:0] mem_addr,
    output dreq,
    output dwrite, 
    input dready_n, dbusy,
    output [31:0] ddata,
    output [31:0] daddr,
    output [1:0] dsize,
    input iready_n,
    input[2:0] oint_n,
    input iack_n
);

    // Fetch-Decode
    wire [31:0] pc_F;
    wire wb_pc_f_hazard;
    wire [6:0] opcode_M;
    wire stop =  iready_n || (opcode_M == `OP_LOAD && dready_n) || (opcode_M == `OP_STORE && dbusy) ;

    // Decode-Execute
    wire [31:0] pc_D, inst_IFID;
    wire [1:0] mem_command;
    wire[1:0]mem_command_D;
    wire [31:0] imm_D;
    wire [31:0] rdata1, rdata2;
    wire[31:0] rdata1_E, rdata2_E;
    wire [6:0] opcode;
    wire funct7_D;
    wire [4:0] rs1_wire, rs2_wire;

    // Execute-Memory
    wire [31:0] inst_IDEX;
    wire [6:0] opcode_E;
    wire [31:0] pc_E, imm_E;
    wire [4:0] rs1_E, rs2_E, rd_E;
    wire funct7_E;
    wire[1:0] mem_command_E;
    wire [31:0] alu_res;
    wire [31:0] rdata2_out;
    wire branch_taken;
    wire jump;
   wire  beq_true ;
   wire  bne_true;
   wire  blt_true  ;
   wire  bge_true   ;
   wire  bltu_true  ;
   wire  bgeu_true  ;
    // Memory-Writeback
    wire [31:0] mem_out_M;
    wire [31:0] pc_M, imm_M;
    wire [31:0] rdata2_M,alu_res_M,alu_res_W;
    wire [4:0] rd_M;
    wire [2:0] funct3_M;
    wire [6:0] funct7_M;
    wire [31:0] rd_data_W;
    wire [31:0] pc_W, imm_W ;
    wire [4:0] rd_W;
    wire [4:0] rd_WW;
    wire r_wn;
    wire [31:0] wd_val;
    wire [31:0] inst_EXM;
    wire [31:0] inst_MW;
    wire [31:0] in_ddata;
    wire [31:0] out_ddata ;
    wire [31:0] mem_out_W;
    wire[1:0] mem_command_M;
   // hazarad_unit
    wire F_bubble;
    wire D_bubble;
    wire E_bubble;

    assign ddata =  in_ddata ;
    assign out_ddata =  ddata; //inout ddataをinputとoutputに分けた
    
    
hazard_unit hazard_unit_inst (
    .rd_E(rd_E),
    .rd_M(rd_M),
    .rs1_D(rs1_wire),
    .rs2_D(rs2_wire),
    .mem_command_M(mem_command_M),
    .jump(jump),
    .F_bubble(F_bubble),
    .D_bubble(D_bubble),
    .E_bubble(E_bubble),
    .wb_pc_f_hazard(wb_pc_f_hazard)
);
 

    

    regfile i_regfile (
        .clk(clk), .rst(rst), .write_n(r_wn), 
        .rd(rd_WW), .in(wd_val),
        .rs1(rs1_wire), .rs2(rs2_wire), // レジスタの入力値を決める(rs1,rs2にdecodeで読みだしたrs1,rs2)　(decodeの信号 ➡　coreの信号 ➡　regfileの信号)
        .out1(rdata1), 
        .out2(rdata2)//レジスタからの出力をEステージにつなげるために，coreを経由する
    );

    // Fetch stage
    fetch fetch_stage (
        //input
        .bubble(F_bubble),
        .branch_taken(branch_taken),
        .stop(stop),
        .clk(clk), 
        .rst(rst),
        .iaddr(iaddr),
        .idata(idata),
        .jump(jump),
        .pc_branch(pc_D),
        .imm_E(imm_E),
        .wb_pc_f_hazard(wb_pc_f_hazard),
        //output
        .inst_IFID(inst_IFID), 
        .now_pc(pc_F),
        .alu_res(alu_res)
        
    );


    // Decode stage
    decode decode_stage (
        //input
        .bubble(D_bubble),
        .jump(jump),
        .clk(clk), 
        .rd_W(rd_W),
        .wd_val(wd_val),
        .stop(stop),
        .rst(rst),
        .inst_IFID(inst_IFID), //inst_Dに伝播
        .pc_in(pc_F),
        .rdata1(rdata1),
        .rdata2(rdata2),
        .r_wn(r_wn),
        .wb_pc_f_hazard(wb_pc_f_hazard),
        //output
        .inst_IDEX(inst_IDEX),
        .rs1_wire(rs1_wire),//レジスタの読み出しアドレスを出力
       .rs2_wire(rs2_wire),
        .pc_out(pc_D),
        .imm_out(imm_E),
        .mem_command_out(mem_command_E), //decodeのmem_command_Dをmemcommand_Dで受け取る
        .opcode(opcode_E),
        .rs1(rdata1_E), //レジスタの値
        .rs2(rdata2_E),//レジスタの値
        .rd_out(rd_E)// rs1_wireの値はrs1に入れている，2も同様➡　レジスタへの入力はdecodeの出力rs1,rs2をcoreにつなげて，regfileにつなげる
    );

    

    // Execute stage
    execute exe_stage (
        //input
        .bubble(E_bubble),
        .branch_taken(branch_taken),
        .imm_E(imm_E),
        .jump(jump),
        .rst(rst),
        .clk(clk),
        .stop(stop),
        .inst_IDEX(inst_IDEX),//inst_Eに伝播
        .wb_pc_f_hazard(wb_pc_f_hazard),
        //output
        .inst_EXM(inst_EXM),
        .pc_in(pc_D),
        .pc_out(pc_E),
        .rdata1_E(rdata1_E),
        .rdata2_E(rdata2_E),// 　レジスタからの出力をつなげた　rdata1,rdata2をEステージへ
        .rdata2_out(rdata2_M),
        .rd_E(rd_E),//rd_Eをrd_outに接続
        .rd_out(rd_M),//Eステージのoutput rd_outをrd_Eに接続
        .alu_res(alu_res),//jumpアドレスのため
        .alu_out(alu_res_M),
        .imm_out(imm_M),
        .mem_command_E(mem_command_E), //decodeのmem_command_Dをinputのmem_command_Dをinput
        .mem_command_out(mem_command_M)
    );

    // Memory stage
    mem mem_stage (
        .clk(clk), 
        .jump(jump),
        .imm_M(imm_M),
        .stop(stop),
        .rdata2_M(rdata2_M),
        .alu_res_M(alu_res_M), 
        .daddr(daddr), //データメモリのアクセスするアドレス (32-bit)
		.dreq(dreq), //データキャッシュ読み書き要求 (1-bit)
		.dwrite(dwrite), //データキャッシュ書き込み要求 (1-bit)
		.dsize(dsize), //データキャッシュに読み書きするサイズ（2-bit 00:byte 01:half 10:word 11:double word)
		.dready_n(dready_n), //データキャッシュ読み出し完了 (1-bit)
		.dbusy(dbusy), //キャッシュがメモリへアクセスを行っていて他の要求を受けることができない状態 (1-bit)
        .in_ddata(in_ddata),
        .out_ddata(out_ddata),
        .rst(rst), 
        .rd_M(rd_M),
        .alu_out_M(alu_res_W),
        .opcode(opcode_M),
        .rd_out(rd_W),
        .pc_in(pc_E),
        .inst_EXM(inst_EXM),
        .inst_MW(inst_MW),
        .imm_out(imm_W),
        .mem_out_M(mem_out_W), 
        .mem_command_M(mem_command_M),
        .pc_out(pc_M),
        .branch_taken(branch_taken)

    );

    // Writeback stage
    writeback wb_stage (
        .clk(clk), 
        .rd_W(rd_W),
        .stop(stop),
        .rst(rst),
        .r_wn(r_wn),
        .inst_MW(inst_MW), 
        .imm_W(imm_W),
        .alu_res_W(alu_res_W), 
        .rd_out(rd_WW),
        .mem_out_W(mem_out_W), 
        .pc_in(pc_M),
        .wd_val(wd_val)
    );

endmodule
