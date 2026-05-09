module jaspergold_complete_design (

    clk,
    rst,

    req,
    data_a,
    data_b,
    opcode,

    secure_access,
    power_enable,

    grant,
    result,
    valid,
    error_flag

);

input clk;
input rst;

input req;
input [3:0] data_a;
input [3:0] data_b;
input [1:0] opcode;

input secure_access;
input power_enable;

output reg grant;
output reg [4:0] result;
output reg valid;
output reg error_flag;

// =====================================================
// FSM STATES
// =====================================================

parameter IDLE    = 2'b00;
parameter PROCESS = 2'b01;
parameter DONE    = 2'b10;
parameter ERROR   = 2'b11;

reg [1:0] current_state;
reg [1:0] next_state;

// =====================================================
// STATE REGISTER
// =====================================================

always @(posedge clk or posedge rst)
begin
    if(rst)
        current_state <= IDLE;
    else
        current_state <= next_state;
end
// =====================================================
// NEXT STATE LOGIC
// =====================================================
always @(*)
begin
    next_state = current_state;
    case(current_state)
        IDLE:
        begin
            if(req)
                next_state = PROCESS;
        end
        PROCESS:
        begin
            if(power_enable)
                next_state = DONE;
            else
                next_state = ERROR;
        end
        DONE:
        begin
            next_state = IDLE;
        end
        ERROR:
        begin

            next_state = IDLE;
        end
    endcase
end
// =====================================================
// OUTPUT LOGIC
// =====================================================
always @(*)
begin
    grant      = 0;
    valid      = 0;
    result     = 0;
    error_flag = 0;
    case(current_state)
        IDLE:
        begin
            grant = 0;
        end
        PROCESS:
        begin
            grant = 1;
            if(!secure_access)
            begin
                error_flag = 1;
            end
            else
            begin

                case(opcode)

                    2'b00:
                        result = data_a + data_b;

                    2'b01:
                        result = data_a - data_b;

                    2'b10:
                        result = data_a & data_b;

                    2'b11:
                        result = data_a ^ data_b;

                    default:
                        result = 0;

                endcase

            end

        end

        DONE:
        begin

            valid = 1;

        end

        ERROR:
        begin

            error_flag = 1;

        end

    endcase

end

endmodule