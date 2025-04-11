// (c) fpga4fun.com & KNJN LLC 2013-2023

// 1. VGA controller
module VGA_controller(
    input pixclk,
    output reg hSync, vSync, DrawArea,
    output reg [9:0] CounterX, CounterY
);
always @(posedge pixclk) CounterX <= (CounterX==799) ? 0 : CounterX+1;
always @(posedge pixclk) if(CounterX==799) CounterY <= (CounterY==524) ? 0 : CounterY+1;

//reg hSync, vSync;
always @(posedge pixclk) hSync <= (CounterX>=656) && (CounterX<752);
always @(posedge pixclk) vSync <= (CounterY>=490) && (CounterY<492);

//reg DrawArea;
always @(posedge pixclk) DrawArea <= (CounterX<640) && (CounterY<480);

endmodule

// 2. Image Generator (입력 : CounterX, CounterY, 출력 : red, green, blue
module ImageGenerator(
    input pixclk,
    input [9:0] CounterX, CounterY,
    output reg [7:0] red, green, blue
);

wire [7:0] RED, GREEN, BLUE;

// 그리기 시작
localparam BOX_CLK_DIV = 100000;
localparam FRAME_WIDTH=640;
localparam FRAME_HEIGHT=480;
localparam BOX_WIDTH=16;
localparam BOX_X_MAX=(FRAME_WIDTH-BOX_WIDTH);
localparam BOX_Y_MAX=(FRAME_HEIGHT-BOX_WIDTH);
localparam BOX_X_MIN=0;
localparam BOX_Y_MIN=0;

reg [31:0] box_cnt;

always @(posedge pixclk)
    box_cnt <= (box_cnt<(BOX_CLK_DIV-1))?box_cnt+1:0;

wire update_box;
assign update_box=(box_cnt==(BOX_CLK_DIV-1))?1:0;

reg [9:0] box_x, box_y;
reg box_x_dir, box_y_dir;

always @(posedge pixclk)
begin
    if(update_box==1) begin
        box_x <= (box_x_dir==0)?box_x+1:box_x-1;
        box_y <= (box_y_dir==0)?box_y+1:box_y-1;
    end
end

always @(posedge pixclk)begin
    if(update_box==1) begin
        if(((box_x_dir==0)&&(box_x>=BOX_X_MAX-1)) || ((box_x_dir==1)&&(box_x<=BOX_X_MIN+1)))
            box_x_dir <= ~box_x_dir;
        if(((box_y_dir==0)&&(box_y>=BOX_Y_MAX-1)) || ((box_y_dir==1)&&(box_y<=BOX_Y_MIN+1)))
            box_y_dir <= ~box_y_dir;
    end
end

wire pixel_in_box;
assign pixel_in_box = ((box_x<=CounterX) && (CounterX<(box_x+BOX_WIDTH))) &&
                      ((box_y<=CounterY) && (CounterY<(box_y+BOX_WIDTH)));

