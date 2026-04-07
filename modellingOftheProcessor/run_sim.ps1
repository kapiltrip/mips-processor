param(
    [ValidateSet("add", "mem", "fact", "all")]
    [string]$Target = "all"
)

$ErrorActionPreference = "Stop"

$artifactDir = Join-Path $PSScriptRoot "artifacts"
$waveformDir = Join-Path $artifactDir "vcd"
$simulations = @(
    @{ Name = "add";  Top = "tb_add_three_numbers"; Sim = "sim_add"  },
    @{ Name = "mem";  Top = "tb_memory_word";       Sim = "sim_mem"  },
    @{ Name = "fact"; Top = "tb_factorial";         Sim = "sim_fact" }
)

New-Item -ItemType Directory -Force -Path $artifactDir, $waveformDir | Out-Null

Push-Location $PSScriptRoot
try {
    foreach ($simulation in $simulations) {
        if ($Target -ne "all" -and $Target -ne $simulation.Name) {
            continue
        }

        $outputPath = Join-Path "artifacts" $simulation.Sim
        iverilog -g2012 -s $simulation.Top -o $outputPath *.v
        if ($LASTEXITCODE -ne 0) {
            throw "iverilog failed for $($simulation.Top)"
        }

        vvp $outputPath
        if ($LASTEXITCODE -ne 0) {
            throw "vvp failed for $($simulation.Sim)"
        }
    }
}
finally {
    Pop-Location
}
