//============================================================================
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

module emu
(
     input         CLK_50M,
     input         RESET,
     inout  [45:0] HPS_BUS,

     //Video
     output        CLK_VIDEO,
     output        CE_PIXEL,

     output  [7:0] VIDEO_ARX,
     output  [7:0] VIDEO_ARY,

     output  [7:0] VGA_R,
     output  [7:0] VGA_G,
     output  [7:0] VGA_B,
     output        VGA_HS,
     output        VGA_VS,
     output        VGA_DE,    // = ~(VBlank | HBlank)
     output        VGA_F1,
     output [1:0]  VGA_SL,
     output        VGA_SCALER,
     
     output        LED_USER,  // 1 - ON, 0 - OFF.
     output  [1:0] LED_POWER,
     output  [1:0] LED_DISK,

     output  [1:0] BUTTONS,

     input         CLK_AUDIO, // 24.576 MHz
     output [15:0] AUDIO_L,
     output [15:0] AUDIO_R,
     output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
     output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

     //ADC
     inout   [3:0] ADC_BUS,

     //SD-SPI
     output        SD_SCK,
     output        SD_MOSI,
     input         SD_MISO,
     output        SD_CS,
     input         SD_CD,

     //DDR3
     output        DDRAM_CLK,
     input         DDRAM_BUSY,
     output  [7:0] DDRAM_BURSTCNT,
     output [28:0] DDRAM_ADDR,
     input  [63:0] DDRAM_DOUT,
     input         DDRAM_DOUT_READY,
     output        DDRAM_RD,
     output [63:0] DDRAM_DIN,
     output  [7:0] DDRAM_BE,
     output        DDRAM_WE,

     //SDRAM
     output        SDRAM_CLK,
     output        SDRAM_CKE,
     output [12:0] SDRAM_A,
     output  [1:0] SDRAM_BA,
     inout  [15:0] SDRAM_DQ,
     output        SDRAM_DQML,
     output        SDRAM_DQMH,
     output        SDRAM_nCS,
     output        SDRAM_nCAS,
     output        SDRAM_nRAS,
     output        SDRAM_nWE,

     //UART
     input         UART_CTS,
     output        UART_RTS,
     input         UART_RXD,
     output        UART_TXD,
     output        UART_DTR,
     input         UART_DSR,

     // Open-drain User port.
     input   [6:0] USER_IN,
     output  [6:0] USER_OUT,

     input         OSD_STATUS
);

//////////////////////////////////////////////////////////////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;  

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER = 0;

assign AUDIO_S = 0;
assign AUDIO_MIX = 0;

assign LED_USER = 0;
assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

assign VIDEO_ARX = status[3] ? 8'd16 : 8'd4;
assign VIDEO_ARY = status[3] ? 8'd9  : 8'd3; 

`include "build_id.v"

localparam CONF_STR = {
    "ChannelF;;",
    "-;",
    "FS,ROMBIN;",
    "O3,Aspect ratio,4:3,16:9;",
    "OA,Video standard,NTSC,PAL;",
    "O1,Swap Joystick,Off,On;",
    "-;",
    "R0,Reset;",
    "J1,Time (1),Mode (2),Hold (3),Start (4),Push,Pull,Turn CW,Turn CCW;",
    "V,v",`BUILD_DATE
};

wire forced_scandoubler;
wire  [1:0] buttons;
wire [31:0] status;
wire [10:0] ps2_key;

wire        ioctl_download;
wire [7:0]  ioctl_index;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire [7:0]  ioctl_dout;
wire        ioctl_wait;
wire [31:0] joystick_0,joystick_1;
wire [15:0] joystick_analog_0,joystick_analog_1;
wire [31:0] joystick_s0,joystick_s1;

