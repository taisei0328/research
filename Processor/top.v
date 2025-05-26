/*
top.v

コアとキャッシュを結ぶ
*/

`include "regfile.v"
`include "cache.v"
`include "core2.v" //ここを自分が作ったコアのファイル名に変更する

module top#(
	parameter BYTE_SIZE = 8,
	parameter HALF_SIZE = 16,
	parameter WORD_SIZE = 32,
	parameter DMEMBUS_SIZE = 256,
	parameter IMEMBUS_SIZE = 256,
	parameter ICACHE_SIZE = 4096,
	parameter ICACHE_ASSOC = 4,
	parameter DCACHE_SIZE = 4096,
	parameter DCACHE_ASSOC = 4
)(
	input clk, input rst,
	input ackd_n, input acki_n,
	input[IMEMBUS_SIZE-1:0] idt,
	input[2:0] oint_n,

	output[WORD_SIZE-1:0] iad,
	output[WORD_SIZE-1:0] dad,
	output imreq, output dmreq,
	output dmwrite,
	output iack_n,

	inout[DMEMBUS_SIZE-1:0] ddt
);

	wire[WORD_SIZE-1:0] daddr, iaddr;
	wire[WORD_SIZE-1:0] ddata, idata;
	wire[1:0] dsize;
	wire dreq, dwrite, dready_n, dbusy;
	wire iready_n;

	//未使用ワイヤ
	wire imwrite, ibusy;

	//設計したプロセッサコア
	core i_core(
		.clk(clk), .rst(rst), //クロックとリセット(1-bit)
		
		//命令キャッシュ系
		.iaddr(iaddr), //命令メモリのアクセスするアドレス (32-bit)
		.iready_n(iready_n), //命令キャッシュの読み出しが完了(1-bit)
		.idata(idata), //読み出された命令 (32-bit)

		//データキャッシュ系
		.daddr(daddr), //データメモリのアクセスするアドレス (32-bit)
		.dreq(dreq), //データキャッシュ読み書き要求 (1-bit)
		.dwrite(dwrite), //データキャッシュ書き込み要求 (1-bit)
		.dsize(dsize), //データキャッシュに読み書きするサイズ（2-bit 00:byte 01:half 10:word 11:double word)
		.dready_n(dready_n), //データキャッシュ読み出し完了 (1-bit)
		.dbusy(dbusy), //キャッシュがメモリへアクセスを行っていて他の要求を受けることができない状態 (1-bit)
		.ddata(ddata), //読み出されたデータ (32-bit)

		//割り込み系
		.oint_n(oint_n), //割り込み 3つのビットそれぞれが1つの理由による割り込みを担当 立ち下がったらその理由による割り込みがあったことを示す (3-bit)
		.iack_n(iack_n) //割り込み許可 立ち上がっている場合は割り込みを許可 (1-bit)
	);

	//命令キャッシュ
	cache#(.cdata_width(32), .cache_size(ICACHE_SIZE), .assoc(ICACHE_ASSOC)) i_icache(
		.clk(clk), .rst(rst),
		.creq(1'b1), .cwrite(1'b0), //読み出し固定
		.caddr(iaddr), .csize(2'b10), //サイズはワード固定
		.ackm_n(acki_n),
		.maddr(iad), .mreq(imreq), .mwrite(imwrite),
		.ready_n(iready_n), .busy(ibusy),
		.mdata(idt), .cdata(idata)
	);
	//データキャッシュ
	cache#(.cdata_width(32), .cache_size(DCACHE_SIZE), .assoc(DCACHE_ASSOC)) i_dcache(
		.clk(clk), .rst(rst),
		.creq(dreq), .cwrite(dwrite), 
		.caddr(daddr), .csize(dsize),
		.ackm_n(ackd_n),
		.maddr(dad), .mreq(dmreq), .mwrite(dmwrite),
		.ready_n(dready_n), .busy(dbusy),
		.mdata(ddt), .cdata(ddata)
	);
endmodule