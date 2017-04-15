///////////////////////////////////////////////////////////////////////
//     S H A N T A N U                                               //
//			T E L H A R K A R                            //
//                                                                   //
//                                                                   //
//					0 1 0 8 0 9 3 0 5            //
///////////////////////////////////////////////////////////////////////
module noc (nocif.md x,crc_if.dn y);


//Structure to save all input data.
typedef struct packed{
            logic [2:0] code;
            logic Len;
            logic Ones;
            logic [2:0] AddrLen;
            logic [7:0] SOURCEID;
            logic [7:0] addr3;
            logic [7:0] addr2;
            logic [7:0] addr1;
            logic [7:0] addr0; 
            logic [7:0] length1;
            logic [7:0] length0; 
            logic [7:0] data3;
            logic [7:0] data2; 
            logic [7:0] data1;
            logic [7:0] data0;         
} DATA_FOR_CRC;

DATA_FOR_CRC my_packet;

DATA_FOR_CRC bunch;

typedef struct packed{
            logic [31:0]link;
            logic [31:0]seed;
            logic [31:0]ctrl;
            logic [31:0]poly;
            logic [31:0]data;
            logic [31:0]len;
	        
} CHAIN_BLOCK;

CHAIN_BLOCK cb;

//Indicates burst Read.
logic [1:0]burst_mode;

//Save 32-bit CRC Read data into 1 byte entries.
reg [7:0]save0, save1, save2, save3;
logic [31:0]CRC_Read, CRC_Write;

//Important Signals.
logic pushin, pushin_d, wr_resp, write_en, read_en, full, empty, pushout;

//Decide address for CRC.
wire [3:0]make_addr = {my_packet.AddrLen, my_packet.Ones};

//Data to be written into CRC.
wire [31:0]write_data = {my_packet.data3, my_packet.data2, my_packet.data1, my_packet.data0};
reg [31:0]member; 

wire [15:0]data_length = {my_packet.length1, my_packet.length0};

//FIFO input output.
wire [42:0] datain, dataout;

reg [7:0] ReturnID;


//Various counters.
int counter,counterl,count_write, burst_read_count, burst_write_count, countresp, countresp_burst, chain_count;

//Master registers required
logic [31:0]chain, start_chain;


//States for 3 State Machines.
enum int {Start=0, SourceID, idlestate, address, idlestate2, LenField, write_stage} state;
enum int {check=0, read, burst_read, write} state2;
enum int {check_fifo=0, latch_fifo, cmd, RetID, resp0, write_resp, the_end, chain_req/*7*/, chain_source/*8*/, chain_addr0/*9*/, chain_addr1/*A*/, chain_addr2/*B*/, chain_addr3/*C*/, chain_len/*D*/, wait_for_resp/*E*/, get_link/*F*/, get_seed/*10*/,get_poly/*11*/, get_ctrl,get_data, get_len, data_req, wait_for_crc, send_data} state3;
enum int {check_d, cmd_d, source_d, d0, d1, d2, d3, end_d} state4;

//FIFO input.
assign datain = {wr_resp,burst_mode,ReturnID,CRC_Read};

always @ (posedge x.clk) begin
if (x.rst) begin
    		state <= Start;
		state2 <= check;
		state3 <= check_fifo;
		bunch <= 96'h0000_00000000_00000000_0000;
		x.CmdR <= 1'b0;
		x.DataR <= 8'b00000000;
		chain_count <= 8'h00;
