module Core (
	input[63:0] entry
,	/* verilator lint_off UNDRIVEN */ /* verilator lint_off UNUSED */ Sysbus bus /* verilator lint_on UNUSED */ /* verilator lint_on UNDRIVEN */
);
	enum { fetch_idle, fetch_waiting, fetch_active } fetch_state;
	logic[63:0] fetch_rip;
	logic[0:2*64*8-1] decode_buffer; // NOTE: buffer bits are left-to-right in increasing order
	logic[5:0] fetch_skip;
	logic[6:0] fetch_offset, decode_offset;

// Imp Data structures
/*
This is the REX prefix
*/
typedef struct packed {
    logic [3:0] def;
    logic W, R, Xe, B;
} rex;

/*
This is the mod_rm byte
*/
typedef struct packed {
    logic [7:6] mod;
    logic [5:3] reg1;
    logic [2:0] rm; 
} mod_rm;

/*
This is the main instruction structure
*/
typedef struct packed {
    rex rex_prefix;
    logic [7:0]opcode;
    mod_rm mod_rm_byte;
} instruction;

/*
Sample way to assign values
*/
rex temp1 = {4'b0100, 1'b1, 1'b1, 1'b1, 1'b1};

//Sohil Code
        logic [255:0][7:0][7:0] opcode_chr;
        logic [7:0][7:0]str = {"       "};
        logic [8:0] i = 0;
        initial 
        begin
            for( i = 0; i < 256; i++)
            begin
                opcode_chr[i] = str;
            end 
            opcode_chr[49] = "XOR     ";
            opcode_chr[137] = "MOV     ";
            opcode_chr[131] = "AND     ";
            opcode_chr[199] = "XOR     ";
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

	always @ (posedge bus.clk)
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
//					$display("fill at %d: %x [%x]", fetch_offset, bus.resp, decode_buffer);
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

	wire[0:(128+15)*8-1] decode_bytes_repeated = { decode_buffer, decode_buffer[0:15*8-1] }; // NOTE: buffer bits are left-to-right in increasing order
	wire[0:15*8-1] decode_bytes = decode_bytes_repeated[decode_offset*8 +: 15*8]; // NOTE: buffer bits are left-to-right in increasing order
        wire[0:8-1] small_buff;
	wire can_decode = (fetch_offset - decode_offset >= 15);

	function logic opcode_inside(logic[7:0] value, low, high);
		opcode_inside = (value >= low && value <= high);
	endfunction

	logic[3:0] bytes_decoded_this_cycle;
        logic W, R, Ex, B;
        logic[0 : 7] opcode;
        logic[0 : 3] reg_byte, rm_byte;
        logic[0 : 1] mod;
        logic[0 : 7] length;
 
	always_comb begin
		if (can_decode) begin : decode_block
			// cse502 : Decoder here
			// remove the following line. It is only here to allow successful compilation in the absence of your code.
			length = 0;
/*                        if (decode_bytes == 0) ;
                        small_buff = decode_bytes[0 : 7];
                            $display("small buff = %x",small_buff);
                        if (small_buff[0:3] == 4) begin
                            W = small_buff[4];
                            R = small_buff[5];
                            Ex = small_buff[6];
                            B = small_buff[7];
			    bytes_decoded_this_cycle =+ 1;
                            opcode = decode_bytes[8 : 15];
                            if (opcode == 31)
                              $display("XOR");
			    bytes_decoded_this_cycle =+ 1;
                            mod = decode_bytes[16 : 17];
                            reg_byte = { {R}, {decode_bytes[18 : 20]} };
                            rm_byte = { {B}, {decode_bytes[21 : 23]} };
                            if(reg_byte == 5)
                              $display("reg byte rbp.W = %x, R = %x, Ex = %x, B = %x, mod = %x",W,R,Ex,B,mod);
                            if(rm_byte == 5)
                              $display("rm byte rbp"); 
                        end
                            $display("Yes IT is REX prefix");

                        $display("OPCODE %x: %s", opcode, opcode_chr[opcode]);
/*SOHIL CODE
                        $display("OPCODE %d: %s", 137, opcode_chr[137]);
                        $display("OPCODE %d: %s", 131, opcode_chr[131]);
                        $display("OPCODE %d: %s", 199, opcode_chr[199]);
*/
/*
			bytes_decoded_this_cycle =+ 15;
*/
			// cse502 : following is an example of how to finish the simulation
			if (decode_bytes == 0 && fetch_state == fetch_idle) $finish;
		end else begin
			bytes_decoded_this_cycle = 0;
		end
	end

	always @ (posedge bus.clk)
		if (bus.reset) begin

			decode_offset <= 0;
			decode_buffer <= 0;

		end else begin // !bus.reset

			decode_offset <= decode_offset + { 3'b0, bytes_decoded_this_cycle };

		end

endmodule
