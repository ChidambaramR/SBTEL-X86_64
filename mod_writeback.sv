/* Writeback-Stage Module */

module mod_writeback (
    input can_writeback,
    /* verilator lint_off UNUSED */
    input EX_WB exwb,
    input store_memstage_active,
    input end_prog,

    output [0:63] regfile[0:16-1],
    output [0:1]  dep_exwb,
    output store_writebackFlag
);

// Refer to slide 11 of 43 in CSE502-L4-Pipelining.pdf
typedef struct packed {
    // PC + 1
    logic [0:63] pc_contents;
    // ALU Result
    logic [0:63] alu_result;
    logic [0:63] alu_ext_result;
    // Control signals
    logic [0:7]  ctl_opcode;
    logic        twob_opcode; 
    logic [0:3]  ctl_regByte;
    logic [0:3]  ctl_rmByte;
    logic sim_end;
    logic [0:1] mod;
} EX_WB;

always_comb begin
    if (can_writeback) begin : writeback_block
        if (exwb.sim_end == 1)
            $finish;

        if (exwb.ctl_opcode == 144) begin
            // Do nothing
        end

        else if ((exwb.ctl_opcode == 247) || ((memex.ctl_opcode == 175) && (memex.twob_opcode == 1))) begin
            //IMUL
            if(exwb.ctl_opcode == 247)
                regfile[0] = exwb.alu_result;
            else
                regfile[exwb.ctl_regByte] = exwb.alu_result;
            if (exwb.alu_ext_result != 0)
                regfile[2] = exwb.alu_ext_result;
        end

        else if(exwb.ctl_opcode == 5) begin
            regfile[0] = exwb.alu_result;
        end

        else if (exwb.ctl_opcode == 255 || exwb.ctl_opcode == 232) begin
            regfile[4] = regfile[4] - 8;
            store_writebackFlag = 1;
        end

        else if (exwb.ctl_opcode == 195 && end_prog) begin
            // RETQ
            regfile[4] = regfile[4] + 8;
        end

        else if (exwb.ctl_opcode == 195 && !end_prog) begin
            // RETQ without CallQ. Do nothing
        end

        else if(exwb.twob_opcode == 1) begin
            // Do nothing when a branch is not taken
        end

        else if(exwb.ctl_opcode == 193) begin
            regfile[exwb.ctl_rmByte] = exwb.alu_result;
        end

        else if ((exwb.ctl_opcode >= 80) && (exwb.ctl_opcode <= 95)) begin
            // PUSH / POP instruction
            if(exwb.ctl_opcode >= 88) begin
                // POP
                regfile[4] = regfile[4] + 8;
                regfile[exwb.ctl_rmByte] = exwb.alu_result;
            end
            else begin
                // PUSH
                regfile[4] = regfile[4] - 8;
                store_writebackFlag = 1;
            end
        end

        else if (exwb.ctl_opcode == 137 && store_memstage_active && exwb.mod !=3) begin
            // STORE INS
            store_writebackFlag = 1;
        end
        
        else if (exwb.ctl_opcode == 137 && exwb.mod == 3) begin
            regfile[exwb.ctl_rmByte] = exwb.alu_result;
        end

        else if (exwb.ctl_opcode == 139 || (exwb.ctl_opcode == 141 && !exwb.twob_opcode)) begin
            // LOAD INS
            regfile[exwb.ctl_regByte] = exwb.alu_result;
        end
        else if ((exwb.ctl_opcode >= 184) && (exwb.ctl_opcode <= 191)) begin
             regfile[exwb.ctl_rmByte] = exwb.alu_result;
        end
        else if (exwb.ctl_opcode == 57) begin
            // Do nothing for CMP instruction
        end
        else begin
            regfile[exwb.ctl_rmByte] = exwb.alu_result;
        end
        dep_exwb = 0;
    end
end

endmodule
