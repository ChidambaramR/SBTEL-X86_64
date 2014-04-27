/*
 * This is the ALU block. Any comments about ALU add here.
 * Info about RFLAGS for each instruction
 * ADD:
 *     It sets the OF and the CF flags to indiciate a carry(overflow) in the signed or unsigned result. 
 *     The SF indicates the sign of the signed result
 */

// Refer to slide 11 of 43 in CSE502-L4-Pipelining.pdf
typedef struct packed {
    // PC + 1
    logic [0:63] pc_contents;
    // REGA Contents
    logic [0:63] data_regA;
    // REGB Contents
    logic [0:63] data_regB;
    // Control signals
    logic [0:63] data_imm;
    logic [0:7]  ctl_opcode;
    logic [0:3]  ctl_regByte;
    logic [0:3]  ctl_rmByte;
    logic [0:1]  ctl_dep;
    logic sim_end;
} MEM_EX;

typedef struct packed {
    logic [12:63] unused;
    logic of; // Overflow flag
    logic df; // Direction flag
    logic If; // Interrupt flag. Not the capital case for I
    logic tf; // trap flag
    logic sf; // sign flag
    logic zf; // zero flag
    logic res_3; // reserved bit. Should be set to 0
    logic af; // adjust flag
    logic res_2; // reserved bit. should be set to 0
    logic pf; // Parity flag
    logic res_1; // reserved bit. should be set to 1
    logic cf; // Carry flag
} flags_reg;

module mod_execute (    
    /* verilator lint_off UNUSED */
    /* verilator lint_off UNDRIVEN */
    input can_execute,
    input MEM_EX memex,
    input [0:8*8-1] load_buffer,
    input store_memstage_active,
    input [0:63] regfile[0:16-1],
    input [0:255][0:0][0:3] opcode_group,
    input flags_reg rflags_seq,

    output enable_writeback,
    output jump_flag,
    output jump_cond_flag,
    output flags_reg rflags,
    output [0:63] rip_exwb,
    output [0:1] dep_exwb,
    output sim_end_signal_exwb,
    output [0 : 63] alu_result_exwb,
    output [0 : 63] alu_ext_result_exwb,
    output [0 : 4-1] regByte_contents_exwb,
    output [0 : 4-1] rmByte_contents_exwb,
    output [0 : 8-1] opcode_exwb
);

logic[0 : 127] data_regAA;
logic[0 : 127] data_regBB;
logic[0 : 64] ext_addReg;
logic[0 : 16*8-1] temp16;
logic[0 : 63] i;

