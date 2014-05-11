module mod_icache #(WORDSIZE = 64, LOGWIDTH = 6, LOGDEPTH = 9, LOGSETS = 2, TAGWIDTH = 13) (
    ICoreCacheBus    iCoreCacheBus,
    CacheArbiterBus iCacheArbiterBus
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
    logic [i_tag    : 0        ] tag;           //    Tag bit positions = 50:0
    logic [i_index  : i_tag+1  ] index;         //  Index bit positions = 57:51
    logic [i_offset : i_index+1] offset;        // Offset bit positions = 63:58
} addr_struct;

typedef struct packed {
    logic valid;
    //logic dirty;
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

logic [logDepth-1:0] cache_readAddr;
logic [bitWidth-1:0] cache_readData;
logic [logDepth-1:0] cache_writeAddr;
logic [bitWidth-1:0] cache_writeData;
logic [wordsPerBlock-1:0] cache_writeEnable;

SRAM #(WORDSIZE, bitWidth, LOGDEPTH) sram_chip (
        iCoreCacheBus.clk, cache_readAddr, cache_readData,
        cache_writeAddr, cache_writeData, cache_writeEnable
    );

initial begin
    $display("Initializing L1 Instruction Cache");
end

always_comb begin
    addr = iCoreCacheBus.req;
end

enum { no_request, new_request, cache_read_req, cache_write_req, memory_request} request_type;

assign iCacheArbiterBus.respack = iCacheArbiterBus.respcyc; // always able to accept response

always @ (posedge iCacheArbiterBus.clk) begin
    if (iCacheArbiterBus.reset) begin
        request_type <= no_request;
        for (i = 0; i < totalSets; i = i+1) begin
            for (j = 0; j < logDepthPerSet; j = j+1) begin
                control[i[logSets:1]][j].valid <= 0;
            end
        end
        cache_writeEnable <= {wordsPerBlock{1'b0}};

    end else if ((request_type == no_request) && (iCoreCacheBus.reqcyc == 1)) begin
        iCoreCacheBus.reqack <= 1;
        iCoreCacheBus.respcyc <= 0;

        // Lookup valid index entry with matching tag in cache
        match_ind <= totalSets;
        lastInvalid <= totalSets;
        for (i = 0; i < totalSets; i++) begin
            if (control[i[logSets:1]][addr.index].valid == 1) begin
                if (control[i[logSets:1]][addr.index].tag == addr.tag) begin
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
        iCoreCacheBus.reqack <= 0;

        if (match_ind == totalSets) begin
            // Cache MISS
            if (lastInvalid == totalSets) begin
                // Allocate a new Cache Block entry
                // No free cache block available. So need to replace with existing block.
                // TODO: Can use least recently used algorithm to find the entry to be evicted
                // For now we evict the first valid entry
                set_ind <= 0;
            end
            else begin
                // Free cache block entry found
                set_ind <= lastInvalid[logSets-1:0];
            end

            iCacheArbiterBus.req <= iCoreCacheBus.req;
            iCacheArbiterBus.reqtag <= iCoreCacheBus.reqtag;
            iCacheArbiterBus.reqcyc <= 1;
            request_type <= memory_request;
        end
        else begin
            // CACHE HIT
            set_ind <= match_ind[logSets-1:0];
            cache_readAddr <= {match_ind[logSets-1:0], addr.index};
            cache_writeEnable <= {wordsPerBlock{1'b0}};
            
            request_type <= cache_read_req;
        end
    end else if (request_type == memory_request) begin
        if (iCacheArbiterBus.reqack == 1) 
            iCacheArbiterBus.reqcyc <= 0;

        if (iCacheArbiterBus.respcyc == 1) begin

            // Send back data to Core
            iCoreCacheBus.resp <= iCacheArbiterBus.resp;
            iCoreCacheBus.resptag <= iCacheArbiterBus.resptag;
            iCoreCacheBus.respcyc <= 1;

        $write("\n icache: %x $$ %x $$ %x $$ %x\n",  iCoreCacheBus.req, addr.tag, addr.index, addr.offset);
            // Also setup new cache block entry and write new block to cache
            control[set_ind][addr.index].tag <= addr.tag;
            control[set_ind][addr.index].valid <= 1;

            cache_writeData <= iCacheArbiterBus.resp;
            cache_writeAddr <= {set_ind, addr.index};
            cache_writeEnable <= {wordsPerBlock{1'b1}};
 
            request_type <= cache_write_req;
        end

    end else if (request_type == cache_read_req) begin
        if (delay_counter >= delay) begin
            // Sent Cache block to iCoreCacheBus
            iCoreCacheBus.resp <= cache_readData;
            iCoreCacheBus.resptag <= iCoreCacheBus.reqtag;
            iCoreCacheBus.respcyc <= 1;
            
            request_type <= no_request;
            delay_counter <= 0;
        end else begin
            delay_counter <= delay_counter + 1;
        end

    end else if (request_type == cache_write_req) begin
    $write("\n icache2: %x $$ %x $$ %x\n\n", cache_writeAddr, cache_writeData, cache_writeEnable);
        iCoreCacheBus.respcyc <= 0;

        if (delay_counter >= delay) begin
            // Data already sent to iCoreCacheBus
            request_type <= no_request;
            delay_counter <= 0;
        end else begin
            delay_counter <= delay_counter + 1;
        end
    end
end

endmodule

