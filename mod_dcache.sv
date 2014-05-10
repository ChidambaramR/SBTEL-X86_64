module mod_dcache #(WORDSIZE = 64, LOGWIDTH = 6, LOGDEPTH = 9, LOGSETS = 2) (
    DCoreCacheBus   dCoreCacheBus,
    CacheArbiterBus dCacheArbiterBus
);

parameter logWidth  = LOGWIDTH,
          byteWidth = (1<<logWidth),            // Cache Block Size = 2^6 = 64 bytes
          bitWidth  = byteWidth*8,              // Cache Block Bit Size = 64*8 = 512 bits 
          wordsize  = WORDSIZE,
          wordsPerBlock = byteWidth/8,          // Words per block = 64/8 = 8 words
          logSets   = LOGSETS,
          totalSets = (1<<logSets),             // 2^2 = 4-way set associative cache
          logDepth  = LOGDEPTH,                 // Total Cache Entries = 2^9 = 512 entries
          logDepthPerSet = logDepth - logSets,  // Cache Entries per Set = 512/4 = 128 entries
          addrsize  = 64,
          i_offset  = addrsize - 1,
          i_index   = i_offset - logWidth,
          i_tag     = i_index  - logDepthPerSet, 
          ports = 1,
          delay = (logDepth-8>0?logDepth-8:1)*(ports>1?(ports>2?(ports>3?100:20):14):10)/10-1;

typedef struct packed {
    logic [0         : i_tag   ] tag;           //    Tag bit positions = 0 :50
    logic [i_tag+1   : i_index ] index;         //  Index bit positions = 51:57
    logic [i_index+1 : i_offset] offset;        // Offset bit positions = 58:63
} addr_struct;

typedef struct packed {
    logic valid;
    logic dirty;
    logic [i_tag:0] tag;
} cntr_struct;

cntr_struct control [totalSets-1:0][(1<<logDepthPerSet)-1:0];

addr_struct addr;
logic[bitWidth-1:0] writeData;
logic[logSets-1:0] set_ind;
logic[logSets:0] match_ind;
logic[logSets:0] lastInvalid;
logic[logSets:0] i;
integer j;
integer delay_counter;
bit writeBlockToMem;
wire [addrsize-1:0] writeBlockAddr;

logic [logDepth-1:0] cache_readAddr;
logic [bitWidth-1:0] cache_readData;
logic [logDepth-1:0] cache_writeAddr;
logic [bitWidth-1:0] cache_writeData;
logic [wordsPerBlock-1:0] cache_writeEnable;

SRAM #(WORDSIZE, LOGWIDTH+3, LOGDEPTH) sram_chip (
        dCoreCacheBus.clk, cache_readAddr, cache_readData,
        cache_writeAddr, cache_writeData, cache_writeEnable
    );

