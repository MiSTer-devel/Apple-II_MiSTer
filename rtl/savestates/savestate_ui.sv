// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Newsdee

//
// savestate_ui.sv - Save-state OSD/UI controller for the Apple II core.
//
// OSD status bits (CONF_STR "Save States" page, lowercase 'o' = +32 offset):
//   status[45]    "Savestates to SDCard" - shown, always grayed (menumask[8]=0),
//                                           forced Off by the wrapper
//   status[47:46] "Savestate Slot"       - selected slot 0-3
//   status[48]    "Save state (F6)"      - command line (rG); miosd pulses the bit
//   status[49]    "Restore state (F5)"   - command line (rH); miosd pulses the bit
//
// status_menumask (hps_io):
//   bit 7 = save states available (enables the two "d7" command lines)
//   bit 8 = always 0 (keeps the "d8" SDCard line grayed out)
//
// Info strings (CONF_STR "I," line; index driven on info):
//   1-4    Active slot 1-4
//   5-12   State N saved / State N loaded   (5 + 2*slot + load)
//   13     Save states unavailable (Saturn)
//   14     Invalid or empty state
//   15     Incompatible state format or CPU
//
// The module latches the operation type and slot when a request is issued
// and reports the result from the manager's done/error, so the feedback
// always names the operation and slot that were actually used. Requests are
// forwarded to the manager unconditionally (except while busy, when the
// manager would drop them): the manager is the rejection authority, and its
// done/error drives the feedback message.

module savestate_ui (
  input  wire        clk,
  input  wire        reset,
  // Availability: Saturn off, no reset/download, manager idle
  input  wire        allow_ss,
  // Manager status
  input  wire        ss_busy,
  input  wire        ss_done,
  input  wire        ss_error,
  input  wire [1:0]  ss_error_code,   // 1 rejected, 2 invalid/empty, 3 incompatible
  // OSD status bits
  input  wire [1:0]  osd_slot,        // status[47:46]
  input  wire        osd_save,        // status[48]
  input  wire        osd_restore,     // status[49]
  // Keyboard hotkeys (F6 save / F5 load) from savestate_hotkeys
  input  wire        hk_save,
  input  wire        hk_load,
  // Outputs
  output reg         ss_save_req,     // one-cycle save request to the manager
  output reg         ss_load_req,     // one-cycle load request to the manager
  output reg  [1:0]  ss_slot,         // selected slot, held while busy
  output reg         info_req,        // one-cycle pulse to hps_io
  output reg  [7:0]  info,            // info string index
  output wire [15:0] status_menumask
);

  reg [1:0] op_slot;
  reg       op_load;
  reg       old_osd_save;
  reg       old_osd_restore;

  // bit 7 gates the Save/Restore command lines, bit 8 stays 0 so the
  // "Savestates to SDCard" line is permanently grayed out.
  assign status_menumask = {7'd0, 1'b0, allow_ss, 7'd0};

  always @(posedge clk) begin
    ss_save_req <= 1'b0;
    ss_load_req <= 1'b0;
    info_req    <= 1'b0;
    info        <= 8'd0;

    old_osd_save    <= osd_save;
    old_osd_restore <= osd_restore;

    if (reset) begin
      ss_slot <= 2'd0;
      op_slot <= 2'd0;
      op_load <= 1'b0;
    end else begin
      // Track the OSD selector, but hold it for the duration of a
      // transaction so the active transfer cannot be redirected.
      if (!ss_busy && osd_slot != ss_slot) begin
        ss_slot  <= osd_slot;
        info     <= 8'd1 + {6'd0, osd_slot};
        info_req <= 1'b1;
      end

      // Commands: the OSD lines pulse their status bit
      if (!ss_busy) begin
        if ((osd_save & ~old_osd_save) | hk_save) begin
          ss_save_req <= 1'b1;
          op_load     <= 1'b0;
          op_slot     <= ss_slot;
        end
        if ((osd_restore & ~old_osd_restore) | hk_load) begin
          ss_load_req <= 1'b1;
          op_load     <= 1'b1;
          op_slot     <= ss_slot;
        end
      end

      // Report the result from manager completion, not the request edge.
      if (ss_done) begin
        if (ss_error) begin
          case (ss_error_code)
            2'd1:    info <= 8'd13;
            2'd2:    info <= 8'd14;
            default: info <= 8'd15;
          endcase
        end else begin
          info <= 8'd5 + {4'd0, op_slot, 1'b0} + {7'd0, op_load};
        end
        info_req <= 1'b1;
      end
    end
  end
endmodule
