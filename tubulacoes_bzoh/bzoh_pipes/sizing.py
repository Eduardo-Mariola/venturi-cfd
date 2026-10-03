"""Economic-velocity line sizing with hydraulic and mechanical verification.

For every line:
1. design flow Q_d = 1.3 Q_n (+30 % scenario); minimum flow 0.7 Q_n;
2. economic diameter D_ec solving Q_d = (pi/4) D^2 v_ec(D), with the
   Walas/Turton economic velocity of the service (or Simpson's diameter for
   gravity lines, or the API RP 14E erosional limit for two-phase lines);
3. commercial sizes of the piping class are scanned from the smallest
   (DN >= DN_min = 3/4") and the first one meeting every criterion is taken:
     - v_d <= v_ec(ID) and dP/L <= economic limit (Walas/Turton);
     - absolute velocity cap; vacuum lines: line dP <= 1 % of P_abs;
     - gravity lines: Fr <= 0.31; two-phase: v_d <= V_erosional;
4. verification: Re, f (Colebrook), dP, wall thickness (ASME B31.3),
   buckling under vacuum, static head for NPSH on saturated suctions.
"""

from dataclasses import dataclass, field

import numpy as np
from scipy.optimize import brentq

from . import hydraulics as hy
from .properties import G
from .tables import SERVICES, SPECS, economic_velocity

NPSH_REQUIRED = 2.0      # m, small centrifugal pumps (pre-selection)
NPSH_MARGIN = 1.0        # m
FR_MAX = 0.31            # Simpson self-venting limit
MILL_TOL = 0.125


@dataclass
class Candidate:
    size: object
    v_d: float
    v_n: float
    v_min: float
    Re: float
    f: float
    dpdl: float
    v_ec: float = float('nan')
    fails: list = field(default_factory=list)


@dataclass
class Result:
    line: object
    spec: object
    service: object
    D_ec: float
    candidates: list
    chosen: Candidate
    governing: str
    notes: list
    dP_line: float
    econ_diameters: dict
    wall: dict = None
    z_min: float = None

    @property
    def tag(self):
        return f'{self.chosen.size.label}-{self.line.code}-{self.line.number}-{self.spec.code}'


def _economic_diameter(line, svc):
    Qd = line.Q_design
    if svc.rule in ('discharge', 'suction', 'gas'):
        return brentq(lambda D: np.pi / 4 * D ** 2 * economic_velocity(svc.rule, D) - Qd,
                      1e-5, 3.0)
    if svc.rule == 'simpson':
        return hy.simpson_min_diameter(Qd, FR_MAX)
    if svc.rule == 'two_phase':
        return np.sqrt(4 * Qd / (np.pi * hy.erosional_velocity(line.rho)))
    return float('nan')


def _evaluate(line, spec, svc, size):
    fl = hy.pipe_flow(line.Q_design, size.ID, line.rho, line.mu, spec.roughness)
    A = fl['A']
    c = Candidate(size, fl['v'], line.Q_normal / A, line.Q_min / A, fl['Re'],
                  fl['f'], fl['dpdl'])
    if svc.rule in ('discharge', 'suction', 'gas'):
        c.v_ec = economic_velocity(svc.rule, size.ID)
        if c.v_d > c.v_ec:
            c.fails.append('velocidade econômica')
    if svc.dp_limit is not None and c.dpdl > svc.dp_limit:
        c.fails.append('perda de carga por 100 m')
    if svc.v_cap is not None and c.v_d > svc.v_cap:
        c.fails.append('velocidade máxima')
    if svc.dp_frac_P is not None and c.dpdl * line.L_eq > svc.dp_frac_P * line.P_kPa * 1e3:
        c.fails.append('ΔP admissível em vácuo')
    if svc.rule == 'simpson' and hy.simpson_froude(line.Q_design, size.ID) > FR_MAX:
        c.fails.append('autoventilação (Fr > 0,31)')
    if svc.rule == 'two_phase' and c.v_d > hy.erosional_velocity(line.rho):
        c.fails.append('velocidade erosional (API RP 14E)')
    return c


GOVERNING = {
    'velocidade econômica': 'Velocidade econômica',
    'perda de carga por 100 m': 'Perda de carga econômica (ΔP/100 m)',
    'velocidade máxima': 'Velocidade máxima admissível',
    'ΔP admissível em vácuo': 'ΔP admissível em vácuo (1 % de P)',
    'autoventilação (Fr > 0,31)': 'Autoventilação (Simpson, Fr ≤ 0,31)',
    'velocidade erosional (API RP 14E)': 'Velocidade erosional (API RP 14E)',
}


