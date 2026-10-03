"""Physical properties used in the line sizing.

Densities and volumetric flows come straight from the Aspen Plus stream table
(NRTL-HOC). The stream table has no transport properties, so the liquid
viscosity is estimated here:

* water          - Vogel equation;
* benzyl alcohol - Andrade fit through the CRC Handbook values
                   (5.47 mPa s at 25 degC, 2.76 mPa s at 50 degC);
* acetic acid    - Lewis-Squires extrapolation from 1.056 mPa s at 25 degC (CRC);
* benzyl acetate - Lewis-Squires extrapolation from ~2.0 mPa s at 25 degC
                   (estimate; covered by the x0.5 / x2 sensitivity run);
* mixture        - Arrhenius (Grunberg-Nissan with G = 0) mole-fraction rule.

Vapours are treated as ideal gases (P <= 1 atm here).
"""

import numpy as np

R_GAS = 8.314462618          # J/(mol K)
G = 9.80665                  # m/s^2
COMPONENTS = ("AGUA", "HAC", "BZOAC", "BZOH")


def water_viscosity(T_C):
    """Liquid water viscosity [Pa s] - Vogel equation (0-250 degC)."""
    return 2.414e-5 * 10.0 ** (247.8 / (T_C + 273.15 - 140.0))


def water_density(T_C):
    """Liquid water density [kg/m^3], 0-100 degC."""
    return 1000.0 * (1.0 - (T_C + 288.9414) / (508929.2 * (T_C + 68.12963))
                     * (T_C - 3.9863) ** 2)


def lewis_squires(mu_ref_mPas, T_ref_C, T_C):
    """Lewis-Squires: mu^-0.2661 = mu_ref^-0.2661 + (T - T_ref)/233 (mu in mPa s)."""
    val = mu_ref_mPas ** -0.2661 + (T_C - T_ref_C) / 233.0
    return val ** (-1.0 / 0.2661)


def andrade(T_C, A, B):
    """Andrade: ln(mu/mPa s) = A + B/T."""
    return np.exp(A + B / (T_C + 273.15))


# Andrade constants for benzyl alcohol fitted through the two CRC points
_B_BZOH = np.log(5.47 / 2.76) / (1.0 / 298.15 - 1.0 / 323.15)
_A_BZOH = np.log(5.47) - _B_BZOH / 298.15


def pure_viscosity(comp, T_C):
    """Pure-liquid viscosity [Pa s] of a component at T_C."""
    if comp == "AGUA":
        return water_viscosity(T_C)
    if comp == "HAC":
        return lewis_squires(1.056, 25.0, T_C) * 1e-3
    if comp == "BZOAC":
        return lewis_squires(2.0, 25.0, T_C) * 1e-3
    if comp == "BZOH":
        return andrade(T_C, _A_BZOH, _B_BZOH) * 1e-3
    raise KeyError(comp)


def mixture_viscosity(x, T_C, factor=1.0):
    """Liquid mixture viscosity [Pa s]: ln mu = sum x_i ln mu_i.

    x: dict component -> mole fraction (renormalised); factor scales the
    result (sensitivity analysis).
    """
    xs = {c: max(float(x.get(c, 0.0)), 0.0) for c in COMPONENTS}
    tot = sum(xs.values())
    ln_mu = sum(xi / tot * np.log(pure_viscosity(c, T_C))
                for c, xi in xs.items() if xi > 0)
    return factor * np.exp(ln_mu)


def ideal_gas_volume_flow(n_kmol_h, T_C, P_kPa):
    """Volumetric flow [m^3/s] of n kmol/h of ideal gas at T, P."""
    return n_kmol_h / 3600.0 * 1e3 * R_GAS * (T_C + 273.15) / (P_kPa * 1e3)


def ideal_gas_density(MW, T_C, P_kPa):
    """Ideal-gas density [kg/m^3]."""
    return P_kPa * 1e3 * MW * 1e-3 / (R_GAS * (T_C + 273.15))


VAPOR_VISCOSITY = 1.0e-5     # Pa s, typical for the organic/water vapours here


def two_phase_viscosity(x_vap, mu_v, mu_l):
    """McAdams homogeneous two-phase viscosity: 1/mu = x/mu_v + (1-x)/mu_l."""
    return 1.0 / (x_vap / mu_v + (1.0 - x_vap) / mu_l)
