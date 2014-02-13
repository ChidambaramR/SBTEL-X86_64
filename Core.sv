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
    logic [0:3] def;
    logic W, R, Xe, B;
} rex;

/*
This is the mod_rm byte
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
This is the main instruction structure
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

//Sohil Code
        logic [0:255][0:1][0:7] mod_rm_enc;
        logic [255:0][7:0][7:0] opcode_char;
        logic [0:15][0:3][0:7] reg_table_64;
        logic [7:0][7:0]str = {"       "};
        logic [8:0] i = 0;
        initial 
        begin
            for( i = 0; i < 256; i++)
            begin
                opcode_char[i] = str;
                mod_rm_enc[i] = 0;
            end 
            /*
            Following values are converted into decimal from hex.
            For example, 0x89 is the hex opcode. This is 137 in decimal
            */
            opcode_char[49] = "XOR     ";
            opcode_char[137] = "MOV     ";
            opcode_char[131] = "AND     ";
            opcode_char[199] = "XOR     ";
            mod_rm_enc[137] = "MR";

            /*
            Table for 64 bit registers. It taken from os dev wiki page, "Registers table"
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
					$display("fill at %d: %x [%x]", fetch_offset, bus.resp, decode_buffer);
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
	wire can_decode = (fetch_offset - decode_offset >= 15);

	function logic opcode_inside(logic[7:0] value, low, high);
		opcode_inside = (value >= low && value <= high);
	endfunction

	logic[3:0] bytes_decoded_this_cycle;
        logic[0 : 7] opcode;
        logic[0 : 7] length;
        logic[0 : 7] offset;
        logic[0 : 1*8-1] temp_prefix;
        rex rex_prefix;
        op_override op_ride;
        mod_rm modRM_byte;
	always_comb begin
		if (can_decode) begin : decode_block

		        // Variable keeping track of the length of the instruction
  	                length = 0;
                        offset = 0;
       /*                 ins = decode_bytes[0 : length*8-1];
                        $display("ins %x",ins);
                        instrn = ins[0:23]; 
       */
       //                 $display("Rex prefix = %x",instrn.rex_prefix);
       //                 $display("Opcode = %s",opcode_char[instrn.opcode]);

                        /*
                        Prefix decoding
                        */
                        temp_prefix = decode_bytes[offset*8 +: 1*8];
                          $display("Prefix %x",temp_prefix);
                        if(temp_prefix >= 64 && temp_prefix <= 79) begin
                          length += 1;
                          rex_prefix = temp_prefix[0 : 7];
                          offset += 1;

                          /*
                          Opcode decoding
                          */
                            opcode = decode_bytes[offset*8 +: 1*8];
                              if(opcode != 15) begin
                                length += 1;
                                $display("Opcode %x mod_rm = %x",opcode,mod_rm_enc[opcode]);
                                if(mod_rm_enc != 0) begin
                                  /*
                                  We have found a Mod R/M byte.
                                  The direction (source / destination is available in mod_rm_enc value")
                                  */
                                  offset += 1;
                                  modRM_byte = decode_bytes[offset*8 +: 1*8];
                                  $display("%s %s",reg_table_64[modRM_byte.rm], reg_table_64[modRM_byte.reg1]);          
                                end
                              end else begin
                                length += 2;
                                offset += 1;
                              end

                          //$display("1st nibble = %x",rex_prefix.def);
                        end else if(temp_prefix == 102) begin
                          op_ride = temp_prefix[0 : 7];
                          length += 1;
                        end


			bytes_decoded_this_cycle =+ length;
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

                        $display("OPCODE %x: %s", opcode, opcode_char[opcode]);
/*SOHIL CODE
                        $display("OPCODE %d: %s", 137, opcode_char[137]);
                        $display("OPCODE %d: %s", 131, opcode_char[131]);
                        $display("OPCODE %d: %s", 199, opcode_char[199]);
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
