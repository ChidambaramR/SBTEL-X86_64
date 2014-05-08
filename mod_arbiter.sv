/* Arbiter Module to communicate between DCache/ICache and Memory */

module Arbiter #(WIDTH = 64, TAG_WIDTH = 13) (
    Sysbus bus,
    CacheArbiterBus icache,
    CacheArbiterBus dcache
);

bit IsArbiterBusy;

initial begin
    IsArbiterBusy = 0;
end

always @ (posedge bus.clk) begin
    if (!IsArbiterBusy && icache.reqcyc) begin
        bus.req <= icache.req;
        bus.reqtag <= icache.reqtag;
        icache.reqack <= 1;
        IsArbiterBusy <= 1;
    end
end

endmodule
