#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
handoff_dir="$(cd -- "${script_dir}/.." && pwd)"
repo_dir="$(cd -- "${handoff_dir}/.." && pwd)"

dc_bin="${DC_BIN:-dc_shell}"
sdc_file="${HESTIA_ASIC_SDC:-asic_handoff/constraints/hestia_1ghz.sdc}"
clock_tag="${HESTIA_ASIC_CLOCK_TAG:-1ghz}"
ports_list="${HESTIA_ASIC_PORTS_LIST:-4}"
design_filter="${HESTIA_ASIC_SWEEP_DESIGNS:-all}"
stamp="$(date +%Y%m%d_%H%M%S)"
run_root="${1:-${repo_dir}/build/dc_logic_only_${clock_tag}_${stamp}}"

mkdir -p "${run_root}"

policy_keys=(hestia dt occamy obm hybrid_themis)
policy_names=("Hestia" "DT-Hybrid" "Occamy-Hybrid" "OBM-Hybrid" "Hybrid-Themis")
policy_modes=(-1 0 1 3 4)

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

echo "DC sweep root: ${run_root}"
echo "SDC: ${sdc_file}"
echo "Ports: ${ports_list}"

for idx in "${!policy_keys[@]}"; do
  key="${policy_keys[$idx]}"
  name="${policy_names[$idx]}"
  mode="${policy_modes[$idx]}"
  if ! should_run_design "${key}" "${name}"; then
    continue
  fi

  for p in ${ports_list}; do
    report_dir="${run_root}/${key}_${p}p"
    mkdir -p "${report_dir}"
    echo "RUN ${name} ${p}P -> ${report_dir}"
    (
      export HESTIA_ASIC_DESIGN_NAME="${name}"
      export HESTIA_ASIC_POLICY_MODE="${mode}"
      export HESTIA_ASIC_PORTS="${p}"
      export HESTIA_ASIC_SDC="${sdc_file}"
      export HESTIA_ASIC_REPORT_DIR="${report_dir}"
      "${dc_bin}" -f "${script_dir}/run_dc_logic_only.tcl"
    ) 2>&1 | tee "${report_dir}/dc.console.log"
  done
done

echo "Done. Collect area_hier.rpt, timing.rpt, and power.rpt from:"
echo "${run_root}"
