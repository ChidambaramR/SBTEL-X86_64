module Core (
    input[63:0] entry,
    /* verilator lint_off UNDRIVEN */
    /* verilator lint_off UNUSED */
    Sysbus bus
    /* verilator lint_on UNUSED */
    /* verilator lint_on UNDRIVEN */
);

// Varuns's change
import "DPI-C" function longint syscall_cse502(input longint rax, input longint rdi, input longint rsi, input longint rdx, input longint r10, input longint r8, input longint r9);

enum { fetch_idle, fetch_waiting, fetch_active } fetch_state;
logic[63:0] fetch_rip;
logic[0:2*64*8-1] decode_buffer; // NOTE: buffer bits are left-to-right in increasing order
logic[0:64*8-1] data_buffer;
logic[0:8*8-1] load_buffer;
logic[0:8*8-1] store_word;
logic store_ins;
logic store_writeback;
logic store_writebackFlag;
//logic store_ack_waiting;
logic store_done;
logic sending_data;
logic store_opn;
logic store_ack_received;

logic load_done; // This variable is true whenever the requested byte has been put into the local buffer
logic[5:0] fetch_skip;
logic[5:0] fetch_store_skip;
logic[5:0] fetch_data_skip;
logic[6:0] fetch_offset, decode_offset;
logic[0:6] data_offset;
logic[0:63] regfile[0:16-1];
logic once;
logic cycle;

logic [0:8] i = 0;
logic [0:4] j = 0;

// 2D Array
logic [0:255][0:0][0:3] opcode_group;

logic [0:6] internal_offset;
logic [0:5] internal_data_offset;


logic data_req;
logic callqFlag;
logic callq_stage2;

logic [0:63] data_reqAddr;

function logic[0 : 8*8-1] byte8_swap(logic[0 : 8*8-1] inp);
      logic[0 : 8*8-1] ret_val;
      ret_val[0*8 : 1*8-1] = inp[7*8 : 8*8-1];
      ret_val[1*8 : 2*8-1] = inp[6*8 : 7*8-1];
      ret_val[2*8 : 3*8-1] = inp[5*8 : 6*8-1];
      ret_val[3*8 : 4*8-1] = inp[4*8 : 5*8-1];
      ret_val[4*8 : 5*8-1] = inp[3*8 : 4*8-1];
      ret_val[5*8 : 6*8-1] = inp[2*8 : 3*8-1];
      ret_val[6*8 : 7*8-1] = inp[1*8 : 2*8-1];
      ret_val[7*8 : 8*8-1] = inp[0*8 : 1*8-1];
      byte8_swap = ret_val;
endfunction


function logic[8*8-1 : 0] Bbyte8_swap(logic[8*8-1 : 0] inp);
      logic[8*8-1 : 0] ret_val;
      ret_val[1*8-1 : 0*8] = inp[8*8-1 : 7*8];
      ret_val[2*8-1 : 1*8] = inp[7*8-1 : 6*8];
      ret_val[3*8-1 : 2*8] = inp[6*8-1 : 5*8];
      ret_val[4*8-1 : 3*8] = inp[5*8-1 : 4*8];
      ret_val[5*8-1 : 4*8] = inp[4*8-1 : 3*8];
      ret_val[6*8-1 : 5*8] = inp[3*8-1 : 2*8];
      ret_val[7*8-1 : 6*8] = inp[2*8-1 : 1*8];
      ret_val[8*8-1 : 7*8] = inp[1*8-1 : 0*8];
      Bbyte8_swap = ret_val;
endfunction

function logic[7*8-1 : 0] byte7_swap(logic[7*8-1 : 0] inp);
      logic[7*8-1 : 0] ret_val;
      ret_val[1*8-1 : 0*8] = inp[7*8-1 : 6*8];
      ret_val[2*8-1 : 1*8] = inp[6*8-1 : 5*8];
      ret_val[3*8-1 : 2*8] = inp[5*8-1 : 4*8];
      ret_val[4*8-1 : 3*8] = inp[4*8-1 : 3*8];
      ret_val[5*8-1 : 4*8] = inp[3*8-1 : 2*8];
      ret_val[6*8-1 : 5*8] = inp[2*8-1 : 1*8];
      ret_val[7*8-1 : 6*8] = inp[1*8-1 : 0*8];
      byte7_swap = ret_val;
