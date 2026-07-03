"""Incompressible axisymmetric Navier-Stokes solver (projection method).

Direct port of ``Simulacao_Venturi_Eduardo_Mariola.m``:

* cylindrical coordinates (z, r) with axial symmetry;
* staggered MAC grid — pressure at cell centres, u_z at z-faces,
  u_r at r-faces;
* fractional-step (Chorin projection): explicit predictor with upwind
  advection + central axisymmetric diffusion, then a pressure-Poisson
  correction enforcing continuity;
* the venturi wall r = R(z) is imposed by a fluid-cell mask;
* time marching with adaptive CFL step until steady state.

Boundary conditions: uniform axial velocity at the inlet, pressure
outlet (ghost p = 0), no-slip wall, symmetry at the axis r = 0.
"""

import time
from dataclasses import dataclass

import numpy as np
import scipy.sparse as sp
from scipy.sparse.linalg import splu

from .geometry import Fluid, VenturiGeometry


@dataclass
class NSResult:
    """Fields and mesh info returned by :func:`solve_ns` (steady state)."""

    geom: VenturiGeometry
    fluid_props: Fluid
    v_in: float
    zc: np.ndarray          # (Nz,)   cell-centre axial coordinates
    rc: np.ndarray          # (Nr,)   cell-centre radial coordinates
    Rw: np.ndarray          # (Nz,)   wall radius per column
    fluid: np.ndarray       # (Nz,Nr) fluid-cell mask
    u: np.ndarray           # (Nz+1,Nr) axial velocity at z-faces
    v: np.ndarray           # (Nz,Nr+1) radial velocity at r-faces
    p: np.ndarray           # (Nz,Nr) pressure at cell centres
    uc: np.ndarray          # (Nz,Nr) axial velocity at centres
    vc: np.ndarray          # (Nz,Nr) radial velocity at centres
    Umag: np.ndarray        # (Nz,Nr) velocity magnitude (NaN outside fluid)
    dz: float
    dr: float
    steps: int
    cpu_s: float


def _build_poisson(fluid, Nz, Nr, dz, dr, rc):
    """Sparse axisymmetric pressure-Poisson operator on fluid cells.

    Homogeneous Neumann at walls/axis/inlet (missing-neighbour terms are
    simply dropped) and Dirichlet ghost p = 0 past the outlet.
    """
    idmap = -np.ones((Nz, Nr), dtype=np.int64)
    idmap[fluid] = np.arange(np.count_nonzero(fluid))
    az = 1.0 / dz**2
    rows, cols, vals = [], [], []
    for i in range(Nz):
        for j in range(Nr):
            if not fluid[i, j]:
                continue
            n = idmap[i, j]
            arP = 1.0 / dr**2 + 1.0 / (2.0 * dr * rc[j])
            arM = 1.0 / dr**2 - 1.0 / (2.0 * dr * rc[j])
            d = 0.0
            if i > 0 and fluid[i - 1, j]:
                rows.append(n); cols.append(idmap[i - 1, j]); vals.append(az)
                d -= az
            if i < Nz - 1 and fluid[i + 1, j]:
                rows.append(n); cols.append(idmap[i + 1, j]); vals.append(az)
                d -= az
            elif i == Nz - 1:               # outlet: ghost cell with p = 0
                d -= az
            if j < Nr - 1 and fluid[i, j + 1]:
                rows.append(n); cols.append(idmap[i, j + 1]); vals.append(arP)
                d -= arP
            if j > 0 and fluid[i, j - 1]:
                rows.append(n); cols.append(idmap[i, j - 1]); vals.append(arM)
                d -= arM
            rows.append(n); cols.append(n); vals.append(d)
    N = np.count_nonzero(fluid)
    A = sp.csc_matrix((vals, (rows, cols)), shape=(N, N))
    return splu(A)


