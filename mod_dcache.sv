/* Data Cache Module */

module mod_dcache #(WORDSIZE = 64, LOGWIDTH = 6, LOGDEPTH = 9, LOGSETS = 2, TAGWIDTH = 13) (
    /* verilator lint_off UNDRIVEN */
    /* verilator lint_off UNUSED */
    DCoreCacheBus   dCoreCacheBus,
    CacheArbiterBus dCacheArbiterBus
);

parameter byteWidth = (1<<LOGWIDTH),            // Cache Block Size = 2^6 = 64 bytes
          bitWidth  = byteWidth*8,              // Cache Block Bit Size = 64*8 = 512 bits 
          wordsPerBlock = byteWidth/8,          // Words per block = 64/8 = 8 words
          totalSets = (1<<LOGSETS),             // 2^2 = 4-way set associative cache
          logDepthPerSet = LOGDEPTH - LOGSETS,  // Total Cache Entries = 2^9 = 512 entries
                                                // Cache Entries per Set = 512/4 = 128 entries
          addrsize  = 64,
          i_offset  = addrsize - 1,
          i_index   = i_offset - LOGWIDTH,
          i_tag     = i_index  - logDepthPerSet, 
          ports = 1,
          delay = (LOGDEPTH-8>0?LOGDEPTH-8:1)*(ports>1?(ports>2?(ports>3?100:20):14):10)/10;

typedef struct packed {
    logic [i_tag    : 0        ] tag;           //    Tag bit positions = 50:0
    logic [i_index  : i_tag+1  ] index;         //  Index bit positions = 57:51
    logic [i_offset : i_index+1] offset;        // Offset bit positions = 63:58
} addr_struct;

typedef struct packed {
    logic valid;
    logic dirty;
    logic [i_tag:0] tag;
} cntr_struct;

cntr_struct control [totalSets-1:0][(1<<logDepthPerSet)-1:0];

addr_struct addr;
logic[LOGSETS-1:0] set_ind;
logic[LOGSETS:0] match_ind;
logic[LOGSETS:0] lastInvalid;
logic[LOGSETS:0] i;
integer j;
integer delay_counter;
bit writeBlockToMem;
logic [addrsize-1:0] writeBlockAddr;
logic [bitWidth-1:0] writeData;

logic [LOGDEPTH-1:0] cache_readAddr;
logic [bitWidth-1:0] cache_readData;
logic [LOGDEPTH-1:0] cache_writeAddr;
logic [bitWidth-1:0] cache_writeData;
logic [wordsPerBlock-1:0] cache_writeEnable;

SRAM #(WORDSIZE, bitWidth, LOGDEPTH) sram_chip (
        dCoreCacheBus.clk, cache_readAddr, cache_readData,
        cache_writeAddr, cache_writeData, cache_writeEnable
    );

initial begin
    $display("Initializing L1 Data Cache");
end

always_comb begin
    addr = dCoreCacheBus.req;
end

enum { no_request, new_request, cache_evict_req, cache_read_req, cache_write_req, mem_read_req, mem_write_req} request_type;

assign dCacheArbiterBus.respack = dCacheArbiterBus.respcyc; // always able to accept response

