/* SRAM Memory Module */

module SRAM #(WORDSIZE = 64, WIDTH = 512, LOGDEPTH = 9) (
    input clk,
    input [LOGDEPTH-1:0] readAddr,
    output[ WIDTH-1:0] readData,
    input [LOGDEPTH-1:0] writeAddr,
    input [ WIDTH-1:0] writeData,
    input [WIDTH/WORDSIZE-1:0] writeEnable
);
parameter ports = 1,
          delay = (LOGDEPTH-8>0?LOGDEPTH-8:1)*(ports>1?(ports>2?(ports>3?100:20):14):10)/10-1;

logic[WIDTH-1:0] mem [(1<<LOGDEPTH)-1:0];

logic[WIDTH-1:0] readpipe[delay-1];

initial begin
    $display("Initializing %0dKB (%0dx%0d) memory, delay = %0d", (WIDTH+7)/8*(1<<LOGDEPTH)/1024, WIDTH, (1<<LOGDEPTH), delay);
    assert(ports == 1) else $fatal("multi-ported SRAM not supported");
end

integer i;

always @ (posedge clk) begin

    if (delay > 0) begin
        readpipe[0] <= mem[readAddr];
        for(i=1; i<delay; ++i)
            readpipe[i] <= readpipe[i-1];
        readData <= readpipe[delay-1];
    end
    else begin
        readData <= mem[readAddr];
    end

    for ( i=0; i<WIDTH/WORDSIZE; i=i+1 ) begin
        if (writeEnable[i]) begin
            mem[writeAddr][i*WORDSIZE+:WORDSIZE] <= writeData[i*WORDSIZE+:WORDSIZE];
        end
    end
end

endmodule

