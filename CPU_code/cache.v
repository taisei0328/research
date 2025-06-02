/*
cache: キャッシュ
  ライトバック方式のキャッシュ

2024/04/03 多分完成
2024/04/21 テスト完了
*/

//マクロ
`define SIZE_BYTE 	2'b00
`define SIZE_HALF 	2'b01
`define SIZE_WORD 	2'b10
`define SIZE_DWORD 	2'b11

`define BYTE 8
`define HALF 16
`define WORD 32
`define DWORD 64

module cache#(
	parameter mdata_width = 256,	//メモリデータラインのビット幅
	parameter cdata_width = 32,		//キャッシュデータラインのビット幅（32ビットか64ビット）
	parameter addr_width = 32,		//アドレスのビット幅
	parameter cache_size = 16384,	//キャッシュの容量（バイト単位）
	parameter block_size = 32,		//ブロックサイズ（バイト単位）
	parameter assoc = 4,			//キャッシュの連想度
	parameter stdout_addr = 32'hf000_0000,	//標準出力のアドレス
	parameter exit_addr = 32'hff00_0000,	//終了アドレス
//	parameter log_filename = "cachelog.dat",
	//以下のパラメータは変更を想定していない
	parameter byte_width = 8,												//1バイトのビット幅（8のみ対応）
	parameter way_size = cache_size/assoc,									//1ウェイの容量（キャッシュ容量/連想度）
	parameter index_width = $clog2(way_size),								//インデックスのビット幅
	parameter tag_width = addr_width - $clog2(block_size) - index_width,	//タグのビット幅
	parameter implicit_width = addr_width - index_width - tag_width,		//アドレスのうちメモリアクセスで必ず0となる部分（暗黙部分）のビット幅
	parameter tag_msb = addr_width - 1,										//タグ部分のMSB
	parameter index_msb = tag_msb - tag_width,								//インデックス部分のMSB
	parameter implicit_msb = index_msb - index_width,						//暗黙部分のMSB
	parameter implicit_lsb = 0,												//暗黙部分のLSB
	parameter index_lsb = implicit_lsb + implicit_width,					//インデックス部分のLSB
	parameter tag_lsb = index_lsb + index_width,							//タグ部分のLSB
	parameter way_entry = way_size/block_size								//ウェイあたりのブロック数
)(
	input clk, input rst,				// クロックとリセット
	input creq,							// キャッシュアクセス要求（書き込み or 読み出し）
	input cwrite,						// キャッシュ書き込み要求
	input[addr_width-1:0] caddr,		// キャッシュアクセスアドレス
	input[1:0] csize,					// 読み書きサイズ
	input ackm_n,						// メモリacknowledgement
	output reg[addr_width-1:0] maddr, 	// メモリアクセスアドレス
	output reg mreq, output reg mwrite,	// メモリアクセス要求/書き込み要求
	output ready_n,						// キャッシュ読み出し完了（caddrに指定されたアドレスのデータがcdataに出力されている）
	output busy,						// キャッシュ処理中（アクセス等を受け付けない状態）
	inout[mdata_width-1:0] mdata,		// メモリアクセス用データライン
	inout[cdata_width-1:0] cdata		// キャッシュアクセス用データライン
);
	genvar i, j;
	integer k, l;

	//LRU方式のための計時カウンタ
	reg[31:0] 				timer;

	//キャッシュの状態を表す
	reg[3:0] 				state;

	//キャッシュの本体
	reg[byte_width-1:0] 	data		[0:block_size-1][0:way_size-1][0:assoc-1];
	reg[tag_width-1:0] 		tag			[0:way_size-1][0:assoc-1];
	reg 					valid		[0:way_size-1][0:assoc-1];
	reg[31:0] 				last_access	[0:way_size-1][0:assoc-1];
	reg 					dirty 		[0:way_size-1][0:assoc-1];


	wire								hit;
	wire[$clog2(assoc)-1:0] 			way_hit;
	wire[assoc-1:0] 					way_hit_one_hot;
	wire[cdata_width-1:0] 				cout;
	wire[byte_width-1:0] 				cin[0:cdata_width/byte_width-1];
	reg [addr_width-1:0] 				addr_reg;
	reg [1:0]							csize_reg;
	reg [byte_width-1:0] 				cin_reg[0:cdata_width/byte_width-1];
	wire[mdata_width-1:0] 				to_mem;
	reg [byte_width-1:0]				to_mem_tmp[0:block_size-1];
	wire[byte_width-1:0]				from_mem[0:block_size-1];

	//デバッグ用
	`ifdef DEBUG
	generate
		wire[assoc-1:0] d_valid;
		wire[index_width-1:0] d_index;
		wire[31:0] d_tmp;
		for(i = 0; i < assoc; i=i+1) begin
			assign d_valid = valid[1][i];
			assign d_index = caddr[index_msb:index_lsb];
			assign d_tmp = way_size;
		end
	endgenerate
	initial begin
		//$monitor("cdata=%h cout=%h", cdata, cout);
	end
	`endif //DEBUG

	//Least Recently Used: LRU のために使う変数
	reg [$clog2(assoc)-1:0] 			lru;
	reg [31:0] 							lru_time;
	reg [$clog2(assoc):0]				lru_count;

	//終了処理に使う変数
	reg [31:0] way_wb, index_wb;

	assign hit = creq && |way_hit_one_hot;
	assign ready_n = cwrite || !hit || busy;
	assign busy  = |state;
	assign mdata = mwrite ? to_mem : {mdata_width{1'bz}};
	
	// cdataにcoutをassign
	generate
		if(cdata_width == 64) begin
			assign cdata = cwrite ? {cdata_width{1'bz}} : 
				csize == `SIZE_BYTE  ? cout[`BYTE-1:0] : 
				csize == `SIZE_HALF  ? cout[`HALF-1:0] : 
				csize == `SIZE_WORD  ? cout[`WORD-1:0] : 
				csize == `SIZE_DWORD ? cout : {cdata_width{1'bz}};
		end else if(cdata_width == 32) begin
			assign cdata = cwrite ? {cdata_width{1'bz}} : 
				csize == `SIZE_BYTE  ? cout[`BYTE-1:0] : 
				csize == `SIZE_HALF  ? cout[`HALF-1:0] : 
				csize == `SIZE_WORD  ? cout : {cdata_width{1'bz}};
		end else begin
			initial begin
				$display("ERROR: Parameter cdata_width=%d is not allowed. Only 32-bit or 64-bit is supported currently.", cdata_width);
				$finish;
			end
		end
	endgenerate


	generate
		if(byte_width != 8) begin
			initial begin
				$display("ERROR: Parameter byte_width=%d is not allowed. Only 8-bit is supported currently.", byte_width);
				$finish;
			end
		end else if(mdata_width/byte_width != block_size) begin
			initial begin
				$display("ERROR: The combination of parameter mdata_width=%d and parameter block_size=%d is not allowed. Two parameters must be the same bit-width currently.", mdata_width, block_size);
				$finish;
			end
		end
	endgenerate
	
	generate
	//キャッシュヒットの判定
	//非同期
		for(i = 0; i < assoc; i = i+1) begin
			assign way_hit_one_hot[i] = valid[caddr[index_msb:index_lsb]][i] && (tag[caddr[index_msb:index_lsb]][i] == caddr[tag_msb:tag_lsb]);
		end
		oh2bin#(.oh_width(assoc), .bin_width($clog2(assoc))) way_hit_oh2bin(.oh(way_hit_one_hot), .bin(way_hit));

	//読み出し
	//非同期
		for(i = 0; i < cdata_width/byte_width; i = i+1) begin
			assign cout[(i+1)*byte_width-1:i*byte_width] = data[caddr[implicit_msb:implicit_lsb]+i][caddr[index_msb:index_lsb]][way_hit];
		end
	//書き込みのために入力データをバイト単位にばらす
		for(i = 0; i < cdata_width/byte_width; i = i+1) begin
			assign cin[i] = cdata[(i+1)*byte_width-1:i*byte_width];
		end
	//メモリからのデータをバイト単位にばらす
		for(i = 0; i < block_size; i = i+1) begin
			assign from_mem[i] = mdata[ mdata_width - i*byte_width - 1 : mdata_width - (i+1)*byte_width ];
		end
	//ばらされているデータをまとめる
		for(i = 0; i < block_size; i = i+1) begin
			assign to_mem[ mdata_width - i*byte_width - 1 : mdata_width - (i+1)*byte_width ] = to_mem_tmp[i];
		end
	endgenerate

	//timerの更新
	always@(posedge clk or negedge rst) begin
		if(!rst) begin
			timer <= 0;
		end else begin
			timer <= timer+1;
		end
	end

	//キャッシュのメイン処理
	//  待機 (state = 0)
	//  + (書き込み要求)
	//    + (通常アドレス)
	//      + (キャッシュヒット) -> キャッシュ書き込み
	//      + (キャッシュミス)
	//        + 追い出しブロックの決定フェーズ (state = 1001)
	//          + (dirtyビットが立っている) -> ブロックをメモリへ書き込み -> 書き込み待ち (state = 1010) -> メモリ読み出し -> 読み出し待ち (state = 1100) -> キャッシュ書き込み
	//          + (dirtyビットが立っていない) -> メモリ読み出し -> 読み出し待ち (state = 1100) -> キャッシュ書き込み
	//    + (stdaddrアドレス)
	//      + cdataをメモリへ書き込み -> 書き込み待ち (state = 1011)
	//    + (exitアドレス)
	//      + 全てのブロックをメモリへ書き込み (state = 0111)
	//  + (読み出し要求)
	//    + (キャッシュヒット) -> キャッシュ読み出し
	//    + (キャッシュミス)
	//      + 追い出しブロックの決定フェーズ (state = 0001)
	//        + (dirtyビットが立っている) -> ブロックをメモリへ書き込み -> 書き込み待ち (state = 0010) -> メモリ読み出し -> 読み出し待ち (state = 0100) -> キャッシュ読み出し
	//        + (dirtyビットが立っていない) -> メモリ読み出し -> 読み出し待ち (state = 0100) -> キャッシュ読み出し
	always@(posedge clk or negedge rst) begin
		if(!rst) begin
			state <= 4'b0;
			mreq <= 0;
			mwrite <= 0;
			for(k = 0; k < assoc; k = k+1) begin
				for(l = 0; l < way_size; l = l+1) begin
					valid[l][k] <= 0;
					dirty[l][k] <= 0;
					tag[l][k] <= 0;
					last_access[l][k] <= 0;
				end
			end
		end else begin
			casez(state)
				4'b0000: //待機
				if(creq) begin
					if(cwrite) begin //書き込み要求
						if(caddr == stdout_addr) begin //標準出力の場合
							for(k = 0; k < block_size; k = k+1) begin
								to_mem_tmp[k] <= k == block_size-1 ? cin[0] : 0;
							end
							mwrite <= 1;
							mreq <= 1;
							maddr <= stdout_addr;
							state <= 4'b0011; //直接書き込み待ち
						end else if(caddr == exit_addr) begin
							//終了処理
							//dirtyビットが立っている全てのブロックを書き戻し
							way_wb <= 0;
							index_wb <= 0;
							state <= 4'b1110; //終了処理
						end else if(hit) begin
							// 最終アクセスを更新
							last_access[caddr[index_msb:index_lsb]][way_hit] <= timer;
							dirty[caddr[index_msb:index_lsb]][way_hit] <= 1;
							// 書き込み
							case(csize)
								`SIZE_BYTE : for(k = 0; k < 1; k = k+1) begin
									data[caddr[implicit_msb:implicit_lsb]+k][caddr[index_msb:index_lsb]][way_hit] <= cin[k];
								end
								`SIZE_HALF : for(k = 0; k < 2; k = k+1) begin
									data[caddr[implicit_msb:implicit_lsb]+k][caddr[index_msb:index_lsb]][way_hit] <= cin[k];
								end
								`SIZE_WORD : for(k = 0; k < 4; k = k+1) begin
									data[caddr[implicit_msb:implicit_lsb]+k][caddr[index_msb:index_lsb]][way_hit] <= cin[k];
								end
								`SIZE_DWORD: for(k = 0; k < 8; k = k+1) begin
									data[caddr[implicit_msb:implicit_lsb]+k][caddr[index_msb:index_lsb]][way_hit] <= cin[k];
								end
							endcase
						end else begin
							//プロセッサが他のことをできるようにデータとアドレスを保持
							for(k = 0; k < cdata_width/byte_width; k = k+1) begin
								cin_reg[k] <= cin[k];
							end
							addr_reg <= caddr;
							csize_reg <= csize;
							state <= 4'b1001;
							lru <= 0;
							lru_count <= 0;
							lru_time <= timer;
						end
					end else begin //読み出し要求
						if(hit) begin
							last_access[caddr[index_msb:index_lsb]][way_hit] <= timer;
						end else begin //キャッシュミスの場合
							//プロセッサが他のことをできるようにデータとアドレスを保持
							for(k = 0; k < cdata_width/byte_width; k = k+1) begin
								cin_reg[k] <= cin[k];
							end
							addr_reg <= caddr;
							csize_reg <= csize;
							state <= 4'b0001;
							lru <= 0;
							lru_count <= 0;
							lru_time <= timer;
						end
					end
				end
				4'bz001: //追い出しブロック検索
				if(lru_count < assoc) begin
					lru_count <= lru_count+1;
					if(last_access[caddr[index_msb:index_lsb]][lru_count] < lru_time) begin
						lru <= lru_count;
						lru_time <= last_access[caddr[index_msb:index_lsb]][lru_count];
					end
				end else begin
					if(dirty[caddr[index_msb:index_lsb]][lru]) begin //dirtyビットが立っていたら
						mreq <= 1;
						mwrite <= 1;
						maddr <= {tag[addr_reg[index_msb:index_lsb]][lru], addr_reg[index_msb:index_lsb], {implicit_width{1'b0}}};
						for(k = 0; k < block_size; k = k+1) begin
							to_mem_tmp[k] <= data[k][addr_reg[index_msb:index_lsb]][lru];
						end
						state <= {state[3], 3'b010}; //メモリ書き込み待ちへ
					end else begin //それ以外なら
						mwrite <= 0;
						mreq <= 1;
						maddr <= addr_reg & {{(addr_width-implicit_width){1'b1}}, {(implicit_width){1'b0}}};
						state <= {state[3], 3'b100}; //メモリ読み出し待ちへ
					end
				end
				4'bz010: //メモリ書き込み待ち
					if(!ackm_n) begin //書き込みが完了したら
						mwrite <= 0;
						mreq <= 1;
						maddr <= addr_reg & {{(addr_width-implicit_width){1'b1}}, {(implicit_width){1'b0}}};
						state <= {state[3], 3'b100}; //読み出し待ちへ
					end
				4'bz100: //メモリ読み出し待ち
					if(!ackm_n) begin //読み出しが完了したら
						mreq <= 0;
						//penalty <= penalty+timer;
						//データをキャッシュに書き込み
						for(k = 0; k < block_size; k = k+1) begin
							data[k][addr_reg[index_msb:index_lsb]][lru] <= from_mem[k];
						end
						//validビットをセット
						valid[addr_reg[index_msb:index_lsb]][lru] <= 1;
						//tagを変更
						tag[addr_reg[index_msb:index_lsb]][lru] <= addr_reg[tag_msb:tag_lsb];
						//last_accessを変更
						last_access[addr_reg[index_msb:index_lsb]][lru] <= timer;
						state <= {state[3], 3'b000};
					end
				4'b1000: begin //キャッシュへ書き込み
					// 最終アクセスを更新
					last_access[addr_reg[index_msb:index_lsb]][lru] <= timer;
					dirty[addr_reg[index_msb:index_lsb]][lru] <= 1;
					state <= 4'b0000;
					// 書き込み
					case(csize_reg)
						`SIZE_BYTE: for(k = 0; k < 1; k = k+1) begin
							data[addr_reg[implicit_msb:implicit_lsb]+k][addr_reg[index_msb:index_lsb]][lru] <= cin_reg[k];
						end
						`SIZE_HALF: for(k = 0; k < 2; k = k+1) begin
							data[addr_reg[implicit_msb:implicit_lsb]+k][addr_reg[index_msb:index_lsb]][lru] <= cin_reg[k];
						end
						`SIZE_WORD: for(k = 0; k < 4; k = k+1) begin
							data[addr_reg[implicit_msb:implicit_lsb]+k][addr_reg[index_msb:index_lsb]][lru] <= cin_reg[k];
						end
						`SIZE_DWORD: for(k = 0; k < 8; k = k+1) begin
							data[addr_reg[implicit_msb:implicit_lsb]+k][addr_reg[index_msb:index_lsb]][lru] <= cin_reg[k];
						end
					endcase
				end
				4'b0011: //直接書き込み待ち
				if(!ackm_n) begin
					mwrite <= 0;
					mreq <= 0;
					state <= 4'b0000;
				end
				4'b1110: //終了処理1
				if(index_wb < way_size) begin //全てのindexを見る
					if(way_wb < assoc) begin //全てのwayを見る
						if(dirty[index_wb][way_wb]) begin
							way_wb <= way_wb+1;
							mwrite <= 1;
							mreq <= 1;
							maddr <= {tag[index_wb][way_wb], index_wb[index_width-1:0], {implicit_width{1'b0}}};
							for(k = 0; k < block_size; k = k+1) begin
								to_mem_tmp[k] <= data[k][index_wb][way_wb];
							end
							state <= 4'b1111; //終了処理2へ
						end
						way_wb <= way_wb+1;
					end else begin //wayを見終わったら次のindexへ
						way_wb <= 0;
						index_wb <= index_wb+1;
					end
				end else begin //全てのindexを見終わったら終了
					for(k = 0; k < block_size; k = k+1) begin
						to_mem_tmp[k] <= 0;
					end
					mwrite <= 1;
					mreq <= 1;
					maddr <= exit_addr;
					state <= 4'b0011; //直接書き込み待ち
				end
				4'b1111: //終了処理2 書き込み待ち
				if(!ackm_n) begin
					state <= 4'b1110;
					mwrite <= 0;
					mreq <= 0;
				end
			endcase
		end
	end
endmodule

module oh2bin #(
	parameter oh_width = 32,
	parameter bin_width = 5
)(
	input[oh_width-1:0]   oh,
	output[bin_width-1:0] bin
);
	genvar i;

	generate
		if(oh_width == 2) begin
			assign bin = oh == 2'b10 ? 1 : 0;
		end else begin
			wire[(oh_width>>1)-1:0] oh_u, oh_d;
			wire[bin_width-2:0] bin_u, bin_d;
			assign oh_u = oh[oh_width-1:oh_width/2];
			assign oh_d = oh[oh_width/2-1:0];
			assign bin = {oh_u ? 1'b1 : 1'b0, {oh_u ? bin_u : bin_d}};
			oh2bin#(.oh_width(oh_width>>1), .bin_width(bin_width-1)) oh2bin_u(.oh(oh_u), .bin(bin_u));
			oh2bin#(.oh_width(oh_width>>1), .bin_width(bin_width-1)) oh2bin_d(.oh(oh_d), .bin(bin_d));
		end
	endgenerate

endmodule