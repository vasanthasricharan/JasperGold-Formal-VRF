// =============================================================================
// Module      : jaspergold_complete_design
// Description : FSM-based Secure Arithmetic Processing Module
//               Four states: IDLE -> PROCESS -> DONE/ERROR -> IDLE
// Operations  : ADD, SUB (signed-safe), AND, XOR
// Security    : Blocks operation on !secure_access; triggers ERROR state
// Power       : ERROR state on !power_enable
// Version     : 3.0  (all feedback addressed – parameterized, security-
//               consistent, signed SUB, SVA in FORMAL guard, no magic numbers)
// =============================================================================

module jaspergold_complete_design #(
    parameter DATA_W = 4,               // Input data width (bits) – override freely
    parameter RES_W  = DATA_W + 1       // Result width: one extra bit for carry/sign
) (
    input  wire               clk,
    input  wire               rst,         // Active-HIGH synchronous reset

    // Protocol handshake
    input  wire               req,
    output reg                grant,

    // Data path
    input  wire [DATA_W-1:0]  data_a,
    input  wire [DATA_W-1:0]  data_b,
    input  wire [1:0]         opcode,     // 00=ADD 01=SUB 10=AND 11=XOR

    // Control
    input  wire               secure_access,
    input  wire               power_enable,

    // Results
    output reg  [RES_W-1:0]   result,
    output reg                valid,
    output reg                error_flag
);

    // =========================================================================
    // FSM STATE ENCODING  (localparams – no magic 2'b?? literals elsewhere)
    // =========================================================================
    localparam [1:0] IDLE    = 2'b00;
    localparam [1:0] PROCESS = 2'b01;
    localparam [1:0] DONE    = 2'b10;
    localparam [1:0] ERROR   = 2'b11;

    reg [1:0] current_state;
    reg [1:0] next_state;

    // Sign-extended wires for safe signed subtraction
    // Zero-extending to RES_W prevents unsigned underflow producing a
    // truncated result (e.g. 0 - 1 = -1 fits correctly in RES_W bits).
    wire signed [DATA_W:0] signed_a = {1'b0, data_a};
    wire signed [DATA_W:0] signed_b = {1'b0, data_b};

    // =========================================================================
    // STATE REGISTER  (sequential – synchronous reset)
    // =========================================================================
    always @(posedge clk) begin
        if (rst)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end

    // =========================================================================
    // NEXT-STATE LOGIC  (pure combinational)
    // =========================================================================
    always @(*) begin
        next_state = current_state;                 // default: hold state

        case (current_state)
            IDLE : begin
                if (req)
                    next_state = PROCESS;
            end

            PROCESS : begin
                // ERROR on EITHER power failure OR security violation
                // (fixes original bug where only power_enable triggered ERROR)
                if (!power_enable || !secure_access)
                    next_state = ERROR;
                else
                    next_state = DONE;
            end

            DONE  : next_state = IDLE;              // unconditional return
            ERROR : next_state = IDLE;              // unconditional recovery

            default: next_state = IDLE;
        endcase
    end

    // =========================================================================
    // OUTPUT LOGIC  (combinational)
    // All outputs driven from defaults first to prevent inferred latches.
    // =========================================================================
    always @(*) begin
        // Safe defaults
        grant      = 1'b0;
        valid      = 1'b0;
        result     = {RES_W{1'b0}};
        error_flag = 1'b0;

        case (current_state)
            IDLE : begin
                grant = 1'b0;
            end

            PROCESS : begin
                grant = 1'b1;                       // request acknowledged

                if (!secure_access || !power_enable) begin
                    // Fault condition – raise error flag immediately
                    error_flag = 1'b1;
                end else begin
                    // Perform the requested arithmetic / logic operation
                    case (opcode)
                        2'b00: result = {1'b0, data_a} + {1'b0, data_b};  // ADD  (unsigned, carry in MSB)
                        2'b01: result = signed_a - signed_b;               // SUB  (signed-safe, no underflow)
                        2'b10: result = {1'b0, data_a & data_b};           // AND
                        2'b11: result = {1'b0, data_a ^ data_b};           // XOR
                        default: result = {RES_W{1'b0}};
                    endcase
                end
            end

            DONE : begin
                valid = 1'b1;                       // operation completed successfully
            end

            ERROR : begin
                error_flag = 1'b1;                  // signal error to downstream logic
            end

            default : begin
                grant = 1'b0;
            end
        endcase
    end

    // =========================================================================
    // SYSTEMVERILOG ASSERTIONS  (SVA – compiled by JasperGold via FORMAL guard)
    //
    // These properties are also mirrored in FSM_arithmetic_properties.sv
    // (standalone bind file).  The guard below prevents synthesis tools from
    // seeing SVA syntax; JasperGold passes +define+FORMAL automatically.
    //
    // To run: jg jg_run.tcl   (which passes -define FORMAL via analyze flags)
    // =========================================================================
`ifdef FORMAL

    default clocking cb @(posedge clk); endclocking
    default disable iff (rst);

    // -- FSM Transitions -------------------------------------------------------
    FSM_IDLE_TO_PROCESS:
        assert property ((current_state == IDLE && req) |=> (current_state == PROCESS));

    FSM_PROCESS_TO_DONE:
        assert property ((current_state == PROCESS && power_enable && secure_access)
                         |=> (current_state == DONE));

    FSM_PROCESS_TO_ERROR_POWER:
        assert property ((current_state == PROCESS && !power_enable)
                         |=> (current_state == ERROR));

    FSM_PROCESS_TO_ERROR_SEC:
        assert property ((current_state == PROCESS && !secure_access)
                         |=> (current_state == ERROR));

    FSM_DONE_TO_IDLE:
        assert property ((current_state == DONE)  |=> (current_state == IDLE));

    FSM_ERROR_TO_IDLE:
        assert property ((current_state == ERROR) |=> (current_state == IDLE));

    // -- Output signal correctness --------------------------------------------
    GRANT_IN_PROCESS:
        assert property ((current_state == PROCESS) |-> grant);

    NO_GRANT_OUTSIDE_PROCESS:
        assert property ((current_state != PROCESS) |-> !grant);

    VALID_IN_DONE:
        assert property ((current_state == DONE) |-> valid);

    NO_VALID_OUTSIDE_DONE:
        assert property ((current_state != DONE) |-> !valid);

    ERROR_ON_INSECURE:
        assert property ((current_state == PROCESS && !secure_access) |-> error_flag);

    ERROR_ON_POWER_FAIL:
        assert property ((current_state == PROCESS && !power_enable)  |-> error_flag);

    ERROR_IN_ERROR_STATE:
        assert property ((current_state == ERROR) |-> error_flag);

    NO_ERROR_IN_IDLE:
        assert property ((current_state == IDLE)  |-> !error_flag);

    // -- Reset behaviour -------------------------------------------------------
    RESET_TO_IDLE:
        assert property (@(posedge clk) $rose(rst) |=> (current_state == IDLE));

    // -- Arithmetic correctness -----------------------------------------------
    ADD_CORRECT:
        assert property ((current_state == PROCESS && opcode == 2'b00
                          && secure_access && power_enable)
                         |-> (result == ({1'b0, data_a} + {1'b0, data_b})));

    SUB_CORRECT:
        assert property ((current_state == PROCESS && opcode == 2'b01
                          && secure_access && power_enable)
                         |-> (result == (signed_a - signed_b)));

    AND_CORRECT:
        assert property ((current_state == PROCESS && opcode == 2'b10
                          && secure_access && power_enable)
                         |-> (result == {1'b0, data_a & data_b}));

    XOR_CORRECT:
        assert property ((current_state == PROCESS && opcode == 2'b11
                          && secure_access && power_enable)
                         |-> (result == {1'b0, data_a ^ data_b}));

    // -- Cover: all four states and key paths are reachable -------------------
    COVER_IDLE    : cover property (current_state == IDLE);
    COVER_PROCESS : cover property (current_state == PROCESS);
    COVER_DONE    : cover property (current_state == DONE);
    COVER_ERROR   : cover property (current_state == ERROR);

    COVER_HAPPY_PATH : cover property (
        (current_state == IDLE) ##1 (current_state == PROCESS)
        ##1 (current_state == DONE) ##1 (current_state == IDLE)
    );

    COVER_SEC_ERROR : cover property (
        (current_state == PROCESS && !secure_access) ##1 (current_state == ERROR)
    );

`endif  // FORMAL

endmodule
