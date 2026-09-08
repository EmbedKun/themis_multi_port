#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-both}"
CLOCK_PERIOD_NS="${CLOCK_PERIOD_NS:-3.333}"
VIVADO_BIN="${VIVADO_BIN:-vivado}"
DESIGNS_FILTER="${HESTIA_SWEEP_DESIGNS:-all}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
STAMP="$(date +%Y%m%d_%H%M%S)"
RUN_ROOT="${REPO_DIR}/build/rerun_resource_${MODE}_${STAMP}"
mkdir -p "${RUN_ROOT}"

PORTS_LIST=(1 2 4 8)
POLICY_ROWS=(
  "DT-Hybrid:dt:0"
  "Occamy-Hybrid:occamy:1"
  "OBM-Hybrid:obm:3"
  "Hybrid-Themis:hybrid_themis:4"
)

want_design() {
  local key="$1"
  [[ "${DESIGNS_FILTER}" == "all" ]] && return 0
  [[ ",${DESIGNS_FILTER}," == *",${key},"* ]]
}

run_vivado() {
  local script="$1"
  local build_dir="$2"
  shift 2
  mkdir -p "${build_dir}"
  echo "RUN ${script} -> ${build_dir}"
  env "$@" "${VIVADO_BIN}" -mode batch -source "${REPO_DIR}/${script}" -tclargs "${build_dir}" "${CLOCK_PERIOD_NS}" \
    2>&1 | tee "${build_dir}/vivado.console.log"
}

read_hestia_row() {
  local build_dir="$1"
  local scale="$2"
  python3 - "$build_dir" "$scale" <<'PY'
import csv
import sys
build_dir, scale = sys.argv[1], sys.argv[2]
path = f"{build_dir}/hestia_paper_resource_table.csv"
with open(path, newline="") as fh:
    for row in csv.DictReader(fh):
        if row["row"].endswith("_raw_rtl_resource_core"):
            print(",".join([
                scale, "Hestia", row["ports"], row["clb_luts"],
                row["clb_registers"], "", "", "", row["wns_ns"], build_dir
            ]))
            break
PY
}

read_baseline_row() {
  local build_dir="$1"
  local design="$2"
  local scale="$3"
  python3 - "$build_dir" "$design" "$scale" <<'PY'
import csv
import sys
build_dir, design, scale = sys.argv[1], sys.argv[2], sys.argv[3]
path = f"{build_dir}/baseline_ddr_resource.csv"
with open(path, newline="") as fh:
    row = next(csv.DictReader(fh))
print(",".join([
    scale, design, row["ports"], row["clb_luts"], row["clb_registers"],
    row["lutram"], row["bram_tiles"], row["uram"], row["wns_ns"], build_dir
]))
PY
}

append_markdown() {
  python3 - "$RUN_ROOT/resource_summary.csv" "$RUN_ROOT/resource_summary.md" <<'PY'
import csv
import sys
csv_path, md_path = sys.argv[1], sys.argv[2]
rows = list(csv.DictReader(open(csv_path, newline="")))
with open(md_path, "w", encoding="ascii") as out:
    out.write("# Resource Sweep Rerun\n\n")
    for scale in ("compact", "5MiB+4GiB"):
        scale_rows = [r for r in rows if r["scale"] == scale]
        if not scale_rows:
            continue
        out.write(f"## {scale}\n\n")
        out.write("| Design | Ports | CLB LUTs | CLB Registers | LUTRAM | BRAM tiles | URAM | WNS ns |\n")
        out.write("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n")
        for r in sorted(scale_rows, key=lambda x: (int(x["ports"]), x["design"])):
            out.write(
                f"| {r['design']} | {r['ports']} | {r['clb_luts']} | {r['clb_registers']} | "
                f"{r['lutram']} | {r['bram_tiles']} | {r['uram']} | {r['wns_ns']} |\n"
            )
        out.write("\n")
PY
}

SUMMARY_CSV="${RUN_ROOT}/resource_summary.csv"
echo "scale,design,ports,clb_luts,clb_registers,lutram,bram_tiles,uram,wns_ns,run_dir" > "${SUMMARY_CSV}"

