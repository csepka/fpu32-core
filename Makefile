# FPU32 — build and run tests (Icarus Verilog)
# Usage: make smoke | make regression | make test | make clean

IVERILOG ?= iverilog
VVP      ?= vvp
IVFLAGS  ?= -g2012

RTL_TOP  = rtl/fpu_top.v
RTL_ADD  = rtl/adder/adder.v
RTL_MUL  = rtl/multiplier/multiplier.v
TB_SMOKE = tb/fpu_tb.sv
TB_REGRESS = tb/fpu_tb_regression.sv

BUILD_DIR = build
SMOKE_VVP = $(BUILD_DIR)/smoke.vvp
REGRESS_VVP = $(BUILD_DIR)/regress.vvp

.PHONY: smoke regression test clean dirs

test: smoke regression

smoke: $(SMOKE_VVP)
	$(VVP) $(SMOKE_VVP)

regression: $(REGRESS_VVP)
	$(VVP) $(REGRESS_VVP)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(SMOKE_VVP): $(BUILD_DIR) $(RTL_TOP) $(RTL_ADD) $(RTL_MUL) $(TB_SMOKE)
	$(IVERILOG) $(IVFLAGS) -o $@ $(RTL_TOP) $(RTL_ADD) $(RTL_MUL) $(TB_SMOKE)

$(REGRESS_VVP): $(BUILD_DIR) $(RTL_TOP) $(RTL_ADD) $(RTL_MUL) $(TB_REGRESS)
	$(IVERILOG) $(IVFLAGS) -o $@ $(RTL_TOP) $(RTL_ADD) $(RTL_MUL) $(TB_REGRESS)

clean:
	rm -rf $(BUILD_DIR) waves.vcd waves_regression.vcd