endfunction

function logic[6*8-1 : 0] byte6_swap(logic[6*8-1 : 0] inp);
      logic[6*8-1 : 0] ret_val;
      ret_val[1*8-1 : 0*8] = inp[6*8-1 : 5*8];
      ret_val[2*8-1 : 1*8] = inp[5*8-1 : 4*8];
      ret_val[3*8-1 : 2*8] = inp[4*8-1 : 3*8];
      ret_val[4*8-1 : 3*8] = inp[3*8-1 : 2*8];
      ret_val[5*8-1 : 4*8] = inp[2*8-1 : 1*8];
      ret_val[6*8-1 : 5*8] = inp[1*8-1 : 0*8];
      byte6_swap = ret_val;
endfunction

function logic[5*8-1 : 0] byte5_swap(logic[5*8-1 : 0] inp);
      logic[5*8-1 : 0] ret_val;
      ret_val[1*8-1 : 0*8] = inp[5*8-1 : 4*8];
      ret_val[2*8-1 : 1*8] = inp[4*8-1 : 3*8];
      ret_val[3*8-1 : 2*8] = inp[3*8-1 : 2*8];
      ret_val[4*8-1 : 3*8] = inp[2*8-1 : 1*8];
      ret_val[5*8-1 : 4*8] = inp[1*8-1 : 0*8];
      byte5_swap = ret_val;
endfunction

function logic[4*8-1 : 0] byte4_swap(logic[4*8-1 : 0] inp);
      logic[4*8-1 : 0] ret_val;
      ret_val[1*8-1 : 0*8] = inp[4*8-1 : 3*8];
      ret_val[2*8-1 : 1*8] = inp[3*8-1 : 2*8];
      ret_val[3*8-1 : 2*8] = inp[2*8-1 : 1*8];
      ret_val[4*8-1 : 3*8] = inp[1*8-1 : 0*8];
      byte4_swap = ret_val;
endfunction

function logic[3*8-1 : 0] byte3_swap(logic[3*8-1 : 0] inp);
      logic[3*8-1 : 0] ret_val;
      ret_val[1*8-1 : 0*8] = inp[3*8-1 : 2*8];
      ret_val[2*8-1 : 1*8] = inp[2*8-1 : 1*8];
      ret_val[3*8-1 : 2*8] = inp[1*8-1 : 0*8];
      byte3_swap = ret_val;
endfunction


function logic[2*8-1 : 0] byte2_swap(logic[2*8-1 : 0] inp);
      logic[2*8-1 : 0] ret_val;
      ret_val[1*8-1 : 0*8] = inp[2*8-1 : 1*8];
      ret_val[2*8-1 : 1*8] = inp[1*8-1 : 0*8];
      byte2_swap = ret_val;
endfunction

function logic[1*8-1 : 0] byte1_swap(logic[1*8-1 : 0] inp);
      logic[1*8-1 : 0] ret_val;
      ret_val[1*8-1 : 0*8] = inp[1*8-1 : 0*8];
      byte1_swap = ret_val;
endfunction