initial begin
    for (i = 0; i < totalSets; i++) begin
        set_ind <= i[logSets:1];
        for (j = 0; j < logDepthPerSet; j++) begin
            control[set_ind][j].valid = 0;
        end
    end
    delay_counter = 0;
    cache_writeEnable = {wordsPerBlock{1'b0}};
    $display("Initializing L1 Data Cache");
end

always_comb begin
    addr = dCoreCacheBus.req;
end

enum { no_request, cache_read_req, cache_write_req, mem_read_req, mem_write_req} request_type;

assign dCacheArbiterBus.respack = dCacheArbiterBus.respcyc; // always able to accept response

always @ (posedge dCacheArbiterBus.clk) begin
    if (dCacheArbiterBus.reset) begin
        request_type <= no_request;

    end else if ((request_type == no_request) && (dCoreCacheBus.reqcyc == 1)) begin
        dCoreCacheBus.reqack <= 1;
        dCoreCacheBus.respcyc <= 0;

        // Lookup valid index entry with matching tag in cache
        match_ind <= totalSets;
        lastInvalid <= totalSets;
        for (i = 0; i < totalSets; i++) begin
            set_ind <= i[logSets:1];
            if (control[set_ind][addr.index].valid == 1) begin
                if (control[set_ind][addr.index].tag == addr.tag) begin
                    match_ind <= i;
                    break;
                end
            end
            else begin
                lastInvalid <= i;
            end
        end

        if (match_ind == totalSets) begin
            // Cache MISS
            writeBlockToMem <= 0;
            if (lastInvalid == totalSets) begin
                // Allocate a new Cache Block entry
                // No free cache block available. So need to replace with existing block.
                // TODO: Can use least recently used algorithm to find the entry to be evicted
                // For now we evict the first valid entry
                set_ind <= 0;

                if (control[set_ind][addr.index].dirty == 1) begin
                    // As the data is dirty, we need to evict write back it to memory
                    writeBlockToMem <= 1;
                    writeBlockAddr <= {control[set_ind][addr.index].tag, addr.index, {logWidth{1'b0}}};
                end
            end
            else begin
                // Free cache block entry found
                set_ind <= lastInvalid[logSets:1];
            end

            if (writeBlockToMem) begin
                // Read the dirty cache block to be written to be memory
                cache_readAddr <= {set_ind, addr.index};
                cache_writeEnable <= {wordsPerBlock{1'b0}};
                
                request_type <= cache_read_req;
                 
            end else begin
                if (dCoreCacheBus.reqtag[0] == dCoreCacheBus.READ) begin
                    dCacheArbiterBus.req <= dCoreCacheBus.req;
                    dCacheArbiterBus.reqtag <= dCoreCacheBus.reqtag;
                    dCacheArbiterBus.reqcyc <= 1;
                    request_type <= mem_read_req;

                end else begin
                    // Setup new cache block entry
                    control[set_ind][addr.index].tag <= addr.tag;
                    control[set_ind][addr.index].valid <= 1;
                    control[set_ind][addr.index].dirty <= 1;

                    // Write data directly to Cache (Write-back policy)
                    cache_writeData <= dCoreCacheBus.reqdata;
                    cache_writeAddr <= {set_ind, addr.index};
                    cache_writeEnable <= {wordsPerBlock{1'b1}};

                    dCoreCacheBus.resptag <= dCoreCacheBus.reqtag;
                    dCoreCacheBus.respcyc <= 1;
                    request_type <= cache_write_req;
                end
            end
        end
        else begin
            // CACHE HIT
            set_ind <= match_ind[logSets:1];
            cache_readAddr <= {set_ind, addr.index};
            cache_writeEnable <= {wordsPerBlock{1'b0}};
            
            request_type <= cache_read_req;
        end
    end else if (request_type == mem_read_req) begin
        if (dCacheArbiterBus.reqack == 1) 
            dCacheArbiterBus.reqcyc <= 0;

        dCoreCacheBus.reqack <= 0;

        if (dCacheArbiterBus.respcyc == 1) begin

            // Send back data to Core
            dCoreCacheBus.resp <= dCacheArbiterBus.resp;
            dCoreCacheBus.resptag <= dCacheArbiterBus.resptag;
            dCoreCacheBus.respcyc <= 1;

            // Also setup new cache block entry and write new block to cache
            control[set_ind][addr.index].tag <= addr.tag;
            control[set_ind][addr.index].valid <= 1;
            control[set_ind][addr.index].dirty <= 0;

            cache_writeData <= dCacheArbiterBus.resp;
            cache_writeAddr <= {set_ind, addr.index};
            cache_writeEnable <= {wordsPerBlock{1'b1}};

            request_type <= cache_write_req;
        end

    end else if (request_type == mem_write_req) begin
        assert(!writeBlockToMem) else $fatal;

        if (dCacheArbiterBus.reqack == 1) 
            dCacheArbiterBus.reqcyc <= 0;

        dCoreCacheBus.reqack <= 0;

        if (dCacheArbiterBus.respcyc == 1) begin
        
            if (dCoreCacheBus.reqtag[0] == dCoreCacheBus.READ) begin
                dCacheArbiterBus.req <= dCoreCacheBus.req;
                dCacheArbiterBus.reqtag <= dCoreCacheBus.reqtag;
                dCacheArbiterBus.reqcyc <= 1;
                request_type <= mem_read_req;

            end else begin
                // Setup new cache block entry
                control[set_ind][addr.index].tag <= addr.tag;
                control[set_ind][addr.index].valid <= 1;
                control[set_ind][addr.index].dirty <= 1;

                // Write data directly to Cache (Write-back policy)
                cache_writeData <= dCoreCacheBus.reqdata;
                cache_writeAddr <= {set_ind, addr.index};
                cache_writeEnable <= {wordsPerBlock{1'b1}};

                dCoreCacheBus.resptag <= dCoreCacheBus.reqtag;
                dCoreCacheBus.respcyc <= 1;
                request_type <= cache_write_req;
            end
        end
    end else if (request_type == cache_read_req) begin
        dCoreCacheBus.reqack <= 0;

        if (delay_counter >= delay) begin

            if (writeBlockToMem) begin
                // Write the dirty cache block to the memory
                dCacheArbiterBus.req <= writeBlockAddr & ~63;
                dCacheArbiterBus.reqdata <= cache_readData;
                dCacheArbiterBus.reqtag <= {dCoreCacheBus.WRITE, dCoreCacheBus.MEMORY, 8'b0};
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
            delay_counter++;
        end

    end else if (request_type == cache_write_req) begin
        dCoreCacheBus.reqack <= 0;

        if (delay_counter >= delay) begin
            // Data already sent to dCoreCacheBus
            request_type <= no_request;
            delay_counter <= 0;
        end else begin
            delay_counter++;
        end
    end
end

endmodule

