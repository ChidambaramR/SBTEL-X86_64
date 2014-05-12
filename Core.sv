/* Core Module containing the Fetch-Stage */

module Core (
    input[63:0] entry,
    /* verilator lint_off UNDRIVEN */
    /* verilator lint_off UNUSED */
    ICoreCacheBus bus,
    DCoreCacheBus databus
);

// Varuns's change
import "DPI-C" function longint syscall_cse502(input longint rax, input longint rdi, input longint rsi, input longint rdx, input longint r10, input longint r8, input longint r9);

enum { fetch_idle, fetch_waiting, fetch_active } fetch_state;
logic[63:0] fetch_rip;
logic[0:2*2*64*8-1] decode_buffer;
logic[0:64*8-1] data_buffer;
logic[0:8*8-1] load_buffer;
logic[0:8*8-1] store_word;
logic store_ins;
logic store_writeback;
logic store_writebackFlag;
logic store_opn;
logic clflush_signal;

logic load_done;
logic[5:0] fetch_skip;
logic[5:0] fetch_data_skip;
logic[7:0] fetch_offset, decode_offset;
logic[0:63] regfile[0:16-1];

logic [0:8] i = 0;
logic [0:4] j = 0;

// 2D Array
logic [0:255][0:0][0:3] opcode_group;

logic data_req;
logic callqFlag;
logic callq_stage2;

logic [0:63] data_reqAddr;
logic [0:63] clflush_param;

