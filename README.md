# Venturi Tube CFD — Axisymmetric Navier-Stokes in Python & MATLAB

*[Leia em Português](README.pt-BR.md)*

Numerical simulation of incompressible water flow through a **Venturi tube**, developed as part of an Undergraduate Research project (PIBIC) at **UNESP — Chemical Engineering** on **mathematical modeling for atmospheric emission control (Venturi scrubbers)**.

Two independent solvers, implemented **from scratch** (no CFD packages), in **both Python and MATLAB**:

| Solver | Method | Python | MATLAB |
|---|---|---|---|
| **Navier-Stokes** | Projection (fractional-step) on a staggered MAC grid, axisymmetric (r, z) | [`ns_projection.py`](python/venturi_cfd/ns_projection.py) | [`Simulacao_Venturi_Eduardo_Mariola.m`](matlab/Simulacao_Venturi_Eduardo_Mariola.m) |
| **Potential flow** | Finite volumes (Python) / FEM via PDE Toolbox (MATLAB) + Bernoulli + Darcy-Weisbach | [`potential_flow.py`](python/venturi_cfd/potential_flow.py) | [`venturi_pde_toolbox.m`](matlab/venturi_pde_toolbox.m) |
| **Navier-Stokes — parametric (advanced)** | Same projection/MAC core, now fully user-configurable (see below) | — | [`venturi_ns_avancado.m`](matlab/venturi_ns_avancado.m) |
| **Potential flow — parametric (advanced)** | FEM + roughness-aware friction (laminar 64/Re, turbulent Swamee-Jain) | — | [`venturi_pde_avancado.m`](matlab/venturi_pde_avancado.m) |

**Advanced parametric solvers (MATLAB):** an interactive/scriptable layer on top of the base solvers to design a *realistic* Venturi tube. The user specifies (every field has a sensible default): working fluid (water/air/glycerin/SAE30 oil presets or custom ρ, μ), pipe material (PVC, stainless/commercial steel, cast iron, concrete, glass — sets the absolute roughness ε), pipe and throat diameters, total and throat lengths, **convergent/divergent cone angles** (section lengths are derived from them), inlet velocity and inlet profile (developed Poiseuille or plug). The NS version adapts the mesh to resolve the throat, detects the flow regime and — when the throat Reynolds exceeds the laminar range — warns and reports a complementary Darcy-Weisbach/Swamee-Jain turbulent estimate using the material roughness. Extra output: radial velocity profiles showing the boundary layer and no-slip at the wall.

> 📌 Related research **presented orally** at the *EJONS 19th International Congress — Scientific Research and Recent Developments* (IKSAD Institute, Istanbul, June 25–27, 2026) — "Integration of Chemical Engineering and Sustainability: Mathematical Modelling in Emission Control".

---

## 🎯 Overview

The code predicts the **velocity field, pressure field and head loss** of laminar water flow through a convergent-throat-divergent tube, and cross-checks every result against analytical references (continuity, Bernoulli, Reynolds number, discharge coefficient *C<sub>d</sub>*, loss coefficient *K*).

- **Domain:** Chemical / Environmental Engineering (Venturi scrubber hydrodynamics)
- **Stack:** Python (NumPy · SciPy · Matplotlib) and MATLAB (base language — no paid toolboxes needed for the NS solver)
- **Status:** active (2025–present)

## 📐 Mathematical model

**Navier-Stokes solver** — incompressible axisymmetric Navier-Stokes equations in cylindrical coordinates (z, r):

```
∂u/∂t + (u·∇)u = −(1/ρ)∇p + ν∇²u ,   ∇·u = 0
```

- **Discretization:** staggered **MAC grid** (pressure at cell centres, u_z and u_r at faces); the wall r = R(z) is imposed by a fluid-cell mask.
- **Time integration:** explicit predictor (first-order upwind advection + central axisymmetric diffusion) followed by a **pressure-Poisson projection** that enforces continuity at machine precision (|∇·u|ₘₐₓ ≈ 10⁻¹⁴). Adaptive CFL time step, marched to steady state.
- **Boundary conditions:** uniform inlet velocity, pressure outlet, no-slip wall, symmetry at the axis.
- The axisymmetric pressure-Poisson operator is assembled sparse and **LU-factorised once**, so each step costs one triangular solve.

**Potential-flow solver** — for irrotational flow, u = ∇φ and mass conservation becomes:

```
∇·( r ∇φ ) = 0
```

solved by a conservative finite-volume scheme in Python (FEM / PDE Toolbox in MATLAB). Pressure follows from **Bernoulli**; the irreversible head loss is estimated with laminar **Darcy-Weisbach** (f = 64/Re) integrated along the tube.

