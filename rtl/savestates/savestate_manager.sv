// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Newsdee

module savestate_manager (
  input  wire        clk,
  input  wire        reset,
  input  wire        request_save,
  input  wire        request_load,
  input  wire        allow_save_state,
  input  wire        cpu_type,
  input  wire        cpu_frozen,
  output wire        stall,
  output wire        machine_ce,
  output reg         busy,
  output reg         done,
  output reg         error,
  output reg  [1:0]  error_code,  // 0 none, 1 rejected, 2 invalid/empty, 3 incompatible
  output reg         locked_cpu_type,

  output reg  [9:0]  ss_addr,
  output reg  [63:0] ss_wdata,
  output reg         ss_wren,
  input  wire [63:0] ss_rdata,

  output reg         ram_bank,
  output reg  [15:0] ram_addr,
  output reg         ram_rd,
  output reg         ram_wr,
  output reg  [7:0]  ram_wdata,
  input  wire [7:0]  ram_rdata,

  output reg  [14:0] slot_addr,
  output reg         slot_rd,
  output reg         slot_wr,
  output reg  [63:0] slot_wdata,
  input  wire [63:0] slot_rdata,
  input  wire        slot_ready
);
  localparam [31:0] MAGIC = 32'h41324C31;
  localparam [15:0] USED_WORDS = 16'd16416;        // 64-bit slot words 0..16415
  localparam [31:0] SS_SIZE_DWORDS = 32'd32832;    // payload in 32-bit units = 2 * USED_WORDS
  localparam [7:0]  SS_VERSION = 8'd1;

  localparam [4:0] IDLE              = 5'd0;
  localparam [4:0] FREEZE            = 5'd1;
  localparam [4:0] SETTLE            = 5'd2;
  localparam [4:0] SAVE_HEADERS      = 5'd3;
  localparam [4:0] SAVE_REG_CAPTURE  = 5'd4;
  localparam [4:0] SAVE_REG_WRITE    = 5'd5;
  localparam [4:0] SAVE_RAM_READ     = 5'd6;
  localparam [4:0] SAVE_RAM_CAPTURE  = 5'd7;
  localparam [4:0] SAVE_RAM_WRITE    = 5'd8;
  localparam [4:0] LOAD_HEADER0      = 5'd9;
  localparam [4:0] LOAD_HEADER1      = 5'd10;
  localparam [4:0] LOAD_REG_READ     = 5'd11;
  localparam [4:0] LOAD_RAM_READ     = 5'd12;
  localparam [4:0] LOAD_RAM_WRITE    = 5'd13;
  localparam [4:0] APPLY_MACHINE     = 5'd14;
  localparam [4:0] APPLY_CPU         = 5'd15;
  localparam [4:0] FINISH            = 5'd16;
  localparam [4:0] FAIL              = 5'd17;

  reg [4:0] state;
  reg       operation_load;
  reg [1:0] fail_code;
  reg [1:0] settle_count;
  reg [4:0] header_index;
  reg [3:0] reg_index;
  reg [16:0] byte_index;
  reg [2:0] byte_lane;
  reg [63:0] pack_word;
  reg [63:0] load_word;
  reg [63:0] header0_read;
  reg [31:0] ss_counter;
  reg [63:0] register_shadow [0:10];

  assign stall = busy;
  assign machine_ce = (state == IDLE) || (state == FREEZE);

  always @* begin
    ss_addr = 10'd0;
    ss_wdata = 64'd0;
    ss_wren = 1'b0;
    ram_bank = byte_index[16];
    ram_addr = byte_index[15:0];
    ram_rd = 1'b0;
    ram_wr = 1'b0;
    ram_wdata = load_word[byte_lane * 8 +: 8];
    slot_addr = 15'd0;
    slot_rd = 1'b0;
    slot_wr = 1'b0;
    slot_wdata = 64'd0;

    case (state)
      SAVE_HEADERS: begin
        slot_addr = {10'd0, header_index};
        slot_wr = 1'b1;
        // word 0 = {size_dwords, counter}, word 1 = {MAGIC, version, reserved[23:1], cpu}
        slot_wdata = (header_index == 0) ? {SS_SIZE_DWORDS, ss_counter} :
                     (header_index == 1) ? {MAGIC, SS_VERSION, 23'd0, locked_cpu_type} : 64'd0;
      end
      SAVE_REG_CAPTURE: ss_addr = {6'd0, reg_index};
      SAVE_REG_WRITE: begin
        slot_addr = 15'd16 + {11'd0, reg_index};
        slot_wr = 1'b1;
        slot_wdata = register_shadow[reg_index];
      end
      SAVE_RAM_READ: ram_rd = 1'b1;
      SAVE_RAM_WRITE: begin
        slot_addr = 15'd32 + byte_index[16:3];
        slot_wr = 1'b1;
        slot_wdata = pack_word;
      end
      LOAD_HEADER0: begin
        slot_addr = 15'd0;
        slot_rd = 1'b1;
      end
      LOAD_HEADER1: begin
        slot_addr = 15'd1;
        slot_rd = 1'b1;
      end
      LOAD_REG_READ: begin
        slot_addr = 15'd16 + {11'd0, reg_index};
        slot_rd = 1'b1;
      end
      LOAD_RAM_READ: begin
        slot_addr = 15'd32 + byte_index[16:3];
        slot_rd = 1'b1;
      end
      LOAD_RAM_WRITE: ram_wr = 1'b1;
      APPLY_MACHINE: begin
        ss_addr = {6'd0, reg_index};
        ss_wdata = register_shadow[reg_index];
        ss_wren = 1'b1;
      end
      APPLY_CPU: begin
        ss_addr = {6'd0, reg_index};
        ss_wdata = register_shadow[reg_index];
        ss_wren = 1'b1;
      end
      default: begin end
    endcase
  end

  always @(posedge clk) begin
    done <= 1'b0;
    error <= 1'b0;
    error_code <= 2'd0;

    if (reset) begin
      state <= IDLE;
      busy <= 1'b0;
      fail_code <= 2'd0;
      locked_cpu_type <= 1'b0;
      operation_load <= 1'b0;
      settle_count <= 2'd0;
      header_index <= 5'd0;
      reg_index <= 4'd0;
      byte_index <= 17'd0;
      byte_lane <= 3'd0;
      pack_word <= 64'd0;
      load_word <= 64'd0;
      header0_read <= 64'd0;
      ss_counter <= 32'd1;
    end else begin
      case (state)
        IDLE: begin
          if (request_save || request_load) begin
            if (!allow_save_state) begin
              done <= 1'b1;
              error <= 1'b1;
              error_code <= 2'd1;
            end else begin
              busy <= 1'b1;
              locked_cpu_type <= cpu_type;
              operation_load <= request_load;
              if (request_save) ss_counter <= ss_counter + 1'b1;
              state <= FREEZE;
            end
          end
        end
        FREEZE: begin
          if (cpu_frozen) begin
            settle_count <= 2'd0;
            state <= SETTLE;
          end
        end
        SETTLE: begin
          if (settle_count == 2'd2) begin
            header_index <= 5'd0;
            state <= operation_load ? LOAD_HEADER0 : SAVE_HEADERS;
          end else begin
            settle_count <= settle_count + 1'b1;
          end
        end
        SAVE_HEADERS: begin
          if (slot_ready) begin
            if (header_index == 5'd15) begin
              reg_index <= 4'd0;
              state <= SAVE_REG_CAPTURE;
            end else begin
              header_index <= header_index + 1'b1;
            end
          end
        end
        SAVE_REG_CAPTURE: begin
          register_shadow[reg_index] <= ss_rdata;
          if (reg_index == 4'd10) begin
            reg_index <= 4'd0;
            state <= SAVE_REG_WRITE;
          end else begin
            reg_index <= reg_index + 1'b1;
          end
        end
        SAVE_REG_WRITE: begin
          if (slot_ready) begin
            if (reg_index == 4'd10) begin
              byte_index <= 17'd0;
              byte_lane <= 3'd0;
              pack_word <= 64'd0;
              state <= SAVE_RAM_READ;
            end else begin
              reg_index <= reg_index + 1'b1;
            end
          end
        end
        SAVE_RAM_READ: state <= SAVE_RAM_CAPTURE;
        SAVE_RAM_CAPTURE: begin
          pack_word[byte_lane * 8 +: 8] <= ram_rdata;
          if (byte_lane == 3'd7) begin
            state <= SAVE_RAM_WRITE;
          end else begin
            byte_lane <= byte_lane + 1'b1;
            byte_index <= byte_index + 1'b1;
            state <= SAVE_RAM_READ;
          end
        end
        SAVE_RAM_WRITE: begin
          if (slot_ready) begin
            if (byte_index == 17'h1FFFF) begin
              state <= FINISH;
            end else begin
              byte_index <= byte_index + 1'b1;
              byte_lane <= 3'd0;
              state <= SAVE_RAM_READ;
            end
          end
        end
        LOAD_HEADER0: begin
          if (slot_ready) begin
            header0_read <= slot_rdata;
            state <= LOAD_HEADER1;
          end
        end
        LOAD_HEADER1: begin
          if (slot_ready) begin
            // word 1 = {MAGIC, version, reserved[23:1], cpu}; word 0 = {size, counter}.
            // Empty slot or non-state word 1 -> 2 (invalid/empty); wrong version or
            // CPU -> 3 (incompatible); bad size -> 2 (invalid). Counter is ignored.
            if (slot_rdata == 64'h0) begin
              fail_code <= 2'd2;
              state <= FAIL;
            end else if (slot_rdata[63:32] != MAGIC) begin
              fail_code <= 2'd2;
              state <= FAIL;
            end else if (slot_rdata[31:24] != SS_VERSION) begin
              fail_code <= 2'd3;
              state <= FAIL;
            end else if (slot_rdata[0] != locked_cpu_type) begin
              fail_code <= 2'd3;
              state <= FAIL;
            end else if (header0_read[63:32] == 32'd0) begin
              fail_code <= 2'd2;
              state <= FAIL;
            end else if (header0_read[63:32] > SS_SIZE_DWORDS) begin
              fail_code <= 2'd2;
              state <= FAIL;
            end else begin
              reg_index <= 4'd0;
              state <= LOAD_REG_READ;
            end
          end
        end
        LOAD_REG_READ: begin
          if (slot_ready) begin
            register_shadow[reg_index] <= slot_rdata;
            if (reg_index == 4'd10) begin
              byte_index <= 17'd0;
              byte_lane <= 3'd0;
              state <= LOAD_RAM_READ;
            end else begin
              reg_index <= reg_index + 1'b1;
            end
          end
        end
        LOAD_RAM_READ: begin
          if (slot_ready) begin
            load_word <= slot_rdata;
            byte_lane <= 3'd0;
            state <= LOAD_RAM_WRITE;
          end
        end
        LOAD_RAM_WRITE: begin
          if (byte_index == 17'h1FFFF) begin
            reg_index <= 4'd3;
            state <= APPLY_MACHINE;
          end else begin
            byte_index <= byte_index + 1'b1;
            if (byte_lane == 3'd7) begin
              byte_lane <= 3'd0;
              state <= LOAD_RAM_READ;
            end else begin
              byte_lane <= byte_lane + 1'b1;
            end
          end
        end
        APPLY_MACHINE: begin
          if (reg_index == 4'd10) begin
            reg_index <= 4'd0;
            state <= APPLY_CPU;
          end else begin
            reg_index <= reg_index + 1'b1;
          end
        end
        APPLY_CPU: begin
          if (reg_index == 4'd2) begin
            settle_count <= 2'd0;
            state <= FINISH;
          end else begin
            reg_index <= reg_index + 1'b1;
          end
        end
        FINISH: begin
          if (settle_count == 2'd2) begin
            busy <= 1'b0;
            done <= 1'b1;
            state <= IDLE;
          end else begin
            settle_count <= settle_count + 1'b1;
          end
        end
        FAIL: begin
          busy <= 1'b0;
          done <= 1'b1;
          error <= 1'b1;
          error_code <= fail_code;
          state <= IDLE;
        end
        default: begin
          busy <= 1'b0;
          error <= 1'b1;
          error_code <= 2'd2;
          state <= IDLE;
        end
      endcase
    end
  end
endmodule
