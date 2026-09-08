param(
  [ValidateSet("compact", "fullscale", "both")]
  [string]$Mode = "both",
  [string]$VivadoPath = "D:\Xilinx\Vivado\2020.2\bin\vivado.bat",
  [string]$ClockPeriodNs = "3.333"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoDir = Resolve-Path (Join-Path $PSScriptRoot "..")
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$runRoot = Join-Path $repoDir "build\rerun_resource_${Mode}_$stamp"
New-Item -ItemType Directory -Force -Path $runRoot | Out-Null

if (!(Test-Path $VivadoPath)) {
  throw "Vivado was not found at $VivadoPath"
}

$portsList = @(1, 2, 4, 8)
$policies = @(
  @{ Design = "DT-Hybrid";      Key = "dt";     Mode = 0 },
  @{ Design = "Occamy-Hybrid";  Key = "occamy"; Mode = 1 },
  @{ Design = "OBM-Hybrid";     Key = "obm";    Mode = 3 },
  @{ Design = "Hybrid-Themis";  Key = "hybrid_themis"; Mode = 4 }
)

$managedEnv = @(
  "HESTIA_RESOURCE_PORTS",
  "HESTIA_RESOURCE_RANK_WIDTH",
  "HESTIA_RESOURCE_SEQ_WIDTH",
  "HESTIA_RESOURCE_PAYLOAD_WIDTH",
  "HESTIA_RESOURCE_CELL_COUNT_WIDTH",
  "HESTIA_RESOURCE_SRAM_CELLS_PER_PORT",
  "HESTIA_RESOURCE_BATCH_SLOTS_PER_PORT",
  "HESTIA_RESOURCE_PACKETS_PER_PORT",
  "HESTIA_RESOURCE_SRAM_CELLS",
  "HESTIA_RESOURCE_BATCH_SIZE",
  "HESTIA_RESOURCE_BATCH_SLOTS",
  "HESTIA_RESOURCE_PACKET_SLOTS",
  "HESTIA_RESOURCE_BBQ_BITMAP_WIDTH",
  "HESTIA_RESOURCE_POLICY_MODE",
  "HESTIA_RESOURCE_POLICY_ALPHA_SHIFT",
  "HESTIA_RESOURCE_EXTERNAL_METADATA",
  "HESTIA_BASELINE_DDR_PORTS",
  "HESTIA_BASELINE_DDR_RANK_WIDTH",
  "HESTIA_BASELINE_DDR_SEQ_WIDTH",
  "HESTIA_BASELINE_DDR_PAYLOAD_WIDTH",
  "HESTIA_BASELINE_DDR_CELL_COUNT_WIDTH",
  "HESTIA_BASELINE_DDR_SRAM_CELLS",
  "HESTIA_BASELINE_DDR_BATCH_SIZE",
  "HESTIA_BASELINE_DDR_BATCH_SLOTS",
  "HESTIA_BASELINE_DDR_PACKET_SLOTS",
  "HESTIA_BASELINE_DDR_BBQ_BITMAP_WIDTH",
  "HESTIA_BASELINE_DDR_POLICY_MODE",
  "HESTIA_BASELINE_DDR_POLICY_ALPHA_SHIFT",
  "HESTIA_BASELINE_DDR_EXTERNAL_METADATA"
)

function Clear-HestiaEnv {
  foreach ($name in $managedEnv) {
    Remove-Item "Env:\$name" -ErrorAction SilentlyContinue
  }
}

function Set-HestiaEnv {
  param([hashtable]$Vars)

  Clear-HestiaEnv
  foreach ($key in $Vars.Keys) {
    Set-Item -Path "Env:\$key" -Value ([string]$Vars[$key])
  }
}

function Invoke-VivadoBatch {
  param(
    [string]$TclScript,
    [string]$BuildDir,
    [hashtable]$EnvVars
  )

  New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
  Set-HestiaEnv $EnvVars
  $consoleLog = Join-Path $BuildDir "vivado.console.log"
  Write-Host "RUN $TclScript -> $BuildDir"
  & $VivadoPath -mode batch -source (Join-Path $repoDir $TclScript) -tclargs $BuildDir $ClockPeriodNs 2>&1 |
    Tee-Object -FilePath $consoleLog
  if ($LASTEXITCODE -ne 0) {
    throw "Vivado failed for $TclScript in $BuildDir"
  }
}

function Read-HestiaResourceRow {
  param(
    [string]$BuildDir,
    [string]$Design,
    [string]$Scale
  )

  $csvPath = Join-Path $BuildDir "hestia_paper_resource_table.csv"
  $raw = Import-Csv $csvPath | Where-Object { $_.row -like "hestia_*_raw_rtl_resource_core" } | Select-Object -First 1
  [pscustomobject]@{
    scale = $Scale
    design = $Design
    ports = [int]$raw.ports
    clb_luts = [int]$raw.clb_luts
    clb_registers = [int]$raw.clb_registers
    lutram = ""
    bram_tiles = ""
    uram = ""
    wns_ns = $raw.wns_ns
    run_dir = $BuildDir
  }
}

function Read-BaselineResourceRow {
  param(
    [string]$BuildDir,
    [string]$Design,
    [string]$Scale
  )

  $csvPath = Join-Path $BuildDir "baseline_ddr_resource.csv"
  $raw = Import-Csv $csvPath | Select-Object -First 1
  [pscustomobject]@{
    scale = $Scale
    design = $Design
    ports = [int]$raw.ports
    clb_luts = [int]$raw.clb_luts
    clb_registers = [int]$raw.clb_registers
    lutram = [int]$raw.lutram
    bram_tiles = [int]$raw.bram_tiles
    uram = [int]$raw.uram
    wns_ns = $raw.wns_ns
    run_dir = $BuildDir
  }
}

function Run-CompactSweep {
  $rows = @()
  $root = Join-Path $runRoot "compact"
  New-Item -ItemType Directory -Force -Path $root | Out-Null

  foreach ($p in $portsList) {
    $buildDir = Join-Path $root "hestia_${p}p"
    Invoke-VivadoBatch "scripts\synth_hestia_resource_core.tcl" $buildDir @{
      HESTIA_RESOURCE_PORTS = $p
      HESTIA_RESOURCE_RANK_WIDTH = 6
      HESTIA_RESOURCE_SEQ_WIDTH = 16
      HESTIA_RESOURCE_PAYLOAD_WIDTH = 32
      HESTIA_RESOURCE_CELL_COUNT_WIDTH = 4
      HESTIA_RESOURCE_SRAM_CELLS_PER_PORT = 8
      HESTIA_RESOURCE_BATCH_SLOTS_PER_PORT = 8
      HESTIA_RESOURCE_PACKETS_PER_PORT = 16
      HESTIA_RESOURCE_BATCH_SIZE = 8
      HESTIA_RESOURCE_BBQ_BITMAP_WIDTH = 8
      HESTIA_RESOURCE_POLICY_MODE = -1
      HESTIA_RESOURCE_POLICY_ALPHA_SHIFT = 0
      HESTIA_RESOURCE_EXTERNAL_METADATA = 0
    }
    $rows += Read-HestiaResourceRow $buildDir "Hestia" "compact"
  }

  foreach ($policy in $policies) {
    foreach ($p in $portsList) {
      $buildDir = Join-Path $root "$($policy.Key)_${p}p"
      Invoke-VivadoBatch "scripts\synth_baseline_ddr_core.tcl" $buildDir @{
        HESTIA_BASELINE_DDR_PORTS = $p
        HESTIA_BASELINE_DDR_RANK_WIDTH = 6
        HESTIA_BASELINE_DDR_SEQ_WIDTH = 16
        HESTIA_BASELINE_DDR_PAYLOAD_WIDTH = 32
        HESTIA_BASELINE_DDR_CELL_COUNT_WIDTH = 4
        HESTIA_BASELINE_DDR_SRAM_CELLS = (8 * $p)
        HESTIA_BASELINE_DDR_BATCH_SIZE = 8
        HESTIA_BASELINE_DDR_BATCH_SLOTS = (8 * $p)
        HESTIA_BASELINE_DDR_PACKET_SLOTS = (16 * $p)
        HESTIA_BASELINE_DDR_BBQ_BITMAP_WIDTH = 8
        HESTIA_BASELINE_DDR_POLICY_MODE = $policy.Mode
        HESTIA_BASELINE_DDR_POLICY_ALPHA_SHIFT = 0
        HESTIA_BASELINE_DDR_EXTERNAL_METADATA = 0
      }
      $rows += Read-BaselineResourceRow $buildDir $policy.Design "compact"
    }
  }

  return $rows
}

function Run-FullScaleSweep {
  $rows = @()
  $root = Join-Path $runRoot "fullscale_5MiB_4GiB"
  New-Item -ItemType Directory -Force -Path $root | Out-Null

  foreach ($p in $portsList) {
    $buildDir = Join-Path $root "hestia_${p}p"
    Invoke-VivadoBatch "scripts\synth_hestia_resource_core.tcl" $buildDir @{
      HESTIA_RESOURCE_PORTS = $p
      HESTIA_RESOURCE_RANK_WIDTH = 10
      HESTIA_RESOURCE_SEQ_WIDTH = 16
      HESTIA_RESOURCE_PAYLOAD_WIDTH = 32
      HESTIA_RESOURCE_CELL_COUNT_WIDTH = 27
      HESTIA_RESOURCE_SRAM_CELLS = 81920
      HESTIA_RESOURCE_BATCH_SIZE = 8
      HESTIA_RESOURCE_BATCH_SLOTS = 8388608
      HESTIA_RESOURCE_PACKET_SLOTS = 81920
      HESTIA_RESOURCE_BBQ_BITMAP_WIDTH = 32
      HESTIA_RESOURCE_POLICY_MODE = -1
      HESTIA_RESOURCE_POLICY_ALPHA_SHIFT = 0
      HESTIA_RESOURCE_EXTERNAL_METADATA = 1
    }
    $rows += Read-HestiaResourceRow $buildDir "Hestia" "5MiB+4GiB"
  }

  foreach ($policy in $policies) {
    foreach ($p in $portsList) {
      $buildDir = Join-Path $root "$($policy.Key)_${p}p"
      Invoke-VivadoBatch "scripts\synth_baseline_ddr_core.tcl" $buildDir @{
        HESTIA_BASELINE_DDR_PORTS = $p
        HESTIA_BASELINE_DDR_RANK_WIDTH = 10
        HESTIA_BASELINE_DDR_SEQ_WIDTH = 16
        HESTIA_BASELINE_DDR_PAYLOAD_WIDTH = 32
        HESTIA_BASELINE_DDR_CELL_COUNT_WIDTH = 27
        HESTIA_BASELINE_DDR_SRAM_CELLS = 81920
        HESTIA_BASELINE_DDR_BATCH_SIZE = 8
        HESTIA_BASELINE_DDR_BATCH_SLOTS = 8388608
        HESTIA_BASELINE_DDR_PACKET_SLOTS = 81920
        HESTIA_BASELINE_DDR_BBQ_BITMAP_WIDTH = 32
        HESTIA_BASELINE_DDR_POLICY_MODE = $policy.Mode
        HESTIA_BASELINE_DDR_POLICY_ALPHA_SHIFT = 0
        HESTIA_BASELINE_DDR_EXTERNAL_METADATA = 1
      }
      $rows += Read-BaselineResourceRow $buildDir $policy.Design "5MiB+4GiB"
    }
  }

  return $rows
}

function Write-Summary {
  param([object[]]$Rows)

  function Expand-Rows {
    param([object]$Item)
    if ($null -eq $Item) {
      return
    }
    if ($Item -is [System.Array]) {
      foreach ($subItem in $Item) {
        Expand-Rows $subItem
      }
    } else {
      $Item
    }
  }
  $Rows = @(Expand-Rows $Rows)

  $csvPath = Join-Path $runRoot "resource_summary.csv"
  $mdPath = Join-Path $runRoot "resource_summary.md"
  $Rows | Sort-Object scale, design, ports | Export-Csv -NoTypeInformation -Path $csvPath

  $md = @()
  $md += "# Resource Sweep Rerun"
  $md += ""
  $md += "Date: $(Get-Date -Format yyyy-MM-dd)"
  $md += ""
  $md += "Vivado: $VivadoPath"
  $md += "Clock target: $ClockPeriodNs ns"
  $md += ""
  foreach ($scale in @("compact", "5MiB+4GiB")) {
    $scaleRows = $Rows | Where-Object { $_.scale -eq $scale }
    if ($scaleRows.Count -eq 0) { continue }
    $md += "## $scale"
    $md += ""
    $md += "| Design | Ports | CLB LUTs | CLB Registers | LUTRAM | BRAM tiles | URAM | WNS ns |"
    $md += "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"
    foreach ($r in ($scaleRows | Sort-Object ports, design)) {
      $md += "| $($r.design) | $($r.ports) | $($r.clb_luts) | $($r.clb_registers) | $($r.lutram) | $($r.bram_tiles) | $($r.uram) | $($r.wns_ns) |"
    }
    $md += ""
  }
  $md | Set-Content -Encoding ASCII -Path $mdPath
  Write-Host "Summary CSV: $csvPath"
  Write-Host "Summary Markdown: $mdPath"
}

$allRows = @()
if ($Mode -eq "compact" -or $Mode -eq "both") {
  $allRows += Run-CompactSweep
}
if ($Mode -eq "fullscale" -or $Mode -eq "both") {
  $allRows += Run-FullScaleSweep
}

Write-Summary $allRows
Clear-HestiaEnv
