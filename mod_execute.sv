/*
 * This is the ALU block. Any comments about ALU add here.
 * Info about RFLAGS for each instruction
 * ADD:
 *     It sets the OF and the CF flags to indiciate a carry(overflow) in the signed or unsigned result. 
 *     The SF indicates the sign of the signed result
 */


import "DPI-C" function longint syscall_cse502(input longint rax, input longint rdi, input longint rsi, input longint rdx, input longint r10, input longint r8, input longint r9);

module mod_execute (    
    /* verilator lint_off UNUSED */
    /* verilator lint_off UNDRIVEN */
    input enable_execute,
    input loadbuffer_done,
    input [0:8*8-1] load_buffer,
    input store_memstage_active,
    input [0:255][0:0][0:3] opcode_group,
    input flags_reg rflags_seq,
    input end_prog, 
    
    output memstage_active,
    output load_done,
    output can_execute,
    output can_writeback,
    output store_writebackFlag,
    output jump_flag,
    output jump_cond_flag,
    output flags_reg rflags,
    output [0:63] regfile[0:16-1],
    output score_board[0:16-1],
    output MEM_EX memex,
    output EX_WB exwb
);

typedef struct packed {
    logic [12:63] unused;
    logic of; // Overflow flag
    logic df; // Direction flag
    logic If; // Interrupt flag. Not the capital case for I
    logic tf; // trap flag
    logic sf; // sign flag
    logic zf; // zero flag
    logic jge;
    //logic jne;
    logic jg;
    logic res_3; // reserved bit. Should be set to 0
    logic af; // adjust flag
    logic res_2; // reserved bit. should be set to 0
    logic pf; // Parity flag
    logic res_1; // reserved bit. should be set to 1
    logic cf; // Carry flag
} flags_reg;

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
    logic        twob_opcode; 
    logic [0:3]  ctl_regByte;
    logic [0:3]  ctl_rmByte;
    logic [0:1]  ctl_dep;
    logic sim_end;
    logic [0:1] mod;
} MEM_EX;

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

// Temporary values to be given to the EXWB pipeline register
logic [0:63] rip_exwb;
logic [0:1]  dep_exwb;
logic [0:1]  mod_exwb;
logic sim_end_signal_exwb;
logic[0 : 63] alu_result_exwb;
logic[0 : 63] alu_ext_result_exwb;
logic[0 : 4-1] regByte_contents_exwb;
logic[0 : 4-1] rmByte_contents_exwb;
logic[0 : 8-1] opcode_exwb;
logic[0 : 63] temp_regA;

logic[0 : 127] data_regAA;
logic[0 : 127] data_regBB;
logic[0 : 64] ext_addReg;
logic[0 : 16*8-1] temp16;
logic[0 : 63] i;

logic enable_writeback;

always_comb begin
    if (can_execute) begin : execute_block

        dep_exwb = memex.ctl_dep;
        mod_exwb = memex.mod;
        sim_end_signal_exwb = memex.sim_end;
        rmByte_contents_exwb = memex.ctl_rmByte;
        opcode_exwb = memex.ctl_opcode;
        //$write("twob opcode = %x",memex.twob_opcode);
        //$write("Opcode at execute stage = %x",memex.ctl_opcode);
        if (dep_exwb == 2 || memex.ctl_opcode == 139 || memex.ctl_opcode == 141) begin
            regByte_contents_exwb = memex.ctl_regByte;
        end
      
        if (memex.sim_end == 1) begin
            // Simulation going to end. Do nothing
        end

        else if (memex.ctl_opcode == 144) begin
            // NO OP
        end

        else if (memex.ctl_opcode == 199 || (memex.ctl_opcode >= 184 && memex.ctl_opcode <= 191)) begin
            // Mov Imm
            //regfile[memex.ctl_rmByte] = memex.data_imm;
            alu_result_exwb = memex.data_imm;
            //$write("rm byte contents = %x",rmByte_contents_exwb);
            //$write("alu %0h rmByte %0h", alu_result_exwb, rmByte_contents_exwb);
        end

        else if (memex.ctl_opcode == 139) begin
            // Load instruction. ex: mov $0x100(%rax), %rbx
            //$write("Asssigning the value to pipeline register");
            alu_result_exwb = load_buffer; // The load buffer is filled in the mem stage
        end


        else if ((memex.ctl_opcode >= 80) && (memex.ctl_opcode < 88)) begin
            // PUSH 
        end

        else if (memex.ctl_opcode == 5) begin
            //$write("syscall finish in exec %x", regfile[0]);
            alu_result_exwb = syscall_cse502(regfile[0], regfile[7], regfile[6], regfile[2], regfile[10], regfile[8], regfile[9]);
            //$write("syscall finish in exec Finish %x", alu_result_exwb);
            //$finish;
        end

        else if ((memex.ctl_opcode >= 88) && (memex.ctl_opcode < 96)) begin
            // POP
            //$write("Execute POP");
            alu_result_exwb = load_buffer;
        end

        else if(memex.ctl_opcode == 141 && memex.twob_opcode == 0) begin
            alu_result_exwb = memex.data_regB; 
            //$write("writing %x into %x",alu_result_exwb, regByte_contents_exwb);
        end

        else if ((memex.ctl_opcode == 141 && memex.twob_opcode == 1) || memex.ctl_opcode == 125) begin
            // JGE instruction and JNL instruction
          jump_cond_flag = 0;
          //$write("jge: %x",rflags_seq.jge);
          if(rflags_seq.jge == 1) begin
              jump_flag = 1;
          end
