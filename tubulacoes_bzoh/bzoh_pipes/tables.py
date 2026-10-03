"""Commercial pipe dimensions, material classes (specs) and sizing criteria."""

from dataclasses import dataclass, field

FT = 0.3048                      # m
INCH = 0.0254                    # m
PSI_100FT = 6894.757 / (100 * FT)   # 1 psi/100 ft in Pa/m (= 0.2262 kPa/m)

# NPS -> (DN, OD mm, wall Sch 10S, wall Sch 40S)       ASME B36.19M
B3619 = {
    '1/2"': (15, 21.34, 2.11, 2.77), '3/4"': (20, 26.67, 2.11, 2.87),
    '1"': (25, 33.40, 2.77, 3.38), '1.1/4"': (32, 42.16, 2.77, 3.56),
    '1.1/2"': (40, 48.26, 2.77, 3.68), '2"': (50, 60.33, 2.77, 3.91),
    '2.1/2"': (65, 73.03, 3.05, 5.16), '3"': (80, 88.90, 3.05, 5.49),
    '3.1/2"': (90, 101.60, 3.05, 5.74), '4"': (100, 114.30, 3.05, 6.02),
    '5"': (125, 141.30, 3.40, 6.55), '6"': (150, 168.28, 3.40, 7.11),
    '8"': (200, 219.08, 3.76, 8.18), '10"': (250, 273.05, 4.19, 9.27),
    '12"': (300, 323.85, 4.57, 9.53), '14"': (350, 355.60, 4.78, 9.53),
    '16"': (400, 406.40, 4.78, 9.53), '18"': (450, 457.20, 4.78, 9.53),
    '20"': (500, 508.00, 5.54, 9.53), '24"': (600, 609.60, 6.35, 9.53),
}
# NPS -> (DN, OD mm, wall Sch 40, wall Sch 80)          ASME B36.10M
B3610 = {
    '1/2"': (15, 21.3, 2.77, 3.73), '3/4"': (20, 26.7, 2.87, 3.91),
    '1"': (25, 33.4, 3.38, 4.55), '1.1/4"': (32, 42.2, 3.56, 4.85),
    '1.1/2"': (40, 48.3, 3.68, 5.08), '2"': (50, 60.3, 3.91, 5.54),
    '2.1/2"': (65, 73.0, 5.16, 7.01), '3"': (80, 88.9, 5.49, 7.62),
    '3.1/2"': (90, 101.6, 5.74, 8.08), '4"': (100, 114.3, 6.02, 8.56),
    '5"': (125, 141.3, 6.55, 9.53), '6"': (150, 168.3, 7.11, 10.97),
    '8"': (200, 219.1, 8.18, 12.70), '10"': (250, 273.0, 9.27, 15.09),
    '12"': (300, 323.8, 10.31, 17.48), '14"': (350, 355.6, 11.13, 19.05),
    '16"': (400, 406.4, 12.70, 21.44), '18"': (450, 457.2, 14.27, 23.83),
    '20"': (500, 508.0, 15.09, 26.19), '24"': (600, 609.6, 17.48, 30.96),
}
# Rarely stocked sizes - avoided (Silva Telles)
NON_PREFERRED = {'1.1/4"', '3.1/2"', '5"'}


@dataclass
class Size:
    label: str
    DN: int
    OD: float        # m
    wall: float      # m
    ID: float        # m
    schedule: str
    preferred: bool = True


@dataclass
class Spec:
    """Piping class used in the line tag (e.g. 3/4"-P-011-S1)."""
    code: str
    material: str
    pipe_std: str
    schedules: str
    rating: str
    service: str
    roughness: float         # m
    allowable_S: float       # Pa, ASME B31.3 basic allowable stress (conservative)
    weld_E: float
    corrosion_c: float       # m
    P_design: float          # Pa (gauge)
    sizes: list = field(default_factory=list)
    DN_min: int = 20


def _stainless():
    out = []
    for lab, (dn, od, w10, w40) in B3619.items():
        sch, w = ('Sch 40S', w40) if dn <= 40 else ('Sch 10S', w10)
        out.append(Size(lab, dn, od / 1e3, w / 1e3, (od - 2 * w) / 1e3, sch,
                        lab not in NON_PREFERRED))
    return out


def _carbon():
    out = []
    for lab, (dn, od, w40, w80) in B3610.items():
        sch, w = ('Sch 80', w80) if dn <= 40 else ('Sch 40', w40)
        out.append(Size(lab, dn, od / 1e3, w / 1e3, (od - 2 * w) / 1e3, sch,
                        lab not in NON_PREFERRED))
    return out


