# NOVA-8 run script for Windows (same targets as the Makefile)
#
#   .\run.ps1 sim alu            compile and run tb/tb_alu.v, log in sim/tb_alu.log
#   .\run.ps1 sim cpu_programs   all test programs on the full CPU
#   .\run.ps1 test               run every testbench, then print a summary
#   .\run.ps1 gls                gate-level sim of every program (slow)
#   .\run.ps1 gls fib            gate-level sim of programs/fib.hex only
#   .\run.ps1 wave alu           open sim/tb_alu.vcd in GTKWave
#   .\run.ps1 asm                assemble every programs/*.asm into .hex
#   .\run.ps1 synth alu          quick Yosys synthesis check of one RTL module
#   .\run.ps1 report             full synthesis, reports go to synth/
#   .\run.ps1 clean              delete compiled sims, VCDs, logs and netlists
#
# A testbench fails if iverilog or vvp fail, or if its output has no
# "RESULT: ALL TESTS PASSED" line. sim, test, gls and asm exit with 1 on failure.
# Set $env:YOSYS to use a different Yosys, e.g. yowasp-yosys.

param(
    [string]$Target = "sim",
    [string]$M = ""
)

Set-Location $PSScriptRoot
$units = @("alu", "reg_file", "pc", "ir", "instr_rom", "data_ram", "control_unit",
           "nova8_top", "cpu_programs")
$rtlModules = @(Get-ChildItem rtl/*.v | ForEach-Object { $_.BaseName })
$yosys = if ($env:YOSYS) { $env:YOSYS } else { "yosys" }

function Assert-Tool($name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        Write-Host "error: '$name' not found (is it installed and on PATH?)"
        exit 1
    }
}

# full-CPU testbenches need every RTL file, unit tests only need their own
function Get-Rtl($mod) {
    if ($mod -eq "nova8_top" -or $mod -eq "cpu_programs" -or $mod -eq "gls") {
        return @(Get-ChildItem rtl/*.v | ForEach-Object { "rtl/" + $_.Name })
    }
    return @("rtl/$mod.v")
}

# Compile and run one testbench, printing the output and saving it to $log.
# Returns "" if it passed, otherwise the reason it failed.
function Invoke-Tb($name, $files, $log) {
    $vvp = "sim/$name.vvp"
    $out = @(& iverilog -g2012 -Wall -o $vvp @files 2>&1 | ForEach-Object { "$_" })
    $code = $LASTEXITCODE
    $out | ForEach-Object { Write-Host $_ }
    if ($code -ne 0) {
        ($out + "iverilog failed (exit $code)") | Set-Content -Encoding ascii $log
        return "iverilog failed"
    }
    $run = @(& vvp $vvp 2>&1 | ForEach-Object { $line = "$_"; Write-Host $line; $line })
    $code = $LASTEXITCODE
    ($out + $run) | Set-Content -Encoding ascii $log
    if ($code -ne 0) { return "vvp failed (exit $code)" }
    if ($run -notcontains "RESULT: ALL TESTS PASSED") { return "no 'RESULT: ALL TESTS PASSED'" }
    return ""
}

function Invoke-Sim($mod) {
    if (-not (Test-Path "tb/tb_$mod.v")) { return "tb/tb_$mod.v not found" }
    return Invoke-Tb "tb_$mod" (@(Get-Rtl $mod) + "tb/tb_$mod.v") "sim/tb_$mod.log"
}

# synthesize the gate netlist for one program, then run tb_gls.v on it
function Invoke-Gls($prog) {
    if (-not (Test-Path "programs/$prog.hex")) { return "programs/$prog.hex not found" }
    $net = "sim/nova8_gate_$prog.v"
    Write-Host "=== gls $prog : synthesizing $net (log in sim/gls_$prog.yosys.log)"
    Copy-Item "programs/$prog.hex" sim/gls_prog.hex
    Remove-Item $net -ErrorAction SilentlyContinue
    & $yosys -q -l "sim/gls_$prog.yosys.log" -p "script synth/gls.ys; write_verilog -noattr $net" 2>&1 |
        ForEach-Object { Write-Host "$_" }
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $net)) { return "yosys failed" }
    return Invoke-Tb "tb_gls" (@(Get-Rtl "gls") + $net + "tb/tb_gls.v") "sim/tb_gls_$prog.log"
}

# print a pass/fail table; $results is a list of @(name, reason)
function Write-Summary($title, $results) {
    $failed = @($results | Where-Object { $_[1] })
    Write-Host "=========================================="
    Write-Host $title
    foreach ($r in $results) {
        $status = if ($r[1]) { "FAIL  ($($r[1]))" } else { "PASS" }
        Write-Host ("  {0,-20} {1}" -f $r[0], $status)
    }
    Write-Host ("  {0} passed, {1} failed (logs in sim/)" -f ($results.Count - $failed.Count), $failed.Count)
    return $failed.Count
}

switch ($Target) {
    "sim" {
        if (-not $M) { $M = "alu" }
        if ($M -eq "gls") { Write-Host "use '.\run.ps1 gls [prog]' for the gate-level test"; exit 1 }
        Assert-Tool iverilog
        Assert-Tool vvp
        $r = Invoke-Sim $M
        if ($r) { Write-Host "FAILED  tb_$M : $r (log in sim/tb_$M.log)"; exit 1 }
        exit 0
    }
    "test" {
        Assert-Tool iverilog
        Assert-Tool vvp
        $results = @()
        foreach ($u in $units) { $results += , @("tb_$u", (Invoke-Sim $u)) }
        $nfail = Write-Summary "TEST SUMMARY" $results
        if ($nfail -gt 0) { exit 1 }
        exit 0
    }
    "gls" {
        Assert-Tool iverilog
        Assert-Tool vvp
        Assert-Tool $yosys
        $progs = if ($M) { @($M) } else { @(Get-ChildItem programs/*.asm | ForEach-Object { $_.BaseName }) }
        $results = @()
        foreach ($p in $progs) { $results += , @("gls $p", (Invoke-Gls $p)) }
        $nfail = Write-Summary "GLS SUMMARY" $results
        if ($nfail -gt 0) { exit 1 }
        exit 0
    }
    "wave" {
        if (-not $M) { $M = "alu" }
        gtkwave "sim/tb_$M.vcd"
    }
    "asm" {
        Assert-Tool python
        foreach ($f in Get-ChildItem programs/*.asm) {
            python assembler.py "programs/$($f.Name)"
            if ($LASTEXITCODE -ne 0) { Write-Host "asm: stopped, $($f.Name) has errors"; exit 1 }
        }
        Copy-Item programs/smoke.hex programs/program.hex
    }
    "synth" {
        if (-not $M) { $M = "alu" }
        if ($rtlModules -notcontains $M) {
            Write-Host "synth: '$M' is not an RTL module (use one of: $($rtlModules -join ', '))"
            exit 1
        }
        Assert-Tool $yosys
        $rtl = (Get-Rtl $M) -join " "
        & $yosys -p "read_verilog $rtl; synth -top $M; stat"
        if ($LASTEXITCODE -ne 0) { exit 1 }
    }
    "report" {
        Assert-Tool $yosys
        & $yosys -p "script synth/synth.ys"
        if ($LASTEXITCODE -ne 0) { exit 1 }
    }
    "clean" {
        Remove-Item sim/*.vvp, sim/*.vcd, sim/*.log, sim/nova8_gate_*.v, sim/gls_prog.hex -ErrorAction SilentlyContinue
    }
    default {
        Write-Host "unknown target '$Target' (use sim, test, gls, wave, asm, synth, report, clean)"
        exit 1
    }
}