end
else begin 
    case (state)
        Start:begin
            	pushin <= 0;
		if (x.CmdW & x.DataW [7:5] == 3'b001 | x.CmdW & x.DataW [7:5] == 3'b011 ) begin
                counter <= 0;
                counterl <= 0;
                count_write <= 0;
                {bunch.code,bunch.Len,bunch.Ones,bunch.AddrLen} <= x.DataW;
                state <= SourceID;
            	end
              else
              begin
              	state <= Start;
              end
              end
        SourceID:begin 
                    if ({x.CmdW,x.DataW[7:5]}==4'b1000)
                    begin
                        state <= idlestate;
                    end
                    else
                    begin
                        bunch.SOURCEID <= x.DataW;
                        state <= address;
                    end
                end
        idlestate:begin
                        if ({x.CmdW,x.DataW[7:5]}==4'b1000)
                        begin
                            state <= idlestate;
                        end
                        else
                        begin
                            bunch.SOURCEID <= x.DataW;
                            state <= address;
                        end
                  end
        address:begin
                if ({x.CmdW,x.DataW[7:5]}==4'b1000)
                begin
                    state <= idlestate2;
                end
                else
                begin
                    if (counter == 0)
                    bunch.addr0 <= x.DataW;
                    else if (counter == 1)
                    bunch.addr1 <= x.DataW;
                    else if (counter == 2)
                    bunch.addr2 <= x.DataW;
                    else
                    bunch.addr3 <= x.DataW;
                               
                    counter <= counter + 1;

                    if (counter < bunch.AddrLen)
                    begin
                        state <= address;
                    end
                    else
                    begin
                        state <= LenField;
                    end
                end
            end 
        idlestate2:begin
                        if ({x.CmdW,x.DataW[7:5]}==4'b1000)
                        begin
                            state <= idlestate2;
                        end
                        else
                        begin
 				if (counter == 0)
                    		bunch.addr0 <= x.DataW;
                    		else if (counter == 1)
                    		bunch.addr1 <= x.DataW;
                    		else if (counter == 2)
                   		bunch.addr2 <= x.DataW;
                    		else
                   		bunch.addr3 <= x.DataW;
                               
                    		counter <= counter + 1;		

                            	if (counter < bunch.AddrLen)
                            	begin
                            	state <= idlestate2;
                            	end
                            	else
                            	begin                       
                            	state <= LenField;
                            	end
                        end
                    end          
                   
        LenField:
                    begin
                            if (counterl == 0)
                                bunch.length0 <= x.DataW;
                            else
                                bunch.length1 <= x.DataW;
                               
                            counterl <= counterl + 1;

                            if (counterl < bunch[92])
                            begin
                                state <= LenField;
                            end
                            else
                            begin
                                if (bunch.code == 3'b011)
                                begin
				    state <= write_stage;
                                end
                                else
                                begin    
				    pushin <= 1'b1;
                                    state <= Start;
                                end
                            end
                    end
        write_stage:
                begin
                    if (count_write == 0)
                    bunch.data0 <= x.DataW;
                    else if (count_write == 1)
                    bunch.data1 <= x.DataW;
                    else if (count_write == 2)
                    bunch.data2 <= x.DataW;
                    else
                    bunch.data3 <= x.DataW;
                               
                    count_write <= count_write + 1;

                    if (count_write<3)
                    begin
                        state <= write_stage;
                    end
                    else
                    begin
			bunch.data3 <= x.DataW;
                        pushin <= 1'b1;
                        state <= Start;
                    end
                end
    endcase






/*///////////////////////////////////////////////////////////////////////////////////////////////////////////////
			  		FSM - 2		

//////////////////////////////////////////////////////////////////////////////////////////////////////////////*/
	case(state2)
		check: begin
			y.Sel <= 1'b0;
			write_en <= 1'b0;
			if (pushin) begin
				if(bunch[95:93] == 3'b001) begin
				my_packet <= bunch;
				state2 <= read;
				end
				else if (bunch[95:93] == 3'b011) begin
				my_packet <= bunch;
				state2 <= write;
				end
				else
				begin 			
				state2 <= check;
				end
			end
			else begin	
				my_packet = 0;
				state2 <= check;
		end
		end			
		read: begin
			begin
				case(make_addr)
					4'b0000: y.addr <= {24'h000000,my_packet.addr0};
					4'b0001: y.addr <= {24'hFFFFFF,my_packet.addr0};
					///////////////////////////////////////////////////////////////////////////
					4'b0010: y.addr <= {16'h0000,my_packet.addr1, my_packet.addr0};
					4'b0011: y.addr <= {16'hFFFF,my_packet.addr1, my_packet.addr0};
					//////////////////////////////////////////////////////////////////////////
					4'b0100: y.addr <= {8'h00,my_packet.addr2,my_packet.addr1, my_packet.addr0};
					4'b0101: y.addr <= {8'hFF,my_packet.addr2,my_packet.addr1, my_packet.addr0};
					//////////////////////////////////////////////////////////////////////////
					4'b0110: y.addr <= {my_packet.addr3,my_packet.addr2,my_packet.addr1, my_packet.addr0};
					4'b0111: y.addr <= {my_packet.addr3,my_packet.addr2,my_packet.addr1, my_packet.addr0};
					/////////////////////////////////////////////////////////////////////////
					default: y.addr <= 0;
				endcase
				y.RW <= 1'b0;
				y.Sel <= 1'b1;
				ReturnID <= my_packet.SOURCEID;
				state2 <= burst_read;
			end
		end
		burst_read:begin
			wr_resp <= 1'b0;
			CRC_Read <= y.data_rd;
			write_en <= 1'b1;
			if(data_length == 16'h0004) burst_mode <= 2'b00; 
			else if(data_length == 16'h0008) burst_mode <= 2'b01;
			else if(data_length == 16'h000C) burst_mode <= 2'b10;
			if(data_length == 16'h0004) begin
			state2 <= check;
			burst_read_count <= 0;
			y.addr <= 32'h4003_2000;
			y.RW <= 1'b0;
			y.Sel <= 1'b0;
			end
			else if(data_length == 16'h0008 && burst_read_count == 1) begin
			state2 <= check;
			burst_read_count <= 0;
			y.addr <= 32'h4003_2000;
			y.RW <= 1'b0;
			y.Sel <= 1'b0;
			end
			else if(data_length == 16'h000C && burst_read_count == 2) begin
			state2 <= check;
			burst_read_count <= 0;
			y.addr <= 32'h4003_2000;
			y.RW <= 1'b0;
			y.Sel <= 1'b0;
			end
			else begin
			y.RW <= 1'b0;
			y.Sel <= 1'b1;
			y.addr <= y.addr + 4'b0100;
			state2 <= burst_read;
			burst_read_count <= burst_read_count + 1;
			end
		end
			
		write: begin
			if(my_packet.addr0 == 8'hF0) begin
				chain <= write_data;
				state2 <= check;
				wr_resp <= 1'b1;
			end
			else if(my_packet.addr0 == 8'hF4) begin
				start_chain <= write_data;
				state2 <= check;
				wr_resp <= 1'b1;
			end
			else begin
			case(make_addr)
				4'b0000: y.addr <= {24'h000000,my_packet.addr0};
				4'b0001: y.addr <= {24'hFFFFFF,my_packet.addr0};
				///////////////////////////////////////////////////////////////////////////
				4'b0010: y.addr <= {16'h0000,my_packet.addr1, my_packet.addr0};
				4'b0011: y.addr <= {16'hFFFF,my_packet.addr1, my_packet.addr0};
				//////////////////////////////////////////////////////////////////////////
				4'b0100: y.addr <= {8'h00,my_packet.addr2,my_packet.addr1, my_packet.addr0};
				4'b0101: y.addr <= {8'hFF,my_packet.addr2,my_packet.addr1, my_packet.addr0};
				//////////////////////////////////////////////////////////////////////////
				4'b0110: y.addr <= {my_packet.addr3,my_packet.addr2,my_packet.addr1, my_packet.addr0};
				4'b0111: y.addr <= {my_packet.addr3,my_packet.addr2,my_packet.addr1, my_packet.addr0};
				/////////////////////////////////////////////////////////////////////////
				default: y.addr <= 0;
			endcase
			y.RW <= 1'b1;
			write_en <= 1'b1;
			y.Sel <= 1'b1;
			y.data_wr <= write_data;
			state2 <= check;
			wr_resp <= 1'b1;
			end
		end
		default: begin
				state2 <= check;
				y.RW <= 0;
				y.Sel <= 0;
				y.addr <= 0;
				y.data_wr <= 0;
				y.addr <= 0;
				wr_resp <= 1'b0;
				write_en <= 1'b1;
			end
	endcase

/*///////////////////////////////////////////////////////////////////////////////////////////////////////////////
			  		FSM - 3		
//////////////////////////////////////////////////////////////////////////////////////////////////////////////*/



		case(state3)
			check_fifo: begin
				countresp <= 0;
				x.CmdR <= 1'b1;
				x.DataR <= 8'b00000000;

				if(empty && start_chain != 32'h0000_0000) begin
				state3 <= chain_source;
				x.CmdR <= 1'b1;
				x.DataR <= 8'h23;
				read_en <= 1'b0;
				end
				else if(empty && start_chain == 32'h0000_0000) begin
				state3 <= check_fifo;
				read_en <= 1'b0;
				end
				else if(!empty) begin
				state3 <= latch_fifo;
				read_en <= 1'b1;
				end
			end
			//FIFO input.
			//assign datain = {wr_resp,burst_mode,ReturnID,CRC_Read};

			latch_fifo: begin
				read_en <= 1'b0;	
				state3 <= cmd;
			end

			cmd: begin
				if(dataout[42]) begin
				x.CmdR <= 1'b1;
				x.DataR <= 8'b10000000;
			        end
				else begin
				x.CmdR <= 1'b1;
				x.DataR <= 8'b01000000;	
				end	
				state3 <= RetID;						
			end

			RetID: begin
				//read_en = 1'b0;
				x.CmdR <= 1'b0;
				x.DataR <= dataout[39:32];
				save3 <= dataout[31:24];
				save2 <= dataout[23:16];
				save1 <= dataout[15:8];
				save0 <= dataout[7:0];
				if(dataout[42])					
					state3 <= check_fifo;
				else
					state3 <= resp0;
			end
			resp0:begin
				if (countresp == 3)begin
				countresp <= 0;
				x.DataR <= save3;
				countresp_burst <= countresp_burst + 1;
				if(countresp_burst<dataout[41:40])
				state3 <= resp0;
				else begin state3 <= the_end;
				end

				if(dataout[41]|dataout[40]) begin
				save3 <= dataout[31:24];
				save2 <= dataout[23:16];
				save1 <= dataout[15:8];
				save0 <= dataout[7:0];
				end
				else begin
				save3 <= 0;
				save2 <= 0;
				save1 <= 0;
				save0 <= 0;
				end				
				end
				////////////////////////////
				else if (countresp == 2)begin
				countresp <= countresp + 1;
				x.DataR <= save2;
				state3 <= resp0;
				read_en <= 1'b0; 
				end
				///////////////////////////
				else if (countresp == 1)begin
				countresp <= countresp + 1;
				x.DataR <= save1;
				state3 <= resp0;
				if(countresp_burst<2)
				read_en <= 1'b1;
				else
				read_en <= 1'b0;
				end
				///////////////////////////
				else begin
				state3 <= resp0;
				countresp <= countresp + 1;
				x.DataR <= save0;			
				end
			end

			the_end: begin
				x.CmdR <= 1'b1;
				x.DataR <= 8'b11111111;	
				state3 <= check_fifo;
				countresp_burst <= 1'b0;
				end
//////////////////////////////////////////////////////////////////////////////
			//give write resp
			chain_source: begin
				x.CmdR <= 1'b0;
				x.DataR <= 8'h25; 
				state3 <= chain_addr0;
			end
			chain_addr0: begin
				x.CmdR <= 1'b0;
				x.DataR <= chain[7:0];	 
				state3 <= chain_addr1;
			end
			chain_addr1: begin
				x.CmdR <= 1'b0;
				x.DataR <= chain[15:8];	 
				state3 <= chain_addr2;
			end
			chain_addr2: begin
				x.CmdR <= 1'b0;
				x.DataR <= chain[23:16];	 
				state3 <= chain_addr3;
			end
			chain_addr3: begin
				x.CmdR <= 1'b0;
				x.DataR <= chain[31:24];	 
				state3 <= chain_len;
			end
			chain_len: begin
				x.DataR <= 8'h18;
				state3 <= wait_for_resp;		
			end
			wait_for_resp: begin
				x.CmdR <= 1'b1;
				x.DataR <= 0;
				if(x.DataW == 8'h25)
					state3 <= get_link;
			end
			get_link: begin
				get_link_data(get_link, get_seed);
                   	 end
			get_seed: begin
				get_seed_data(get_seed, get_ctrl);
			end
			get_ctrl: begin
				get_ctrl_data(get_ctrl, get_poly);
                   	end
			get_poly: begin
				get_poly_data(get_poly, get_data);
			end
			get_data: begin
				get_data_data(get_data, get_len);
                   	end
			get_len: begin
				get_len_data(get_len, data_req);
			end
			data_req: begin
				request_data(data_req, wait_for_crc);
				pushin_d <= 1'b1;
			end
			wait_for_crc: begin
				x.CmdR <= 1'b1;
				x.DataR <= 0;
				pushin_d <= 1'b0;
				if(pushout) begin
					state3 <= send_data;
				end
				else
					state3 <= wait_for_crc;
			end
			send_data: begin
				
			//send data to memory
			//get next link
			
			end
			endcase
			
////////////////////////////// FSM-4 \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
	
			case(state4)
			check_d: begin
			if(pushin_d)
			state4 <= cmd_d;
			else
			state4 <= check_d;			
			end

			cmd_d: begin
			
			if(x.DataW == 8'h40)
			state4 <= source_d;
			else
			if (pushin_d)
			state4 <= cmd_d;
			else begin
			state4 <= check_d;
			//give write resp
			//write-back;
			pushout <= 1'b1;
			end
			end

			source_d: begin
			if(x.DataW == 8'h25)
			state4 <= d0;
			else
			state4 <= source_d;
			end

			d0: begin
			if(x.CmdW)
			state4 <= cmd_d;
			else begin
			CRC_Write[7:0] <= x.DataW;
			state4 <= d1;
			end
			end

			d1: begin
			CRC_Write[15:8] <= x.DataW;
			state4 <= d2;
			end
			
			d2: begin
			CRC_Write[23:16] <= x.DataW;
			state4 <= d3;
			end

			d3: begin
			state4 <= d0;
			CRC_Write[31:24] <= x.DataW;

			load:begin
		    	y.Sel <= 1'b1;
		    	y.RW <= 1'b1;
		    	y.addr <= 32'h4003_2008;
		    	y.data_wr <= CRC_Write;
			if(x.CmdW)
			state4 <= cmd_d;
			else begin
			CRC_Write[7:0] <= x.DataW;
			state4 <= d1;
			end
			end
			end
		endcase
			
	end

end
fifo f(write_en,x.rst,full,empty,x.clk,read_en,datain,dataout);

task get_link_data(input int current_state, input int next_state);
                    chain_count <= chain_count + 1;
                    if (chain_count == 0)
                    cb.link[7:0] <= x.DataW;
                    else if (chain_count == 1)begin
                    cb.link[15:8]  <= x.DataW;
		    y.RW <= 1'b1;
		    y.Sel <= 1'b1;
		    y.addr <= 32'h4003_2008;
		    y.data_wr <= 32'h0000_0040;
		    end
                    else if (chain_count == 2) begin
                    cb.link[23:16]  <= x.DataW;
		    end
                    else begin
                    cb.link[31:24]  <= x.DataW;
		    chain_count <= 0;
		    end
		    
                    if (chain_count<3)
                    begin
                       state3 <= current_state;
                    end
                    else
                    begin
                        state3 <= next_state;
		    end
endtask

task get_seed_data(input int current_state, input int next_state);
                    chain_count <= chain_count + 1;
                    if (chain_count == 0)
                    cb.seed[7:0] <= x.DataW;
                    else if (chain_count == 1)
                    cb.seed[15:8]  <= x.DataW;
                    else if (chain_count == 2) begin
                    cb.seed[23:16]  <= x.DataW;
		    //y.addr <= 32'h4003_2000; link addr and data
		    end
                    else begin
                    cb.seed[31:24]  <= x.DataW;
		    chain_count <= 0;
		    //y.data_wr <= cb.seed;
		    end
		    
                    if (chain_count<3)
                    begin
                       state3 <= current_state;
                    end
                    else
                    begin
                        state3 <= next_state;
		    end
endtask


task get_ctrl_data(input int current_state, input int next_state);
                    chain_count <= chain_count + 1;
                    if (chain_count == 0)
                    cb.ctrl[7:0] <= x.DataW;
                    else if (chain_count == 1)
                    cb.ctrl[15:8]  <= x.DataW;
                    else if (chain_count == 2) begin
                    cb.ctrl[23:16]  <= x.DataW;
		    y.Sel <= 1'b1;
		    y.addr <= 32'h4003_2008;
		    y.data_wr <= cb.seed;
		    end
                    else begin
                    cb.ctrl[31:24]  <= x.DataW;
		    chain_count <= 0;
		    end
		    
                    if (chain_count<3)
                    begin
                       state3 <= current_state;
                    end
                    else
                    begin
                        state3 <= next_state;
		    end
endtask

task get_poly_data(input int current_state, input int next_state);
                    chain_count <= chain_count + 1;
                    if (chain_count == 0)
                    cb.poly[7:0] <= x.DataW;
                    else if (chain_count == 1)
                    cb.poly[15:8]  <= x.DataW;
                    else if (chain_count == 2) begin
                    cb.poly[23:16]  <= x.DataW;
		    y.Sel <= 1'b1;
		    y.addr <= 32'h4003_2008;
		    y.data_wr <= cb.ctrl;
		    end
                    else begin
                    cb.poly[31:24]  <= x.DataW;
		    chain_count <= 0;
		    end
		    
                    if (chain_count<3)
                    begin
                       state3 <= current_state;
                    end
                    else
                    begin
                        state3 <= next_state;
		    end
endtask

task get_data_data(input int current_state, input int next_state);
                    chain_count <= chain_count + 1;
                    if (chain_count == 0)
                    cb.data[7:0] <= x.DataW;
                    else if (chain_count == 1)
                    cb.data[15:8]  <= x.DataW;
                    else if (chain_count == 2) begin
                    cb.data[23:16]  <= x.DataW;
		    y.Sel <= 1'b1;
		    y.addr <= 32'h4003_2004;
		    y.data_wr <= cb.poly;
		    end
                    else begin
                    cb.data[31:24]  <= x.DataW;
		    chain_count <= 0;
		    end
		    
                    if (chain_count<3)
                    begin
                       state3 <= current_state;
                    end
                    else
                    begin
                        state3 <= next_state;
		    end
endtask

task get_len_data(input int current_state, input int next_state);
                    chain_count <= chain_count + 1;
                    if (chain_count == 0)
                    cb.len[7:0] <= x.DataW;
                    else if (chain_count == 1)
                    cb.len[15:8]  <= x.DataW;
                    else if (chain_count == 2)
                    cb.len[23:16]  <= x.DataW;
                    else begin
                    cb.len[31:24]  <= x.DataW;
		    chain_count <= 0;
		    end
		    
                    if (chain_count<3)
                    begin
                       state3 <= current_state;
                    end
                    else
                    begin
                        state3 <= next_state;
		    end
endtask

task request_data(input int current_state, input int next_state);
                    if (chain_count == 0) begin
		    x.CmdR <=1'b1;
	    	    x.DataR <= 8'h23;
                    chain_count <= chain_count + 1;
                    state3 <= current_state;
		    end

                    else if (chain_count == 1) begin
		    x.CmdR <= 1'b0;
		    x.DataR <= 8'h25;
                    chain_count <= chain_count + 1;
                    state3 <= current_state;
		    end

                    else if (chain_count == 2)begin
		    x.DataR <= cb.data[7:0];
                    chain_count <= chain_count + 1;
                    state3 <= current_state;
		    end

                    else if (chain_count == 3)begin
		    x.DataR <= cb.data[15:8];
                    chain_count <= chain_count + 1;
                    state3 <= current_state;
		    end

                    else if (chain_count == 4)begin
		    x.DataR <= cb.data[23:16];
                    chain_count <= chain_count + 1;
                    state3 <= current_state;
		    end

                    else if (chain_count == 5)begin
		    x.DataR <= cb.data[31:24];
                    chain_count <= chain_count + 1;
                    state3 <= current_state;
		    end

                    else begin
		    if(cb.len > 8'h80) begin
		    x.DataR <= 8'h80;
		    cb.len <= cb.len - 8'h80;
                    state3 <= current_state;
		    chain_count <= 0;
		    end

		    else begin
		    x.DataR <= cb.len;
                    chain_count <= chain_count + 1;
                    state3 <= next_state;
		    end
		    end
endtask
endmodule


////////////////////////////////////////////////////////
module fifo (wr_en,reset,full,empty,clk,rd_en,data_in,data_out);
parameter width=43;
parameter depth=100;

input wr_en,rd_en,reset,clk;
output full,empty;
input [width-1:0] data_in;
output reg [width-1:0] data_out;
reg  [width-1 :0 ] data_mem [depth-1 : 0 ];
reg [width-1 :0 ] wr_ptr,rd_ptr;

wire [42:0] test_mem0,test_mem1,test_mem2,test_mem3,test_mem6, test_mem10,test_mem11;
assign test_mem0 = data_mem[0];
assign test_mem1 = data_mem[1];
assign test_mem2 = data_mem[2];
assign test_mem3 = data_mem[3];
assign test_mem10 = data_mem[10];
assign test_mem11 = data_mem[11];
assign test_mem6 = data_mem[6];					


assign full = (rd_ptr == wr_ptr +1);
assign empty = (rd_ptr == wr_ptr);

always @ (posedge clk,posedge reset)
begin
	if (reset)
	begin
		wr_ptr <= 0;
		rd_ptr <= 0;
		data_out <= 0;
	end
	else
	begin
		if (rd_en && !empty)
		begin
			data_out <= data_mem[rd_ptr];
			if(rd_ptr < 99)
			rd_ptr <= rd_ptr +1;
			else
			rd_ptr <= 0;
		end
		else
		begin
			data_out <= data_out;
			rd_ptr <= rd_ptr;
		end
		if (wr_en && !full)
		begin
			data_mem[wr_ptr] <= data_in;
			if(wr_ptr < 99)
			wr_ptr <= wr_ptr +1;
			else
			wr_ptr <= 0;
		end
		else
		begin
			data_mem[wr_ptr] <= data_mem[wr_ptr];
			wr_ptr <= wr_ptr;
		end
	end
end

endmodule






















