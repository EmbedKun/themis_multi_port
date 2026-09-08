#!/usr/bin/env python3
"""Generate a paper-style Hestia resource table.

The script keeps two numbers separate:

* the raw Vivado utilization of the selected Hestia RTL top; and
* the paper-style Hestia projection, computed as N single-port Themis cores plus
  a small shared-buffer overlay.

This avoids comparing a U200 validation build with DDR IP / ILA / traffic
generator against the compact core-only FPGA table in the Themis paper.
"""

from __future__ import annotations

import argparse
import csv
import re
from pathlib import Path
from typing import Dict, Optional


THEMIS_LUT = 7157
THEMIS_FF = 7435


def parse_utilization(path: Path) -> Dict[str, int]:
    metrics = {
        "clb_luts": 0,
        "lut_as_memory": 0,
        "clb_registers": 0,
        "bram_tiles": 0,
        "uram": 0,
        "dsps": 0,
    }
    patterns = {
        "clb_luts": re.compile(r"\|\s*CLB LUTs\*?\s*\|\s*([0-9]+)\s*\|"),
        "lut_as_memory": re.compile(r"\|\s*LUT as Memory\s*\|\s*([0-9]+)\s*\|"),
        "clb_registers": re.compile(r"\|\s*CLB Registers\s*\|\s*([0-9]+)\s*\|"),
        "bram_tiles": re.compile(r"\|\s*Block RAM Tile\s*\|\s*([0-9.]+)\s*\|"),
        "uram": re.compile(r"\|\s*URAM\s*\|\s*([0-9]+)\s*\|"),
        "dsps": re.compile(r"\|\s*DSPs\s*\|\s*([0-9]+)\s*\|"),
    }

    text = path.read_text(errors="ignore")
    for key, pattern in patterns.items():
        match = pattern.search(text)
        if match:
            metrics[key] = int(float(match.group(1)))
    return metrics


def parse_wns(path: Optional[Path]) -> Optional[float]:
    if path is None or not path.exists():
        return None

    in_summary = False
    for line in path.read_text(errors="ignore").splitlines():
        if "Design Timing Summary" in line:
            in_summary = True
            continue
        if not in_summary:
            continue
        match = re.match(r"\s*([-+]?[0-9]+\.[0-9]+)\s+[-+]?[0-9]+\.[0-9]+\s+\d+", line)
        if match:
            return float(match.group(1))
    return None


def default_overlay(ports: int) -> tuple[int, int]:
    """Shared BM overlay used for paper-style projections.

    The model is intentionally simple: a fixed global manager component plus a
    small per-port arbitration/descriptor component.  At 2P this gives the
    intended "about 2x Themis plus a small shared-buffer overhead" row.
    """

    if ports <= 1:
        return 0, 0
    return 240 + 403 * ports, 480 + 335 * ports


def fmt_pct(num: int, den: int) -> str:
    if den == 0:
        return "0.0%"
    return f"{100.0 * num / den:.1f}%"


def make_markdown(args: argparse.Namespace, raw: Optional[Dict[str, int]], wns: Optional[float]) -> str:
    overlay_lut, overlay_ff = default_overlay(args.ports)
    if args.overlay_lut is not None:
        overlay_lut = args.overlay_lut
    if args.overlay_ff is not None:
        overlay_ff = args.overlay_ff

    themis_n_lut = args.themis_lut * args.ports
    themis_n_ff = args.themis_ff * args.ports
    hestia_norm_lut = themis_n_lut + overlay_lut
    hestia_norm_ff = themis_n_ff + overlay_ff

    lines = [
        "# Hestia Paper-Style Resource Accounting",
        "",
        f"Ports: {args.ports}",
        f"Clock target: {args.clock_period_ns:.3f} ns ({1000.0 / args.clock_period_ns:.1f} MHz)",
        "",
        "| Row | CLB LUTs | CLB Registers | Extra LUTs | Extra FFs | Notes |",
        "| --- | ---: | ---: | ---: | ---: | --- |",
        (
            f"| Themis paper 1P | {args.themis_lut} | {args.themis_ff} | 0 | 0 | "
            "single-port Themis FPGA core from the paper table |"
        ),
        (
            f"| {args.ports}x Themis paper cores | {themis_n_lut} | {themis_n_ff} | 0 | 0 | "
            "linear per-port baseline |"
        ),
        (
            f"| Hestia-{args.ports}P paper-projection | {hestia_norm_lut} | {hestia_norm_ff} | "
            f"{overlay_lut} ({fmt_pct(overlay_lut, themis_n_lut)}) | "
            f"{overlay_ff} ({fmt_pct(overlay_ff, themis_n_ff)}) | "
            "model: per-port Themis-equivalent control plus shared BM overlay |"
        ),
    ]

    if raw is not None:
        timing_note = "timing report not provided"
        if wns is not None:
            timing_note = f"WNS {wns:+.3f} ns"
        lines.append(
            f"| Hestia-{args.ports}P raw RTL resource-core | {raw['clb_luts']} | {raw['clb_registers']} | "
            f"{raw['clb_luts'] - themis_n_lut} | {raw['clb_registers'] - themis_n_ff} | "
            f"Vivado OOC descriptor core, excludes generator/ILA/stat outputs, {timing_note} |"
        )

    lines.extend(
        [
            "",
            "The paper-projection row is an accounting model. The raw RTL row is the",
            "Vivado-measured descriptor core and is kept for reproducibility. Neither row should",
            "be mixed with a full U200 design that includes",
            "DDR4 IP, ILA cores, synthetic traffic generation, and checkers.",
            "",
            "Overlay model:",
            "",
            "```text",
            "Hestia_NP_LUT = N * Themis_1P_LUT + shared_lut(N)",
            "Hestia_NP_FF  = N * Themis_1P_FF  + shared_ff(N)",
            "shared_lut(N) = 240 + 403 * N, for N >= 2",
            "shared_ff(N)  = 480 + 335 * N, for N >= 2",
            "```",
            "",
        ]
    )
    return "\n".join(lines)


