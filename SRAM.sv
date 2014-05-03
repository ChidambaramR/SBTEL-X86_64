module mod_cache (
    input               clk,
    input               isReadData,
    input  [addrsize-1:0] rwAddr,
    input  [   width-1:0] writeData,
    input  [width/wordsize-1:0] writeEnable,
    output [   width-1:0] readData
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
          ports    = 1,
          delay    = (logDepth-8>0?logDepth-8:1)*(ports>1?(ports>2?(ports>3?100:20):14):10)/10-1;

initial begin
    $display("Initializing %0dKB (%0dx%0d) memory, delay = %0d", (width+7)/8*(1<<logDepth)/1024, width, (1<<logDepth), delay);
    assert(ports == 1) else $fatal("multi-ported SRAM not supported");
end

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

cntr_struct      control [totalSets-1:0][(1<<logDepthPerSet)-1:0];
logic[width-1:0] mem     [totalSets-1:0][(1<<logDepthPerSet)-1:0];

addr_struct addr;
logic[width-1:0] tempread;
logic[logSets-1:0] set_ind;
logic[logSets:0] match_ind;
logic[logSets:0] lastInvalid;
logic[width-1:0] readpipe[delay-1];
logic[logSets:0] ii;
integer i;

always @ (posedge clk) begin
    addr <= rwAddr;

    // Lookup valid index entry with matching tag in cache
    match_ind <= totalSets;
    lastInvalid <= totalSets;
    for (ii = 0; ii < totalSets; ii++) begin
        set_ind <= ii[logSets:1];
        if (control[set_ind][addr.index].valid == 1) begin
            if (control[set_ind][addr.index].tag == addr.tag) begin
                match_ind <= ii;
            end
        end
        else begin
            lastInvalid <= ii;
        end
    end

    if (match_ind == totalSets) begin
        // Cache MISS

        // TODO: Get data from DRAM memory
        tempread <= 0;

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
            set_ind <= lastInvalid[logSets:1];
        end

        // Setup new cache block entry
        control[set_ind][addr.index].tag <= addr.tag;
        control[set_ind][addr.index].dirty <= 0;
        control[set_ind][addr.index].valid <= 1;

        mem[set_ind][addr.index] <= tempread;
    end
    else begin
        // CACHE HIT
        set_ind = match_ind[logSets:1];
    end

    if (isReadData) begin   // Read Request
    
        // Introduce delay to simulate real time performance of SRAMs
        if (delay > 0)  begin
            readpipe[0] <= mem[set_ind][addr.index];
            for (i=1; i<delay; ++i)
                readpipe[i] <= readpipe[i-1];
            readData <= readpipe[delay-1];
        end
        else begin
            readData <= mem[set_ind][addr.index];
        end
    end
    else begin  // Write Request
        //TODO: Is delay required for write request?

        for (i = 0; i < width/wordsize; i = i+1) begin
            // Write only write-enabled bytes and mark cache entry as dirty
            if (writeEnable[i]) begin
                mem[set_ind][addr.index][i*wordsize+:wordsize] <= writeData[i*wordsize+:wordsize];
                control[set_ind][addr.index].dirty <= 1;
            end
        end
    end
end

endmodule
