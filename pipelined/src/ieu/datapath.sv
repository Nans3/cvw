///////////////////////////////////////////
// datapath.sv
//
// Written: David_Harris@hmc.edu, Sarah.Harris@unlv.edu
// Created: 9 January 2021
// Modified: 
//
// Purpose: Wally Integer Datapath
// 
// Documentation: RISC-V System on Chip Design Chapter 4 (Figure 4.12)
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// 
// Copyright (C) 2021-23 Harvey Mudd College & Oklahoma State University
//
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the “License”); you may not use this file 
// except in compliance with the License, or, at your option, the Apache License version 2.0. You 
// may obtain a copy of the License at
//
// https://solderpad.org/licenses/SHL-2.1/
//
// Unless required by applicable law or agreed to in writing, any work distributed under the 
// License is distributed on an “AS IS” BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, 
// either express or implied. See the License for the specific language governing permissions 
// and limitations under the License.
////////////////////////////////////////////////////////////////////////////////////////////////

`include "wally-config.vh"

module datapath (
  input  logic             clk, reset,
  // Decode stage signals
  input  logic [2:0]       ImmSrcD,                 // Selects type of immediate extension
  input  logic [31:0]      InstrD,                  // Instruction in Decode stage
  input  logic [2:0]       Funct3E,                 // Funct3 field of instruction in Execute stage
  // Execute stage signals
  input  logic             StallE, FlushE,          // Stall, flush Execute stage
  input  logic [1:0]       ForwardAE, ForwardBE,    // Forward ALU operands from later stages
  input  logic [2:0]       ALUControlE,             // Indicate operation ALU performs
  input  logic             ALUSrcAE, ALUSrcBE,      // ALU operands
  input  logic             ALUResultSrcE,           // Selects result to pass on to Memory stage
  input  logic             JumpE,                   // Is a jump (j) instruction
  input  logic             BranchSignedE,           // Branch comparison operands are signed (if it's a branch)
  input  logic [`XLEN-1:0] PCE,                     // PC in Execute stage  
  input  logic [`XLEN-1:0] PCLinkE,                 // PC + 4 (of instruction in Execute stage)
  output logic [1:0]       FlagsE,                  // Comparison flags ({eq, lt})
  output logic [`XLEN-1:0] IEUAdrE,                 // Address computed by ALU
  output logic [`XLEN-1:0] ForwardedSrcAE, ForwardedSrcBE, // ALU sources before the mux chooses between them and PCE to put in srcA/B
  // Memory stage signals
  input  logic             StallM, FlushM,          // Stall, flush Memory stage
  input  logic             FWriteIntM, FCvtIntW,    // FPU writes register file, FPU converts float to int ***
  input  logic [`XLEN-1:0] FIntResM,                // FPU integer result ***
  output logic [`XLEN-1:0] SrcAM,                   // ALU's Source A in Memory stage *** say why needed?***
  output logic [`XLEN-1:0] WriteDataM,              // Write data in Memory stage
  // Writeback stage signals
  input  logic             StallW, FlushW,          // Stall, flush Writeback stage
