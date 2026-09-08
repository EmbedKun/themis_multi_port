#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
handoff_dir="$(cd -- "${script_dir}/.." && pwd)"
repo_dir="$(cd -- "${handoff_dir}/.." && pwd)"
vivado_bin="${VIVADO_BIN:-vivado}"
clk_period_ns="${HESTIA_ASIC_CLK_PERIOD_NS:-1.000}"
stamp="$(date +%Y%m%d_%H%M%S)"
run_root="${1:-${repo_dir}/build/asic_logic_only_${stamp}}"
ports_list="${HESTIA_ASIC_PORTS_LIST:-4}"
design_filter="${HESTIA_ASIC_SWEEP_DESIGNS:-all}"

mkdir -p "${run_root}"

policy_keys=(hestia dt occamy obm hybrid_themis)
policy_names=("Hestia" "DT-Hybrid" "Occamy-Hybrid" "OBM-Hybrid" "Hybrid-Themis")
policy_modes=(-1 0 1 3 4)

summary_csv="${run_root}/resource_summary.csv"
summary_md="${run_root}/resource_summary.md"
echo "design,policy_mode,ports,rank_width,seq_width,cell_count_width,sram_cells,batch_size,batch_slots,packet_slots,bbq_bitmap_width,clb_luts,clb_registers,lutram,bram_tiles,uram,dsps,wns_ns,blackbox_memories,run_dir" > "${summary_csv}"

should_run_design() {
  local key="$1"
  local name="$2"
  if [[ "${design_filter}" == "all" ]]; then
    return 0
  fi
  case ",${design_filter}," in
    *",${key},"*|*",${name},"*) return 0 ;;
    *) return 1 ;;
  esac
}

for idx in "${!policy_keys[@]}"; do
  key="${policy_keys[$idx]}"
  name="${policy_names[$idx]}"
  mode="${policy_modes[$idx]}"
  if ! should_run_design "${key}" "${name}"; then
    continue
  fi
  for p in ${ports_list}; do
    build_dir="${run_root}/${key}_${p}p"
    mkdir -p "${build_dir}"
    echo "RUN ${name} ${p}P -> ${build_dir}"
    (
      export HESTIA_ASIC_DESIGN_NAME="${name}"
      export HESTIA_ASIC_POLICY_MODE="${mode}"
      export HESTIA_ASIC_PORTS="${p}"
      export HESTIA_ASIC_RANK_WIDTH="${HESTIA_ASIC_RANK_WIDTH:-10}"
      export HESTIA_ASIC_SEQ_WIDTH="${HESTIA_ASIC_SEQ_WIDTH:-16}"
      export HESTIA_ASIC_PAYLOAD_WIDTH="${HESTIA_ASIC_PAYLOAD_WIDTH:-32}"
      export HESTIA_ASIC_CELL_COUNT_WIDTH="${HESTIA_ASIC_CELL_COUNT_WIDTH:-27}"
      export HESTIA_ASIC_SRAM_CELLS="${HESTIA_ASIC_SRAM_CELLS:-81920}"
      export HESTIA_ASIC_BATCH_SIZE="${HESTIA_ASIC_BATCH_SIZE:-8}"
      export HESTIA_ASIC_BATCH_SLOTS="${HESTIA_ASIC_BATCH_SLOTS:-8388608}"
      export HESTIA_ASIC_PACKET_SLOTS="${HESTIA_ASIC_PACKET_SLOTS:-81920}"
      export HESTIA_ASIC_BBQ_BITMAP_WIDTH="${HESTIA_ASIC_BBQ_BITMAP_WIDTH:-32}"
      export HESTIA_ASIC_POLICY_ALPHA_SHIFT="${HESTIA_ASIC_POLICY_ALPHA_SHIFT:-0}"
      "${vivado_bin}" -mode batch -source "${script_dir}/run_vivado_logic_only_synth.tcl" -tclargs "${build_dir}" "${clk_period_ns}"
    ) 2>&1 | tee "${build_dir}/vivado.console.log"
    tail -n +2 "${build_dir}/asic_logic_only_resource.csv" | sed "s#\$#,${build_dir}#" >> "${summary_csv}"
  done
done

{
  echo "# ASIC Logic-Only Resource Sweep"
  echo
  echo "Clock target: ${clk_period_ns} ns"
  echo
  echo "| Design | Ports | CLB LUTs | CLB Registers | LUTRAM | BRAM | URAM | DSP | WNS ns | Black-box memories |"
  echo "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"
  awk -F, 'NR>1 {printf("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n", $1, $3, $12, $13, $14, $15, $16, $17, $18, $19)}' "${summary_csv}"
} > "${summary_md}"

echo "Summary CSV: ${summary_csv}"
echo "Summary Markdown: ${summary_md}"
