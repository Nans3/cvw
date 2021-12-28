///////////////////////////////////////////
// lsu.sv
//
// Written: David_Harris@hmc.edu 9 January 2021
// Modified: 
//
// Purpose: Load/Store Unit 
//          Top level of the memory-stage hart logic
//          Contains data cache, DTLB, subword read/write datapath, interface to external bus
// 
// A component of the Wally configurable RISC-V project.
// 
// Copyright (C) 2021 Harvey Mudd College & Oklahoma State University
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, 
// modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software 
// is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES 
// OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS 
// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT 
// OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
///////////////////////////////////////////

`include "wally-config.vh"

module lsu 
  (
   input logic 				   clk, reset,
   input logic 				   StallM, FlushM, StallW, FlushW,
   output logic 			   LSUStall,
   // Memory Stage

   // connected to cpu (controls)
   input logic [1:0] 		   MemRWM,
   input logic [2:0] 		   Funct3M,
   input logic [6:0] 		   Funct7M, 
   input logic [1:0] 		   AtomicM,
   input logic 				   ExceptionM,
   input logic 				   PendingInterruptM,
   input logic 				   FlushDCacheM,
   output logic 			   CommittedM, 
   output logic 			   SquashSCW,
   output logic 			   DCacheMiss,
   output logic 			   DCacheAccess,

   // address and write data
   input logic [`XLEN-1:0] 	   IEUAdrE,
   (* mark_debug = "true" *)output logic [`XLEN-1:0]    IEUAdrM,
   input logic [`XLEN-1:0] 	   WriteDataM, 
   output logic [`XLEN-1:0]    ReadDataM,

   // cpu privilege
   input logic [1:0] 		   PrivilegeModeW,
   input logic 				   DTLBFlushM,
   // faults
   output logic 			   DTLBLoadPageFaultM, DTLBStorePageFaultM,
   output logic 			   LoadMisalignedFaultM, LoadAccessFaultM,
   // cpu hazard unit (trap)
   output logic 			   StoreMisalignedFaultM, StoreAccessFaultM,

   // connect to ahb
(* mark_debug = "true" *)   output logic [`PA_BITS-1:0] DCtoAHBPAdrM,
   output logic 			   DCtoAHBReadM, 
   output logic 			   DCtoAHBWriteM,
   input logic 				   DCfromAHBAck,