initial begin

    for (i = 0; i < 256; i++)
    begin
        opcode_group[i] = 0;
    end

    for (j = 0; j <= 15; j++) begin
        regfile[j[1:4]] = {64{1'b0}};
    end

    regfile[4] = 31744;  // Initialize RSP to 0x7C00
    callqFlag = 0;

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

logic send_fetch_req;
logic outstanding_req;
logic jump_sent;

/* verilator lint_off IMPLICIT */
always_comb begin
    if (fetch_state != fetch_idle) begin
        send_fetch_req = 0;
    end else if (bus.reqack) begin
        send_fetch_req = 0;
    end else if (!jump_signal && !jump_cond_signal && !store_ins && !data_req) begin
        send_fetch_req = (fetch_offset - decode_offset < 8'd16);
    end
end

assign bus.respack = bus.respcyc; // always able to accept response
assign databus.respack = databus.respcyc; // always able to accept response

always @ (posedge bus.clk) begin
    if (bus.reset) begin

        fetch_state <= fetch_idle;
        fetch_rip <= entry & ~63;
        fetch_skip <= entry[5:0];
        fetch_offset <= 0;

    end else begin // !bus.reset
        /*
         * REQCYC
         * If reqcyc is up, then we are sending a request to the memory.
         * Immediately after sending the request, we will be getting back an 
         * ACK from the bus. Once we get back an ACK, we know our request 
         * has been acknowledged and we have to start waiting for the resposne. 
         *
         * SEND_FETCH_REQ
         * Whenever we get an ACK, the send_fetch_req goes down.
         */

        if (store_writebackFlag)
            store_writeback <= 1;
        
        if (clflush_ins == 1)
            clflush_signal <= 1;

        if (!bus.respcyc) begin

            if (jump_signal && !outstanding_req) begin
                // Fetch request for jump instruction
                outstanding_req <= 1;
                bus.req <= jump_target & ~63;
                bus.reqtag <= { bus.READ, bus.MEMORY, 8'b0 };
                bus.reqcyc <= 1;
                store_writeback <= 0;
                fetch_offset <= 0;
                decode_offset <= 0;
                jump_sent <= 1;
            end

            if (!data_req && !store_ins) begin
                // Sending a request for instruction fetch
                if (send_fetch_req) begin
                    outstanding_req <= 1;
                    bus.req <= fetch_rip & ~63;
                    bus.reqtag <= { bus.READ, bus.MEMORY, 8'b0 };
                    bus.reqcyc <= send_fetch_req;
                    store_writeback <= 0;
                end
            end
        end

        if (!databus.respcyc) begin
            if (!outstanding_req) begin
                if (clflush_ins) begin
                    databus.req <= (clflush_param & ~63);
                    databus.reqtag <= { databus.WRITE, databus.MEMORY, {5'b0,1'b1,1'b1,1'b1} };
                    databus.reqcyc <= 1;
                    outstanding_req <= 1;

                end else if (store_ins && store_opn) begin
                    // Handling store instruction
                    databus.req <= (data_reqAddr & ~63);
                    databus.reqcyc <= 1;
                    databus.reqtag <= { databus.WRITE, databus.MEMORY, {6'b0,1'b1,1'b1}};
                    databus.reqdata <= store_word;
                    databus.reqword <= (data_reqAddr[58:63])&(~7);
                    outstanding_req <= 1;

                end else if (data_req) begin
                    // Sending a request for data
                    databus.req <= (data_reqAddr & ~63) ;
                    fetch_data_skip <= (data_reqAddr[58:63])&(~7);
                    databus.reqtag <= { databus.READ, databus.MEMORY, {7'b0,1'b1}};
                    databus.reqcyc <= 1;
                    data_buffer <= 0;
                    load_buffer <= 0;
                    load_done <= 0;
                    outstanding_req <= 1;
                end
            end
        end

        if (bus.respcyc && (bus.resptag[7:0] == 0)) begin
             // It takes around 48 micro seconds for a response to come back.
            if (jump_signal && jump_sent) begin
                jump_signal <= 0;
                /* verilator lint_off BLKSEQ */
                jump_flag = 0;
                jump_sent <= 0;
            end

            assert(!send_fetch_req) else $fatal;
            outstanding_req <= 0;
            fetch_state <= fetch_active;

            if (fetch_skip == 0)
                        decode_buffer[(fetch_offset*8) +: 512-0*8 ] <= bus.resp[511-0*8  : 0];
            else if (fetch_skip == 1)
                        decode_buffer[(fetch_offset*8) +: 512-1*8 ] <= bus.resp[511-1*8  : 0];
            else if (fetch_skip == 2)
                        decode_buffer[(fetch_offset*8) +: 512-2*8 ] <= bus.resp[511-2*8  : 0];
            else if (fetch_skip == 3)
                        decode_buffer[(fetch_offset*8) +: 512-3*8 ] <= bus.resp[511-3*8  : 0];
            else if (fetch_skip == 4) 
                        decode_buffer[(fetch_offset*8) +: 512-4*8 ] <= bus.resp[511-4*8  : 0];
            else if (fetch_skip == 5)
                        decode_buffer[(fetch_offset*8) +: 512-5*8 ] <= bus.resp[511-5*8  : 0];
            else if (fetch_skip == 6)
                        decode_buffer[(fetch_offset*8) +: 512-6*8 ] <= bus.resp[511-6*8  : 0];
            else if (fetch_skip == 7)
                        decode_buffer[(fetch_offset*8) +: 512-7*8 ] <= bus.resp[511-7*8  : 0];
            else if (fetch_skip == 8)
                        decode_buffer[(fetch_offset*8) +: 512-8*8 ] <= bus.resp[511-8*8  : 0];
            else if (fetch_skip == 9)
                        decode_buffer[(fetch_offset*8) +: 512-9*8 ] <= bus.resp[511-9*8  : 0];
            else if (fetch_skip == 10)
                        decode_buffer[(fetch_offset*8) +: 512-10*8] <= bus.resp[511-10*8 : 0];
            else if (fetch_skip == 11)
                        decode_buffer[(fetch_offset*8) +: 512-11*8] <= bus.resp[511-11*8 : 0];
            else if (fetch_skip == 12)
                        decode_buffer[(fetch_offset*8) +: 512-12*8] <= bus.resp[511-12*8 : 0];
            else if (fetch_skip == 13)
                        decode_buffer[(fetch_offset*8) +: 512-13*8] <= bus.resp[511-13*8 : 0];
            else if (fetch_skip == 14)
                        decode_buffer[(fetch_offset*8) +: 512-14*8] <= bus.resp[511-14*8 : 0];
            else if (fetch_skip == 15)
                        decode_buffer[(fetch_offset*8) +: 512-15*8] <= bus.resp[511-15*8 : 0];
            else if (fetch_skip == 16)
                        decode_buffer[(fetch_offset*8) +: 512-16*8] <= bus.resp[511-16*8 : 0];
            else if (fetch_skip == 17)
                        decode_buffer[(fetch_offset*8) +: 512-17*8] <= bus.resp[511-17*8 : 0];
            else if (fetch_skip == 18)
                        decode_buffer[(fetch_offset*8) +: 512-18*8] <= bus.resp[511-18*8 : 0];
            else if (fetch_skip == 19)
                        decode_buffer[(fetch_offset*8) +: 512-19*8] <= bus.resp[511-19*8 : 0];
            else if (fetch_skip == 20)
                        decode_buffer[(fetch_offset*8) +: 512-20*8] <= bus.resp[511-20*8 : 0];
            else if (fetch_skip == 21)
                        decode_buffer[(fetch_offset*8) +: 512-21*8] <= bus.resp[511-21*8 : 0];
            else if (fetch_skip == 22)
                        decode_buffer[(fetch_offset*8) +: 512-22*8] <= bus.resp[511-22*8 : 0];
            else if (fetch_skip == 23)
                        decode_buffer[(fetch_offset*8) +: 512-23*8] <= bus.resp[511-23*8 : 0];
            else if (fetch_skip == 24)
                        decode_buffer[(fetch_offset*8) +: 512-24*8] <= bus.resp[511-24*8 : 0];
            else if (fetch_skip == 25)
                        decode_buffer[(fetch_offset*8) +: 512-25*8] <= bus.resp[511-25*8 : 0];
            else if (fetch_skip == 26)
                        decode_buffer[(fetch_offset*8) +: 512-26*8] <= bus.resp[511-26*8 : 0];
            else if (fetch_skip == 27)
                        decode_buffer[(fetch_offset*8) +: 512-27*8] <= bus.resp[511-27*8 : 0];
            else if (fetch_skip == 28)
                        decode_buffer[(fetch_offset*8) +: 512-28*8] <= bus.resp[511-28*8 : 0];
            else if (fetch_skip == 29)
                        decode_buffer[(fetch_offset*8) +: 512-29*8] <= bus.resp[511-29*8 : 0];
            else if (fetch_skip == 30)
                        decode_buffer[(fetch_offset*8) +: 512-30*8] <= bus.resp[511-30*8 : 0];
            else if (fetch_skip == 31)
                        decode_buffer[(fetch_offset*8) +: 512-31*8] <= bus.resp[511-31*8 : 0];
            else if (fetch_skip == 32)
                        decode_buffer[(fetch_offset*8) +: 512-32*8] <= bus.resp[511-32*8 : 0];
            else if (fetch_skip == 33)
                        decode_buffer[(fetch_offset*8) +: 512-33*8] <= bus.resp[511-33*8 : 0];
            else if (fetch_skip == 34)
                        decode_buffer[(fetch_offset*8) +: 512-34*8] <= bus.resp[511-34*8 : 0];
            else if (fetch_skip == 35)
                        decode_buffer[(fetch_offset*8) +: 512-35*8] <= bus.resp[511-35*8 : 0];
            else if (fetch_skip == 36)
                        decode_buffer[(fetch_offset*8) +: 512-36*8] <= bus.resp[511-36*8 : 0];
            else if (fetch_skip == 37)
                        decode_buffer[(fetch_offset*8) +: 512-37*8] <= bus.resp[511-37*8 : 0];
            else if (fetch_skip == 38)
                        decode_buffer[(fetch_offset*8) +: 512-38*8] <= bus.resp[511-38*8 : 0];
            else if (fetch_skip == 39)
                        decode_buffer[(fetch_offset*8) +: 512-39*8] <= bus.resp[511-39*8 : 0];
            else if (fetch_skip == 40)
                        decode_buffer[(fetch_offset*8) +: 512-40*8] <= bus.resp[511-40*8 : 0];
            else if (fetch_skip == 41)
                        decode_buffer[(fetch_offset*8) +: 512-41*8] <= bus.resp[511-41*8 : 0];
            else if (fetch_skip == 42)
                        decode_buffer[(fetch_offset*8) +: 512-42*8] <= bus.resp[511-42*8 : 0];
            else if (fetch_skip == 43)
                        decode_buffer[(fetch_offset*8) +: 512-43*8] <= bus.resp[511-43*8 : 0];
            else if (fetch_skip == 44)
                        decode_buffer[(fetch_offset*8) +: 512-44*8] <= bus.resp[511-44*8 : 0];
            else if (fetch_skip == 45)
                        decode_buffer[(fetch_offset*8) +: 512-45*8] <= bus.resp[511-45*8 : 0];
            else if (fetch_skip == 46)
                        decode_buffer[(fetch_offset*8) +: 512-46*8] <= bus.resp[511-46*8 : 0];
            else if (fetch_skip == 47)
                        decode_buffer[(fetch_offset*8) +: 512-47*8] <= bus.resp[511-47*8 : 0];
            else if (fetch_skip == 48)
                        decode_buffer[(fetch_offset*8) +: 512-48*8] <= bus.resp[511-48*8 : 0];
            else if (fetch_skip == 49)
                        decode_buffer[(fetch_offset*8) +: 512-49*8] <= bus.resp[511-49*8 : 0];
            else if (fetch_skip == 50)
                        decode_buffer[(fetch_offset*8) +: 512-50*8] <= bus.resp[511-50*8 : 0];
            else if (fetch_skip == 51)
                        decode_buffer[(fetch_offset*8) +: 512-51*8] <= bus.resp[511-51*8 : 0];
            else if (fetch_skip == 52)
                        decode_buffer[(fetch_offset*8) +: 512-52*8] <= bus.resp[511-52*8 : 0];
            else if (fetch_skip == 53)
                        decode_buffer[(fetch_offset*8) +: 512-53*8] <= bus.resp[511-53*8 : 0];
            else if (fetch_skip == 54)
                        decode_buffer[(fetch_offset*8) +: 512-54*8] <= bus.resp[511-54*8 : 0];
            else if (fetch_skip == 55)
                        decode_buffer[(fetch_offset*8) +: 512-55*8] <= bus.resp[511-55*8 : 0];
            else if (fetch_skip == 56)
                        decode_buffer[(fetch_offset*8) +: 512-56*8] <= bus.resp[511-56*8 : 0];
            else if (fetch_skip == 57)
                        decode_buffer[(fetch_offset*8) +: 512-57*8] <= bus.resp[511-57*8 : 0];
            else if (fetch_skip == 58)
                        decode_buffer[(fetch_offset*8) +: 512-58*8] <= bus.resp[511-58*8 : 0];
            else if (fetch_skip == 59)
                        decode_buffer[(fetch_offset*8) +: 512-59*8] <= bus.resp[511-59*8 : 0];
            else if (fetch_skip == 60)
                        decode_buffer[(fetch_offset*8) +: 512-60*8] <= bus.resp[511-60*8 : 0];
            else if (fetch_skip == 61)
                        decode_buffer[(fetch_offset*8) +: 512-61*8] <= bus.resp[511-61*8 : 0];
            else if (fetch_skip == 62)
                        decode_buffer[(fetch_offset*8) +: 512-62*8] <= bus.resp[511-62*8 : 0];
            else if (fetch_skip == 63)
                        decode_buffer[(fetch_offset*8) +: 512-63*8] <= bus.resp[511-63*8 : 0];

            fetch_offset <= (fetch_offset + 64) - {1'b0, 1'b0, fetch_skip};
            fetch_rip <= fetch_rip + 64;
            fetch_skip <= 0;
            
        end else begin
            // Handling the jump signal when no response in the bus
            if (jump_flag) begin
                 // A jump is found and we need to resteer the fetch
                if (!outstanding_req) begin
                    fetch_rip <= (jump_target & ~63);
                    decode_buffer <= 0;
                    /* verilator lint_off WIDTH */
                    fetch_skip <= ((jump_target[58:63])&(~7)) + ((jump_target[58:63])&(7));
                end
                jump_signal <= 1;
                if (callq_stage2)
                    callq_stage2 <= 0;
            end

            if (fetch_state == fetch_active) begin
                fetch_state <= fetch_idle;
            end else if (bus.reqack) begin
                /*
                 * We got an ACK from the bus. So we have to wait.
                 */
                assert(fetch_state == fetch_idle) else $fatal;
                /*
                 * At the point when we got an ACK, the fetch state should have been idle. If the
                 * fetch state was not idle, we would not have sent a request at all. So we are making
                 * the sanity check. 
                 */
                bus.reqcyc <= 0;
                fetch_state <= fetch_waiting;
            end
        end
        
        if (databus.respcyc && (databus.resptag[7:0] == 1)) begin
            // We received a response for data read request
            if (!load_done) begin
                data_req <= 0;
                load_buffer[0 : 63] <= databus.resp[(64-fetch_data_skip)*8-1 -: 64];
                load_done <= 1;
                if (callqFlag)
                    callq_stage2 <= 1;
            end
            outstanding_req <= 0;
        end else if (databus.respcyc && (databus.resptag[7:0] == 3)) begin
            // We received a response for data store request
            store_writeback <= 0;
            store_opn <= 0;
            if (callqFlag)
                callq_stage2 <= 1;

            outstanding_req <= 0;
        end else if (databus.respcyc && (databus.resptag[7:0] == 7)) begin
            // We received a response for cache line flush request
            clflush_signal <= 0;
            outstanding_req <= 0;

        end else begin
            load_done <= 0;
            if (databus.reqack) begin
                databus.reqcyc <= 0;
            end
        end
    end
end

wire[0:(2*128+15)*8-1] decode_bytes_repeated = { decode_buffer, decode_buffer[0:15*8-1] }; // NOTE: buffer bits are left-to-right in increasing order
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
    logic [0:1]  mod;
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
    logic [0:3]  ctl_regByte;
    logic [0:3]  ctl_rmByte;
    logic sim_end;
    logic [0:1] mod;
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

mod_decode decode (
        // INPUT PARAMS
        jump_signal, fetch_rip, fetch_offset, decode_offset, 
        decode_bytes, opcode_group, callq_stage2, load_buffer, store_writeback, 
        end_prog, clflush_signal,
        // OUTPUT PARAMS
        regfile, rflags, load_done, memex, exwb, rip, 
        jump_target, store_word, store_ins, store_opn, 
        jump_flag, data_req, data_reqAddr, bytes_decoded_this_cycle,
        store_writebackFlag, callqFlag, rflags_seq, idmem, jump_cond_signal,
        end_progFlag, clflush_ins, clflush_param
    );

always @ (posedge bus.clk) begin
    if (bus.reset) begin
        decode_offset <= 0;
        decode_buffer <= 0;
    end else begin // !bus.reset
        if (end_progFlag)
            end_prog <= 1;

        if (!jump_flag)
            decode_offset <= decode_offset + { 3'b0, bytes_decoded_this_cycle };
        else if (jump_flag && bus.respcyc)
            jump_signal <= 1;
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