run_compact() {
  local root="${RUN_ROOT}/compact"
  mkdir -p "${root}"

  if want_design hestia; then
    for p in "${PORTS_LIST[@]}"; do
      local build_dir="${root}/hestia_${p}p"
      run_vivado "scripts/synth_hestia_resource_core.tcl" "${build_dir}" \
        HESTIA_RESOURCE_PORTS="${p}" \
        HESTIA_RESOURCE_RANK_WIDTH=6 \
        HESTIA_RESOURCE_SEQ_WIDTH=16 \
        HESTIA_RESOURCE_PAYLOAD_WIDTH=32 \
        HESTIA_RESOURCE_CELL_COUNT_WIDTH=4 \
        HESTIA_RESOURCE_SRAM_CELLS_PER_PORT=8 \
        HESTIA_RESOURCE_BATCH_SLOTS_PER_PORT=8 \
        HESTIA_RESOURCE_PACKETS_PER_PORT=16 \
        HESTIA_RESOURCE_BATCH_SIZE=8 \
        HESTIA_RESOURCE_BBQ_BITMAP_WIDTH=8 \
        HESTIA_RESOURCE_POLICY_MODE=-1 \
        HESTIA_RESOURCE_POLICY_ALPHA_SHIFT=0 \
        HESTIA_RESOURCE_EXTERNAL_METADATA=0
      read_hestia_row "${build_dir}" compact >> "${SUMMARY_CSV}"
    done
  fi

  for row in "${POLICY_ROWS[@]}"; do
    IFS=: read -r design key policy <<<"${row}"
    want_design "${key}" || continue
    for p in "${PORTS_LIST[@]}"; do
      local build_dir="${root}/${key}_${p}p"
      run_vivado "scripts/synth_baseline_ddr_core.tcl" "${build_dir}" \
        HESTIA_BASELINE_DDR_PORTS="${p}" \
        HESTIA_BASELINE_DDR_RANK_WIDTH=6 \
        HESTIA_BASELINE_DDR_SEQ_WIDTH=16 \
        HESTIA_BASELINE_DDR_PAYLOAD_WIDTH=32 \
        HESTIA_BASELINE_DDR_CELL_COUNT_WIDTH=4 \
        HESTIA_BASELINE_DDR_SRAM_CELLS="$((8 * p))" \
        HESTIA_BASELINE_DDR_BATCH_SIZE=8 \
        HESTIA_BASELINE_DDR_BATCH_SLOTS="$((8 * p))" \
        HESTIA_BASELINE_DDR_PACKET_SLOTS="$((16 * p))" \
        HESTIA_BASELINE_DDR_BBQ_BITMAP_WIDTH=8 \
        HESTIA_BASELINE_DDR_POLICY_MODE="${policy}" \
        HESTIA_BASELINE_DDR_POLICY_ALPHA_SHIFT=0 \
        HESTIA_BASELINE_DDR_EXTERNAL_METADATA=0
      read_baseline_row "${build_dir}" "${design}" compact >> "${SUMMARY_CSV}"
    done
  done
}

run_fullscale() {
  local root="${RUN_ROOT}/fullscale_5MiB_4GiB"
  mkdir -p "${root}"

  if want_design hestia; then
    for p in "${PORTS_LIST[@]}"; do
      local build_dir="${root}/hestia_${p}p"
      run_vivado "scripts/synth_hestia_resource_core.tcl" "${build_dir}" \
        HESTIA_RESOURCE_PORTS="${p}" \
        HESTIA_RESOURCE_RANK_WIDTH=10 \
        HESTIA_RESOURCE_SEQ_WIDTH=16 \
        HESTIA_RESOURCE_PAYLOAD_WIDTH=32 \
        HESTIA_RESOURCE_CELL_COUNT_WIDTH=27 \
        HESTIA_RESOURCE_SRAM_CELLS=81920 \
        HESTIA_RESOURCE_BATCH_SIZE=8 \
        HESTIA_RESOURCE_BATCH_SLOTS=8388608 \
        HESTIA_RESOURCE_PACKET_SLOTS=81920 \
        HESTIA_RESOURCE_BBQ_BITMAP_WIDTH=32 \
        HESTIA_RESOURCE_POLICY_MODE=-1 \
        HESTIA_RESOURCE_POLICY_ALPHA_SHIFT=0 \
        HESTIA_RESOURCE_EXTERNAL_METADATA=1
      read_hestia_row "${build_dir}" "5MiB+4GiB" >> "${SUMMARY_CSV}"
    done
  fi

  for row in "${POLICY_ROWS[@]}"; do
    IFS=: read -r design key policy <<<"${row}"
    want_design "${key}" || continue
    for p in "${PORTS_LIST[@]}"; do
      local build_dir="${root}/${key}_${p}p"
      run_vivado "scripts/synth_baseline_ddr_core.tcl" "${build_dir}" \
        HESTIA_BASELINE_DDR_PORTS="${p}" \
        HESTIA_BASELINE_DDR_RANK_WIDTH=10 \
        HESTIA_BASELINE_DDR_SEQ_WIDTH=16 \
        HESTIA_BASELINE_DDR_PAYLOAD_WIDTH=32 \
        HESTIA_BASELINE_DDR_CELL_COUNT_WIDTH=27 \
        HESTIA_BASELINE_DDR_SRAM_CELLS=81920 \
        HESTIA_BASELINE_DDR_BATCH_SIZE=8 \
        HESTIA_BASELINE_DDR_BATCH_SLOTS=8388608 \
        HESTIA_BASELINE_DDR_PACKET_SLOTS=81920 \
        HESTIA_BASELINE_DDR_BBQ_BITMAP_WIDTH=32 \
        HESTIA_BASELINE_DDR_POLICY_MODE="${policy}" \
        HESTIA_BASELINE_DDR_POLICY_ALPHA_SHIFT=0 \
        HESTIA_BASELINE_DDR_EXTERNAL_METADATA=1
      read_baseline_row "${build_dir}" "${design}" "5MiB+4GiB" >> "${SUMMARY_CSV}"
    done
  done
}

case "${MODE}" in
  compact) run_compact ;;
  fullscale) run_fullscale ;;
  both) run_compact; run_fullscale ;;
  *) echo "Usage: $0 [compact|fullscale|both]" >&2; exit 2 ;;
esac

append_markdown
echo "Summary CSV: ${SUMMARY_CSV}"
echo "Summary Markdown: ${RUN_ROOT}/resource_summary.md"
