`timescale 1ns / 1ps

module woz_bram #(
    parameter width_a = 8,
    parameter widthad_a = 10,
    parameter init_file= ""
) (
    // Port A
    input   wire                clock_a,
    input   wire                wren_a,
    input   wire    [widthad_a-1:0]  address_a,
    input   wire    [width_a-1:0]  data_a,
    output  reg     [width_a-1:0]  q_a,

    // Port B
    input   wire                clock_b,
    input   wire                wren_b,
    input   wire    [widthad_a-1:0]  address_b,
    input   wire    [width_a-1:0]  data_b,
    output  wire    [width_a-1:0]  q_b
);

    initial begin
        $display("Loading rom.");
        $display(init_file);
        if (init_file>0)
        	$readmemh(init_file, mem);
    end


// Shared memory
reg [width_a-1:0] mem [(2**widthad_a)-1:0];

// Port A - Registered (standard BRAM behavior)
always @(posedge clock_a) begin
    if(wren_a) begin
        mem[address_a] <= data_a;
        q_a      <= data_a;
`ifdef DEBUG_VERBOSE
        if (widthad_a == 17 && address_a == 17'h10F3A)
            $display("BRAM_WATCHPOINT: write [%05h] <= %02h (curcyl[0])", address_a, data_a);
`endif
    end else begin
        q_a      <= mem[address_a];
    end
end

// Port B - Registered read (standard FPGA BRAM behavior with 1-cycle latency)
// Address is registered, data appears on the next clock edge.
reg [width_a-1:0] q_b_reg;
always @(posedge clock_b) begin
    if(wren_b) begin
        mem[address_b] <= data_b;
        q_b_reg <= data_b;
    end else begin
        q_b_reg <= mem[address_b];
    end
end
assign q_b = q_b_reg;

endmodule