initial begin
    // Initial value of RSP from mailing list

    for (i = 0; i < 256; i++)
    begin
        opcode_group[i] = 0;
    end

    for (j = 0; j <= 15; j++) begin
        regfile[j[1:4]] = {64{1'b0}};
    end

    regfile[4] = 31744;  // WARNING. Change it to 0x7C00 after Varun's fix
    //regfile[6] = 1;
    callqFlag = 0;

    store_ack_received = 0;
    //for (j = 0; j <= 14; j++) begin
    //    score_board[j] = 0;
    //end

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
logic jump_sent;

always_comb begin
    if (fetch_state != fetch_idle) begin
        send_fetch_req = 0; // hack: in theory, we could try to send another request at this point
    end else if (bus.reqack) begin
        send_fetch_req = 0; // hack: still idle, but already got ack (in theory, we could try to send another request as early as this)
    end else begin
    if (!jump_signal && !jump_cond_signal && !store_ins && !data_req)
            send_fetch_req = (fetch_offset - decode_offset < 7'd32);
        //if (jump_signal && !bus.respcyc) begin
        //    jump_flag = 0;
        //    send_fetch_req = 1;
        //end
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
         * Immediately after sending the request, we will be getting back an 
         * ACK from the bus. Once we get back an ACK, we know our request 
         * has been acknowledged and we have to start waiting for the resposne. 
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
        if (store_writebackFlag)
            store_writeback <= 1;

          if (store_opn == 0)
            sending_data <= 0;

        if (!bus.respcyc) begin

            if (jump_signal && !outstanding_fetch_req) begin
                // Fetch request for jump instruction
                outstanding_fetch_req <= 1;
                bus.req <= jump_target & ~63;
                           // $write("Sending req on bus 1");
                bus.reqtag <= { bus.READ, bus.MEMORY, 8'b0 };
                bus.reqcyc <= 1;
                store_writeback <= 0;
                fetch_offset <= 0;
                decode_offset <= 0;
                jump_sent <= 1;
            end

            if (!data_req && !store_ins) begin
                // Sending a reques for instructions
                if (send_fetch_req) begin
                    outstanding_fetch_req <= 1;
                    bus.req <= fetch_rip & ~63;
                    //bus.req <= (fetch_rip - {57'b0, (fetch_offset - decode_offset)}) & ~63;
                    bus.reqtag <= { bus.READ, bus.MEMORY, 8'b0 };
                    bus.reqcyc <= send_fetch_req;
                    store_writeback <= 0;
                end
            end
            else if (store_ins && store_done) begin

                // Handling store instruction
                if (!outstanding_fetch_req) begin
                    if (cycle == 1) begin
                        bus.req <= (data_reqAddr & ~63);
                        bus.reqcyc <= 1;
                        bus.reqtag <= { bus.WRITE, bus.MEMORY, {6'b0,1'b1,1'b1}};
                        cycle <= 0;
                        data_offset <= 0;
                        store_writeback <= 0;
                    end
                    else if (store_ack_received) begin
                        // Now send the contents of the data to be stored
                        //if (!bus.reqcyc) begin
                        /*
                         * We have to wait till reqack is received. Whenever a reqack is received
                         * we can start sending the data. This means that the memory has accepted our 
                         * requested.
                         */
                        if (!(data_offset >= 56)) begin
                            //$write("Sending req on bus 2");
                            bus.reqcyc <= 1;
                            //store_ack_waiting <= 1;
                            bus.req <= byte8_swap(data_buffer[data_offset*8 +: 64]);
                            //if (data_offset == 56)
                            //    $finish;
                            data_offset <= data_offset + 8;
                        end
                        else begin
                            // We have completed sending the data
                            store_opn <= 0;
                            store_done <= 0;
                            //store_writebackFlag = 1;
                            bus.req <= byte8_swap(data_buffer[data_offset*8 +: 64]);
                            //$write("wrote to memory");
                            if (callqFlag)
                                callq_stage2 <= 1;
                        end
                        //end
                    end
                end
            end
            else begin
                // Sending a request for data
                if (!outstanding_fetch_req && (data_req)) begin
                    //$write("sending req for %x", (data_reqAddr & ~63));
                    bus.req <= (data_reqAddr & ~63) ;
                    fetch_data_skip <= (data_reqAddr[58:63])&(~7);
                    fetch_store_skip <= (data_reqAddr[58:63])&(~7);
                    internal_data_offset <= (data_reqAddr[58:63])&(7);
                    //$write("req = %x", bus.req);
                    bus.reqtag <= { bus.READ, bus.MEMORY, {7'b0,1'b1}};
                    bus.reqcyc <= 1;
                    data_offset <= 0;
                    data_buffer <= 0;
                    load_buffer <= 0;
                    once <= 1;
                    store_writeback <= 0;
                    outstanding_fetch_req <= 1;
                    //outstanding_data_req <= 1;
                end
            end
        end

        if (bus.respcyc && (bus.resptag[7:0] == 0)) begin
            //outstanding_fetch_req <= 0;
            //if (!jump_flag) begin
            /*
             * It takes around 48 micro seconds for a response to come back.
             */
            if (jump_signal && jump_sent) begin
                jump_signal <= 0;
                /* verilator lint_off BLKSEQ */
                jump_flag = 0;  // TODO: Is this correct?
                jump_sent <= 0;
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
                if (internal_offset == 0)
                  decode_buffer[(fetch_offset)*8 +: 64] <= (bus.resp);
                else if (internal_offset == 1)
                  decode_buffer[(fetch_offset)*8 +: 56] <= (bus.resp[55:0]);
                else if (internal_offset == 2)
                  decode_buffer[(fetch_offset)*8 +: 48] <= (bus.resp[47:0]);
                else if (internal_offset == 3)
                  decode_buffer[(fetch_offset)*8 +: 40] <= (bus.resp[39:0]);
                else if (internal_offset == 4)
                  decode_buffer[(fetch_offset)*8 +: 32] <= (bus.resp[31:0]);
                else if (internal_offset == 5)
                  decode_buffer[(fetch_offset)*8 +: 24] <= (bus.resp[23:0]);
                else if (internal_offset == 6)
                  decode_buffer[(fetch_offset)*8 +: 16] <= (bus.resp[15:0]);
                else if (internal_offset == 7)
                  decode_buffer[(fetch_offset)*8 +: 8] <=  (bus.resp[7:0]);
                //$display("orig resp %x",bus.resp);
                //$display("resp %x io = %x",bus.resp[31:0], internal_offset);
                //$display("%x",decode_buffer[(fetch_offset+internal_offset)*8 +: 64]);
                fetch_offset <= (fetch_offset + 8)- internal_offset;
                internal_offset <= 0;
            end
            //end
            //else begin
            //    /*
            //     * A jump is found and we need to resteer the fetch
            //     */
            //    fetch_rip <= (jump_target & ~63);
            //    decode_buffer <= 0;
            //    /* verilator lint_off WIDTH */
            //    fetch_skip <= (jump_target[58:63])&(~7);
            //    internal_offset <= (jump_target[58:63])&(7);
            //    //$write("io = %0h fs = %0h",internal_offset,fetch_skip);
            //    fetch_offset <= 0;
            //    jump_signal <= 1;
            //end
        end else if (bus.respcyc && (bus.resptag[7:0] == 1)) begin
            /*
             * We received a response for data request
             */
            outstanding_fetch_req <= 0;
            if(!load_done)
              data_req <= 0;
            //$write("got response for my data req. Yayy");
            fetch_state <= fetch_active;
            if (!store_ins) begin
                if ((fetch_data_skip) > 0) begin
                    // Fetch skip is up only when there is a response for the first time. 
                    fetch_data_skip <= fetch_data_skip - 8;
                end
                else if(!load_done) begin
                    load_buffer[(data_offset*8) +: 64] <= byte8_swap(bus.resp);
                    load_done <= 1;
                    if(callqFlag)
                        callq_stage2 <= 1;
                end
                data_offset <= data_offset + 8;
            end
            else begin
                // This is the flag which controls whether STORE operation has completed or not. If 0, not complete
                // We are begining the STORE operation.
                // We are here for a STORE instruction
                if (((fetch_store_skip) > 0)) begin
                    /*
                     * If fetch store skip has some value, then we dont have to mangle these contents.
                     */
                    data_buffer[data_offset*8 +: 64] <= byte8_swap(bus.resp);
                    fetch_store_skip <= fetch_store_skip - 8;
                end
                else if (once) begin
                    data_buffer[data_offset*8 +: 64] <= store_word;
                    once <= 0;
                end
                else
                    data_buffer[data_offset*8 +: 64] <= byte8_swap(bus.resp);
                
                data_offset <= data_offset + 8;
                //$display("Bus.resp = %x data_offset = %x",bus.resp, data_offset);
                if (data_offset >= 56) begin
                    /*
                     * We have finished getting the contents in the data buffer. Now put the change buffer
                     * in the corresponding place.
                     */
                    //data_buffer[(data_offset)*8 +: 2*64] <= bus.resp;
                    //$write("Changed buffer = %x",data_buffer);
                    store_done <= 1;
                    sending_data <= 1;
                    //store_writeback <= 0;
                    cycle <= 1;
                    data_offset <= 0;
                end
            end
            //if (data_offset >= 56)
            //    load_done <= 1;
        end
        else begin
            // Handling the jump signal when no response in the bus
            //if (!jump_flag)
            //    jump_signal <= 0;
            load_done <= 0;
            if (jump_flag) begin
                /*
                 * A jump is found and we need to resteer the fetch
                 */
                if (!outstanding_fetch_req) begin
                fetch_rip <= (jump_target & ~63);
                decode_buffer <= 0;
                /* verilator lint_off WIDTH */
                fetch_skip <= (jump_target[58:63])&(~7);
                internal_offset <= (jump_target[58:63])&(7);
                //$write("io = %0h fs = %0h",internal_offset,fetch_skip);
                //fetch_offset <= 0;
                end
                jump_signal <= 1;
                if(callq_stage2)
                    callq_stage2 <= 0;
            end

            //if (jump_cond_flag)
            //    fetch_rip <= (jump_target & ~63);

            if (fetch_state == fetch_active) begin
                fetch_state <= fetch_idle;
            end else if (bus.reqack) begin
                /*
                 * We got an ACK from the bus. So we have to wait.
                 */
                //if (store_ack_waiting)
                //    store_ack_waiting <= 0;
                assert(fetch_state == fetch_idle) else $fatal;
                /*
                 * At the point when we got an ACK, the fetch state should have been idle. If the
                 * fetch state was not idle, we would not have sent a request at all. So we are making
                 * the sanity check. 
                 */
                if (!store_done) begin
                    bus.reqcyc <= 0;
                end
                if (!sending_data)
                    fetch_state <= fetch_waiting;
            end
        end
    end
end

wire[0:(128+15)*8-1] decode_bytes_repeated = { decode_buffer, decode_buffer[0:15*8-1] }; // NOTE: buffer bits are left-to-right in increasing order
wire[0:15*8-1] decode_bytes = decode_bytes_repeated[decode_offset*8 +: 15*8]; // NOTE: buffer bits are left-to-right in increasing order

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
    logic jge; // Flag for jump greater than equal to
    logic res_3; // reserved bit. Should be set to 0
    logic af; // adjust flag
    logic res_2; // reserved bit. should be set to 0
    logic pf; // Parity flag
    logic res_1; // reserved bit. should be set to 1
    logic cf; // Carry flag
} flags_reg;

// Refer to slide 11 of 43 in CSE502-L4-Pipilining.pdf
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
    // Control signals
    logic [0:7]  ctl_opcode;
    logic [0:3]  ctl_regByte;
    logic [0:3]  ctl_rmByte;
    logic sim_end;
} EX_WB;



logic [0:63] rip;

logic[0 : 3] bytes_decoded_this_cycle;    
logic jump_flag;
logic jump_signal;
logic[0 : 63] jump_target;

/* verilator lint_off UNUSED */
/* verilator lint_off UNDRIVEN */
ID_MEM idmem;
MEM_EX memex;
EX_WB exwb;
flags_reg rflags;
flags_reg rflags_seq;

// Request ack logic
always_comb begin
  if (bus.reqack && store_done)
      store_ack_received = 1;
end

mod_decode dec (
        // INPUT PARAMS
        jump_signal, fetch_rip, fetch_offset, decode_offset, 
        decode_bytes, opcode_group, callq_stage2, load_buffer, store_writeback, 
        outstanding_fetch_req,
        // OUTPUT PARAMS
        regfile, rflags, load_done, memex, exwb, rip, 
        jump_target, store_word, store_ins, store_opn, 
        jump_flag, data_req, data_reqAddr, bytes_decoded_this_cycle,
      store_writebackFlag, callqFlag, rflags_seq, idmem, jump_cond_signal
        );

always @ (posedge bus.clk) begin
    //can_decode <= 1;
    if (bus.reset) begin
        decode_offset <= 0;
        decode_buffer <= 0;
    end else begin // !bus.reset
        if (!jump_flag)
            decode_offset <= decode_offset + { 3'b0, bytes_decoded_this_cycle };
        else begin
            if (!outstanding_fetch_req && !bus.respcyc) begin
                //decode_offset <= 0;
                //fetch_offset <= 0;
            end
        end
//        $display("\n\n");
//        disp_reg_file();
//        $display("\n\n");
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

