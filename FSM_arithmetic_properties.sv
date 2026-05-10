// =============================================================================
// File        : FSM_arithmetic_properties.sv
// Description : Standalone SystemVerilog Assertion (SVA) property file
//               for use with Cadence JasperGold Formal Verification.
//
// Usage (JasperGold TCL):
//   analyze -sv FSM_arithmetic_model.v FSM_arithmetic_properties.sv
//   elaborate  -top jaspergold_complete_design
//   prove -all
// =============================================================================

module FSM_arithmetic_properties #(
    parameter DATA_W = 4,
    parameter RES_W  = DATA_W + 1
) (
    input wire              clk,
    input wire              rst,
    input wire              req,
    input wire              grant,
    input wire [DATA_W-1:0] data_a,
    input wire [DATA_W-1:0] data_b,
    input wire [1:0]        opcode,
    input wire              secure_access,
    input wire              power_enable,
    input wire [RES_W-1:0]  result,
    input wire              valid,
    input wire              error_flag,
    // Expose internal state for property binding
    input wire [1:0]        current_state
);

    // =========================================================================
    // State encoding (must match DUT)
    // =========================================================================
    localparam [1:0] IDLE    = 2'b00;
    localparam [1:0] PROCESS = 2'b01;
    localparam [1:0] DONE    = 2'b10;
    localparam [1:0] ERROR   = 2'b11;

    // Default clocking and reset for all properties
    default clocking cb @(posedge clk); endclocking
    default disable iff (rst);

    // =========================================================================
    // ASSUMPTIONS  (constrain the formal engine's input space)
    // =========================================================================

    // opcode is always a 2-bit value – no assumption needed (it's structural)
    // data_a and data_b are free; formal explores all 4-bit values.

    // =========================================================================
    // FSM TRANSITION PROPERTIES
    // =========================================================================

    // P1: IDLE -> PROCESS on req
    P1_IDLE_TO_PROCESS: assert property (
        (current_state == IDLE && req) |=> (current_state == PROCESS)
    );

    // P2: PROCESS -> DONE when power and security are valid
    P2_PROCESS_TO_DONE: assert property (
        (current_state == PROCESS && power_enable && secure_access)
        |=> (current_state == DONE)
    );

    // P3: PROCESS -> ERROR when power fails
    P3_PROCESS_TO_ERROR_POWER: assert property (
        (current_state == PROCESS && !power_enable)
        |=> (current_state == ERROR)
    );

    // P4: PROCESS -> ERROR on security violation
    P4_PROCESS_TO_ERROR_SEC: assert property (
        (current_state == PROCESS && !secure_access)
        |=> (current_state == ERROR)
    );

    // P5: DONE always returns to IDLE (no deadlock)
    P5_DONE_TO_IDLE: assert property (
        (current_state == DONE) |=> (current_state == IDLE)
    );

    // P6: ERROR always returns to IDLE (no deadlock)
    P6_ERROR_TO_IDLE: assert property (
        (current_state == ERROR) |=> (current_state == IDLE)
    );

    // P7: FSM reaches IDLE within 1 cycle after reset
    P7_RESET_IDLE: assert property (
        $rose(rst) |=> (current_state == IDLE)
    );

    // =========================================================================
    // OUTPUT / SIGNAL CORRECTNESS PROPERTIES
    // =========================================================================

    // P8: grant is high iff in PROCESS state
    P8_GRANT_IN_PROCESS: assert property (
        (current_state == PROCESS) |-> grant
    );

    P8b_NO_GRANT_OUTSIDE_PROCESS: assert property (
        (current_state != PROCESS) |-> !grant
    );

    // P9: valid is high iff in DONE state
    P9_VALID_IN_DONE: assert property (
        (current_state == DONE) |-> valid
    );

    P9b_NO_VALID_OUTSIDE_DONE: assert property (
        (current_state != DONE) |-> !valid
    );

    // P10: error_flag on security violation during PROCESS
    P10_ERROR_FLAG_INSECURE: assert property (
        (current_state == PROCESS && !secure_access) |-> error_flag
    );

    // P11: error_flag on power failure during PROCESS
    P11_ERROR_FLAG_POWER: assert property (
        (current_state == PROCESS && !power_enable) |-> error_flag
    );

    // P12: error_flag asserted throughout ERROR state
    P12_ERROR_FLAG_IN_ERROR: assert property (
        (current_state == ERROR) |-> error_flag
    );

    // P13: No spurious error_flag in IDLE (when not in PROCESS/ERROR)
    P13_NO_ERROR_IN_IDLE: assert property (
        (current_state == IDLE) |-> !error_flag
    );

    // =========================================================================
    // ARITHMETIC CORRECTNESS PROPERTIES
    // =========================================================================

    // P14: ADD result correctness (unsigned carry included in RES_W)
    P14_ADD_CORRECT: assert property (
        (current_state == PROCESS && opcode == 2'b00 && secure_access && power_enable)
        |-> (result == ({1'b0, data_a} + {1'b0, data_b}))
    );

    // P15: SUB result correctness (signed-safe)
    P15_SUB_CORRECT: assert property (
        (current_state == PROCESS && opcode == 2'b01 && secure_access && power_enable)
        |-> (result == ($signed({1'b0, data_a}) - $signed({1'b0, data_b})))
    );

    // P16: AND result correctness
    P16_AND_CORRECT: assert property (
        (current_state == PROCESS && opcode == 2'b10 && secure_access && power_enable)
        |-> (result == {1'b0, data_a & data_b})
    );

    // P17: XOR result correctness
    P17_XOR_CORRECT: assert property (
        (current_state == PROCESS && opcode == 2'b11 && secure_access && power_enable)
        |-> (result == {1'b0, data_a ^ data_b})
    );

    // =========================================================================
    // COVER POINTS  (reachability – all states must be reachable)
    // =========================================================================

    COVER_IDLE    : cover property (current_state == IDLE);
    COVER_PROCESS : cover property (current_state == PROCESS);
    COVER_DONE    : cover property (current_state == DONE);
    COVER_ERROR   : cover property (current_state == ERROR);

    // Cover: error from security violation is reachable
    COVER_SEC_ERROR : cover property (
        (current_state == PROCESS && !secure_access) ##1 (current_state == ERROR)
    );

    // Cover: successful full transaction IDLE->PROCESS->DONE->IDLE
    COVER_HAPPY_PATH : cover property (
        (current_state == IDLE) ##1 (current_state == PROCESS)
        ##1 (current_state == DONE) ##1 (current_state == IDLE)
    );

endmodule

// ============================================================================
// Bind statement – connects property module to DUT without modifying DUT code
// ============================================================================
bind jaspergold_complete_design FSM_arithmetic_properties #(
    .DATA_W (DATA_W),
    .RES_W  (RES_W)
) prop_inst (
    .clk           (clk),
    .rst           (rst),
    .req           (req),
    .grant         (grant),
    .data_a        (data_a),
    .data_b        (data_b),
    .opcode        (opcode),
    .secure_access (secure_access),
    .power_enable  (power_enable),
    .result        (result),
    .valid         (valid),
    .error_flag    (error_flag),
    .current_state (current_state)
);
