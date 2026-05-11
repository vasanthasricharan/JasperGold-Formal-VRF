# FSM-Based Secure Arithmetic Processing Module — Formal Verification

## Project Overview

This project implements and formally verifies a **4-state FSM-based Secure Arithmetic Processing Module** using JasperGold Formal Verification. The design processes ADD, SUB (signed-safe), AND, and XOR operations with security and power-control gating.

### FSM State Machine

```
        rst
         |
         v
    +--------+   req    +----------+
    |  IDLE  |--------->| PROCESS  |
    |        |          |          |
    +--------+          +----------+
         ^                 |      |
         |   power_enable  |      | !power_enable
         |   secure_access |      |   OR
         |                 v      v !secure_access
         |             +------+ +-------+
         +-------------|  DONE| | ERROR |
                       +------+ +-------+
```

### File Structure

| File | Description |
|------|-------------|
| `FSM_arithmetic_model.v` | RTL DUT — 4-state FSM with parameterized data path, signed arithmetic, and inline SVA (`ifdef FORMAL` guarded) |
| `FSM_arithmetic_properties.sv` | Standalone SVA property module — bind-based, non-invasive; 17 assertions + 7 cover points + 3 assumptions |
| `FSM_arithmetic_model_normal_tb.v` | Directed RTL simulation testbench — functional, security, boundary, X-state, deadlock tests |
| `FSM_arithmetic_model_jasper_tb.v` | Exhaustive simulation testbench — all 4 opcodes × all 4-bit data values, with inline SVA |
| `jg_run.tcl` | JasperGold TCL script — analyze, elaborate, clock/reset, assume, prove, cover, CEX dump, reports |
| `jg_assert_report.txt` | JasperGold assertion proof results (all 17 properties proven) |
| `jg_cover_report.txt` | JasperGold cover reachability results (all 7 cover points reached) |
| `jg_full_session_log.txt` | Complete JasperGold session log with engine status |

---

## Prerequisites

### For RTL Simulation (Normal & Jasper-Style Testbenches)

Any IEEE 1800-2012 compatible simulator:

- **Icarus Verilog** (free): `iverilog` version 11+ recommended
- **ModelSim / Questa** (Mentor / Siemens EDA)
- **VCS** (Synopsys)
- **Xcelium** (Cadence)

### For Formal Verification (JasperGold Flow)

- **JasperGold Formal Verification Platform** (Cadence), version 2019.06 or later
- License for `JasperGold Apps: FPV` (Formal Property Verification)

---

## Running the Normal RTL Simulation

The normal testbench (`FSM_arithmetic_model_normal_tb.v`) runs directed tests covering all opcodes, boundary values, security violations, X-state injection, and deadlock detection.

### Using Icarus Verilog (iverilog)

```bash
# Compile
iverilog -g2012 \
    -o tb_normal_sim \
    FSM_arithmetic_model.v \
    FSM_arithmetic_model_normal_tb.v

# Run
vvp tb_normal_sim

# View waveform (optional — requires GTKWave)
gtkwave normal_sim.vcd
```

### Using ModelSim / Questa

```bash
# Compile
vlog -sv FSM_arithmetic_model.v FSM_arithmetic_model_normal_tb.v

# Simulate
vsim -batch -do "run -all; quit" tb_normal_simulation

# Or interactive
vsim tb_normal_simulation
```

### Using VCS (Synopsys)

```bash
vcs -sverilog \
    FSM_arithmetic_model.v \
    FSM_arithmetic_model_normal_tb.v \
    -o tb_normal_sim

./tb_normal_sim
```

### Expected Normal Simulation Output