assign joystick_s0 = status[1] ? joystick_1 : joystick_0;
assign joystick_s1 = status[1] ? joystick_0 : joystick_1;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
    .clk_sys(clk_sys),
    .HPS_BUS(HPS_BUS),
    .conf_str(CONF_STR),
    .joystick_0(joystick_0),
    .joystick_1(joystick_1),
    .joystick_analog_0(joystick_analog_0),
    .joystick_analog_1(joystick_analog_1),
    .forced_scandoubler(forced_scandoubler),
    .buttons(buttons),
    .status(status),
    .ioctl_download(ioctl_download),
    .ioctl_index(ioctl_index),
    .ioctl_wr(ioctl_wr),
    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout),
    .ioctl_wait(ioctl_wait),
    .ps2_key(ps2_key),
);

wire clk_sys,pll_locked;

wire pal    = status[10];

chf_core chf_core
(
    .clk(clk_sys),
    .pll_locked(pll_locked),
    .pal(pal),
    .reset(RESET | status[0]),
    .vga_clk(CLK_VIDEO),
    .vga_ce(CE_PIXEL),
    .vga_r(VGA_R),
    .vga_g(VGA_G),
    .vga_b(VGA_B),
    .vga_hs(VGA_HS),
    .vga_vs(VGA_VS),
    .vga_de(VGA_DE),
    .joystick_0(joystick_s0),
    .joystick_1(joystick_s1),
    .status(status),
    .ioctl_download(ioctl_download),
    .ioctl_index(ioctl_index),
    .ioctl_wr(ioctl_wr),
    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout),
    .ioctl_wait(ioctl_wait),
    .audio_l(AUDIO_L),
    .audio_r(AUDIO_R)
);

pll pll
(
    .refclk(CLK_50M),
    .reconfig_to_pll(reconfig_to_pll),
    .reconfig_from_pll(reconfig_from_pll),
    .locked(pll_locked),
    .outclk_0(clk_sys)
);

wire [63:0] reconfig_to_pll;
wire [63:0] reconfig_from_pll;
wire        cfg_waitrequest;
reg         cfg_write;
reg   [5:0] cfg_address;
reg   [31:0] cfg_data;

/*
pll_cfg pll_cfg
(
    .mgmt_clk(CLK_50M),
    .mgmt_reset(0),
    .mgmt_waitrequest(cfg_waitrequest),
    .mgmt_read(0),
    .mgmt_readdata(),
    .mgmt_write(cfg_write),
    .mgmt_address(cfg_address),
    .mgmt_writedata(cfg_data),
    .reconfig_to_pll(reconfig_to_pll),
    .reconfig_from_pll(reconfig_from_pll)
);


// NTSC : 3.579545MHz *  12 =  42.95454MHz
// PAL  : 4MHz        *  12 =  48MHz
  
// STIC : CLK * 12
// IVOICE : CLK
  
reg tv_reset = 0;
always @(posedge CLK_50M) begin
    reg pald = 0, pald2 = 0;
    reg [2:0] state = 0;

    pald  <= pal;
    pald2 <= pald;

    cfg_write <= 0;
    if(pald2 != pald) state <= 1;

    if(!cfg_waitrequest) begin
        if(state) state<=state+1'd1;
        case(state)
               0: tv_reset <= 0;
               1: begin
                         tv_reset <= 1;
                         cfg_address <= 0; // Waitrequest mode
                         cfg_data <= 0;
                         cfg_write <= 1;
                    end
               2: begin
                         cfg_address <= 3; // N counter
                         cfg_data <= 32'h00010000;
                         cfg_write <= 1;
                    end
               3: begin
                         cfg_address <= 4; // M counter
                         cfg_data <= 32'h00000404;
                         cfg_write <= 1;
                    end
               4: begin
                         cfg_address <= 5; // C0 counter
                         cfg_data <= pald2 ? 32'h00020504 : 32'h00000505;
                         cfg_write <= 1;
                    end
               5: begin
                         cfg_address <= 7; // M frac
                         cfg_data <= pald2 ? 32'hA3D709E8 : 32'h9745BF27;
                         cfg_write <= 1;
                    end
               6: begin
                         cfg_address <= 2; // Start reconf
                         cfg_data <= 0;
                         cfg_write <= 1;
                    end
          endcase
     end
end
*/
endmodule
