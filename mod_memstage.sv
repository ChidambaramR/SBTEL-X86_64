
module mod_memstage(
    
    input can_memstage, 
    input[0:8*8-1] load_buffer,
    input ID_MEM idmem,
    input store_memstage_active,
    input store_ins,
    input store_opn,
    input [0:255][0:0][0:3] opcode_group,
    input flags_reg rflags_seq,

    output can_writeback,
    output loadbuffer_done,
    output data_reqFlag,
    output store_reqFlag,
    output store_writebackFlag,
    output jump_flag,
    output jump_cond_flag,
    output memstage_active,
    output load_done,
    output score_board[0:16-1],
    output [0:63] regfile[0:16-1],
    output flags_reg rflags,
    output MEM_EX memex,
    output EX_WB exwb
    );    

/*
* Refer to wiki page of RFLAGS for the bit pattern
*/ 
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
} ID_MEM;

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

// Temporary values which will be stored in the MEMEX pipeline register
logic [0:63] rip_memex;
logic [0:63] regA_contents_memex;
logic [0:63] regB_contents_memex;
logic [0:63] imm_contents_memex;
logic [0:1]  mod_contents_memex;
logic [0:7] opcode_contents_memex;
logic       twob_opcode_contents_memex;
logic [0:4-1] rmByte_contents_memex;     // 4 bit Register B INDEX for the ALU
logic [0:4-1] regByte_contents_memex;    // 4 bit Register A INDEX for the ALU
logic [0:1] dependency_memex;
logic sim_end_signal_memex;               // Variable to keep track of simulation ending

logic can_execute;
logic enable_execute;

always_comb begin
    if (can_memstage) begin : memstage_block
    if (!memstage_active && !store_memstage_active) begin
            rip_memex              = idmem.pc_contents;
            regA_contents_memex    = idmem.data_regA;
            regB_contents_memex    = idmem.data_regB;
            imm_contents_memex     = idmem.data_imm;
            opcode_contents_memex  = idmem.ctl_opcode;
            rmByte_contents_memex  = idmem.ctl_rmByte;
            regByte_contents_memex = idmem.ctl_regByte;
            dependency_memex       = idmem.ctl_dep;
            sim_end_signal_memex   = idmem.sim_end;
            twob_opcode_contents_memex = idmem.twob_opcode;
            mod_contents_memex     = idmem.mod;
            enable_execute = 1;
        end
        else begin
            /*
             * Data req flag is set. This is a load ins
             * For store instruction we dont have to worry about further pipeline stages
             */
            if (!store_ins) begin
            if (load_done) begin
                  //$write("load byte = %x",load_buffer);
                  rmByte_contents_memex  = idmem.ctl_rmByte;
                  regByte_contents_memex = idmem.ctl_regByte;
                  opcode_contents_memex  = idmem.ctl_opcode;
                  dependency_memex       = idmem.ctl_dep;
                  twob_opcode_contents_memex = idmem.twob_opcode;
                  loadbuffer_done = 1;
                  enable_execute = 1;
                  mod_contents_memex     = idmem.mod;
                  data_reqFlag = 0;
                  // Got the load value. Should feed this in the pipeline
                  //$finish;
                end
                else begin
                    enable_execute = 0;
                end
            end
            else begin
              // This is a STORE instruction
                if (store_opn == 0) begin
                    rmByte_contents_memex  = idmem.ctl_rmByte;
                    twob_opcode_contents_memex = idmem.twob_opcode;
                    regByte_contents_memex = idmem.ctl_regByte;
                    opcode_contents_memex  = idmem.ctl_opcode;
                    dependency_memex       = idmem.ctl_dep;
                    store_reqFlag = 0;
                    enable_execute = 1;
                    mod_contents_memex     = idmem.mod;
                end
                else
                  enable_execute = 0;
            end

            //$display("Issuing store to mem");
            //$display("Target addre = %x",data_reqAddr);
        end
    end
    else
        enable_execute = 0;
end

mod_execute ex (
        // INPUT PARAMS
        enable_execute, loadbuffer_done, load_buffer, 
        store_memstage_active, opcode_group, rflags_seq, 
        //OUTPUT PARAMS
        memstage_active, load_done, can_execute, can_writeback,
        store_writebackFlag, jump_flag, jump_cond_flag, 
        rflags, regfile, score_board, memex, exwb
        );

always @ (posedge bus.clk) begin

    if (bus.reset) begin
        //if (store_complete) begin
        //    store_done <= 0;
        //end
    end else begin // !bus.reset
        can_execute <= 0;
        if (enable_execute) begin
            /*
             * Giving to the pipeline register of ALU
             */
            memex.pc_contents <= rip_memex;
            memex.data_regA <= regA_contents_memex;
            memex.data_regB <= regB_contents_memex;
            memex.data_imm <= imm_contents_memex;
            memex.ctl_opcode <= opcode_contents_memex;
            memex.twob_opcode <= twob_opcode_contents_memex;
            memex.ctl_rmByte <= rmByte_contents_memex;
            memex.ctl_regByte <= regByte_contents_memex;
            memex.ctl_dep <= dependency_memex;
            memex.sim_end <= sim_end_signal_memex;
            memex.mod  <= mod_contents_memex;
            if (loadbuffer_done) begin
                //load_done <= 0;
                memstage_active <= 0;
            end
            can_execute <= 1;
        end
        

    end
end

endmodule

