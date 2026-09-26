// Temporary lint stubs for VHDL-only entities (not synthesized here).
// Port-accurate so the Verilog wrapper lint can check connections.

module dpram #(parameter addr_width_g = 8, data_width_g = 8) (
  input  wire [addr_width_g-1:0] address_a,
  input  wire [addr_width_g-1:0] address_b,
  input  wire                    clock_a,
  input  wire                    clock_b,
  input  wire [data_width_g-1:0] data_a,
  input  wire [data_width_g-1:0] data_b,
  input  wire                    enable_a,
  input  wire                    enable_b,
  input  wire                    wren_a,
  input  wire                    wren_b,
  output wire [data_width_g-1:0] q_a,
  output wire [data_width_g-1:0] q_b
);
  assign q_a = {data_width_g{1'b0}};
  assign q_b = {data_width_g{1'b0}};
endmodule

module hdd (
  input  wire        CLK_14M,
  input  wire        IO_SELECT,
  input  wire        DEVICE_SELECT,
  input  wire        RESET,
  input  wire [15:0] A,
  input  wire        RD,
  input  wire [7:0]  D_IN,
  output wire [7:0]  D_OUT,
  output wire [15:0] sector,
  output wire        hdd_read,
  output wire        hdd_write,
  input  wire        hdd_mounted,
  input  wire        hdd_protect,
  input  wire [8:0]  ram_addr,
  input  wire [7:0]  ram_di,
  output wire [7:0]  ram_do,
  input  wire        ram_we
);
  assign D_OUT = 8'd0;
  assign sector = 16'd0;
  assign hdd_read = 1'b0;
  assign hdd_write = 1'b0;
  assign ram_do = 8'd0;
endmodule

module hdd_rom (
  input  wire [7:0] addr,
  input  wire       clk,
  output wire [7:0] dout
);
  assign dout = 8'd0;
endmodule

module ssc_rom (
  input  wire       clk,
  input  wire [10:0] addr,
  output wire [7:0] data
);
  assign data = 8'd0;
endmodule

// Quartus PLL wrapper: stub for lint only (IP parameters are synthetic).
module pll (
  input  wire  refclk,
  input  wire  rst,
  output wire  outclk_0,
  output wire  outclk_1,
  output wire  locked
);
  assign outclk_0 = refclk;
  assign outclk_1 = refclk;
  assign locked   = 1'b1;
endmodule