assign RED=(pixel_in_box==1)?{8{1'b1}}:0;
assign GREEN=0;
assign BLUE=0;


// 그리기 끝

always @(posedge pixclk) red <= RED;
always @(posedge pixclk) green <= GREEN;
always @(posedge pixclk) blue <= BLUE;

endmodule

////////////////////////////////////////////////////////////////////////
module HDMI_test(
   input pixclk,  // 25MHz
   output [2:0] TMDSp, TMDSn,
   output TMDSp_clock, TMDSn_clock
);

wire [9:0] CounterX, CounterY;
wire hSync, vSync;
wire DrawArea;
VGA_controller vc0(.pixclk(pixclk), 
                    .hSync(hSync), .vSync(vSync), 
                    .DrawArea(DrawArea), 
                    .CounterX(CounterX), .CounterY(CounterY)); 

wire [7:0] red, green, blue;
ImageGenerator ig0(pixclk, CounterX, CounterY,red, green, blue);


// 3. TMDS Encoding
wire [9:0] TMDS_red, TMDS_green, TMDS_blue;
TMDS_encoder encode_R(.clk(pixclk), .VD(red  ), .CD(2'b00)        , .VDE(DrawArea), .TMDS(TMDS_red));
TMDS_encoder encode_G(.clk(pixclk), .VD(green), .CD(2'b00)        , .VDE(DrawArea), .TMDS(TMDS_green));
TMDS_encoder encode_B(.clk(pixclk), .VD(blue ), .CD({vSync,hSync}), .VDE(DrawArea), .TMDS(TMDS_blue));

// 4. HDMI clock
wire clk_TMDS;  // 25MHz x 10 = 250MHz
clk_wiz_1 c0(.clk_in1(pixclk),.clk_out1(clk_TMDS));

// 5. HDMI serializer - 250mhz
reg [3:0] TMDS_mod10=0;  // modulus 10 counter
reg [9:0] TMDS_shift_red=0, TMDS_shift_green=0, TMDS_shift_blue=0;
reg TMDS_shift_load=0;
always @(posedge clk_TMDS) TMDS_shift_load <= (TMDS_mod10==4'd9);

always @(posedge clk_TMDS)
begin
   TMDS_shift_red   <= TMDS_shift_load ? TMDS_red   : TMDS_shift_red  [9:1];
   TMDS_shift_green <= TMDS_shift_load ? TMDS_green : TMDS_shift_green[9:1];
   TMDS_shift_blue  <= TMDS_shift_load ? TMDS_blue  : TMDS_shift_blue [9:1];   
   TMDS_mod10 <= (TMDS_mod10==4'd9) ? 4'd0 : TMDS_mod10+4'd1;
end

// 6. 차동 신호 생성부
OBUFDS OBUFDS_red  (.I(TMDS_shift_red  [0]), .O(TMDSp[2]), .OB(TMDSn[2]));
OBUFDS OBUFDS_green(.I(TMDS_shift_green[0]), .O(TMDSp[1]), .OB(TMDSn[1]));
OBUFDS OBUFDS_blue (.I(TMDS_shift_blue [0]), .O(TMDSp[0]), .OB(TMDSn[0]));
OBUFDS OBUFDS_clock(.I(pixclk), .O(TMDSp_clock), .OB(TMDSn_clock));

endmodule


// 7. TMDS Encoder
module TMDS_encoder(
   input clk,
   input [7:0] VD,  // video data (red, green or blue)
   input [1:0] CD,  // control data
   input VDE,  // video data enable, to choose between CD (when VDE=0) and VD (when VDE=1)
   output reg [9:0] TMDS = 0
);

wire [3:0] Nb1s = VD[0] + VD[1] + VD[2] + VD[3] + VD[4] + VD[5] + VD[6] + VD[7];
wire XNOR = (Nb1s>4'd4) || (Nb1s==4'd4 && VD[0]==1'b0);
wire [8:0] q_m = {~XNOR, q_m[6:0] ^ VD[7:1] ^ {7{XNOR}}, VD[0]};

reg [3:0] balance_acc = 0;
wire [3:0] balance = q_m[0] + q_m[1] + q_m[2] + q_m[3] + q_m[4] + q_m[5] + q_m[6] + q_m[7] - 4'd4;
wire balance_sign_eq = (balance[3] == balance_acc[3]);
wire invert_q_m = (balance==0 || balance_acc==0) ? ~q_m[8] : balance_sign_eq;
wire [3:0] balance_acc_inc = balance - ({q_m[8] ^ ~balance_sign_eq} & ~(balance==0 || balance_acc==0));
wire [3:0] balance_acc_new = invert_q_m ? balance_acc-balance_acc_inc : balance_acc+balance_acc_inc;
wire [9:0] TMDS_data = {invert_q_m, q_m[8], q_m[7:0] ^ {8{invert_q_m}}};
wire [9:0] TMDS_code = CD[1] ? (CD[0] ? 10'b1010101011 : 10'b0101010100) : (CD[0] ? 10'b0010101011 : 10'b1101010100);

always @(posedge clk) TMDS <= VDE ? TMDS_data : TMDS_code;
always @(posedge clk) balance_acc <= VDE ? balance_acc_new : 4'h0;
endmodule


////////////////////////////////////////////////////////////////////////