(* mark_debug = "true" *)   input logic [`XLEN-1:0] 	   DCfromAHBReadData,
   output logic [`XLEN-1:0]    DCtoAHBWriteData,
   output logic [2:0] 		   DCtoAHBSizeM, 

   // mmu management

   // page table walker
   input logic [`XLEN-1:0] 	   SATP_REGW, // from csr
   input logic 				   STATUS_MXR, STATUS_SUM, STATUS_MPRV,
   input logic [1:0] 		   STATUS_MPP,

   input logic [`XLEN-1:0] 	   PCF,
   input logic 				   ITLBMissF,
   output logic [`XLEN-1:0]    PTE,
   output logic [1:0] 		   PageType,
   output logic 			   ITLBWriteF,

   input 					   var logic [7:0] PMPCFG_ARRAY_REGW[`PMP_ENTRIES-1:0],
   input 					   var logic [`XLEN-1:0] PMPADDR_ARRAY_REGW[`PMP_ENTRIES-1:0] // *** this one especially has a large note attached to it in pmpchecker.
   );

  logic 					   DTLBPageFaultM;
  
  logic [`PA_BITS-1:0] 		   MemPAdrM;  // from mmu to dcache
  logic [`XLEN+1:0] 		   IEUAdrExtM;
  logic 					   DTLBMissM;
  logic 					   DTLBWriteM;
  logic 					   HPTWStall;  
  logic [`PA_BITS-1:0] 		   HPTWAdr;
  logic 					   HPTWRead;
  logic [1:0] 				   DCRWM;
  logic [1:0] 				   LsuRWM;
  logic [2:0] 				   LsuFunct3M;
  logic [1:0] 				   LsuAtomicM;
  logic [`PA_BITS-1:0] 		   LsuPAdrM;
  logic [11:0] 				   LsuAdrE, DCAdrE;  
  logic 					   CPUBusy;
  logic 					   MemReadM;
  logic 					   DataMisalignedM;
  logic 					   DCacheStall;

  logic 					   CacheableM;
  logic 					   SelHPTW;
  logic [2:0] 				   HPTWSize;


  logic 					   DCCommittedM;
  logic 					   CommittedMfromBus;

  logic 					   AnyCPUReqM;
  logic 					   MemAfterIWalkDone;
  logic 					   BusStall;
  

  typedef enum 				   {STATE_T0_READY,
								STATE_T0_REPLAY,
								STATE_T3_DTLB_MISS,
								STATE_T4_ITLB_MISS,
								STATE_T5_ITLB_MISS,
								STATE_T7_DITLB_MISS} statetype;

  statetype InterlockCurrState, InterlockNextState;
  logic 					   InterlockStall;
  logic 					   SelReplayCPURequest;
  logic 					   IgnoreRequest;


  
  assign AnyCPUReqM = (|MemRWM)  | (|AtomicM);

  always_ff @(posedge clk)
    if (reset)    InterlockCurrState <= #1 STATE_T0_READY;
    else InterlockCurrState <= #1 InterlockNextState;

  always_comb begin
	case(InterlockCurrState)
	  STATE_T0_READY:        if(~ITLBMissF & DTLBMissM & AnyCPUReqM)          InterlockNextState = STATE_T3_DTLB_MISS;
	                         else if(ITLBMissF & ~DTLBMissM & ~AnyCPUReqM)    InterlockNextState = STATE_T4_ITLB_MISS;
                             else if(ITLBMissF & ~DTLBMissM & AnyCPUReqM)     InterlockNextState = STATE_T5_ITLB_MISS;
					         else if(ITLBMissF & DTLBMissM & AnyCPUReqM)      InterlockNextState = STATE_T7_DITLB_MISS;
					         else                                             InterlockNextState = STATE_T0_READY;
	  STATE_T0_REPLAY:       if(DCacheStall)                                  InterlockNextState = STATE_T0_REPLAY;
	                         else                                             InterlockNextState = STATE_T0_READY;
	  STATE_T3_DTLB_MISS:    if(DTLBWriteM)                                   InterlockNextState = STATE_T0_REPLAY;
						     else                                             InterlockNextState = STATE_T3_DTLB_MISS;
	  STATE_T4_ITLB_MISS:    if(ITLBWriteF)                                   InterlockNextState = STATE_T0_READY;
	                         else                                             InterlockNextState = STATE_T4_ITLB_MISS;
	  STATE_T5_ITLB_MISS:    if(ITLBWriteF)                                   InterlockNextState = STATE_T0_REPLAY;
						     else                                             InterlockNextState = STATE_T5_ITLB_MISS;
	  STATE_T7_DITLB_MISS:   if(DTLBWriteM)                                   InterlockNextState = STATE_T5_ITLB_MISS;
						     else                                             InterlockNextState = STATE_T7_DITLB_MISS;
	  default: InterlockNextState = STATE_T0_READY;
	endcase
  end // always_comb
  
  // signal to CPU it needs to wait on HPTW.
  /* -----\/----- EXCLUDED -----\/-----
   // this code has a problem with imperas64mmu as it reads in an invalid uninitalized instruction.  InterlockStall becomes x and it propagates
   // everywhere.  The case statement below implements the same logic but any x on the inputs will resolve to 0.
   assign InterlockStall = (InterlockCurrState == STATE_T0_READY & (DTLBMissM | ITLBMissF)) | 
   (InterlockCurrState == STATE_T3_DTLB_MISS) | (InterlockCurrState == STATE_T4_ITLB_MISS) |
   (InterlockCurrState == STATE_T5_ITLB_MISS) | (InterlockCurrState == STATE_T7_DITLB_MISS);

   -----/\----- EXCLUDED -----/\----- */

  always_comb begin
	InterlockStall = 1'b0;
	case(InterlockCurrState) 
	  STATE_T0_READY: if(DTLBMissM | ITLBMissF) InterlockStall = 1'b1;
	  STATE_T3_DTLB_MISS: InterlockStall = 1'b1;
	  STATE_T4_ITLB_MISS: InterlockStall = 1'b1;
	  STATE_T5_ITLB_MISS: InterlockStall = 1'b1;
	  STATE_T7_DITLB_MISS: InterlockStall = 1'b1;
	  default: InterlockStall = 1'b0;
	endcase
  end
  
  
  // When replaying CPU memory request after PTW select the IEUAdrM for correct address.
  assign SelReplayCPURequest = (InterlockNextState == STATE_T0_REPLAY);
  assign SelHPTW = (InterlockCurrState == STATE_T3_DTLB_MISS) | (InterlockCurrState == STATE_T4_ITLB_MISS) |
				  (InterlockCurrState == STATE_T5_ITLB_MISS) | (InterlockCurrState == STATE_T7_DITLB_MISS);
  assign IgnoreRequest = (InterlockCurrState == STATE_T0_READY & (ITLBMissF | DTLBMissM | ExceptionM | PendingInterruptM)) |
						 ((InterlockCurrState == STATE_T0_REPLAY)
						  & (ExceptionM | PendingInterruptM));
  
  

  flopenrc #(`XLEN) AddressMReg(clk, reset, FlushM, ~StallM, IEUAdrE, IEUAdrM);

  // *** add generate to conditionally create hptw, lsuArb, and mmu
  // based on `MEM_VIRTMEM
  hptw hptw(.clk, .reset, .SATP_REGW, .PCF, .IEUAdrM,
			.ITLBMissF(ITLBMissF & ~PendingInterruptM),
			.DTLBMissM(DTLBMissM & ~PendingInterruptM),
			.MemRWM, .PTE, .PageType, .ITLBWriteF, .DTLBWriteM,
			.HPTWReadPTE(ReadDataM),
			.DCacheStall, .HPTWAdr, .HPTWRead, .HPTWSize, .AnyCPUReqM);
  



  assign LSUStall = DCacheStall | InterlockStall | BusStall;
  

  // arbiter between IEU and hptw
  
  // multiplex the outputs to LSU
  mux2 #(2) rwmux(MemRWM, {HPTWRead, 1'b0}, SelHPTW, LsuRWM);
  mux2 #(3) sizemux(Funct3M, HPTWSize, SelHPTW, LsuFunct3M);
  mux2 #(2) atomicmux(AtomicM, 2'b00, SelHPTW, LsuAtomicM);
  mux2 #(12) adremux(IEUAdrE[11:0], HPTWAdr[11:0], SelHPTW, LsuAdrE);
  assign IEUAdrExtM = {2'b00, IEUAdrM};
  mux2 #(`PA_BITS) lsupadrmux(IEUAdrExtM[`PA_BITS-1:0], HPTWAdr, SelHPTW, LsuPAdrM);

  assign CPUBusy = StallW & ~SelHPTW;  
  // always block interrupts when using the hardware page table walker.
  assign CommittedM = SelHPTW | DCCommittedM | CommittedMfromBus;

  // this is for the d cache SRAM.
  // turns out because we cannot pipeline hptw requests we don't need this register
  //flop #(`PA_BITS) HPTWAdrMReg(clk, HPTWAdr, HPTWAdrM);   // delay HPTWAdrM by a cycle
  
  //assign LsuRWM = SelHPTW ? {HPTWRead, 1'b0} : MemRWM;
  //assign LsuAdrE = SelHPTW ? HPTWAdr[11:0] : IEUAdrE[11:0];  
  //assign LsuAtomicM = SelHPTW ? 2'b00 : AtomicM;
  //assign LsuPAdrM = SelHPTW ? HPTWAdr : IEUAdrExtM[`PA_BITS-1:0]; 

  mmu #(.TLB_ENTRIES(`DTLB_ENTRIES), .IMMU(0))
  dmmu(.clk, .reset, .SATP_REGW, .STATUS_MXR, .STATUS_SUM, .STATUS_MPRV, .STATUS_MPP,
       .PrivilegeModeW, .DisableTranslation(SelHPTW),
       .PAdr(LsuPAdrM),
       .VAdr(IEUAdrM),
       .Size(LsuFunct3M[1:0]),
       .PTE,
       .PageTypeWriteVal(PageType),
       .TLBWrite(DTLBWriteM),
       .TLBFlush(DTLBFlushM),
       .PhysicalAddress(MemPAdrM),
       .TLBMiss(DTLBMissM),
       .Cacheable(CacheableM),
       .Idempotent(), .AtomicAllowed(),
       .TLBPageFault(DTLBPageFaultM),
       .InstrAccessFaultF(), .LoadAccessFaultM, .StoreAccessFaultM,
       .AtomicAccessM(1'b0), .ExecuteAccessF(1'b0), 
       .WriteAccessM(LsuRWM[0]), .ReadAccessM(LsuRWM[1]),
       .PMPCFG_ARRAY_REGW, .PMPADDR_ARRAY_REGW
       ); // *** the pma/pmp instruction access faults don't really matter here. is it possible to parameterize which outputs exist?


  // Move generate from lrsc to outside this module.
  generate
	if (`A_SUPPORTED) begin
	  assign MemReadM = LsuRWM[1] & ~(IgnoreRequest) & ~DTLBMissM;
	  lrsc lrsc(.clk, .reset, .FlushW, .CPUBusy, .MemReadM, .LsuRWM, .LsuAtomicM, .MemPAdrM,
				.SquashSCW, .DCRWM);
	end else begin
      assign SquashSCW = 0;
      assign DCRWM = LsuRWM;
	end
  endgenerate

  // Specify which type of page fault is occurring
  // *** `MEM_VIRTMEM
  assign DTLBLoadPageFaultM = DTLBPageFaultM & LsuRWM[1];
  assign DTLBStorePageFaultM = DTLBPageFaultM & LsuRWM[0];

  // Determine if an Unaligned access is taking place
  // hptw guarantees alignment, only check inputs from IEU.
  always_comb
    case(Funct3M[1:0]) 
      2'b00:  DataMisalignedM = 0;                       // lb, sb, lbu
      2'b01:  DataMisalignedM = IEUAdrM[0];              // lh, sh, lhu
      2'b10:  DataMisalignedM = IEUAdrM[1] | IEUAdrM[0]; // lw, sw, flw, fsw, lwu
      2'b11:  DataMisalignedM = |IEUAdrM[2:0];           // ld, sd, fld, fsd
    endcase 

  // If the CPU's (not HPTW's) request is a page fault.
  assign LoadMisalignedFaultM = DataMisalignedM & MemRWM[1];
  assign StoreMisalignedFaultM = DataMisalignedM & MemRWM[0];

  // conditional
  // 1. ram // controlled by `MEM_DTIM
  // 2. cache `MEM_DCACHE
  // 3. wire pass-through
  assign DCAdrE = SelReplayCPURequest ? IEUAdrM[11:0] : LsuAdrE[11:0];

  localparam integer   WORDSPERLINE = `DCACHE_BLOCKLENINBITS/`XLEN;
  localparam integer   LOGWPL = $clog2(WORDSPERLINE);
  localparam integer   BLOCKLEN = `DCACHE_BLOCKLENINBITS;
  
  localparam integer   FetchCountThreshold = WORDSPERLINE - 1;
  localparam integer   BLOCKBYTELEN = BLOCKLEN/8;
  localparam integer   OFFSETLEN = $clog2(BLOCKBYTELEN);

  // temp
  logic 		       SelUncached;
  logic 			   FetchCountFlag;
  
  logic [`XLEN-1:0]    FinalAMOWriteDataM, FinalWriteDataM;
  (* mark_debug = "true" *) logic [`XLEN-1:0]    DC_HWDATA_FIXNAME;
  logic 			   SelFlush;
  logic [`XLEN-1:0]    ReadDataWordM;
  logic [`DCACHE_BLOCKLENINBITS-1:0] DCacheMemWriteData;

  // keep
  logic [`XLEN-1:0]    ReadDataWordMuxM;


  logic [LOGWPL-1:0]   FetchCount, NextFetchCount;
  logic [`PA_BITS-1:0] 	       BasePAdrMaskedM;  
  logic [OFFSETLEN-1:0]        BasePAdrOffsetM;

  logic 			   CntEn, PreCntEn;
  logic 			   CntReset;
  logic [`PA_BITS-1:0] BasePAdrM;
  logic [`XLEN-1:0]    ReadDataBlockSetsM [(`DCACHE_BLOCKLENINBITS/`XLEN)-1:0];
  


  logic 			   DCWriteLine;
  logic 			   DCFetchLine;
  logic 			   BUSACK;
  
  dcache dcache(.clk, .reset, .CPUBusy,
				.MemRWM(DCRWM),
				.Funct3M(LsuFunct3M),
				.Funct7M, .FlushDCacheM,
				.AtomicM(LsuAtomicM),
				.MemAdrE(DCAdrE),
				.MemPAdrM,
				.FinalWriteDataM, .ReadDataWordM, .DCacheStall,
				.CommittedM(DCCommittedM),
				.DCacheMiss, .DCacheAccess, .IgnoreRequest,
				.CacheableM(CacheableM), 

				.BasePAdrM,
				.ReadDataBlockSetsM,
				.SelFlush,
				.DCacheMemWriteData,
				.DCFetchLine,
				.DCWriteLine,
				.BUSACK
				);


  mux2 #(`XLEN) UnCachedDataMux(.d0(ReadDataWordM),
				.d1(DCacheMemWriteData[`XLEN-1:0]),
				.s(SelUncached),
				.y(ReadDataWordMuxM));
  
  // finally swr
  subwordread subwordread(.ReadDataWordMuxM,
			  .MemPAdrM(MemPAdrM[2:0]),
			  .Funct3M(LsuFunct3M),
			  .ReadDataM);

  generate
    if (`A_SUPPORTED) begin
      logic [`XLEN-1:0] AMOResult;
      amoalu amoalu(.srca(ReadDataM), .srcb(WriteDataM), .funct(Funct7M), .width(LsuFunct3M[1:0]), 
                    .result(AMOResult));
      mux2 #(`XLEN) wdmux(WriteDataM, AMOResult, LsuAtomicM[1], FinalAMOWriteDataM);
    end else
      assign FinalAMOWriteDataM = WriteDataM;
  endgenerate
  
  subwordwrite subwordwrite(.HRDATA(ReadDataWordM),
			    .HADDRD(MemPAdrM[2:0]),
			    .HSIZED({LsuFunct3M[2], 1'b0, LsuFunct3M[1:0]}),
			    .HWDATAIN(FinalAMOWriteDataM),
			    .HWDATA(FinalWriteDataM));

  assign DCtoAHBWriteData = CacheableM | SelFlush ? DC_HWDATA_FIXNAME : WriteDataM;

  generate
    if (`XLEN == 32) assign DCtoAHBSizeM = CacheableM | SelFlush ? 3'b010 : LsuFunct3M;
    else assign DCtoAHBSizeM = CacheableM | SelFlush ? 3'b011 : LsuFunct3M;
  endgenerate;

  // Bus Side logic
  // register the fetch data from the next level of memory.
  // This register should be necessary for timing.  There is no register in the uncore or
  // ahblite controller between the memories and this cache.

  genvar index;
  generate
    for (index = 0; index < WORDSPERLINE; index++) begin:fetchbuffer
      flopen #(`XLEN) fb(.clk(clk),
			 .en(DCfromAHBAck & DCtoAHBReadM & (index == FetchCount)),
			 .d(DCfromAHBReadData),
			 .q(DCacheMemWriteData[(index+1)*`XLEN-1:index*`XLEN]));
    end
  endgenerate


  // if not cacheable the offset bits needs to be sent to the EBU.
  // if cacheable the offset bits are discarded.  $ FSM will fetch the whole block.
  assign BasePAdrOffsetM = CacheableM ? {{OFFSETLEN}{1'b0}} : BasePAdrM[OFFSETLEN-1:0];
  assign BasePAdrMaskedM = {BasePAdrM[`PA_BITS-1:OFFSETLEN], BasePAdrOffsetM};
  
  assign DCtoAHBPAdrM = ({{`PA_BITS-LOGWPL{1'b0}}, FetchCount} << $clog2(`XLEN/8)) + BasePAdrMaskedM;
  
  assign DC_HWDATA_FIXNAME = ReadDataBlockSetsM[FetchCount];

  assign FetchCountFlag = (FetchCount == FetchCountThreshold[LOGWPL-1:0]);
  assign CntEn = PreCntEn & DCfromAHBAck;

  flopenr #(LOGWPL) 
  FetchCountReg(.clk(clk),
		.reset(reset | CntReset),
		.en(CntEn),
		.d(NextFetchCount),
		.q(FetchCount));

  assign NextFetchCount = FetchCount + 1'b1;

  typedef enum {STATE_BUS_READY,
				STATE_BUS_FETCH_WDV,
				STATE_BUS_WRITE_WDV,
				STATE_BUS_UNCACHED_WRITE,
				STATE_BUS_UNCACHED_WRITE_DONE,
				STATE_BUS_UNCACHED_READ,
				STATE_BUS_UNCACHED_READ_DONE} busstatetype;

  (* mark_debug = "true" *) busstatetype BusCurrState, BusNextState;

  always_ff @(posedge clk)
    if (reset)    BusCurrState <= #1 STATE_BUS_READY;
    else BusCurrState <= #1 BusNextState;  
  
  always_comb begin
	BusNextState = STATE_BUS_READY;
	CntReset = 1'b0;
	BusStall = 1'b0;
	PreCntEn = 1'b0;
	DCtoAHBWriteM = 1'b0;
	DCtoAHBReadM = 1'b0;
	CommittedMfromBus = 1'b0;
	BUSACK = 1'b0;
	SelUncached = 1'b0;
	
	case(BusCurrState)
	  STATE_BUS_READY: begin
		if(IgnoreRequest) begin
		  BusNextState = STATE_BUS_READY;
		end else
		// uncache write
		if(DCRWM[0] & ~CacheableM) begin
		  BusNextState = STATE_BUS_UNCACHED_WRITE;
		  CntReset = 1'b1;
		  BusStall = 1'b1;
		  DCtoAHBWriteM = 1'b1;
		end
		// uncached read
		else if(DCRWM[1] & ~CacheableM) begin
		  BusNextState = STATE_BUS_UNCACHED_READ;
		  CntReset = 1'b1;
		  BusStall = 1'b1;
		  DCtoAHBReadM = 1'b1;
		end
		// D$ Fetch Line
		else if(DCFetchLine) begin
		  BusNextState = STATE_BUS_FETCH_WDV;
		  CntReset = 1'b1;
		  BusStall = 1'b1;
		end
		// D$ Write Line
		else if(DCWriteLine) begin
		  BusNextState = STATE_BUS_WRITE_WDV;
		  CntReset = 1'b1;
		  BusStall = 1'b1;
		end
	  end

      STATE_BUS_UNCACHED_WRITE : begin
		BusStall = 1'b1;	
		DCtoAHBWriteM = 1'b1;
		CommittedMfromBus = 1'b1;
		if(DCfromAHBAck) begin
		  BusNextState = STATE_BUS_UNCACHED_WRITE_DONE;
		end else begin
		  BusNextState = STATE_BUS_UNCACHED_WRITE;
		end
      end

      STATE_BUS_UNCACHED_READ: begin
		BusStall = 1'b1;	
		DCtoAHBReadM = 1'b1;
		CommittedMfromBus = 1'b1;
		if(DCfromAHBAck) begin
		  BusNextState = STATE_BUS_UNCACHED_READ_DONE;
		end else begin
		  BusNextState = STATE_BUS_UNCACHED_READ;
		end
      end
      
      STATE_BUS_UNCACHED_WRITE_DONE: begin
		CommittedMfromBus = 1'b1;
		BusNextState = STATE_BUS_READY;
      end

      STATE_BUS_UNCACHED_READ_DONE: begin
		CommittedMfromBus = 1'b1;
		SelUncached = 1'b1;
      end

      STATE_BUS_FETCH_WDV: begin
		BusStall = 1'b1;
        PreCntEn = 1'b1;
		DCtoAHBReadM = 1'b1;
		CommittedMfromBus = 1'b1;
		
        if (FetchCountFlag & DCfromAHBAck) begin
          BusNextState = STATE_BUS_READY;
		  BUSACK = 1'b1;
        end else begin
          BusNextState = STATE_BUS_FETCH_WDV;
        end
      end

      STATE_BUS_WRITE_WDV: begin
		BusStall = 1'b1;
        PreCntEn = 1'b1;
		DCtoAHBWriteM = 1'b1;
		CommittedMfromBus = 1'b1;
		if(FetchCountFlag & DCfromAHBAck) begin
		  BusNextState = STATE_BUS_READY;
		  BUSACK = 1'b1;
		end else begin
		  BusNextState = STATE_BUS_WRITE_WDV;
		end	  
      end
	endcase
  end

endmodule

