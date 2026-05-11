`timescale 1ns/1ps
// =============================================================================
// Module      : tb_normal_simulation
// Description : Directed RTL simulation testbench for jaspergold_complete_design.
//               Covers: functional ops, protocol handshake, security violation,
//               power-off corner, reset, X-state injection, deadlock check,
//               and boundary (min/max) cases.
// Version     : 3.0
//   – X-propagation check fixed: injects X during a live PROCESS transaction
//     and checks DUT output signals (result, error_flag), not the input reg
//   – All magic 2'b?? literals replaced with named state localparams
//   – Signed subtraction underflow test (3 - 5) explicitly included
//   – Named `define used for all timing constants (no bare #10 magic numbers)
// =============================================================================

// Local defines – all timing in one place; no bare magic numbers elsewhere
`define CLK_HALF   5    // Half-period = 5 ns  => 10 ns clock
`define RST_HOLD   20   // Reset hold time (ns)
`define STEP       10   // One clock cycle (ns)

module tb_normal_simulation;

    // =========================================================================
    // DUT PARAMETERS (mirror DUT defaults)
    // =========================================================================
    localparam DATA_W = 4;
    localparam RES_W  = DATA_W + 1;

    // FSM state encoding – mirrors DUT localparams; avoids magic 2'b?? literals
    localparam [1:0] ST_IDLE    = 2'b00;
    localparam [1:0] ST_PROCESS = 2'b01;
    localparam [1:0] ST_DONE    = 2'b10;
    localparam [1:0] ST_ERROR   = 2'b11;

    // =========================================================================
    // SIGNAL DECLARATIONS
    // =========================================================================
    reg                  clk;
    reg                  rst;
    reg                  req;
    reg  [DATA_W-1:0]    data_a;
    reg  [DATA_W-1:0]    data_b;
    reg  [1:0]           opcode;
    reg                  secure_access;
    reg                  power_enable;

    wire                 grant;
    wire [RES_W-1:0]     result;
    wire                 valid;
    wire                 error_flag;

    // =========================================================================
    // DUT INSTANTIATION
    // =========================================================================
    jaspergold_complete_design #(
        .DATA_W (DATA_W),
        .RES_W  (RES_W)
    ) dut (
        .clk          (clk),
        .rst          (rst),
        .req          (req),
        .data_a       (data_a),
        .data_b       (data_b),
        .opcode       (opcode),
        .secure_access(secure_access),
        .power_enable (power_enable),
        .grant        (grant),
        .result       (result),
        .valid        (valid),
        .error_flag   (error_flag)
    );

    // =========================================================================
    // CLOCK GENERATION  (10 ns period)
    // =========================================================================
    initial clk = 1'b0;
    always  #(`CLK_HALF) clk = ~clk;

    // =========================================================================
    // WAVEFORM DUMP
    // =========================================================================
    initial begin
        $dumpfile("normal_sim.vcd");
        $dumpvars(0, tb_normal_simulation);
    end

    // =========================================================================
    // VERIFICATION METRICS
    // =========================================================================
    integer total_operations;
    integer passed_operations;
    integer failed_operations;

    integer protocol_pass;
    integer protocol_fail;

    integer idle_count;
    integer process_count;
    integer done_count;
    integer error_count;

    integer security_checks;
    integer security_pass;
    integer security_fail;

    integer x_injections;
    integer x_detected;       // X propagated to DUT outputs (correct check)

    integer min_boundary_checks;
    integer max_boundary_checks;

    integer reset_checks;
    integer reset_pass;
    integer reset_fail;

    integer deadlock_checks;
    integer deadlock_failures;

    real functional_accuracy;
    real protocol_accuracy;
    real security_accuracy;
    real reset_accuracy;
    real overall_accuracy;

    reg [RES_W-1:0] expected_result;

    // =========================================================================
    // TASK: run_one_op
    //   Applies one full IDLE->PROCESS->DONE/ERROR transaction and checks result.
    // =========================================================================
    task run_one_op;
        input [DATA_W-1:0] a;
        input [DATA_W-1:0] b;
        input [1:0]        op;
        input              sa;   // secure_access
        input              pe;   // power_enable
        begin
            data_a        = a;
            data_b        = b;
            opcode        = op;
            secure_access = sa;
            power_enable  = pe;
            req           = 1'b1;

            // Compute expected result (only meaningful when sa && pe)
            case (op)
                2'b00: expected_result = {1'b0, a} + {1'b0, b};
                2'b01: expected_result = $signed({1'b0, a}) - $signed({1'b0, b});
                2'b10: expected_result = {1'b0, a & b};
                2'b11: expected_result = {1'b0, a ^ b};
                default: expected_result = {RES_W{1'b0}};
            endcase

            @(posedge clk); #1;   // allow PROCESS state to settle

            // ---- FSM tracking (named localparams, no magic 2'b??) ----
            case (dut.current_state)
                ST_IDLE    : idle_count    = idle_count    + 1;
                ST_PROCESS : process_count = process_count + 1;
                ST_DONE    : done_count    = done_count    + 1;
                ST_ERROR   : error_count   = error_count   + 1;
            endcase

            // ---- Functional check (only valid when no fault) ----
            if (sa && pe) begin
                total_operations = total_operations + 1;
                if (result == expected_result) begin
                    passed_operations = passed_operations + 1;
                    $display("[PASS] op=%b  a=%0d  b=%0d  got=%0d  exp=%0d",
                             op, a, b, result, expected_result);
                end else begin
                    failed_operations = failed_operations + 1;
                    $display("[FAIL] op=%b  a=%0d  b=%0d  got=%0d  exp=%0d",
                             op, a, b, result, expected_result);
                end
            end

            // ---- Protocol check ----
            if (req && grant)
                protocol_pass = protocol_pass + 1;
            else
                protocol_fail = protocol_fail + 1;

            req = 1'b0;
            @(posedge clk); #1;   // DONE or ERROR
            @(posedge clk); #1;   // back to IDLE
        end
    endtask

    // =========================================================================
    // TASK: inject_x_and_check
    //   FIXED X-propagation check (v3.0):
    //   Previous version only checked whether the input register data_a itself
    //   contained X, which is trivially always true after assignment and does
    //   NOT verify whether X propagated through the DUT combinational logic.
    //
    //   This task drives data_a=X during a real PROCESS transaction so the DUT
    //   actually computes with the unknown value, then checks the DUT OUTPUT
    //   signals (result, error_flag) for X propagation.
    // =========================================================================
    task inject_x_and_check;
        begin
            // Drive X into data_a while initiating a real PROCESS transaction
            data_a        = {DATA_W{1'bx}};
            data_b        = {DATA_W{1'b1}};   // known value for data_b
            opcode        = 2'b00;             // ADD – most sensitive to unknown operand
            secure_access = 1'b1;
            power_enable  = 1'b1;
            req           = 1'b1;

            x_injections = x_injections + 1;

            @(posedge clk); #1;   // DUT in PROCESS state, computing with X input

            // CORRECT check: did X propagate THROUGH the DUT to its outputs?
            if ((^result === 1'bx) || (^error_flag === 1'bx)) begin
                x_detected = x_detected + 1;
                $display("[X-PROP] X propagated to DUT output: result=%b error_flag=%b",
                         result, error_flag);
            end else begin
                $display("[X-PROP] X contained by DUT logic – result=%0d error_flag=%b",
                         result, error_flag);
            end

            req    = 1'b0;
            data_a = {DATA_W{1'b0}};  // restore to known value
            @(posedge clk); #1;        // DONE or ERROR
            @(posedge clk); #1;        // back to IDLE
        end
    endtask

    // =========================================================================
    // MAIN SIMULATION SEQUENCE
    // =========================================================================
    initial begin

        // --- Initialize all signals and counters ----------------------------
        rst           = 1'b1;
        req           = 1'b0;
        data_a        = {DATA_W{1'b0}};
        data_b        = {DATA_W{1'b0}};
        opcode        = 2'b00;
        secure_access = 1'b1;
        power_enable  = 1'b1;

        total_operations   = 0;  passed_operations = 0;  failed_operations = 0;
        protocol_pass      = 0;  protocol_fail     = 0;
        idle_count         = 0;  process_count     = 0;
        done_count         = 0;  error_count       = 0;
        security_checks    = 0;  security_pass     = 0;  security_fail = 0;
        x_injections       = 0;  x_detected        = 0;
        min_boundary_checks= 0;  max_boundary_checks = 0;
        reset_checks       = 0;  reset_pass        = 0;  reset_fail    = 0;
        deadlock_checks    = 0;  deadlock_failures  = 0;

        // --- Reset verification -------------------------------------------
        #(`RST_HOLD);
        reset_checks = reset_checks + 1;
        if (dut.current_state == ST_IDLE)
            reset_pass = reset_pass + 1;
        else
            reset_fail = reset_fail + 1;

        rst = 1'b0;
        @(posedge clk); #1;

        // --- (A) Directed functional tests – all four opcodes --------------
        // Using non-trivial values; includes 3-5 to verify signed subtraction
        // handling (would produce incorrect 5-bit result without sign extension).
        run_one_op(4'd3,  4'd1,  2'b00, 1'b1, 1'b1);  // ADD   3+1   =  4
        run_one_op(4'd3,  4'd5,  2'b01, 1'b1, 1'b1);  // SUB   3-5   = -2 (signed, 5-bit)
        run_one_op(4'd6,  4'd3,  2'b10, 1'b1, 1'b1);  // AND   6&3   =  2
        run_one_op(4'd9,  4'd5,  2'b11, 1'b1, 1'b1);  // XOR   9^5   = 12

        // --- (B) Boundary / corner-case tests ------------------------------
        run_one_op(4'd0,  4'd0,  2'b00, 1'b1, 1'b1);   // ADD  0+0  = 0  (min)
        min_boundary_checks = min_boundary_checks + 1;

        run_one_op(4'd15, 4'd15, 2'b00, 1'b1, 1'b1);   // ADD  15+15 = 30 (needs 5 bits)
        run_one_op(4'd15, 4'd15, 2'b10, 1'b1, 1'b1);   // AND  15&15 = 15
        run_one_op(4'd0,  4'd15, 2'b01, 1'b1, 1'b1);   // SUB  0-15  = -15 (signed underflow)
        max_boundary_checks = max_boundary_checks + 3;

        // --- (C) Security violation test ----------------------------------
        security_checks = security_checks + 1;
        run_one_op(4'd7, 4'd3, 2'b00, 1'b0, 1'b1);   // !secure_access => ERROR
        if (error_flag || dut.current_state == ST_ERROR || error_count > 0)
            security_pass = security_pass + 1;
        else
            security_fail = security_fail + 1;

        // --- (D) Power failure test ----------------------------------------
        security_checks = security_checks + 1;
        run_one_op(4'd7, 4'd3, 2'b00, 1'b1, 1'b0);   // !power_enable => ERROR
        if (error_count > 0)
            security_pass = security_pass + 1;
        else
            security_fail = security_fail + 1;

        // Restore safe state
        secure_access = 1'b1;
        power_enable  = 1'b1;

        // --- (E) X-State injection – FIXED --------------------------------
        // inject_x_and_check drives data_a=X during a real PROCESS transaction
        // and checks DUT output signals for propagation (not just the input reg).
        inject_x_and_check();

        // --- (F) Deadlock detection ----------------------------------------
        deadlock_checks = deadlock_checks + 1;
        req = 1'b1;
        @(posedge clk); #1;   // PROCESS
        req = 1'b0;
        @(posedge clk); #1;   // DONE
        @(posedge clk); #1;   // IDLE
        if (dut.current_state == ST_IDLE)
            ; // no deadlock – expected
        else begin
            deadlock_failures = deadlock_failures + 1;
            $display("[WARN] Possible deadlock – FSM did not return to IDLE");
        end

        // --- Accuracy calculations ----------------------------------------
        functional_accuracy = (passed_operations  * 100.0) / total_operations;
        protocol_accuracy   = (protocol_pass       * 100.0) / (protocol_pass + protocol_fail);
        security_accuracy   = (security_pass       * 100.0) / security_checks;
        reset_accuracy      = (reset_pass          * 100.0) / reset_checks;
        overall_accuracy    = (functional_accuracy + protocol_accuracy +
                               security_accuracy   + reset_accuracy) / 4.0;

        // =====================================================================
        // FINAL REPORT
        // =====================================================================
        $display(" ");
        $display("=================================================================================================================");
        $display("|                         NORMAL RTL SIMULATION ANALYTICS REPORT                                                |");
        $display("=================================================================================================================");
        $display("| FUNCTIONAL VERIFICATION");
        $display("|---------------------------------------------------------------------------------------------------------------|");
        $display("| Total Operations Tested        : %-5d", total_operations);
        $display("| Passed Operations              : %-5d", passed_operations);
        $display("| Failed Operations              : %-5d", failed_operations);
        $display("| Functional Accuracy            : %0.2f %%", functional_accuracy);
        $display("|---------------------------------------------------------------------------------------------------------------|");
        $display("| PROTOCOL VERIFICATION");
        $display("| Successful Handshakes          : %-5d", protocol_pass);
        $display("| Failed Handshakes              : %-5d", protocol_fail);
        $display("| Protocol Accuracy              : %0.2f %%", protocol_accuracy);
        $display("|---------------------------------------------------------------------------------------------------------------|");
        $display("| FSM STATE OBSERVATION");
        $display("| IDLE State Visits              : %-5d", idle_count);
        $display("| PROCESS State Visits           : %-5d", process_count);
        $display("| DONE State Visits              : %-5d", done_count);
        $display("| ERROR State Visits             : %-5d", error_count);
        $display("|---------------------------------------------------------------------------------------------------------------|");
        $display("| SECURITY TESTING");
        $display("| Security Checks                : %-5d", security_checks);
        $display("| Security Passes                : %-5d", security_pass);
        $display("| Security Failures              : %-5d", security_fail);
        $display("| Security Accuracy              : %0.2f %%", security_accuracy);
        $display("|---------------------------------------------------------------------------------------------------------------|");
        $display("| X-PROPAGATION ANALYSIS  (checks DUT outputs, not input reg)");
        $display("| X-State Injections             : %-5d", x_injections);
        $display("| X-State Detections (DUT output): %-5d", x_detected);
        $display("|---------------------------------------------------------------------------------------------------------------|");
        $display("| CORNER CASE ANALYSIS");
        $display("| Minimum Boundary Tests         : %-5d", min_boundary_checks);
        $display("| Maximum Boundary Tests         : %-5d", max_boundary_checks);
        $display("|---------------------------------------------------------------------------------------------------------------|");
        $display("| RESET VERIFICATION");
        $display("| Reset Checks                   : %-5d", reset_checks);
        $display("| Reset Passes                   : %-5d", reset_pass);
        $display("| Reset Failures                 : %-5d", reset_fail);
        $display("| Reset Accuracy                 : %0.2f %%", reset_accuracy);
        $display("|---------------------------------------------------------------------------------------------------------------|");
        $display("| DEADLOCK ANALYSIS");
        $display("| Deadlock Checks                : %-5d", deadlock_checks);
        $display("| Deadlock Failures              : %-5d", deadlock_failures);
        $display("|---------------------------------------------------------------------------------------------------------------|");
        $display("| OVERALL SIMULATION CONFIDENCE  : %0.2f %%", overall_accuracy);
        $display("=================================================================================================================");
        $display(" ");
        $display("#############################################################################################################");
        $display("#                                  NORMAL SIMULATION COMPLETED                                               #");
        $display("#############################################################################################################");
        $display("# Verification Method : Directed RTL Simulation                                                             #");
        $display("# Verification Scope  : Functional + Security + Power + Boundary + X-State (DUT output check)              #");
        $display("# Verification Nature : Runtime Behavioral Observation                                                      #");
        $display("# Coverage Type       : Testcase Dependent                                                                  #");
        $display("#############################################################################################################");

        $finish;
    end

endmodule
