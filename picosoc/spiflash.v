/*
 *  PicoSoC - A simple example SoC using PicoRV32
 *
 *  Copyright (C) 2017  Clifford Wolf <clifford@clifford.at>
 *
 *  Permission to use, copy, modify, and/or distribute this software for any
 *  purpose with or without fee is hereby granted, provided that the above
 *  copyright notice and this permission notice appear in all copies.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 *  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 *  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 *  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 *  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 *  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 *  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 */

`timescale 1 ns / 1 ps

//
// Simple SPI flash simulation model
//
// This model samples io input signals 1ns before the SPI clock edge and
// updates output signals 1ns after the SPI clock edge.
//
// Supported commands:
//    AB, B9, FF, 03, BB, EB, ED
//
// Well written SPI flash data sheets:
//    Cypress S25FL064L http://www.cypress.com/file/316661/download
//    Cypress S25FL128L http://www.cypress.com/file/316171/download
//
// SPI flash used on iCEBreaker board:
//    https://www.winbond.com/resource-files/w25q128jv%20dtr%20revb%2011042016.pdf
//

module spiflash (
	input csb,
	input sck,
//	inout io0, // MOSI
//	inout io1, // MISO
//	inout io2,
//	inout io3,
	input  wire io0_oe,
	input  wire io1_oe,
	input  wire io2_oe,
	input  wire io3_oe,
	input  wire io0_di,
	input  wire io1_di,
	input  wire io2_di,
	input  wire io3_di,
	output wire io0_dout,
	output wire io1_dout,
	output wire io2_dout,
	output wire io3_dout,
	output reg  [18:0] avs_address      ,
	output reg         avs_read         ,
	input  wire [31:0] avs_readdata     ,
	input  wire        avs_waitrequest  ,
	input  wire        avs_readdatavalid,
	output reg  [1:0]  avs_burstcount
);
  wire clk;

	localparam verbose = 0;
	localparam integer latency = 8;

	reg [7:0] buffer;
	integer bitcount = 0;
	integer bytecount = 0;
	integer dummycount = 0;

	reg [7:0] spi_cmd;
	reg [7:0] xip_cmd = 0;
	reg [23:0] spi_addr;

	reg [7:0] spi_in;
	reg [7:0] spi_out;
	reg spi_io_vld;

	reg powered_up = 0;

	localparam [3:0] mode_spi         = 1;
	localparam [3:0] mode_dspi_rd     = 2;
	localparam [3:0] mode_dspi_wr     = 3;
	localparam [3:0] mode_qspi_rd     = 4;
	localparam [3:0] mode_qspi_wr     = 5;
	localparam [3:0] mode_qspi_ddr_rd = 6;
	localparam [3:0] mode_qspi_ddr_wr = 7;

	reg [3:0] mode = 1;
	reg [3:0] next_mode = 4;

	//	reg io0_oe = 0;
	//	reg io1_oe = 0;
	//	reg io2_oe = 0;
	//	reg io3_oe = 0;
	//
	//	reg io0_dout = 0;
	//	reg io1_dout = 0;
	//	reg io2_dout = 0;
	//	reg io3_dout = 0;

	//	assign #1 io0 = io0_oe ? io0_dout : 1'bz;
	//	assign #1 io1 = io1_oe ? io1_dout : 1'bz;
	//	assign #1 io2 = io2_oe ? io2_dout : 1'bz;
	//	assign #1 io3 = io3_oe ? io3_dout : 1'bz;

	wire io0_delayed;
	wire io1_delayed;
	wire io2_delayed;
	wire io3_delayed;
	
	wire [7:0] buffer_next;

	assign io0_delayed = io0_di;
	assign io1_delayed = io1_di;
	assign io2_delayed = io2_di;
	assign io3_delayed = io3_di;
	
	assign buffer_next = {buffer, io0_di};
	assign clk = sck | csb;

//	assign avs_address = {spi_addr, buffer_next};
//	assign avs_read    = powered_up && spi_cmd == 8'h03 && bytecount == 4;
//	assign avs_burstcount = 0;

// 16 MB (128Mb) Flash
//	reg [7:0] memory [0:16*1024*1024-1];
//
//	reg [1023:0] firmware_file;
//	initial begin
//		if (!$value$plusargs("firmware=%s", firmware_file))
//			firmware_file = "firmware.hex";
//		$readmemh(firmware_file, memory);
//	end

	task spi_action;
		begin
			spi_in <= buffer_next;
			// if (bytecount == 1) begin
			if (bytecount == 0) begin
				// spi_cmd <= buffer;
				spi_cmd <= buffer_next;
				if (spi_cmd == 8'hab) // power up
					powered_up <= 1;
				if (spi_cmd == 8'hb9) // power down
					powered_up <= 0;
				if (spi_cmd == 8'hff) // quit qpi mode
					xip_cmd <= 0;
			end
			if (powered_up && spi_cmd == 'h03) begin // read data bytes
				if (bytecount == 1)
					spi_addr[23:16] <= buffer_next;
				else if (bytecount == 2) begin
					spi_addr[15:8] <= buffer_next;
				end
				else if (bytecount == 3) begin
					spi_addr[7:0] <= buffer_next;
					avs_address <= {spi_addr, buffer_next};
					avs_read <= 1;
					avs_burstcount <= 0;
				end
				else if (bytecount > 3) begin
//					buffer <= memory[spi_addr];
					avs_address <= spi_addr;
					avs_read <= 1;
					avs_burstcount <= 0;
					spi_addr <= spi_addr + 1;
				end
				if (avs_read && avs_readdatavalid) begin
					avs_read <= 0;
				end
			end
			if (powered_up && spi_cmd == 'hbb) begin // fast read dual i/o
				if (bytecount == 1)
					mode <= mode_dspi_rd;
				if (bytecount == 2)
					spi_addr[23:16] <= buffer_next;
				if (bytecount == 3)
					spi_addr[15:8] <= buffer_next;
				if (bytecount == 4)
					spi_addr[7:0] <= buffer_next;
				if (bytecount == 5) begin
					xip_cmd <= (buffer_next == 8'ha5) ? spi_cmd : 8'h00;
					mode <= mode_dspi_wr;
					dummycount <= latency;
				end
				if (bytecount >= 5) begin
					//buffer <= memory[spi_addr];
	//					avs_address <= spi_addr;
					spi_addr <= spi_addr + 1;
				end
			end
			if (powered_up && spi_cmd == 'heb) begin // fast read quad i/o
				if (bytecount == 1)
					mode <= mode_qspi_rd;
				if (bytecount == 2)
					spi_addr[23:16] <= buffer_next;
				if (bytecount == 3)
					spi_addr[15:8] <= buffer_next;
				if (bytecount == 4)
					spi_addr[7:0] <= buffer_next;
				if (bytecount == 5) begin
					xip_cmd <= (buffer_next == 8'ha5) ? spi_cmd : 8'h00;
					mode <= mode_qspi_wr;
					dummycount <= latency;
				end
				if (bytecount >= 5) begin
					//buffer <= memory[spi_addr];
	//					avs_address <= spi_addr;
					spi_addr <= spi_addr + 1;
				end
			end
			if (powered_up && spi_cmd == 'hed) begin
				if (bytecount == 1)
					next_mode <= mode_qspi_ddr_rd;
				if (bytecount == 2)
					spi_addr[23:16] <= buffer_next;
				if (bytecount == 3)
					spi_addr[15:8] <= buffer_next;
				if (bytecount == 4)
					spi_addr[7:0] <= buffer_next;
				if (bytecount == 5) begin
					xip_cmd <= (buffer_next == 8'ha5) ? spi_cmd : 8'h00;
					mode <= mode_qspi_ddr_wr;
					dummycount <= latency;
				end
				if (bytecount >= 5) begin
					//buffer <= memory[spi_addr];
	//					avs_address <= spi_addr;
					spi_addr <= spi_addr + 1;
				end
			end

			spi_out <= buffer;
			spi_io_vld <= 1;

			if (verbose) begin
				if (bytecount == 1)
					$write("<SPI-START>");
				$write("<SPI:%02x:%02x>", spi_in, spi_out);
			end

		end
	endtask

	always @(posedge clk) begin
		if (csb) begin
			buffer <= 0;
			bitcount <= 0;
			bytecount <= 0;
			mode <= mode_spi;
			avs_read <= 0;
			avs_address <= 0;
			avs_burstcount <= 0;
		end 
		else if (!csb) begin
			if (dummycount > 0) begin
				dummycount <= dummycount - 1;
			end else
			case (mode)
				mode_spi: begin
					buffer <= {buffer, io0_di};
					if (bitcount == 7) begin
						bitcount <= 0;
						bytecount <= bytecount + 1;
						spi_action;
					end
					else
						bitcount <= bitcount + 1;
				end
				mode_dspi_rd, mode_dspi_wr: begin
					buffer <= {buffer, io1_di, io0_di};
					if (bitcount == 6) begin
						bitcount <= 0;
						bytecount <= bytecount + 1;
						spi_action;
					end
					else
						bitcount <= bitcount + 2;
				end
				mode_qspi_rd, mode_qspi_wr: begin
					buffer <= {buffer, io3_di, io2_di, io1_di, io0_di};
					if (bitcount == 4) begin
						bitcount <= 0;
						bytecount <= bytecount + 1;
						spi_action;
					end
					else
						bitcount <= bitcount + 4;
				end
			endcase
		end
		else if (xip_cmd) begin
			buffer <= xip_cmd;
			bitcount <= 0;
			bytecount <= 1;
			spi_action;
		end
//	end
//
//	always @(posedge clk) begin
//		if (avs_read && avs_readdatavalid) begin
//			avs_read <= 0;
//			buffer <= avs_readdata;
//		end
	end
	
endmodule