**Verification (production mesh, water at 20 °C, v_in = 0.015 m/s):**

| Quantity | Analytical | Simulated |
|---|---|---|
| Inlet velocity (continuity) | 0.0150 m/s | 0.0150 m/s |
| Throat velocity (continuity) | 0.0938 m/s | ≈ 0.094–0.109 m/s (profile development) |
| Inlet→throat pressure drop (Bernoulli) | 4.27 Pa | 4.2–5.7 Pa (inviscid vs. viscous) |
| Reynolds (inlet / throat) | 747 / 1868 | laminar regime confirmed |
| Net head loss (NS) | — | ≈ 5–6 Pa, C_d ≈ 0.87 |

## 🗂️ Repository structure

```
.
├── python/
│   ├── venturi_cfd/          # package: geometry, solvers, plots, validation
│   │   ├── geometry.py       # wall profile R(z), fluid properties
│   │   ├── ns_projection.py  # Navier-Stokes (projection / MAC)
│   │   ├── potential_flow.py # potential flow (finite volumes)
│   │   ├── plots.py          # mirrored contour fields, profiles
│   │   └── validation.py     # analytical cross-checks (Re, Cd, K, Bernoulli)
│   └── examples/
│       ├── run_ns_case.py
│       └── run_potential_case.py
├── matlab/                   # original MATLAB implementations
├── results/
│   ├── python/               # figures generated by the Python solvers
│   └── matlab/               # figures generated by the MATLAB solvers
├── docs/                     # model notes and references
├── requirements.txt
└── README.md
```

## ▶️ How to run

**Python** (≥ 3.10):

```bash
pip install -r requirements.txt
cd python/examples
python run_ns_case.py            # Navier-Stokes, production mesh (~1 min)
python run_ns_case.py --quick    # coarse mesh, fast sanity check (~5 s)
python run_potential_case.py     # potential flow (~10 s)
```

**MATLAB** (R2019b or later):

```matlab
cd matlab
Simulacao_Venturi_Eduardo_Mariola        % Navier-Stokes (base MATLAB only)
Simulacao_Venturi_Eduardo_Mariola(true)  % quick coarse-mesh run
venturi_pde_toolbox                      % potential flow (needs PDE Toolbox)

% Advanced parametric solvers:
venturi_ns_avancado                      % interactive input (ENTER = default)
venturi_ns_avancado('padrao')            % run with defaults, no prompts
venturi_ns_avancado('padrao', struct('D_th',0.015,'ang_div',5))  % scripted
venturi_pde_avancado                     % parametric FEM version (PDE Toolbox)
```

Figures are written as PNG to `results/`.

## 📊 Sample results

**Velocity field — acceleration at the throat (streamlines):**

![velocity field](results/python/venturi_cfd_velocity.png)

**Pressure field — drop at the throat, partial recovery in the diffuser:**

![pressure field](results/python/venturi_cfd_pressure.png)

**Axis profiles and head loss:**

| | |
|---|---|
| ![axis profiles](results/python/venturi_cfd_axis_profiles.png) | ![head loss](results/python/venturi_cfd_head_loss.png) |

**Advanced parametric solver — radial velocity profiles (boundary layer / no-slip):**

![radial profiles](results/matlab/venturi_ns_adv_perfis_radiais.png)

## 📚 References

- Chorin, A. J. (1968). *Numerical solution of the Navier-Stokes equations*. Mathematics of Computation, 22, 745–762. (projection method)
- Harlow, F. H.; Welch, J. E. (1965). *Numerical calculation of time-dependent viscous incompressible flow of fluid with free surface*. Physics of Fluids, 8, 2182–2189. (MAC grid)
- Said Ali, A.; Sheikh Suleimany, J.; Ibrahim, R. (2023). *Numerical Modeling of the Flow around a Cylinder using FEATool Multiphysics*. Engineering, Technology & Applied Science Research, 13(4), 11290–11297. (methodological reference)
- White, F. M. *Fluid Mechanics*, McGraw-Hill. (Venturi meters, Darcy-Weisbach, discharge coefficient)

## 👤 Author

**Eduardo Mariola Shouga Mendes** — Chemical Engineering student, UNESP
[LinkedIn](https://www.linkedin.com/in/eduardo-m-456a91220/) · shougamariola@gmail.com

## ⚖️ License & academic note

Released under the [MIT License](LICENSE). This repository is part of ongoing undergraduate research (PIBIC/UNESP); if you build on the model or results, please credit the author and cite the EJONS 19th International Congress (IKSAD Institute, 2026) presentation.