always_comb begin
    if (can_execute) begin : execute_block

        dep_exwb = memex.ctl_dep;
        sim_end_signal_exwb = memex.sim_end;
        rmByte_contents_exwb = memex.ctl_rmByte;
        opcode_exwb = memex.ctl_opcode;
        //$write("Opcode at execute stage = %x",memex.ctl_opcode);
        if (dep_exwb == 2) begin
            regByte_contents_exwb = memex.ctl_regByte;
        end

        if (memex.ctl_opcode == 199 || (memex.ctl_opcode >= 184 && memex.ctl_opcode <= 191)) begin
            // Mov Imm
            //regfile[memex.ctl_rmByte] = memex.data_imm;
            alu_result_exwb = memex.data_imm;
            //$write("alu %0h rmByte %0h", alu_result_exwb, rmByte_contents_exwb);
        end

        else if (memex.ctl_opcode == 139) begin
            // Load instruction. ex: mov $0x100(%rax), %rbx
            //$write("Asssigning the value to pipeline register");
            alu_result_exwb = load_buffer; // The load buffer is filled in the mem stage
        end

        else if (memex.ctl_opcode == 141 || memex.ctl_opcode == 125) begin
            // JGE instruction and JNL instruction
            jump_cond_flag = 0;
        end

        else if (memex.ctl_opcode == 49) begin
          alu_result_exwb = memex.data_regA ^ memex.data_regB;
          //$write("Hurray Xor'd %x", alu_result_exwb);
          //$finish;
        end

        else if (memex.ctl_opcode == 116) begin
            // JE instruction
            jump_cond_flag = 0;
            if (rflags_seq.zf == 1) begin
              jump_flag = 1; // Zero flag is set for JE instruction.
              //$write("Conditional jump");
            end
        end

        else if (memex.ctl_opcode == 137 && !store_memstage_active) begin // Move reg to reg
            alu_result_exwb = regfile[memex.ctl_regByte];
        end

        else if (opcode_group[memex.ctl_opcode] != 0) begin
            // Check table A-6 of INTEL manual
            if (memex.ctl_regByte == 4) begin
                // AND instruction
                //$display("data_imm = %0h data_regA = %0h result = %0h", memex.data_imm, memex.data_regA, (memex.data_imm & memex.data_regA));
                //regfile[memex.ctl_rmByte] = memex.data_imm & memex.data_regA;
                alu_result_exwb = memex.data_imm & memex.data_regA;
            end
            else if (memex.ctl_regByte == 1) begin
                // OR Instruction
                //regfile[memex.ctl_rmByte] = memex.data_imm | memex.data_regA;
                alu_result_exwb = memex.data_imm | memex.data_regA;
            end
            else if (memex.ctl_regByte == 0) begin
                // ADD instruction
                ext_addReg = {65{1'b0}};
                ext_addReg = memex.data_imm + memex.data_regA;
                //$write("data_imm = %0h, data_regA = %0h ext_addReg = %0h",memex.data_imm, memex.data_regA, ext_addReg[1:64]);
                alu_result_exwb = ext_addReg[1:64];
                rflags.cf = ext_addReg[0];
            end
            else if (memex.ctl_regByte == 7) begin
                // CMP instruction
                // We need to set the RFLAGS for the jump ins to properly execute
                // Zero flag is set when the operands are equal
                rflags.zf = (memex.data_regA == memex.data_imm);
                //$write("0 flag is set %x, %x, %x",rflags.zf, memex.data_regA, memex.data_imm);
            end
        end

        else if (memex.ctl_opcode == 13) begin
            // OR instruction with immediate operands
            //regfile[0] = memex.data_imm | memex.data_regA;
            alu_result_exwb = memex.data_imm | memex.data_regA;
            rmByte_contents_exwb = 0;
        end

        else if (memex.ctl_opcode == 9 ) begin
            // OR instruction with reg operands 
            //$write("alu %0h %0h",memex.data_regA, memex.data_regB);
            alu_result_exwb = memex.data_regA | memex.data_regB;
        end

        else if (memex.ctl_opcode == 1 ) begin
            // Add instruction 
            alu_result_exwb = memex.data_regA + memex.data_regB;;
        end

        else if (memex.ctl_opcode == 247 ) begin
            // IMUL instruction "RDX:RAX = RAX * REG64"

            // Sign extend 64 bit register values to 128 bit
            data_regAA = {{64{memex.data_regB[0]}}, memex.data_regB}; 
            data_regBB = {{64{memex.data_regA[0]}}, memex.data_regA};

            // 128 bit multiplication
            temp16 = data_regAA * data_regBB;
            // Store result into RDX:RAX
            alu_ext_result_exwb = temp16[0:63];
            alu_result_exwb = temp16[64:127];
        end
        else if ((memex.ctl_opcode == 193 ) || (memex.ctl_opcode == 209 ) || (memex.ctl_opcode == 211 ))  begin
            /*
             * Opcode for SHL and SHR
             * In Mod R/M Byte,
             * If reg = 4, then 
             *       SHIFT Left 
             *   else if reg = 5
             *       SHIFT Right
             */
            alu_result_exwb = {memex.data_regA};
            if (memex.data_regB == 4) begin
                for (i = 0; i < memex.data_imm; i = i+1)
                begin
                    alu_result_exwb = alu_result_exwb * 2;
                end
            end
            else begin
                for (i = 0; i < memex.data_imm; i = i+1)
                begin
                    alu_result_exwb = alu_result_exwb / 2;
                end
            end
        end
        //$display("PC  = %0h, regA = %0h, regB = %0h, imm = %0h , opcode = %0h, ctl_regByte = %0h, ctl_rmByte = %0h",memex.pc_contents, memex.data_regA, memex.data_regB, memex.data_imm, memex.ctl_opcode, memex.ctl_regByte, memex.ctl_rmByte);
        rip_exwb = memex.pc_contents;
        if (memex.ctl_opcode != 125 && memex.ctl_opcode != 116 ) begin
            /*
             * We dont want the write back stage for conditional jumps.
             * We just want the ALU to execute and set the flags for resteering the fetch
             */
            enable_writeback = 1;
        end
        else
            enable_writeback = 0;
    end
    else
        enable_writeback = 0;
end

endmodule
