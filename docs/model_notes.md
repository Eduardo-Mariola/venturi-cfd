# Model notes / Notas do modelo

## Geometry (both solvers)

Convergent-throat-divergent tube, wall radius R(z) piecewise linear:

| Section | Length [m] | Radius [m] |
|---|---|---|
| Inlet run | 0.05 | 0.025 |
| Convergent | 0.05 | 0.025 → 0.010 |
| Throat | 0.02 | 0.010 |
| Divergent (diffuser) | 0.10 | 0.010 → 0.025 |
| Outlet run | 0.08 | 0.025 |

Working fluid: water at ~20 °C (ρ = 998 kg/m³, μ = 1.002·10⁻³ Pa·s).
Inlet velocity: 0.015 m/s → Re ≈ 747 (inlet) / 1868 (throat), laminar.

## Navier-Stokes solver (projection / MAC)

Axisymmetric incompressible momentum equations in (z, r):

- Continuity: ∂u_z/∂z + (1/r) ∂(r u_r)/∂r = 0
- z-momentum: ∂u_z/∂t + u_z ∂u_z/∂z + u_r ∂u_z/∂r
  = −(1/ρ) ∂p/∂z + ν [∂²u_z/∂z² + ∂²u_z/∂r² + (1/r) ∂u_z/∂r]
- r-momentum: ∂u_r/∂t + u_z ∂u_r/∂z + u_r ∂u_r/∂r
  = −(1/ρ) ∂p/∂r + ν [∂²u_r/∂z² + ∂²u_r/∂r² + (1/r) ∂u_r/∂r − u_r/r²]

Fractional-step scheme per time step n:

1. **Predictor** — explicit advection (first-order upwind) and diffusion
   (second-order central, axisymmetric terms included) give u*.
2. **Pressure Poisson** — ∇²p = (ρ/Δt) ∇·u* on fluid cells
   (axisymmetric 5-point stencil; Neumann at walls/axis/inlet, ghost
   Dirichlet p = 0 past the outlet). The sparse operator is LU-factorised
   once outside the time loop.
3. **Correction** — u = u* − (Δt/ρ) ∇p, which enforces ∇·u ≈ 0 to
   machine precision.

Stability: Δt = min(viscous limit 0.05·Δr²/ν, convective CFL 0.4·min(Δz,Δr)/|u|max),
re-evaluated every step. March until steady state (relative change < 10⁻⁴)
or t_final.

## Potential-flow solver

Irrotational approximation u = ∇φ; continuity becomes ∇·(r ∇φ) = 0.

- MATLAB: FEM (PDE Toolbox), coefficient form with c = r.
- Python: conservative finite volumes on the same masked grid
  (face conductances r_c·Δr/Δz and r_f·Δz/Δr; prescribed inlet flux,
  Dirichlet φ = 0 at the outlet, zero flux at wall/axis).

Pressure from Bernoulli: p = ½ρ(v_in² − |u|²) (inlet reference).
Irreversible head loss from laminar Darcy-Weisbach integrated along z:
h_f = ∫ f/D · V²/(2g) dz with f = 64/Re.

## Verification quantities

- Continuity: flow rate Q conserved; throat velocity v_t = v_in (R₁/R_t)².
- Bernoulli: Δp inlet→throat = ½ρ(v_t² − v_in²) = 4.27 Pa.
- Discharge coefficient: C_d = Q / (A_t √(2Δp / ρ(1−β⁴))) ≈ 0.83–0.87.
- Loss coefficient: K = Δp_loss / (½ρv_t²) ≈ 1.2–1.3.
- Net head loss (NS, viscous): ≈ 5–6 Pa (≈ 0.55–0.58 mm w.c.).
