// =============================================================================
// Module      : jaspergold_complete_design
// Description : FSM-based Secure Arithmetic Processing Module
//               Four states: IDLE -> PROCESS -> DONE/ERROR -> IDLE
// Operations  : ADD, SUB (signed-safe), AND, XOR
// Security    : Blocks operation on !secure_access; also triggers ERROR state
// Power       : ERROR state on !power_enable
// Version     : 2.0  (improved – parameterized, security-consistent, signed SUB)
// =============================================================================

module jaspergold_complete_design #(
    parameter DATA_W = 4,               // Input data width (bits)
    parameter RES_W  = DATA_W + 1       // Result width – one extra bit for carry/sign
) (
    input  wire               clk,
    input  wire               rst,

    // Protocol
    input  wire               req,
    output reg                grant,

    // Data path
    input  wire [DATA_W-1:0]  data_a,
    input  wire [DATA_W-1:0]  data_b,
    input  wire [1:0]         opcode,

    // Control
    input  wire               secure_access,
    input  wire               power_enable,

    // Results
    output reg  [RES_W-1:0]   result,
    output reg                valid,
    output reg                error_flag
);

    // =========================================================================
    // FSM STATE ENCODING
    // =========================================================================
    localparam [1:0] IDLE    = 2'b00;
    localparam [1:0] PROCESS = 2'b01;
    localparam [1:0] DONE    = 2'b10;
    localparam [1:0] ERROR   = 2'b11;

    reg [1:0] current_state;
    reg [1:0] next_state;

    // Internal signed wires for subtraction
    wire signed [DATA_W:0]   signed_a = {1'b0, data_a};  // zero-extend to RES_W
    wire signed [DATA_W:0]   signed_b = {1'b0, data_b};

    // =========================================================================
    // STATE REGISTER  (sequential)
    // =========================================================================
    always @(posedge clk or posedge rst) begin
        if (rst)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end

    // =========================================================================
    // NEXT-STATE LOGIC  (combinational)
    // =========================================================================
    always @(*) begin
        next_state = current_state;             // default: hold
        case (current_state)
            IDLE : begin
                if (req)
                    next_state = PROCESS;
            end

            PROCESS : begin
                // ERROR on power failure OR security violation
                if (!power_enable || !secure_access)
                    next_state = ERROR;
                else
                    next_state = DONE;
            end

            DONE  : next_state = IDLE;          // unconditional return
            ERROR : next_state = IDLE;          // unconditional recovery
            default: next_state = IDLE;
        endcase
    end

    // =========================================================================
    // OUTPUT LOGIC  (combinational, Moore + Mealy)
    // =========================================================================
    always @(*) begin
        // Safe defaults – no latches
        grant      = 1'b0;
        valid      = 1'b0;
        result     = {RES_W{1'b0}};
        error_flag = 1'b0;

        case (current_state)
            IDLE : begin
                grant = 1'b0;                   // waiting for request
            end

            PROCESS : begin
                grant = 1'b1;                   // request acknowledged

                if (!secure_access || !power_enable) begin
                    // Security or power violation – raise error
                    error_flag = 1'b1;
                end else begin
                    // Normal arithmetic / logic operations
                    case (opcode)
                        2'b00: result = {1'b0, data_a} + {1'b0, data_b};          // ADD  (unsigned, carry in MSB)
                        2'b01: result = signed_a - signed_b;                       // SUB  (signed-safe, preserves sign)
                        2'b10: result = {1'b0, data_a & data_b};                   // AND
                        2'b11: result = {1'b0, data_a ^ data_b};                   // XOR
                        default: result = {RES_W{1'b0}};
                    endcase
                end
            end

            DONE : begin
                valid = 1'b1;                   // operation successful
            end

            ERROR : begin
                error_flag = 1'b1;              // latch error to output
            end

            default : begin
                grant = 1'b0;
            end
        endcase
    end

    // =========================================================================
    // SYSTEMVERILOG ASSERTIONS  (SVA – compilable by JasperGold)
    // These are embedded directly for ease of integration.
    // To use with JasperGold: analyze this file, elaborate, then run prove.
    // =========================================================================
`ifdef FORMAL

    // -- Assumption: clock and reset are well-behaved -----------------------
    // (JasperGold infers clk from sequential elements; these helpers anchor it)

    // -- FSM Transition: IDLE -> PROCESS on req ----------------------------
    FSM_IDLE_TO_PROCESS: assert property (
        @(posedge clk) disable iff (rst)
        (current_state == IDLE && req) |=> (current_state == PROCESS)
    );

    // -- FSM Transition: PROCESS -> DONE when no fault ---------------------
    FSM_PROCESS_TO_DONE: assert property (
        @(posedge clk) disable iff (rst)
        (current_state == PROCESS && power_enable && secure_access) |=> (current_state == DONE)
    );

    // -- FSM Transition: PROCESS -> ERROR on power failure -----------------
    FSM_PROCESS_TO_ERROR_POWER: assert property (
        @(posedge clk) disable iff (rst)
        (current_state == PROCESS && !power_enable) |=> (current_state == ERROR)
    );

    // -- FSM Transition: PROCESS -> ERROR on security violation -----------
    FSM_PROCESS_TO_ERROR_SEC: assert property (
        @(posedge clk) disable iff (rst)
        (current_state == PROCESS && !secure_access) |=> (current_state == ERROR)
    );

    // -- Liveness: DONE/ERROR always return to IDLE (deadlock-free) --------
    FSM_DONE_TO_IDLE: assert property (
        @(posedge clk) disable iff (rst)
        (current_state == DONE) |=> (current_state == IDLE)
    );

    FSM_ERROR_TO_IDLE: assert property (
        @(posedge clk) disable iff (rst)
        (current_state == ERROR) |=> (current_state == IDLE)
    );

    // -- Grant is asserted iff in PROCESS state ----------------------------
    GRANT_IN_PROCESS: assert property (
        @(posedge clk) disable iff (rst)
        (current_state == PROCESS) |-> grant
    );

    // -- Valid is asserted iff in DONE state --------------------------------
    VALID_IN_DONE: assert property (
        @(posedge clk) disable iff (rst)
        (current_state == DONE) |-> valid
    );

    // -- Error flag on security violation in PROCESS -----------------------
    ERROR_ON_INSECURE: assert property (
        @(posedge clk) disable iff (rst)
        (current_state == PROCESS && !secure_access) |-> error_flag
    );

    // -- Error flag in ERROR state -----------------------------------------
    ERROR_IN_ERROR_STATE: assert property (
        @(posedge clk) disable iff (rst)
        (current_state == ERROR) |-> error_flag
    );

    // -- Reset drives FSM to IDLE ------------------------------------------
    RESET_TO_IDLE: assert property (
        @(posedge clk)
        rst |=> (current_state == IDLE)
    );

    // -- No grant in IDLE -------------------------------------------------
    NO_GRANT_IN_IDLE: assert property (
        @(posedge clk) disable iff (rst)
        (current_state == IDLE) |-> !grant
    );

    // -- Cover: all four states are reachable ------------------------------
    COVER_IDLE    : cover property (@(posedge clk) current_state == IDLE);
    COVER_PROCESS : cover property (@(posedge clk) current_state == PROCESS);
    COVER_DONE    : cover property (@(posedge clk) current_state == DONE);
    COVER_ERROR   : cover property (@(posedge clk) current_state == ERROR);

`endif  // FORMAL

endmodule
