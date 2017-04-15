//
// This is an interface for the simple CRC Block
//

module crc(crc_if.dp m);

logic [31:0]CRC_CTRL;
logic [31:0]CRC_GPOLY;
logic [31:0]CRC_DATA, sel_data_rd;
logic [31:0]f_data_rd, checksum, data;
integer i;
bit checkpoint;
parameter mask = 32'h0000FFFF;

typedef struct {
	bit WAS;
	bit TCRC;
	bit FXOR;	
	logic [1:0]TOTR;
	logic [1:0]TOT;
	} control;

control ctrl;
	
assign ctrl.WAS = CRC_CTRL[25];
assign ctrl.TCRC = CRC_CTRL[24];
assign ctrl.FXOR = CRC_CTRL[26];	
assign ctrl.TOTR = CRC_CTRL[29:28];
assign ctrl.TOT = CRC_CTRL[31:30];

assign read_addr = m.addr;

////////////  OUTPUT  \\\\\\\\\\\\\\\\\\\\\\\

assign m.data_rd = (m.RW)? 0: f_data_rd;
assign f_data_rd = sel_data_rd;


always @(*) begin
	case(m.addr)

	'h4003_2008:
		sel_data_rd = CRC_CTRL;
	'h4003_2004:
		sel_data_rd = CRC_GPOLY;
	'h4003_2000:begin
			case(ctrl.TOTR)
				'b00:
				if(ctrl.FXOR)
					sel_data_rd = invert(CRC_DATA, ctrl.FXOR, ctrl.TCRC);
					      else 
					sel_data_rd = CRC_DATA;
				'b01:
				if(ctrl.FXOR)
					sel_data_rd = transpose_01(invert(CRC_DATA, ctrl.FXOR, ctrl.TCRC));
					      else 
					sel_data_rd =  transpose_01(CRC_DATA);
				'b10:
				if(ctrl.FXOR)
					sel_data_rd = transpose_10(invert(CRC_DATA, ctrl.FXOR, ctrl.TCRC));
					      else 
					sel_data_rd = transpose_10(CRC_DATA);
				'b11:
				if(ctrl.FXOR)
					sel_data_rd = transpose_11(invert(CRC_DATA, ctrl.FXOR, ctrl.TCRC));
					      else 
					sel_data_rd = transpose_11(CRC_DATA);
			endcase
		      end
	endcase		
end

always @(posedge m.clk or posedge m.rst) begin
	if (m.rst) begin
		CRC_CTRL = 'h0000_0000;
		CRC_GPOLY = 'h0000_1021;
		CRC_DATA = 'hFFFF_FFFF;
		checksum = 'hFFFF_FFFF;
	end
	else
		begin
		if(m.Sel) begin
			if(m.RW) begin
				case(m.addr) 
					'h4003_2008: CRC_CTRL = m.data_wr;
 	   				'h4003_2004: CRC_GPOLY = m.data_wr;
					'h4003_2000: begin
							case(ctrl.WAS)
								'b0:begin 
									case(ctrl.TOT)
											'b00:
												data = m.data_wr;
											'b01:
												data = transpose_01(m.data_wr);
											'b10:
												data = transpose_10(m.data_wr);
											'b11:
												data = transpose_11(m.data_wr);
									endcase
///////////////////////// CRC ENGINE LOGIC \\\\\\\\\\\\\\\\\\\\\

									for(i = 0; i < 32; i=i+1) begin
										case(ctrl.TCRC)
										     'b1:
											if(checksum[31]) begin
												checksum = {checksum[30:0], data[31]};
												checksum = checksum ^ CRC_GPOLY;
												end
											else begin
												checksum = {checksum[30:0], data[31]};
												checksum = checksum; 
												end
										     'b0:
											if(checksum[15]) begin
												checksum = {checksum[30:0], data[31]};
												checksum = checksum ^ CRC_GPOLY;
												checksum = {16'h0000, checksum[15:0]};
												end
											else begin
												checksum = {checksum[30:0], data[31]};
												checksum = {16'h0000, checksum[15:0]};;
												end
										endcase
												data = {data[30:0],1'b0};											
									end
									CRC_DATA = checksum;
								     end
								'b1: begin 
									case(ctrl.TOT)
											'b00:
												CRC_DATA = m.data_wr;
											'b01:
												CRC_DATA = transpose_01(m.data_wr);
											'b10:
												CRC_DATA = transpose_10(m.data_wr);
											'b11:
												CRC_DATA = transpose_11(m.data_wr);
									endcase
								     	checksum = CRC_DATA; 
								       end
						     	endcase
						     end 						     
					 default: begin CRC_CTRL = CRC_CTRL;
			   		   	  	CRC_GPOLY = CRC_GPOLY;
			   	 	   	  	CRC_DATA = CRC_DATA;
						  end
			        endcase
		      	end
	   		else begin 	   
				CRC_CTRL = CRC_CTRL;
			   	CRC_GPOLY = CRC_GPOLY;
			   	CRC_DATA = CRC_DATA;	    
			end
		 end
	         else begin
			CRC_CTRL = CRC_CTRL;
			CRC_GPOLY = CRC_GPOLY;
			CRC_DATA = CRC_DATA;
	 	 end
	end
end

/////////////// FUNCTIONS TO TRANPOSE DATA
function [31:0] transpose_01 (input [31:0] op);
	      transpose_01 = {bit_flip(op[31:24]), bit_flip(op[23:16]), bit_flip(op[15:8]), bit_flip(op[7:0])};
endfunction

function [31:0] transpose_10 (input [31:0] op);
	      transpose_10 = {bit_flip(op[7:0]), bit_flip(op[15:8]), bit_flip(op[23:16]), bit_flip(op[31:24])};
endfunction

function [31:0] transpose_11 (input [31:0] op);
	      transpose_11 = {op[7:0], op[15:8], op[23:16], op[31:24]};
endfunction

function [7:0] bit_flip(input [7:0]bit_f);
	 bit_flip = {bit_f[0], bit_f[1], bit_f[2], bit_f[3], bit_f[4], bit_f[5], bit_f[6], bit_f[7]};
endfunction

function [31:0] invert(input [31:0]raw, input FXOR, input TCRC);
	 invert = (FXOR)? (TCRC)? ~(raw) : (raw^mask) : raw;
	
endfunction 

endmodule
