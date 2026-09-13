param(
  [string]$VivadoPath = "D:\Xilinx\Vivado\2020.2\bin\vivado.bat",
  [string]$ClockPeriodNs = "1.000",
  [int[]]$PortsList = @(4),
  [string]$Designs = "all"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$handoffDir = Resolve-Path (Join-Path $scriptDir "..")
$repoDir = Resolve-Path (Join-Path $handoffDir "..")
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$runRoot = Join-Path $repoDir "build\asic_logic_only_$stamp"
New-Item -ItemType Directory -Force -Path $runRoot | Out-Null

if (!(Test-Path $VivadoPath)) {
  throw "Vivado was not found at $VivadoPath"
}

$policies = @(
  @{ Key = "hestia";        Name = "Hestia";        Mode = -1 },
  @{ Key = "dt";            Name = "DT-Hybrid";     Mode = 0 },
  @{ Key = "occamy";        Name = "Occamy-Hybrid"; Mode = 1 },
  @{ Key = "obm";           Name = "OBM-Hybrid";    Mode = 3 },
  @{ Key = "hybrid_themis"; Name = "Hybrid-Themis"; Mode = 4 }
)

function Test-DesignSelected {
  param([string]$Key, [string]$Name)

  if ($Designs -eq "all") {
    return $true
  }
  $selected = $Designs.Split(",") | ForEach-Object { $_.Trim() }
  return ($selected -contains $Key) -or ($selected -contains $Name)
}

$managedEnv = @(
  "HESTIA_ASIC_DESIGN_NAME",
  "HESTIA_ASIC_POLICY_MODE",
  "HESTIA_ASIC_PORTS",
  "HESTIA_ASIC_RANK_WIDTH",
  "HESTIA_ASIC_SEQ_WIDTH",
  "HESTIA_ASIC_PAYLOAD_WIDTH",
  "HESTIA_ASIC_CELL_COUNT_WIDTH",
  "HESTIA_ASIC_SRAM_CELLS",
  "HESTIA_ASIC_BATCH_SIZE",
  "HESTIA_ASIC_BATCH_SLOTS",
  "HESTIA_ASIC_PACKET_SLOTS",
  "HESTIA_ASIC_BBQ_BITMAP_WIDTH",
  "HESTIA_ASIC_POLICY_ALPHA_SHIFT"
)

function Clear-HestiaAsicEnv {
  foreach ($name in $managedEnv) {
    Remove-Item "Env:\$name" -ErrorAction SilentlyContinue
  }
}

function Set-HestiaAsicEnv {
  param([hashtable]$Vars)

  Clear-HestiaAsicEnv
  foreach ($key in $Vars.Keys) {
    Set-Item -Path "Env:\$key" -Value ([string]$Vars[$key])
  }
}

$summaryRows = @()

foreach ($policy in $policies) {
  if (!(Test-DesignSelected $policy.Key $policy.Name)) {
    continue
  }
  foreach ($p in $PortsList) {
    $buildDir = Join-Path $runRoot "$($policy.Key)_${p}p"
    New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
    Set-HestiaAsicEnv @{
      HESTIA_ASIC_DESIGN_NAME = $policy.Name
      HESTIA_ASIC_POLICY_MODE = $policy.Mode
      HESTIA_ASIC_PORTS = $p
      HESTIA_ASIC_RANK_WIDTH = 10
      HESTIA_ASIC_SEQ_WIDTH = 16
      HESTIA_ASIC_PAYLOAD_WIDTH = 32
      HESTIA_ASIC_CELL_COUNT_WIDTH = 27
      HESTIA_ASIC_SRAM_CELLS = 81920
      HESTIA_ASIC_BATCH_SIZE = 8
      HESTIA_ASIC_BATCH_SLOTS = 8388608
      HESTIA_ASIC_PACKET_SLOTS = 81920
      HESTIA_ASIC_BBQ_BITMAP_WIDTH = 32
      HESTIA_ASIC_POLICY_ALPHA_SHIFT = 0
    }

    $consoleLog = Join-Path $buildDir "vivado.console.log"
    Write-Host "RUN $($policy.Name) ${p}P -> $buildDir"
    & $VivadoPath -mode batch -source (Join-Path $scriptDir "run_vivado_logic_only_synth.tcl") -tclargs $buildDir $ClockPeriodNs 2>&1 |
      Tee-Object -FilePath $consoleLog
    if ($LASTEXITCODE -ne 0) {
      throw "Vivado failed for $($policy.Name) ${p}P"
    }
    $row = Import-Csv (Join-Path $buildDir "asic_logic_only_resource.csv") | Select-Object -First 1
    $row | Add-Member -NotePropertyName run_dir -NotePropertyValue $buildDir
    $summaryRows += $row
  }
}

$summaryCsv = Join-Path $runRoot "resource_summary.csv"
$summaryMd = Join-Path $runRoot "resource_summary.md"
$summaryRows | Export-Csv -NoTypeInformation -Path $summaryCsv

$md = @()
$md += "# ASIC Logic-Only Resource Sweep"
$md += ""
$md += "Clock target: $ClockPeriodNs ns"
$md += ""
$md += "| Design | Ports | CLB LUTs | CLB Registers | LUTRAM | BRAM | URAM | DSP | WNS ns | Black-box memories |"
$md += "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"
foreach ($row in ($summaryRows | Sort-Object {[int]$_.ports}, design)) {
  $md += "| $($row.design) | $($row.ports) | $($row.clb_luts) | $($row.clb_registers) | $($row.lutram) | $($row.bram_tiles) | $($row.uram) | $($row.dsps) | $($row.wns_ns) | $($row.blackbox_memories) |"
}
$md | Set-Content -Encoding ASCII -Path $summaryMd

Write-Host "Summary CSV: $summaryCsv"
Write-Host "Summary Markdown: $summaryMd"
Clear-HestiaAsicEnv
