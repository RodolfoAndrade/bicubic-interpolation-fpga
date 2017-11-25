// ----------------------------------------------------------------------
// Copyright (c) 2016, The Regents of the University of California All
// rights reserved.
// 
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
// 
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
// 
//     * Redistributions in binary form must reproduce the above
//       copyright notice, this list of conditions and the following
//       disclaimer in the documentation and/or other materials provided
//       with the distribution.
// 
//     * Neither the name of The Regents of the University of California
//       nor the names of its contributors may be used to endorse or
//       promote products derived from this software without specific
//       prior written permission.
// 
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL REGENTS OF THE
// UNIVERSITY OF CALIFORNIA BE LIABLE FOR ANY DIRECT, INDIRECT,
// INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
// BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
// OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
// ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
// TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE
// USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
// DAMAGE.
// ----------------------------------------------------------------------
//----------------------------------------------------------------------------
// Filename:			chnl_tester.v
// Version:				1.00.a
// Verilog Standard:	Verilog-2001
// Description:			Sample RIFFA channel user module. Designed to exercise
// 						the RIFFA TX and RX interfaces. Receives data on the
//						RX interface and saves the last value received. Sends
//						the same amount of data back on the TX interface. The
//						returned data starts with the last value received, 
//						resets and increments to end with a value equal to the
//						number of (4 byte) words sent back on the TX interface.
// Author:				Matt Jacobsen
// History:				@mattj: Version 2.0
//-----------------------------------------------------------------------------
`timescale 1ns/1ns
module chnl_tester #(
	parameter C_PCI_DATA_WIDTH = 9'd64
)
(
	input CLK,
	input CLK_50,
	input RST,
	output CHNL_RX_CLK, 
	input CHNL_RX, 
	output CHNL_RX_ACK, 
	input CHNL_RX_LAST, 
	input [31:0] CHNL_RX_LEN, 
	input [30:0] CHNL_RX_OFF, 
	input [C_PCI_DATA_WIDTH-1:0] CHNL_RX_DATA, 
	input CHNL_RX_DATA_VALID, 
	output CHNL_RX_DATA_REN,
	
	output CHNL_TX_CLK, 
	output CHNL_TX, 
	input CHNL_TX_ACK, 
	output CHNL_TX_LAST, 
	output [31:0] CHNL_TX_LEN, 
	output [30:0] CHNL_TX_OFF, 
	output [C_PCI_DATA_WIDTH-1:0] CHNL_TX_DATA, 
	output CHNL_TX_DATA_VALID, 
	input CHNL_TX_DATA_REN
);

reg [C_PCI_DATA_WIDTH-1:0] rData={C_PCI_DATA_WIDTH{1'b0}};
reg [C_PCI_DATA_WIDTH-1:0] wData;
reg [31:0] rLen=0;
reg [31:0] rCount=0;
reg [1:0] rState=0;

assign CHNL_RX_CLK = CLK;
assign CHNL_RX_ACK = (rState == 2'd1);
assign CHNL_RX_DATA_REN = (rState == 2'd1);

assign CHNL_TX_CLK = CLK;
assign CHNL_TX = (rState == 2'd3);
assign CHNL_TX_LAST = 1'd1;
assign CHNL_TX_LEN = 4096;//(128*128)/4; // in words
assign CHNL_TX_OFF = 0;
assign CHNL_TX_DATA = wData;
assign CHNL_TX_DATA_VALID = CHNL_TX_DATA_REN & !fifo_is_empty & (rState == 2'd3);

// IMAGE PROCESSING 
reg [31:0] rows, cols;
reg input_valid;
reg info_valid;

always @(posedge CLK or posedge RST) begin
	if (RST) begin
		rLen <= #1 0;
		rCount <= #1 0;
		rState <= #1 0;
		rData <= #1 0;
		input_valid <= 0;
		info_valid <= 0;
		rows <= 0;		
		cols <= 0;
		//wData <= 0;
	end
	else begin
		case (rState)
		
		2'd0: begin // Wait for start of RX, save length
			if (CHNL_RX) begin
				rLen <= #1 CHNL_RX_LEN;
				rCount <= #1 0;
				rState <= #1 2'd1;
				input_valid <= 0;
				info_valid <= 0;
				rows <= 0;
				cols <= 0;
			end
		end
		
		2'd1: begin // Wait for last data in RX, save value
			if (CHNL_RX_DATA_VALID) begin
				rData <= #1 CHNL_RX_DATA;
				if(rCount == 0 ) begin
					info_valid <= 1;
					rows <= CHNL_RX_DATA[31:0];
					cols <= CHNL_RX_DATA[63:32];
				end
				//else if (rCount == 1) begin
					//cols <= CHNL_RX_DATA[9:0];// & 32'h0000__02FF;
				//end
				else begin
					input_valid <= 1;
				end
				rCount <= #1 rCount + (C_PCI_DATA_WIDTH/32);
			end
			else begin
				input_valid <= 0;
			end
			if (rCount >= rLen) begin
				rState <= #1 2'd2;
				input_valid <= 0;
			end
		end
		

		2'd2: begin // Prepare for TX			
			/* O ciclo 3 
			*/
			rData <=  {32'd2, 32'd1};
			rCount <=  32'd2;
			rState <=  2'd3;
		end

		2'd3: begin // Start TX with save length and data value
			if (CHNL_TX_DATA_VALID) begin
				rData <=  {rCount + 2, rCount + 1};
				rCount <=  rCount + (C_PCI_DATA_WIDTH/32);
				if (rCount >= 4096)
					rState <=  2'd0;
			end
		end
		
		endcase
	end
end

reg [31:0] pixel_out;
reg output_valid;
//CHNL_TX_DATA_VALIDwire read_fifo;
wire fifo_is_empty;

//assign read_fifo = CHNL_TX_DATA_VALID;

control_unit c_unit(    
    .clock(CLK_50), 
	 .clock_riffa(CLK),
	 .reset(RST),
    .rows(rows), 
	 .cols(cols),
    .input_valid(input_valid),
	 .info_valid(info_valid),
    .riffa_data_in(rData),
    .pixel_out(pixel_out),
    .output_valid(output_valid)
);

fifo_out fifo_c_unit_to_riffa(
	.data(pixel_out[7:0]),
	.aclr(RST),
	.rdclk(CLK),
	.rdreq(CHNL_TX_DATA_VALID),
	.wrclk(CLK_50),
	.wrreq(output_valid),
	.q(wData),
	.rdempty(fifo_is_empty)
);


endmodule