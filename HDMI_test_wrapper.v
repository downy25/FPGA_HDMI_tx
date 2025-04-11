`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/04/10 11:23:41
// Design Name: 
// Module Name: HDMI_test_wrapper
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module HDMI_test_wrapper(
    input clk_125Mhz,  // 25MHz
	output [2:0] TMDSp, TMDSn,
	output TMDSp_clock, TMDSn_clock
);
    wire clk_25Mhz; 
    clk_wiz_0 DUT1(
       .clk_in1(clk_125Mhz),
       .clk_out1(clk_25Mhz)
    );
    
    HDMI_test DUT0(
        .pixclk(clk_25Mhz),
        .TMDSp(TMDSp),
        .TMDSn(TMDSn),
        .TMDSp_clock(TMDSp_clock),
        .TMDSn_clock(TMDSn_clock)
    );
endmodule
