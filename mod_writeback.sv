// Refer to slide 11 of 43 in CSE502-L4-Pipelining.pdf
typedef struct packed {
    // PC + 1
    logic [0:63] pc_contents;
    // ALU Result
    logic [0:63] alu_result;
    logic [0:63] alu_ext_result;
    // Control signals
    logic [0:7]  ctl_opcode;
    logic [0:3]  ctl_regByte;
    logic [0:3]  ctl_rmByte;
    logic sim_end;
} EX_WB;

module mod_writeback (
    input can_writeback,
    /* verilator lint_off UNUSED */
    input EX_WB exwb,
    input store_memstage_active,
    output [0:63] regfile[0:16-1],
    output [0:1]  dep_exwb,
    output store_writebackFlag
);

always_comb begin
    if (can_writeback) begin : writeback_block
        if (exwb.ctl_opcode == 247) begin
            regfile[0] = exwb.alu_result;
            regfile[2] = exwb.alu_ext_result;
        end

        else if (exwb.ctl_opcode == 255 || exwb.ctl_opcode == 232) begin
            regfile[4] = regfile[4] - 8;
            store_writebackFlag = 1;
        end

        else if ((exwb.ctl_opcode >= 80) && (exwb.ctl_opcode <= 95)) begin
            // PUSH / POP instruction
            if(exwb.ctl_opcode >= 88) begin
                // POP
                //$write("POP");
                regfile[4] = regfile[4] + 8;
                regfile[exwb.ctl_rmByte] = exwb.alu_result;
                //$finish;
            end
            else begin
                // PUSH
              $write("PUSH");
              regfile[4] = regfile[4] - 8;
              store_writebackFlag = 1;
              $finish;
            end
        end

        else if (exwb.ctl_opcode == 137 && store_memstage_active) begin
            //$write("here!! wr opcode = %x", exwb.ctl_opcode);
            // STORE INS
            store_writebackFlag = 1;
        end
        else if (exwb.ctl_opcode == 139) begin
            // LOAD INS
            regfile[exwb.ctl_regByte] = exwb.alu_result;
        end
        else begin
            regfile[exwb.ctl_rmByte] = exwb.alu_result;
            //$write("Writing %0h into %0h",exwb.alu_result, exwb.ctl_rmByte);
        end
        dep_exwb = 0;
        //$display("Issuing writeback");
        if (exwb.sim_end == 1)
            $finish;
    end
end

endmodule