```
=================================================================================================================
|                         NORMAL RTL SIMULATION ANALYTICS REPORT                                                |
=================================================================================================================
| FUNCTIONAL VERIFICATION
| Total Operations Tested        : 12
| Passed Operations              : 12
| Functional Accuracy            : 100.00 %
| PROTOCOL VERIFICATION
| Successful Handshakes          : 12
| Protocol Accuracy              : 100.00 %
| SECURITY TESTING
| Security Checks                : 2
| Security Passes                : 2
| Security Accuracy              : 100.00 %
| OVERALL SIMULATION CONFIDENCE  : 100.00 %
=================================================================================================================
```

---

## Running the JasperGold-Style Exhaustive Simulation

The exhaustive testbench (`FSM_arithmetic_model_jasper_tb.v`) runs all 4 opcodes × 16 data combinations = 64 normal operations plus security, power, and X-state tests for each combination, with inline SVA assertion checking.

### Using Icarus Verilog

```bash
# Compile (SVA concurrent assertions require -g2012)
iverilog -g2012 \
    -o tb_jasper_sim \
    FSM_arithmetic_model.v \
    FSM_arithmetic_model_jasper_tb.v

# Run
vvp tb_jasper_sim

# View waveform (optional)
gtkwave wave.vcd
```

### Using Xcelium (Cadence)

```bash
xrun -sv \
    FSM_arithmetic_model.v \
    FSM_arithmetic_model_jasper_tb.v \
    -top tb_jaspergold_complete \
    -access +rwc

# Interactive with waveform
xrun -sv \
    FSM_arithmetic_model.v \
    FSM_arithmetic_model_jasper_tb.v \
    -top tb_jaspergold_complete \
    -access +rwc \
    -gui
```

### Expected Exhaustive Simulation Output

```
=================================================================================================================
|     JasperGold-Style Exhaustive Simulation : all opcodes x all 4-bit data combinations                       |
=================================================================================================================
| Total Operations Tested        : 256
| Passed Operations              : 256
| Functional Accuracy            : 100.00 %
| Security Integrity             : 100.00%
| SVA Assertion Failures Caught  : 0
| OVERALL VERIFICATION CONFIDENCE : 100.00 %
=================================================================================================================
```

---

## Running the JasperGold Formal Verification Flow

### Quick Start

```bash
# Batch mode (CI / headless server)
jg -batch jg_run.tcl

# Interactive GUI mode
jg jg_run.tcl
```

### Step-by-Step Explanation

The `jg_run.tcl` script performs the following steps automatically:

**Step 1 — Analyze:** Compiles both RTL and SVA property files with SV-2012 support and `+define+FORMAL` to enable the inline assertion block.

```tcl
analyze -sv12 +define+FORMAL \
    FSM_arithmetic_model.v \
    FSM_arithmetic_properties.sv
```

**Step 2 — Elaborate:** Instantiates the design top with `DATA_W=4`. The `bind` statement in `FSM_arithmetic_properties.sv` automatically attaches `prop_inst` to the DUT.

```tcl
elaborate -top jaspergold_complete_design -param "DATA_W=4"
```

**Step 3 — Clock/Reset:** Declares the 10 ns clock and active-HIGH synchronous reset.

```tcl
clock clk -period 10
reset -expression {rst == 1'b1}
```

**Step 4 — Assumptions:** Constrains the formal engine to legal stimulus. The assume statements reference `prop_inst.current_state` (the bound property module port) for reliable hierarchical path resolution in both batch and GUI modes.

**Step 5 — Prove + Cover:**

```tcl
prove -all -bg    # BMC + K-induction + ABC in parallel
cover -all        # Reachability analysis
```

**Step 6 — Reports:** Generates `jg_assert_report.txt`, `jg_cover_report.txt`, `jg_full_session_log.txt`, and VCD counterexample waveforms for any failing properties (none expected).

### Verifying a Wider Data Path

To verify an 8-bit version without modifying RTL:

```tcl
# In jg_run.tcl, replace:
elaborate -top jaspergold_complete_design -param "DATA_W=4"
# with:
elaborate -top jaspergold_complete_design -param "DATA_W=8"
```

---

## Properties Verified

