"""Pipe-flow hydraulics and economic-diameter correlations.

Darcy-Weisbach with the Colebrook-White friction factor (Swamee-Jain as the
explicit initial guess), Simpson's self-venting criterion for gravity lines,
the API RP 14E erosional velocity for two-phase lines, elastic buckling of
pipes under vacuum and the classical economic-diameter correlations used as a
cross-check of the economic-velocity method.
"""

import numpy as np

from .properties import G


def swamee_jain(Re, rel_rough):
    """Explicit friction factor (Swamee & Jain, 1976), turbulent flow."""
    return 0.25 / np.log10(rel_rough / 3.7 + 5.74 / Re ** 0.9) ** 2


def friction_factor(Re, rel_rough):
    """Darcy friction factor: 64/Re (laminar) or Colebrook-White (turbulent)."""
    if Re < 2300.0:
        return 64.0 / Re
    f = swamee_jain(Re, rel_rough)
    for _ in range(50):
        f_new = (-2.0 * np.log10(rel_rough / 3.7 + 2.51 / (Re * np.sqrt(f)))) ** -2
        if abs(f_new - f) < 1e-12:
            break
        f = f_new
    return f_new


def pipe_flow(Q, D, rho, mu, eps):
    """Velocity, Reynolds, friction factor and pressure gradient [Pa/m]."""
    A = np.pi * D ** 2 / 4.0
    v = Q / A
    Re = rho * v * D / mu
    f = friction_factor(Re, eps / D)
    dpdl = f / D * rho * v ** 2 / 2.0
    return dict(A=A, v=v, Re=Re, f=f, dpdl=dpdl)




def simpson_froude(Q, D):
    """Froude number of the full-pipe velocity, Fr = v / sqrt(g D) (Simpson, 1968)."""
    v = Q / (np.pi * D ** 2 / 4.0)
    return v / np.sqrt(G * D)


def simpson_min_diameter(Q, Fr_max=0.31):
    """Smallest inside diameter that keeps a gravity drain self-venting."""
    return (4.0 * Q / (np.pi * np.sqrt(G) * Fr_max)) ** 0.4


def economic_diameters(Q, rho):
    """Economic (optimum) inside diameters [m] from classical correlations.

    Q   design volumetric flow [m^3/s];  rho density [kg/m^3]

    * Peters, Timmerhaus & West (2003), turbulent: D = 0.363 Q^0.45 rho^0.13
    * Sinnott (2005), carbon steel : d = 0.293 G^0.53 rho^-0.37
    * Sinnott (2005), stainless    : d = 0.260 G^0.52 rho^-0.37   (G in kg/s)
    """
    Gm = Q * rho
    return {
        'Peters-Timmerhaus': 0.363 * Q ** 0.45 * rho ** 0.13,
        'Sinnott (aço carbono)': 0.293 * Gm ** 0.53 * rho ** -0.37,
        'Sinnott (aço inox)': 0.260 * Gm ** 0.52 * rho ** -0.37,
    }


def erosional_velocity(rho_m, C=100.0):
    """API RP 14E erosional velocity [m/s]: V_e = C / sqrt(rho_m) in US units.

    V_e[ft/s] = C / sqrt(rho_m[lb/ft^3]); C = 100 for continuous service.
    """
    rho_lb = rho_m * 0.062428
    return 0.3048 * C / np.sqrt(rho_lb)


def vacuum_buckling_pressure(OD, wall, E=195e9, nu=0.3):
    """Elastic buckling pressure [Pa] of a long tube: 2E/(1-nu^2) (t/D)^3."""
    return 2.0 * E / (1.0 - nu ** 2) * (wall / OD) ** 3
