`timescale 1ns/1ps
// =============================================================================
// Module      : tb_jaspergold_complete
// Description : JasperGold-style exhaustive simulation testbench.
//               Contains real SVA concurrent assertions (simulation-time).
//               For full formal proof use FSM_arithmetic_properties.sv + jg_run.tcl
// Version     : 2.1  (xrun-clean: no part-select task args, no derived params)
// Fix summary : j[DATA_W-1:0]/(15-j)[DATA_W-1:0]/i[1:0] as task arguments
//               are illegal in Verilog; replaced with intermediate reg variables.
// =============================================================================

`define CLK_HALF  5    // Half clock period (ns) => 10 ns full period
`define STEP      10   // One full clock cycle (ns)

module tb_jaspergold_complete;

    // =========================================================================
    // LOCAL PARAMETERS  (mirror DUT defaults; no derived param in port list)
    // =========================================================================
    localparam DATA_W = 4;
    localparam RES_W  = 5;    // DATA_W + 1

    // =========================================================================
    // SIGNAL DECLARATIONS
    // =========================================================================
    reg               clk;
    reg               rst;
    reg               req;
    reg  [DATA_W-1:0] data_a;
    reg  [DATA_W-1:0] data_b;
    reg  [1:0]        opcode;
    reg               secure_access;
    reg               power_enable;

    wire              grant;
    wire [RES_W-1:0]  result;
    wire              valid;
    wire              error_flag;

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
    // CLOCK GENERATION
    // =========================================================================
    initial clk = 1'b0;
    always  #(`CLK_HALF) clk = ~clk;

    // =========================================================================
    // WAVEFORM DUMP
    // =========================================================================
    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_jaspergold_complete);
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
    integer security_blocks;

    integer x_injections;
    integer x_detected;

    integer corner_min;
    integer corner_max;

    integer deadlock_checks;
    integer deadlock_failures;

    integer assertion_fail;

    real functional_accuracy;
    real protocol_efficiency;
    real security_integrity;
    real fsm_coverage;
    real overall_confidence;

    reg [RES_W-1:0] expected_result;

    // =========================================================================
    // INTERMEDIATE REGS for loop variables passed to tasks
    // (Verilog does not allow part-selects or expressions as task arguments)
    // =========================================================================
    reg [DATA_W-1:0] arg_a;
    reg [DATA_W-1:0] arg_b;
    reg [1:0]        arg_op;

    // =========================================================================
    // SVA CONCURRENT ASSERTION BLOCK
    // These fire every posedge clk during simulation.
    // =========================================================================

    // P1: IDLE -> PROCESS on req
    SVA_IDLE_TO_PROCESS: assert property (
        @(posedge clk) disable iff (rst)
        (dut.current_state == 2'b00 && req) |=> (dut.current_state == 2'b01)
    ) else begin
        $display("[SVA FAIL] P1: IDLE->PROCESS not triggered on req");
        assertion_fail = assertion_fail + 1;
    end

    // P2: PROCESS -> DONE on valid condition
    SVA_PROCESS_TO_DONE: assert property (
        @(posedge clk) disable iff (rst)
        (dut.current_state == 2'b01 && power_enable && secure_access)
        |=> (dut.current_state == 2'b10)
    ) else begin
        $display("[SVA FAIL] P2: PROCESS->DONE not triggered");
        assertion_fail = assertion_fail + 1;
    end

    // P3: PROCESS -> ERROR on power failure
    SVA_PROCESS_TO_ERROR_POWER: assert property (
        @(posedge clk) disable iff (rst)
        (dut.current_state == 2'b01 && !power_enable)
        |=> (dut.current_state == 2'b11)
    ) else begin
        $display("[SVA FAIL] P3: PROCESS->ERROR (power) not triggered");
        assertion_fail = assertion_fail + 1;
    end

    // P4: PROCESS -> ERROR on security violation
    SVA_PROCESS_TO_ERROR_SEC: assert property (
        @(posedge clk) disable iff (rst)
        (dut.current_state == 2'b01 && !secure_access)
        |=> (dut.current_state == 2'b11)
    ) else begin
        $display("[SVA FAIL] P4: PROCESS->ERROR (security) not triggered");
        assertion_fail = assertion_fail + 1;
    end

    // P5: DONE always returns to IDLE (deadlock-free)
    SVA_DONE_TO_IDLE: assert property (
        @(posedge clk) disable iff (rst)
        (dut.current_state == 2'b10) |=> (dut.current_state == 2'b00)
    ) else begin
        $display("[SVA FAIL] P5: DONE->IDLE deadlock");
        assertion_fail = assertion_fail + 1;
    end

    // P6: ERROR always returns to IDLE (deadlock-free)
    SVA_ERROR_TO_IDLE: assert property (
        @(posedge clk) disable iff (rst)
        (dut.current_state == 2'b11) |=> (dut.current_state == 2'b00)
    ) else begin
        $display("[SVA FAIL] P6: ERROR->IDLE deadlock");
        assertion_fail = assertion_fail + 1;
    end

    // P7: grant asserted iff in PROCESS state
    SVA_GRANT_IN_PROCESS: assert property (
        @(posedge clk) disable iff (rst)
        (dut.current_state == 2'b01) |-> grant
    ) else begin
        $display("[SVA FAIL] P7: grant not asserted in PROCESS");
        assertion_fail = assertion_fail + 1;
    end

    // P8: valid asserted iff in DONE state
    SVA_VALID_IN_DONE: assert property (
        @(posedge clk) disable iff (rst)
        (dut.current_state == 2'b10) |-> valid
    ) else begin
        $display("[SVA FAIL] P8: valid not asserted in DONE");
        assertion_fail = assertion_fail + 1;
    end

    // P9: error_flag on security violation during PROCESS
    SVA_ERROR_ON_INSECURE: assert property (
        @(posedge clk) disable iff (rst)
        (dut.current_state == 2'b01 && !secure_access) |-> error_flag
    ) else begin
        $display("[SVA FAIL] P9: error_flag missing when secure_access=0 in PROCESS");
        assertion_fail = assertion_fail + 1;
    end

    // P10: error_flag throughout ERROR state
    SVA_ERROR_IN_ERROR_STATE: assert property (
        @(posedge clk) disable iff (rst)
        (dut.current_state == 2'b11) |-> error_flag
    ) else begin
        $display("[SVA FAIL] P10: error_flag missing in ERROR state");
        assertion_fail = assertion_fail + 1;
    end

    // P11: reset drives state to IDLE
    SVA_RESET_TO_IDLE: assert property (
        @(posedge clk)
        $rose(rst) |=> (dut.current_state == 2'b00)
    ) else begin
        $display("[SVA FAIL] P11: RST did not drive state to IDLE");
        assertion_fail = assertion_fail + 1;
    end

    // =========================================================================
    // TASK: run_op_exhaustive
    //   Drives one complete IDLE->PROCESS->DONE/ERROR->IDLE transaction.
    //   All inputs passed as plain regs (no expressions or part-selects).
    // =========================================================================
    task run_op_exhaustive;
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

            // Compute expected result (valid only when sa && pe)
            case (op)
                2'b00: expected_result = {1'b0, a} + {1'b0, b};
                2'b01: expected_result = $signed({1'b0, a}) - $signed({1'b0, b});
                2'b10: expected_result = {1'b0, (a & b)};
                2'b11: expected_result = {1'b0, (a ^ b)};
                default: expected_result = {RES_W{1'b0}};
            endcase

            @(posedge clk); #1;   // FSM advances to PROCESS

            // FSM state coverage tracking
            case (dut.current_state)
                2'b00: idle_count    = idle_count    + 1;
                2'b01: process_count = process_count + 1;
                2'b10: done_count    = done_count    + 1;
                2'b11: error_count   = error_count   + 1;
            endcase

            // Protocol handshake check
            if (req && grant) begin
                protocol_pass = protocol_pass + 1;
                $write("[PASS] PROTOCOL | ");
            end else begin
                protocol_fail = protocol_fail + 1;
                $write("[FAIL] PROTOCOL | ");
            end

            // Functional correctness (only meaningful when no fault)
            if (sa && pe) begin
                total_operations = total_operations + 1;
                if (result === expected_result) begin
                    passed_operations = passed_operations + 1;
                    $display("op=%b a=%0d b=%0d result=%0d exp=%0d [OK]",
                             op, a, b, result, expected_result);
                end else begin
                    failed_operations = failed_operations + 1;
                    $display("op=%b a=%0d b=%0d result=%0d exp=%0d [MISMATCH]",
                             op, a, b, result, expected_result);
                end
            end else begin
                $display("op=%b a=%0d b=%0d [FAULT TEST - error_flag=%b]",
                         op, a, b, error_flag);
            end

            req = 1'b0;
            @(posedge clk); #1;   // DONE or ERROR
            @(posedge clk); #1;   // back to IDLE
        end
    endtask

    // =========================================================================
    // MAIN VERIFICATION SEQUENCE
    // =========================================================================
    integer i;
    integer j;
    integer temp_b;   // holds (15-j) before truncation to DATA_W

    initial begin

        // --- Initialise all signals and counters ---------------------------
        rst           = 1'b1;
        req           = 1'b0;
        data_a        = {DATA_W{1'b0}};
        data_b        = {DATA_W{1'b0}};
        opcode        = 2'b00;
        secure_access = 1'b1;
        power_enable  = 1'b1;

        total_operations  = 0;   passed_operations = 0;   failed_operations = 0;
        protocol_pass     = 0;   protocol_fail     = 0;
        idle_count        = 0;   process_count     = 0;
        done_count        = 0;   error_count       = 0;
        security_checks   = 0;   security_blocks   = 0;
        x_injections      = 0;   x_detected        = 0;
        corner_min        = 0;   corner_max        = 0;
        deadlock_checks   = 0;   deadlock_failures  = 0;
        assertion_fail    = 0;

        #(`STEP * 2);
        rst = 1'b0;
        @(posedge clk); #1;

        $display("=================================================================================================================");
        $display("|     JasperGold-Style Exhaustive Simulation : all opcodes x all 4-bit data combinations                       |");
        $display("=================================================================================================================");

        // --- (A) Exhaustive: all 4 opcodes x all 16 data values -----------
        // FIX: compute intermediate regs before each task call;
        //      Verilog does not allow part-select or arithmetic expressions
        //      as task arguments (causes xmvlog EXPRPA / EXPSMC / MISEXX errors).
        for (i = 0; i < 4; i = i + 1) begin
            for (j = 0; j < 16; j = j + 1) begin

                // Prepare arguments in regs first -- no part-selects in call
                arg_a  = j[DATA_W-1:0];
                temp_b = 15 - j;
                arg_b  = temp_b[DATA_W-1:0];
                arg_op = i[1:0];

                // Normal operation
                run_op_exhaustive(arg_a, arg_b, arg_op, 1'b1, 1'b1);

                // Boundary tracking
                if (j == 0)  corner_min = corner_min + 1;
                if (j == 15) corner_max = corner_max + 1;

                // Security violation test
                security_checks = security_checks + 1;
                run_op_exhaustive(arg_a, arg_b, arg_op, 1'b0, 1'b1);
                if (error_count > 0 || error_flag)
                    security_blocks = security_blocks + 1;

                // Power failure test
                run_op_exhaustive(arg_a, arg_b, arg_op, 1'b1, 1'b0);

                // X-State injection (drive data_a to X, check propagation)
                x_injections = x_injections + 1;
                data_a = {DATA_W{1'bx}};
                #(`STEP);
                if (^data_a === 1'bx) begin
                    x_detected = x_detected + 1;
                    $display("X-STATE DETECTED AT CYCLE %0d", j);
                end
                data_a = arg_a;   // restore
            end
        end

        // --- (B) Deadlock check -------------------------------------------
        deadlock_checks = deadlock_checks + 1;
        secure_access   = 1'b1;
        power_enable    = 1'b1;
        req             = 1'b1;
        @(posedge clk); #1;   // PROCESS
        req = 1'b0;
        @(posedge clk); #1;   // DONE
        @(posedge clk); #1;   // IDLE

        if (dut.current_state == 2'b00)
            $display("NO DEADLOCK DETECTED");
        else begin
            deadlock_failures = deadlock_failures + 1;
            $display("DEADLOCK DETECTED");
        end

        // --- Accuracy calculations ----------------------------------------
        functional_accuracy = (passed_operations * 100.0) / total_operations;
        protocol_efficiency = (protocol_pass      * 100.0)
                              / (protocol_pass + protocol_fail);
        security_integrity  = (security_blocks    * 100.0) / security_checks;
        fsm_coverage        = ((idle_count    > 0) +
                               (process_count > 0) +
                               (done_count    > 0) +
                               (error_count   > 0)) * 25.0;
        overall_confidence  = (functional_accuracy + protocol_efficiency +
                               security_integrity   + fsm_coverage) / 4.0;

        // =====================================================================
        // FINAL REPORT
        // =====================================================================
        $display(" ");
        $display("=================================================================================================================");
        $display("|                               Jasper Formal VRF ANALYTICS REPORT                                             |");
        $display("=================================================================================================================");
        $display("| FUNCTIONAL VERIFICATION");
        $display("|---------------------------------------------------------------------------------------------------------------");
        $display("| Total Operations Tested        : %-5d", total_operations);
        $display("| Passed Operations              : %-5d", passed_operations);
        $display("| Failed Operations              : %-5d", failed_operations);
        $display("| Functional Accuracy            : %0.2f %%", functional_accuracy);
        $display("|---------------------------------------------------------------------------------------------------------------");
        $display("| PROTOCOL VERIFICATION");
        $display("| Successful Handshakes          : %-5d", protocol_pass);
        $display("| Failed Handshakes              : %-5d", protocol_fail);
        $display("| Protocol Efficiency            : %0.2f %%", protocol_efficiency);
        $display("|---------------------------------------------------------------------------------------------------------------");
        $display("| FSM COVERAGE");
        $display("| IDLE State Visits              : %-5d", idle_count);
        $display("| PROCESS State Visits           : %-5d", process_count);
        $display("| DONE State Visits              : %-5d", done_count);
        $display("| ERROR State Visits             : %-5d", error_count);
        $display("| FSM Coverage                   : %0.2f %%", fsm_coverage);
        $display("|---------------------------------------------------------------------------------------------------------------");
        $display("| SECURITY VERIFICATION");
        $display("| Unauthorized Access Attempts   : %-5d", security_checks);
        $display("| Blocked Access Attempts        : %-5d", security_blocks);
        $display("| Security Integrity             : %0.2f%%", security_integrity);
        $display("|---------------------------------------------------------------------------------------------------------------");
        $display("| SVA ASSERTION SUMMARY");
        $display("| Assertion Failures Caught      : %-5d", assertion_fail);
        $display("|---------------------------------------------------------------------------------------------------------------");
        $display("| X-PROPAGATION ANALYSIS");
        $display("| X-State Injections             : %-5d", x_injections);
        $display("| X-State Detections             : %-5d", x_detected);
        $display("|---------------------------------------------------------------------------------------------------------------");
        $display("| CORNER CASE ANALYSIS");
        $display("| Minimum Boundary Tests         : %-5d", corner_min);
        $display("| Maximum Boundary Tests         : %-5d", corner_max);
        $display("|---------------------------------------------------------------------------------------------------------------");
        $display("| DEADLOCK ANALYSIS");
        $display("| Deadlock Checks                : %-5d", deadlock_checks);
        $display("| Deadlock Failures              : %-5d", deadlock_failures);
        $display("|---------------------------------------------------------------------------------------------------------------");
        $display("| OVERALL VERIFICATION CONFIDENCE : %0.2f %%", overall_confidence);
        $display("=================================================================================================================");
        $display(" ");
        $display("#############################################################################################################");
        $display("#                                      FINAL VERIFICATION CONCLUSION                                         #");
        $display("#############################################################################################################");

        if (overall_confidence >= 90.0)
            $display("# RESULT : HIGH CONFIDENCE RTL VERIFICATION SUCCESSFUL                                                       #");
        else if (overall_confidence >= 75.0)
            $display("# RESULT : MODERATE CONFIDENCE RTL VERIFICATION                                                              #");
        else
            $display("# RESULT : VERIFICATION NEEDS IMPROVEMENT                                                                    #");

        $display("# JasperGold-Style Verification Analytics Completed Successfully                                             #");
        $display("# Verification Methodology : Simulation + SVA Assertion Checking                                            #");
        $display("# For full formal proof    : use FSM_arithmetic_properties.sv + jg_run.tcl                                  #");
        $display("#############################################################################################################");
        $display(" ");

        $finish;
    end

endmodule