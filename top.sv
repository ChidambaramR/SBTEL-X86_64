module top #(DATA_WIDTH = 64, TAG_WIDTH = 13) (
	input[63:0] entry
,	input reset
,	input clk
,	output[DATA_WIDTH-1:0] req
,	output[TAG_WIDTH-1:0] reqtag
,	input[DATA_WIDTH-1:0] resp
,	input[TAG_WIDTH-1:0] resptag
,	output reqcyc
,	input respcyc
,	input reqack
,	output respack
);
	/* verilator lint_off UNDRIVEN */
	/* verilator lint_off UNUSED */
	Sysbus #(DATA_WIDTH, TAG_WIDTH) uncore_bus(reset, clk);
	SysbusBottom #(DATA_WIDTH, TAG_WIDTH) dummy(uncore_bus.Bottom, req, reqtag, resp, resptag, reqcyc, respcyc, reqack, respack);

        ICoreCacheBus iCoreCacheBus(reset, clk);
        DCoreCacheBus dCoreCacheBus(reset, clk);
        CacheArbiterBus iCacheArbiterBus(reset, clk);
        CacheArbiterBus dCacheArbiterBus(reset, clk);

	Core core(entry, iCoreCacheBus.CorePorts, dCoreCacheBus.CorePorts);

        mod_icache icache(iCoreCacheBus.CachePorts, iCacheArbiterBus.CachePorts);
        mod_dcache dcache(dCoreCacheBus.CachePorts, dCacheArbiterBus.CachePorts);
        mod_arbiter arbiter(uncore_bus.Top, iCacheArbiterBus.ArbiterPorts, dCacheArbiterBus.ArbiterPorts);

	/* verilator lint_on UNUSED */
	/* verilator lint_on UNDRIVEN */

	initial begin
		$display("Initializing top, entry point = %x", entry);
	end
endmodule
