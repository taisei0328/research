`ifndef HAZARD_UNIT_V
`define HAZARD_UNIT_V

module hazard_unit (
    input [4:0] rd_E,
    input [4:0] rd_M,
    input [4:0] rs1_D,
    input [4:0] rs2_D,
    input [1:0] mem_command_M,
    input jump,
    
    output wb_pc_f_hazard,
    output F_bubble,
    output D_bubble,
    output E_bubble
);

    wire wb_pc_f_hazard_id_ex = 
    ((rd_E == rs1_D && rs1_D != 0) || (rd_E== rs2_D && rs2_D != 0)) &&
    (rd_E != 5'b0) ;

    wire wb_pc_f_hazard_id_mem = (((rd_M == rs1_D) |
    (rd_M == rs2_D)) & (rd_M != 5'b0) ) ;

    assign  wb_pc_f_hazard = wb_pc_f_hazard_id_ex | wb_pc_f_hazard_id_mem;
    
    assign F_bubble = wb_pc_f_hazard || jump ;
    assign D_bubble = wb_pc_f_hazard  || jump;
    assign E_bubble = jump; // ジャンプ時は Execute フラッシュ
    

endmodule

`endif