always @ (posedge dCacheArbiterBus.clk) begin
    if (dCacheArbiterBus.reset) begin
        request_type <= no_request;
        for (i = 0; i < totalSets; i = i+1) begin
            for (j = 0; j < logDepthPerSet; j = j+1) begin
                control[i[LOGSETS-1:0]][j].valid <= 0;
            end
        end
        cache_writeEnable <= {wordsPerBlock{1'b0}};

    end else if ((request_type == no_request) && (dCoreCacheBus.reqcyc == 1)) begin
        dCoreCacheBus.reqack <= 1;
        dCoreCacheBus.respcyc <= 0;

        // Lookup valid index entry with matching tag in cache
        match_ind <= totalSets;
        lastInvalid <= totalSets;
        for (i = 0; i < totalSets; i++) begin
            if (control[i[LOGSETS-1:0]][addr.index].valid == 1) begin
                if (control[i[LOGSETS-1:0]][addr.index].tag == addr.tag) begin
                    match_ind <= i;
                    break;
                end
            end
            else begin
                lastInvalid <= i;
            end
        end
        request_type <= new_request;
    
    end else if (request_type == new_request) begin
        dCoreCacheBus.reqack <= 0;

        if (match_ind == totalSets) begin
            // Cache MISS
            if (dCoreCacheBus.reqtag[7:0] == 7) begin
        //$write("\n dcache NO EVICT CACHE MISS: %x $$ %x $$ %x $$ %x $$ %x\n", dCoreCacheBus.reqtag, dCoreCacheBus.req, addr.tag, addr.index, addr.offset);
                dCoreCacheBus.resptag <= dCoreCacheBus.reqtag;
                dCoreCacheBus.respcyc <= 1;
                request_type <= no_request;
            end else begin
                writeBlockToMem <= 0;
                if (lastInvalid == totalSets) begin
                    // No free cache block available. So need to replace with existing block.
                    // Can use least recently used algorithm to find the entry to be evicted
                    // For now we evict the first valid entry
                    set_ind <= 0;
                    request_type <= cache_evict_req;
                end
                else begin
                    // Free cache block entry found
                    set_ind <= lastInvalid[LOGSETS-1:0];
                    // First read the block from memory
                    dCacheArbiterBus.req <= dCoreCacheBus.req;
                    dCacheArbiterBus.reqtag <= {dCoreCacheBus.READ, dCoreCacheBus.MEMORY, {7'b0, 1'b1}};
                    dCacheArbiterBus.reqcyc <= 1;
                    request_type <= mem_read_req;
                end
            end
        end
        else begin
            // CACHE HIT
            set_ind <= match_ind[LOGSETS-1:0];

            if (dCoreCacheBus.reqtag[TAGWIDTH-1] == dCoreCacheBus.READ) begin
                cache_readAddr <= {match_ind[LOGSETS-1:0], addr.index};
                cache_writeEnable <= {wordsPerBlock{1'b0}};
                request_type <= cache_read_req;
        //$write("\n dcache READ CACHE HIT: %x $$ %x $$ %x $$ %x $$ %x\n", dCoreCacheBus.reqtag, dCoreCacheBus.req, addr.tag, addr.index, addr.offset);

            end else begin
                if (dCoreCacheBus.reqtag[7:0] == 7) begin
                    if (control[match_ind[LOGSETS-1:0]][addr.index].dirty == 1) begin
        //$write("\n dcache DIRTY EVICT CACHE HIT: %x $$ %x $$ %x $$ %x $$ %x\n", dCoreCacheBus.reqtag, dCoreCacheBus.req, addr.tag, addr.index, addr.offset);
                        request_type <= cache_evict_req;
                    end else begin
        //$write("\n dcache NOT DIRTY EVICT CACHE HIT: %x $$ %x $$ %x $$ %x $$ %x\n", dCoreCacheBus.reqtag, dCoreCacheBus.req, addr.tag, addr.index, addr.offset);
                        control[match_ind[LOGSETS-1:0]][addr.index].valid <= 0;
                        dCoreCacheBus.resptag <= dCoreCacheBus.reqtag;
                        dCoreCacheBus.respcyc <= 1;
                        request_type <= no_request;
                    end
                end else begin
                    control[match_ind[LOGSETS-1:0]][addr.index].dirty <= 1;
                    
                    // Write data directly to Cache (Write-back policy)
                    cache_writeAddr <= {match_ind[LOGSETS-1:0], addr.index};
                    cache_writeData[(64-dCoreCacheBus.reqword)*8-1 -: 64] <= dCoreCacheBus.reqdata;
                    cache_writeEnable <= 1 << (7 - dCoreCacheBus.reqword[5:3]);

                    dCoreCacheBus.resptag <= dCoreCacheBus.reqtag;
                    dCoreCacheBus.respcyc <= 1;
                    request_type <= cache_write_req;
        //$write("\n dcache WRITE CACHE HIT: %x $$ %x $$ %x $$ %x $$ %x $$ %x $$ %x\n", dCoreCacheBus.reqdata, dCoreCacheBus.reqword, dCoreCacheBus.reqtag, dCoreCacheBus.req, addr.tag, addr.index, addr.offset);
                end
            end
        end
    end else if (request_type == cache_evict_req) begin

        if (control[set_ind][addr.index].dirty == 1) begin
            // As the data is dirty, we need to evict write back it to memory
            writeBlockToMem <= 1;
            writeBlockAddr <= {control[set_ind][addr.index].tag, addr.index, {LOGWIDTH{1'b0}}};
            cache_readAddr <= {set_ind, addr.index};
            cache_writeEnable <= {wordsPerBlock{1'b0}};
        //$write("\n dcache CACHE DIRTY EVICTION: %x $$ %x $$ %x $$ %x $$ %x\n", dCoreCacheBus.reqtag, dCoreCacheBus.req, addr.tag, addr.index, addr.offset);
            
            request_type <= cache_read_req;
        end else begin
            dCacheArbiterBus.req <= dCoreCacheBus.req;
            dCacheArbiterBus.reqtag <= {dCoreCacheBus.READ, dCoreCacheBus.MEMORY, {7'b0, 1'b1}};
            dCacheArbiterBus.reqcyc <= 1;
            request_type <= mem_read_req;
        end
    end else if (request_type == mem_read_req) begin
        if (dCacheArbiterBus.reqack == 1) 
            dCacheArbiterBus.reqcyc <= 0;

        if (dCacheArbiterBus.respcyc == 1) begin

            // Send back data to Core
            dCoreCacheBus.resp <= dCacheArbiterBus.resp;
            dCoreCacheBus.resptag <= dCoreCacheBus.reqtag;
            dCoreCacheBus.respcyc <= 1;
        //$write("\n dcache Mem Read: %x $$ %x $$ %x $$ %x $$ %x $$ %x $$ %x\n", dCoreCacheBus.reqdata, dCoreCacheBus.reqword, dCoreCacheBus.reqtag, dCoreCacheBus.req, addr.tag, addr.index, addr.offset);

            // Also setup new cache block entry and write new block to cache
            control[set_ind][addr.index].tag <= addr.tag;
            control[set_ind][addr.index].valid <= 1;
            control[set_ind][addr.index].dirty <= 0;

            cache_writeAddr <= {set_ind, addr.index};
            cache_writeData <= dCacheArbiterBus.resp;
            cache_writeEnable <= {wordsPerBlock{1'b1}};

            if (dCoreCacheBus.reqtag[TAGWIDTH-1] == dCoreCacheBus.WRITE) begin
                cache_writeData[(64-dCoreCacheBus.reqword)*8-1 -: 64] <= dCoreCacheBus.reqdata;
            end

            request_type <= cache_write_req;
        end

    end else if (request_type == mem_write_req) begin
        assert(!writeBlockToMem) else $fatal;

        if (dCacheArbiterBus.reqack == 1) 
            dCacheArbiterBus.reqcyc <= 0;

        if (dCacheArbiterBus.respcyc == 1) begin
        //$write("\n dcache Mem Write: %x $$ %x $$ %x $$ %x $$ %x\n", dCoreCacheBus.reqtag, dCoreCacheBus.req, addr.tag, addr.index, addr.offset);
        
            if (dCoreCacheBus.reqtag[7:0] == 7) begin
                // Dirty block evicted. Make the block Invalid
                control[set_ind][addr.index].valid <= 0;
                dCoreCacheBus.resptag <= dCoreCacheBus.reqtag;
                dCoreCacheBus.respcyc <= 1;
                request_type <= no_request;

            end else begin
                // Read the requested block from memory
                dCacheArbiterBus.req <= dCoreCacheBus.req;
                dCacheArbiterBus.reqtag <= {dCoreCacheBus.READ, dCoreCacheBus.MEMORY, {7'b0, 1'b1}};
                dCacheArbiterBus.reqcyc <= 1;
                request_type <= mem_read_req;

            end 
        end
    end else if (request_type == cache_read_req) begin

        if (delay_counter >= delay) begin

        //$write("\n dcache Cache Read: %x $$ %x \n", cache_readData, cache_writeEnable);
            if (writeBlockToMem) begin
                // Write the dirty cache block to the memory
                dCacheArbiterBus.req <= writeBlockAddr & ~63;
                dCacheArbiterBus.reqdata <= cache_readData;
                dCacheArbiterBus.reqtag <= {dCoreCacheBus.WRITE, dCoreCacheBus.MEMORY, {6'b0, 1'b0, 1'b0}};
                dCacheArbiterBus.reqcyc <= 1;

                request_type <= mem_write_req;
                writeBlockToMem <= 0;
            end else begin
                // Send Cache block to dCoreCacheBus
                dCoreCacheBus.resp <= cache_readData;
                dCoreCacheBus.resptag <= dCoreCacheBus.reqtag;
                dCoreCacheBus.respcyc <= 1;
                request_type <= no_request;
            end

            delay_counter <= 0;
        end else begin
            delay_counter <= delay_counter + 1;
        end

    end else if (request_type == cache_write_req) begin
        dCoreCacheBus.respcyc <= 0;

        if (delay_counter >= delay) begin
            
        //$write("\n dcache Cache Write: %x $$ %x $$ %x\n\n", cache_writeAddr, cache_writeData, cache_writeEnable);
            // Data already sent to dCoreCacheBus
            request_type <= no_request;
            delay_counter <= 0;
            cache_writeEnable <= {wordsPerBlock{1'b0}};
        end else begin
            delay_counter <= delay_counter + 1;
        end
    end else begin
        dCoreCacheBus.respcyc <= 0;
    end
end

endmodule

