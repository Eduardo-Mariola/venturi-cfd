"""Run the axisymmetric potential-flow venturi case and save the figures.

Usage:
    python run_potential_case.py
"""

import argparse
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

from venturi_cfd import solve_potential
from venturi_cfd.plots import (plot_axis_profiles, plot_head_loss,
                               plot_pressure_field, plot_velocity_field)
from venturi_cfd.validation import potential_report


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--outdir", default=None,
                    help="output directory for figures (default: ../../results/python)")
    args = ap.parse_args()

    outdir = pathlib.Path(args.outdir) if args.outdir else \
        pathlib.Path(__file__).resolve().parents[2] / "results" / "python"
    outdir.mkdir(parents=True, exist_ok=True)

    res = solve_potential()
    potential_report(res)

    plot_velocity_field(
        res, outdir / "venturi_potential_velocity.png",
        "Potential flow - velocity |U|: throat acceleration (streamlines)")
    plot_pressure_field(
        res, outdir / "venturi_potential_pressure.png",
        "Potential flow - Bernoulli pressure: depression at the throat")
    plot_axis_profiles(
        res, outdir / "venturi_potential_axis_profiles.png",
        "Axis profiles: max velocity and min pressure at the throat")
    plot_head_loss(
        res.zc, res.hf * 1000.0, res.geom,
        outdir / "venturi_potential_head_loss.png",
        "Viscous head loss (laminar Darcy-Weisbach) along the venturi",
        r"Cumulative head loss $h_f$  [mm w.c.]")
    print(f"\nFigures saved to: {outdir}")


if __name__ == "__main__":
    main()
