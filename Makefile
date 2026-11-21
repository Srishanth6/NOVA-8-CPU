# NOVA-8 build script
#
#   make sim M=alu           compile and run tb/tb_alu.v, log in sim/tb_alu.log
#   make sim M=cpu_programs  all test programs on the full CPU
#   make test                run every testbench, then print a summary
#   make gls                 gate-level sim of every program (slow)
#   make gls P=fib           gate-level sim of programs/fib.hex only
#   make wave M=alu          open sim/tb_alu.vcd in GTKWave
#   make asm                 assemble every programs/*.asm into .hex
#   make synth M=alu         quick Yosys synthesis check of one RTL module
#   make report              full synthesis, reports go to synth/
#   make clean               delete compiled sims, VCDs, logs and netlists
#
# A testbench fails if iverilog or vvp fail, or if its output has no
# "RESULT: ALL TESTS PASSED" line. sim, test, gls and asm exit non-zero on failure.
# Run all targets from the project root.

M ?= alu
P ?= all
IVERILOG = iverilog -g2012 -Wall
YOSYS ?= yosys
# python on Windows; python3 on Linux if python is not on PATH
PYTHON ?= $(shell command -v python >/dev/null 2>&1 && echo python || echo python3)
UNITS = alu reg_file pc ir instr_rom data_ram control_unit nova8_top cpu_programs
RTL_MODULES = $(basename $(notdir $(wildcard rtl/*.v)))
PROGS = $(basename $(notdir $(wildcard programs/*.asm)))
GLS_PROGS = $(if $(filter all,$(P)),$(PROGS),$(P))

# full-CPU testbenches need every RTL file, unit tests only need their own
RTL = $(if $(filter nova8_top cpu_programs,$(M)),$(wildcard rtl/*.v),rtl/$(M).v)

# $(call run_tb,<tb name>,<source files>,<log file>)
# vvp's exit code goes through a file because "vvp | tee" returns tee's
run_tb = $(IVERILOG) -o sim/$(1).vvp $(2) > $(3) 2>&1; rc=$$?; cat $(3); \
	if [ $$rc -ne 0 ]; then echo "FAILED  $(1) : iverilog failed"; exit 1; fi; \
	{ vvp sim/$(1).vvp 2>&1; echo $$? > sim/$(1).rc; } | tee -a $(3); \
	rc=$$(cat sim/$(1).rc); rm -f sim/$(1).rc; \
	if [ "$$rc" -ne 0 ]; then echo "FAILED  $(1) : vvp failed (exit $$rc)"; exit 1; fi; \
	grep -q "^RESULT: ALL TESTS PASSED" $(3) || \
	{ echo "FAILED  $(1) : no 'RESULT: ALL TESTS PASSED' (log in $(3))"; exit 1; }

.PHONY: sim test gls gls_one wave asm synth report clean

sim:
	@if [ "$(M)" = gls ]; then echo "use 'make gls [P=prog]' for the gate-level test"; exit 1; fi
	@$(call run_tb,tb_$(M),$(RTL) tb/tb_$(M).v,sim/tb_$(M).log)

test:
	@failed=""; \
	for m in $(UNITS); do \
		$(MAKE) --no-print-directory sim M=$$m || failed="$$failed $$m"; \
	done; \
	echo "=========================================="; \
	echo "TEST SUMMARY"; \
	for m in $(UNITS); do \
		case " $$failed " in *" $$m "*) r=FAIL;; *) r=PASS;; esac; \
		printf "  %-20s %s\n" tb_$$m $$r; \
	done; \
	echo "  failed:$${failed:- none} (logs in sim/)"; \
	[ -z "$$failed" ]

# gate-level sim: synth/gls.ys reads the program from sim/gls_prog.hex
gls:
	@failed=""; \
	for p in $(GLS_PROGS); do \
		$(MAKE) --no-print-directory gls_one P=$$p || failed="$$failed $$p"; \
	done; \
	echo "=========================================="; \
	echo "GLS SUMMARY"; \
	for p in $(GLS_PROGS); do \
		case " $$failed " in *" $$p "*) r=FAIL;; *) r=PASS;; esac; \
		printf "  %-20s %s\n" "gls $$p" $$r; \
	done; \
	echo "  failed:$${failed:- none} (logs in sim/)"; \
	[ -z "$$failed" ]

gls_one:
	@test -f programs/$(P).hex || { echo "gls: programs/$(P).hex not found"; exit 1; }
	@echo "=== gls $(P) : synthesizing sim/nova8_gate_$(P).v (log in sim/gls_$(P).yosys.log)"
	@cp programs/$(P).hex sim/gls_prog.hex
	@rm -f sim/nova8_gate_$(P).v
	@$(YOSYS) -q -l sim/gls_$(P).yosys.log -p "script synth/gls.ys; write_verilog -noattr sim/nova8_gate_$(P).v"
	@$(call run_tb,tb_gls,$(wildcard rtl/*.v) sim/nova8_gate_$(P).v tb/tb_gls.v,sim/tb_gls_$(P).log)

wave:
	gtkwave sim/tb_$(M).vcd &

asm:
	@for f in programs/*.asm; do $(PYTHON) assembler.py $$f || exit 1; done
	cp programs/smoke.hex programs/program.hex

synth:
	@if [ -z "$(filter $(M),$(RTL_MODULES))" ]; then \
		echo "synth: '$(M)' is not an RTL module (use one of: $(RTL_MODULES))"; exit 1; fi
	$(YOSYS) -p "read_verilog $(RTL); synth -top $(M); stat"

report:
	$(YOSYS) -p "script synth/synth.ys"

clean:
	rm -f sim/*.vvp sim/*.vcd sim/*.log sim/nova8_gate_*.v sim/gls_prog.hex
