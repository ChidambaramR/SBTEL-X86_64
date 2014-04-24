module Core (
    input[63:0] entry,
    /* verilator lint_off UNDRIVEN */ /* verilator lint_off UNUSED */ Sysbus bus /* verilator lint_on UNUSED */ /* verilator lint_on UNDRIVEN */
);
    
    enum { fetch_idle, fetch_waiting, fetch_active } fetch_state;
    logic[63:0] fetch_rip;
    //logic[63:0] fetch_data_rip;
    logic[0:2*64*8-1] decode_buffer; // NOTE: buffer bits are left-to-right in increasing order
    logic[0:64*8-1] data_buffer;
    logic[0:8*8-1] load_buffer;
    logic[0:8*8-1] store_word;
    logic store_ins;
    logic store_writeback;
    logic store_writebackFlag;
    logic store_ack_waiting;
    logic store_done;
    logic store_opn;
    logic store_ack_received;

    logic load_done; // This variable is true whenever the requested byte has been put into the local buffer
    logic loadbuffer_done;
    logic[5:0] fetch_skip;
    logic[5:0] fetch_store_skip;
    logic[5:0] fetch_data_skip;
    logic[6:0] fetch_offset, decode_offset;
    logic[0:6] data_offset;
    logic[0:63] regfile[0:16-1];
    logic score_board[0:16-1];
    logic once;
    logic cycle;
    

    
    logic [0:8] i = 0;
    logic [0:4] j = 0;


    // 2D Array
    logic [0:255][0:0][0:3] opcode_group;

    logic [0:63] internal_offset;
    logic [0:63] internal_data_offset;
    
    logic can_memstage;
    logic can_execute;
    logic can_writeback;
    logic enable_memstage;
    logic enable_execute;
    logic enable_writeback;

    logic data_req;
    logic memstage_active;
    logic store_memstage_active;
    logic data_reqFlag;
    logic store_reqFlag;
    logic [0:63] data_reqAddr;

    initial 
    begin
        for (i = 0; i < 256; i++)
        begin
            //opcode_char[i] = empty_str;
            //opcode_enc[i] = "   ";
            opcode_group[i] = 0;
        end

        for (j = 0; j <= 15; j++) begin
            regfile[j] = {64{1'b0}};
        end

        store_ack_received = 0;
        /*for (j = 0; j <= 14; j++) begin
            score_board[j] = 0;
        end*/

        /*
         * Group of Shared opcode
         */
        opcode_group[128] = 1;
        opcode_group[129] = 1;
        opcode_group[130] = 1;
        opcode_group[131] = 1;

    end 
   
    function void disp_reg_file();
        $display("RAX = %x", regfile[0]);
        $display("RBX = %x", regfile[3]);
        $display("RCX = %x", regfile[1]);
        $display("RDX = %0h", regfile[2]);
        $display("RSI = %0h", regfile[6]);
        $display("RDI = %0h", regfile[7]);
        $display("RBP = %0h", regfile[5]);
        $display("RSP = %0h", regfile[4]);
        $display("R8 = %0h", regfile[8]);
        $display("R9 = %0h", regfile[9]);
        $display("R10 = %0h", regfile[10]);
        $display("R11 = %0h", regfile[11]);
        $display("R12 = %0h", regfile[12]);
        $display("R13 = %0h", regfile[13]);
        $display("R14 = %0h", regfile[14]);
        $display("R15 = %0h", regfile[15]);
    endfunction 

    function logic mtrr_is_mmio(logic[63:0] physaddr);
        mtrr_is_mmio = ((physaddr > 640*1024 && physaddr < 1024*1024));
    endfunction
    
    logic send_fetch_req;
    logic outstanding_fetch_req;

    always_comb begin
        if (fetch_state != fetch_idle) begin
            send_fetch_req = 0; // hack: in theory, we could try to send another request at this point
        end else if (bus.reqack) begin
            send_fetch_req = 0; // hack: still idle, but already got ack (in theory, we could try to send another request as early as this)
        end else begin
            if(!jump_signal)
                send_fetch_req = (fetch_offset - decode_offset < 7'd32);
            /*if(jump_signal && !bus.respcyc) begin
                jump_flag = 0;
                send_fetch_req = 1;
            end*/
        end
    end
    
    assign bus.respack = bus.respcyc; // always able to accept response
    
    always @ (posedge bus.clk) begin
        if (bus.reset) begin
    
            fetch_state <= fetch_idle;
            fetch_rip <= entry & ~63;
            fetch_skip <= entry[5:0];
            fetch_offset <= 0;
            internal_offset <= 0;
    
        end else begin // !bus.reset

    
            /*
            * REQCYC
            * If reqcyc is up, then we are sending a request to the memory.
              Immediately after sending the request, we will be getting back an 
              ACK from the bus. Once we get back an ACK, we know our request 
              has been acknowledged and we have to start waiting for the resposne. 
            */

            /*
            * SEND_FETCH_REQ
            * Whenever we get an ACK, the send_fetch_req goes down.
            */

            /*
            * FETCH_RIP & ~63
            * Dont understand.
            * This and logic is to fetch not more than 64 bytes. If the entry is 8000E0, then
            * result of the and is 8000C0. That means we have to fetch from 800000 to 8000C0.
            * how is this 64 bytes?
            */
            if(store_writebackFlag)
              store_writeback <= 1;

            if(!bus.respcyc) begin

            if(jump_signal && !outstanding_fetch_req) begin
                    // Fetch request for jump instruction
                    outstanding_fetch_req <= 1;
                    bus.req <= fetch_rip & ~63;
                    bus.reqtag <= { bus.READ, bus.MEMORY, 8'b0 };
                    bus.reqcyc <= 1;
                    store_writeback <= 0;
            end

            if(!data_req && !store_ins) begin
                // Sending a reques for instructions
                if(send_fetch_req) begin
                    outstanding_fetch_req <= 1;
                    bus.req <= fetch_rip & ~63;
                    //bus.req <= (fetch_rip - {57'b0, (fetch_offset - decode_offset)}) & ~63;
                    bus.reqtag <= { bus.READ, bus.MEMORY, 8'b0 };
                    bus.reqcyc <= send_fetch_req;
                    store_writeback <= 0;
                end
            end
            else if(store_ins && store_done) begin
                if(!outstanding_fetch_req) begin
                    if(cycle == 1) begin
                        bus.req <= (data_reqAddr & ~63);
                        bus.reqcyc <= 1;
                        bus.reqtag <= { bus.WRITE, bus.MEMORY, {6'b0,1'b1,1'b1}};
                        cycle <= 0;
                        store_writeback <= 0;
                    end
                    else if(store_ack_received) begin
                        // Now send the contents of the data to be stored
                //        if(!bus.reqcyc) begin
                            /*
                            * We have to wait till reqack is received. Whenever a reqack is received
                            * we can start sending the data. This means that the memory has accepted our 
                            * requested.
                            */
                            if(!(data_offset >= 64)) begin
                                bus.reqcyc <= 1;
                                store_ack_waiting <= 1;
                                bus.req <= data_buffer[data_offset*8 +: 64];
                                //if(data_offset == 16)
                                  //  $finish;
                                data_offset <= data_offset + 8;
                            end
                            else begin
                                // We have completed sending the data
                                store_opn <= 0;
                                store_done <= 0;
                                $write("wrote to memory");
                                //$finish;
                            end
                  //      end
                    end

                end
            end
            else begin
                // Sending a request for data
                if(!outstanding_fetch_req && (data_req)) begin
                    bus.req <= (data_reqAddr & ~63) ;
                    fetch_data_skip <= (data_reqAddr[58:63])&(~7);
                    fetch_store_skip <= (data_reqAddr[58:63])&(~7);
                    internal_data_offset <= (data_reqAddr[58:63])&(7);
                    //$write("req = %x", bus.req);
                    bus.reqtag <= { bus.READ, bus.MEMORY, {7'b0,1'b1}};
                    bus.reqcyc <= 1;
                    data_offset <= 0;
                    data_buffer <= 0;
                    once <= 1;
                    store_writeback <= 0;
                    outstanding_fetch_req <= 1;
//                    outstanding_data_req <= 1;
                    //$finish;
                end
            end
            end

    
            if (bus.respcyc && (bus.resptag[7:0] == 0)) begin
                //outstanding_fetch_req <= 0;
                //if(!jump_flag) begin
                    /*
                    * It takes around 48 micro seconds for a response to come back.
                    */
                    if(jump_signal) begin
                          fetch_offset <= 0;
                          decode_offset <= 0;
                          jump_signal <= 0;
                          jump_flag = 0;
                    end
                    assert(!send_fetch_req) else $fatal;
                    outstanding_fetch_req <= 0;
                    fetch_state <= fetch_active;
                    fetch_rip <= fetch_rip + 8;
                    if ((fetch_skip) > 0) begin
                        /*
                        * Fetch skip is up only when there is a response for the first time. 
                        */
                        fetch_skip <= fetch_skip - 8;
                    end else begin
                        if(internal_offset == 0)
                          decode_buffer[(fetch_offset)*8 +: 64] <= bus.resp;
                        else if(internal_offset == 1)
                          decode_buffer[(fetch_offset)*8 +: 56] <= bus.resp[55:0];
                        else if(internal_offset == 2)
                          decode_buffer[(fetch_offset)*8 +: 48] <= bus.resp[47:0];
                        else if(internal_offset == 3)
                          decode_buffer[(fetch_offset)*8 +: 40] <= bus.resp[39:0];
                        else if(internal_offset == 4)
                          decode_buffer[(fetch_offset)*8 +: 32] <= bus.resp[31:0];
                        else if(internal_offset == 5)
                          decode_buffer[(fetch_offset)*8 +: 24] <= bus.resp[23:0];
                        else if(internal_offset == 6)
                          decode_buffer[(fetch_offset)*8 +: 16] <= bus.resp[15:0];
                        else if(internal_offset == 7)
                          decode_buffer[(fetch_offset)*8 +: 8] <= bus.resp[7:0];
//                        $display("orig resp %x",bus.resp);
//                        $display("resp %x io = %x",bus.resp[55:0], internal_offset);
                        //$display("%x",decode_buffer[(fetch_offset+internal_offset)*8 +: 64]);
                        fetch_offset <= fetch_offset - internal_offset + 8;
                        internal_offset <= 0;
                    end
                //end
//                else begin
                    /*
                    * A jump is found and we need to resteer the fetch
                    */
                   // fetch_rip <= (jump_target & ~63);
                   // decode_buffer <= 0;
                    /* verilator lint_off WIDTH */
                  /*  fetch_skip <= (jump_target[58:63])&(~7);
                    internal_offset <= (jump_target[58:63])&(7);
                    //$write("io = %0h fs = %0h",internal_offset,fetch_skip);
                    fetch_offset <= 0;
                    jump_signal <= 1; */
//                end
            end else if(bus.respcyc && (bus.resptag[7:0] == 1)) begin
                /*
                * We received a response for data request
                */
                outstanding_fetch_req <= 0;
                data_req <= 0;
                //$write("got response for my data req. Yayy");
                fetch_state <= fetch_active;
                if(!store_ins) begin
                    // We are here for a LOAD instruction
                    if ((fetch_data_skip) > 0) begin
                        /*
                        * Fetch skip is up only when there is a response for the first time. 
                        */
                        fetch_data_skip <= fetch_data_skip - 8;
                    end else begin
                        if(!load_done) begin
                        if(internal_data_offset == 0)
                          load_buffer <= bus.resp[63:56];
                        else if(internal_data_offset == 1)
                          load_buffer <= bus.resp[55:48];
                        else if(internal_data_offset == 2)
                          load_buffer <= bus.resp[47:40];
                        else if(internal_data_offset == 3)
                          load_buffer <= bus.resp[39:32];
                        else if(internal_data_offset == 4)
                          load_buffer <= bus.resp[31:24];
                        else if(internal_data_offset == 5)
                          load_buffer <= bus.resp[23:16];
                        else if(internal_data_offset == 6)
                          load_buffer <= bus.resp[15:8];
                        else if(internal_data_offset == 7)
                          load_buffer <= bus.resp[7:0];
//                        $display("orig resp %x",bus.resp);
//                        $display("resp %x io = %x",bus.resp[55:0], internal_offset);
                        //$display("%x",decode_buffer[(fetch_offset+internal_offset)*8 +: 64]);
                        internal_data_offset <= 0;
                        load_done <= 1;
                        end
                    end
                end
                else begin
                      // This is the flag which controls whether STORE operation has completed or not. If 0, not complete
                      // We are begining the STORE operation.
                      // We are here for a STORE instruction
                      if(((fetch_store_skip) > 0)) begin
                          /*
                          * If fetch store skip has some value, then we dont have to mangle these contents.
                          */
                          data_buffer[data_offset*8 +: 64] <= bus.resp;
                          fetch_store_skip <= fetch_store_skip - 8;
                      end
                      else if(once) begin
                          data_buffer[data_offset*8 +: 64] <= store_word;
                          once <= 0;
                      end
                      else
                          data_buffer[data_offset*8 +: 64] <= bus.resp;
                      
                      data_offset <= data_offset + 8;
                      $display("Bus.resp = %x data_offset = %x",bus.resp, data_offset);
                      if(data_offset >= 56) begin
                          /*
                          * We have finished getting the contents in the data buffer. Now put the change buffer
                          * in the corresponding place.
                          */
                        //data_buffer[(data_offset)*8 +: 2*64] <= bus.resp;
                        $write("Changed buffer = %x",data_buffer);
                        store_done <= 1;
                        //store_writeback <= 0;
                        cycle <= 1;
                        data_offset <= 0;
                      end
                          


                end
                //if(data_offset >= 56)
                  //load_done <= 1;
                  //  $finish;
            end
            else begin
                // Handling the jump signal when no response in the bus
                //if(!jump_flag)
                  //  jump_signal <= 0;
              if(jump_flag) begin
                    /*
                    * A jump is found and we need to resteer the fetch
                    */
                    if(!outstanding_fetch_req) begin
                    fetch_rip <= (jump_target & ~63);
                    decode_buffer <= 0;
                    /* verilator lint_off WIDTH */
                    fetch_skip <= (jump_target[58:63])&(~7);
                    internal_offset <= (jump_target[58:63])&(7);
                    //$write("io = %0h fs = %0h",internal_offset,fetch_skip);
                    //fetch_offset <= 0;
                    end
                    jump_signal <= 1;
             end

//                if(jump_cond_flag)
//                    fetch_rip <= (jump_target & ~63);

                if (fetch_state == fetch_active) begin
                    fetch_state <= fetch_idle;
                end else if (bus.reqack) begin
                    /*
                    * We got an ACK from the bus. So we have to wait.
                    */
                    //if(store_ack_waiting)
                      //  store_ack_waiting <= 0;
                    assert(fetch_state == fetch_idle) else $fatal;
                    /*
                    * At the point when we got an ACK, the fetch state should have been idle. If the
                      fetch state was not idle, we would not have sent a request at all. So we are making
                      the sanity check. 
                    */
                    if(!store_done)
                      bus.reqcyc <= 0;
                    fetch_state <= fetch_waiting;
                end
            end
    
        end
    end
    
    wire[0:(128+15)*8-1] decode_bytes_repeated = { decode_buffer, decode_buffer[0:15*8-1] }; // NOTE: buffer bits are left-to-right in increasing order
    wire[0:15*8-1] decode_bytes = decode_bytes_repeated[decode_offset*8 +: 15*8]; // NOTE: buffer bits are left-to-right in increasing order

    /*
    All definitions (state elements) for ALU goes here
    */
    /*
    * Following is the pipeline register between decode and execute state
    * It contains, PC+1, (8 bytes)
                   REG A contents, (8 bytes)
                   REG B contents, (8 bytes)
                   Displacement values, (8 bytes)
                   Immediate values, (8 bytes)
                   Opcode value (1 byte)
    */
    
    // Refer to slide 11 of 43 in CSE502-L4-Pipilining.pdf
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

    // Refer to slide 11 of 43 in CSE502-L4-Pipelining.pdf
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
    } MEM_EX;

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
        logic res_3; // reserved bit. Should be set to 0
        logic af; // adjust flag
        logic res_2; // reserved bit. should be set to 0
        logic pf; // Parity flag
        logic res_1; // reserved bit. should be set to 1
        logic cf; // Carry flag
    } flags_reg;


    // Temporary values which will be stored in the IDMEM pipeline register
    logic [0:63] rip;
    logic[0 : 63] regA_contents;
    logic[0 : 63] regB_contents;
    logic[0 : 63] disp_contents;
    logic[0 : 63] imm_contents;
    logic[0 : 7] opcode_contents;
    logic[0 : 4-1] rmByte_contents;     // 4 bit Register B INDEX for the ALU
    logic[0 : 4-1] regByte_contents;    // 4 bit Register A INDEX for the ALU
    logic[0 :1] dependency;
    logic sim_end_signal;               // Variable to keep track of simulation ending

    // Temporary values which will be stored in the MEMEX pipeline register
    logic [0:63] rip_memex;
    logic[0 : 63] regA_contents_memex;
    logic[0 : 63] regB_contents_memex;
    logic[0 : 63] disp_contents_memex;
    logic[0 : 63] imm_contents_memex;
    logic[0 : 7] opcode_contents_memex;
    logic[0 : 4-1] rmByte_contents_memex;     // 4 bit Register B INDEX for the ALU
    logic[0 : 4-1] regByte_contents_memex;    // 4 bit Register A INDEX for the ALU
    logic[0 :1] dependency_memex;
    logic sim_end_signal_memex;               // Variable to keep track of simulation ending

    // Temporary values to be given to the EXWB pipeline register
    logic [0:63] rip_exwb;
    logic [0:1]  dep_exwb;
    logic sim_end_signal_exwb;
    logic[0 : 63] alu_result_exwb;
    logic[0 : 63] alu_ext_result_exwb;
    logic[0 : 63] regB_contents_exwb;
    logic[0 : 4-1] regByte_contents_exwb;
    logic[0 : 4-1] rmByte_contents_exwb;
    logic[0 : 8-1] opcode_exwb;

    logic[0 : 3] bytes_decoded_this_cycle;    
    logic jump_flag;
    logic jump_signal;
    logic jump_cond_signal;
    logic jump_cond_flag;
    logic[0 : 63] jump_target;

    /* verilator lint_off UNUSED */
    ID_MEM idmem;
    MEM_EX memex;
    EX_WB exwb;
    flags_reg rflags;
    flags_reg rflags_seq;

    // Request ack logic
    always_comb begin
      if(bus.reqack && store_done)
          store_ack_received = 1;
    end
    
    mod_decode dec( 
            can_writeback,
            data_req,
            memstage_active,
            store_memstage_active,
            jump_signal,
            jump_cond_signal,
            fetch_rip,
            fetch_offset, 
            decode_offset,
            decode_bytes,
            opcode_group,
            score_board,
            regfile,
            regA_contents,
            regB_contents,
            disp_contents,
            imm_contents,
            opcode_contents,
            rmByte_contents,     // 4 bit Register B INDEX for the ALU
            regByte_contents,    // 4 bit Register A INDEX for the ALU
            dependency,
            sim_end_signal,               // Variable to keep track of simulation ending
            rip,
            jump_target,
            loadbuffer_done,
            store_word,
            store_ins,
            enable_memstage,
            store_reqFlag,
            data_reqFlag,
            jump_flag,
            jump_cond_flag,
            data_reqAddr,
            bytes_decoded_this_cycle,
            store_writebackFlag
        );

    mod_memstage m1(can_memstage, memstage_active, load_done, load_buffer,  
                        idmem, store_memstage_active, store_ins, 
                        store_opn, enable_execute, loadbuffer_done,
                        data_reqFlag, store_reqFlag, rip_memex,
                        regA_contents_memex, regB_contents_memex, disp_contents_memex,
                        imm_contents_memex, opcode_contents_memex, rmByte_contents_memex,   
                        regByte_contents_memex, dependency_memex, sim_end_signal_memex);    

  
   /*
    * This is the ALU block. Any comments about ALU add here.
    * Info about RFLAGS for each instruction
    * ADD:
    *     It sets the OF and the CF flags to indiciate a carry(overflow) in the signed or unsigned result. 
          The SF indicates the sign of the signed result
    */

    mod_execute ex (can_execute, memex, load_buffer, store_memstage_active, 
                        regfile, opcode_group, rflags_seq,
                        enable_writeback, jump_flag, jump_cond_flag,
                        rflags, rip_exwb, dep_exwb,
                        sim_end_signal_exwb, alu_result_exwb, alu_ext_result_exwb,
                        regByte_contents_exwb, rmByte_contents_exwb, opcode_exwb);

    mod_writeback rb (can_writeback, exwb, store_memstage_active, 
                        regfile, dep_exwb, store_writebackFlag);
        
    always @ (posedge bus.clk) begin
        //can_decode <= 1;
        if (bus.reset) begin
            decode_offset <= 0;
            decode_buffer <= 0;
        end else begin // !bus.reset
            if(!jump_flag)
                decode_offset <= decode_offset + { 3'b0, bytes_decoded_this_cycle };
            else begin
                if(!outstanding_fetch_req && !bus.respcyc) begin
            //        decode_offset <= 0;
            //        fetch_offset <= 0;
                end
            end

            /*if(store_complete) begin
                store_done <= 0;
            end*/

            // Set all the flags right here
            rflags_seq.zf <= rflags.zf;

            if(jump_cond_flag)
                jump_cond_signal <= 1;
            else
                jump_cond_signal <= 0;


                // Decoder is detecting a dependency
                if(dependency == 1) begin
                    //while(1);
                    //$write("BOOM BOOM. Ins = %s",opcode_char[opcode_contents]);
                    score_board[rmByte_contents] <= 1;
                end
                else if(dependency == 2) begin
//                    $write("BOOM BOOM %s %s\n",reg_table_64[rmByte_contents], reg_table_64[regByte_contents]);
                    score_board[rmByte_contents] <= 1;
                    score_board[regByte_contents] <= 1;
                end
            //end

            if(!data_reqFlag && !store_reqFlag )
              can_memstage <= 0;
            if(store_opn == 0 && store_writeback)
              store_memstage_active <= 0;
            if (enable_memstage) begin
                /*
                * Giving to the pipeline register of Memory Stage
                */

                idmem.pc_contents <= rip;
                idmem.data_regA <= regA_contents;
                idmem.data_regB <= regB_contents;
                idmem.data_disp <= disp_contents;
                idmem.data_imm <= imm_contents;
                idmem.ctl_opcode <= opcode_contents;
                idmem.ctl_rmByte <= rmByte_contents;
                idmem.ctl_regByte <= regByte_contents;
                idmem.ctl_dep <= dependency;
                idmem.sim_end <= sim_end_signal;
                can_memstage <= 1;
                if(data_reqFlag) begin
                    data_req <= 1;
                    memstage_active <= 1;
                end
                if(store_reqFlag) begin
                    store_opn <= 1;
                    data_req <= 1;
                    store_memstage_active <= 1;
                end
            end

            can_execute <= 0;
            if (enable_execute) begin
                /*
                * Giving to the pipeline register of ALU
                */
                memex.pc_contents <= rip_memex;
                memex.data_regA <= regA_contents_memex;
                memex.data_regB <= regB_contents_memex;
                memex.data_disp <= disp_contents_memex;
                memex.data_imm <= imm_contents_memex;
                memex.ctl_opcode <= opcode_contents_memex;
                memex.ctl_rmByte <= rmByte_contents_memex;
                memex.ctl_regByte <= regByte_contents_memex;
                memex.ctl_dep <= dependency_memex;
                memex.sim_end <= sim_end_signal_memex;
                if(loadbuffer_done) begin
                    load_done <= 0;
                    memstage_active <= 0;
                end
                can_execute <= 1;
            end

            can_writeback <= 0;
            if(enable_writeback) begin
                /*
                * Giving to the write back stage of the processor
                */
                exwb.pc_contents <= rip_exwb;
                exwb.alu_result <= alu_result_exwb;
                exwb.alu_ext_result <= alu_ext_result_exwb;
                exwb.data_regB <= regB_contents_exwb;
                exwb.ctl_rmByte <= rmByte_contents_exwb;
                exwb.ctl_regByte <= regByte_contents_exwb;
                exwb.sim_end <= sim_end_signal_exwb; 
                exwb.ctl_opcode <= opcode_exwb;
                //$write("rmByte %0h regByte %0h dep EXWB %0h",rmByte_contents_exwb, regByte_contents_exwb, dep_exwb);
                score_board[rmByte_contents_exwb] <= 0;
                if(dep_exwb == 2) begin
                    score_board[regByte_contents_exwb] <= 0;
                end
                can_writeback <= 1;
            end

        end
    end

    // cse502 : Use the following as a guide to print the Register File contents.
    final begin
            $display("RAX = 0x%0h", regfile[0]);
            $display("RBX = 0x%0h", regfile[3]);
            $display("RCX = 0x%0h", regfile[1]);
            $display("RDX = 0x%0h", regfile[2]);
            $display("RSI = 0x%0h", regfile[6]);
            $display("RDI = 0x%0h", regfile[7]);
            $display("RBP = 0x%0h", regfile[5]);
            $display("RSP = 0x%0h", regfile[4]);
            $display("R8 =  0x%0h", regfile[8]);
            $display("R9 =  0x%0h", regfile[9]);
            $display("R10 = 0x%0h", regfile[10]);
            $display("R11 = 0x%0h", regfile[11]);
            $display("R12 = 0x%0h", regfile[12]);
            $display("R13 = 0x%0h", regfile[13]);
            $display("R14 = 0x%0h", regfile[14]);
            $display("R15 = 0x%0h", regfile[15]);
            $display("RIP = 0x%0h", rip);
    end
endmodule


