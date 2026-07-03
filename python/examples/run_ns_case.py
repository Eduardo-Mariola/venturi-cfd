"""Run the axisymmetric Navier-Stokes venturi case and save the figures.

Usage:
    python run_ns_case.py            # production mesh (300x60)
    python run_ns_case.py --quick    # coarse mesh, fast sanity check
"""

import argparse
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

from venturi_cfd import solve_ns
from venturi_cfd.plots import (plot_axis_profiles, plot_head_loss,
                               plot_pressure_field, plot_velocity_field)
from venturi_cfd.validation import ns_report


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--quick", action="store_true",
                    help="coarse mesh for a fast test run")
    ap.add_argument("--outdir", default=None,
                    help="output directory for figures (default: ../../results/python)")
    args = ap.parse_args()

    outdir = pathlib.Path(args.outdir) if args.outdir else \
        pathlib.Path(__file__).resolve().parents[2] / "results" / "python"
    outdir.mkdir(parents=True, exist_ok=True)

    res = solve_ns(quick=args.quick)
    ns_report(res)

    rho_g = res.fluid_props.rho * res.fluid_props.g
    pa = res.p[:, 0]
    hpiezo_mm = (pa - pa[-1]) / rho_g * 1000.0

    plot_velocity_field(
        res, outdir / "venturi_cfd_velocity.png",
        "Velocity field |U| - throat acceleration (streamlines)")
    plot_pressure_field(
        res, outdir / "venturi_cfd_pressure.png",
        "Pressure field p [Pa] - drop at the throat, recovery in the diffuser")
    plot_axis_profiles(
        res, outdir / "venturi_cfd_axis_profiles.png",
        "Axis profiles: max velocity and min pressure at the throat")
    plot_head_loss(
        res.zc, hpiezo_mm, res.geom, outdir / "venturi_cfd_head_loss.png",
        "Head loss along the venturi (partial recovery in the diffuser)",
        r"$(p - p_{out})/\rho g$  [mm w.c.]")
    print(f"\nFigures saved to: {outdir}")


if __name__ == "__main__":
    main()