(* mark_debug = "true" *)  input  logic             RegWriteW, IntDivW,  // Write register file, integer divide instruction
  input  logic             SquashSCW,               // ***
  input  logic [2:0]       ResultSrcW,              // Select source of result to write back to register file
  input  logic [`XLEN-1:0] FCvtIntResW,             // FPU integer result ***
  input  logic [`XLEN-1:0] ReadDataW,               // Read data from LSU
  input  logic [`XLEN-1:0] CSRReadValW, MDUResultW, // CSR read result, MDU (Multiply/divide unit) result *** 
  input  logic [`XLEN-1:0] FIntDivResultW,          // FPU's integer divide result ***
   // Hazard Unit signals 
  output logic [4:0]       Rs1D, Rs2D, Rs1E, Rs2E,  // Register sources to read in Decode or Execute stage
  output logic [4:0]       RdE, RdM, RdW            // Register destinations in Execute, Memory, or Writeback stage
);

  // Fetch stage signals
  // Decode stage signals
  logic [`XLEN-1:0] R1D, R2D;                       // Read data from Rs1 (RD1), Rs2 (RD2)
  logic [`XLEN-1:0] ExtImmD;                        // Extended immediate in Decode stage *** According to Figure 4.12, should be ImmExtD
  logic [4:0]       RdD;                            // Destination register in Decode stage
  // Execute stage signals
  logic [`XLEN-1:0] R1E, R2E;                       // Source operands read from register file
  logic [`XLEN-1:0] ExtImmE;                        // Extended immediate in Execute stage ***According to Figure 4.12, should be ImmExtE
  logic [`XLEN-1:0] SrcAE, SrcBE;                   // ALU operands
  logic [`XLEN-1:0] ALUResultE, AltResultE, IEUResultE; // ALU result, Alternative result (ExtImmE or PC+4), computed address *** According to Figure 4.12, IEUResultE should be called IEUAdrE
  // Memory stage signals
  logic [`XLEN-1:0] IEUResultM;                     // Address computed by ALU *** According to Figure 4.12, IEUResultM should be called IEUAdrM
  logic [`XLEN-1:0] IFResultM;                      // ***
  // Writeback stage signals
  logic [`XLEN-1:0] SCResultW;                      // Store Conditional result
  logic [`XLEN-1:0] ResultW;                        // Result to write to register file
  logic [`XLEN-1:0] IFResultW, IFCvtResultW, MulDivResultW; // *** 

  // Decode stage
  assign Rs1D      = InstrD[19:15];
  assign Rs2D      = InstrD[24:20];
  assign RdD       = InstrD[11:7];
  regfile regf(clk, reset, RegWriteW, Rs1D, Rs2D, RdW, ResultW, R1D, R2D);
  extend ext(.InstrD(InstrD[31:7]), .ImmSrcD, .ExtImmD);
 
  // Execute stage pipeline register and logic
  flopenrc #(`XLEN) RD1EReg(clk, reset, FlushE, ~StallE, R1D, R1E);
  flopenrc #(`XLEN) RD2EReg(clk, reset, FlushE, ~StallE, R2D, R2E);
  flopenrc #(`XLEN) ExtImmEReg(clk, reset, FlushE, ~StallE, ExtImmD, ExtImmE);
  flopenrc #(5)     Rs1EReg(clk, reset, FlushE, ~StallE, Rs1D, Rs1E);
  flopenrc #(5)     Rs2EReg(clk, reset, FlushE, ~StallE, Rs2D, Rs2E);
  flopenrc #(5)     RdEReg(clk, reset, FlushE, ~StallE, RdD, RdE);
	
  mux3  #(`XLEN)  faemux(R1E, ResultW, IFResultM, ForwardAE, ForwardedSrcAE);
  mux3  #(`XLEN)  fbemux(R2E, ResultW, IFResultM, ForwardBE, ForwardedSrcBE);
  comparator_dc_flip #(`XLEN) comp(ForwardedSrcAE, ForwardedSrcBE, BranchSignedE, FlagsE);
  mux2  #(`XLEN)  srcamux(ForwardedSrcAE, PCE, ALUSrcAE, SrcAE);
  mux2  #(`XLEN)  srcbmux(ForwardedSrcBE, ExtImmE, ALUSrcBE, SrcBE);
  alu   #(`XLEN)  alu(SrcAE, SrcBE, ALUControlE, Funct3E, ALUResultE, IEUAdrE);
  mux2 #(`XLEN)   altresultmux(ExtImmE, PCLinkE, JumpE, AltResultE);
  mux2 #(`XLEN)   ieuresultmux(ALUResultE, AltResultE, ALUResultSrcE, IEUResultE);

  // Memory stage pipeline register
  flopenrc #(`XLEN) SrcAMReg(clk, reset, FlushM, ~StallM, SrcAE, SrcAM);
  flopenrc #(`XLEN) IEUResultMReg(clk, reset, FlushM, ~StallM, IEUResultE, IEUResultM);
  flopenrc #(5)     RdMReg(clk, reset, FlushM, ~StallM, RdE, RdM);	
  flopenrc #(`XLEN) WriteDataMReg(clk, reset, FlushM, ~StallM, ForwardedSrcBE, WriteDataM); 
  
  // Writeback stage pipeline register and logic
  flopenrc #(`XLEN) IFResultWReg(clk, reset, FlushW, ~StallW, IFResultM, IFResultW);
  flopenrc #(5)     RdWReg(clk, reset, FlushW, ~StallW, RdM, RdW);

  // floating point inputs: FIntResM comes from fclass, fcmp, fmv; FCvtIntResW comes from fcvt
  if (`F_SUPPORTED) begin:fpmux
    mux2  #(`XLEN)  resultmuxM(IEUResultM, FIntResM, FWriteIntM, IFResultM);
    mux2  #(`XLEN)  cvtresultmuxW(IFResultW, FCvtIntResW, FCvtIntW, IFCvtResultW);
    if (`IDIV_ON_FPU) begin
      mux2  #(`XLEN)  divresultmuxW(MDUResultW, FIntDivResultW, IntDivW, MulDivResultW);
    end else begin 
      assign MulDivResultW = MDUResultW;
    end
  end else begin:fpmux
    assign IFResultM = IEUResultM; assign IFCvtResultW = IFResultW;
    assign MulDivResultW = MDUResultW;
  end
  mux5  #(`XLEN)  resultmuxW(IFCvtResultW, ReadDataW, CSRReadValW, MulDivResultW, SCResultW, ResultSrcW, ResultW); 
 
  // handle Store Conditional result if atomic extension supported
  if (`A_SUPPORTED) assign SCResultW = {{(`XLEN-1){1'b0}}, SquashSCW};
  else              assign SCResultW = 0;
endmodule
