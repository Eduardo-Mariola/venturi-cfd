"""
venturi_cfd — Axisymmetric CFD of water flow in a Venturi tube.

Python port of the MATLAB solvers developed for the undergraduate research
project (PIBIC/UNESP) "Mathematical modelling in emission control —
Venturi scrubbers", by Eduardo Mariola Shouga Mendes.

Modules
-------
geometry        Venturi wall profile and fluid/mesh parameters.
ns_projection   Incompressible axisymmetric Navier-Stokes solver
                (projection / fractional-step method on a staggered MAC grid).
potential_flow  Axisymmetric potential-flow solver (finite volumes) with
                Bernoulli pressure and Darcy-Weisbach head-loss estimate.
plots           Publication-style figures (mirrored contour fields, profiles).
validation      Analytical cross-checks (continuity, Bernoulli, Re, Cd, K).
"""

from .geometry import VenturiGeometry, Fluid
from .ns_projection import solve_ns
from .potential_flow import solve_potential

__version__ = "1.0.0"
__author__ = "Eduardo Mariola Shouga Mendes"

__all__ = ["VenturiGeometry", "Fluid", "solve_ns", "solve_potential"]
