# =============================================================================
# File        : jg_run.tcl
# Description : JasperGold Formal Verification TCL script for
#               FSM-based Secure Arithmetic Processing Module.
#               Version 2.1 – improved reset polarity, CEX dump, assume
#               constraints, cover-before-prove, parameterised elaboration.
#
# Usage:
#   jg -batch jg_run.tcl          (batch mode – no GUI)
#   jg jg_run.tcl                 (interactive GUI mode)
#
# Files required in the same directory:
#   FSM_arithmetic_model.v
#   FSM_arithmetic_properties.sv
# =============================================================================

# -----------------------------------------------------------------------------
# 0. Enable extended reporting (GUI and batch)
# -----------------------------------------------------------------------------
set_option -verbose true

# -----------------------------------------------------------------------------
# 1. Clear any previous session
# -----------------------------------------------------------------------------
clear -all

# -----------------------------------------------------------------------------
# 2. Analyze (compile) the RTL and the standalone SVA property file.
#    -sv12 enables full SV-2012 including SVA concurrent assertions and 'bind'.
# -----------------------------------------------------------------------------
analyze -sv12 \
    FSM_arithmetic_model.v \
    FSM_arithmetic_properties.sv

# -----------------------------------------------------------------------------
# 3. Elaborate the design top.
#    Change DATA_W here (e.g. -param "DATA_W=8") to verify a different width
#    without touching any source file.
# -----------------------------------------------------------------------------
elaborate -top jaspergold_complete_design \
          -param "DATA_W=4"

# -----------------------------------------------------------------------------
# 4. Declare the clock.
#    JasperGold needs an explicit clock declaration; 10 ns period matches the
#    testbench timescale but is irrelevant to the formal engine (cycle-accurate).
# -----------------------------------------------------------------------------
clock clk -period 10

# -----------------------------------------------------------------------------
# 5. Declare the reset.
#    'rst' is active-HIGH (posedge rst in always block).  The -expression form
#    is preferred; -posedge/negedge qualifiers tell the engine the polarity so
#    it initialises the model correctly before proving.
# -----------------------------------------------------------------------------
reset -expression {rst == 1'b1}

# -----------------------------------------------------------------------------
# 6. Add input assumptions to constrain the formal engine.
#    Without these the engine may explore degenerate corners (e.g. opcode
#    changing mid-cycle) that cannot happen in real use.
#    These mirror the implicit protocol defined in the documentation.
# -----------------------------------------------------------------------------
# Assumption A1: req stays stable for at least one cycle after assertion
# (simple level-sensitive assumption – engine may pulse req for one cycle).
assume -name ASSUME_REQ_STABLE { @(posedge clk) req |-> ##1 !req || req }

# Assumption A2: opcode and data inputs are stable while in PROCESS state
# (prevents unrealistic mid-operation input changes).
assume -name ASSUME_DATA_STABLE_IN_PROCESS {
    @(posedge clk)
    (dut.current_state == 2'b01) |->
        ($stable(data_a) && $stable(data_b) && $stable(opcode))
}

# Assumption A3: power_enable and secure_access do not change mid-PROCESS
assume -name ASSUME_CTRL_STABLE_IN_PROCESS {
    @(posedge clk)
    (dut.current_state == 2'b01) |->
        ($stable(power_enable) && $stable(secure_access))
}

# -----------------------------------------------------------------------------
# 7. Run formal proof on all assert properties.
#    -bg runs multiple engines in parallel (BMC + K-induction + ABC).
#    Remove -bg for sequential/single-core environments.
# -----------------------------------------------------------------------------
prove -all -bg

# -----------------------------------------------------------------------------
# 8. Check all cover points (reachability analysis).
#    Running cover AFTER prove ensures the engine has state-space data.
# -----------------------------------------------------------------------------
cover -all

# -----------------------------------------------------------------------------
# 9. Dump counter-examples (CEX) to VCD for any failing property.
#    These waveforms can be loaded in any waveform viewer for debug.
# -----------------------------------------------------------------------------
set cex_dir "jg_cex"
file mkdir $cex_dir

foreach prop [get_property_list -assert -status {falsified}] {
    set fname "${cex_dir}/cex_${prop}.vcd"
    report -cex $prop -vcd $fname
    puts "CEX saved: $fname"
}

# -----------------------------------------------------------------------------
# 10. Text reports
# -----------------------------------------------------------------------------
report -summary
report -property -assert  -file jg_assert_report.txt
report -property -cover   -file jg_cover_report.txt

# Also save a full session log
report -log                -file jg_full_log.txt

# -----------------------------------------------------------------------------
# 11. Done
# -----------------------------------------------------------------------------
puts ""
puts "============================================================"
puts "  JasperGold Formal Verification Flow Complete."
puts "  Assert report : jg_assert_report.txt"
puts "  Cover  report : jg_cover_report.txt"
puts "  Full   log    : jg_full_log.txt"
puts "  CEX waveforms : ${cex_dir}/cex_*.vcd  (if any failures)"
puts "============================================================"
