/*
top_test: CPCプロセッサ設計演習用テストベンチ

2024/04/03 多分完成している
2024/04/21 テスト完了
*/

`timescale 1ns/1ps

`include "top.v"

module top_test;
//パラメータの定義
parameter INTOTAL = 100000000;		// シミュレーションを中断するサイクル数
parameter CYCLE = 10;				// 1サイクルの時間（ns）
parameter HALF_CYCLE = CYCLE / 2;	// 1/2サイクル

//データ幅
parameter BYTE_SIZE = 8;
parameter HALF_SIZE = 16;
parameter WORD_SIZE = 32;
parameter MEMBLOCK_SIZE = 32; //メモリの最小アクセス単位

//メモリ関連
parameter MEM_SIZE 		= 32'h1000_0000; //メモリサイズ
parameter DMEM_LAT 		= 100;           //データ用メモリアクセスラインのレイテンシ
parameter IMEM_LAT 		= 100;           //命令用メモリアクセスラインのレイテンシ
parameter STDOUT_ADDR 	= 32'hf000_0000; //このアドレスに書き込まれたデータは標準出力される
parameter EXIT_ADDR 	= 32'hff00_0000; //このアドレスにアクセスがあるとシミュレーションが終了する

//キャッシュの設定
//ここでの設定はシミュレーションのみで有効
//論理合成でも適用したい場合はtopのパラメータ値を変更すること
parameter ICACHE_SIZE = 4096;
parameter ICACHE_ASSOC = 4;
parameter DCACHE_SIZE = 4096;
parameter DCACHE_ASSOC = 4;


//reg/wireの定義
reg clk, rst;


//メモリ関係
reg[WORD_SIZE-1:0]                  daddr, iaddr;   //内部処理用のアドレス保持レジスタ
reg                                 acki_n, ackd_n; //命令用ポート/データ用ポートのacknowledgement信号
wire[WORD_SIZE-1:0]                 iad;            //命令ポートアドレスライン
reg [MEMBLOCK_SIZE*BYTE_SIZE-1:0]   idt;            //命令ポートデータライン
wire[WORD_SIZE-1:0]                 dad;            //データポートアドレスライン
wire[MEMBLOCK_SIZE*BYTE_SIZE-1:0]   ddt;            //データポートデータライン
wire                                ireq, dreq;     //命令ポート/データポート要求信号
wire                                dwrite;         //データポート書き込み要求信号
reg [MEMBLOCK_SIZE*BYTE_SIZE-1:0]   memory[0:MEM_SIZE/MEMBLOCK_SIZE]; //メモリ

//割り込み関係
//現在未使用
wire     iack_n;
reg[2:0] oint_n;

//その他変数
integer i, j, k;
integer fp; //ダンプファイル用のファイルポインタ
integer cil, cdll, cdsl; //メモリのレイテンシを計算するための変数
integer accessed_addr;   //アクセスされた最大のアドレスを記憶
integer cycles;          //実行サイクル数を計算

//キャッシュの監視
integer icache_log_fp;
integer dcache_log_fp;   //ログファイルのファイルポインタ
integer icache_reqcnt, dcache_reqcnt;  //リクエストのあった回数
integer icache_readcnt, dcache_readcnt; //内読み出しリクエストの回数
integer icache_wrtcnt, dcache_wrtcnt;  //内書き込みリクエストの回数
integer icache_hitcnt, dcache_hitcnt;  //キャッシュヒットした回数
integer icache_misscnt, dcache_misscnt; //キャッシュミスした回数
wire icache_req, dcache_req;
wire icache_wrt, dcache_wrt;
wire icache_hit, dcache_hit;
wire[WORD_SIZE-1:0] icache_addr, dcache_addr; 
wire[3:0] icache_state, dcache_state;

assign icache_req = i_top.i_icache.creq;
assign dcache_req = i_top.i_dcache.creq;
assign icache_wrt = i_top.i_icache.cwrite;
assign dcache_wrt = i_top.i_dcache.cwrite;
assign icache_hit = i_top.i_icache.hit;
assign dcache_hit = i_top.i_dcache.hit;
assign icache_addr = i_top.i_icache.caddr;
assign dcache_addr = i_top.i_dcache.caddr;
assign icache_state = i_top.i_icache.state;
assign dcache_state = i_top.i_dcache.state;

