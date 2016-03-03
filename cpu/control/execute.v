//=============================================================================
// This module implements the instruction execute state logic.
//
//  Copyright (C) 2014-2016  Goran Devic
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//=============================================================================
// Using a compiled format will include files generated by "gencompile.py" script
// These files are a processed version of "exec_matrix_compiled.vh"
// You would define this on Xilinx and undefine (comment out) on Altera
`define USE_COMPILED_FORMAT

module execute
(
    //----------------------------------------------------------
    // Control signals generated by the instruction execution
    //----------------------------------------------------------
    `include "exec_module.vh"

    output reg nextM,                   // Last M cycle of any instruction
    output reg setM1,                   // Last T clock of any instruction
    output reg fFetch,                  // Function: opcode fetch cycle ("M1")
    output reg fMRead,                  // Function: memory read cycle
    output reg fMWrite,                 // Function: memory write cycle
    output reg fIORead,                 // Function: IO Read cycle
    output reg fIOWrite,                // Function: IO Write cycle

    //----------------------------------------------------------
    // Inputs from the instruction decode PLA
    //----------------------------------------------------------
    input wire [104:0] pla,             // Statically decoded instructions

    //----------------------------------------------------------
    // Inputs from various blocks
    //----------------------------------------------------------
    input wire nreset,                  // Internal reset signal
    input wire in_intr,                 // Servicing maskable interrupt
    input wire in_nmi,                  // Servicing non-maskable interrupt
    input wire in_halt,                 // Currently in HALT mode
    input wire im1,                     // Interrupt Mode 1
    input wire im2,                     // Interrupt Mode 2
    input wire use_ixiy,                // Special decode signal
    input wire flags_cond_true,         // Flags condition is true
    input wire repeat_en,               // Enable repeat of a block instruction
    input wire flags_zf,                // ZF to test a condition
    input wire flags_nf,                // NF to test for subtraction
    input wire flags_sf,                // SF to test for 8-bit sign of a value
    input wire flags_cf,                // CF to set HF for CCF

    //----------------------------------------------------------
    // Machine and clock cycles
    //----------------------------------------------------------
    input wire M1,                      // Machine cycle #1
    input wire M2,                      // Machine cycle #2
    input wire M3,                      // Machine cycle #3
    input wire M4,                      // Machine cycle #4
    input wire M5,                      // Machine cycle #5
    input wire T1,                      // T-cycle #1
    input wire T2,                      // T-cycle #2
    input wire T3,                      // T-cycle #3
    input wire T4,                      // T-cycle #4
    input wire T5,                      // T-cycle #5
    input wire T6                       // T-cycle #6
);

// Detects unknown instructions by signalling the known ones
reg validPLA;                           // Valid PLA asserts this reg
// Activates a state machine to compute WZ=IX+d; takes 5T cycles
reg ixy_d;                              // Compute WX=IX+d
// Signals the setting of IX/IY and CB/ED prefix flags; inhibits clearing them
reg setIXIY;                            // Set IX/IY flag at the next T cycle
reg setCBED;                            // Set CB or ED flag at the next T cycle
// Holds asserted by non-repeating versions of block instructions (LDI/CPI,...)
reg nonRep;                             // Non-repeating block instruction
// Suspends incrementing PC through address latch unless in HALT or interrupt mode
reg pc_inc_hold;                        // Normally 0 unless in one of those modes

//--------------------------------------------------------------
// Define various shortcuts to field naming
//--------------------------------------------------------------
`define GP_REG_BC       2'h0
`define GP_REG_DE       2'h1
`define GP_REG_HL       2'h2
`define GP_REG_AF       2'h3

`define PFSEL_P         2'h0
`define PFSEL_V         2'h1
`define PFSEL_IFF2      2'h2
`define PFSEL_REP       2'h3

//--------------------------------------------------------------
// Make available different bits and sections of the opcode byte
//--------------------------------------------------------------
wire op0 = pla[99];
wire op1 = pla[100];
wire op2 = pla[101];
wire op3 = pla[102];
wire op4 = pla[103];
wire op5 = pla[104];

wire [1:0] op21 = { pla[101], pla[100] };
wire [1:0] op54 = { pla[104], pla[103] };

//--------------------------------------------------------------
// 8-bit register selections needs to swizzle mux for A and F
//--------------------------------------------------------------
wire rsel0 = op0 ^ (op1 & op2);
wire rsel3 = op3 ^ (op4 & op5);

// Temporary test code
reg [4:0] check_db1;
reg check_db1_fail;
reg [2:0] check_db2;
reg check_db2_fail;

`ifdef USE_COMPILED_FORMAT
`include "temp_wires.vh"                // Define all temp wires used with compiled equations
`endif

always @(*) // always_comb
begin
    //-----------------------------------------------------------------------------
    // Default assignment of all control outputs to 0 to prevent generating latches
    //-----------------------------------------------------------------------------
    `include "exec_zero.vh"             // Initial assignment to all ctl wires to zero

    // Reset internal control regs
    validPLA = 0;                       // Will be set by every *valid* PLA entry
    nextM = 0;                          // Will be set to advance to the next M cycle
    setM1 = 0;                          // Will be set on a last M/T cycle of an instruction

    // Reset global machine cycle functions
    fFetch = M1;                        // Fetch is aliased to M1
    fMRead = 0; fMWrite = 0; fIORead = 0; fIOWrite = 0;
    ixy_d = 0;
    setIXIY = 0;
    setCBED = 0;
    nonRep = 0;
    pc_inc_hold = 0;

    //-------------------------------------------------------------------------
    // State-based signal assignment; code generated from Timings spreadsheet
    //-------------------------------------------------------------------------
`ifdef USE_COMPILED_FORMAT
    `include "exec_matrix_compiled.vh"  // Compiled execution equations
`else
    `include "exec_matrix.vh"           // Execution statements in the original nested-if format
`endif

    // Needed by data bus 0 override logic, make only one bus writer active at any time
    ctl_bus_db_oe = ctl_bus_db_oe & ~(ctl_bus_zero_oe | ctl_bus_ff_oe);

    // Temporary test code to catch bus contention
    check_db1[4:0] = {ctl_reg_out_lo, ctl_sw_2u, ctl_flags_oe, ctl_daa_oe, ctl_sw_1d};
    check_db1_fail = ~(check_db1[4:0]==0 || check_db1[4:0]==5'b00001 || check_db1[4:0]==5'b00010 || check_db1[4:0]==5'b00100 || check_db1[4:0]==5'b01000 || check_db1[4:0]==5'b10000);
`ifdef MODEL_TECH
    if (check_db1_fail==1)
    begin
        setM1 = 1; // Screw up simulation so we catch it
        validPLA = 0;
        $display("DB1 BUS ERROR");
    end
`endif

    check_db2[2:0] = {ctl_reg_out_hi, ctl_sw_2d, ctl_alu_oe};
    check_db2_fail = ~(check_db2[2:0]==0 || check_db2[2:0]==3'b001 || check_db2[2:0]==3'b010 || check_db2[2:0]==3'b100);
`ifdef MODEL_TECH
    if (check_db2_fail==1)
    begin
        // setM1 = 1; // Screw up simulation so we catch it
        // validPLA = 0;
        $display("DB2 BUS ERROR");
    end
`endif

end

endmodule
