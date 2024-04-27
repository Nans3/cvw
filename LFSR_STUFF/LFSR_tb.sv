module stimulus ();
//tested
   logic  clock;
   logic [6:0]  In;
   logic [6:0]  Out;
   logic  load;
   logic  select;
   logic  enable;
   logic  Width;
   
   assign Width = 7;
//    integer handle3;
//    integer desc3;
   
   // Instantiate DUT
   LFSR #Width dut (In, clock, load, enable, Out);

   // Setup the clock to toggle every 1 time units 
   initial 
     begin	
	clock = 1'b1;
	forever #2 clock = ~clock;
     end

//    initial
//      begin
// 	// Gives output file name
// 	handle3 = $fopen("test.out");
// 	// Tells when to finish simulation
// 	#500 $finish;		
//      end

//    always 
//      begin
// 	desc3 = handle3;
// 	#5 $fdisplay(desc3, "%b %b || %b", 
// 		     reset_b, In, Out);
//      end   
   
   initial 
     begin      
	#0  In = 7'b1111111;
	#0  load = 1'b0;
	#0  select = 1'b0;
	#0  enable = 1'b0;
	#0  load = 1'b1;
	#10  enable = 1'b1;
	#0  load = 1'b0;
     end

endmodule // LFSR_tb

