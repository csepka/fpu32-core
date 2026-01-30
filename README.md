# FPU32 — IEEE 754 Single-Precision Floating-Point Unit

A synthesizable **32-bit IEEE 754 single-precision** floating-point unit (FPU) in Verilog/SystemVerilog with **add**, **subtract**, and **multiply** operations. Designed for RTL verification and hardware roles; suitable for FPGA or ASIC flow.

## Features

- **Operations:** Add, subtract, multiply (IEEE 754 round-to-nearest-even)
- **Interface:** Ready/valid handshake (producer/consumer flow control)
- **RTL:** Synchronous design; adder and multiplier use stb/ack handshaking internally
- **Verification:** Smoke test + regression with directed and random stimulus; IEEE-aware comparison (NaN, ±0, ±Inf)

## Architecture

```
                    ┌─────────────────────────────────────────┐
                    │              fpu_top                     │
  operands_val ────►│  ┌─────────┐    ┌─────────┐             │
  operands_bits_A ─►│  │  state  │───►│  adder  │─── add_z ───┼──► result_bits
  operands_bits_B ─►│  │ machine │    └─────────┘             │    result_val
  operands_sel ────►│  │         │    ┌─────────┐             │
  result_rdy ──────►│  │         │───►│multiplier│── mul_z ───┼──► operands_rdy
                    │  └─────────┘    └─────────┘             │
                    └─────────────────────────────────────────┘
```

- **`operands_sel`:** `2'b00` = add, `2'b01` = subtract, `2'b10` = multiply  
- **Flow:** Idle → send A → send B → wait for result → back to Idle. Subtract is implemented as add with negated B.

## Project Structure

```
fpu32/
├── rtl/
│   ├── fpu_top.v          # Top-level FPU (state machine + operand routing)
│   ├── adder/
│   │   └── adder.v        # IEEE 754 single-precision adder (handshake I/O)
│   └── multiplier/
│       └── multiplier.v   # IEEE 754 single-precision multiplier (handshake I/O)
├── tb/
│   ├── fpu_tb.sv          # Smoke test (e.g. 1.0 + 1.0 = 2.0)
│   └── fpu_tb_regression.sv  # Regression: directed + 100 random cases
├── build/                 # Compiled testbenches (gitignored)
├── Makefile               # Build and run tests
└── README.md
```

## Requirements

- **Icarus Verilog** (iverilog, vvp) — e.g. `brew install icarus-verilog` on macOS

## Build & Test

```bash
# Build and run smoke test
make smoke

# Build and run full regression (directed + random)
make regression

# Run both
make test

# Clean build artifacts
make clean
```

Regression checks directed cases (e.g. 1+1=2, 2.5−1.25=1.25, (−1)×(−1)=1) and 100 random normalized operands against a reference model with IEEE-aware comparison.

## Resume / Interview Talking Points

- **IEEE 754:** Single-precision format; handling of normals, subnormals, NaN, ±Inf, ±0 in testbench
- **Ready/valid:** Producer/consumer backpressure; same pattern used in many industry designs
- **Verification:** Reference model in SystemVerilog; directed + constrained-random tests; portable float helpers (no vendor-specific real↔bits)
- **RTL style:** Synchronous FSM; clear separation between top-level control and datapath (adder/multiplier)

## Resume One-Liner

*"FPU32: IEEE 754 single-precision FPU (add/sub/mul) in Verilog with ready/valid interface; full regression (directed + random) and reference-model verification."*

## License

MIT. The adder and multiplier cores are derived from work by Jonathan P Dawson (2013); see headers in `rtl/adder/adder.v` and `rtl/multiplier/multiplier.v`.
