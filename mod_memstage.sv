typedef struct packed {
    // PC + 1
    logic [0:63] pc_contents;
    // REGA Contents
    logic [0:63] data_regA;
    // REGB Contents
    logic [0:63] data_regB;
    // Control signals
    logic [0:63] data_disp;
    logic [0:63] data_imm;
    logic [0:7]  ctl_opcode;
    logic [0:3]  ctl_regByte;
    logic [0:3]  ctl_rmByte;
    logic [0:1]  ctl_dep;
    logic sim_end;
} ID_MEM;

module mod_memstage(
    
    input can_memstage, 
    input memstage_active,
    input load_done,
    input[0:8*8-1] load_buffer,
    input ID_MEM idmem,
    input store_memstage_active,
    input store_ins,
    input store_opn,
    output enable_execute,
    output loadbuffer_done,
    output data_reqFlag,
    output store_reqFlag,
    
    // Temporary values which will be stored in the MEMEX pipeline register
    output [0:63] rip_memex,
    output [0 : 63] regA_contents_memex,
    output [0 : 63] regB_contents_memex,
    output [0 : 63] disp_contents_memex,
    output [0 : 63] imm_contents_memex,
    output [0 : 7] opcode_contents_memex,
    output [0 : 4-1] rmByte_contents_memex,     // 4 bit Register B INDEX for the ALU
    output [0 : 4-1] regByte_contents_memex,    // 4 bit Register A INDEX for the ALU
    output [0 :1] dependency_memex,
    output sim_end_signal_memex                // Variable to keep track of simulation ending
    );    


    always_comb begin
        if (can_memstage) begin : memstage_block
        if(!memstage_active && !store_memstage_active) begin
                rip_memex              = idmem.pc_contents;
                regA_contents_memex    = idmem.data_regA;
                regB_contents_memex    = idmem.data_regB;
                disp_contents_memex    = idmem.data_disp;
                imm_contents_memex     = idmem.data_imm;
                opcode_contents_memex  = idmem.ctl_opcode;
                rmByte_contents_memex  = idmem.ctl_rmByte;
                regByte_contents_memex = idmem.ctl_regByte;
                dependency_memex       = idmem.ctl_dep;
                sim_end_signal_memex   = idmem.sim_end;
                enable_execute = 1;
            end
            else begin
                /*
                * Data req flag is set. This is a load ins
                * For store instruction we dont have to worry about further pipeline stages
                */
                if(!store_ins) begin
                    if(load_done) begin
                      $write("load byte = %x",load_buffer);
                      rmByte_contents_memex  = idmem.ctl_rmByte;
                      regByte_contents_memex = idmem.ctl_regByte;
                      opcode_contents_memex  = idmem.ctl_opcode;
                      dependency_memex       = idmem.ctl_dep;
                      loadbuffer_done = 1;
                      enable_execute = 1;
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
                    if(store_opn == 0) begin
                        rmByte_contents_memex  = idmem.ctl_rmByte;
                        regByte_contents_memex = idmem.ctl_regByte;
                        opcode_contents_memex  = idmem.ctl_opcode;
                        dependency_memex       = idmem.ctl_dep;
                        store_reqFlag = 0;
                        enable_execute = 1;
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
endmodule

