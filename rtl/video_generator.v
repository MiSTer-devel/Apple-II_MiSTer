`timescale 1ns / 1ps

//-----------------------------------------------------------------------------
//
// Apple II/e Video Generation Logic
//
// György Szombathelyi
//
// Original Apple II+ Video Generation Logic by
// Stephen A. Edwards, sedwards@cs.columbia.edu
//
// This takes data from memory and various mode switches to produce the
// lookup address in the video ROM, and the result is fed to the video shift
// register.
//
// Based on the book Understanding the Apple IIe by Jim Sather
//
//-----------------------------------------------------------------------------

module video_generator(
input wire        CLK_14M,    // 14.31818 MHz master clock
input wire        CLK_7M,
input wire        ALTCHAR,
input wire        ROMSWITCH,
input wire        GR2,
input wire        SEGA,
input wire        SEGB,
input wire        SEGC,
input wire        WNDW_N,
input wire [7:0]  DL,         // Data from RAM
input wire        LDPS_N,

// load different video roms
input wire [24:0] ioctl_addr,
input wire [7:0]  ioctl_data,
input wire        ioctl_wr,

input wire        FLASH_CLK,  // Low-frequency flashing text clock
output wire       VIDEO
);

// IIe signals
wire [11:0] video_rom_addr;
reg  [7:0]  video_rom_out;
reg  [7:0]  video_shiftreg;

wire [12:0] video_rom_input_addr;

  //---------------------------------------------------------------------------
  //
  // Apple II/e Video generator circuit
  //
  // Chapter 8 of Understanding the Apple II by Jim Sather
  //
  //---------------------------------------------------------------------------
  assign video_rom_addr = {GR2,
                           DL[7] | (~GR2 & DL[6] & FLASH_CLK & ~ALTCHAR),
                           DL[6] & (ALTCHAR | GR2 | DL[7]),
                           DL[5:0], SEGC, SEGB, SEGA};

  assign video_rom_input_addr = ioctl_wr ? ioctl_addr[12:0]
                                         : {ROMSWITCH, video_rom_addr};

  // Writable video ROM (spram equivalent; Quartus uses
  // "rtl/roms/video2.mif", the same content is provided here as
  // "rtl/roms/video2.hex"). Synchronous read; on a write the new data
  // appears on the output (spram NEW_DATA behavior).
  reg [7:0] video_rom [0:8191];
  initial $readmemh("rtl/roms/video2.hex", video_rom);

  always @(posedge CLK_14M) begin
    if (ioctl_wr) begin
      video_rom[video_rom_input_addr] <= ioctl_data;
      video_rom_out                   <= ioctl_data;
    end else begin
      video_rom_out <= video_rom[video_rom_input_addr];
    end
  end

  always @(posedge CLK_14M) begin
    if (CLK_7M == 1'b0) begin
      if (LDPS_N == 1'b0) begin
        // load
        if (WNDW_N == 1'b1) begin
          video_shiftreg <= {8{1'b1}};
        end
        else begin
          video_shiftreg <= video_rom_out;
        end
      end
      else begin
        // shift
        video_shiftreg <= {video_shiftreg[0], video_shiftreg[7:1]};
      end
    end
  end

  assign VIDEO = ~video_shiftreg[0];

endmodule
