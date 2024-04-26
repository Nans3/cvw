module stimulus ();
//tested
   logic  clock;
   logic [3:0]  In;
   logic [3:0]  Out;
   logic  load;
   logic  select;
   logic  enable;
   
   
//    integer handle3;
//    integer desc3;
   
   // Instantiate DUT
   LFSR dut (In, clock, load, enable, select, Out);

   // Setup the clock to toggle every 1 time units 
   initial 
     begin	
	clock = 1'b1;
	forever #5 clock = ~clock;
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
	#0  In = 4'b1111;
	#0  load = 1'b0;
	#0  enable = 1'b1;
     end

endmodule // LFSR_tb