def solve_ns(quick=False, v_in=0.015, geom=None, fluid_props=None,
             verbose=True) -> NSResult:
    """March the axisymmetric Navier-Stokes equations to steady state.

    Parameters
    ----------
    quick : bool
        ``True`` runs a coarse mesh (fast sanity check); ``False`` runs the
        production mesh used for the report figures.
    v_in : float
        Uniform inlet axial velocity [m/s].
    geom, fluid_props :
        Override the default :class:`VenturiGeometry` / :class:`Fluid`.
    """
    geom = geom or VenturiGeometry()
    fl = fluid_props or Fluid()
    rho, nu = fl.rho, fl.nu
    R1, Rt, L = geom.R1, geom.Rt, geom.L

    log = print if verbose else (lambda *a, **k: None)
    log("=== Venturi CFD - axisymmetric NS, projection on a MAC grid ===")

    # ---- MAC mesh (z, r): p at centres; u_z at z-faces; u_r at r-faces ----
    if quick:
        Nz, Nr, Tfinal = 160, 34, 6.0
    else:
        Nz, Nr, Tfinal = 300, 60, 9.0
    dz, dr = L / Nz, R1 / Nr
    zc = (np.arange(Nz) + 0.5) * dz
    rc = (np.arange(Nr) + 0.5) * dr
    rf = np.arange(Nr + 1) * dr                    # r-faces (rf[0] = axis)
    Rw = geom.wall_radius(zc)
    fluid = rc[None, :] < Rw[:, None]              # fluid cell if rc < R(z)
    inletcol = fluid[0, :]

    # active faces (True between two fluid cells; False = wall)
    activeU = np.zeros((Nz + 1, Nr), dtype=bool)
    activeU[1:Nz, :] = fluid[:-1, :] & fluid[1:, :]
    activeU[0, :] = inletcol                       # inlet
    activeU[Nz, :] = fluid[-1, :]                  # outlet
    activeV = np.zeros((Nz, Nr + 1), dtype=bool)
    activeV[:, 1:Nr] = fluid[:, :-1] & fluid[:, 1:]
    log(f"MAC mesh {Nz}x{Nr} ({np.count_nonzero(fluid)} fluid cells).  "
        f"dz={dz:.2g}  dr={dr:.2g}")

    # ---- pressure operator (compact axisymmetric Poisson), factorised once
    lu = _build_poisson(fluid, Nz, Nr, dz, dr, rc)

    # ---- time step (explicit stability; convective limit re-evaluated) ----
    umax = v_in * (R1 / Rt) ** 2
    dt_visc = 0.20 * 0.25 * dr**2 / nu             # viscous limit (fixed)
    dt = min(dt_visc, 0.20 * min(dz, dr) / umax)   # initial convective CFL
    nsteps = int(np.ceil(Tfinal / dt)) * 3         # generous cap (stops at steady state)
    log(f"dt0={dt:.3g} s  dt_visc={dt_visc:.3g} s  (t_final~{Tfinal:.1f} s)")

    # ---- time marching (projection) ----
    u = np.zeros((Nz + 1, Nr))
    v = np.zeros((Nz, Nr + 1))
    p = np.zeros((Nz, Nr))
    u[0, inletcol] = v_in
    RC = rc[None, :]
    RFa = rf[1:][None, :]
    RFb = rf[:-1][None, :]

    log("Solving...")
    t0 = time.perf_counter()
    uold = u.copy()
    tcur = 0.0
    report_every = max(1, round(nsteps / 12))
    n_done = 0
    for n in range(nsteps):
        # adaptive time step (convective CFL + viscous limit)
        smax = max(np.abs(u).max(), np.abs(v).max())
        dt = min(dt_visc, 0.40 * min(dz, dr) / max(smax, umax))
        tcur += dt
        if tcur > Tfinal:
            break
        n_done = n + 1

        # --- predictor (upwind advection + central axisymmetric diffusion)
        us, vs = u.copy(), v.copy()

        # u_z momentum (interior z-faces i = 1..Nz-1)
        uRpad = np.hstack([u[:, :1], u, np.zeros((Nz + 1, 1))])  # axis mirror; wall 0
        d2uz = (u[2:Nz + 1] - 2 * u[1:Nz] + u[0:Nz - 1]) / dz**2
        d2ur = (uRpad[1:Nz, 2:] - 2 * uRpad[1:Nz, 1:-1] + uRpad[1:Nz, :-2]) / dr**2
        durdr = (uRpad[1:Nz, 2:] - uRpad[1:Nz, :-2]) / (2 * dr)
        diffU = nu * (d2uz + d2ur + durdr / RC)
        uP = u[1:Nz]
        duz_b = (uP - u[0:Nz - 1]) / dz
        duz_f = (u[2:Nz + 1] - uP) / dz
        duz = np.where(uP > 0, duz_b, duz_f)
        uS, uN, uC = uRpad[1:Nz, :-2], uRpad[1:Nz, 2:], uRpad[1:Nz, 1:-1]
        dur_b = (uC - uS) / dr
        dur_f = (uN - uC) / dr
        vbar = 0.25 * (v[0:Nz - 1, 0:Nr] + v[1:Nz, 0:Nr]
                       + v[0:Nz - 1, 1:Nr + 1] + v[1:Nz, 1:Nr + 1])
        dur = np.where(vbar > 0, dur_b, dur_f)
        us[1:Nz] = uP + dt * (-(uP * duz + vbar * dur) + diffU)

        # u_r momentum (interior r-faces j = 1..Nr-1)
        vZpad = np.vstack([v[:1], v, v[-1:]])      # inlet/outlet: dv/dz = 0
        d2vz = (vZpad[2:, 1:Nr] - 2 * v[:, 1:Nr] + vZpad[:-2, 1:Nr]) / dz**2
        d2vr = (v[:, 2:Nr + 1] - 2 * v[:, 1:Nr] + v[:, 0:Nr - 1]) / dr**2
        dvrdr = (v[:, 2:Nr + 1] - v[:, 0:Nr - 1]) / (2 * dr)
        rfV = rf[1:Nr][None, :]
        diffV = nu * (d2vz + d2vr + dvrdr / rfV - v[:, 1:Nr] / rfV**2)
        vP = v[:, 1:Nr]
        ubar = 0.25 * (u[0:Nz, 0:Nr - 1] + u[0:Nz, 1:Nr]
                       + u[1:Nz + 1, 0:Nr - 1] + u[1:Nz + 1, 1:Nr])
        dvz_b = (vP - vZpad[:-2, 1:Nr]) / dz
        dvz_f = (vZpad[2:, 1:Nr] - vP) / dz
        dvz = np.where(ubar > 0, dvz_b, dvz_f)
        dvr_b = (vP - v[:, 0:Nr - 1]) / dr
        dvr_f = (v[:, 2:Nr + 1] - vP) / dr
        dvr = np.where(vP > 0, dvr_b, dvr_f)
        vs[:, 1:Nr] = vP + dt * (-(ubar * dvz + vP * dvr) + diffV)

        # --- BCs on the predictor field
        us *= activeU
        us[0, inletcol] = v_in
        us[Nz, :] = us[Nz - 1, :] * activeU[Nz, :]  # outlet: du/dz = 0 estimate
        vs *= activeV                               # axis (j=0) and wall already 0

        # --- axisymmetric divergence of (us, vs)
        D = ((us[1:Nz + 1] - us[0:Nz]) / dz
             + (RFa * vs[:, 1:] - RFb * vs[:, :-1]) / (RC * dr))
        D[~fluid] = 0.0

        # --- Poisson:  Lap(p) = (rho/dt) D
        pv = lu.solve((rho / dt) * D[fluid])
        p[:] = 0.0
        p[fluid] = pv

        # --- correction
        u, v = us.copy(), vs.copy()
        u[1:Nz] = us[1:Nz] - dt / rho * (p[1:Nz] - p[0:Nz - 1]) / dz
        v[:, 1:Nr] = vs[:, 1:Nr] - dt / rho * (p[:, 1:Nr] - p[:, 0:Nr - 1]) / dr
        u[Nz] = us[Nz] + dt / rho * p[Nz - 1] / dz  # pressure outlet (ghost p = 0)

        # --- final BCs
        u *= activeU
        u[0, inletcol] = v_in
        v *= activeV
        if not np.all(np.isfinite(u)):
            raise FloatingPointError(
                f"Diverged (NaN/Inf) at step {n + 1}. Reduce the CFL number.")

        if (n + 1) % report_every == 0 or n == 0:
            Dc = ((u[1:Nz + 1] - u[0:Nz]) / dz
                  + (RFa * v[:, 1:] - RFb * v[:, :-1]) / (RC * dr))
            chg = np.abs(u - uold).max() / max(v_in, 1e-9)
            log(f"  step {n + 1:6d}/{nsteps}  |div|max={np.abs(Dc[fluid]).max():.2e}"
                f"  Umax={np.abs(u).max():.4f}  d(u)/Uin={chg:.2e}")
            if chg < 1e-4 and n > 50:
                log("  -> steady state reached.")
                break
            uold = u.copy()

    cpu = time.perf_counter() - t0
    log(f"Done in {cpu:.1f} s of CPU time.")

    # ---- cell-centred fields ----
    uc = 0.5 * (u[:-1] + u[1:])
    vc = 0.5 * (v[:, :-1] + v[:, 1:])
    Umag = np.hypot(uc, vc)
    Umag[~fluid] = np.nan

    return NSResult(geom=geom, fluid_props=fl, v_in=v_in, zc=zc, rc=rc, Rw=Rw,
                    fluid=fluid, u=u, v=v, p=p, uc=uc, vc=vc, Umag=Umag,
                    dz=dz, dr=dr, steps=n_done, cpu_s=cpu)
