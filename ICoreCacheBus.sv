/* Bus Interface between Core and Icache */

interface ICoreCacheBus #(DATA_WIDTH = 512, WORDSIZE = 64, TAG_WIDTH = 13) (
    /* verilator lint_off UNDRIVEN */
    /* verilator lint_off UNUSED */
    input reset,
    input clk
);

wire[WORDSIZE-1:0] req;
wire[TAG_WIDTH-1:0] reqtag;
wire[DATA_WIDTH-1:0] resp;
wire[TAG_WIDTH-1:0] resptag;
wire reqcyc;
wire respcyc;
wire reqack;
wire respack;

parameter
    READ    /* verilator public */ = 1'b1,
    WRITE   /* verilator public */ = 1'b0,
    MEMORY  /* verilator public */ = 4'b0001,
    MMIO    /* verilator public */ = 4'b0011,
    PORT    /* verilator public */ = 4'b0100,
    IRQ	    /* verilator public */ = 4'b1110;

modport CachePorts (
    input reset,
    input clk,
    input req,
    input reqtag,
    output resp,
    output resptag,
    input reqcyc,
    output respcyc,
    output reqack,
    input respack
);

modport CorePorts (
    input reset,
    input clk,
    output req,
    output reqtag,
    input resp,
    input resptag,
    output reqcyc,
    input respcyc,
    input reqack,
    output respack
);

endinterface
