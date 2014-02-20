module Core (
    input[63:0] entry,
    /* verilator lint_off UNDRIVEN */ /* verilator lint_off UNUSED */ Sysbus bus /* verilator lint_on UNUSED */ /* verilator lint_on UNDRIVEN */
);
    
    enum { fetch_idle, fetch_waiting, fetch_active } fetch_state;
    logic[63:0] fetch_rip;
    logic[0:2*64*8-1] decode_buffer; // NOTE: buffer bits are left-to-right in increasing order
    logic[5:0] fetch_skip;
    logic[6:0] fetch_offset, decode_offset;
    
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
    
    logic [0:255][0:2][0:7] mod_rm_enc;
    logic [0:255][0:7][0:7] opcode_char;
    logic [0:15][0:3][0:7] reg_table_64;
    logic [0:7][0:3][0:7] reg_table_32;
    logic [0:7][0:3][0:7] reg_table_8;
    logic [0:7][0:7]empty_str = {"       "};
    logic [0:8] i = 0;
    logic [0:63] prog_addr;
    logic [0:63] temp_crr;

    // 2D Array
    logic [0:8*8-1] opcode_enc[0:14][0:8] ;
    logic [0:255][0:0][0:3] opcode_group;

    logic [0:15*8-1] space_buffer;
    logic [0:7][0:7] instr_buffer;
    logic [0:32*8-1] reg_buffer;
    initial 
    begin
        
        for (i = 0; i < 256; i++)
        begin
            opcode_char[i] = empty_str;
            mod_rm_enc[i] = "   ";
        end 
        /*
         * Following values are converted into decimal from hex.
         * For example, 0x89 is the hex opcode. This is 137 in decimal
         * Also store Mod RM byte encoding for each opcode
         */

        /*
         * First byte of a 2 byte opcode instruction
         */
        opcode_char[15] = "XXXXXXXX"; mod_rm_enc [15] = "XXX"; // 0F

        /*
         * Prefixes: To distinguish with actual instruction opcodes, we set mod_rm_enc as "PRE"
         */
        opcode_char [38] = "es      "; mod_rm_enc [38] = "PRE"; // 26
        opcode_char [46] = "cs      "; mod_rm_enc [46] = "PRE"; // 2E
        opcode_char [54] = "ss      "; mod_rm_enc [54] = "PRE"; // 36
        opcode_char [62] = "dd      "; mod_rm_enc [62] = "PRE"; // 3E
        opcode_char[100] = "fs      "; mod_rm_enc[100] = "PRE"; // 64
        opcode_char[101] = "gs      "; mod_rm_enc[101] = "PRE"; // 65
        opcode_char[102] = "operand "; mod_rm_enc[102] = "PRE"; // 66
        opcode_char[103] = "address "; mod_rm_enc[103] = "PRE"; // 67
        opcode_char[240] = "lock    "; mod_rm_enc[240] = "PRE"; // F0
        opcode_char[242] = "repne   "; mod_rm_enc[242] = "PRE"; // F2
        opcode_char[243] = "repe    "; mod_rm_enc[243] = "PRE"; // F3

        /*
         * REX Prefixes: To distinguish with actual instruction opcodes, we set mod_rm_enc as "PRE"
         */
        opcode_char [64] = "rex     "; mod_rm_enc [64] = "PRE"; // 40
        opcode_char [65] = "rex     "; mod_rm_enc [65] = "PRE"; // 41
        opcode_char [66] = "rex     "; mod_rm_enc [66] = "PRE"; // 42
        opcode_char [67] = "rex     "; mod_rm_enc [67] = "PRE"; // 43
        opcode_char [68] = "rex     "; mod_rm_enc [68] = "PRE"; // 44
        opcode_char [69] = "rex     "; mod_rm_enc [69] = "PRE"; // 45
        opcode_char [70] = "rex     "; mod_rm_enc [70] = "PRE"; // 46
        opcode_char [71] = "rex     "; mod_rm_enc [71] = "PRE"; // 47
        opcode_char [72] = "rex     "; mod_rm_enc [72] = "PRE"; // 48
        opcode_char [73] = "rex     "; mod_rm_enc [73] = "PRE"; // 49
        opcode_char [74] = "rex     "; mod_rm_enc [74] = "PRE"; // 4A
        opcode_char [75] = "rex     "; mod_rm_enc [75] = "PRE"; // 4B
        opcode_char [76] = "rex     "; mod_rm_enc [76] = "PRE"; // 4C
        opcode_char [77] = "rex     "; mod_rm_enc [77] = "PRE"; // 4D
        opcode_char [78] = "rex     "; mod_rm_enc [78] = "PRE"; // 4E
        opcode_char [79] = "rex     "; mod_rm_enc [79] = "PRE"; // 4F

        /*
         * Opcodes for XOR
         */
        opcode_char [49] = "xor     "; mod_rm_enc [49] = "MR "; // 31

        /*
         * Opcodes for AND
         */
        opcode_char [32] = "and     "; mod_rm_enc [32] = "MR "; // 20
        opcode_char [33] = "and     "; mod_rm_enc [33] = "MR "; // 21
        opcode_char[129] = "and     "; mod_rm_enc[129] = "MI "; // 81
        opcode_char[131] = "and     "; mod_rm_enc[131] = "MIS"; // 83
         
        /*
         * Opcodes for MOV
         */
        opcode_char[137] = "mov     "; mod_rm_enc[137] = "MR "; // 89
        opcode_char[139] = "mov     "; mod_rm_enc[139] = "RM "; // 8B
        opcode_char[199] = "mov     "; mod_rm_enc[199] = "MI "; // C7

        /* 
         * Special MOV Opcodes
         */
        opcode_char[184] = "mov     "; mod_rm_enc[184] = "SP "; // B8
        opcode_char[185] = "mov     "; mod_rm_enc[185] = "SP "; // B9
        opcode_char[186] = "mov     "; mod_rm_enc[196] = "SP "; // BA
        opcode_char[187] = "mov     "; mod_rm_enc[187] = "SP "; // BB
        opcode_char[188] = "mov     "; mod_rm_enc[188] = "SP "; // BC
        opcode_char[189] = "mov     "; mod_rm_enc[189] = "SP "; // BD
        opcode_char[190] = "mov     "; mod_rm_enc[190] = "SP "; // BE
        opcode_char[191] = "mov     "; mod_rm_enc[191] = "SP "; // BF
    
        /*
         * Opcodes for Instructions w/o REX Prefixes
         */
        opcode_char[114] = "jb      "; mod_rm_enc[114] = "D1 "; // 72
        opcode_char[232] = "callq   "; mod_rm_enc[232] = "D4 "; // E8
        opcode_char[233] = "jmpq    "; mod_rm_enc[233] = "D4 "; // E9
        opcode_char[235] = "jmp     "; mod_rm_enc[235] = "D1 "; // E9
        opcode_char[255] = "callq   "; mod_rm_enc[255] = "M  "; // FF 
        
        /*
         * Opcodes for Instructions w/o REX Prefixes and w/o MOD RM
         */
        opcode_char[108] = "insb    "; // 6C
        opcode_char[111] = "outsl   "; // 6F

        /*
         * Opcodes for SUB
         */
        opcode_char [41] = "sub     "; mod_rm_enc [41] = "MR " ; // 29

        /*
         * Opcodes for CMP
         */
        opcode_char [57] = "cmp     "; mod_rm_enc [57] = "MR "; // 39
        opcode_char [61] = "cmp     "; mod_rm_enc [61] = "XXX"; 

        /*
         * Opcode for ADD
         */
        opcode_char  [1] = "add     "; mod_rm_enc  [1] = "MR "; // 1
        
        /*
         * Opcode for PUSH
         */
        opcode_char [80] = "push    "; mod_rm_enc [80] = "XXX";
        opcode_char [81] = "push    "; mod_rm_enc [81] = "XXX";
        opcode_char [82] = "push    "; mod_rm_enc [82] = "XXX";
        opcode_char [83] = "push    "; mod_rm_enc [83] = "XXX";
        opcode_char [84] = "push    "; mod_rm_enc [84] = "XXX";
        opcode_char [85] = "push    "; mod_rm_enc [85] = "XXX";
        opcode_char [86] = "push    "; mod_rm_enc [86] = "XXX";
        opcode_char [87] = "push    "; mod_rm_enc [87] = "XXX";
       

        /*
         * Opcode for POP
         */
        opcode_char [88] = "pop     "; mod_rm_enc [88] = "XXX";
        opcode_char [89] = "pop     "; mod_rm_enc [89] = "XXX";
        opcode_char [90] = "pop     "; mod_rm_enc [90] = "XXX";
        opcode_char [91] = "pop     "; mod_rm_enc [91] = "XXX";
        opcode_char [92] = "pop     "; mod_rm_enc [92] = "XXX";
        opcode_char [93] = "pop     "; mod_rm_enc [93] = "XXX";
        opcode_char [94] = "pop     "; mod_rm_enc [94] = "XXX";
        opcode_char [95] = "pop     "; mod_rm_enc [95] = "XXX";

        /*
         * Opcode for RET
         */
        opcode_char[195] = "retq    "; mod_rm_enc[195] = "XXX";

        /*
         * Opcode for LEA
         */
        opcode_char[141] = "lea     "; mod_rm_enc[141] = "RM ";
        
        /*
         * Opcode for SHL and SHR
         */
        opcode_char[193] = "shr     "; mod_rm_enc[193] = "MI ";
        opcode_char[209] = "shr     "; mod_rm_enc[209] = "M1 ";
        opcode_char[211] = "shr     "; mod_rm_enc[211] = "MC ";
        
        /*
        * Opcode for TEST
        */
        opcode_char[133] = "test    "; mod_rm_enc[133] = "MR ";

        /*
        * Opcode for XCHG
        */
        opcode_char[134] = "xchg    "; mod_rm_enc[134] = "O  ";
        opcode_char[135] = "xchg    "; mod_rm_enc[135] = "O  ";
        opcode_char[144] = "xchg    "; mod_rm_enc[144] = "O  ";

        /*
         * Shared OPCODE encoding. This block and the group block is taken from table
         * A6 in Appendix A of intel manual.
         */
        opcode_enc[1][0] = "add     ";
        opcode_enc[1][1] = "or      ";
        opcode_enc[1][2] = "adc     ";
        opcode_enc[1][3] = "sbb     ";
        opcode_enc[1][4] = "and     ";
        opcode_enc[1][5] = "sub     ";
        opcode_enc[1][6] = "xor     ";
        opcode_enc[1][7] = "cmp     ";

        /*
         * Group of Shared opcode
         */
        opcode_group[128] = 1;
        opcode_group[129] = 1;
        opcode_group[130] = 1;
        opcode_group[131] = 1;

        /*
         * Table for 8/32/64 bit registers. It taken from os dev wiki page, "Registers table"
         */
        reg_table_64[0] = "%rax";  reg_table_32[0] = "%eax";    reg_table_8[0] = "%al";
        reg_table_64[1] = "%rcx";  reg_table_32[1] = "%ecx";    reg_table_8[1] = "%cl";
        reg_table_64[2] = "%rdx";  reg_table_32[2] = "%edx";    reg_table_8[2] = "%dl";
        reg_table_64[3] = "%rbx";  reg_table_32[3] = "%ebx";    reg_table_8[3] = "%bl";
        reg_table_64[4] = "%rsp";  reg_table_32[4] = "%esp";    reg_table_8[4] = "%ah";
        reg_table_64[5] = "%rbp";  reg_table_32[5] = "%ebp";    reg_table_8[5] = "%bh";
        reg_table_64[6] = "%rsi";  reg_table_32[6] = "%esi";    reg_table_8[6] = "%dh";
        reg_table_64[7] = "%rdi";  reg_table_32[7] = "%edi";    reg_table_8[7] = "%bh";
        reg_table_64[8] = "%r8";
        reg_table_64[9] = "%r9";
        reg_table_64[10] = "%r10";
        reg_table_64[11] = "%r11";
        reg_table_64[12] = "%r12";
        reg_table_64[13] = "%r13";
        reg_table_64[14] = "%r14";
        reg_table_64[15] = "%r15";
    
    end 
    
    function logic mtrr_is_mmio(logic[63:0] physaddr);
        mtrr_is_mmio = ((physaddr > 640*1024 && physaddr < 1024*1024));
    endfunction
    
    logic send_fetch_req;
    always_comb begin
        if (fetch_state != fetch_idle) begin
            send_fetch_req = 0; // hack: in theory, we could try to send another request at this point
        end else if (bus.reqack) begin
            send_fetch_req = 0; // hack: still idle, but already got ack (in theory, we could try to send another request as early as this)
        end else begin
            send_fetch_req = (fetch_offset - decode_offset < 7'd32);
        end
    end
    
    assign bus.respack = bus.respcyc; // always able to accept response
    
    always @ (posedge bus.clk) begin
        if (bus.reset) begin
    
            fetch_state <= fetch_idle;
            fetch_rip <= entry & ~63;
            fetch_skip <= entry[5:0];
            fetch_offset <= 0;
    
        end else begin // !bus.reset
    
            bus.reqcyc <= send_fetch_req;
            bus.req <= fetch_rip & ~63;
            bus.reqtag <= { bus.READ, bus.MEMORY, 8'b0 };
    
            if (bus.respcyc) begin
                assert(!send_fetch_req) else $fatal;
                fetch_state <= fetch_active;
                fetch_rip <= fetch_rip + 8;
                if (fetch_skip > 0) begin
                    fetch_skip <= fetch_skip - 8;
                end else begin
                    decode_buffer[fetch_offset*8 +: 64] <= bus.resp;
                    //$display("fill at %d: %x [%x]", fetch_offset, bus.resp, decode_buffer);
                    fetch_offset <= fetch_offset + 8;
                end
            end else begin
                if (fetch_state == fetch_active) begin
                    fetch_state <= fetch_idle;
                end else if (bus.reqack) begin
                    assert(fetch_state == fetch_idle) else $fatal;
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
        else if (opcode == 31)  inst = "nopw    ";   // 0F 1F
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
     * Function to print a 4 byte number byte by byte
     */
    function void display_byte (logic[0 : 4*8-1] inp);
        $write("%x %x %x %x", inp[0*8 : 1*8-1], inp[1*8 : 2*8-1], inp[2*8 : 3*8-1], inp[3*8 : 4*8-1]);
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

    /*
     * Print Program bytes 
     */
    function print_prog_bytes(logic[0 : 15*8-1] prog_bytes, logic[0 : 3] size);
        logic[0 : 3] ii = 0;
        for(ii = 0; ii < size; ii++) begin
            $write(" %x", prog_bytes[ii*8 +: 1*8]);
        end
        for(ii = size; ii < 15; ii++) begin
            $write("   ");
        end
    endfunction

    
    logic[0 : 3] bytes_decoded_this_cycle;
    logic[0 : 7] opcode;
    logic[0 : 3] offset;
    logic[0 : 23] mod_rm_enc_byte; // Store encoding for given opcode
    logic[0 : 4*8-1] disp_byte;
    logic[0 : 4*8-1] imm_byte;
    logic[0 : 3] regByte;
    logic[0 : 3] rmByte;
    logic[0 : 4*8-1] high_byte;
    logic[0 : 4*8-1] low_byte;

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

    always_comb begin
        if (can_decode) begin : decode_block
            $display(""); 
            // Variables which are to be reset for each new decoding
            offset = 0;
            mod_rm_enc_byte = 0;
            disp_byte = 0;
            imm_byte = 0;
            short_disp_byte = 0;
            high_byte = 0;
            low_byte = 0;
            rex_prefix = 0;
            prefix = 0;
            for (i = 0; i < 32 ; i++) begin
                reg_buffer[i*8 +: 8] = " "; 
            end
            instr_buffer = empty_str; 
   
            // Compute program address for next instruction
            prog_addr = fetch_rip - {57'b0, (fetch_offset - decode_offset)};
            $write("%s:       ", byte8_to_str(prog_addr));

            /*
             * Prefix decoding
             */
            temp_prefix = decode_bytes[offset*8 +: 1*8];
            mod_rm_enc_byte = mod_rm_enc[temp_prefix];

            while (mod_rm_enc_byte == "PRE") begin
                prefix = temp_prefix;
                prefix_char = opcode_char[prefix];
                if (prefix_char == "rex     ")
                    rex_prefix = prefix;

                space_buffer[(offset)*8 +: 8] = prefix;
                offset += 1;

                // Search if next byte is also a prefix
                temp_prefix = decode_bytes[offset*8 +: 1*8];
                mod_rm_enc_byte = mod_rm_enc[temp_prefix];
            end
            mod_rm_enc_byte = 0;
   
            /*
             * For instructions with either a REX prefix OR No prefix
             */
            if (rex_prefix != 0 || prefix == 0) begin
                /*
                 * Opcode decoding
                 */
                opcode = decode_bytes[offset*8 +: 1*8];
                space_buffer[(offset)*8 +: 8] = opcode;
                offset += 1;

                /*
                 * ALL SPECIAL CASES GOES UPFRONT
                 */
                if (opcode == 108) begin
                    /* INSB instruction */
                    instr_buffer = opcode_char[opcode];
                    reg_buffer[0:135] = {"(%dx), %es:(%rdi)"};
             
                end else if (opcode == 111) begin
                    /* OUTSB instruction */
                    instr_buffer = opcode_char[opcode];
                    reg_buffer[0:135] = {"%ds:(%rsi), (%dx)"};

                end else if (opcode == 144 && rex_prefix == 0) begin
                    /* NOP instruction */
                    instr_buffer = "nop     ";

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

                    reg_buffer[0:191] = {{"$0x"}, {byte8_to_str({byte_swap(low_byte), byte_swap(high_byte)})},
                                  {","}, {reg_table_64[opcode - 184]} };
                    instr_buffer = opcode_char[opcode]; 
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
                    mod_rm_enc_byte = mod_rm_enc[opcode];

                    if (mod_rm_enc_byte == "MI ") begin
                        imm_byte[0:7] = decode_bytes[offset*8 +: 1*8]; 
                        space_buffer[(offset)*8 +: 1*8] = imm_byte[0:7];
                        offset += 1;
                        reg_buffer[0:87] = {{"$0x"}, {byte1_to_str(imm_byte[0:7])}, {", "}, {reg_table_64[rmByte]}};
                    end
                    /* No Test Case for mod encode = M1 or MC */
                    else if (mod_rm_enc_byte == "M1 ") begin
                        reg_buffer[0:87] = {{"$0x01, "}, {reg_table_64[rmByte]}};
                    end
                    else if (mod_rm_enc_byte == "MC ") begin
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
                         * We have got a two byte opcode with REX prefix
                         * Pretend as though nothing happened and over write the opcode
                         * with the next byte. Now it appears to the program that only one opcode
                         * occured
                         */
                        opcode = decode_bytes[offset*8 +: 1*8];
                        space_buffer[(offset)*8 +: 8] = opcode;
                        offset += 1;

                        instr_buffer = decode_2_byte_opcode(opcode);

                        // All the 2 byte Opcodes except "0F 05/AF" have a 4 byte displacement
                        if (opcode == 5)        // 0F 05 (syscall)
                            mod_rm_enc_byte = "XXX";
                        else if (opcode == 175) // 0F AF (imul)
                            mod_rm_enc_byte = "RM ";
                        else 
                            mod_rm_enc_byte = "D4 ";

                    end else begin
                        instr_buffer = opcode_char[opcode];
                        mod_rm_enc_byte = mod_rm_enc[opcode];
                    end

                    assert(mod_rm_enc_byte != 0) else $fatal;

                    if (mod_rm_enc_byte[0:7] == "M" || mod_rm_enc_byte[0:7] == "R") begin
                        /*
                         * We have found a Mod R/M byte for MR, RM, M, MI, MIS
                         * The direction (source / destination is available in mod_rm_enc value")
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
                        instr_buffer = opcode_enc[opcode_group[opcode]][regByte];
                    end

                    if (mod_rm_enc_byte == "M  ") begin
                        // reg bits need to be 2
                        assert(modRM_byte.reg1 == 2) else $fatal;
                        reg_buffer[0:39] = {{"*"} , {reg_table_64[rmByte]}};
                    end

                    else if (mod_rm_enc_byte == "MR ") begin
                        /*
                         * Register addressing mode
                         */ 
                        if (modRM_byte.mod == 3) begin
                            /*
                             * There is no displacement and no index registers
                             */
                            reg_buffer[0:79] = {{reg_table_64[regByte]}, {", "}, {reg_table_64[rmByte]}};
                        end
                        else if (disp_byte != 0) begin
                            /*
                            * It is NOT sign extended. The displacement value is 32 bits
                            */
                            reg_buffer[0:183] = {{reg_table_64[regByte]}, {", $0x"}, {byte4_to_str(byte_swap(disp_byte))}, {"("},
                                            {reg_table_64[rmByte]}, {")"}};
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

                    else if (mod_rm_enc_byte == "RM ") begin
                        /*
                         * Register addressing mode
                         * The direction of source and destination are interchanged
                         */
                        if (modRM_byte.mod == 3) begin
                            /*
                             * There is no displacement and index register
                             */
                            reg_buffer[0:63] = {{reg_table_64[rmByte]}, {reg_table_64[regByte]}};
                        end
                        else if (disp_byte != 0) begin
                            /*
                            * It is NOT sign extended. The displacement value is 32 bits
                            */
                            reg_buffer[0:183] = {{"$0x"}, {byte4_to_str(byte_swap(disp_byte))}, {"("}, {reg_table_64[rmByte]}, {"), "},
                                            {reg_table_64[regByte]}};
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
                            reg_buffer[0:95] = {{"("}, {reg_table_64[rmByte]}, {"), "}, {reg_table_64[regByte]}};
                        end
                    end

                    else if (mod_rm_enc_byte == "MI ") begin
                        /*
                         * Immediate addressing mode
                         */
                        imm_byte = decode_bytes[offset*8 +: 4*8]; 
                        space_buffer[(offset)*8 +: 4*8] = imm_byte;
                        offset += 4; // Assuming immediate values as 4. Correct?
                        reg_buffer[0:135] = {{"$0x"}, {byte4_to_str(byte_swap(imm_byte))}, {", "}, {reg_table_64[rmByte]}};

                        /*
                        Dont know why I wrote this code. Keep it. Do not delete
                        if (disp_byte != 0) begin
                            $write("$0x%x(%s)",byte_swap(disp_byte), reg_table_64[regByte]);
                        end else begin
                            $write("%s",reg_table_64[regByte]);
                        end*/
                    end

                    else if (mod_rm_enc_byte == "MIS") begin
                        /*
                         * Signed extension
                         * Right now handling only 1 byte immediate to sign extension
                         */
                        short_imm_byte = decode_bytes[offset*8 +: 1*8]; 
                        space_buffer[(offset)*8 +: 8] = short_imm_byte;
                        offset += 1;
                        signed_imm_byte = {{56{short_imm_byte[0]}}, {short_imm_byte}};
                        reg_buffer[0:199] = {{"$0x"}, {byte8_to_str(signed_imm_byte)}, {", "}, {reg_table_64[rmByte]}};
                    end

                    else if (mod_rm_enc_byte == "D1 ") begin
                        /*
                         * 1 byte relative displacement
                         */
                        short_disp_byte = decode_bytes[offset*8 +: 1*8];
                        space_buffer[(offset)*8 +: 8] = short_disp_byte;
                        offset += 1;
                        
                        disp_byte = {24'b0, short_disp_byte};
                        temp_crr = rel_to_abs_addr(prog_addr, disp_byte, offset);
                        reg_buffer[0:151] = {{"$0x"}, {byte8_to_str(temp_crr)}};
                    end

                    else if (mod_rm_enc_byte == "D4 ") begin
                        /*
                         * 4 byte relative displacement
                         */
                        disp_byte = decode_bytes[offset*8 +: 4*8];
                        space_buffer[(offset)*8 +: 4*8] = disp_byte;
                        offset += 4;
     
                        temp_crr = rel_to_abs_addr(prog_addr, byte_swap(disp_byte), offset);
                        reg_buffer[0:151] = {{"$0x"}, {byte8_to_str(temp_crr)}};
                    end
                end

            end else if (prefix == 46) begin
                /* TODO: CS Override */
                opcode = decode_bytes[offset*8 +: 1*8];
                space_buffer[(offset)*8 +: 8] = opcode;
                offset += 1; // 0F

                opcode = decode_bytes[offset*8 +: 1*8];
                space_buffer[(offset)*8 +: 8] = opcode;
                offset += 1;

                instr_buffer = decode_2_byte_opcode(opcode);
            end else if (prefix == 102) begin
                /* TODO: Operand Override */
                opcode = decode_bytes[offset*8 +: 1*8]; 
                space_buffer[(offset)*8 +: 8] = opcode;
                offset += 1;

                instr_buffer = opcode_char[opcode];

            end else if (prefix != 0) begin
                /* Dont need to support other Prefixes. Just printing out the prefix name */
                instr_buffer = opcode_char[prefix];
                
            end 

            print_prog_bytes(space_buffer, offset);
            $write("%s%s", instr_buffer, reg_buffer);

            bytes_decoded_this_cycle =+ offset;
            if (decode_bytes == 0 && fetch_state == fetch_idle) $finish;

        end else begin
            bytes_decoded_this_cycle = 0;
        end
    end
    
    always @ (posedge bus.clk) begin
        if (bus.reset) begin
            decode_offset <= 0;
            decode_buffer <= 0;
        end else begin // !bus.reset
            decode_offset <= decode_offset + { 3'b0, bytes_decoded_this_cycle };
        end
    end

endmodule