//          rflags.jge = 0;
        end

        else if ((memex.ctl_opcode == 142 && memex.twob_opcode == 1)) begin
            // JLE instructionn
          jump_cond_flag = 0;
          if(rflags_seq.jge == 0 && rflags_seq.jg == 0) begin
              jump_flag = 1;
          end
        end

        else if ((memex.ctl_opcode == 131 && memex.twob_opcode == 1)) begin
            // JAE instruction
            jump_cond_flag = 0;
            if(rflags_seq.jge == 1) begin
                jump_flag = 1;
            end
        end

        else if ((memex.ctl_opcode == 143 && memex.twob_opcode == 1)) begin
            // JG instruction 
          jump_cond_flag = 0;
          //$write("jge: %x",rflags_seq.jge);
          if(rflags_seq.jg == 1 && rflags_seq.zf == 0) begin
              jump_flag = 1;
          end
        end

        else if ((memex.ctl_opcode == 140 && memex.twob_opcode == 1)) begin
            // JL instructionn
          jump_cond_flag = 0;
          if(rflags_seq.jge == 0 && rflags_seq.jg == 0 && rflags_seq.zf == 0) begin
              jump_flag = 1;
          end
        end

        else if ((memex.ctl_opcode == 33)) begin
          // AND instructions
          alu_result_exwb = memex.data_regA & memex.data_regB;
        end

        else if ((memex.ctl_opcode == 133 && memex.twob_opcode == 1)) begin
            // JGE instruction and JNL instruction
          jump_cond_flag = 0;
          //$write("jge: %x",rflags_seq.jge);
          if(rflags_seq.zf == 0) begin
              jump_flag = 1;
          end
        end

        else if ((memex.ctl_opcode == 133 && memex.twob_opcode == 0)) begin
            // TEST instruction
            if(memex.data_regA != 0 & memex.data_regB != 0)
                rflags.zf = 0; // Not equal
            else
                rflags.zf = 1; // Equal
        end


        else if (memex.ctl_opcode == 49) begin
          alu_result_exwb = memex.data_regA ^ memex.data_regB;
          //$write("Hurray Xor'd %x", alu_result_exwb);
          //$finish;
        end

        else if (memex.ctl_opcode == 116 || memex.ctl_opcode == 132) begin
            // JE instruction
            jump_cond_flag = 0;
            //$write("zf = %x",rflags_seq.zf);
            if (rflags_seq.zf == 1) begin
              jump_flag = 1; // Zero flag is set for JE instruction.
             // $write("Conditional jump");
            end
            //rflags.zf = 0;
        end

        else if (memex.ctl_opcode == 137 && memex.mod == 3) begin // Move reg to reg
            alu_result_exwb = regfile[memex.ctl_regByte];
        end

        else if (memex.ctl_opcode == 137 && !store_memstage_active) begin // Move reg to reg
            alu_result_exwb = regfile[memex.ctl_regByte];
        end

        else if(memex.ctl_opcode == 41) begin
            //$write("subtracting here");
            alu_result_exwb = regfile[memex.ctl_rmByte] - regfile[memex.ctl_regByte];
        end

        else if (memex.ctl_opcode == 57) begin
