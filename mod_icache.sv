
module mod_icache (
    input                 clk,
    input                 newRequest,
    input  [addrsize-1:0] readAddr,
    output [bitWidth-1:0] readBlock,
    output                response
);

parameter logWidth  = 6,
          byteWidth = (1<<logWidth),            // Cache Block Size = 2^6 = 64 bytes
          bitWidth  = (1<<logwidth)*8,          // Cache Block Bit Size = 64*8 = 512 bits 
          logSets   = 2,
          totalSets = (1<<logSets),             // 2^2 = 4-way set associative cache
          logDepth  = 7,                        // Total Cache Entries = 2^7 = 128 entries
          logDepthPerSet = logDepth - logSets,  // Cache Entries per Set = 128/4 = 32 entries
          wordsize  = 64,
          addrsize  = 64,
          i_offset  = addrsize - 1,
          i_index   = i_offset - logWidth,
          i_tag     = i_index  - logDepthPerSet, 

typedef struct packed {
    logic [i_tag    : 0        ] tag;           //    Tag bit positions = 52:0
    logic [i_index  : i_tag+1  ] index;         //  Index bit positions = 57:53
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

logic isCacheRequest;
logic [logDepth-1:0] cache_readAddr;
logic [logDepth-1:0] cache_writeAddr;
logic [bitWidth/wordsize-1:0] writeEnable;

logic clk_cache,
logic [logDepth-1:0] readAddr_cache;
logic [bitWidth-1:0] readData_cache;
logic [logDepth-1:0] writeAddr_cache;
logic [bitWidth-1:0] writeData_cache;
logic [bitWidth/wordsize-1:0] writeEnable_cache;

initial begin
end

wire new_request = newRequest;

SRAM sram_chip (
        clk_cache, readAddr_cache, readData_cache,
        writeAddr_cache, writeData_cache, writeEnable_cache
    );

always @ (posedge clk) begin
    if (isCacheRequest) begin
        clk_cache           <= clk;
        readAddr_cache      <= cache_readAddr;
        writeAddr_cache     <= cache_writeAddr;
        writeData_cache     <= writeData;
        writeEnable_cache   <= writeEnable;
    end

    if (isPendingMemReq) begin
        // reqcyc = 1
        // if(bus.resp)
        // after fetching set done <= 1
        // TODO: Use sysbus.req to send request
    end
end

always_comb begin

    // Initialize isPendingMemReq=0
    // Unset isPendingMemReq based on bus.resp

    addr = readAddr;

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
        isPendingMemReq = 1;
        // if(done)
        while (!isPendingMemReq);

        // TODO: Get data from DRAM memory
        writeData = 0;

        if (lastInvalid == totalSets) begin
            // Allocate a new Cache Block entry
            // No free cache block available. So need to replace with existing block.
            // TODO: Can use least recently used algorithm to find the entry to be evicted
            // For now we evict the first valid entry
            set_ind = 0;
        end
        else begin
            // Free cache block entry found
            set_ind = lastInvalid[logSets:1];
        end

        // Setup new cache block entry
        control[set_ind][addr.index].tag = addr.tag;
        control[set_ind][addr.index].valid = 1;

        cache_writeAddr = {set_ind, addr.index};
        writeEnable = {logDepth'b1};
        isCacheRequest = 1;
    end
    else begin
        // CACHE HIT
        set_ind = match_ind[logSets:1];
        cache_readAddr = {set_ind, addr.index};
        writeEnable = 0;

        isCacheRequest = 1;
    end
end

endmodule
