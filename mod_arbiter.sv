/* Arbiter Module to communicate between DCache/ICache and Memory */

module mod_arbiter #(DATA_WIDTH = 512, TAG_WIDTH = 13) (
    /* verilator lint_off UNDRIVEN */
    /* verilator lint_off UNUSED */
    Sysbus bus,
    CacheArbiterBus iCacheBus,
    CacheArbiterBus dCacheBus
);

enum {sysbus_idle, sysbus_iread, sysbus_dread, sysbus_iread_done, sysbus_dread_done, sysbus_dwrite} sysbus_state;

logic send_sysbus_req;
logic [0:DATA_WIDTH-1] data_buffer;
logic [ TAG_WIDTH-1:0] tag_data;
integer data_offset;

initial begin
    $display("Initializing Arbiter Module");
end

function logic[0 : 8*8-1] byte8_swap(logic[0 : 8*8-1] inp);
      logic[0 : 8*8-1] ret_val;
      integer ii;

      for (ii = 0; ii < 8; ii++) begin
          ret_val[ii*8 +: 8] = inp[(7-ii)*8 +: 8];
      end  

      byte8_swap = ret_val;
endfunction

assign bus.respack = bus.respcyc; // always able to accept response

always @ (posedge bus.clk) begin
    if (bus.reset) begin

        sysbus_state <= sysbus_idle;
        
    end else begin // !bus.reset
        
        if (sysbus_state == sysbus_idle && (dCacheBus.reqcyc || iCacheBus.reqcyc)) begin

            if (dCacheBus.reqcyc) begin
                dCacheBus.reqack <= 1;

                bus.req    <= dCacheBus.req;
                bus.reqtag <= dCacheBus.reqtag;
                bus.reqcyc <= 1;

                if (dCacheBus.reqtag[TAG_WIDTH-1] == dCacheBus.READ) begin
                    sysbus_state <= sysbus_dread;
                end else begin
                    sysbus_state <= sysbus_dwrite;
                    data_offset <= 56;
                end
                
            end else if (iCacheBus.reqcyc) begin
                iCacheBus.reqack <= 1;

                bus.req    <= iCacheBus.req;
                bus.reqtag <= iCacheBus.reqtag;
                bus.reqcyc <= 1;

                sysbus_state <= sysbus_iread;
            end

        end else if (sysbus_state == sysbus_iread) begin
            if (bus.reqack)
                bus.reqcyc <= 0;
            iCacheBus.reqack <= 0;

            if (bus.respcyc) begin
                data_buffer[data_offset*8 +: 64] <= bus.resp;
                data_offset <= data_offset + 8;

                if (data_offset >= 56) begin
                    iCacheBus.resptag <= bus.resptag;
                    sysbus_state <= sysbus_iread_done;
                end
            end

        end else if (sysbus_state == sysbus_iread_done) begin
            // 64 bytes read, ready to send them to icache
            iCacheBus.resp <= data_buffer;
            iCacheBus.respcyc <= 1;

            sysbus_state <= sysbus_idle;
            data_buffer <= 0;
            data_offset <= 0;

        end else if (sysbus_state == sysbus_dread) begin
            if (bus.reqack)
                bus.reqcyc <= 0;
            dCacheBus.reqack <= 0;

            if (bus.respcyc) begin
                data_buffer[data_offset*8 +: 64] <= byte8_swap(bus.resp);
                data_offset <= data_offset + 8;

                if (data_offset >= 56) begin
                    dCacheBus.resptag <= bus.resptag;
                    sysbus_state <= sysbus_dread_done;
                end
            end

        end else if (sysbus_state == sysbus_dread_done) begin
            // 64 bytes read, ready to send them to icache
            dCacheBus.resp <= data_buffer;
            dCacheBus.respcyc <= 1;

            sysbus_state <= sysbus_idle;
            data_buffer <= 0;
            data_offset <= 0;

        end else if (sysbus_state == sysbus_dwrite) begin

            assert(!bus.respcyc) else $fatal;

            if (bus.reqack) begin
                bus.req <= byte8_swap(dCacheBus.reqdata[data_offset*8 +: 64]);
                bus.reqcyc <= 1;
                data_offset <= data_offset - 8; 

                if (data_offset == 0) begin
                    // 64 bytes written, ready to send signal to dcache
                    dCacheBus.resptag <= bus.resptag;
                    dCacheBus.respcyc <= 1;

                    sysbus_state <= sysbus_idle;
                    data_offset <= 0;
                end
            end
        end else begin
            bus.reqcyc <= 0;
            iCacheBus.respcyc <= 0;
            dCacheBus.respcyc <= 0;
        end
    end
end

endmodule
