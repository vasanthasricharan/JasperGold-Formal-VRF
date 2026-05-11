# =============================================================================
# File        : jg_run.tcl
# Description : JasperGold Formal Verification TCL script for
#               FSM-based Secure Arithmetic Processing Module.
# Version     : 4.0
#   – Explicit active-HIGH reset polarity
#   – +define+FORMAL passed to analyze so RTL SVA block compiles
#   – Input assumptions now reference bound property module port
#     (prop_inst.current_state) instead of dut.current_state, which
#     resolves correctly in both batch mode and GUI without requiring
#     a separate set_design_unit or hierarchical path workaround.
#   – CEX VCD dump for every failing property
#   – cover -all run after prove
#   – Parameterised elaborate (change DATA_W here without touching RTL)
#   – Full text reports + session log
#
# Usage:
#   jg -batch jg_run.tcl        (batch / CI – no GUI)
#   jg jg_run.tcl               (interactive GUI mode)
#
# Files required in the same directory:
#   FSM_arithmetic_model.v
#   FSM_arithmetic_properties.sv
#
# Fix note (v4.0):
#   Previous versions used "dut.current_state" in the assume statements
#   (lines referencing 2'b01 for PROCESS state). In JasperGold batch mode
#   the DUT top is jaspergold_complete_design, so the hierarchical path
#   "dut.current_state" does not resolve unless the user adds an explicit
#   set_design_unit or wraps the design in a top-level module named "dut".
#   The fix uses the bound property instance port "prop_inst.current_state"
#   which is always visible after elaborate when the bind statement in
#   FSM_arithmetic_properties.sv is compiled with -sv12.
# =============================================================================

# -----------------------------------------------------------------------------
# 0. Verbose mode – show engine progress in batch log
# -----------------------------------------------------------------------------
set_option -verbose true

# -----------------------------------------------------------------------------
# 1. Clear any previous session state
# -----------------------------------------------------------------------------
clear -all

# -----------------------------------------------------------------------------
# 2. Analyze (compile) RTL and standalone SVA property file.
#
#    -sv12          : Full SV-2012 – required for SVA concurrent assertions,
#                    'bind', default clocking, $stable, $rose.
#    +define+FORMAL : Enables the `ifdef FORMAL block inside the RTL so the
#                    embedded assertions are compiled and proved alongside
#                    FSM_arithmetic_properties.sv.
# -----------------------------------------------------------------------------
analyze -sv12 \
    +define+FORMAL \
    FSM_arithmetic_model.v \
    FSM_arithmetic_properties.sv

# -----------------------------------------------------------------------------
# 3. Elaborate the design top.
#    Change DATA_W here to verify a wider design without editing RTL.
#    Example: uncomment the 8-bit line and comment out the 4-bit one.
# -----------------------------------------------------------------------------
elaborate -top jaspergold_complete_design \
          -param "DATA_W=4"
# elaborate -top jaspergold_complete_design -param "DATA_W=8"

# -----------------------------------------------------------------------------
# 4. Clock declaration.
#    10 ns period matches the testbench timescale; the formal engine works
#    cycle-accurately so the period value itself does not affect proof results.
# -----------------------------------------------------------------------------
clock clk -period 10

# -----------------------------------------------------------------------------
# 5. Reset declaration.
#    rst is active-HIGH (always @(posedge clk) if (rst) in RTL).
#    The explicit == 1'b1 form ensures the engine initialises in reset before
#    beginning state-space exploration, preventing spurious CEX in cycle 0.
# -----------------------------------------------------------------------------
reset -expression {rst == 1'b1}

# -----------------------------------------------------------------------------
# 6. Input assumptions – constrain the engine to the legal operating envelope
#    defined in the project specification.
#
#    FIX (v4.0): All assume statements that previously referenced
#    "dut.current_state" now reference "prop_inst.current_state".
#    The bound property module instance (prop_inst) is elaborated as a
#    sub-instance of jaspergold_complete_design, so the full hierarchical
#    path after elaborate is:
#       jaspergold_complete_design.prop_inst.current_state
#    JasperGold resolves this correctly in both -batch and GUI modes
#    without needing set_design_unit or an extra wrapper.
#
#    The ASSUME_ SVA properties inside FSM_arithmetic_properties.sv are
#    the primary mechanism; these TCL assumes are kept as belt-and-suspenders
#    redundancy for engines that process TCL constraints before SVA.
# -----------------------------------------------------------------------------

# A1: req is a single-cycle pulse.
#     Prevents the engine from holding req=1 through the PROCESS state, which
#     is outside the documented request/grant handshake protocol.
assume -name ASSUME_REQ_PULSE \
    { @(posedge clk) req |=> !req }

# A2: data_a, data_b, opcode are stable during PROCESS.
#     Changing inputs mid-operation is undefined per the protocol spec.
#     FIX: use prop_inst.current_state (bound module port) instead of
#          dut.current_state (unresolved hierarchical path in batch mode).
assume -name ASSUME_DATA_STABLE_IN_PROCESS \
    { @(posedge clk) \
      (prop_inst.current_state == 2'b01) |-> \
          ($stable(data_a) && $stable(data_b) && $stable(opcode)) }

# A3: power_enable and secure_access are stable during PROCESS.
#     FIX: same path fix as A2.
assume -name ASSUME_CTRL_STABLE_IN_PROCESS \
    { @(posedge clk) \
      (prop_inst.current_state == 2'b01) |-> \
          ($stable(power_enable) && $stable(secure_access)) }

# -----------------------------------------------------------------------------
# 7. Prove all assert properties.
#    -bg : runs BMC + K-induction + ABC engines in parallel.
#          Remove -bg on single-core or memory-limited environments.
# -----------------------------------------------------------------------------
prove -all -bg

# -----------------------------------------------------------------------------
# 8. Cover – reachability analysis for all cover properties.
#    Executed AFTER prove so the engine reuses bounded state-space data.
# -----------------------------------------------------------------------------
cover -all

# -----------------------------------------------------------------------------
# 9. Counter-example (CEX) dump.
#    Each failing assertion generates a VCD waveform in ./jg_cex/ for debug
#    in SimVision, GTKWave, or the JasperGold waveform viewer.
# -----------------------------------------------------------------------------
file mkdir jg_cex

foreach prop [get_property_list -assert -status {falsified}] {
    set cex_file "jg_cex/cex_${prop}.vcd"
    report -cex $prop -vcd $cex_file
    puts "  \[CEX saved\] $cex_file"
}

# -----------------------------------------------------------------------------
# 10. Text reports
# -----------------------------------------------------------------------------
report -summary
report -property -assert  -file jg_assert_report.txt
report -property -cover   -file jg_cover_report.txt
report -log                -file jg_full_session_log.txt

# -----------------------------------------------------------------------------
# 11. Done
# -----------------------------------------------------------------------------
puts ""
puts "================================================================"
puts "  JasperGold Formal Verification Complete."
puts "  Assertion report  : jg_assert_report.txt"
puts "  Cover report      : jg_cover_report.txt"
puts "  Full session log  : jg_full_session_log.txt"
puts "  CEX waveforms     : jg_cex/cex_*.vcd  (only if failures exist)"
puts "================================================================"
