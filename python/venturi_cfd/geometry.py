"""Venturi geometry (wall profile R(z)) and fluid properties."""

from dataclasses import dataclass, field

import numpy as np


@dataclass
class Fluid:
    """Working fluid — defaults are water at ~20 C."""

    rho: float = 998.0        # density [kg/m^3]
    mu: float = 1.002e-3      # dynamic viscosity [Pa.s]
    g: float = 9.81           # gravity [m/s^2]

    @property
    def nu(self) -> float:
        """Kinematic viscosity [m^2/s]."""
        return self.mu / self.rho


@dataclass
class VenturiGeometry:
    """Convergent-throat-divergent tube, same dimensions as the MATLAB model.

    The wall radius R(z) is piecewise linear:
    inlet run -> linear convergent -> cylindrical throat -> linear
    divergent (diffuser) -> outlet run.
    """

    R1: float = 0.025         # inlet/outlet radius [m]
    Rt: float = 0.010         # throat radius [m]
    L_in: float = 0.05        # inlet straight section [m]
    L_conv: float = 0.05      # convergent section [m]
    L_th: float = 0.02        # throat length [m]
    L_div: float = 0.10       # divergent (diffuser) section [m]
    L_out: float = 0.08       # outlet straight section [m]

    # section boundaries, filled in __post_init__
    z1: float = field(init=False)
    z2: float = field(init=False)
    z3: float = field(init=False)
    z4: float = field(init=False)
    L: float = field(init=False)

    def __post_init__(self) -> None:
        self.z1 = self.L_in
        self.z2 = self.z1 + self.L_conv
        self.z3 = self.z2 + self.L_th
        self.z4 = self.z3 + self.L_div
        self.L = self.z4 + self.L_out

    def wall_radius(self, z: np.ndarray) -> np.ndarray:
        """Wall radius R(z) [m] for axial position(s) z [m]."""
        z = np.asarray(z, dtype=float)
        R = np.full_like(z, self.R1)
        m = (z >= self.z1) & (z < self.z2)
        R[m] = self.R1 + (self.Rt - self.R1) * (z[m] - self.z1) / (self.z2 - self.z1)
        m = (z >= self.z2) & (z < self.z3)
        R[m] = self.Rt
        m = (z >= self.z3) & (z < self.z4)
        R[m] = self.Rt + (self.R1 - self.Rt) * (z[m] - self.z3) / (self.z4 - self.z3)
        return R

    @property
    def beta(self) -> float:
        """Diameter ratio Dt/D1."""
        return self.Rt / self.R1

    @property
    def A1(self) -> float:
        """Inlet cross-section area [m^2]."""
        return np.pi * self.R1**2

    @property
    def At(self) -> float:
        """Throat cross-section area [m^2]."""
        return np.pi * self.Rt**2
