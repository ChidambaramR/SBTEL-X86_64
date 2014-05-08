module mod_cache (
    input                 clk,
    input                 isReadData,
    input  [addrsize-1:0] rwAddr,
    input  [wordsize-1:0] writeWord,
    output [wordsize-1:0] readWord
);

parameter logWidth = 7,                         // Cache Block Size = 2^7 = 128 bytes
          width    = (1<<logwidth),
          logSets  = 2,                         // 2^2 = 4-way set associative cache
          totalSets = (1<<logSets),
          logDepth = 9,                         // Total Cache Entries = 2^9 = 512 entries
          logDepthPerSet = logDepth - logSets,  // Cache Entries per Set = 512/4 = 128 entries
          wordsize = 64,
          addrsize = 64,
          i_offset = addrsize - 1,
          i_index  = i_offset - logWidth,
          i_tag    = i_index  - logDepthPerSet, 

typedef struct packed {
    logic [i_tag    : 0        ] tag;           //    Tag bit positions = 49:0
    logic [i_index  : i_tag+1  ] index;         //  Index bit positions = 56:50
    logic [i_offset : i_index+1] offset;        // Offset bit positions = 63:57
} addr_struct;

typedef struct packed {
    logic valid;
    logic dirty;
    logic [i_tag:0] tag;
} cntr_struct;

cntr_struct control [totalSets-1:0][(1<<logDepthPerSet)-1:0];

addr_struct addr;
logic[width-1:0] writeData;
logic[logSets-1:0] set_ind;
logic[logSets:0] match_ind;
logic[logSets:0] lastInvalid;
logic[logSets:0] i;

logic isCacheHit;
logic cache_readAddr;
logic cache_writeAddr;

logic clk_cache,
logic [logDepth-1:0] readAddr_cache;
logic [width-1:0] readData_cache;
logic [logDepth-1:0] writeAddr_cache;
logic [width-1:0] writeData_cache;
logic [width/wordsize-1:0] writeEnable_cache;

SRAM sram_chip (
        clk_cache, readAddr_cache, readData_cache,
        writeAddr_cache, writeData_cache, writeEnable_cache
    );

always @ (posedge clk) begin
    clk_cache           <= clk;
    readAddr_cache      <= cache_readAddr;
    writeAddr_cache     <= cache_writeAddr;
    writeData_cache     <= writeData;
    writeEnable_cache   <= write
end

always_comb begin
    addr = rwAddr;

    // Lookup valid index entry with matching tag in cache
    match_ind = totalSets;
    lastInvalid = totalSets;
    for (i = 0; i < totalSets; i++) begin
        set_ind = i[logSets:1];
        if (control[set_ind][addr.index].valid == 1) begin
            if (control[set_ind][addr.index].tag == addr.tag) begin
                match_ind = i;
                break;
            end
        end
        else begin
            lastInvalid = i;
        end
    end

    if (match_ind == totalSets) begin
        // Cache MISS
        isCacheHit = 0;

        // TODO: Get data from DRAM memory
        writeData = 0;

        // Allocate a new Cache Block entry
        if (lastInvalid == totalSets) begin
            // No free cache block available. So need to replace with existing block.
            // TODO: Can use least recently used algorithm to find the entry to be evicted
            // For now we evict the first valid entry
            set_ind = 0;

            if (control[set_ind][addr.index].dirty == 1) begin
                // TODO: As the data is dirty, we need to write back it to memory
            end
        end
        else begin
            // Free cache block entry found
            set_ind = lastInvalid[logSets:1];
        end

        // Setup new cache block entry
        control[set_ind][addr.index].tag = addr.tag;
        control[set_ind][addr.index].dirty = 0;
        control[set_ind][addr.index].valid = 1;

        cache_writeAddr = {set_ind, addr.index};
    end
    else begin
        // CACHE HIT
        isCacheHit = 1;

        set_ind = match_ind[logSets:1];

        if (!isReadData)
            cache_writeAddr = {set_ind, addr.index};
    end
    if (isReadData)
        cache_readAddr = {set_ind, addr.index};
    else
        control[set_ind][addr.index].dirty = 1;
end

endmodule
