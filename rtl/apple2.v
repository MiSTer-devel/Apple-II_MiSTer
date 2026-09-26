//-----------------------------------------------------------------------------
// Top level of an Apple //e
//
// Based on:
// Top level of an Apple ][+
//
// Stephen A. Edwards, sedwards@cs.columbia.edu
//
//-----------------------------------------------------------------------------

module apple2(
    CLK_14M,
    CLK_2M,
    PALMODE,
    ROMSWITCH,
    CPU_WAIT,
    PHASE_ZERO,
    PHASE_ZERO_R,
    PHASE_ZERO_F,
    FLASH_CLK,
    reset,
    cpu,
    STALL,
    ADDR,
    ram_addr,
    D,
    ram_do,
    aux,
    PD,
    CPU_WE,
    IRQ_n,
    NMI_n,
    ram_we,
    VIDEO,
    COLOR_LINE,
    RUN_FILL_OK,
    TEXT_MODE,
    HBL,
    VBL,
    K,
    READ_KEY,
    AKD,
    AN,
    GAMEPORT,
    PDL_STROBE,
    STB,
    IO_SELECT,
    DEVICE_SELECT,
    IO_STROBE,
    ioctl_addr,
    ioctl_data,
    ioctl_index,
    ioctl_download,
    ioctl_wr,
    saturn_5_inslot,
    speaker,
    DBG_T65_REGS,
    DBG_DI,
    DBG_ROM_ADDR,
    DBG_ROM_OUT,
    ss_addr,
    ss_wdata,
    ss_wren,
    ss_rdata,
    machine_ce,
    cpu_frozen,
    Z80_EN,
    Z80_A,
    Z80_DO,
    Z80_WE,
    CPU_DI
);
    input         CLK_14M;		// 14.31818 MHz master clock
    output        CLK_2M;
    input         PALMODE;		// PAL/NTSC selection
    input         ROMSWITCH;
    input         CPU_WAIT;
    output        PHASE_ZERO;
    output        PHASE_ZERO_R;	// next clock is PHI0=1
    output        PHASE_ZERO_F;	// next clock is PHI0=0
    input         FLASH_CLK;		// approx. 2 Hz flashing char clock
    input         reset;
    input         cpu;		// 0 - 6502, 1 - 65C02
    input         STALL;		// 1: hold the CPU in place (OSD pause)
    output [15:0] ADDR;		// CPU address
    output [17:0] ram_addr;		// RAM address
    output [7:0]  D;		// Data to RAM
    input [15:0]  ram_do;		// Data from RAM (lo byte: MAIN RAM, hi byte: AUX RAM)
    output reg    aux;		// Write to MAIN or AUX RAM
    input [7:0]   PD;		// Data to CPU from peripherals
    output        CPU_WE;
    input         IRQ_n;
    input         NMI_n;
    output        ram_we;		// RAM write enable
    output        VIDEO;
    output        COLOR_LINE;
    output        RUN_FILL_OK;
    output        TEXT_MODE;
    output        HBL;
    output        VBL;
    input [7:0]   K;		// Keyboard data
    output reg    READ_KEY;		// Processor has read key
    input         AKD;		// Any key down flag
    output [3:0]  AN;		// Annunciator outputs
    // GAMEPORT input bits:
    //  7    6    5    4    3   2   1    0
    // pdl3 pdl2 pdl1 pdl0 pb3 pb2 pb1 casette
    input [7:0]   GAMEPORT;
    output reg    PDL_STROBE;		// Pulses high when C07x read
    output reg    STB;		// Pulses high when C04x read
    output [7:0]  IO_SELECT;
    output [7:0]  DEVICE_SELECT;
    output reg    IO_STROBE;
    // load different video roms
    input  [24:0] ioctl_addr;
    input  [7:0]  ioctl_data;
    input  [7:0]  ioctl_index;
    input         ioctl_download;
    input         ioctl_wr;
    input         saturn_5_inslot;
    output        speaker;		// One-bit speaker output
    output [63:0] DBG_T65_REGS;	// T65 debug: {PC,S,P,Y,X,A} (harness instrumentation)
    output [7:0]  DBG_DI;		// T65 data input as seen by the CPU (harness instrumentation)
    output [13:0] DBG_ROM_ADDR;    // ROM address bus (harness instrumentation)
    output [7:0]  DBG_ROM_OUT;     // ROM data out (harness instrumentation)
    input  [9:0]  ss_addr;         // selected CPU savestate word address
    input  [63:0] ss_wdata;        // selected CPU savestate write data
    input         ss_wren;         // selected CPU savestate write strobe
    output [63:0] ss_rdata;        // selected CPU savestate read data
    input         machine_ce;      // normal machine state enable
    output        cpu_frozen;      // STALL held at a CPU boundary
    // Z80 Softcard: when Z80_EN is set the Z80 drives the CPU bus in place of
    // the (frozen) 6502, so I/O, ROM, language card and slots decode as usual.
    input         Z80_EN;
    input  [15:0] Z80_A;
    input  [7:0]  Z80_DO;
    input         Z80_WE;
    output [7:0]  CPU_DI;          // data to the CPU (D_IN)

    // Clocks
    wire          CLK_7M;
    wire          Q3;
    wire          RAS_N;
    wire          CAS_N;
    wire          AX;
    reg           PHASE_ZERO_D;
    wire          COLOR_REF;
    wire          CPU_EN;
    wire [63:0]   timing_ss_rdata;
    wire [63:0]   video_ss_rdata;

    // From the timing generator
    wire [15:0]   VIDEO_ADDRESS;
    wire          LDPS_N;
    wire          WNDW_N;
    wire          GR2;
    wire          SEGA;
    wire          SEGB;
    wire          SEGC;

    // Soft switches
    reg [7:0]     soft_switches;
    wire          MIXED_MODE;
    wire          PAGE2;
    wire          HIRES_MODE;
    wire          DHIRES_MODE;

    // ][e auxilary switches
    reg           RAMRD;
    reg           RAMWRT;
    reg           CXROM;
    reg           STORE80;
    reg           C3ROM;
    reg           C8ROM;
    reg           ALTZP;
    reg           ALTCHAR;
    reg           COL80;
    reg           SF_D;

    // CPU signals
    wire [7:0]    D_IN;
    wire [7:0]    D_OUT;
    wire [15:0]   A;
    // nmos6502 (NMOS 6502 core; replaced T65 on 2026-09-04). Source:
    // rtl/cpu/nmos6502/. Same "one bus access per cycle" model as the wdc65c02
    // core below; WDC_MODE=0 selects NMOS 6502 bus/flag behavior.
    wire [15:0]   N6502_A;
    wire [7:0]    N6502_DO;
    wire          N6502_WE;       // active-high write cycle
    // NMOS-specific / SoC outputs, unused on the Apple II (collected into
    // nmos6502_unused_ok below so lint stays quiet)
    wire          N6502_SYNC;
    wire          N6502_VECTOR_PULL;
    wire          N6502_ML_N;
    wire          N6502_PHI1O;
    wire          N6502_PHI2O;
    wire          N6502_BUS_OE;
    wire          N6502_DOUT_OE;
    wire          N6502_INT_SEQ;
    wire          N6502_RTI_DONE;
    wire          N6502_IN_WAI;
    wire          N6502_IN_STP;
    // wdc65c02 (W65C02S-style 65C02 core; replaced the top-level cpu_65c02 on
    // 2026-09-04). Source: rtl/cpu/wdc65c02/. R65Cx2 remains the
    // differential-test golden.
    wire [15:0]   N65C02_A;
    wire [7:0]    N65C02_DO;
    wire          N65C02_WE;      // active-high write cycle
    // SoC-specific outputs, unused on the Apple II (collected into
    // n65c02_unused_ok below so lint stays quiet)
    wire          N65C02_SYNC;
    wire          N65C02_VECTOR_PULL;
    wire          N65C02_INT_SEQ;
    wire          N65C02_RTI_DONE;
    wire          N65C02_IN_WAI;
    wire          N65C02_IN_STP;
    wire          we;

    // Main ROM signals
    wire [7:0]    rom_out;
    wire [13:0]   rom_addr;

    // Address decoder signals
    reg           RAM_SELECT;
    reg           KEYBOARD_SELECT;
    reg           TAPE_OUT;
    reg           SPEAKER_SELECT;
    reg           SOFTSWITCH_SELECT;
    reg           ROM_SELECT;
    reg           GAMEPORT_SELECT;
    reg           HRAM_CONTROL;
    reg           C01X_SELECT;

    // Speaker signal
    reg           speaker_sig;

    reg [7:0]     CPU_DL;		// Latched RAM data
    wire [7:0]    VIDEO_DL;
    reg [15:0]    VIDEO_DL_LATCH;

    // Bank Switched RAM signals
    wire          Dxxx;
    reg           HRAM_READ;
    reg           HRAM_PRE_WR;
    reg           HRAM_WR_N;
    reg           HRAM_BANK1;
    wire [17:0]   CPU_RAM_ADDR;

    wire          HRAM_READ_EN;
    wire          HRAM_WRITE_EN;

    reg [7:0]     ioselect;
    reg [7:0]     devselect;

    // ramcard
    wire [17:0]   card_addr;
    wire          card_ram_rd;
    wire          card_ram_we;
    wire          ram_card_read;
    wire          ram_card_write;
    wire          ram_card_sel;

    wire          video_rom_select;

    assign CLK_2M = Q3;

    assign ram_addr = (PHASE_ZERO == 1'b1) ? CPU_RAM_ADDR :
                      {2'b00, VIDEO_ADDRESS};
    assign ram_we = machine_ce && (PHASE_ZERO == 1'b1) ? ((we & RAM_SELECT) | (we & (HRAM_WRITE_EN | ram_card_write))) :
                    1'b0;
    assign CPU_WE = we;

    // ramcard

    ramcard ram_card_D(
        .clk(CLK_14M),
        .reset_in(reset),
        .addr(A),
        .ram_addr(card_addr),
        .card_ram_we(card_ram_we),
        .card_ram_rd(card_ram_rd)
    );

    assign ram_card_read = ROM_SELECT & card_ram_rd & saturn_5_inslot;
    assign ram_card_write = ROM_SELECT & card_ram_we & saturn_5_inslot;
    assign ram_card_sel = (we == 1'b1) ? ram_card_write :
                          ram_card_read;


    always @(posedge CLK_14M)
    begin: RAM_data_latch
        if (ss_wren && (ss_addr == 10'd4))
        begin
            CPU_DL         <= ss_wdata[7:0];
            VIDEO_DL_LATCH <= ss_wdata[23:8];
        end
        else if (machine_ce && AX == 1'b1 & CAS_N == 1'b0 & RAS_N == 1'b1 & Q3 == 1'b0)
        begin
            // Latch video data at Phase 1, CPU data at Phase 0
            if (PHASE_ZERO == 1'b0)
                VIDEO_DL_LATCH <= ram_do;
            else if (aux == 1'b0)
                CPU_DL <= ram_do[7:0];
            else
                CPU_DL <= ram_do[15:8];
        end
    end
    assign VIDEO_DL = (PHASE_ZERO == 1'b0) ? VIDEO_DL_LATCH[7:0] :
                      VIDEO_DL_LATCH[15:8];

    assign ADDR = A;
    assign D = D_OUT;

    assign IO_SELECT = ioselect;
    assign DEVICE_SELECT = devselect;

    // Address decoding
    assign rom_addr = A[13:0];

    always @(*)
    begin: address_decoder
        ROM_SELECT = 1'b0;
        RAM_SELECT = 1'b0;
        KEYBOARD_SELECT = 1'b0;
        C01X_SELECT = 1'b0;
        TAPE_OUT = 1'b0;
        SPEAKER_SELECT = 1'b0;
        SOFTSWITCH_SELECT = 1'b0;
        GAMEPORT_SELECT = 1'b0;
        PDL_STROBE = 1'b0;
        STB = 1'b0;
        HRAM_CONTROL = 1'b0;
        ioselect = 8'b0;
        devselect = 8'b0;
        IO_STROBE = 1'b0;
        case (A[15:14])
            2'b00, 2'b01, 2'b10 :		// 0000 - BFFF
                RAM_SELECT = 1'b1;
            2'b11 :		// C000 - FFFF
                case (A[13:12])
                    2'b00 :		// C000 - CFFF
                        case (A[11:8])
                            4'h0 :		// C000 - C0FF
                                case (A[7:4])
                                    4'h0 :		// C000 - C00F
                                        KEYBOARD_SELECT = 1'b1;
                                    4'h1 :		// C010 - C01F
                                        C01X_SELECT = 1'b1;
                                    4'h2 :		// C020 - C02F
                                        TAPE_OUT = 1'b1;
                                    4'h3 :		// C030 - C03F
                                        SPEAKER_SELECT = 1'b1;
                                    4'h4 :		// C040 - C04F
                                        STB = 1'b1;
                                    4'h5 :		// C050 - C05F
                                        SOFTSWITCH_SELECT = 1'b1;
                                    4'h6 :		// C060 - C06F
                                        GAMEPORT_SELECT = 1'b1;
                                    4'h7 :		// C070 - C07F
                                        PDL_STROBE = 1'b1;
                                    4'h8 :		// C080 - C08F
                                        HRAM_CONTROL = 1'b1;
                                    4'h9, 4'hA, 4'hB, 4'hC, 4'hD, 4'hE, 4'hF :		// C090 - C0FF
                                        devselect[(A[6:4])] = 1'b1;
                                    default :
                                        ;
                                endcase
                            4'h1, 4'h2, 4'h4, 4'h5, 4'h6, 4'h7 :		// C100 - C2FF, C400-C7FF
                                if (CXROM == 1'b1)
                                    ROM_SELECT = 1'b1;
                                else
                                    ioselect[(A[10:8])] = 1'b1;
                            4'h3 :		// C300 - C3FF
                                if (CXROM == 1'b1 | C3ROM == 1'b0)
                                    ROM_SELECT = 1'b1;
                                else
                                    ioselect[(A[10:8])] = 1'b1;
                            4'h8, 4'h9, 4'hA, 4'hB, 4'hC, 4'hD, 4'hE, 4'hF :		// C800 - CFFF
                                if (CXROM == 1'b1 | C8ROM == 1'b1)
                                    ROM_SELECT = 1'b1;
                                else
                                    IO_STROBE = 1'b1;
                            default :
                                ;
                        endcase
                    2'b01, 2'b10, 2'b11 :		// D000 - FFFF
                        ROM_SELECT = 1'b1;
                    default :
                        ;
                endcase
            default :
                ;
        endcase
    end

    always @(*)
    begin: aux_ctrl
        aux = 1'b0;
        if (ram_card_sel == 1'b1 || Z80_EN)		// the Z80 only uses main RAM
            aux = 1'b0;
        else if (A[15:9] == 7'b0000000 | A[15:14] == 2'b11)		// Page 00,01,C0-FF
            aux = ALTZP;
        else if (A[15:10] == 6'b000001)		// Page 04-07
            aux = (STORE80 & PAGE2) | ((~STORE80) & ((RAMRD & (~we)) | (RAMWRT & we)));
        else if (A[15:13] == 3'b001)		// Page 20-3F
            aux = (STORE80 & PAGE2 & HIRES_MODE) | (((~STORE80) | (~HIRES_MODE)) & ((RAMRD & (~we)) | (RAMWRT & we)));
        else
            aux = (RAMRD & (~we)) | (RAMWRT & we);
    end

    always @(posedge CLK_14M)
    begin: speaker_ctrl
        if (ss_wren && (ss_addr == 10'd3))
            speaker_sig <= ss_wdata[18];
        else if (machine_ce && PHASE_ZERO_R == 1'b1 & SPEAKER_SELECT == 1'b1)
            speaker_sig <= (~speaker_sig);
    end

    always @(posedge CLK_14M)
    begin: softswitches
        if (ss_wren && (ss_addr == 10'd3))
            soft_switches <= ss_wdata[7:0];
        else if (machine_ce && PHASE_ZERO_R == 1'b1 & SOFTSWITCH_SELECT == 1'b1)
            soft_switches[(A[3:1])] <= A[0];
    end

    assign TEXT_MODE = soft_switches[0];
    assign MIXED_MODE = soft_switches[1];
    assign PAGE2 = soft_switches[2];
    assign HIRES_MODE = soft_switches[3];
    assign AN = soft_switches[7:4];
    assign DHIRES_MODE = AN[3];
    assign RUN_FILL_OK = ~HIRES_MODE | ~DHIRES_MODE;


    always @(posedge CLK_14M)
    begin: hram_ctrl
        if (reset == 1'b1)
        begin
            HRAM_PRE_WR <= 1'b0;
            HRAM_READ <= 1'b0;
            HRAM_WR_N <= 1'b0;
            HRAM_BANK1 <= 1'b0;
        end
        else
        begin
            if (ss_wren && (ss_addr == 10'd3))
            begin
                HRAM_READ   <= ss_wdata[19];
                HRAM_PRE_WR <= ss_wdata[20];
                HRAM_WR_N   <= ss_wdata[21];
                HRAM_BANK1  <= ss_wdata[22];
            end
            else if (machine_ce && PHASE_ZERO_R == 1'b1 & HRAM_CONTROL == 1'b1)
            begin
                HRAM_BANK1 <= A[3];
                HRAM_PRE_WR <= A[0] & (~we);
                if ((HRAM_PRE_WR & (~we) & A[0]) == 1'b1)
                    HRAM_WR_N <= 1'b0;
                else if (A[0] == 1'b0)
                    HRAM_WR_N <= 1'b1;
                HRAM_READ <= (~(A[0] ^ A[1]));
            end
        end
    end

    assign Dxxx = (A[15:12] == 4'hD) ? 1'b1 :
                  1'b0;
    assign CPU_RAM_ADDR = (ram_card_sel == 1'b1) ? card_addr :
                          {2'b00, A[15:13], (A[12] & (~(HRAM_BANK1 & Dxxx))), A[11:0]};
    assign HRAM_READ_EN = HRAM_READ & A[15] & A[14] & (A[13] | A[12]);		// Dxxx-Fxxx
    assign HRAM_WRITE_EN = (~HRAM_WR_N) & A[15] & A[14] & (A[13] | A[12]);		// Dxxx-Fxxx


    always @(posedge CLK_14M)
    begin: softswitches_IIe
        if (reset == 1'b1)
        begin
            STORE80 <= 1'b0;
            RAMRD <= 1'b0;
            RAMWRT <= 1'b0;
            CXROM <= 1'b0;
            ALTZP <= 1'b0;
            C3ROM <= 1'b0;
            C8ROM <= 1'b0;
            COL80 <= 1'b0;
            ALTCHAR <= 1'b0;
        end
        else
        begin
            if (ss_wren && (ss_addr == 10'd3))
            begin
                STORE80 <= ss_wdata[11];
                RAMRD   <= ss_wdata[8];
                RAMWRT  <= ss_wdata[9];
                CXROM   <= ss_wdata[10];
                ALTZP   <= ss_wdata[14];
                C3ROM   <= ss_wdata[12];
                C8ROM   <= ss_wdata[13];
                ALTCHAR <= ss_wdata[15];
                COL80   <= ss_wdata[16];
                SF_D    <= ss_wdata[17];
            end
            else if (ss_wren && (ss_addr == 10'd4))
                READ_KEY <= ss_wdata[25];
            else if (machine_ce) begin
            READ_KEY <= 1'b0;
            if (A[15:8] == 8'hC3 & C3ROM == 1'b0)
                C8ROM <= 1'b1;
            else if (A == 16'hCFFF)
                C8ROM <= 1'b0;
            if (PHASE_ZERO_R == 1'b1 & KEYBOARD_SELECT == 1'b1 & we == 1'b1)
                case (A[3:1])
                    3'b000 :
                        STORE80 <= A[0];
                    3'b001 :
                        RAMRD <= A[0];
                    3'b010 :
                        RAMWRT <= A[0];
                    3'b011 :
                        CXROM <= A[0];
                    3'b100 :
                        ALTZP <= A[0];
                    3'b101 :
                        C3ROM <= A[0];
                    3'b110 :
                        COL80 <= A[0];
                    3'b111 :
                        ALTCHAR <= A[0];
                    default :
                        ;
                endcase
            else if (C01X_SELECT == 1'b1 & we == 1'b0)
                case (A[3:0])
                    4'h0 :
                        begin
                            SF_D <= AKD;
                            READ_KEY <= 1'b1;
                        end
                    4'h1 :
                        SF_D <= (~HRAM_BANK1);
                    4'h2 :
                        SF_D <= HRAM_READ;
                    4'h3 :
                        SF_D <= RAMRD;
                    4'h4 :
                        SF_D <= RAMWRT;
                    4'h5 :
                        SF_D <= CXROM;
                    4'h6 :
                        SF_D <= ALTZP;
                    4'h7 :
                        SF_D <= C3ROM;
                    4'h8 :
                        SF_D <= STORE80;
                    4'h9 :
                        SF_D <= (~VBL);
                    4'hA :
                        SF_D <= TEXT_MODE;
                    4'hB :
                        SF_D <= MIXED_MODE;
                    4'hC :
                        SF_D <= PAGE2;
                    4'hD :
                        SF_D <= HIRES_MODE;
                    4'hE :
                        SF_D <= ALTCHAR;
                    4'hF :
                        SF_D <= COL80;
                    default :
                        ;
                endcase
            else if (C01X_SELECT == 1'b1 & we == 1'b1)
                READ_KEY <= 1'b1;
            end
        end
    end

    assign speaker = speaker_sig;

    assign D_IN = (RAM_SELECT == 1'b1 | HRAM_READ_EN == 1'b1 | ram_card_read == 1'b1) ? CPU_DL : 		// RAM
                  (KEYBOARD_SELECT == 1'b1) ? K : 		// Keyboard
                  (C01X_SELECT == 1'b1) ? {SF_D, K[6:0]} : 		// ][e softswitches
                  (GAMEPORT_SELECT == 1'b1) ? {GAMEPORT[(A[2:0])], VIDEO_DL[6:0]} : 		// Gameport
                  (ROM_SELECT == 1'b1) ? rom_out : 		// ROMs
                  (TAPE_OUT == 1'b1 | SPEAKER_SELECT == 1'b1 | STB == 1'b1 | SOFTSWITCH_SELECT == 1'b1 | PDL_STROBE == 1'b1 | HRAM_CONTROL == 1'b1 | A == 16'hCFFF) ? VIDEO_DL : 		// Floating bus
                  PD;		// Peripherals

    timing_generator timing(
        .CLK_14M(CLK_14M),
        .PALMODE(PALMODE),
        .VID7M(CLK_7M),
        .CAS_N(CAS_N),
        .RAS_N(RAS_N),
        .Q3(Q3),
        .AX(AX),
        .PHI0(PHASE_ZERO),
        .PHI0_EN_R(PHASE_ZERO_R),
        .PHI0_EN_F(PHASE_ZERO_F),
        .COLOR_REF(COLOR_REF),
        .TEXT_MODE(TEXT_MODE),
        .PAGE2(PAGE2),
        .HIRES_MODE(HIRES_MODE),
        .MIXED_MODE(MIXED_MODE),
        .COL80(COL80),
        .STORE80(STORE80),
        .DHIRES_MODE(DHIRES_MODE),
        .VID7(VIDEO_DL[7]),
        .VIDEO_ADDRESS(VIDEO_ADDRESS),
        .SEGA(SEGA),
        .SEGB(SEGB),
        .SEGC(SEGC),
        .GR1(COLOR_LINE),
        .GR2(GR2),
        .VBLANK(VBL),
        .HBLANK(HBL),
        .WNDW_N(WNDW_N),
        .LDPS_N(LDPS_N),
        .ss_addr(ss_addr),
        .ss_wdata(ss_wdata),
        .ss_wren(ss_wren),
        .machine_ce(machine_ce),
        .ss_rdata(timing_ss_rdata)
    );

    assign video_rom_select = (ioctl_download == 1'b1 & ioctl_wr == 1'b1 & ioctl_index == 8'h01) ? 1'b1 : 1'b0;

    video_generator video_display(
        .CLK_14M(CLK_14M),
        .CLK_7M(CLK_7M),
        .GR2(GR2),
        .SEGA(SEGA),
        .SEGB(SEGB),
        .SEGC(SEGC),
        .ALTCHAR(ALTCHAR),
        .ROMSWITCH(ROMSWITCH),
        .WNDW_N(WNDW_N),
        .DL(VIDEO_DL),
        .LDPS_N(LDPS_N),
        .FLASH_CLK(FLASH_CLK),
        .ioctl_addr(ioctl_addr),
        .ioctl_data(ioctl_data),
        .ioctl_wr(video_rom_select),
        .VIDEO(VIDEO),
        .ss_addr(ss_addr),
        .ss_wdata(ss_wdata),
        .ss_wren(ss_wren),
        .machine_ce(machine_ce),
        .ss_rdata(video_ss_rdata)
    );

    assign we = Z80_EN ? Z80_WE : (cpu == 1'b0) ? N6502_WE : N65C02_WE;
    assign A = Z80_EN ? Z80_A : (cpu == 1'b0) ? N6502_A : N65C02_A;
    assign D_OUT = Z80_EN ? Z80_DO : (cpu == 1'b0) ? N6502_DO : N65C02_DO;
    assign CPU_DI = D_IN;
    // DBG_DI: data as seen by the NMOS CPU - dout during a write, din during a
    // read. The nmos6502 core has no T65-style DI loopback, so derive it here.
    assign DBG_DI = N6502_WE ? N6502_DO : D_IN;
    // The nmos6502 core exposes a savestate bus, not a direct register-file
    // port; tie the legacy T65 debug readout off (unused by the harness).
    assign DBG_T65_REGS = 64'd0;
    assign DBG_ROM_ADDR = rom_addr;
    assign DBG_ROM_OUT = rom_out;
    //CPU_EN <= PHASE_ZERO_F; -- not sure why this isn't working??
    wire CPU_EN_RAW = (PHASE_ZERO_D == 1'b1 & PHASE_ZERO == 1'b0) ? 1'b1 : 1'b0;
    assign CPU_EN = machine_ce && CPU_EN_RAW;
    assign cpu_frozen = STALL && !CPU_EN_RAW;

    always @(posedge CLK_14M)
    begin: cpu_enable
        if (ss_wren && (ss_addr == 10'd4))
            PHASE_ZERO_D <= ss_wdata[24];
        else if (machine_ce)
            PHASE_ZERO_D <= PHASE_ZERO;
    end

    // NMOS 6502: nmos6502 core (WDC_MODE=0, one bus access per cycle).
    //   ce = CPU_EN, rdy = ~CPU_WAIT - the same edge model as the wdc65c02 core
    //        below, so machine RAM/ROM timing is unchanged.
    //   so_n tied high (no Set Overflow pin on the Apple II); be=1 (always drive
    //        the core's address/data/write - the mux below selects the bus).
    //   stp_nop=1: Apple II has no power switch, so STP ($DB) is a NOP.
    //   ml_n/phi1o/phi2o/bus_oe/dout_oe are NMOS-specific pins unused here.
    wire [63:0] nmos6502_ss_rdata;
    wire nmos6502_unused_ok = &{1'b0, N6502_SYNC, N6502_VECTOR_PULL,
                                 N6502_ML_N, N6502_PHI1O, N6502_PHI2O,
                                 N6502_BUS_OE, N6502_DOUT_OE,
                                 N6502_INT_SEQ, N6502_RTI_DONE, N6502_IN_WAI,
                                 N6502_IN_STP, nmos6502_ss_rdata};
    nmos6502 #(.WDC_MODE(1'b0)) cpu6502(
        .clk(CLK_14M),
        .ce(CPU_EN),
        .ce_n(1'b0),
        .reset(reset),
        .stall(STALL),
        .irq_n(IRQ_n),
        .nmi_n(NMI_n),
        .rdy(~CPU_WAIT),
        .so_n(1'b1),
        .be(1'b1),
        .stp_nop(1'b1),
        .addr(N6502_A),
        .dout(N6502_DO),
        .din(D_IN),
        .we(N6502_WE),
        .sync(N6502_SYNC),
        .vector_pull(N6502_VECTOR_PULL),
        .ml_n(N6502_ML_N),
        .phi1o(N6502_PHI1O),
        .phi2o(N6502_PHI2O),
        .bus_oe(N6502_BUS_OE),
        .dout_oe(N6502_DOUT_OE),
        .int_seq(N6502_INT_SEQ),
        .rti_done(N6502_RTI_DONE),
        .in_wai(N6502_IN_WAI),
        .in_stp(N6502_IN_STP),
        .ss_addr(ss_addr),
        .ss_wdata(ss_wdata),
        .ss_wren(ss_wren && !cpu),
        .ss_rdata(nmos6502_ss_rdata)
    );

    // 65C02: wdc65c02 core (W65C02S-style, one bus access per cycle;
    // source rtl/cpu/wdc65c02/).
    //   ce = CPU_EN: the PHASE_ZERO falling-edge pulse; on it the core samples
    //        din and launches the next cycle's address/write - the exact edge
    //        R65Cx2's enable used, so machine RAM/ROM timing is unchanged.
    //   rdy = ~CPU_WAIT replaces the old enable-gating (CPU_EN & ~CPU_WAIT).
    //   reset is active-HIGH synchronous here (R65Cx2 was active-low).
    //   stp_nop=1: Apple II has no power switch, so STP ($DB) is a NOP.
    //   STALL is a real port (OSD pause, wired by apple2_top); the
    //   savestate bus is still tied off; see PLAN.md section 6.
    wire [63:0] n65c02_ss_rdata;
    wire n65c02_unused_ok = &{1'b0, N65C02_SYNC, N65C02_VECTOR_PULL,
                               N65C02_INT_SEQ, N65C02_RTI_DONE, N65C02_IN_WAI,
                               N65C02_IN_STP, n65c02_ss_rdata};
    wdc65c02 #(.WDC_MODE(1'b1)) cpu65c02(
        .clk(CLK_14M),
        .ce(CPU_EN),
        .ce_n(1'b0),
        .reset(reset),
        .stall(STALL),
        .irq_n(IRQ_n),
        .nmi_n(NMI_n),
        .rdy(~CPU_WAIT),
        .stp_nop(1'b1),
        .addr(N65C02_A),
        .dout(N65C02_DO),
        .din(D_IN),
        .we(N65C02_WE),
        .sync(N65C02_SYNC),
        .vector_pull(N65C02_VECTOR_PULL),
        .int_seq(N65C02_INT_SEQ),
        .rti_done(N65C02_RTI_DONE),
        .in_wai(N65C02_IN_WAI),
        .in_stp(N65C02_IN_STP),
        .ss_addr(ss_addr),
        .ss_wdata(ss_wdata),
        .ss_wren(ss_wren && cpu),
        .ss_rdata(n65c02_ss_rdata)
    );

    // Original Apple had asynchronous ROMs.  We use a synchronous ROM
    // that needs its address earlier, hence the odd clock.
    rom #(8,14,"rtl/roms/apple2e.hex") roms (
        .clock(CLK_14M),
        .ce(1'b1),
        .a(rom_addr),
        .data_out(rom_out)
    );

    assign ss_rdata = (ss_addr == 10'd3) ?
                      {41'd0, HRAM_BANK1, HRAM_WR_N, HRAM_PRE_WR,
                       HRAM_READ, speaker_sig, SF_D, COL80, ALTCHAR,
                       ALTZP, C8ROM, C3ROM, STORE80, CXROM, RAMWRT,
                       RAMRD, soft_switches} :
                      (ss_addr == 10'd4) ?
                      {38'd0, READ_KEY, PHASE_ZERO_D, VIDEO_DL_LATCH, CPU_DL} :
                      (ss_addr == 10'd5) ? timing_ss_rdata :
                      (ss_addr == 10'd6) ? timing_ss_rdata :
                      (ss_addr == 10'd7) ? video_ss_rdata :
                      cpu ? n65c02_ss_rdata : nmos6502_ss_rdata;
endmodule