def wall_check(spec, size, P_abs_kPa):
    """ASME B31.3 eq. (3a) internal pressure + elastic buckling under vacuum."""
    P = spec.P_design
    t_p = P * size.OD / (2.0 * (spec.allowable_S * spec.weld_E + 0.4 * P))
    t_min = (t_p + spec.corrosion_c) / (1.0 - MILL_TOL)
    out = dict(P_design=P, t_pressure=t_p, t_min=t_min, t_nom=size.wall,
               ok=size.wall >= t_min)
    if P_abs_kPa < 100.0:
        p_cr = hy.vacuum_buckling_pressure(size.OD, size.wall * (1 - MILL_TOL))
        out.update(P_cr=p_cr, vac_ok=p_cr / 3.0 >= 101325.0)
        out['ok'] = out['ok'] and out['vac_ok']
    return out


def size_line(line):
    spec, svc = SPECS[line.spec], SERVICES[line.service]
    sizes = [s for s in spec.sizes if s.preferred and s.DN >= spec.DN_min]
    D_ec = _economic_diameter(line, svc)
    cands = [_evaluate(line, spec, svc, s) for s in sizes]
    ok = [c for c in cands if not c.fails]
    notes = list(line.notes)
    if ok:
        chosen = ok[0]
        i = cands.index(chosen)
        if i == 0:
            governing = ('DN mínimo da especificação (3/4")' if D_ec <= chosen.size.ID
                         else GOVERNING.get('velocidade econômica'))
            if svc.rule == 'simpson' and D_ec <= chosen.size.ID:
                governing = 'DN mínimo da especificação (3/4")'
        else:
            governing = GOVERNING[cands[i - 1].fails[0]]
    else:
        chosen = cands[-1]
        governing = 'NENHUM DIÂMETRO ATENDE - revisar'
        notes.append('; '.join(chosen.fails))

    if svc.rule == 'two_phase' and chosen.v_min < 3.0:
        notes.append(f'Bifásico: v = {chosen.v_min:.1f} m/s na vazão mínima (< 3 m/s, '
                     'API RP 14E) - risco de golfadas; manter trecho curto e '
                     'com caimento contínuo.')
    if chosen.Re < 2300:
        notes.append(f'Escoamento laminar (Re = {chosen.Re:.0f}).')

    dP_line = chosen.dpdl * line.L_eq
    z_min = None
    if line.service in ('suction', 'suction_vac', 'reboiler_feed'):
        # saturated liquid: NPSHa = z - h_f - entrance loss
        h_f = dP_line / (line.rho * G) + 0.5 * chosen.v_d ** 2 / (2 * G)
        z_min = NPSH_REQUIRED + NPSH_MARGIN + h_f if line.service != 'reboiler_feed' else None

    wall = wall_check(spec, chosen.size, line.P_kPa)
    if not wall['ok']:
        notes.append('Espessura insuficiente - aumentar schedule.')
    econ = hy.economic_diameters(line.Q_design, line.rho)
    return Result(line, spec, svc, D_ec, cands, chosen, governing, notes, dP_line,
                  econ, wall, z_min)


def size_all(lines):
    return [size_line(ln) for ln in lines]


def sensitivity(build, base):
    """DN changes against the base case for a few perturbed premises.

    build(mu_factor) -> line list; base: list of base-case Results.
    """
    from .tables import SERVICES as SV
    base_dn = {r.line.number: r.chosen.size.label for r in base}

    def diff(results):
        return [(r.line.number, base_dn[r.line.number], r.chosen.size.label)
                for r in results if r.chosen.size.label != base_dn[r.line.number]]

    cases = []
    for f in (0.5, 2.0):
        cases.append((f'Viscosidade dos líquidos × {f:g}'.replace('.', ','),
                      diff(size_all(build(f)))))
    lines = build(1.0)
    for ln in lines:
        ln.design_factor = 1.0
    cases.append(('Sem fator de projeto (vazão normal)', diff(size_all(lines))))
    orig = SV['vapor_vac'].dp_frac_P
    for frac in (0.005, 0.02):
        SV['vapor_vac'].dp_frac_P = frac
        cases.append((f'ΔP admissível em vácuo = {frac * 100:g} % de P'.replace('.', ','),
                      diff(size_all(build(1.0)))))
    SV['vapor_vac'].dp_frac_P = orig
    return cases


def nearest_preferred(spec_code, D):
    """Smallest preferred commercial size of a class with ID >= D."""
    for s in SPECS[spec_code].sizes:
        if s.preferred and s.ID >= D:
            return s
    return SPECS[spec_code].sizes[-1]
