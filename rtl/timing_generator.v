`timescale 1ns / 1ps

//-----------------------------------------------------------------------------
//
// Apple //e Timing logic
// Szombathelyi György
//
// Based on original Apple ][+ timing logic by:
// Stephen A. Edwards, sedwards@cs.columbia.edu
//
// Following the schematics of the book Understanding the Apple IIe by Jim Sather
//
//-----------------------------------------------------------------------------
// no timescale needed

module timing_generator(
input wire CLK_14M,
input wire PALMODE,    // PAL/NTSC selection
output reg VID7M,
output reg Q3,
output reg RAS_N,
output reg CAS_N,
output reg AX,
output reg PHI0,
output reg COLOR_REF,
output wire PHI0_EN_R,  // next clock is PHI0=1
output wire PHI0_EN_F,  // next clock is PHI0=0
input wire TEXT_MODE,
input wire PAGE2,
input wire HIRES_MODE,
input wire MIXED_MODE,
input wire COL80,
input wire STORE80,
input wire DHIRES_MODE,
input wire VID7,
output wire [15:0] VIDEO_ADDRESS,
output reg SEGA,
output reg SEGB,
output reg SEGC,
output reg GR1,
output reg GR2,
output reg HBLANK,
output reg VBLANK,
output reg WNDW_N,
output reg LDPS_N
);

// 14.31818 MHz master clock
// 2 MHz signal in phase with PHI0
// 1.0 MHz processor clock
// 3.579545 MHz colorburst
// Horizontal blanking
// Vertical blanking
// Composite blanking



reg [6:0] H = 7'b0000000;
reg [8:0] V = 9'b011111010;
wire [8:0] V_RESET;
wire COLOR_DELAY_N;
reg CLK_7M;
wire RAS_N_PRE; wire AX_PRE; wire CAS_N_PRE; wire Q3_PRE; wire PHI0_PRE; wire VID7M_PRE; wire LDPS_N_PRE;
wire RASRISE1;
wire H0; wire VA; wire VB; wire VC; wire V2; wire V4; wire GR2_G;
wire HIRES;
wire HBL; wire VBL;

  assign RASRISE1 = RAS_N == 1'b1 && PHI0 == 1'b0 && Q3 == 1'b0 ? 1'b1 : 1'b0;
  assign GR2_G = GR2 & DHIRES_MODE;
  // The main clock signal generator

  always @(posedge CLK_14M) begin
    COLOR_REF <= CLK_7M ^ COLOR_REF;
    CLK_7M <=  ~CLK_7M;
  end

  // The timing HAL equations
  assign RAS_N_PRE =  ~(Q3 | ( ~RAS_N &  ~AX) | ( ~RAS_N & COLOR_REF & H0 & PHI0) | ( ~RAS_N &  ~CLK_7M & H0 & PHI0));
  assign AX_PRE =  ~(( ~RAS_N & Q3) | ( ~AX & Q3));
  assign CAS_N_PRE =  ~(( ~AX) | ( ~AX &  ~PHI0) | ( ~CAS_N &  ~RAS_N));
  assign Q3_PRE =  ~(( ~AX &  ~PHI0 &  ~CLK_7M) | ( ~AX & PHI0 & CLK_7M) | ( ~Q3 &  ~RAS_N));
  assign PHI0_PRE =  ~((PHI0 & RAS_N &  ~Q3) | ( ~PHI0 &  ~RAS_N) | ( ~PHI0 & Q3));
  assign VID7M_PRE =  ~((GR2_G & SEGB) | ( ~GR2_G & COL80) | ( ~GR2_G & CLK_7M) | ( ~VID7 &  ~PHI0 &  ~Q3 &  ~AX) | ( ~H0 & COLOR_REF &  ~PHI0 &  ~Q3 &  ~AX) | (VID7M & AX) | (VID7M & PHI0) | (VID7M & Q3));
  assign LDPS_N_PRE =  ~(( ~Q3 &  ~AX & COL80 &  ~GR2_G) | ( ~Q3 &  ~AX &  ~PHI0 &  ~GR2_G) | ( ~Q3 &  ~AX &  ~PHI0 & SEGB) | ( ~Q3 &  ~AX &  ~PHI0 &  ~VID7) | ( ~Q3 &  ~AX &  ~PHI0 & COLOR_REF &  ~H0) | ( ~Q3 & AX &  ~RAS_N &  ~PHI0 & VID7 &  ~SEGB & GR2_G));

  assign PHI0_EN_R = ~PHI0 & PHI0_PRE;
  assign PHI0_EN_F = PHI0 & ~PHI0_PRE;
  always @(posedge CLK_14M) begin
    RAS_N <= RAS_N_PRE;
    AX <= AX_PRE;
    CAS_N <= CAS_N_PRE;
    Q3 <= Q3_PRE;
    PHI0 <= PHI0_PRE;
    VID7M <= VID7M_PRE;
    LDPS_N <= LDPS_N_PRE;
  end

  // various auxilary signals
  always @(posedge CLK_14M) begin
    if(RASRISE1 == 1'b1) begin
      HBLANK <= HBL;
      VBLANK <= VBL;
      WNDW_N <= HBL | VBL;
      GR2 <= GR1;
      GR1 <=  ~(TEXT_MODE | (V2 & V4 & MIXED_MODE));
    end
  end

  assign HIRES = HIRES_MODE & GR2;
  always @(posedge CLK_14M) begin
    if(RASRISE1 == 1'b1) begin
      if(GR1 == 1'b0) begin
        SEGA <= VA;
        SEGB <= VB;
        SEGC <= VC;
      end
      else begin
        SEGA <= H0;
        SEGB <=  ~HIRES_MODE;
        SEGC <= VC;
      end
    end
  end

  // Horizontal and vertical counters
  assign V_RESET = PALMODE ? 9'b011001000 : 9'b011111010;

  always @(posedge CLK_14M) begin
    if(RASRISE1 == 1'b1) begin
      if(H[6] == 1'b0) begin
        H <= 7'b1000000;
      end
      else begin
        H <= H + 7'd1;
        if(H == 7'b1111111) begin
          V <= V + 9'd1;
          if(V == 9'b111111111) begin
            V <= V_RESET;
          end
        end
      end
    end
  end

  assign H0 = H[0];
  assign VA = V[0];
  assign VB = V[1];
  assign VC = V[2];
  assign V2 = V[5];
  assign V4 = V[7];
  assign HBL =  ~(H[5] | (H[3] & H[4]));
  assign VBL = V[6] & V[7];
  // V_SYNC <= VBL and V(5) and not V(4) and not V(3) and
  //           not V(2) and (H(4) or H(3) or H(5));
  // H_SYNC <= HBL and H(3) and not H(2);
  // SYNC <= not (V_SYNC or H_SYNC);
  // COLOR_BURST <= HBL and H(2) and H(3) and (COLOR_REF or TEXT_MODE);
  // Video address calculation
  assign VIDEO_ADDRESS[2:0] = H[2:0];
  assign VIDEO_ADDRESS[6:3] = ({ ~H[5],V[6],H[4],H[3]}) + ({V[7], ~H[5],V[7],1'b1}) + ({3'b000,V[6]});
  assign VIDEO_ADDRESS[9:7] = V[5:3];
  assign VIDEO_ADDRESS[14:10] = HIRES == 1'b0 ? {2'b00,HBL,PAGE2 &  ~STORE80, ~(PAGE2 &  ~STORE80)} : {PAGE2 &  ~STORE80, ~(PAGE2 &  ~STORE80),V[2:0]};
  assign VIDEO_ADDRESS[15] = 1'b0;

endmodule