### FSM Transition Properties (P1–P7)

| ID | Property | Proven |
|----|----------|--------|
| P1 | IDLE → PROCESS when req asserted | ✓ |
| P2 | PROCESS → DONE when power_enable && secure_access | ✓ |
| P3 | PROCESS → ERROR when !power_enable | ✓ |
| P4 | PROCESS → ERROR when !secure_access | ✓ |
| P5 | DONE → IDLE (unconditional, deadlock-free) | ✓ |
| P6 | ERROR → IDLE (unconditional, deadlock-free) | ✓ |
| P7 | Reset drives FSM to IDLE within one cycle | ✓ |

### Output Signal Correctness (P8–P13)

| ID | Property | Proven |
|----|----------|--------|
| P8 | grant asserted iff in PROCESS state | ✓ |
| P8b | grant NOT asserted outside PROCESS | ✓ |
| P9 | valid asserted iff in DONE state | ✓ |
| P9b | valid NOT asserted outside DONE | ✓ |
| P10 | error_flag raised on security violation in PROCESS | ✓ |
| P11 | error_flag raised on power failure in PROCESS | ✓ |
| P12 | error_flag asserted throughout ERROR state | ✓ |
| P13 | No spurious error_flag in IDLE | ✓ |

### Arithmetic Correctness (P14–P17)

| ID | Property | Proven |
|----|----------|--------|
| P14 | ADD result = unsigned sum with carry in MSB | ✓ |
| P15 | SUB result = signed-safe subtraction (no underflow truncation) | ✓ |
| P16 | AND result = zero-extended bitwise AND | ✓ |
| P17 | XOR result = zero-extended bitwise XOR | ✓ |

### Cover Points (Reachability)

| Cover Point | Description | Reached |
|-------------|-------------|---------|
| COVER_IDLE | IDLE state reachable | ✓ |
| COVER_PROCESS | PROCESS state reachable | ✓ |
| COVER_DONE | DONE state reachable | ✓ |
| COVER_ERROR | ERROR state reachable | ✓ |
| COVER_HAPPY_PATH | IDLE→PROCESS→DONE→IDLE full transaction | ✓ |
| COVER_SEC_ERROR_PATH | PROCESS(insecure)→ERROR→IDLE | ✓ |
| COVER_PWR_ERROR_PATH | PROCESS(!power)→ERROR→IDLE | ✓ |

---

## Design Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `DATA_W` | 4 | Input data width in bits — override at elaborate time |
| `RES_W` | `DATA_W + 1` | Result width — extra bit for carry/sign extension |

---

## Known Issues and Notes

- **`jg_run.tcl` assume path fix (v4.0):** The assume statements now use `prop_inst.current_state` instead of `dut.current_state`. The old path did not resolve correctly in JasperGold batch mode because the design top is `jaspergold_complete_design`, not a module named `dut`. The bound property instance `prop_inst` (instantiated via the `bind` statement) is always visible after elaboration.

- **`ifdef FORMAL guard:** The inline SVA block inside `FSM_arithmetic_model.v` is compiled only when `+define+FORMAL` is passed. Normal simulators (iverilog, ModelSim) will not compile the SVA block by default, preventing syntax errors in simulation-only flows.

- **Signed subtraction:** The SUB operation uses `$signed({1'b0, data_a}) - $signed({1'b0, data_b})` to prevent unsigned underflow truncation. For example, `0 - 15 = -15` is correctly represented in `RES_W` bits.

---

## References

- Cadence JasperGold FPV Documentation: https://www.cadence.com/en_US/home/tools/system-design-and-verification/formal-and-static-verification/jasper-gold-verification-platform.html
- IEEE Std 1800-2012 (SystemVerilog): SVA concurrent assertion syntax
- Project documentation: `PS-23_JasperGold_Formal_VRF_documentation.docx`
- Project presentation: `PS-23_JasperGold_Formal_VRF.pptx`