top #(
	.ICACHE_SIZE(ICACHE_SIZE), .ICACHE_ASSOC(ICACHE_ASSOC), 
	.DCACHE_SIZE(DCACHE_SIZE), .DCACHE_ASSOC(DCACHE_ASSOC)
) i_top(
	//input
	.clk(clk), .rst(rst),
	.ackd_n(ackd_n), .acki_n(acki_n),
	.idt(idt), .oint_n(oint_n),

	//output
	.iad(iad), .dad(dad),
	.imreq(imreq),
	.dmreq(dmreq), .dmwrite(write),
	.iack_n(iack_n),

	//inout
	.ddt(ddt)
);

//クロックの生成
always begin
	clk = 1'b1;
	#(HALF_CYCLE) clk = 1'b0;
	#(HALF_CYCLE) cycles = cycles+1;
end

//初期化処理
initial begin
	//vcdファイル生成
	$dumpfile("wave.vcd");
	$dumpvars(0, i_top);
	//メモリファイルの読み込み
	$readmemh("./mem.dat", memory);
	//メインメモリアクセスの記録
	fp = $fopen("mem_log.dat");

	//内部信号のリセット
	oint_n = 3'b111;
	acki_n = 1'b1;
	ackd_n = 1'b1;
	cil = 0;
	cdll = 0;
	cdsl = 0;
	cycles = 0;

	//キャッシュ監視信号のリセット
	icache_log_fp = $fopen("icache_log.dat");
	dcache_log_fp = $fopen("dcache_log.dat");   //ログファイルのファイルポインタ
	icache_reqcnt = 0;
	dcache_reqcnt = 0;  //リクエストのあった回数
	icache_readcnt = 0;
	dcache_readcnt = 0; //内読み出しリクエストの回数
	icache_wrtcnt = 0;
	dcache_wrtcnt = 0;  //内書き込みリクエストの回数
	icache_hitcnt = 0;
	dcache_hitcnt = 0;  //キャッシュヒットした回数
	icache_misscnt = 0;
	dcache_misscnt = 0; //キャッシュミスした回数

	//リセット
	rst = 1'b1;
	#10 
	rst = 1'b0;
	#10
	rst = 1'b1;
end

//サイクル処理
initial begin
	#HALF_CYCLE;
	for(i = 0; i < INTOTAL; i = i+1) begin
		iaddr = iad;
		fetch_t;

		daddr = dad;
		load_t;
		store_t;

		#CYCLE
		release ddt;
	end

	$display("Reach INTOTAL (%d).", INTOTAL);
	dump_t;
	$finish;
	
end

