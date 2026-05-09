`timescale 1ns/1ps

module tb_normal_simulation;

// =====================================================
// INPUTS
// =====================================================

reg clk;
reg rst;

reg req;

reg [3:0] data_a;
reg [3:0] data_b;

reg [1:0] opcode;

reg secure_access;
reg power_enable;

// =====================================================
// OUTPUTS
// =====================================================

wire grant;
wire [4:0] result;
wire valid;
wire error_flag;

// =====================================================
// DUT
// =====================================================

jaspergold_complete_design dut (

    .clk(clk),
    .rst(rst),

    .req(req),

    .data_a(data_a),
    .data_b(data_b),

    .opcode(opcode),

    .secure_access(secure_access),
    .power_enable(power_enable),

    .grant(grant),
    .result(result),
    .valid(valid),
    .error_flag(error_flag)

);

// =====================================================
// CLOCK
// =====================================================

always #5 clk = ~clk;

// =====================================================
// WAVEFORM
// =====================================================

initial
begin

    $dumpfile("normal_sim.vcd");
    $dumpvars(0, tb_normal_simulation);

end

// =====================================================
// VARIABLES
// =====================================================

integer i;

// Functional Metrics
integer total_operations;
integer passed_operations;
integer failed_operations;

// Protocol Metrics
integer protocol_pass;
integer protocol_fail;

// FSM Metrics
integer idle_count;
integer process_count;
integer done_count;
integer error_count;

// Security Metrics
integer security_checks;
integer security_pass;
integer security_fail;

// X-State Metrics
integer x_injections;
integer x_detected;

// Corner Metrics
integer min_boundary_checks;
integer max_boundary_checks;

// Reset Metrics
integer reset_checks;
integer reset_pass;
integer reset_fail;

// Deadlock Metrics
integer deadlock_checks;
integer deadlock_failures;

// Accuracy Values
real functional_accuracy;
real protocol_accuracy;
real security_accuracy;
real reset_accuracy;
real overall_accuracy;

// =====================================================
// EXPECTED RESULT
// =====================================================

reg [4:0] expected_result;

// =====================================================
// CLOCK INITIALIZATION
// =====================================================

initial
begin

    clk = 0;

end

// =====================================================
// MAIN TEST
// =====================================================

initial
begin

    // ================================================
    // INITIALIZATION
    // ================================================

    rst = 1;

    req = 0;

    data_a = 0;
    data_b = 0;

    opcode = 0;

    secure_access = 1;
    power_enable  = 1;

    total_operations = 0;
    passed_operations = 0;
    failed_operations = 0;

    protocol_pass = 0;
    protocol_fail = 0;

    idle_count = 0;
    process_count = 0;
    done_count = 0;
    error_count = 0;

    security_checks = 0;
    security_pass = 0;
    security_fail = 0;

    x_injections = 0;
    x_detected = 0;

    min_boundary_checks = 0;
    max_boundary_checks = 0;

    reset_checks = 0;
    reset_pass = 0;
    reset_fail = 0;

    deadlock_checks = 0;
    deadlock_failures = 0;

    #20;

    // ================================================
    // RESET CHECK
    // ================================================

    reset_checks = reset_checks + 1;

    if(dut.current_state == 2'b00)
        reset_pass = reset_pass + 1;
    else
        reset_fail = reset_fail + 1;

    rst = 0;

    // ================================================
    // DIRECTED TESTING
    // ================================================

    for(i = 0; i < 4; i = i + 1)
    begin

        req = 1;

        opcode = i;

        data_a = i + 3;
        data_b = i + 1;

        // ============================================
        // EXPECTED RESULT
        // ============================================

        case(opcode)

            2'b00:
                expected_result = data_a + data_b;

            2'b01:
                expected_result = data_a - data_b;

            2'b10:
                expected_result = data_a & data_b;

            2'b11:
                expected_result = data_a ^ data_b;

        endcase

        #10;

        total_operations = total_operations + 1;

        // ============================================
        // FSM TRACKING
        // ============================================

        case(dut.current_state)

            2'b00:
                idle_count = idle_count + 1;

            2'b01:
                process_count = process_count + 1;

            2'b10:
                done_count = done_count + 1;

            2'b11:
                error_count = error_count + 1;

        endcase

        // ============================================
        // FUNCTIONAL CHECK
        // ============================================

        if(result == expected_result)
            passed_operations = passed_operations + 1;
        else
            failed_operations = failed_operations + 1;

        // ============================================
        // PROTOCOL CHECK
        // ============================================

        if(req && grant)
            protocol_pass = protocol_pass + 1;
        else
            protocol_fail = protocol_fail + 1;

        // ============================================
        // SECURITY CHECK
        // ============================================

        security_checks = security_checks + 1;

        if(secure_access && !error_flag)
            security_pass = security_pass + 1;
        else
            security_fail = security_fail + 1;

        // ============================================
        // BOUNDARY CHECKS
        // ============================================

        if(data_a == 0 || data_b == 0)
            min_boundary_checks =
            min_boundary_checks + 1;

        if(data_a == 15 || data_b == 15)
            max_boundary_checks =
            max_boundary_checks + 1;

        // ============================================
        // RETURN TO NEXT STATE
        // ============================================

        #10;

        req = 0;

        #10;

    end

    // ================================================
    // SECURITY FAILURE TEST
    // ================================================

    secure_access = 0;

    req = 1;

    #10;

    security_checks = security_checks + 1;

    if(error_flag)
        security_pass = security_pass + 1;
    else
        security_fail = security_fail + 1;

    secure_access = 1;

    req = 0;

    // ================================================
    // X-STATE TEST
    // ================================================

    x_injections = x_injections + 1;

    data_a = 4'bxxxx;

    #10;

    if(^data_a === 1'bx)
        x_detected = x_detected + 1;

    // ================================================
    // DEADLOCK TEST
    // ================================================

    deadlock_checks = deadlock_checks + 1;

    req = 1;

    #20;

    if(valid != 1)
        deadlock_failures =
        deadlock_failures + 1;

    req = 0;

    // ================================================
    // ACCURACY CALCULATIONS
    // ================================================

    functional_accuracy =
    (passed_operations * 100.0) /
    total_operations;

    protocol_accuracy =
    (protocol_pass * 100.0) /
    (protocol_pass + protocol_fail);

    security_accuracy =
    (security_pass * 100.0) /
    security_checks;

    reset_accuracy =
    (reset_pass * 100.0) /
    reset_checks;

    overall_accuracy =
    (
        functional_accuracy +
        protocol_accuracy +
        security_accuracy +
        reset_accuracy
    ) / 4.0;

    // ================================================
    // FINAL REPORT
    // ================================================

    $display(" ");
    $display("=================================================================================================================");
    $display("|                         NORMAL RTL SIMULATION ANALYTICS REPORT                                                |");
    $display("=================================================================================================================");

    // ================================================
    // FUNCTIONAL
    // ================================================

    $display("| FUNCTIONAL VERIFICATION");

    $display("|---------------------------------------------------------------------------------------------------------------|");

    $display("| Total Operations Tested        : %-5d", total_operations);

    $display("| Passed Operations              : %-5d", passed_operations);

    $display("| Failed Operations              : %-5d", failed_operations);

    $display("| Functional Accuracy            : %0.2f %%", functional_accuracy);

    // ================================================
    // PROTOCOL
    // ================================================

    $display("|---------------------------------------------------------------------------------------------------------------|");

    $display("| PROTOCOL VERIFICATION");

    $display("| Successful Handshakes          : %-5d", protocol_pass);

    $display("| Failed Handshakes              : %-5d", protocol_fail);

    $display("| Protocol Accuracy              : %0.2f %%", protocol_accuracy);

    // ================================================
    // FSM
    // ================================================

    $display("|---------------------------------------------------------------------------------------------------------------|");

    $display("| FSM STATE OBSERVATION");

    $display("| IDLE State Visits              : %-5d", idle_count);

    $display("| PROCESS State Visits           : %-5d", process_count);

    $display("| DONE State Visits              : %-5d", done_count);

    $display("| ERROR State Visits             : %-5d", error_count);

    // ================================================
    // SECURITY
    // ================================================

    $display("|---------------------------------------------------------------------------------------------------------------|");

    $display("| SECURITY TESTING");

    $display("| Security Checks                : %-5d", security_checks);

    $display("| Security Passes                : %-5d", security_pass);

    $display("| Security Failures              : %-5d", security_fail);

    $display("| Security Accuracy              : %0.2f %%", security_accuracy);

    // ================================================
    // X STATE
    // ================================================

    $display("|---------------------------------------------------------------------------------------------------------------|");

    $display("| X-PROPAGATION ANALYSIS");

    $display("| X-State Injections             : %-5d", x_injections);

    $display("| X-State Detections             : %-5d", x_detected);

    // ================================================
    // CORNER CASE
    // ================================================

    $display("|---------------------------------------------------------------------------------------------------------------|");

    $display("| CORNER CASE ANALYSIS");

    $display("| Minimum Boundary Tests         : %-5d", min_boundary_checks);

    $display("| Maximum Boundary Tests         : %-5d", max_boundary_checks);

    // ================================================
    // RESET
    // ================================================

    $display("|---------------------------------------------------------------------------------------------------------------|");

    $display("| RESET VERIFICATION");

    $display("| Reset Checks                   : %-5d", reset_checks);

    $display("| Reset Passes                   : %-5d", reset_pass);

    $display("| Reset Failures                 : %-5d", reset_fail);

    $display("| Reset Accuracy                 : %0.2f %%", reset_accuracy);

    // ================================================
    // DEADLOCK
    // ================================================

    $display("|---------------------------------------------------------------------------------------------------------------|");

    $display("| DEADLOCK ANALYSIS");

    $display("| Deadlock Checks                : %-5d", deadlock_checks);

    $display("| Deadlock Failures              : %-5d", deadlock_failures);

    // ================================================
    // OVERALL
    // ================================================

    $display("|---------------------------------------------------------------------------------------------------------------|");

    $display("| OVERALL SIMULATION CONFIDENCE  : %0.2f %%", overall_accuracy);

    $display("=================================================================================================================");

    $display(" ");
    $display("#############################################################################################################");
    $display("#                                  NORMAL SIMULATION COMPLETED                                               #");
    $display("#############################################################################################################");
    $display("# Verification Method : Directed RTL Simulation                                                             #");
    $display("# Verification Scope  : Limited Stimulus-Based Testing                                                      #");
    $display("# Verification Nature : Runtime Behavioral Observation                                                      #");
    $display("# Coverage Type       : Testcase Dependent                                                                  #");
    $display("#############################################################################################################");

    $finish;

end

endmodule