SPECS = {
    'S1': Spec('S1', 'Aço inoxidável AISI 316L', 'ASTM A312 TP316L (com/sem costura)',
               'ASME B36.19M - Sch 40S até 1.1/2"; Sch 10S a partir de 2"',
               'Flanges ASME B16.5 Classe 150 RF (A182 F316L)',
               'Linhas de processo com ácido acético / meio hidrolítico',
               roughness=0.015e-3, allowable_S=100e6, weld_E=0.85,
               corrosion_c=0.0, P_design=10e5, sizes=_stainless()),
    'S2': Spec('S2', 'Aço inoxidável AISI 304L', 'ASTM A312 TP304L (com/sem costura)',
               'ASME B36.19M - Sch 40S até 1.1/2"; Sch 10S a partir de 2"',
               'Flanges ASME B16.5 Classe 150 RF (A182 F304L)',
               'Alimentações limpas a 25 °C (água de processo, acetato de benzila)',
               roughness=0.015e-3, allowable_S=100e6, weld_E=0.85,
               corrosion_c=0.0, P_design=10e5, sizes=_stainless()),
    'C1': Spec('C1', 'Aço carbono ASTM A106 Gr. B', 'ASTM A106 Gr. B sem costura',
               'ASME B36.10M - Sch 80 até 1.1/2"; Sch 40 a partir de 2"',
               'Flanges ASME B16.5 Classe 150 RF (A105)',
               'Água de resfriamento; vapor e condensado de baixa e média pressão',
               roughness=0.045e-3, allowable_S=130e6, weld_E=1.0,
               corrosion_c=1.5e-3, P_design=10e5, sizes=_carbon()),
    'C2': Spec('C2', 'Aço carbono ASTM A106 Gr. B', 'ASTM A106 Gr. B sem costura',
               'ASME B36.10M - Sch 80 até 1.1/2"; Sch 40 a partir de 2"',
               'Flanges ASME B16.5 Classe 600 RF (A105)',
               'Vapor e condensado de alta pressão (~40 bar a)',
               roughness=0.045e-3, allowable_S=130e6, weld_E=1.0,
               corrosion_c=1.5e-3, P_design=45e5, sizes=_carbon()),
}


@dataclass
class Service:
    """Sizing criteria of a service.

    rule: 'discharge' -> v_ec = (5 + D/3) ft/s, dP <= 2.0 psi/100 ft
          'suction'   -> v_ec = (1.3 + D/6) ft/s, dP <= 0.4 psi/100 ft
          'gas'       -> v_ec = 20 D ft/s,     dP <= 0.5 psi/100 ft
          (Walas, 1988; Turton et al., 2018 - D = inside diameter in inches)
          'simpson'   -> self-venting gravity line, Fr <= 0.31
          'two_phase' -> API RP 14E erosional velocity, dP <= 2.0 psi/100 ft
    """
    key: str
    label: str
    rule: str
    dp_limit: float = None          # Pa/m
    v_cap: float = None             # m/s absolute cap
    dp_frac_P: float = None         # max line dP as fraction of P_abs (vacuum)


SERVICES = {
    'discharge': Service('discharge', 'Líquido - recalque / linha pressurizada',
                         'discharge', dp_limit=2.0 * PSI_100FT, v_cap=3.0),
    'suction': Service('suction', 'Líquido - sucção de bomba', 'suction',
                       dp_limit=0.4 * PSI_100FT),
    'suction_vac': Service('suction_vac',
                           'Líquido saturado - sucção de bomba de coluna a vácuo',
                           'suction', dp_limit=0.4 * PSI_100FT),
    'reboiler_feed': Service('reboiler_feed',
                             'Líquido saturado - fundo da coluna → refervedor',
                             'suction', dp_limit=0.4 * PSI_100FT),
    'gravity': Service('gravity', 'Condensado por gravidade → vaso de refluxo',
                       'simpson'),
    'vapor': Service('vapor', 'Vapor de processo (≈ 1 atm)', 'gas',
                     dp_limit=0.5 * PSI_100FT, v_cap=40.0),
    'vapor_vac': Service('vapor_vac', 'Vapor de processo em vácuo', 'gas',
                         v_cap=60.0, dp_frac_P=0.01),
    'two_phase': Service('two_phase', 'Bifásico líquido-vapor', 'two_phase',
                         dp_limit=2.0 * PSI_100FT),
    'cw': Service('cw', 'Água de resfriamento (suprimento/retorno)', 'discharge',
                  dp_limit=2.0 * PSI_100FT, v_cap=3.0),
    'steam': Service('steam', 'Vapor d\'água saturado', 'gas',
                     dp_limit=0.5 * PSI_100FT, v_cap=40.0),
    'condensate': Service('condensate', 'Condensado saturado (antes do purgador)',
                          'suction', dp_limit=0.4 * PSI_100FT),
}


def economic_velocity(rule, ID):
    """Walas/Turton economic velocity [m/s] for inside diameter ID [m]."""
    D_in = ID / INCH
    if rule == 'discharge':
        return (5.0 + D_in / 3.0) * FT
    if rule == 'suction':
        return (1.3 + D_in / 6.0) * FT
    if rule == 'gas':
        return 20.0 * D_in * FT
    return None
