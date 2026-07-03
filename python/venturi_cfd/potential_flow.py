"""Axisymmetric potential-flow solver (finite volumes).

Python counterpart of ``venturi_pde_toolbox.m``. The MATLAB version solves
the axisymmetric potential-flow equation with the PDE Toolbox (FEM); here
the same equation is discretised by a conservative finite-volume scheme on
the masked cell-centred grid, removing any proprietary dependency.

For incompressible, irrotational flow the velocity derives from a
potential, u = grad(phi), and mass conservation in cylindrical
coordinates (axisymmetry) becomes

    div( r * grad(phi) ) = 0

Boundary conditions: prescribed normal velocity at the inlet (Neumann),
reference potential phi = 0 at the outlet (Dirichlet), impermeable wall
and symmetry axis (zero flux).

The pressure follows from Bernoulli and the *irreversible* head loss is
estimated separately with laminar Darcy-Weisbach along the tube, exactly
as in the MATLAB script.
"""

from dataclasses import dataclass

import numpy as np
import scipy.sparse as sp
from scipy.integrate import cumulative_trapezoid
from scipy.sparse.linalg import spsolve

from .geometry import Fluid, VenturiGeometry


@dataclass
class PotentialResult:
    """Fields returned by :func:`solve_potential`."""

    geom: VenturiGeometry
    fluid_props: Fluid
    v_in: float
    zc: np.ndarray          # (Nz,)   cell-centre axial coordinates
    rc: np.ndarray          # (Nr,)   cell-centre radial coordinates
    Rw: np.ndarray          # (Nz,)   wall radius per column
    fluid: np.ndarray       # (Nz,Nr) fluid-cell mask
    phi: np.ndarray         # (Nz,Nr) velocity potential (NaN outside)
    uc: np.ndarray          # (Nz,Nr) axial velocity at centres
    vc: np.ndarray          # (Nz,Nr) radial velocity at centres
    Umag: np.ndarray        # (Nz,Nr) velocity magnitude (NaN outside fluid)
    p: np.ndarray           # (Nz,Nr) Bernoulli pressure (ref. inlet)
    hf: np.ndarray          # (Nz,)   cumulative Darcy-Weisbach head loss [m]
    dz: float
    dr: float


def solve_potential(Nz=420, Nr=130, v_in=0.015, geom=None, fluid_props=None,
                    verbose=True) -> PotentialResult:
    """Solve div(r grad phi) = 0 on the venturi and post-process the flow."""
    geom = geom or VenturiGeometry()
    fl = fluid_props or Fluid()
    rho, mu, g = fl.rho, fl.mu, fl.g
    R1, L = geom.R1, geom.L

    log = print if verbose else (lambda *a, **k: None)
    log("=== Venturi - axisymmetric potential flow (finite volumes) ===")

    # ---- cell-centred grid with fluid mask (same layout as the NS solver)
    dz, dr = L / Nz, R1 / Nr
    zc = (np.arange(Nz) + 0.5) * dz
    rc = (np.arange(Nr) + 0.5) * dr
    rf = np.arange(Nr + 1) * dr
    Rw = geom.wall_radius(zc)
    fluid = rc[None, :] < Rw[:, None]
    N = np.count_nonzero(fluid)
    log(f"FV grid {Nz}x{Nr} ({N} fluid cells).  dz={dz:.2g}  dr={dr:.2g}")

    idmap = -np.ones((Nz, Nr), dtype=np.int64)
    idmap[fluid] = np.arange(N)

    # ---- assemble  sum_faces A_f (phi_nb - phi_P)/d = b  per unit radian --
    # z-face area / dz -> rc[j]*dr/dz ;  r-face area / dr -> rf[j]*dz/dr
    rows, cols, vals = [], [], []
    b = np.zeros(N)
    gz = dr / dz
    gr = dz / dr
    for i in range(Nz):
        for j in range(Nr):
            if not fluid[i, j]:
                continue
            n = idmap[i, j]
            d = 0.0
            if i > 0 and fluid[i - 1, j]:              # west face
                c = rc[j] * gz
                rows.append(n); cols.append(idmap[i - 1, j]); vals.append(c)
                d -= c
            elif i == 0:                               # inlet: u_z = v_in
                b[n] -= v_in * rc[j] * dr
            if i < Nz - 1 and fluid[i + 1, j]:         # east face
                c = rc[j] * gz
                rows.append(n); cols.append(idmap[i + 1, j]); vals.append(c)
                d -= c
            elif i == Nz - 1:                          # outlet: phi = 0 (ghost)
                d -= rc[j] * gz
            if j < Nr - 1 and fluid[i, j + 1]:         # north face
                c = rf[j + 1] * gr
                rows.append(n); cols.append(idmap[i, j + 1]); vals.append(c)
                d -= c
            if j > 0 and fluid[i, j - 1]:              # south face
                c = rf[j] * gr
                rows.append(n); cols.append(idmap[i, j - 1]); vals.append(c)
                d -= c
            rows.append(n); cols.append(n); vals.append(d)
            # wall and axis faces: zero flux -> no contribution

    A = sp.csc_matrix((vals, (rows, cols)), shape=(N, N))
    log("Solving the axisymmetric Laplace problem (potential)...")
    phi_v = spsolve(A, b)
    phi = np.full((Nz, Nr), np.nan)
    phi[fluid] = phi_v

    # ---- velocities from face differences of phi (MAC-like), then centred
    phi0 = np.where(fluid, phi, 0.0)
    uf = np.zeros((Nz + 1, Nr))                        # u_z at z-faces
    act = fluid[:-1, :] & fluid[1:, :]
    uf[1:Nz][act] = (phi0[1:][act] - phi0[:-1][act]) / dz
    uf[0, fluid[0, :]] = v_in                          # inlet face
    uf[Nz, fluid[-1, :]] = -2.0 * phi0[-1, fluid[-1, :]] / dz  # outlet (phi=0 at face)
    vf = np.zeros((Nz, Nr + 1))                        # u_r at r-faces
    actv = fluid[:, :-1] & fluid[:, 1:]
    vf[:, 1:Nr][actv] = (phi0[:, 1:][actv] - phi0[:, :-1][actv]) / dr

    uc = 0.5 * (uf[:-1] + uf[1:])
    vc = 0.5 * (vf[:, :-1] + vf[:, 1:])
    Umag = np.hypot(uc, vc)
    Umag[~fluid] = np.nan

    # ---- Bernoulli pressure (reference: inlet) ----
    p = 0.5 * rho * (v_in**2 - Umag**2)

    # ---- viscous head loss (laminar Darcy-Weisbach) along the tube ----
    Q = v_in * geom.A1
    Az = np.pi * Rw**2
    Vz = Q / Az
    Dz = 2.0 * Rw
    Rez = rho * Vz * Dz / mu
    fz = 64.0 / Rez                                    # laminar friction factor
    dhf = fz / Dz * Vz**2 / (2.0 * g)                  # dh_f/dz
    hf = cumulative_trapezoid(dhf, zc, initial=0.0)    # cumulative loss [m]

    return PotentialResult(geom=geom, fluid_props=fl, v_in=v_in, zc=zc, rc=rc,
                           Rw=Rw, fluid=fluid, phi=phi, uc=uc, vc=vc,
                           Umag=Umag, p=p, hf=hf, dz=dz, dr=dr)
