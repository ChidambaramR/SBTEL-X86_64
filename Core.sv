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
    

    /*
     * This is the REX prefix
     */
    typedef struct packed {
        logic [0:3] def;
        logic W, R, Xe, B;
    } rex;
    
    /*
     * This is the mod_rm byte
     */
    typedef struct packed {
        logic [6:7] mod;
        logic [3:5] reg1;
        logic [0:2] rm; 
    } mod_rm;
    
    logic [0:255][0:2][0:7] opcode_enc;
    logic [0:255][0:7][0:7] opcode_char;
    logic [0:15][0:3][0:7] reg_table_64;
    logic [0:7][0:7]empty_str = {"       "};
    logic [0:8] i = 0;
    logic [0:4] j = 0;
    logic [0:63] temp_crr;


    // 2D Array
    logic [0:8*8-1] shared_opcode[0:14][0:8];
    logic [0:255][0:0][0:3] opcode_group;

    logic [0:15*8-1] space_buffer;
    logic [0:7][0:7] instr_buffer;
    logic [0:32*8-1] reg_buffer;
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
            opcode_char[i] = empty_str;
            opcode_enc[i] = "   ";
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
         * Following values are converted into decimal from hex.
         * For example, 0x89 is the hex opcode. This is 137 in decimal
         * Also store Mod RM byte encoding for each opcode
         */

        /*
         * First byte of a 2 byte opcode instruction
         */
        opcode_char[15] = "XXXXXXXX"; opcode_enc [15] = "XXX"; // 0F

        /*
         * Prefixes: To distinguish with actual instruction opcodes, we set opcode_enc as "PRE"
         */
        opcode_char [38] = "es      "; opcode_enc [38] = "PRE"; // 26
        opcode_char [46] = "cs      "; opcode_enc [46] = "PRE"; // 2E
        opcode_char [54] = "ss      "; opcode_enc [54] = "PRE"; // 36
        opcode_char [62] = "dd      "; opcode_enc [62] = "PRE"; // 3E
        opcode_char[100] = "fs      "; opcode_enc[100] = "PRE"; // 64
        opcode_char[101] = "gs      "; opcode_enc[101] = "PRE"; // 65
        opcode_char[102] = "operand "; opcode_enc[102] = "PRE"; // 66
        opcode_char[103] = "address "; opcode_enc[103] = "PRE"; // 67
        opcode_char[240] = "lock    "; opcode_enc[240] = "PRE"; // F0
        opcode_char[242] = "repne   "; opcode_enc[242] = "PRE"; // F2
        opcode_char[243] = "repe    "; opcode_enc[243] = "PRE"; // F3

        /*
         * REX Prefixes: To distinguish with actual instruction opcodes, we set opcode_enc as "PRE"
         */
        opcode_char [64] = "rex     "; opcode_enc [64] = "PRE"; // 40
        opcode_char [65] = "rex     "; opcode_enc [65] = "PRE"; // 41
        opcode_char [66] = "rex     "; opcode_enc [66] = "PRE"; // 42
        opcode_char [67] = "rex     "; opcode_enc [67] = "PRE"; // 43
        opcode_char [68] = "rex     "; opcode_enc [68] = "PRE"; // 44
        opcode_char [69] = "rex     "; opcode_enc [69] = "PRE"; // 45
        opcode_char [70] = "rex     "; opcode_enc [70] = "PRE"; // 46
        opcode_char [71] = "rex     "; opcode_enc [71] = "PRE"; // 47
        opcode_char [72] = "rex     "; opcode_enc [72] = "PRE"; // 48
        opcode_char [73] = "rex     "; opcode_enc [73] = "PRE"; // 49
        opcode_char [74] = "rex     "; opcode_enc [74] = "PRE"; // 4A
        opcode_char [75] = "rex     "; opcode_enc [75] = "PRE"; // 4B
        opcode_char [76] = "rex     "; opcode_enc [76] = "PRE"; // 4C
        opcode_char [77] = "rex     "; opcode_enc [77] = "PRE"; // 4D
        opcode_char [78] = "rex     "; opcode_enc [78] = "PRE"; // 4E
        opcode_char [79] = "rex     "; opcode_enc [79] = "PRE"; // 4F


        /*
         * Opcodes for single byte IMUL
         */
        opcode_char[247] = "imul    "; opcode_enc[247] = "M  "; // F7

        /*
         * Opcodes for AND
         */
        opcode_char  [1] = "add     "; opcode_enc  [1] = "MR ";

        /*
        * Opcodes for OR
        */
        opcode_char [13] = "or      "; opcode_enc [13] = "I  ";
        opcode_char  [9] = "or      "; opcode_enc  [9] = "MR ";
        /*
         * Opcodes for XOR
         */
        opcode_char [49] = "xor     "; opcode_enc [49] = "MR "; // 31

        /*
         * Opcodes for AND
         */
        opcode_char [32] = "and     "; opcode_enc [32] = "MR "; // 20
        opcode_char [33] = "and     "; opcode_enc [33] = "MR "; // 21
        opcode_char[129] = "and     "; opcode_enc[129] = "MI "; // 81
        opcode_char[131] = "and     "; opcode_enc[131] = "MIS"; // 83
         
        /*
         * Opcodes for MOV
         */
        opcode_char[137] = "mov     "; opcode_enc[137] = "MR "; // 89
        opcode_char[139] = "mov     "; opcode_enc[139] = "RM "; // 8B
        opcode_char[199] = "mov     "; opcode_enc[199] = "MI "; // C7

        /* 
         * Special MOV Opcodes
         */
        opcode_char[184] = "mov     "; opcode_enc[184] = "SP "; // B8
        opcode_char[185] = "mov     "; opcode_enc[185] = "SP "; // B9
        opcode_char[186] = "mov     "; opcode_enc[196] = "SP "; // BA
        opcode_char[187] = "mov     "; opcode_enc[187] = "SP "; // BB
        opcode_char[188] = "mov     "; opcode_enc[188] = "SP "; // BC
        opcode_char[189] = "mov     "; opcode_enc[189] = "SP "; // BD
        opcode_char[190] = "mov     "; opcode_enc[190] = "SP "; // BE
        opcode_char[191] = "mov     "; opcode_enc[191] = "SP "; // BF
    
        /*
         * Opcodes for Instructions w/o REX Prefixes
         */
        opcode_char[114] = "jb      "; opcode_enc[114] = "D1 "; // 72
        opcode_char[232] = "callq   "; opcode_enc[232] = "D4 "; // E8
        opcode_char[233] = "jmpq    "; opcode_enc[233] = "D4 "; // E9
        opcode_char[235] = "jmp     "; opcode_enc[235] = "D1 "; // EB
        opcode_char[125] = "jge     "; opcode_enc[125] = "D1 "; // EB
        opcode_char[116] = "je      "; opcode_enc[116] = "D1 "; // EB
        opcode_char[255] = "callq   "; opcode_enc[255] = "M  "; // FF 
        
        /*
         * Opcodes for Instructions w/o REX Prefixes and w/o MOD RM
         */
        opcode_char[108] = "insb    "; // 6C
        opcode_char[111] = "outsl   "; // 6F

        /*
         * Opcodes for SUB
         */
        opcode_char [41] = "sub     "; opcode_enc [41] = "MR " ; // 29

        /*
         * Opcodes for CMP
         */
        opcode_char [57] = "cmp     "; opcode_enc [57] = "MR "; // 39
        opcode_char [61] = "cmp     "; opcode_enc [61] = "XXX"; 

        /*
         * Opcode for ADD
         */
        opcode_char  [1] = "add     "; opcode_enc  [1] = "MR "; // 1
        
        /*
         * Opcode for PUSH
         */
        opcode_char [80] = "push    "; opcode_enc [80] = "XXX";
        opcode_char [81] = "push    "; opcode_enc [81] = "XXX";
        opcode_char [82] = "push    "; opcode_enc [82] = "XXX";
        opcode_char [83] = "push    "; opcode_enc [83] = "XXX";
        opcode_char [84] = "push    "; opcode_enc [84] = "XXX";
        opcode_char [85] = "push    "; opcode_enc [85] = "XXX";
        opcode_char [86] = "push    "; opcode_enc [86] = "XXX";
        opcode_char [87] = "push    "; opcode_enc [87] = "XXX";
       

        /*
         * Opcode for POP
         */
        opcode_char [88] = "pop     "; opcode_enc [88] = "XXX";
        opcode_char [89] = "pop     "; opcode_enc [89] = "XXX";
        opcode_char [90] = "pop     "; opcode_enc [90] = "XXX";
        opcode_char [91] = "pop     "; opcode_enc [91] = "XXX";
        opcode_char [92] = "pop     "; opcode_enc [92] = "XXX";
        opcode_char [93] = "pop     "; opcode_enc [93] = "XXX";
        opcode_char [94] = "pop     "; opcode_enc [94] = "XXX";
        opcode_char [95] = "pop     "; opcode_enc [95] = "XXX";

        /*
         * Opcode for RET
         */
        opcode_char[195] = "retq    "; opcode_enc[195] = "XXX";

        /*
         * Opcode for LEA
         */
        opcode_char[141] = "lea     "; opcode_enc[141] = "RM ";
        
        /*
         * Opcode for SHL and SHR
         * In Mod R/M Byte,
         * If reg = 4, then 
         *       SHIFT Left 
         *   else if reg = 5
         *       SHIFT Right
         */
        opcode_char[193] = "shr     "; opcode_enc[193] = "MI ";
        opcode_char[209] = "shr     "; opcode_enc[209] = "M1 ";
        opcode_char[211] = "shr     "; opcode_enc[211] = "MC ";
        
        /*
         * Opcode for TEST
         */
        opcode_char[133] = "test    "; opcode_enc[133] = "MR ";

        /*
         * Opcode for NOP
         */
        opcode_char[144] = "nop     "; opcode_enc[144] = "XXX"; // 90

        /*
         * Shared OPCODE encoding. This block and the group block is taken from table
         * A6 in Appendix A of intel manual.
         */
        shared_opcode[1][0] = "add     ";
        shared_opcode[1][1] = "or      ";
        shared_opcode[1][2] = "adc     ";
        shared_opcode[1][3] = "sbb     ";
        shared_opcode[1][4] = "and     ";
        shared_opcode[1][5] = "sub     ";
        shared_opcode[1][6] = "xor     ";
        shared_opcode[1][7] = "cmp     ";

        /*
         * Group of Shared opcode
         */
        opcode_group[128] = 1;
        opcode_group[129] = 1;
        opcode_group[130] = 1;
        opcode_group[131] = 1;

        /*
         * Table for 64 bit registers. It taken from os dev wiki page, "Registers table"
         */
        reg_table_64 [0] = "%rax";
        reg_table_64 [1] = "%rcx";
        reg_table_64 [2] = "%rdx";
        reg_table_64 [3] = "%rbx";
        reg_table_64 [4] = "%rsp";
        reg_table_64 [5] = "%rbp";
        reg_table_64 [6] = "%rsi";
        reg_table_64 [7] = "%rdi";
        reg_table_64 [8] = "%r8";
        reg_table_64 [9] = "%r9";
        reg_table_64[10] = "%r10";
        reg_table_64[11] = "%r11";
        reg_table_64[12] = "%r12";
        reg_table_64[13] = "%r13";
        reg_table_64[14] = "%r14";
        reg_table_64[15] = "%r15";
   
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
            send_fetch_req = (fetch_offset - decode_offset < 7'd32);
            if(jump_signal && !bus.respcyc) begin
                jump_flag = 0;
                send_fetch_req = 1;
            end
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
            if(!bus.respcyc) begin
            if(!data_req && !store_ins) begin
                // Sending a reques for instructions
                if(send_fetch_req)
                    outstanding_fetch_req <= 1;
                bus.req <= fetch_rip & ~63;
                bus.reqtag <= { bus.READ, bus.MEMORY, 8'b0 };
                bus.reqcyc <= send_fetch_req;
            end
            else if(store_ins && store_done) begin
                if(!outstanding_fetch_req) begin
                    if(cycle == 1) begin
                        bus.req <= (data_reqAddr & ~63);
                        bus.reqcyc <= 1;
                        bus.reqtag <= { bus.WRITE, bus.MEMORY, {6'b0,1'b1,1'b1}};
                        cycle <= 0;
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
                    outstanding_fetch_req <= 1;
//                    outstanding_data_req <= 1;
                    //$finish;
                end
            end
            end

    
            if (bus.respcyc && (bus.resptag[7:0] == 0)) begin
                if(!jump_flag) begin
                    /*
                    * It takes around 48 micro seconds for a response to come back.
                    */
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
                end
                else begin
                    /*
                    * A jump is found and we need to resteer the fetch
                    */
                    fetch_rip <= (jump_target & ~63);
                    decode_buffer <= 0;
                    /* verilator lint_off WIDTH */
                    fetch_skip <= (jump_target[58:63])&(~7);
                    internal_offset <= (jump_target[58:63])&(7);
                    //$write("io = %0h fs = %0h",internal_offset,fetch_skip);
                    fetch_offset <= 0;
                    jump_signal <= 1;
                end
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
                if(!jump_flag)
                    jump_signal <= 0;
                else begin
                    /*
                    * A jump is found and we need to resteer the fetch
                    */
                    fetch_rip <= (jump_target & ~63);
                    decode_buffer <= 0;
                    /* verilator lint_off WIDTH */
                    fetch_skip <= (jump_target[58:63])&(~7);
                    internal_offset <= (jump_target[58:63])&(7);
                    //$write("io = %0h fs = %0h",internal_offset,fetch_skip);
                    fetch_offset <= 0;
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
    wire can_decode = (fetch_offset - decode_offset >= 7'd15);
     
    function logic opcode_inside(logic[7:0] value, low, high);
        opcode_inside = (value >= low && value <= high);
    endfunction

    /*
     * Function to Swap 32 bit value. Returns the swapped value
     */
    function logic[0 : 4*8-1] byte_swap(logic[0 : 4*8-1] inp);
        logic[0 : 4*8-1] ret_val;
        ret_val[0*8 : 1*8-1] = inp[3*8 : 4*8-1];
        ret_val[1*8 : 2*8-1] = inp[2*8 : 3*8-1];
        ret_val[2*8 : 3*8-1] = inp[1*8 : 2*8-1];
        ret_val[3*8 : 4*8-1] = inp[0*8 : 1*8-1];
        byte_swap = ret_val;
    endfunction

    function logic[0 : 2*8-1] byte1_to_str(logic[0 : 1*8-1] inp);
        logic[0:2*8-1] ret_val;
        logic[0:15][0:0][0:7] hextoa;
        logic[0:7] ii = 0;
        logic[0:7] ret_len = 0;
        
        hextoa[0]  = 48; hextoa[1] = 49; hextoa[2] = 50; hextoa[3] = 51; hextoa[4] = 52; 
        hextoa[5]  = 53; hextoa[6] = 54; hextoa[7] = 55; hextoa[8] = 56; hextoa[9] = 57;
        hextoa[10] = 97; hextoa[11] = 98; hextoa[12] = 99; hextoa[13] = 100; hextoa[14] = 101; 
        hextoa[15] = 102;

        // Code to remove leading zeros
        // while (ii < 8 && inp[ii*4 +: 4] == 0) ii++;

        while (ii < 2) begin
            ret_val[ret_len*8 +: 8] = hextoa[inp[ii*4 +: 4]];
            ret_len++;
            ii++;
        end
        
        byte1_to_str = ret_val;
    endfunction
    
    function logic[0 : 8*8-1] byte4_to_str(logic[0 : 4*8-1] inp);
        logic[0:8*8-1] ret_val;
        logic[0:15][0:0][0:7] hextoa;
        logic[0:7] ii = 0;
        logic[0:7] ret_len = 0;
        
        hextoa[0]  = 48; hextoa[1] = 49; hextoa[2] = 50; hextoa[3] = 51; hextoa[4] = 52; 
        hextoa[5]  = 53; hextoa[6] = 54; hextoa[7] = 55; hextoa[8] = 56; hextoa[9] = 57;
        hextoa[10] = 97; hextoa[11] = 98; hextoa[12] = 99; hextoa[13] = 100; hextoa[14] = 101; 
        hextoa[15] = 102;

        // Code to remove leading zeros
        // while (ii < 8 && inp[ii*4 +: 4] == 0) ii++;

        while (ii < 8) begin
            ret_val[ret_len*8 +: 8] = hextoa[inp[ii*4 +: 4]];
            ret_len++;
            ii++;
        end
        
        byte4_to_str = ret_val;
    endfunction

    function logic[0 : 16*8-1] byte8_to_str(logic[0 : 8*8-1] inp);
        logic[0 : 16*8-1] ret_val;
        logic [0:15][0:0][0:7] hextoa;
        logic [0:7] ii = 0;
        logic [0:7] ret_len = 0;
        
        hextoa[0]  = 48; hextoa[1] = 49; hextoa[2] = 50; hextoa[3] = 51; hextoa[4] = 52; 
        hextoa[5]  = 53; hextoa[6] = 54; hextoa[7] = 55; hextoa[8] = 56; hextoa[9] = 57;
        hextoa[10] = 97; hextoa[11] = 98; hextoa[12] = 99; hextoa[13] = 100; hextoa[14] = 101; 
        hextoa[15] = 102;
        
        // Code to remove leading zeros
        // while (ii < 16 && inp[ii*4 +: 4] == 0) ii++;

        while (ii < 16) begin
            ret_val[ret_len*8 +: 8] = hextoa[inp[ii*4 +: 4]];
            ret_len++;
            ii++;
        end
        
        byte8_to_str = ret_val;
    endfunction

    /*
     * Returns the Instruction for a 2 byte Opcode value, i.e. of form "0F <opcode>"
     */
    function logic[0 : 8*8-1] decode_2_byte_opcode (logic[0 : 7] opcode);
        logic[0 : 8*8-1] inst;

        if (opcode == 5)        inst = "syscall ";   // 0F 05
        else if (opcode == 128) inst = "jo      ";   // 0F 80
        else if (opcode == 129) inst = "jno     ";   // 0F 81
        else if (opcode == 130) inst = "jb      ";   // 0F 82
        else if (opcode == 131) inst = "jae     ";   // 0F 83
        else if (opcode == 132) inst = "je      ";   // 0F 84
        else if (opcode == 133) inst = "jne     ";   // 0F 85
        else if (opcode == 134) inst = "jbe     ";   // 0F 86
        else if (opcode == 135) inst = "ja      ";   // 0F 87
        else if (opcode == 136) inst = "js      ";   // 0F 88
        else if (opcode == 137) inst = "jns     ";   // 0F 89
        else if (opcode == 138) inst = "jpe     ";   // 0F 8A
        else if (opcode == 139) inst = "jpo     ";   // 0F 8B
        else if (opcode == 140) inst = "jl      ";   // 0F 8C
        else if (opcode == 141) inst = "jge     ";   // 0F 8D
        else if (opcode == 142) inst = "jle     ";   // 0F 8E
        else if (opcode == 143) inst = "jg      ";   // 0F 8F
        else if (opcode == 175) inst = "imul    ";   // 0F AF
        else begin
            assert(0) else $fatal(1, "Invalid 2 byte Opcode");
            inst = "        ";  
        end

        decode_2_byte_opcode = inst;
    endfunction

    /*
     * Function to compute absolute address given current program address, relative address and length of instruction
     */
    function logic[0 : 63] rel_to_abs_addr(logic[0 : 63] prog_counter, logic[0 : 31] rel_addr, logic[0 : 3] length);
        logic[0 : 63] abs_addr;
        logic[0 : 63] signed_rel_addr;
        signed_rel_addr = {{32{rel_addr[0]}}, rel_addr};
        abs_addr = prog_counter + signed_rel_addr + {60'b0, length};
        rel_to_abs_addr = abs_addr;
    endfunction

    /* verilator lint_off UNDRIVEN */
    function print_prog_bytes(logic[0 : 15*8-1] prog_bytes, logic[0 : 3] size);
        logic[0 : 3] ii = 0;
        for(ii = 0; ii < size; ii++) begin
            $write(" %x", prog_bytes[ii*8 +: 1*8]);
        end
        for(ii = size; ii < 11; ii++) begin
            $write("   ");
        end
    endfunction

    function logic check_dep();
        logic depp = 0;
        logic[0 : 3] ii = 0;
        for(ii = 0; ii < 14; ii++) begin
            if(score_board[ii] == 1)
                depp = 1;
        end
        check_dep = depp;
    endfunction


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

    /*
    All deifinitions (state elements) for DECODER goes here
    */
    logic[0 : 3] bytes_decoded_this_cycle;
    logic[0 : 7] opcode;
    logic[0 : 3] offset;
    logic[0 : 23] opcode_enc_byte; // Store encoding for given opcode
    logic[0 : 4*8-1] disp_byte;
    logic[0 : 4*8-1] imm_byte;
    logic[0 : 3] regByte;
    logic[0 : 3] rmByte;
    logic[0 : 4*8-1] high_byte;
    logic[0 : 4*8-1] low_byte;
    logic rip_flag;


    /*
     * Signed immediate and displacement variable declaration. try to re-use these variables
     */
    logic[0 : 63] signed_imm_byte;
    logic[0 : 7] short_imm_byte;
    logic[0 : 63] signed_disp_byte;
    logic[0 : 7] short_disp_byte;
    
    logic[0 : 7][0 : 7] prefix_char;
    logic[0 : 7] prefix;
    logic[0 : 7] temp_prefix;
    rex rex_prefix;
    mod_rm modRM_byte;

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


    always_comb begin
        dependency = 0;

        if(can_writeback == 1 || jump_signal == 1 || jump_cond_signal == 1 || data_req == 1 || memstage_active == 1 || store_memstage_active == 1 )
            can_decode = 0;

        if (can_decode) begin : decode_block
            // Variables which are to be reset for each new decoding
            offset = 0;
            opcode_enc_byte = 0;
            disp_byte = 0;
            imm_byte = 0;
            short_disp_byte = 0;
            high_byte = 0;
            low_byte = 0;
            rex_prefix = 0;
            prefix = 0;
            jump_target = 0;
            loadbuffer_done = 0;
            data_reqFlag = 0;
            store_word = 0;
            store_ins = 0;
            for (i = 0; i < 32 ; i++) begin
                reg_buffer[i*8 +: 8] = " "; 
            end
            instr_buffer = empty_str; 
   
            // Compute program address for next instruction
            rip = fetch_rip - {57'b0, (fetch_offset - decode_offset)};

            /*
             * Prefix decoding
             */
            temp_prefix = decode_bytes[offset*8 +: 1*8];
            opcode_enc_byte = opcode_enc[temp_prefix];
            while (opcode_enc_byte == "PRE") begin
                prefix = temp_prefix;
                prefix_char = opcode_char[prefix];
                if (prefix_char == "rex     ")
                    rex_prefix = prefix;

                space_buffer[(offset)*8 +: 8] = prefix;
                offset += 1;

                // Search if next byte is also a prefix
                temp_prefix = decode_bytes[offset*8 +: 1*8];
                opcode_enc_byte = opcode_enc[temp_prefix];
            end
            opcode_enc_byte = 0;

           /*
            * For instructions with either a REX prefix OR No prefix Opcode decoding
            */
            if (rex_prefix != 0 || prefix == 0) begin
                /*
                 * Opcode decoding
                 */
                opcode = decode_bytes[offset*8 +: 1*8];
                opcode_contents = opcode; // This is for storing the value in the pipeline reg
                space_buffer[(offset)*8 +: 8] = opcode;
                offset += 1;

                /*
                 * ALL SPECIAL CASES GOES UPFRONT
                 */
                if (opcode == 13) begin
                    /* Special case for OR instruction */
                    imm_byte = decode_bytes[offset*8 +: 4*8]; 
                    space_buffer[(offset)*8 +: 4*8] = imm_byte;
                    offset += 4; // Assuming immediate values as 4. Correct?
                    reg_buffer[0:135] = {{"$0x"}, {byte4_to_str(byte_swap(imm_byte))}, {", "}, {reg_table_64[0]}};
                 
                    if(score_board[0] == 0) begin
                        /*
                        * If register is available (i.e score board val is 0)
                        */
                        imm_contents = {{32{1'b0}}, {imm_byte}};
                        imm_contents = {{byte_swap(imm_contents[0:31])}, {byte_swap(imm_contents[32:63])}};
                        regB_contents = {64{1'b0}};
                        regA_contents = regfile[0]; // Statically assigning 0 because it is RAX for opcode 13
                        rmByte_contents = 0;
                        regByte_contents = 0; //{4{1'b0}};
                        dependency = 1;
                    end
                    else begin
                        offset = 0;
                        can_decode = 0;
                        enable_memstage = 0;
                    end

                end
                if (opcode == 108) begin
                    /* INSB instruction */
                    instr_buffer = opcode_char[opcode];
                    reg_buffer[0:135] = {"(%dx), %es:(%rdi)"};
             
                end else if (opcode == 111) begin
                    /* OUTSB instruction */
                    instr_buffer = opcode_char[opcode];
                    reg_buffer[0:135] = {"%ds:(%rsi), (%dx)"};

                end else if ((opcode >= 80 && opcode <= 95)) begin
                    /*
                     * Special case for PUSH/POP
                     * Refer to Table 3-1 of Intel Manual
                     */
                    instr_buffer = opcode_char[opcode];

                    if (opcode >= 88)
                        opcode = opcode - 8;

                    opcode = opcode - 80;
                    reg_buffer[0:31] = reg_table_64[opcode];

                    if(score_board[opcode[0:3]] == 0) begin
                        // Checking for availability of registers
                        regA_contents = regfile[opcode[0:3]]; // Get the 8 byte register content and store in temp register
                        regB_contents = {{64{1'b1}}};
                        dependency = 1;
                    end
                    else begin
                        offset = 0;
                        can_decode = 0;
                        enable_memstage = 0;
                    end

                end // End of Opcode for Special PUSH/POP block

                else if ((opcode >= 184) && (opcode <= 191)) begin
                    /*
                     * If the opcode is between B8 to BF, then it is 64 bit operand
                     * Refer to section 2.2.1.5 of the manual
                     */
                    high_byte = decode_bytes[offset*8 +: 4*8];
                    space_buffer[(offset)*8 +: 4*8] = byte_swap(high_byte);
                    offset += 4;
                    low_byte = decode_bytes[offset*8 +: 4*8];
                    space_buffer[(offset)*8 +: 4*8] = byte_swap(low_byte);
                    offset += 4;

                    reg_buffer[0:199] = {{"$0x"}, {byte8_to_str({byte_swap(low_byte), byte_swap(high_byte)})},
                                  {", "}, {reg_table_64[opcode - 184]} };
                    instr_buffer = opcode_char[opcode];

                    if(score_board[opcode - 184] == 0) begin
                        regA_contents = regfile[opcode - 184];
                        regB_contents = {64{1'b1}};
                        imm_contents = {{byte_swap(low_byte)}, {byte_swap(high_byte)}};
                        opcode = opcode - 184;
                        rmByte_contents = opcode[4:7];
                        //$write("opcode = %s rm %0h",reg_table_64[rmByte_contents], rmByte_contents);
                        regByte_contents = 0;
                        dependency = 1;
                    end
                    else begin
                        can_decode = 0;
                        enable_memstage = 0;
                        offset = 0;
                    end

                end // End of Opcode for Special MOV block

                else if ((opcode == 193) || (opcode == 209) || (opcode == 211)) begin //Begin of SHIFT Instructions
                    /*
                     * SHIFT Left and Right Logic
                     * Case 193 : SHR r/m64, imm8 ==> Shift Register r/m64 right by imm8 bits (Op/En : "MI")
                     * Case 209 : SHR r/m64, 1    ==> Shift Register r/m64 right by 1 bit     (Op/En : "M1")
                     * Case 211 : SHR r/m64, cl   ==> Shift Register r/m64 right by cl bits   (Op/En : "MC")
                     * 
                     * If reg = 4, then 
                     *       SHIFT Left 
                     *   else if reg = 5
                     *       SHIFT Right
                     */
                    modRM_byte = decode_bytes[offset*8 +: 1*8];
                    space_buffer[(offset)*8 +: 8] = modRM_byte;
                    offset += 1;

                    if(modRM_byte.reg1 == 4)
                        instr_buffer = {"shl     "};
                    else if(modRM_byte.reg1 == 5)
                        instr_buffer = {"shr     "};

                    rmByte = {{rex_prefix.B}, {modRM_byte.rm}};
                    opcode_enc_byte = opcode_enc[opcode];

                    if (opcode_enc_byte == "MI ") begin
                        imm_byte[0:7] = decode_bytes[offset*8 +: 1*8]; 
                        space_buffer[(offset)*8 +: 1*8] = imm_byte[0:7];
                        offset += 1;
                        reg_buffer[0:87] = {{"$0x"}, {byte1_to_str(imm_byte[0:7])}, {", "}, {reg_table_64[rmByte]}};
                        if(score_board[rmByte] == 0) begin
                            //$write("Inside MI");
                            //regByte_contents = regByte;
                            rmByte_contents = rmByte;
                            regA_contents = regfile[rmByte];
                            regB_contents = {{61{1'b0}}, {modRM_byte.reg1}};
                            imm_contents = {{56{1'b0}}, {imm_byte[0:7]}};
                            dependency = 1;
                        end
                    end
                    /* No Test Case for mod encode = M1 or MC */
                    else if (opcode_enc_byte == "M1 ") begin
                        reg_buffer[0:87] = {{"$0x01, "}, {reg_table_64[rmByte]}};
                    end
                    else if (opcode_enc_byte == "MC ") begin
                        reg_buffer[0:71] = {{"%cl"}, {", "}, {reg_table_64[rmByte]}};
                    end
                    else begin
                        assert(0) else $fatal(1, "Invalid Mod RM Encoding for SHIFT");
                    end
                end // End of Opcode for SHIFT Block
                
                else begin 
                    /*
                     * General Decode Logic for Instructions
                     */
                    if (opcode == 15) begin
                        /*
                         * We have got a two byte opcode. Pretend as though nothing happened and 
                         * over write the opcode with the next byte. 
                         * Now it appears to the program that only one byte opcode occured.
                         */
                        opcode = decode_bytes[offset*8 +: 1*8];
                        space_buffer[(offset)*8 +: 8] = opcode;
                        offset += 1;

                        instr_buffer = decode_2_byte_opcode(opcode);

                        // All the 2 byte Opcodes except "0F 05/AF" have a 4 byte displacement
                        if (opcode == 5)        // 0F 05 (syscall)
                            opcode_enc_byte = "XXX";
                        else if (opcode == 175) // 0F AF (imul)
                            opcode_enc_byte = "RM ";
                        else                    // 0F xx (jump inst)
                            opcode_enc_byte = "D4 ";

                    end else begin
                        instr_buffer = opcode_char[opcode];
                        opcode_enc_byte = opcode_enc[opcode];
                    end

                    assert(opcode_enc_byte != 0) else $fatal;

                    if (opcode_enc_byte[0:7] == "M" || opcode_enc_byte[0:7] == "R") begin
                        /*
                         * We have found a Mod R/M byte for MR, RM, M, MI, MIS
                         * The direction (source / destination is available in opcode_enc value")
                         */
                        modRM_byte = decode_bytes[offset*8 +: 1*8];
                        space_buffer[(offset)*8 +: 8] = modRM_byte;
                        offset += 1;

                        /*
                         * Check if there is a displacement in the instruction
                         * If mod bit == 0 and RM bit == 5, then 32 bit disp
                         * If mod bit == 1 then 8 bit disp
                         * If mod bit == 2 then 32 bit disp
                         * If mod bit == 3 then No disp 
                         */
                        if ((modRM_byte.mod == 0 && modRM_byte.rm == 5) || modRM_byte.mod == 2) begin
                            disp_byte = decode_bytes[offset*8 +: 4*8];
                            space_buffer[(offset)*8 +: 4*8] = disp_byte;
                            offset += 4;
                        end
                        else if (modRM_byte.mod == 1) begin
                            short_disp_byte = decode_bytes[offset*8 +: 1*8];
                            space_buffer[(offset)*8 +: 8] = short_disp_byte;
                            offset += 1;
                        end 
                        /*
                         * RIP Addressing
                         */
                        if ((modRM_byte.mod == 0 && modRM_byte.rm == 5))
                            rip_flag = 1;
                        else
                            rip_flag = 0;
                    end

                    /*
                     * PRINT CODE BLOCK
                     * Depending on REX prefix, print the registers
                     * !!! WARNING: Printing is done in reverse order to ensure
                     *     readability. INTEL and GNU's ONJDUMP follow opposite
                     *     syntax
                     * If Op Encode(in instruction reference of the manual) is MR, it is in
                     * the following format. Operand1: ModRM:r/m  Operand2: ModRM:reg (r) 
                     */
                    regByte = {{rex_prefix.R}, {modRM_byte.reg1}};
                    rmByte = {{rex_prefix.B}, {modRM_byte.rm}};

                    if (rex_prefix != 0 && opcode >= 128 && opcode <= 131) begin
                        // We might have a shared opcode 
                        instr_buffer = shared_opcode[opcode_group[opcode]][regByte];
                    end

                    if (opcode_enc_byte == "M  ") begin

                        if (modRM_byte.mod == 3) begin
                            /*
                             * Case for IMUL instruction
                             */
                            reg_buffer[0:31] = {reg_table_64[rmByte]};
                            if(score_board[rmByte] == 0 && score_board[0] == 0) begin
                                // Both RAX and dest register should be available
                                // If we reach here, we are good
                                //regByte_contents = regByte;
                                regByte_contents = 0;
                                rmByte_contents = rmByte;
                                regA_contents = regfile[rmByte];
                                regB_contents = regfile[0]; // HACK. We cannot directly use regfile[0] in ALU
                                imm_contents = {64{1'b0}};
                                dependency = 2;
                            end
                            else begin
                                offset = 0;
                                can_decode = 0;
                                enable_memstage = 0;
                            end
                        end
                        else begin
                            // reg bits need to be 2
                            assert(modRM_byte.reg1 == 2) else $fatal;
                            reg_buffer[0:39] = {{"*"} , {reg_table_64[rmByte]}};
                        end
                        
                    end

                    else if (opcode_enc_byte == "MR ") begin
                        /*
                         * Register addressing mode
                         */ 
                        if (modRM_byte.mod == 3) begin
                            /*
                             * There is no displacement and no index registers
                             */
                            reg_buffer[0:79] = {{reg_table_64[regByte]}, {", "}, {reg_table_64[rmByte]}};
                            if((score_board[regByte] == 0) && (score_board[rmByte] == 0)) begin
                                regByte_contents = regByte;
                                rmByte_contents = rmByte;
                                regA_contents = regfile[regByte];
                                regB_contents = regfile[rmByte];
                                imm_contents = {64{1'b0}};
                                dependency = 2;
                            end
                            else begin
                                offset = 0;
                                can_decode = 0;
                                enable_memstage = 0;
                            end

                        end
                        else if (disp_byte != 0) begin
                            /*
                            * It is NOT sign extended. The displacement value is 32 bits
                            */
                            if(rip_flag == 1) begin
                                reg_buffer[0:183] = {{reg_table_64[regByte]}, {", $0x"}, {byte4_to_str(byte_swap(disp_byte))}, {"("},
                                            {"%rip"}, {")"}};
                            end
                            else begin
  
                                if (modRM_byte.rm == 5) begin
                                    /*
                                     * This is a special case. For this very particular case, the value 0xffffff08
                                     * is displayed as 0xffffffffffffff08. So extending and storing in the reg buffer here.
                                     * I believe this is some of the OPCODE Exceptions.
                                     */
                                    signed_disp_byte = {{32{1'b1}}, {byte_swap(disp_byte)}};
                                    reg_buffer[0:247] = {{reg_table_64[regByte]}, {", $0x"}, {byte8_to_str(signed_disp_byte)},
                                        {"("}, {reg_table_64[rmByte]}, {")"}};
                                end

                                else begin
                                    reg_buffer[0:183] = {{reg_table_64[regByte]}, {", $0x"}, {byte4_to_str(byte_swap(disp_byte))}, {"("},
                                            {reg_table_64[rmByte]}, {")"}};
                                    $write("found you");
                                    if((score_board[rmByte] == 0) && (score_board[regByte] == 0)) begin
                                          store_reqFlag = 1;
                                          data_reqAddr = byte_swap(disp_byte) + regfile[rmByte];
                                          store_word = regfile[regByte];
                                          store_ins = 1;
                                          dependency = 2;
                                      end
                                      else begin
                                          offset = 0;
                                          can_decode = 0;
                                          enable_memstage = 0;
                                      end
                                end
                            end

                        end
                        else if (short_disp_byte != 0) begin
                            /*
                            * The displacement value is SIGN extended
                            */
                            signed_disp_byte = {{56{short_disp_byte[0]}}, {short_disp_byte}};
                            reg_buffer[0:247] = {{reg_table_64[regByte]}, {", $0x"}, {byte8_to_str(signed_disp_byte)},
                                            {"("}, {reg_table_64[rmByte]}, {")"}};
                        end
                        else begin
                            /*
                             * There is no displacement but only index registers
                             */
                            assert(modRM_byte.mod == 0) else $fatal;
                            reg_buffer[0:95] = {{reg_table_64[regByte]}, {", "}, {"("}, {reg_table_64[rmByte]}, {")"}};
                        end
                    end

                    else if (opcode_enc_byte == "RM ") begin
                        /*
                         * Register addressing mode
                         * The direction of source and destination are interchanged
                         */
                        if (modRM_byte.mod == 3) begin
                            /*
                             * There is no displacement and index register
                             */
                            reg_buffer[0:79] = {{reg_table_64[rmByte]}, {", "}, {reg_table_64[regByte]}};
                            if((score_board[regByte] == 0) && (score_board[rmByte] == 0)) begin
                                regByte_contents = regByte;
                                rmByte_contents = rmByte;
                                regA_contents = regfile[regByte];
                                regB_contents = regfile[rmByte];
                                imm_contents = {64{1'b0}};
                            end
                            else begin
                                offset = 0;
                                enable_memstage = 0;
                            end

                        end
                        else if (disp_byte != 0) begin
                            /*
                            * It is NOT sign extended. The displacement value is 32 bits
                            */
                            if(rip_flag == 1)
                                reg_buffer[0:183] = {{"$0x"}, {byte4_to_str(byte_swap(disp_byte))}, {"("}, {"%rip"}, {"), "},
                                            {reg_table_64[regByte]}};
                            else begin
                                if (modRM_byte.rm == 5) begin
                                      /*
                                      * This is a special case. For this very particular case, the value 0xffffff08
                                      * is displayed as 0xffffffffffffff08. So extending and storing in the reg buffer here.
                                      * I believe this is some of the OPCODE Exceptions.
                                      */
                                       signed_disp_byte = {{32{1'b1}}, {byte_swap(disp_byte)}};
                                       reg_buffer[0:247] = {{"$0x"}, {byte8_to_str(signed_disp_byte)}, {"("}, {reg_table_64[rmByte]},
                                            {"), "}, {reg_table_64[regByte]}};
                                end
                                else begin
                                      //$write("found you");
                                      reg_buffer[0:183] = {{"$0x"}, {byte4_to_str(byte_swap(disp_byte))}, {"("}, {reg_table_64[rmByte]}, {"), "},
                                            {reg_table_64[regByte]}};
                                      if((score_board[rmByte] == 0) && (score_board[regByte] == 0)) begin
                                          data_reqFlag = 1;
                                          data_reqAddr = byte_swap(disp_byte) + regfile[rmByte];
                                          regByte_contents = regByte;
                                          rmByte_contents = rmByte;
                                          dependency = 2;
                                      end
                                      else begin
                                          offset = 0;
                                          can_decode = 0;
                                          enable_memstage = 0;
                                      end
                                end
                            end

                        end
                        else if (short_disp_byte != 0) begin
                            /*
                            * The displacement value is SIGN extended
                            */
                            signed_disp_byte = {{56{short_disp_byte[0]}}, {short_disp_byte}};
                            reg_buffer[0:247] = {{"$0x"}, {byte8_to_str(signed_disp_byte)}, {"("}, {reg_table_64[rmByte]},
                                            {"), "}, {reg_table_64[regByte]}};
                        end
                        else begin
                            /*
                             * There is no displacement but only index registers
                             */
                            assert(modRM_byte.mod == 0) else $fatal;
                            if(rip_flag == 1)
                                reg_buffer[0:95] = {{"("}, {"%rip"}, {"), "}, {reg_table_64[regByte]}};
                            else
                                reg_buffer[0:95] = {{"("}, {reg_table_64[rmByte]}, {"), "}, {reg_table_64[regByte]}};
                        end
                    end

                    else if (opcode_enc_byte == "MI ") begin
                        /*
                         * Immediate addressing mode
                         */
                        imm_byte = decode_bytes[offset*8 +: 4*8]; 
                        space_buffer[(offset)*8 +: 4*8] = imm_byte;
                        offset += 4; // Assuming immediate values as 4. Correct?
                        reg_buffer[0:135] = {{"$0x"}, {byte4_to_str(byte_swap(imm_byte))}, {", "}, {reg_table_64[rmByte]}};
                        
                        /*
                         *
                         * This is to add into the pipeline register
                         * Immediate bytes present so regB_contents NA
                         * Set pipeline regByte to bits 3, 4, 5 of MOD R/m for Group Encoding
                         * Load register rmByte from Regfile into regA_contents
                         * DO NOT USE regByte unless opcode is a shared opcode.
                         */
                        
                        imm_contents = {{32{1'b0}}, {imm_byte}};
                        imm_contents = {{byte_swap(imm_contents[0:31])}, {byte_swap(imm_contents[32:63])}};
                        if(score_board[rmByte] == 0) begin
                            regB_contents = {64{1'b0}};
                            regA_contents = regfile[rmByte];
                            rmByte_contents = rmByte;
                            regByte_contents = regByte; //{4{1'b0}};
                            dependency = 1;
                        end
                        else begin
                            offset = 0;
                            can_decode = 0;
                            enable_memstage = 0;
                        end

                        /*
                        Dont know why I wrote this code. Keep it. Do not delete
                        if (disp_byte != 0) begin
                            $write("$0x%x(%s)",byte_swap(disp_byte), reg_table_64[regByte]);
                        end else begin
                            $write("%s",reg_table_64[regByte]);
                        end*/
                    end

                    else if (opcode_enc_byte == "MIS") begin
                        /*
                         * Signed extension
                         * Right now handling only 1 byte immediate to sign extension
                         */

                        short_imm_byte = decode_bytes[offset*8 +: 1*8]; 
                        space_buffer[(offset)*8 +: 8] = short_imm_byte;
                        offset += 1;
                        signed_imm_byte = {{56{short_imm_byte[0]}}, {short_imm_byte}};
                    
                        /*
                         *
                         * This is to add into the pipeline register
                         * Immediate bytes present so regB_contents NA
                         * Set pipeline regByte to bits 3, 4, 5 of MOD R/m for Group Encoding
                         * Load register rmByte from Regfile into regA_contents
                         * DO NOT USE regByte unless opcode is a shared opcode.
                         *
                         */
                         
                        imm_contents = signed_imm_byte;
                        regB_contents = {64{1'b0}};
                        reg_buffer[0:199] = {{"$0x"}, {byte8_to_str(signed_imm_byte)}, {", "}, {reg_table_64[rmByte]}};
                        if(score_board[rmByte] == 0) begin
                            regB_contents = {64{1'b0}};
                            regA_contents = regfile[rmByte];
                            rmByte_contents = rmByte;
                            regByte_contents = regByte;
                            dependency = 1;
                        end
                        else begin
                            offset = 0;
                            can_decode = 0;
                            enable_memstage = 0;
                        end
                    
                    end

                    else if (opcode_enc_byte == "D1 ") begin
                        /*
                         * 1 byte relative displacement
                         */
                        short_disp_byte = decode_bytes[offset*8 +: 1*8];
                        space_buffer[(offset)*8 +: 8] = short_disp_byte;
                        offset += 1;
                         
                        disp_byte = {{24{short_disp_byte[0]}}, {short_disp_byte}};
                        temp_crr = rel_to_abs_addr(rip, disp_byte, offset);
                        reg_buffer[0:151] = {{"$0x"}, {byte8_to_str(temp_crr)}};
                        
                        if(opcode == 235) begin
                            bytes_decoded_this_cycle = 0;
                            enable_memstage = 0;
                            jump_flag = 1; // Unconditional jump
                        end
                        else 
                            jump_cond_flag = 1; // Conditional jump
                        
                        jump_target = temp_crr;
                    end

                    else if (opcode_enc_byte == "D4 ") begin
                        /*
                         * 4 byte relative displacement
                         * Conditional Jumps
                         */
                        disp_byte = decode_bytes[offset*8 +: 4*8];
                        space_buffer[(offset)*8 +: 4*8] = disp_byte;
                        offset += 4;
     
                        temp_crr = rel_to_abs_addr(rip, byte_swap(disp_byte), offset);
                        reg_buffer[0:151] = {{"$0x"}, {byte8_to_str(temp_crr)}};
                        bytes_decoded_this_cycle = 0;
                        jump_cond_flag = 1;
                        enable_memstage = 0;
                        jump_target = temp_crr;
                    end
                end
            end else begin
                /* Dont need to support other Prefixes. Just printing out the prefix name */
                instr_buffer = opcode_char[prefix];
            end 

            // Print Instruction Encoding for non empty opcode_char[] entries
            // Also enable execution phase only if decoder can correctly decode the bytes
            if ((instr_buffer != empty_str) && can_decode) begin
                $write("  %0h:    ", rip);
                print_prog_bytes(space_buffer, offset);
                $write("%s%s\n", instr_buffer, reg_buffer);
                enable_memstage = 1;
                if(jump_flag == 1) begin
                      can_decode = 0;
                      enable_memstage = 0;
                end
                else if(jump_cond_flag == 1) begin
                      can_decode = 0;
                end
                else if(data_reqFlag == 1) begin
                      can_decode = 0;
                end
                else if(store_reqFlag == 1) begin
                      can_decode = 0;
                end

            end
            else begin
                enable_memstage = 0;
            end

            bytes_decoded_this_cycle =+ offset;

            // Note: Currently we finish on retq instruction. Later we might want to change below condition.
            if (instr_buffer == "retq    ") begin
                can_decode = 0;
                enable_memstage = 0;
                sim_end_signal = 1; // Simulation should end
            end
            else
                sim_end_signal = 0; // Simulation should not end

        end else begin
            enable_memstage = 0;
            bytes_decoded_this_cycle = 0;
        end
    end

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

  
    /*
    * This is the ALU block. Any comments about ALU add here.
    * Info about RFLAGS for each instruction
    * ADD:
    *     It sets the OF and the CF flags to indiciate a carry(overflow) in the signed or unsigned result. 
          The SF indicates the sign of the signed result
    */

    logic[0 : 127] data_regAA;
    logic[0 : 127] data_regBB;
    logic[0 : 64] ext_addReg;
    logic[0 : 16*8-1] temp16;

    always_comb begin
        if (can_execute) begin : execute_block

            dep_exwb = memex.ctl_dep;
            sim_end_signal_exwb = memex.sim_end;
            rmByte_contents_exwb = memex.ctl_rmByte;
            opcode_exwb = memex.ctl_opcode;
            //$write("Opcode at execute stage = %x",memex.ctl_opcode);
            if(dep_exwb == 2) begin
                regByte_contents_exwb = memex.ctl_regByte;
            end

            if(memex.ctl_opcode == 199 || (memex.ctl_opcode >= 184 && memex.ctl_opcode <= 191)) begin         //   Mov Imm 
                //regfile[memex.ctl_rmByte] = memex.data_imm;
                alu_result_exwb = memex.data_imm;
                //$write("alu %0h rmByte %0h", alu_result_exwb, rmByte_contents_exwb);
            end

            else if(memex.ctl_opcode == 139) begin
                // Load instruction. ex: mov $0x100(%rax), %rbx
                //$write("Asssigning the value to pipeline register");
                alu_result_exwb = load_buffer; // The load buffer is filled in the mem stage

            end

            else if(memex.ctl_opcode == 141 || memex.ctl_opcode == 125) begin
                // JGE instruction and JNL instruction
                jump_cond_flag = 0;
            end

            else if(memex.ctl_opcode == 116) begin
                // JE instruction
                jump_cond_flag = 0;
                if(rflags_seq.zf == 1) begin
                  jump_flag = 1; // Zero flag is set for JE instruction.
                  //$write("Conditional jump");
                end
            end

            else if(memex.ctl_opcode == 137) begin // Move reg to reg
                alu_result_exwb = regfile[memex.ctl_regByte];
            end

            else if(opcode_group[memex.ctl_opcode] != 0) begin
                // Check table A-6 of INTEL manual
                if(memex.ctl_regByte == 4) begin
                    // AND instruction
                    //$display("data_imm = %0h data_regA = %0h result = %0h", memex.data_imm, memex.data_regA, (memex.data_imm & memex.data_regA));
                    //regfile[memex.ctl_rmByte] = memex.data_imm & memex.data_regA;
                    alu_result_exwb = memex.data_imm & memex.data_regA;
                end
                else if(memex.ctl_regByte == 1) begin
                    // OR Instruction
                    //regfile[memex.ctl_rmByte] = memex.data_imm | memex.data_regA;
                    alu_result_exwb = memex.data_imm | memex.data_regA;
                end
                else if(memex.ctl_regByte == 0) begin
                    // ADD instruction
                    ext_addReg = {65{1'b0}};
                    ext_addReg = memex.data_imm + memex.data_regA;
                    //$write("data_imm = %0h, data_regA = %0h ext_addReg = %0h",memex.data_imm, memex.data_regA, ext_addReg[1:64]);
                    alu_result_exwb = ext_addReg[1:64];
                    rflags.cf = ext_addReg[64];
                end
                else if(memex.ctl_regByte == 7) begin
                    // CMP instruction
                    // We need to set the RFLAGS for the jump ins to properly execute
                    /*
                    * Zero flag is set when the operands are equal
                    */
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
  //              $write("alu %0h %0h",memex.data_regA, memex.data_regB);
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
                // SHR & SHL instruction is with reg operands 
                /*
                 * Opcode for SHL and SHR
                 * In Mod R/M Byte,
                 * If reg = 4, then 
                 *       SHIFT Left 
                 *   else if reg = 5
                 *       SHIFT Right
                 */
                alu_result_exwb = {memex.data_regA};
                if (memex.data_regB == 4)
                    begin
                        for (i = 0; i < memex.data_imm; i = i+1)
                        begin
                            alu_result_exwb = alu_result_exwb * 2;
                        end
                    end
                else
                    begin
                        for (i = 0; i < memex.data_imm; i=i+1)
                        begin
                            alu_result_exwb = alu_result_exwb / 2;
                        end
                    end
            end
            //$display("PC  = %0h, regA = %0h, regB = %0h, disp = %0h, imm = %0h , opcode = %0h, ctl_regByte = %0h, ctl_rmByte = %0h",memex.pc_contents, memex.data_regA, memex.data_regB, memex.data_disp, memex.data_imm, memex.ctl_opcode, memex.ctl_regByte, memex.ctl_rmByte);
            rip_exwb = memex.pc_contents;
            if(memex.ctl_opcode != 125 && memex.ctl_opcode != 116) begin
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
            if(exwb.sim_end == 1)
                $finish;
        end
    end

    always @ (posedge bus.clk) begin
        if (bus.reset) begin
            decode_offset <= 0;
            decode_buffer <= 0;
        end else begin // !bus.reset
            if(!jump_flag)
                decode_offset <= decode_offset + { 3'b0, bytes_decoded_this_cycle };
            else begin
                decode_offset <= 0;
                fetch_offset <= 0;
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

            //if (can_decode) begin

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

            if(!data_reqFlag && !store_reqFlag)
              can_memstage <= 0;
            if(store_opn == 0)
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
