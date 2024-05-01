module stimulus ();
//tested
   logic  clock;
   logic [8:0]  In;
   logic [2:0]  In3;
   logic [3:0]  In4;
   logic [4:0]  In5;
   logic [5:0]  In6;
   logic [6:0]  In7;
   logic [7:0]  In8;
   logic [8:0]  In9;
   logic [2:0]  Out3;
   logic [3:0]  Out4;
   logic [4:0]  Out5;
   logic [5:0]  Out6;
   logic [6:0]  Out7;
   logic [7:0]  Out8;
   logic [8:0]  Out9;
   logic  load;
   logic  select;
   logic  enable;
//    integer counter;
//    integer increment;
//    integer handle3;
//    integer desc3;
   
   // Instantiate DUT
     LFSR #(3) dut3 (In3, clock, load, enable, Out3);
     LFSR #(4) dut4 (In4, clock, load, enable, Out4);
     LFSR #(5) dut5 (In5, clock, load, enable, Out5);
     LFSR #(6) dut6 (In6, clock, load, enable, Out6);
     LFSR #(7) dut7 (In7, clock, load, enable, Out7);
     LFSR #(8) dut8 (In8, clock, load, enable, Out8);
     LFSR #(9) dut9 (In9, clock, load, enable, Out9);

     assign In3 = In[2:0];
     assign In4 = In[3:0];
     assign In5 = In[4:0];
     assign In6 = In[5:0];
     assign In7 = In[6:0];
     assign In8 = In[7:0];
     assign In9 = In[8:0];

   // Setup the clock to toggle every 1 time units 
   initial 
     begin	
	clock = 1'b1;
	// counter = 0;
	forever #2 clock = ~clock;
	// forever #0 counter = increment;
     end
     // increment = counter + 1;

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
	#0  In = 9'b0000001;
	#0  load = 1'b0;
	#0  select = 1'b0;
	#0  enable = 1'b0;
	#0  load = 1'b1;
	#10  enable = 1'b1;
	#0  load = 1'b0;
     end

endmodule // LFSR_tb

