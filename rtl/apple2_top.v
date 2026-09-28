//
// Apple II+ toplevel abstract
//
// Copyright (c) 2014 W. Soltys <wsoltys@gmail.com>
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

module apple2_top(
    CLK_14M,
    CLK_50M,
    reset_cold,
    reset_warm,
    soft_reset,
    cpu_type,
    CPU_WAIT,
    cpu_stall,
    ss_addr,
    ss_wdata,
    ss_wren,
    ss_rdata,
    machine_ce,
    cpu_frozen,
    ram_we,
    ram_di,
    ram_do,
    ram_addr,
    ram_aux,
    ioctl_addr,
    ioctl_data,
    ioctl_index,
    ioctl_download,
    ioctl_wr,
    ioctl_wait,
    hsync,
    vsync,
    hblank,
    vblank,
    r,
    g,
    b,
    SCREEN_MODE,
    TEXT_COLOR,
    video_switch,
    palette_switch,
    COLOR_PALETTE,
    NTSC_VERTICAL_COMB,
    use_composite,
    comp_preset,
    comp_hfix,
    comp_hue_adj,
    PALMODE,
    ROMSWITCH,
    PS2_Key,
    virtual_keyboard_active,
    virtual_keyboard_event,
    virtual_keyboard_pressed,
    virtual_keyboard_code,
    virtual_control,
    virtual_open_apple,
    virtual_closed_apple,
    joy,
    joy_an,
    JOY_TO_KEY_EN,
    // WOZ SD block interface (one hps_io channel per drive)
    SD_LBA0,
    SD_RD0,
    SD_WR0,
    SD_ACK0,
    SD_BUFF_DIN0,
    SD_LBA1,
    SD_RD1,
    SD_WR1,
    SD_ACK1,
    SD_BUFF_DIN1,
    SD_BUFF_ADDR,
    SD_BUFF_DOUT,
    SD_BUFF_WR,
    IMG_MOUNTED0,
    IMG_MOUNTED1,
    IMG_READONLY,
    IMG_SIZE,
    D1_ACTIVE,
    D2_ACTIVE,
    D1_MOTOR_ON,
    D2_MOTOR_ON,
    D1_IO_ACTIVE,
    D2_IO_ACTIVE,
    D1_STEP_ACTIVE,
    D2_STEP_ACTIVE,
    D1_TRACK_ZERO_STEP,
    D2_TRACK_ZERO_STEP,
    D1_WP,
    D2_WP,
    DISK_ACT,
    DISK_READY,
    HDD_SECTOR,
    HDD_READ,
    HDD_WRITE,
    HDD_MOUNTED,
    HDD_PROTECT,
    HDD_RAM_ADDR,
    HDD_RAM_DI,
    HDD_RAM_DO,
    HDD_RAM_WE,
    AUDIO_L,
    AUDIO_R,
    TAPE_IN,
    UART_TXD,
    UART_RXD,
    UART_RTS,
    UART_CTS,
    UART_DTR,
    UART_DSR,
    RTC,
    mouse_strobe,
    mouse_x,
    mouse_y,
    mouse_button,
    mouse_4_inslot,
    mouse_5_inslot,
    mb_4_inslot,
    mb_5_inslot,
    saturn_5_inslot,
    softcard_4_inslot
);
    input         CLK_14M;
    input         CLK_50M;
    input         reset_cold;
    input         reset_warm;
    output        soft_reset;
    input         cpu_type;
    input         CPU_WAIT;
    input         cpu_stall; // 1: hold the CPU in place (OSD pause)

    input  [9:0]  ss_addr;
    input  [63:0] ss_wdata;
    input         ss_wren;
    output [63:0] ss_rdata;
    input         machine_ce;
    output        cpu_frozen;

    // main RAM
    output        ram_we;
    output [7:0]  ram_di;
    input [15:0]  ram_do;
    output [17:0] ram_addr;
    output        ram_aux;

    // load replacement rom files
    input  [24:0] ioctl_addr;
    input  [7:0]  ioctl_data;
    input  [7:0]  ioctl_index;
    input         ioctl_download;
    input         ioctl_wr;
    output        ioctl_wait;

    // video output
    output        hsync;
    output        vsync;
    output        hblank;
    output        vblank;
    output [7:0]  r;
    output [7:0]  g;
    output [7:0]  b;
    input  [1:0]  SCREEN_MODE;		// 00: Color, 01: B&W, 10: Green, 11: Amber
    input         TEXT_COLOR;		// 1 = color processing for text lines in mixed modes
    output        video_switch;
    output        palette_switch;
    input  [1:0]  COLOR_PALETTE;	// 00: Original (//e NTSC), 01: //gs, 02: AppleWin, 03: //c PAL
    input         NTSC_VERTICAL_COMB;
    // Composite video switch (see rtl/video/video_pipeline.sv).
    //   use_composite: "Color sharpness" RGB/Composite (Apple-II_woz status[4]).
    //   comp_preset:   0=Calibrated 1=Eyeballed 2=Punchy 3=Muted (status[2:1]).
    //   comp_hfix:     A/B composite right-edge fix (0=current hshift=9,
    //                  1=trimmed hshift=0). Composite path only.
    input         use_composite;
    input  [1:0]  comp_preset;
    input         comp_hfix;
    input  [4:0]  comp_hue_adj;
    input         PALMODE;		// PAL/NTSC selection
    input         ROMSWITCH;

    input  [10:0] PS2_Key;
    input         virtual_keyboard_active;
    input         virtual_keyboard_event;
    input         virtual_keyboard_pressed;
    input  [6:0]  virtual_keyboard_code;
    input         virtual_control;
    input         virtual_open_apple;
    input         virtual_closed_apple;
    input  [15:0] joy;
    input  [15:0] joy_an;
    input         JOY_TO_KEY_EN;

    // WOZ disk control: SD block interface, one hps_io channel per drive
    output [31:0] SD_LBA0;
    output        SD_RD0;
    output        SD_WR0;
    input         SD_ACK0;
    output [7:0]  SD_BUFF_DIN0;
    output [31:0] SD_LBA1;
    output        SD_RD1;
    output        SD_WR1;
    input         SD_ACK1;
    output [7:0]  SD_BUFF_DIN1;
    input  [8:0]  SD_BUFF_ADDR;
    input  [7:0]  SD_BUFF_DOUT;
    input         SD_BUFF_WR;
    input         IMG_MOUNTED0;
    input         IMG_MOUNTED1;
    input         IMG_READONLY;
    input  [63:0] IMG_SIZE;

    output        D1_ACTIVE;	// Disk 1 motor on
    output        D2_ACTIVE;	// Disk 2 motor on
    output        D1_MOTOR_ON;
    output        D2_MOTOR_ON;
    output        D1_IO_ACTIVE;
    output        D2_IO_ACTIVE;
    output        D1_STEP_ACTIVE;
    output        D2_STEP_ACTIVE;
    output        D1_TRACK_ZERO_STEP;
    output        D2_TRACK_ZERO_STEP;
    input         D1_WP;
    input         D2_WP;

    output        DISK_ACT;
    input  [1:0]  DISK_READY;	// unused in WOZ mode (no track buffer)

    // The WOZ card exposes only D1/D2_ACTIVE (motor incl. 1 s holdover).
    // The fine-grained Disk II drive signals do not exist on the flux
    // drives and are tied off (the WOZ wrapper does not use them).
    assign D1_MOTOR_ON        = 1'b0;
    assign D2_MOTOR_ON        = 1'b0;
    assign D1_IO_ACTIVE       = 1'b0;
    assign D2_IO_ACTIVE       = 1'b0;
    assign D1_STEP_ACTIVE     = 1'b0;
    assign D2_STEP_ACTIVE     = 1'b0;
    assign D1_TRACK_ZERO_STEP = 1'b0;
    assign D2_TRACK_ZERO_STEP = 1'b0;

    // HDD control
    output [15:0] HDD_SECTOR;
    output        HDD_READ;
    output        HDD_WRITE;
    input         HDD_MOUNTED;
    input         HDD_PROTECT;
    input  [8:0]  HDD_RAM_ADDR;
    input  [7:0]  HDD_RAM_DI;
    output [7:0]  HDD_RAM_DO;
    input         HDD_RAM_WE;

    output [9:0]  AUDIO_L;
    output [9:0]  AUDIO_R;
    input         TAPE_IN;

    output        UART_TXD;
    input         UART_RXD;
    output        UART_RTS;
    input         UART_CTS;
    output        UART_DTR;
    input         UART_DSR;
    input  [64:0] RTC;

    input         mouse_strobe;
    input  [8:0]  mouse_x;
    input  [8:0]  mouse_y;
    input         mouse_button;

    // slot status
    input         mouse_4_inslot;
    input         mouse_5_inslot;
    input         mb_4_inslot;
    input         mb_5_inslot;
    input         saturn_5_inslot;
    input         softcard_4_inslot; // Microsoft Z80 Softcard (slot 4)

    wire          CLK_2M;
    reg           CLK_2M_D;
    wire          PHASE_ZERO;
    wire          PHASE_ZERO_R;
    wire          PHASE_ZERO_F;
    wire [7:0]    IO_SELECT;
    wire [7:0]    DEVICE_SELECT;
    wire          IO_STROBE;
    wire [15:0]   ADDR;
    wire [7:0]    D;
    wire [7:0]    PD;
    wire [7:0]    DISK_DO;
    wire [7:0]    HDD_DO;
    wire [7:0]    PSG_4_DO;
    wire [7:0]    PSG_5_DO;
    wire [7:0]    MOUSE_4_DO;
    wire [7:0]    MOUSE_5_DO;
    wire [7:0]    CLOCK_DO;
    wire [7:0]    SSC_DO;
    wire          SSC_ROM_EN;
    wire          cpu_we;
    wire          psg_4_irq_n;
    wire          psg_4_nmi_n;
    wire          psg_4_oe;
    wire          psg_5_irq_n;
    wire          psg_5_nmi_n;
    wire          psg_5_oe;
    wire          mouse_4_irq_n;
    wire          mouse_5_irq_n;
    wire          MOUSE_4_OE;
    wire          MOUSE_5_OE;
    wire          CLOCK_OE;
    wire          ssc_irq_n;

    wire          we_ram;
    wire          VIDEO;
    wire          HBL;
    wire          VBL;
    wire          COLOR_LINE;
    wire          COLOR_LINE_CONTROL;
    wire          RUN_FILL_OK;
    wire          TEXT_MODE;

    wire [7:0]    GAMEPORT;

    wire [7:0]    K;
    wire          read_key;
    wire          akd;
    wire          open_apple;
    wire          closed_apple;

    reg [22:0]    flash_clk;
    reg           power_on_reset;
    reg           reset;

    wire [17:0]   a_ram;

    // ------------------------------------------------------------------
    // Microsoft Z80 Softcard (slot 4)
    //
    // Adapted from the apple2efpga MiST port, itself derived from
    // system.v (a2e128 core) by Jesus Arias.
    //
    // The 6502/65C02 lives inside the apple2 core, so the Z80 cannot be
    // The 6502 is frozen via CPU_WAIT and the Z80 drives the core's CPU
    // bus (Z80_EN), so address decoding, I/O, ROM and the language card
    // work exactly as for the 6502. Video phases pass through
    // untouched.
    // ------------------------------------------------------------------
    wire          z80_mreq_n, z80_rd_n, z80_wr_n, z80_rfsh_n;
    wire [15:0]   z80_A;
    wire [7:0]    z80_DO;
    reg  [3:0]    z80_ham;
    wire [15:0]   z80_addr_x = {z80_ham, z80_A[11:0]};
    wire          z80_mem_we = ~z80_wr_n & ~z80_mreq_n & z80_rfsh_n;
    reg           z80_vid_cen = 1'b0;
    reg  [2:0]    z80_vid_cnt = 3'd0;
    reg           zsel = 1'b0;
    reg  [1:0]    zsel_guard = 2'd0;
    wire [7:0]    z80_DI;

    wire [9:0]    psg_4_audio_l;
    wire [9:0]    psg_4_audio_r;
    wire [9:0]    psg_5_audio_l;
    wire [9:0]    psg_5_audio_r;
    wire [9:0]    audio;
    wire [63:0]   core_ss_rdata;

    // box-average the $C030 speaker bit at 14.318 MHz into
    // ~48 kHz samples (298 clocks = 20.8 us) so fast toggles average out
    // instead of aliasing from point sampling. Duty maps to 0..512 (half-
    // scale, 4x the old 0..128 level); the framework DC blocker centers it.
    wire        spk_bit;
    reg  [8:0]  spk_cnt = 9'd0;
    reg  [8:0]  spk_sum = 9'd0;
    reg  [9:0]  spk_avg = 10'd0;
    wire [8:0]  spk_sum_now = spk_sum + {8'b0, spk_bit};
    wire [17:0] spk_prod = {spk_sum_now, 9'b0};      // *512, max 152576 < 2^18
    wire [17:0] spk_div  = spk_prod / 18'd298;        // max 512

    reg           joyx;
    reg           joyy;
    wire          pdl_strobe;

    // In the Apple ][, this was a 555 timer
    always @(posedge CLK_14M)
    begin: power_on
        if (ss_wren && (ss_addr == 10'd8))
        begin
            flash_clk      <= ss_wdata[22:0];
            power_on_reset <= ss_wdata[23];
            reset          <= ss_wdata[24];
        end
        else if (machine_ce)
        begin
            reset <= reset_warm | power_on_reset;

            if (reset_cold == 1'b1 || soft_reset == 1'b1)
            begin
                power_on_reset <= 1'b1;
                flash_clk      <= {23{1'b0}};
            end
            else
            begin
                if (flash_clk[22] == 1'b1)
                    power_on_reset <= 1'b0;

                flash_clk <= flash_clk + 23'd1;
            end
        end
    end

    // Paddle buttons
    // GAMEPORT input bits:
    //  7    6    5    4    3   2   1    0
    // pdl3 pdl2 pdl1 pdl0 pb3 pb2 pb1 casette
    assign GAMEPORT = {2'b00, joyy, joyx, 1'b0,
               joy[5] | closed_apple, joy[4] | open_apple, TAPE_IN};

    always @(posedge CLK_14M) begin : P1
    reg signed [31:0] cx = 0, cy = 0;

    CLK_2M_D <= CLK_2M;
    if (CLK_2M_D == 1'b0 && CLK_2M == 1'b1) begin
      if (cx > 0) begin
        cx = cx - 1;
        joyx <= 1'b1;
      end
      else begin
        joyx <= 1'b0;
      end
      if (cy > 0) begin
        cy = cy - 1;
        joyy <= 1'b1;
      end
      else begin
        joyy <= 1'b0;
      end
      if (pdl_strobe == 1'b1) begin
        cx = 2800 + (22 * ($signed(joy_an[15:8])));
        cy = 2800 + (22 * ($signed(joy_an[7:0])));
        // max 5650
        if (cx < 0) begin
          cx = 0;
        end
        else if (cx >= 5590) begin
          cx = 5650;
        end
        if (cy < 0) begin
          cy = 0;
        end
        else if (cy >= 5590) begin
          cy = 5650;
        end
      end
    end
  end

    assign COLOR_LINE_CONTROL = (COLOR_LINE | (TEXT_COLOR & ~TEXT_MODE)) & (~(SCREEN_MODE[1] | SCREEN_MODE[0]));		// Color or B&W mode

    // Simulate power up on cold reset to go to the disk boot routine
    assign ram_we = (reset_cold == 1'b0) ? we_ram : 1'b1;
    assign ram_addr = (reset_cold == 1'b0) ? a_ram : 18'h03F4;		// 1012; $3F4
    assign ram_di = (reset_cold == 1'b0) ? D : 8'b00000000;

    assign PD = (psg_4_oe == 1'b1) ? PSG_4_DO :
                (psg_5_oe == 1'b1) ? PSG_5_DO :
                (MOUSE_4_OE == 1'b1) ? MOUSE_4_DO :
                (MOUSE_5_OE == 1'b1) ? MOUSE_5_DO :
                (CLOCK_OE == 1'b1) ? CLOCK_DO :
                (IO_SELECT[7] == 1'b1 | DEVICE_SELECT[7] == 1'b1) ? HDD_DO :
                (IO_SELECT[2] == 1'b1 | DEVICE_SELECT[2] == 1'b1 | SSC_ROM_EN == 1'b1) ? SSC_DO :
                DISK_DO;

    // 60 Hz IRQ (level_2/level_2b pattern): one short pulse per VBL
    // rising edge, in the 14 MHz domain.  DEAD as of 2026-09-10:
    // irq_60hz_pulse no longer drives IRQ_n - the VBL-locked pulse
    // corrupted video (part of the screen missing; hardware-verified
    // 2026-09-10; see the IRQ_n port comment below).  It was added
    // 2026-09-09 as a stand-in for the machine 60 Hz heartbeat to fix
    // a DOS 3.3 boot hang - a red herring: hardware retest 2026-09-10
    // confirmed DOS 3.3 .woz boots fine without it (the original hang
    // was a disk-transport bug fixed in the woz01->woz04 iterations).
    // Kept for reference; trimmed in synthesis.
    reg  [4:0] irq_60hz_cnt;
    reg        vbl_irq_d;
    wire       irq_60hz_pulse = (irq_60hz_cnt != 5'd0);
    always @(posedge CLK_14M) begin
        vbl_irq_d <= VBL;
        if (VBL && !vbl_irq_d)
            irq_60hz_cnt <= 5'd16;
        else if (irq_60hz_cnt != 5'd0)
            irq_60hz_cnt <= irq_60hz_cnt - 5'd1;
    end

    apple2 core(
        .CLK_14M(CLK_14M),
        .CLK_2M(CLK_2M),
        .PALMODE(PALMODE),
        .ROMSWITCH(ROMSWITCH),
        .CPU_WAIT(CPU_WAIT | zsel),   // freeze the 6502 while the Z80 runs
        .PHASE_ZERO(PHASE_ZERO),
        .PHASE_ZERO_R(PHASE_ZERO_R),
        .PHASE_ZERO_F(PHASE_ZERO_F),
        .FLASH_CLK(flash_clk[22]),
        .reset(reset),
        .cpu(cpu_type),
        .STALL(cpu_stall),
        .ADDR(ADDR),
        .ram_addr(a_ram),
        .D(D),
        .ram_do(ram_do),
        .aux(ram_aux),
        .PD(PD),
        .CPU_WE(cpu_we),
        .IRQ_n(psg_4_irq_n & psg_5_irq_n & ssc_irq_n & mouse_4_irq_n & mouse_5_irq_n),  // 60Hz pulse REMOVED (2026-09-10, hardware-verified): the VBL-locked pulse corrupted the video (part of screen missing). Was "... & ~irq_60hz_pulse".
        .NMI_n(psg_4_nmi_n & psg_5_nmi_n),
        .ram_we(we_ram),
        .VIDEO(VIDEO),
        .COLOR_LINE(COLOR_LINE),
        .RUN_FILL_OK(RUN_FILL_OK),
        .TEXT_MODE(TEXT_MODE),
        .HBL(HBL),
        .VBL(VBL),
        .K(K),
        .READ_KEY(read_key),
        .AKD(akd),
        .AN(),
        .GAMEPORT(GAMEPORT),
        .PDL_STROBE(pdl_strobe),
        .STB(),
        .IO_SELECT(IO_SELECT),
        .DEVICE_SELECT(DEVICE_SELECT),
        .IO_STROBE(IO_STROBE),
        .ioctl_addr(ioctl_addr),
        .ioctl_data(ioctl_data),
        .ioctl_index(ioctl_index),
        .ioctl_download(ioctl_download),
        .ioctl_wr(ioctl_wr),
        .saturn_5_inslot(saturn_5_inslot),
        .speaker(spk_bit),
        .DBG_T65_REGS(),
        .DBG_DI(),
        .DBG_ROM_ADDR(),
        .DBG_ROM_OUT(),
        .ss_addr(ss_addr),
        .ss_wdata(ss_wdata),
        .ss_wren(ss_wren),
        .ss_rdata(core_ss_rdata),
        .machine_ce(machine_ce),
        .cpu_frozen(cpu_frozen),
        .Z80_EN(zsel),
        .Z80_A(z80_addr_x),
        .Z80_DO(z80_DO),
        .Z80_WE(z80_mem_we),
        .CPU_DI(z80_DI)
    );

    assign ss_rdata = (ss_addr == 10'd8) ?
                      {39'd0, reset, power_on_reset, flash_clk} :
                      (ss_addr == 10'd9) ?
                      {36'd0, spk_avg, spk_sum, spk_cnt} : core_ss_rdata;

    video_pipeline vp(
        .CLK_14M(CLK_14M),
        .VIDEO(VIDEO),
        .HBL(HBL),
        .VBL(VBL),
        // machine_ce low during save/load/OSD-pause: hold the composite
        // pipeline (and its subcarrier/comb state) frozen so the frame
        // stays put and resumes at the same color phase (see the
        // machine_ce note in video_pipeline.sv).
        .machine_ce(machine_ce),
        .COLOR_LINE(COLOR_LINE_CONTROL),
        .SCREEN_MODE(SCREEN_MODE),
        .COLOR_PALETTE(COLOR_PALETTE),
        .RUN_FILL_OK(RUN_FILL_OK),
        .NTSC_VERTICAL_COMB(NTSC_VERTICAL_COMB),
        // for custom palette loader
        .ioctl_addr(ioctl_addr),
        .ioctl_data(ioctl_data),
        .ioctl_index(ioctl_index),
        .ioctl_download(ioctl_download),
        .ioctl_wr(ioctl_wr),
        .ioctl_wait(ioctl_wait),
        .use_composite(use_composite),
        .comp_preset(comp_preset),
        .comp_hfix(comp_hfix),
        .comp_hue_adj(comp_hue_adj),
        .R(r),
        .G(g),
        .B(b),
        .HS(hsync),
        .VS(vsync),
        .HBL_O(hblank),
        .VBL_O(vblank)
    );

`ifdef JOY_TO_KEY
    // Joy-to-key: map the digital joystick to Apple II keystrokes. Sits next
    // to the keyboard (CLK_14M domain) and injects one-shot key presses
    // independently of the OSK virtual path, so PS/2 and the raw joystick are
    // both untouched. The build flag includes the feature and the OSD input
    // controls it at runtime.
    wire        joy_key_press;
    wire [6:0]  joy_key_code;
    joy_to_key joy_to_key(
        .clk(CLK_14M),
        .reset(reset_cold),
        .enable(JOY_TO_KEY_EN),
        .joy(joy),
        // Select is bus bit 7; `joy` is already zeroed by the wrapper while
        // the OSK is up, so shift is naturally 0 then (Select = OSK opacity).
        .shift(joy[7]),
        .ioctl_download(ioctl_download),
        .ioctl_wr(ioctl_wr),
        .ioctl_addr(ioctl_addr),
        .ioctl_data(ioctl_data),
        .ioctl_index(ioctl_index),
        .joy_key_press(joy_key_press),
        .joy_key_code(joy_key_code)
    );
`endif

    keyboard keyboard(
        .PS2_Key(PS2_Key),
        .virtual_active(virtual_keyboard_active),
        .virtual_event(virtual_keyboard_event),
        .virtual_pressed(virtual_keyboard_pressed),
        .virtual_code(virtual_keyboard_code),
        .virtual_control(virtual_control),
        .virtual_open_apple(virtual_open_apple),
        .virtual_closed_apple(virtual_closed_apple),
`ifdef JOY_TO_KEY
        .joy_key_code(joy_key_code),
        .joy_key_press(joy_key_press),
`endif
        .CLK_14M(CLK_14M),
        .reset(reset_cold),	// use reset_cold, not reset so we keep the
                              // keyboard state machine running for key up
                              // events during / after reset
        .reads(read_key),
        .K(K),
        .akd(akd),
        .open_apple(open_apple),
        .closed_apple(closed_apple),
        .soft_reset(soft_reset),
        .video_toggle(video_switch),
        .palette_toggle(palette_switch)
    );

    assign DISK_ACT = ~(D1_ACTIVE | D2_ACTIVE);

    // WOZ Disk II slot controller (rtl/woz/disk_ii_woz.sv): replaces
    // disk_ii + drive_ii x2 + the track buffer bus.  Reads the .woz image
    // over the hps_io SD block interface (one channel per drive); the
    // hps_io streaming protocol is exactly what the WOZ expects, and
    // sd_blk_cnt is left 0 (single-block requests).  IMG_MOUNTED is a
    // LEVEL (the wrapper latches the hps_io mount pulse).  DD_RESET is
    // reset_cold: a cold reset re-seats the drives; a warm reset leaves
    // them spinning (real-machine behavior).
    disk_ii_woz disk(
        .CLK_14M(CLK_14M),
        .RESET(reset),
        .DD_RESET(reset_cold),
        .PHASE_ZERO(PHASE_ZERO),
        .IO_SELECT(IO_SELECT[6]),
        .DEVICE_SELECT(DEVICE_SELECT[6]),
        .WE(cpu_we),
        .A(ADDR),
        .D_IN(D),
        .D_OUT(DISK_DO),
        .D1_ACTIVE(D1_ACTIVE),
        .D2_ACTIVE(D2_ACTIVE),
        .D1_WP(D1_WP),
        .D2_WP(D2_WP),
        .SD_LBA0(SD_LBA0),
        .SD_RD0(SD_RD0),
        .SD_WR0(SD_WR0),
        .SD_ACK0(SD_ACK0),
        .SD_BUFF_DIN0(SD_BUFF_DIN0),
        .SD_LBA1(SD_LBA1),
        .SD_RD1(SD_RD1),
        .SD_WR1(SD_WR1),
        .SD_ACK1(SD_ACK1),
        .SD_BUFF_DIN1(SD_BUFF_DIN1),
        .SD_BUFF_ADDR(SD_BUFF_ADDR),
        .SD_BUFF_DOUT(SD_BUFF_DOUT),
        .SD_BUFF_WR(SD_BUFF_WR),
        .IMG_MOUNTED0(IMG_MOUNTED0),
        .IMG_MOUNTED1(IMG_MOUNTED1),
        .IMG_READONLY(IMG_READONLY),
        .IMG_SIZE(IMG_SIZE)
    );

// HDD presence: the full build and SIM_FAST_HDD keep it; plain SIM_FAST stubs slot 7.
`ifdef SIM_FAST
  `ifdef SIM_FAST_HDD
    `define __HDD_PRESENT
  `endif
`else
  `define __HDD_PRESENT
`endif
`ifdef __HDD_PRESENT
    hdd hdd(
        .CLK_14M(CLK_14M),
        .IO_SELECT(IO_SELECT[7]),
        .DEVICE_SELECT(DEVICE_SELECT[7]),
        .RESET(reset),
        .A(ADDR),
        .RD(~cpu_we),
        .D_IN(D),
        .D_OUT(HDD_DO),
        .sector(HDD_SECTOR),
        .hdd_read(HDD_READ),
        .hdd_write(HDD_WRITE),
        .hdd_mounted(HDD_MOUNTED),
        .hdd_protect(HDD_PROTECT),
        .ram_addr(HDD_RAM_ADDR),
        .ram_di(HDD_RAM_DI),
        .ram_do(HDD_RAM_DO),
        .ram_we(HDD_RAM_WE)
    );
`else
    // SIM_FAST: no HDD - 6502 sees an empty slot 7
    assign HDD_DO     = 8'b0;
    assign HDD_SECTOR = 16'b0;
    assign HDD_READ   = 1'b0;
    assign HDD_WRITE  = 1'b0;
`endif

`ifdef SIM_FAST
    // SIM_FAST: no Mockingboard in slot 4
    assign PSG_4_DO      = 8'b0;
    assign psg_4_oe      = 1'b0;
    assign psg_4_irq_n   = 1'b1;
    assign psg_4_nmi_n   = 1'b1;
    assign psg_4_audio_l = 10'b0;
    assign psg_4_audio_r = 10'b0;
`else
    MOCKINGBOARD mb_4(
        .CLK_14M(CLK_14M),
        .PHASE_ZERO(PHASE_ZERO),
        .PHASE_ZERO_R(PHASE_ZERO_R),
        .PHASE_ZERO_F(PHASE_ZERO_F),
        .I_RESET_L(~reset),
        .I_ENA_H(mb_4_inslot),

        .I_ADDR(ADDR[7:0]),
        .I_DATA(D),
        .O_DATA(PSG_4_DO),
        .I_RW_L(~cpu_we),
        .I_IOSEL_L(~IO_SELECT[4] | ~mb_4_inslot),
        .OE(psg_4_oe),

        .O_IRQ_L(psg_4_irq_n),
        .O_NMI_L(psg_4_nmi_n),
        .O_AUDIO_L(psg_4_audio_l),
        .O_AUDIO_R(psg_4_audio_r)
    );
`endif

`ifdef SIM_FAST
    // SIM_FAST: no Mockingboard in slot 5
    assign PSG_5_DO      = 8'b0;
    assign psg_5_oe      = 1'b0;
    assign psg_5_irq_n   = 1'b1;
    assign psg_5_nmi_n   = 1'b1;
    assign psg_5_audio_l = 10'b0;
    assign psg_5_audio_r = 10'b0;
`else
    MOCKINGBOARD mb_5(
        .CLK_14M(CLK_14M),
        .PHASE_ZERO(PHASE_ZERO),
        .PHASE_ZERO_R(PHASE_ZERO_R),
        .PHASE_ZERO_F(PHASE_ZERO_F),
        .I_RESET_L(~reset),
        .I_ENA_H(mb_5_inslot),

        .I_ADDR(ADDR[7:0]),
        .I_DATA(D),
        .O_DATA(PSG_5_DO),
        .I_RW_L(~cpu_we),
        .I_IOSEL_L(~IO_SELECT[5] | ~mb_5_inslot),
        .OE(psg_5_oe),

        .O_IRQ_L(psg_5_irq_n),
        .O_NMI_L(psg_5_nmi_n),
        .O_AUDIO_L(psg_5_audio_l),
        .O_AUDIO_R(psg_5_audio_r)
    );
`endif

`ifdef SIM_FAST
    // SIM_FAST: no Superserial in slot 2
    assign SSC_DO     = 8'b0;
    assign SSC_ROM_EN = 1'b0;
    assign ssc_irq_n  = 1'b1;
    assign UART_TXD   = 1'b0;
    assign UART_RTS   = 1'b0;
    assign UART_DTR   = 1'b0;
`else
    superserial ssc(
        .CLK_50M(CLK_50M),
        .CLK_14M(CLK_14M),
        .CLK_2M(CLK_2M),
        .PH_2(PHASE_ZERO),
        .IO_SELECT_N(~IO_SELECT[2]),
        .DEVICE_SELECT_N(~DEVICE_SELECT[2]),
        .IO_STROBE_N(~IO_STROBE),
        .ADDRESS(ADDR),
        .RW_N(~cpu_we),
        .RESET(reset),
        .DATA_IN(D),
        .DATA_OUT(SSC_DO),
        .ROM_EN(SSC_ROM_EN),
        .UART_CTS(UART_CTS),
        .UART_RTS(UART_RTS),
        .UART_RXD(UART_RXD),
        .UART_TXD(UART_TXD),
        .UART_DTR(UART_DTR),
        .UART_DSR(UART_DSR),
        .IRQ_N(ssc_irq_n)
    );
`endif

`ifdef SIM_FAST
    // SIM_FAST: no mouse in slot 4
    assign MOUSE_4_DO    = 8'b0;
    assign MOUSE_4_OE    = 1'b0;
    assign mouse_4_irq_n = 1'b1;
`else
    applemouse mouse_4(
        .CLK_14M(CLK_14M),
        .CLK_2M(CLK_2M),
        .PHASE_ZERO(PHASE_ZERO),
        .IO_SELECT(IO_SELECT[4] & mouse_4_inslot),
        .IO_STROBE(IO_STROBE),
        .DEVICE_SELECT(DEVICE_SELECT[4] & mouse_4_inslot),
        .RESET(reset),
        .A(ADDR),
        .RNW(~cpu_we),
        .D_IN(D),
        .D_OUT(MOUSE_4_DO),
        .OE(MOUSE_4_OE),
        .IRQ_N(mouse_4_irq_n),
        .STROBE(mouse_strobe),
        .X(mouse_x),
        .Y(mouse_y),
        .SCALE(2'b00),
        .BUTTON(mouse_button)
    );
`endif

`ifdef SIM_FAST
    // SIM_FAST: no mouse in slot 5
    assign MOUSE_5_DO    = 8'b0;
    assign MOUSE_5_OE    = 1'b0;
    assign mouse_5_irq_n = 1'b1;
`else
    applemouse mouse_5(
        .CLK_14M(CLK_14M),
        .CLK_2M(CLK_2M),
        .PHASE_ZERO(PHASE_ZERO),
        .IO_SELECT(IO_SELECT[5] & mouse_5_inslot),
        .IO_STROBE(IO_STROBE),
        .DEVICE_SELECT(DEVICE_SELECT[5] & mouse_5_inslot),
        .RESET(reset),
        .A(ADDR),
        .RNW(~cpu_we),
        .D_IN(D),
        .D_OUT(MOUSE_5_DO),
        .OE(MOUSE_5_OE),
        .IRQ_N(mouse_5_irq_n),
        .STROBE(mouse_strobe),
        .X(mouse_x),
        .Y(mouse_y),
        .SCALE(2'b00),
        .BUTTON(mouse_button)
    );
`endif

`ifdef SIM_FAST
    // SIM_FAST: no NSC in the slot ROM space
    assign CLOCK_DO = 8'b0;
    assign CLOCK_OE = 1'b0;
`else
    // No Slot Clock (NSC): DS1216E-style software time interface hiding
    // under each slot's ROM page at offsets $00-$07 (replaces the old
    // clock_card; see NSC_PORT_NOTES.md). nsc_ticker supplies BCD time/date
    // (HPS RTC reload + free-running calendar); no_slot_clock (BSD port of
    // jtflanagan/AppleTini's module) implements the 64-write unlock /
    // 64-bit readout protocol on the bus.
    wire        nsc_time_en;
    wire [63:0] nsc_time_bcd;

    nsc_ticker nsc_tkr(
        .clk(CLK_14M),
        .rst(reset),
        .rtc(RTC),
        .time_bcd(nsc_time_bcd),
        .time_en(nsc_time_en)
    );

    // Reachable from any slot 1-6 wide window ($C1xx-$C7xx; $C3xx only when
    // C3ROM is set) or the $C8xx-$CFFF slot-ROM window (IO_STROBE decode).
    // The stock driver probes slots 3,1,2,4-7 then internal, so with the
    // default C3ROM=0 it finds the NSC at $C1xx. The module itself restricts
    // to offsets $00-$07.
    wire nsc_slot_sel = IO_SELECT[6] | IO_SELECT[5] | IO_SELECT[4] |
                        IO_SELECT[3] | IO_SELECT[2] | IO_SELECT[1] |
                        IO_STROBE;

    no_slot_clock nsc(
        .clk(CLK_14M),
        .rst(reset),
        .strobe(PHASE_ZERO_R),
        .addr(ADDR),
        .rw(~cpu_we),
        .slot_sel(nsc_slot_sel),
        .input_time({20'b0, nsc_time_bcd}),
        .input_time_en(nsc_time_en),
        .wr_data(CLOCK_DO),
        .wr_data_en(CLOCK_OE)
    );
`endif

    always @(posedge CLK_14M) begin
        if (ss_wren && (ss_addr == 10'd9)) begin
            spk_cnt <= ss_wdata[8:0];
            spk_sum <= ss_wdata[17:9];
            spk_avg <= ss_wdata[27:18];
        end else if (machine_ce) begin
            if (spk_cnt == 9'd297) begin
                spk_cnt <= 9'd0;
                spk_sum <= 9'd0;
                spk_avg <= spk_div[9:0];
            end else begin
                spk_cnt <= spk_cnt + 9'd1;
                if (spk_bit) spk_sum <= spk_sum + 9'd1;
            end
        end
    end
    // ------------------------------------------------------------------
    // Microsoft Z80 Softcard (slot 4)
    // ------------------------------------------------------------------

    // CPU select flip-flop. system.v toggles on any write to $C4xx:
    //   if ((~cclke)&(ca[15:8]==8'hC4)&we) zsel<=~zsel
    // There, 'ca' is combinational so the condition clears itself as soon as
    // the newly active CPU drives the bus. Here both ADDR and z80_A are
    // registered, so the stale address of the CPU just parked could retrigger
    // the toggle. The guard counter blanks detection for two CPU cycles,
    // giving the incoming CPU time to update its address bus.
    always @(posedge CLK_14M or posedge reset) begin
        if (reset) begin
            zsel <= 1'b0;
            zsel_guard <= 2'd0;
        end else if (!softcard_4_inslot) begin
            zsel <= 1'b0;
            zsel_guard <= 2'd0;
        end else if (machine_ce && PHASE_ZERO_F) begin
            if (zsel_guard != 2'd0)
                zsel_guard <= zsel_guard - 2'd1;
            // Any write to $C4xx (the Z80's $E4xx) hands the bus to the other
            // CPU. ADDR/cpu_we come from whichever CPU drives the core bus.
            else if (ADDR[15:8] == 8'hC4 && cpu_we) begin
                zsel <= ~zsel;
                zsel_guard <= 2'd2;
            end
        end
    end

    // Softcard address translation: the card wires the Z80 address bus to the
    // Apple bus with the top nibble incremented, so CP/M gets contiguous RAM
    // from $0000 and the Apple I/O page lands where the Z80 will not run code.
    //   Z80 $0000-$AFFF -> Apple $1000-$BFFF   (main RAM)
    //   Z80 $B000-$DFFF -> Apple $D000-$FFFF   (language card RAM)
    //   Z80 $E000-$EFFF -> Apple $C000-$CFFF   (I/O and slot ROM)
    //   Z80 $F000-$FFFF -> Apple $0000-$0FFF   (zero page and stack)
    always @* begin
        case (z80_A[15:12])
            4'hB:    z80_ham = 4'hD;
            4'hC:    z80_ham = 4'hE;
            4'hD:    z80_ham = 4'hF;
            4'hE:    z80_ham = 4'hC;
            4'hF:    z80_ham = 4'h0;
            default: z80_ham = z80_A[15:12] + 4'd1;
        endcase
    end

    // The Softcard Z80 ran at 2MHz, twice the Apple bus rate. PHASE_ZERO_F
    // alone gives 1MHz, so add a second clock enable in the middle of the
    // video phase, where the RAM is busy with video and not with the Z80.
    // Internal Z80 operations then run at 2MHz while memory accesses stay at
    // 1MHz -- correct, since there is one CPU RAM slot per bus cycle.
    always @(posedge CLK_14M) begin
        z80_vid_cen <= 1'b0;
        if (PHASE_ZERO_F)
            z80_vid_cnt <= 3'd0;
        else if (!PHASE_ZERO) begin
            if (z80_vid_cnt != 3'd7)
                z80_vid_cnt <= z80_vid_cnt + 3'd1;
            if (z80_vid_cnt == 3'd3)
                z80_vid_cen <= 1'b1;
        end
    end

    // Stall the extra enable on real memory accesses. On a read the RAM data is
    // not there yet; on a write ram_we is gated by PHASE_ZERO=1, so advancing
    // now would drop WR_n before the RAM commits and lose the write.
    wire z80_wait_n = ~(zsel & z80_vid_cen & ~z80_mreq_n & z80_rfsh_n);

    // The core latches CPU read data (CPU_DL) on the PHASE_ZERO_F edge itself,
    // so step the Z80 one clock later -- the same edge the 6502 uses (CPU_EN).
    reg z80_cpu_cen = 1'b0;
    always @(posedge CLK_14M) z80_cpu_cen <= PHASE_ZERO_F;

    // ponytail: Z80 state is not in save states; allow_ss is blocked instead.
    wire z80_cen = (z80_cpu_cen | z80_vid_cen) & zsel & machine_ce & ~cpu_stall;

    T80s #(.Mode(0), .T2Write(1), .IOWait(0)) softcard(
        .RESET_n(~reset),
        .CLK(CLK_14M),
        .CEN(z80_cen),
        .WAIT_n(z80_wait_n),
        .INT_n(1'b1),
        .NMI_n(1'b1),
        .BUSRQ_n(1'b1),
        .M1_n(),
        .MREQ_n(z80_mreq_n),
        .IORQ_n(),
        .RD_n(z80_rd_n),
        .WR_n(z80_wr_n),
        .RFSH_n(z80_rfsh_n),
        .HALT_n(),
        .BUSAK_n(),
        .A(z80_A),
        .DI(z80_DI),
        .DO(z80_DO)
    );

    assign audio = spk_avg;
    // 3x 10-bit sum needs 11 bits (765+765+512=2042); saturate instead of
    // truncating. Single-MB usage is bit-identical to the old wrap.
    wire [10:0] audio_sum_l = psg_4_audio_l + psg_5_audio_l + audio;
    wire [10:0] audio_sum_r = psg_4_audio_r + psg_5_audio_r + audio;
    assign AUDIO_L = audio_sum_l[10] ? 10'h3FF : audio_sum_l[9:0];
    assign AUDIO_R = audio_sum_r[10] ? 10'h3FF : audio_sum_r[9:0];

endmodule
