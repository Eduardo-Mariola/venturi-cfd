"""Analytical cross-checks: continuity, Bernoulli, Reynolds, Cd and K.

Same verification report as the MATLAB solvers, so the Python and MATLAB
results can be compared line by line.
"""

import numpy as np


def area_mean_p(p, fluid, rc, dr, zc, zq):
    """Area-weighted mean pressure of the cross-section nearest to z = zq."""
    i = int(np.argmin(np.abs(zc - zq)))
    row, m = p[i, :], fluid[i, :]
    w = 2.0 * np.pi * rc[m] * dr
    return float(np.sum(row[m] * w) / np.sum(w))


def ns_report(res, verbose=True):
    """Verification report for the Navier-Stokes solution.

    Returns a dict with the derived quantities (also printed when verbose).
    """
    g = res.geom
    fl = res.fluid_props
    rho, mu = fl.rho, fl.mu
    v_in = res.v_in
    A1, At, beta = g.A1, g.At, g.beta

    Q = 2.0 * np.pi * np.sum(res.u[0, res.fluid[0]] * res.rc[res.fluid[0]]) * res.dr
    v1_cfd = Q / A1
    vt_teo = v_in * (g.R1 / g.Rt) ** 2
    Re_in = rho * v_in * (2 * g.R1) / mu
    Re_th = rho * vt_teo * (2 * g.Rt) / mu

    p_in = area_mean_p(res.p, res.fluid, res.rc, res.dr, res.zc, res.zc[0])
    p_th = area_mean_p(res.p, res.fluid, res.rc, res.dr, res.zc, (g.z2 + g.z3) / 2)
    p_out = area_mean_p(res.p, res.fluid, res.rc, res.dr, res.zc, res.zc[-1])
    dP_inth = p_in - p_th
    dP_bern = 0.5 * rho * (vt_teo**2 - v_in**2)
    dP_loss = p_in - p_out
    hL = dP_loss / (rho * fl.g)
    if dP_inth > 0:
        Q_ideal = At * np.sqrt(2 * dP_inth / (rho * (1 - beta**4)))
        Cd = Q / Q_ideal
    else:
        Cd = np.nan
    K_loss = dP_loss / (0.5 * rho * vt_teo**2)
    Umax = float(np.nanmax(res.Umag))

    out = dict(beta=beta, area_ratio=A1 / At, Re_in=Re_in, Re_th=Re_th, Q=Q,
               v1_cfd=v1_cfd, vt_teo=vt_teo, Umax=Umax, dP_bern=dP_bern,
               dP_inth=dP_inth, dP_loss=dP_loss, hL=hL, Cd=Cd, K_loss=K_loss)
    if verbose:
        print("\n================= RESULTS (CFD) =================")
        print(f"beta=Dt/D1 ....................... {beta:.3f}   (A1/At={A1/At:.2f})")
        print(f"Reynolds inlet / throat .......... {Re_in:.0f} / {Re_th:.0f}  (laminar < ~2300)")
        print(f"Flow rate Q (CFD) ................ {Q:.3e} m^3/s = {Q*6e4:.3f} L/min")
        print(f"v_inlet imposed / CFD ............ {v_in:.4f} / {v1_cfd:.4f} m/s")
        print(f"v_throat (continuity) ............ {vt_teo:.4f} m/s")
        print(f"|U|_max (CFD) .................... {Umax:.4f} m/s")
        print(f"dP inlet->throat: Bernoulli / CFD  {dP_bern:.3f} / {dP_inth:.3f} Pa")
        print(f"Net head loss (CFD) .............. {dP_loss:.3f} Pa  ({hL*1000:.3f} mm w.c.)")
        print(f"Discharge coefficient Cd ......... {Cd:.4f}")
        print(f"Loss coefficient K (throat ref.) . {K_loss:.4f}")
        print("===================================================")
    return out


def potential_report(res, verbose=True):
    """Verification report for the potential-flow solution."""
    g = res.geom
    fl = res.fluid_props
    rho, mu = fl.rho, fl.mu
    v_in = res.v_in
    A1, At, beta = g.A1, g.At, g.beta

    Q = v_in * A1
    vt_teo = v_in * (g.R1 / g.Rt) ** 2
    Re_in = rho * v_in * (2 * g.R1) / mu
    Re_th = rho * vt_teo * (2 * g.Rt) / mu
    Umax = float(np.nanmax(res.Umag))
    dP_bern = 0.5 * rho * (vt_teo**2 - v_in**2)
    p_axis = np.where(res.fluid, res.p, np.nan)[:, 0]
    p_min = float(np.nanmin(p_axis))
    hf_tot = float(res.hf[-1])
    dPf_tot = rho * fl.g * hf_tot

    out = dict(beta=beta, area_ratio=A1 / At, Re_in=Re_in, Re_th=Re_th, Q=Q,
               vt_teo=vt_teo, Umax=Umax, dP_bern=dP_bern, p_min=p_min,
               hf_tot=hf_tot, dPf_tot=dPf_tot)
    if verbose:
        print("\n=========== RESULTS (potential flow / FV) ===========")
        print(f"beta=Dt/D1 ....................... {beta:.3f}   (A1/At={A1/At:.2f})")
        print(f"Reynolds inlet / throat .......... {Re_in:.0f} / {Re_th:.0f}  (laminar < ~2300)")
        print(f"Flow rate Q ...................... {Q:.3e} m^3/s = {Q*6e4:.3f} L/min")
        print(f"v_inlet (imposed) ................ {v_in:.4f} m/s")
        print(f"v_throat (continuity) ............ {vt_teo:.4f} m/s")
        print(f"|U|_max (FV, potential) .......... {Umax:.4f} m/s")
        print(f"Drop inlet->throat (Bernoulli) ... {dP_bern:.3f} Pa")
        print(f"Min. pressure at the throat ...... {p_min:.3f} Pa")
        print(f"Total viscous head loss .......... {dPf_tot:.3f} Pa  ({hf_tot*1000:.3f} mm w.c.)")
        print("=====================================================")
        print("Note: potential flow is inviscid (pressure fully recovers in the")
        print("  diffuser). The IRREVERSIBLE loss is estimated by Darcy-Weisbach")
        print("  and/or by the Navier-Stokes solver (ns_projection.py).")
    return out