//命令キャッシュの監視
always@(posedge clk) begin
	if(rst) begin
		if(icache_state == 4'b0000) begin
			if(icache_req) begin
				if(icache_wrt) begin
					if(icache_addr == STDOUT_ADDR) begin
						icache_reqcnt <= icache_reqcnt+1;
						icache_wrtcnt <= icache_wrtcnt+1;
						icache_misscnt <= icache_misscnt+1;
						$fwrite(icache_log_fp, "WRITE REQ (MISS) TIME=%d ADDR=%h (STDOUT)\n", cycles, icache_addr);
					end else if(icache_addr == EXIT_ADDR) begin
						icache_reqcnt <= icache_reqcnt+1;
						icache_wrtcnt <= icache_wrtcnt+1;
						icache_misscnt <= icache_misscnt+1;
						$fwrite(icache_log_fp, "WRITE REQ (MISS) TIME=%d ADDR=%h (EXIT)\n", cycles, icache_addr);
					end else if(icache_hit) begin
						icache_reqcnt <= icache_reqcnt+1;
						icache_wrtcnt <= icache_wrtcnt+1;
						icache_hitcnt <= icache_hitcnt+1;
						$fwrite(icache_log_fp, "WRITE REQ (HIT ) TIME=%d ADDR=%h\n", cycles, icache_addr);
					end
				end else begin
					if(icache_hit) begin
						icache_reqcnt <= icache_reqcnt+1;
						icache_readcnt <= icache_readcnt+1;
						icache_hitcnt <= icache_hitcnt+1;
						$fwrite(icache_log_fp, "READ  REQ (HIT ) TIME=%d ADDR=%h\n", cycles, icache_addr);
					end else begin
						icache_reqcnt <= icache_reqcnt+1;
						icache_readcnt <= icache_readcnt+1;
						icache_misscnt <= icache_misscnt+1;
						$fwrite(icache_log_fp, "READ  REQ (MISS) TIME=%d ADDR=%h\n", cycles, icache_addr);
					end
				end
			end
		end
	end
end


//データキャッシュの監視
always@(posedge clk) begin
	if(rst) begin
		if(dcache_state == 4'b0000) begin
			if(dcache_req) begin
				if(dcache_wrt) begin
					if(dcache_addr == STDOUT_ADDR) begin
						dcache_reqcnt <= dcache_reqcnt+1;
						dcache_wrtcnt <= dcache_wrtcnt+1;
						dcache_misscnt <= dcache_misscnt+1;
						$fwrite(dcache_log_fp, "WRITE REQ (MISS) TIME=%d ADDR=%h (STDOUT)\n", cycles, dcache_addr);
					end else if(dcache_addr == EXIT_ADDR) begin
						dcache_reqcnt <= dcache_reqcnt+1;
						dcache_wrtcnt <= dcache_wrtcnt+1;
						dcache_misscnt <= dcache_misscnt+1;
						$fwrite(dcache_log_fp, "WRITE REQ (MISS) TIME=%d ADDR=%h (EXIT)\n", cycles, dcache_addr);
					end else if(dcache_hit) begin
						dcache_reqcnt <= dcache_reqcnt+1;
						dcache_wrtcnt <= dcache_wrtcnt+1;
						dcache_hitcnt <= dcache_hitcnt+1;
						$fwrite(dcache_log_fp, "WRITE REQ (HIT ) TIME=%d ADDR=%h\n", cycles, dcache_addr);
					end
				end else begin
					if(dcache_hit) begin
						dcache_reqcnt <= dcache_reqcnt+1;
						dcache_readcnt <= dcache_readcnt+1;
						dcache_hitcnt <= dcache_hitcnt+1;
						$fwrite(dcache_log_fp, "READ  REQ (HIT ) TIME=%d ADDR=%h\n", cycles, dcache_addr);
					end else begin
						dcache_reqcnt <= dcache_reqcnt+1;
						dcache_readcnt <= dcache_readcnt+1;
						dcache_misscnt <= dcache_misscnt+1;
						$fwrite(dcache_log_fp, "READ  REQ (MISS) TIME=%d ADDR=%h\n", cycles, dcache_addr);
					end
				end
			end
		end
	end
end

//命令ラインの読み出し
task fetch_t; begin
	if(imreq) begin //命令のリクエストがあったら
		if(accessed_addr < iaddr) accessed_addr = iaddr; 
		cil = cil+1; //レイテンシを1加算
		if(cil == IMEM_LAT) begin //レイテンシが設定値を超えてたら読み出し完了
			idt = memory[iaddr>>$clog2(MEMBLOCK_SIZE)];
			acki_n = 1'b0;
			cil = 0;
			$fwrite(fp, "IMEM READ  REQ TIME=%d ADDR=%h\n", cycles, iaddr);
		end else begin
			idt = {MEMBLOCK_SIZE{1'bx}};
			acki_n = 1'b1;
		end
	end else begin
		acki_n = 1'b1;
		cil = 0;
	end
end
endtask

//データラインの読み出し
task load_t; begin
	if(dmreq && !write) begin
		if(accessed_addr < daddr) accessed_addr = daddr;

		cdll = cdll+1;

		if(cdll == DMEM_LAT) begin
			force ddt = memory[daddr>>$clog2(MEMBLOCK_SIZE)];
			ackd_n = 1'b0;
			cdll = 0;
			$fwrite(fp, "DMEM READ  REQ TIME=%d ADDR=%h\n", cycles, daddr);
		end else begin
			ackd_n = 1'b1;
		end
	end else begin
		cdll = 0;
	end
end
endtask

//データラインの書き込み
task store_t; begin
	if(dmreq && write) begin
		if(daddr == EXIT_ADDR) begin
			$display("\nExited by program at cycle-time %d.", cycles);
			$fwrite(icache_log_fp, "\n",
				"TOTAL ACCESS:     %d\n", icache_reqcnt, 
				"-----------------------------\n",
				"    READ  ACCESS: %d\n", icache_readcnt,
				"    WRITE ACCESS: %d\n", icache_wrtcnt,
				"    HIT         : %d\n", icache_hitcnt,
				"    MISS        : %d\n", icache_misscnt,
				"    MISS RATE   :    %f %%\n", 100*($itor(icache_misscnt)/$itor(icache_reqcnt)));
			$fwrite(dcache_log_fp, "\n",
				"TOTAL ACCESS:     %d\n", dcache_reqcnt,
				"-----------------------------\n",
				"    READ  ACCESS: %d\n", dcache_readcnt,
				"    WRITE ACCESS: %d\n", dcache_wrtcnt,
				"    HIT         : %d\n", dcache_hitcnt,
				"    MISS        : %d\n", dcache_misscnt,
				"    MISS RATE   :    %f %%\n", 100*($itor(dcache_misscnt)/$itor(dcache_reqcnt)));
			$fclose(icache_log_fp);
			$fclose(dcache_log_fp);
			dump_t;
			$finish;
		end else if (daddr != STDOUT_ADDR) begin
			if(accessed_addr < daddr) begin
				accessed_addr = daddr;
			end
		end

		cdsl = cdsl+1;

		if(cdsl == DMEM_LAT) begin
			if(daddr == STDOUT_ADDR) begin
				//$display("stdout %h", ddt);
				$write("%c", ddt[BYTE_SIZE-1:0]);
			end else begin
				memory[daddr>>$clog2(MEMBLOCK_SIZE)] = ddt;
				$fwrite(fp, "DMEM WRITE REQ TIME=%d ADDR=%h\n", cycles, iaddr);
			end

			ackd_n = 1'b0;
			cdsl = 0;
		end else begin
			ackd_n = 1'b1;
		end
	end else begin
		cdsl = 0;
	end
end
endtask

task dump_t; begin
	$fclose(fp);
	//メモリのダンプ
	fp = $fopen("./mem_dump.dat");
	for(i = 32'h0000_0000; i < 32'h0002_0000 && i < MEM_SIZE; i = i+1) begin
		$fwrite(fp, "%h: %h\n", i<<$clog2(MEMBLOCK_SIZE), memory[i]);
	end
	$fclose(fp);

	//命令キャッシュのダンプ
	fp = $fopen("./icache_dump.dat");
	for(i = 0; i < i_top.i_icache.assoc; i=i+1) begin
		$fwrite(fp, "#%3d \n", i);
		for(j = 0; j < i_top.i_icache.way_size; j=j+1) begin
			$fwrite(fp, "%h: tag=%h (%h) valid=%b dirty=%b lu=%d data= ", j, i_top.i_icache.tag[j][i], {i_top.i_icache.tag[j][i], j[$clog2(ICACHE_SIZE/ICACHE_ASSOC)-1:0], {5{1'b0}}}, i_top.i_icache.valid[j][i], i_top.i_icache.dirty[j][i], i_top.i_icache.last_access[j][i]);
			for(k = 0; k < i_top.i_icache.block_size; k=k+1) begin
				$fwrite(fp, "%h ", i_top.i_icache.data[k][j][i]);
			end
			$fwrite(fp, "\n");
		end
		$fwrite(fp, "\n");
	end

	//データキャッシュのダンプ
	fp = $fopen("./dcache_dump.dat");
	for(i = 0; i < i_top.i_dcache.assoc; i=i+1) begin
		$fwrite(fp, "#%3d \n", i);
		for(j = 0; j < i_top.i_dcache.way_size; j=j+1) begin
			$fwrite(fp, "%h: tag=%h (%h) valid=%b dirty=%b lu=%d data= ", j, i_top.i_dcache.tag[j][i], {i_top.i_dcache.tag[j][i], j[$clog2(DCACHE_SIZE/DCACHE_ASSOC)-1:0], {5{1'b0}}}, i_top.i_dcache.valid[j][i], i_top.i_dcache.dirty[j][i], i_top.i_dcache.last_access[j][i]);
			for(k = 0; k < i_top.i_dcache.block_size; k=k+1) begin
				$fwrite(fp, "%h ", i_top.i_dcache.data[k][j][i]);
			end
			$fwrite(fp, "\n");
		end
		$fwrite(fp, "\n");
	end

	//レジスタのダンプ
	fp = $fopen("./reg_dump.dat");
	for(i = 0; i < 32; i = i+4) begin
		$fwrite(
			fp, 
			"%d:%h %d:%h %d:%h %d:%h\n", 
			i, i_top.i_core.i_regfile.registers[i], 
			i+1, i_top.i_core.i_regfile.registers[i+1], 
			i+2, i_top.i_core.i_regfile.registers[i+2], 
			i+3, i_top.i_core.i_regfile.registers[i+3]
		);
	end
	$fclose(fp);
end endtask
endmodule