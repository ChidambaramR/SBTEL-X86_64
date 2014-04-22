// Refer to slide 11 of 43 in CSE502-L4-Pipelining.pdf
typedef struct packed {
    // PC + 1
    logic [0:63] pc_contents;
    // ALU Result
    logic [0:63] alu_result;
    logic [0:63] alu_ext_result;
    // REGB Contents
    logic [0:63] data_regB;
    // Control signals
    logic [0:63] data_disp;
    logic [0:63] data_imm;
    logic [0:7]  ctl_opcode;
    logic [0:3]  ctl_regByte;
    logic [0:3]  ctl_rmByte;
    logic sim_end;
} EX_WB;

module mod_writeback (
        input can_writeback,
        input EX_WB exwb,
        output [0:63] regfile[0:16-1],
        output [0:1]  dep_exwb
);

always_comb begin
    if (can_writeback) begin : writeback_block
        if(exwb.ctl_opcode == 247) begin
            regfile[0] = exwb.alu_result;
            regfile[2] = exwb.alu_ext_result;
        end
        else begin
            regfile[exwb.ctl_rmByte] = exwb.alu_result;
        end
        dep_exwb = 0;
        //$display("Issuing writeback");
        if(exwb.sim_end == 1)
            $finish;
    end
end

endmodule
