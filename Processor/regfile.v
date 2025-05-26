/*
regfile: レジスタファイル
  入力:
    clk: クロック （1ビット）
    rst: リセット（1ビット）
    write_n: 書き込み有効化（1ビット）
    rd: 書き込みレジスタアドレス（ceil(log2(reg_num)ビット）
    in: 書き込みデータ（data_widthビット）
    rs1, rs2: 読み出しレジスタアドレス（ceil(log2(reg_num)ビット）
  出力:
    out1, out2: 読み出しデータ（data_widthビット）
  パラメータ:
    data_width: レジスタのデータ幅
    reg_num: レジスタの本数
    zeroreg: ゼロレジスタを有効にするかどうか（1:有効 0:無効）

  使用例:
  1. RV32I用のレジスタ（32ビット32本ゼロレジスタあり） （既定値）
  regfile#(.data_width(32), .reg_num(32), .zeroreg(1)) rf(.clk(clk), .rst(rst), ...
  
  2. RVD（倍精度浮動小数点数演算拡張）用のレジスタ（64ビット32本ゼロレジスタなし）
  regfile#(.data_width(64), .reg_num(32), .zeroreg(0)) frf(.clk(clk), ...

2024/04/03 たぶん完成している（一応確認済）
*/

`ifndef REGFILE_V
`define REGFILE_V
module regfile #(
    parameter data_width = 32,
    parameter reg_num = 32,
    parameter addr_width = $clog2(reg_num),
    parameter zeroreg = 1
)(
    input clk, input rst, input write_n,
    input[addr_width-1:0] rs1, input[addr_width-1:0] rs2, input[addr_width-1:0] rd,
    input[data_width-1:0] in,
    output[data_width-1:0] out1, output[data_width-1:0] out2
);
    integer i;
    reg[data_width-1:0] registers[0:reg_num];
    
    //ゼロレジスタ対応の場合分け
    generate 
        if(zeroreg) begin
            assign out1 = rs1 == 0 ? 0 : registers[rs1];
            assign out2 = rs2 == 0 ? 0 : registers[rs2];
        end else begin
            assign out1 = registers[rs1];
            assign out2 = registers[rs2];
        end    
    endgenerate

    always@(posedge clk, negedge rst)begin
        if(!rst) begin
            for(i = 0; i < reg_num; i = i+1)begin
                registers[i] <= 0;
            end
        end else if(!write_n) begin
            for(i = 0; i < reg_num; i = i+1)begin
                registers[i] <= rd == i ? in : registers[i];
            end
        end else begin
            for(i = 0; i < reg_num; i = i+1)begin
                registers[i] <= registers[i];
            end
        end
    end
    
endmodule
`endif //REGFILE_V