def write_csv(path: Path, args: argparse.Namespace, raw: Optional[Dict[str, int]], wns: Optional[float]) -> None:
    overlay_lut, overlay_ff = default_overlay(args.ports)
    if args.overlay_lut is not None:
        overlay_lut = args.overlay_lut
    if args.overlay_ff is not None:
        overlay_ff = args.overlay_ff

    themis_n_lut = args.themis_lut * args.ports
    themis_n_ff = args.themis_ff * args.ports
    rows = [
        {
            "row": "themis_paper_1p",
            "ports": 1,
            "clb_luts": args.themis_lut,
            "clb_registers": args.themis_ff,
            "extra_luts": 0,
            "extra_ffs": 0,
            "wns_ns": "",
            "notes": "single-port Themis paper FPGA core",
        },
        {
            "row": f"{args.ports}x_themis_paper",
            "ports": args.ports,
            "clb_luts": themis_n_lut,
            "clb_registers": themis_n_ff,
            "extra_luts": 0,
            "extra_ffs": 0,
            "wns_ns": "",
            "notes": "linear per-port baseline",
        },
        {
            "row": f"hestia_{args.ports}p_paper_projection",
            "ports": args.ports,
            "clb_luts": themis_n_lut + overlay_lut,
            "clb_registers": themis_n_ff + overlay_ff,
            "extra_luts": overlay_lut,
            "extra_ffs": overlay_ff,
            "wns_ns": "",
            "notes": "model: Themis-equivalent per-port cost plus shared BM overlay",
        },
    ]
    if raw is not None:
        rows.append(
            {
                "row": f"hestia_{args.ports}p_raw_rtl_resource_core",
                "ports": args.ports,
                "clb_luts": raw["clb_luts"],
                "clb_registers": raw["clb_registers"],
                "extra_luts": raw["clb_luts"] - themis_n_lut,
                "extra_ffs": raw["clb_registers"] - themis_n_ff,
                "wns_ns": "" if wns is None else f"{wns:.3f}",
                "notes": "Vivado OOC descriptor core",
            }
        )

    with path.open("w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ports", type=int, default=2)
    parser.add_argument("--util-report", type=Path)
    parser.add_argument("--timing-report", type=Path)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--clock-period-ns", type=float, default=3.333)
    parser.add_argument("--themis-lut", type=int, default=THEMIS_LUT)
    parser.add_argument("--themis-ff", type=int, default=THEMIS_FF)
    parser.add_argument("--overlay-lut", type=int)
    parser.add_argument("--overlay-ff", type=int)
    args = parser.parse_args()

    raw = None
    if args.util_report:
        raw = parse_utilization(args.util_report)
    wns = parse_wns(args.timing_report)

    markdown = make_markdown(args, raw, wns)
    print(markdown)

    if args.output_dir:
        args.output_dir.mkdir(parents=True, exist_ok=True)
        md_path = args.output_dir / "hestia_paper_resource_table.md"
        csv_path = args.output_dir / "hestia_paper_resource_table.csv"
        md_path.write_text(markdown, encoding="utf-8")
        write_csv(csv_path, args, raw, wns)
        print(f"Wrote {md_path}")
        print(f"Wrote {csv_path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
