// =============================================================================
// File        : FSM_arithmetic_properties.sv
// Description : Standalone SystemVerilog Assertion (SVA) property module
//               for use with Cadence JasperGold Formal Verification.
//               Bound to the DUT via the 'bind' statement at the bottom –
//               the DUT source does not need to be modified.
//
// Version     : 3.0
//   – Arithmetic correctness properties added (P14-P17)
//   – Both-direction signal checks (grant, valid, error_flag)
//   – Multi-step cover sequences for happy-path and error-path
//   – assume constraints to guide formal engine
//
// Usage (JasperGold TCL – see jg_run.tcl):
//   analyze -sv12 FSM_arithmetic_model.v FSM_arithmetic_properties.sv
//   elaborate  -top jaspergold_complete_design
//   prove -all
//   cover -all
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
    // Internal state exposed via bind for white-box property checking
    input wire [1:0]        current_state
);

    // =========================================================================
    // State encoding – must match DUT localparams exactly
    // =========================================================================
    localparam [1:0] IDLE    = 2'b00;
    localparam [1:0] PROCESS = 2'b01;
    localparam [1:0] DONE    = 2'b10;
    localparam [1:0] ERROR   = 2'b11;

    // Default clocking and reset for all properties in this module
    default clocking cb @(posedge clk); endclocking
    default disable iff (rst);

    // =========================================================================
    // ASSUMPTIONS  – constrain the formal engine's input space to legal
    // operating conditions so the engine doesn't explore physically impossible
    // stimulus sequences (e.g. opcode changing mid-PROCESS).
    // =========================================================================

    // A1: req pulses for exactly one cycle (de-asserts on the next cycle).
    //     This prevents the engine from holding req high indefinitely.
    ASSUME_REQ_PULSE: assume property (
        req |=> !req
    );

    // A2: data and opcode are stable while the FSM is in PROCESS.
    //     Changing inputs mid-operation is not part of the protocol spec.
    ASSUME_DATA_STABLE_IN_PROCESS: assume property (
        (current_state == PROCESS) |->
            ($stable(data_a) && $stable(data_b) && $stable(opcode))
    );

    // A3: control signals stable in PROCESS – no mid-operation power/security
    //     changes (consistent with realistic hardware behaviour).
    ASSUME_CTRL_STABLE_IN_PROCESS: assume property (
        (current_state == PROCESS) |->
            ($stable(power_enable) && $stable(secure_access))
    );

    // =========================================================================
    // FSM TRANSITION PROPERTIES
    // =========================================================================

    // P1: IDLE -> PROCESS whenever req is asserted
    P1_IDLE_TO_PROCESS: assert property (
        (current_state == IDLE && req) |=> (current_state == PROCESS)
    );

    // P2: PROCESS -> DONE when power and security are valid
    P2_PROCESS_TO_DONE: assert property (
        (current_state == PROCESS && power_enable && secure_access)
        |=> (current_state == DONE)
    );

    // P3: PROCESS -> ERROR on power failure
    P3_PROCESS_TO_ERROR_POWER: assert property (
        (current_state == PROCESS && !power_enable)
        |=> (current_state == ERROR)
    );

    // P4: PROCESS -> ERROR on security violation
    P4_PROCESS_TO_ERROR_SEC: assert property (
        (current_state == PROCESS && !secure_access)
        |=> (current_state == ERROR)
    );

    // P5: DONE always returns to IDLE (deadlock-free liveness)
    P5_DONE_TO_IDLE: assert property (
        (current_state == DONE) |=> (current_state == IDLE)
    );

    // P6: ERROR always returns to IDLE (deadlock-free liveness)
    P6_ERROR_TO_IDLE: assert property (
        (current_state == ERROR) |=> (current_state == IDLE)
    );

    // P7: Reset drives FSM to IDLE within one cycle
    P7_RESET_IDLE: assert property (
        @(posedge clk) $rose(rst) |=> (current_state == IDLE)
    );

    // =========================================================================
    // OUTPUT / SIGNAL CORRECTNESS PROPERTIES
    // =========================================================================

    // P8: grant asserted if and only if in PROCESS state
    P8_GRANT_IN_PROCESS: assert property (
        (current_state == PROCESS) |-> grant
    );

    P8b_NO_GRANT_OUTSIDE_PROCESS: assert property (
        (current_state != PROCESS) |-> !grant
    );

    // P9: valid asserted if and only if in DONE state
    P9_VALID_IN_DONE: assert property (
        (current_state == DONE) |-> valid
    );

    P9b_NO_VALID_OUTSIDE_DONE: assert property (
        (current_state != DONE) |-> !valid
    );

    // P10: error_flag raised on security violation while in PROCESS
    P10_ERROR_FLAG_INSECURE: assert property (
        (current_state == PROCESS && !secure_access) |-> error_flag
    );

    // P11: error_flag raised on power failure while in PROCESS
    P11_ERROR_FLAG_POWER: assert property (
        (current_state == PROCESS && !power_enable) |-> error_flag
    );

    // P12: error_flag asserted throughout ERROR state
    P12_ERROR_FLAG_IN_ERROR: assert property (
        (current_state == ERROR) |-> error_flag
    );

    // P13: No spurious error_flag in IDLE (clean baseline)
    P13_NO_ERROR_IN_IDLE: assert property (
        (current_state == IDLE) |-> !error_flag
    );

    // =========================================================================
    // ARITHMETIC CORRECTNESS PROPERTIES
    // (only meaningful when secure_access && power_enable – otherwise
    //  the DUT drives error_flag instead of a valid result)
    // =========================================================================

    // P14: ADD result is the unsigned sum with carry in MSB
    P14_ADD_CORRECT: assert property (
        (current_state == PROCESS && opcode == 2'b00
         && secure_access && power_enable)
        |-> (result == ({1'b0, data_a} + {1'b0, data_b}))
    );

    // P15: SUB result is signed-safe (handles underflow without truncation)
    P15_SUB_CORRECT: assert property (
        (current_state == PROCESS && opcode == 2'b01
         && secure_access && power_enable)
        |-> (result == ($signed({1'b0, data_a}) - $signed({1'b0, data_b})))
    );

    // P16: AND result is zero-extended bitwise AND
    P16_AND_CORRECT: assert property (
        (current_state == PROCESS && opcode == 2'b10
         && secure_access && power_enable)
        |-> (result == {1'b0, data_a & data_b})
    );

    // P17: XOR result is zero-extended bitwise XOR
    P17_XOR_CORRECT: assert property (
        (current_state == PROCESS && opcode == 2'b11
         && secure_access && power_enable)
        |-> (result == {1'b0, data_a ^ data_b})
    );

    // =========================================================================
    // COVER POINTS  – prove all four states and key multi-step sequences
    // are reachable (unreachable-state analysis).
    // =========================================================================

    COVER_IDLE    : cover property (current_state == IDLE);
    COVER_PROCESS : cover property (current_state == PROCESS);
    COVER_DONE    : cover property (current_state == DONE);
    COVER_ERROR   : cover property (current_state == ERROR);

    // Full happy-path transaction: IDLE -> PROCESS -> DONE -> IDLE
    COVER_HAPPY_PATH : cover property (
        (current_state == IDLE) ##1 (current_state == PROCESS)
        ##1 (current_state == DONE) ##1 (current_state == IDLE)
    );

    // Security-triggered error path: PROCESS (insecure) -> ERROR -> IDLE
    COVER_SEC_ERROR_PATH : cover property (
        (current_state == PROCESS && !secure_access)
        ##1 (current_state == ERROR)
        ##1 (current_state == IDLE)
    );

    // Power-triggered error path
    COVER_PWR_ERROR_PATH : cover property (
        (current_state == PROCESS && !power_enable)
        ##1 (current_state == ERROR)
        ##1 (current_state == IDLE)
    );

endmodule

// =============================================================================
// Bind statement – attaches the property module to the DUT without touching
// the DUT source code.  Requires -sv12 in JasperGold analyze command.
// =============================================================================
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