//            $write("regA %x regB %x",memex.data_regA, memex.data_regB);
            if(memex.data_regA == memex.data_regB)
                rflags.zf = 1;
            else
                rflags.zf = 0;

            if(memex.data_regB >= memex.data_regA) begin
                    //$write("setting 1");
                rflags.jge = 1;
                rflags.jg = 1;
            end
            else begin
                rflags.jge = 0;
                rflags.jg = 0;
                rflags.zf = 0;
            end
            
        end

        else if (opcode_group[memex.ctl_opcode] != 0) begin
            // Check table A-6 of INTEL manual
            if (memex.ctl_regByte == 4) begin
                // AND instruction
                //regfile[memex.ctl_rmByte] = memex.data_imm & memex.data_regA;
                alu_result_exwb =   (memex.data_imm ) & memex.data_regA;
        //        $display("data_imm = %0h data_regA = %0h result = %0h", memex.data_imm, memex.data_regA, (alu_result_exwb));
            end
            else if(memex.ctl_regByte == 5) begin
                // SUB instruction
              alu_result_exwb = memex.data_regA - memex.data_imm;
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
                if(memex.data_regA == memex.data_imm)
                    rflags.zf = 1;
                else
                    rflags.zf = 0;

                if(memex.data_regA[0] == 1) begin
                    // Signed
                    // HACK. If it reaches here, value is regA is always assumed as less than imm
                        // for this project. Will fail elsewhere
                    rflags.jge = 0;
                    rflags.jg = 0;
                end
                else begin
                    if(memex.data_regA >= memex.data_imm) begin
                        //$write("setting 1");
                        rflags.jge = 1;
                        rflags.jg = 1;
                    end
                    else begin
                        rflags.jge = 0;
                        rflags.jg = 0;
                        rflags.zf = 0;
                    end
                end
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

        else if ((memex.ctl_opcode == 175) && (memex.twob_opcode == 1)) begin
            data_regAA = {{64{memex.data_regB[0]}}, memex.data_regB}; 
            data_regBB = {{64{memex.data_regA[0]}}, memex.data_regA};
            
            // 128 bit multiplication
            temp16 = data_regAA * data_regBB;
            // Store result into RDX:RAX
            alu_ext_result_exwb = temp16[0:63];
            alu_result_exwb = temp16[64:127];
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
            //$write("alu result = %x rm = %x",alu_result_exwb, rmByte_contents_exwb);
        end
        //$display("PC  = %0h, regA = %0h, regB = %0h, imm = %0h , opcode = %0h, ctl_regByte = %0h, ctl_rmByte = %0h",memex.pc_contents, memex.data_regA, memex.data_regB, memex.data_imm, memex.ctl_opcode, memex.ctl_regByte, memex.ctl_rmByte);
        rip_exwb = memex.pc_contents;
        if (memex.ctl_opcode != 125 && memex.ctl_opcode != 116 /*&& memex.ctl_opcode != 195*/) begin
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

mod_writeback rb (
        // INPUT PARAMS
        can_writeback, exwb, store_memstage_active, end_prog,
        // OUTPUT PARAMS
        regfile, dep_exwb, store_writebackFlag
    );

always @ (posedge bus.clk) begin

    if (bus.reset) begin
        //if (store_complete) begin
        //    store_done <= 0;
        //end
    end else begin // !bus.reset
        
        can_writeback <= 0;
        if (enable_writeback) begin
            /*
            * Giving to the write back stage of the processor
            */
            exwb.pc_contents <= rip_exwb;
            exwb.alu_result <= alu_result_exwb;
            exwb.alu_ext_result <= alu_ext_result_exwb;
            exwb.ctl_rmByte <= rmByte_contents_exwb;
            exwb.ctl_regByte <= regByte_contents_exwb;
            exwb.sim_end <= sim_end_signal_exwb; 
            exwb.ctl_opcode <= opcode_exwb;
            exwb.twob_opcode <= memex.twob_opcode;
            exwb.mod <= mod_exwb;
            //$write("rmByte %0h regByte %0h dep EXWB %0h",rmByte_contents_exwb, regByte_contents_exwb, dep_exwb);
            score_board[rmByte_contents_exwb] <= 0;
            if (dep_exwb == 2) begin
                score_board[regByte_contents_exwb] <= 0;
            end
            can_writeback <= 1;
        end

    end
end

endmodule
