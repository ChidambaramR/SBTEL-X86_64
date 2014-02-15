module Core (
    input[63:0] entry,
    /* verilator lint_off UNDRIVEN */ /* verilator lint_off UNUSED */ Sysbus bus /* verilator lint_on UNUSED */ /* verilator lint_on UNDRIVEN */
);
    
    enum { fetch_idle, fetch_waiting, fetch_active } fetch_state;
    logic[63:0] fetch_rip;
    logic[0:2*64*8-1] decode_buffer; // NOTE: buffer bits are left-to-right in increasing order
    logic[5:0] fetch_skip;
    logic[6:0] fetch_offset, decode_offset;
    
    // Imp Data structures
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
    
    typedef struct packed {
        logic [0 : 7] op_prefix;
    } op_override;
    
    /*
     * This is the main instruction structure
     */
    typedef struct packed {
        rex rex_prefix;
        logic [0:7] opcode;
        mod_rm mod_rm_byte;
    } instruction;
    
    /*typedef union packed {
        rex rex_prefix;
        op_override op_ride;
    } prefix;*/
    /*
    Sample way to assign values
    */
    //rex temp1 = {4'b0100, 1'b1, 1'b1, 1'b1, 1'b1};
    
    logic [0:255][0:2][0:7] mod_rm_enc;
    logic [255:0][7:0][7:0] opcode_char;
    logic [0:15][0:3][0:7] reg_table_64;
    logic [0:15][0:3][0:7] reg_table_32;
    logic [7:0][7:0]str = {"       "};
    logic [8:0] i = 0;
    
    initial 
    begin
        for (i = 0; i < 256; i++)
        begin
            opcode_char[i] = str;
            mod_rm_enc[i] = 0;
        end 
        /*
         * Following values are converted into decimal from hex.
         * For example, 0x89 is the hex opcode. This is 137 in decimal
         * Also store Mod RM byte encoding for each opcode
         */
        
        /*
        * Opcodes for XOR
        */
        opcode_char [49] = "XOR     "; mod_rm_enc[49] = "MR "; // 31

        /*
        * Opcodes for AND
        */
        opcode_char[131] = "AND     "; mod_rm_enc[131] = "MIS"; // 83
    
        /*
         * Opcodes for MOV
         */
        opcode_char[137] = "MOV     "; mod_rm_enc[137] = "MR "; // 89
        opcode_char[139] = "MOV     "; mod_rm_enc[139] = "RM "; // 8B
        opcode_char[199] = "MOV     "; mod_rm_enc[199] = "MI "; // c7
    
        /*
         * Opcodes for CALL
         */
        opcode_char[232] = "CALLQ   "; mod_rm_enc[232] = "MR "; // E8
        opcode_char[255] = "CALLQ   "; mod_rm_enc[255] = "MR "; // FF 
    
        /*
         * Table for 64 bit registers. It taken from os dev wiki page, "Registers table"
         */
        reg_table_64[0] = "%rax";
        reg_table_64[1] = "%rcx";
        reg_table_64[2] = "%rdx";
        reg_table_64[3] = "%rbx";
        reg_table_64[4] = "%rsp";
        reg_table_64[5] = "%rbp";
        reg_table_64[6] = "%rsi";
        reg_table_64[7] = "%rdi";
        reg_table_64[8] = "%r8";
        reg_table_64[9] = "%r9";
        reg_table_64[10] = "%r10";
        reg_table_64[11] = "%r11";
        reg_table_64[12] = "%r12";
        reg_table_64[13] = "%r13";
        reg_table_64[14] = "%r14";
        reg_table_64[15] = "%r15";
    
        /*
         * Table for 32 bit registers. It taken from os dev wiki page, "Registers table"
         */
        reg_table_32[0] = "%rax";
        reg_table_32[1] = "%rcx";
        reg_table_32[2] = "%rdx";
        reg_table_32[3] = "%rbx";
        reg_table_32[4] = "%rsp";
        reg_table_32[5] = "%rbp";
        reg_table_32[6] = "%rsi";
        reg_table_32[7] = "%rdi";
        reg_table_32[8] = "%r8";
        reg_table_32[9] = "%r9";
        reg_table_32[10] = "%r10";
        reg_table_32[11] = "%r11";
        reg_table_32[12] = "%r12";
        reg_table_32[13] = "%r13";
        reg_table_32[14] = "%r14";
        reg_table_32[15] = "%r15";
    
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
            send_fetch_req = (fetch_offset - decode_offset < 32);
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
    wire can_decode = (fetch_offset - decode_offset >= 15);
    
    function logic opcode_inside(logic[7:0] value, low, high);
        opcode_inside = (value >= low && value <= high);
    endfunction

    /*
    Function to Swap value. Returns the swapped value
    */
    function logic[0 : 4*8-1] byte_swap(logic[0 : 4*8-1] inp);
        logic[0 : 4*8-1] ret_val;
        ret_val[0*8 : 1*8-1] = inp[3*8 : 4*8-1];
        ret_val[1*8 : 2*8-1] = inp[2*8 : 3*8-1];
        ret_val[2*8 : 3*8-1] = inp[1*8 : 2*8-1];
        ret_val[3*8 : 4*8-1] = inp[0*8 : 1*8-1];
        byte_swap = ret_val;
    endfunction

    
    logic[3:0] bytes_decoded_this_cycle;
    logic[0 : 7] opcode;
    logic[0 : 3] length;
    logic[0 : 7] offset;
    logic[0 : 1*8-1] temp_prefix;
    logic[0 : 23] mod_rm_enc_byte; // It can store two chars. Eg MR / RM / MI etc
    logic[0 : 4*8-1] disp_byte;
    logic[0 : 4*8-1] imm_byte;
    logic[0 : 3] regByte;
    logic[0 : 3] rmByte;
    logic[0 : 63] signed_imm_byte;
    logic[0 : 7] short_imm_byte;
    
    rex rex_prefix;
    op_override op_ride;
    mod_rm modRM_byte;

    always_comb begin
        if (can_decode) begin : decode_block
   
            // Variables which are to be reset for each new decoding
            $display(" ");
            length = 0;
            offset = 0;
            mod_rm_enc_byte = 0;
            disp_byte = 0;
            imm_byte = 0;
   
            /*
             * Prefix decoding
             */
            temp_prefix = decode_bytes[offset*8 +: 1*8];
            /*
            If the byte is between 0x40 and 0x4F, then it is REX prefix
            Below is the decimal equivalnet check
            */
            if (temp_prefix >= 64 && temp_prefix <= 79) begin
                rex_prefix = temp_prefix[0 : 7];
                offset += 1;
                length += 1;
                $write("%x ",rex_prefix);
   
                /*
                 * Opcode decoding
                 */
                opcode = decode_bytes[offset*8 +: 1*8];
                offset += 1;
                length += 1;
                if (opcode != 15) begin
                    /*
                     * Only the primary OPCODE
                     */
                    mod_rm_enc_byte = mod_rm_enc[opcode];
                    $write("%x ",opcode);
                    if (mod_rm_enc_byte != 0) begin
                        /*
                         * We have found a Mod R/M byte.
                         * The direction (source / destination is available in mod_rm_enc value")
                         */
                        modRM_byte = decode_bytes[offset*8 +: 1*8];
                        $write("%x       ",modRM_byte);
                        offset += 1;
                        length += 1;
   
                        /*
                         * Check if there is a displacement in the instruction
                         * If mod bit is NOT 11 or 3(decimal), then there is a displacement
                         * Right now assuming that length of displacement is 4 bytes. Should
                         * modify cases when length is lesser than 4 bytes
                         */
                            if (modRM_byte.mod != 3) begin
                                if (modRM_byte.mod == 0) begin
                                    disp_byte = 1; // Just to say that there is 0 displacement 
                                end
                                else begin
                                    disp_byte = decode_bytes[offset*8 +: 4*8]; 
                                    offset += 4;
                                    length += 4; // Assuming immediate values as 4. Correct?
                                end
                            end
    
                            /*
                             * Check if the instruction has Immediate values
                             */
                            if (mod_rm_enc_byte == "MI ") begin
                                imm_byte = decode_bytes[offset*8 +: 4*8]; 
                                offset += 4;
                                length += 4; // Assuming immediate values as 4. Correct?
                            end
                            else if(mod_rm_enc_byte == "MIS") begin
                                /*
                                Immediate value is sign extended
                                */
                                short_imm_byte = decode_bytes[offset*8 +: 1*8]; 
                                offset += 1;
                                length += 1;
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
                        $write("%s    ",opcode_char[opcode]);
                        if (rex_prefix.W) begin
                            /*
                             * 64 bit operands
                             */
                            regByte = {{rex_prefix.R}, {modRM_byte.reg1}};
    
                            rmByte = {{rex_prefix.B}, {modRM_byte.rm}};
    
                            if (mod_rm_enc_byte == "MR ") begin
                            /*
                             * Register addressing mode
                             */  
                                if (disp_byte != 0)
                                    /*
                                     * There is displacement
                                     */
                                    if (modRM_byte.mod == 0) begin
                                        /*
                                         * There is no immediate value for 
                                         * that displacement, then the mod bits of the modRM byte
                                         * will be 0
                                         */
                                        $write("%s, (%s)",reg_table_64[regByte], reg_table_64[rmByte]);
                                    end
                                    else begin
                                        /*
                                         * There is some displacement value
                                         */
                                        $write("%s, $0x%x(%s)",reg_table_64[regByte], byte_swap(disp_byte), reg_table_64[rmByte]);
                                    end
    
                                else begin
                                    /*
                                     * There is no displacement
                                     */
                                    $write("%s, %s",reg_table_64[regByte], reg_table_64[rmByte]);
                                end
                            end
    
                            if (mod_rm_enc_byte == "RM ") begin
                            /*
                             * Register addressing mode
                             * The direction of source and destination are interchanged
                             */
                                if (disp_byte != 0) begin
                                /*
                                 * There is displacement
                                 */
                                    if (modRM_byte.mod == 0) begin
                                    /*
                                     * No immediate value
                                     */
                                        $write("%s, (%s)", reg_table_64[rmByte], reg_table_64[regByte]);
                                    end
                                    else begin 
                                        $write("$0x%x(%s), %s",byte_swap(disp_byte), reg_table_64[rmByte], reg_table_64[regByte]); 
                                    end
                                end
                            end
    
                            else if (mod_rm_enc_byte == "MI ") begin
                                /*
                                 * Immediate addressing mode
                                 */
                                if (imm_byte != 0) begin
                                    $write("$0x%x, %s",byte_swap(imm_byte), reg_table_64[rmByte]);
                                end else begin
                                    $write("%s",reg_table_64[rmByte]);
                                end 

                                /*
                                Dont know why I wrote this code. Keep it. Do not delete
                                if (disp_byte != 0) begin
                                    $write("$0x%x(%s)",byte_swap(disp_byte), reg_table_64[regByte]);
                                end else begin
                                    $write("%s",reg_table_64[regByte]);
                                end*/
                            end

                            else if(mod_rm_enc_byte == "MIS") begin
                                /*
                                * Signed extension
                                * Right now handling only 1 byte immediate to sign extension
                                */
                                signed_imm_byte = {{56{short_imm_byte[0]}}, {short_imm_byte}};
                                $write("$0x%x, %s",signed_imm_byte,reg_table_64[rmByte]);
                            end

                        end // END OF REW.W bit check
                        else begin          
                            $write("%s %s",reg_table_32[regByte], reg_table_32[rmByte]);
                        end
    
                    end else begin
                        length += 2;
                        offset += 1;
                    end
    
                    //$display("1st nibble = %x",rex_prefix.def);
                end else if (temp_prefix == 102) begin
                    op_ride = temp_prefix[0 : 7];
                    $display("Operand override = %x",op_ride);
                    length += 1;
                end
    
                bytes_decoded_this_cycle =+ length;
    
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
