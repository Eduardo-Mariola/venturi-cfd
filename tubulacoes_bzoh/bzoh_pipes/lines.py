"""Line list of the benzyl-alcohol unit (Area 2) built from the project data.

Three groups of lines are generated:

1. PFD process streams 1-34 (Aspen Plus stream table);
2. column auxiliary lines of T-101...T-105 (overhead vapour, condensate,
   reflux-pump suction, reflux, reboiler feed and reboiler vapour return),
   from the RadFrac results (D, R, B, boil-up, T, P);
3. utility lines: cooling water to the condensers/coolers/reactor jacket,
   steam to the reboilers and the corresponding condensate.
"""

import csv
import pathlib
from dataclasses import dataclass, field

from . import properties as pr

DATA = pathlib.Path(__file__).resolve().parents[1] / "dados"

DESIGN_FACTOR = 1.30     # covers the +30 % production scenario of the report
TURNDOWN = 0.70          # -30 % scenario (minimum-velocity checks)
CP_WATER = 4.18          # kJ/(kg K)
CW_T_IN, CW_T_OUT = 25.0, 35.0

# Origin/destination outside the PFD blocks
BATTERY_LIMITS = {"1": ("Limite de bateria", None), "2": ("Limite de bateria", None),
                  "3": ("Área 1", None), "4": ("Limite de bateria", None),
                  "29": (None, "Tancagem"), "34": (None, "Tancagem")}

STREAM_DESC = {
    "1": "Água de processo (alimentação)",
    "2": "Ácido acético glacial (alimentação)",
    "3": "Acetato de benzila (alimentação da Área 1)",
    "4": "Água (alimentação da M-104)",
    "5": "Mistura das alimentações frescas",
    "6": "Alimentação do reator R-101 (com reciclos)",
    "7": "Efluente do reator R-101",
    "8": "Efluente do reator + reciclo orgânico (30)",
    "9": "Efluente resfriado no E-101",
    "10": "Alimentação da T-101 (após redução de pressão)",
    "11": "Destilado da T-101 (água / ácido acético)",
    "12": "Fundo da T-101 (acetato + álcool benzílico)",
    "13": "Alimentação da T-103",
    "14": "Destilado da T-103 (rico em álcool benzílico)",
    "15": "Fundo da T-103 - reciclo de acetato ao reator",
    "16": "Destilado da T-103 + água (bifásico)",
    "17": "Alimentação da T-104 (azeotrópica)",
    "18": "Destilado da T-104 (água + acetato de benzila)",
    "19": "Fundo da T-104 (álcool benzílico bruto)",
    "20": "Fundo da T-104 resfriado no E-102",
    "21": "Alimentação da T-105 (após redução de pressão)",
    "22": "Destilado da T-105 (água + álcool benzílico)",
    "23": "Fundo da T-105 - álcool benzílico 99,9 %",
    "24": "Destilado da T-105 - reciclo à M-105",
    "25": "Fase orgânica do decantador V-101",
    "26": "Fase aquosa do V-101 - reciclo à M-105",
    "27": "Alimentação da T-102 (destilado da T-101)",
    "28": "Destilado da T-102 (água)",
    "29": "Fundo da T-102 - ácido acético subproduto (≈ 90 %)",
    "30": "Fase orgânica - reciclo à M-103",
    "31": "Fase orgânica - à M-106",
    "32": "Reciclo ao reator (M-106 → M-102)",
    "33": "Destilado da T-104 resfriado (E-103) → decantador",
    "34": "Álcool benzílico produto → tancagem",
}

# Service and material class of each PFD stream
SUCTION_VAC = {"11", "12", "22", "23"}
TWO_PHASE = {"6", "16"}
CLEAN_FEEDS = {"1", "3", "4"}          # 304L (S2); everything else 316L (S1)


@dataclass
class Line:
    number: str
    code: str               # fluid code in the tag (P, PV, PM, AR, VB, VM, VA, CD)
    description: str
    origin: str
    destination: str
    phase: str              # 'L', 'V' or 'LV'
    service: str            # key of tables.SERVICES
    spec: str               # key of tables.SPECS
    Q_normal: float         # m^3/s at operating conditions
    T_C: float
    P_kPa: float
    rho: float              # kg/m^3 (mixture density for two-phase lines)
    mu: float               # Pa s
    L_eq: float             # equivalent length [m]
    group: str
    source: str
    x_vap: float = 0.0
    mass_kg_h: float = 0.0
    design_factor: float = DESIGN_FACTOR
    notes: list = field(default_factory=list)

    @property
    def Q_design(self):
        return self.Q_normal * self.design_factor

    @property
    def Q_min(self):
        return self.Q_normal * TURNDOWN


def _kw(q):
    return f"{q:,.1f} kW".replace(",", "X").replace(".", ",").replace("X", ".")


def _read(name):
    with open(DATA / name, encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def load_streams():
    return {r["corrente"]: r for r in _read("correntes_aspen.csv")}


def _x(row):
    return {c: float(row[f"x_{c}"]) for c in pr.COMPONENTS}


def process_lines(streams, mu_factor=1.0):
    lines = []
    for sid, r in streams.items():
        T, P = float(r["T_C"]), float(r["P_bar"]) * 100.0
        m = float(r["vazao_massica_kg_h"])
        xv = float(r["frac_vapor_massica"] or 0.0)
        Q = float(r["vazao_vol_L_min"]) / 60000.0
        mu_l = pr.mixture_viscosity(_x(r), T, mu_factor)
        origin, dest = r["de"] or "", r["para"] or ""
        desc = STREAM_DESC.get(sid, f"Corrente {sid} do PFD")
        if sid in BATTERY_LIMITS:
            o, d = BATTERY_LIMITS[sid]
            origin, dest = o or origin, d or dest
        if sid in TWO_PHASE:
            rho = float(r["rho_mistura_kg_m3"])
            mu = pr.two_phase_viscosity(xv, pr.VAPOR_VISCOSITY, mu_l)
            phase, service, code = "LV", "two_phase", "PM"
        else:
            rho, mu = float(r["rho_liquido_kg_m3"]), mu_l
            phase, code = "L", "P"
            service = "suction_vac" if sid in SUCTION_VAC else "discharge"
        spec = "S2" if sid in CLEAN_FEEDS else "S1"
        lines.append(Line(f"{int(sid):03d}", code, desc, origin, dest, phase,
                          service, spec, Q, T, P, rho, mu, 30.0, "Processo (PFD)",
                          f"Aspen Plus - corrente {sid}", x_vap=xv, mass_kg_h=m))
    return lines


def column_lines(streams, mu_factor=1.0):
    lines = []
    for k, c in enumerate(_read("colunas.csv"), start=1):
        col = c["coluna"]
        P = float(c["P_kPa"])
        Tt, Tb = float(c["T_topo_C"]), float(c["T_fundo_C"])
        D, R, L = float(c["D_kmol_h"]), float(c["R"]), float(c["L_kmol_h"])
        B, Vb = float(c["B_kmol_h"]), float(c["Vboil_kmol_h"])
        sd, sb = streams[c["corrente_destilado"]], streams[c["corrente_fundo"]]
        MWd, MWb = float(sd["MM_media"]), float(sb["MM_media"])
        rhod, rhob = float(sd["rho_liquido_kg_m3"]), float(sb["rho_liquido_kg_m3"])
        mud = pr.mixture_viscosity(_x(sd), Tt, mu_factor)
        mub = pr.mixture_viscosity(_x(sb), Tb, mu_factor)
        vac = P < 50.0
        V = D * (R + 1.0)
        # Liquid to the kettle reboiler = B + boil-up. Without the RadFrac stage
        # profile the boil-up vapour is converted to mass with the bottoms molar
        # mass (conservative); an Aspen value can be given in colunas.csv.
        MWv = float(c.get("MM_vapor_fundo") or MWb)
        m_reb_feed = float(c.get("L_fundo_kg_h") or (B * MWb + Vb * MWv))
        reb_note = ([] if c.get("MM_vapor_fundo") else
                    ["Boil-up convertido em massa com a massa molar do fundo "
                     "(conservador); refinar com o perfil do RadFrac no Aspen."])
        cond, drum, reb = f"Condensador {col}", f"Vaso de refluxo {col}", f"Refervedor {col}"
        src = f"Aspen Plus - RadFrac {col}"
        n = lambda i: f"1{k}{i}"   # noqa: E731

        lines += [
            Line(n(1), "PV", f"Vapor de topo da {col}", f"{col} (topo)", cond, "V",
                 "vapor_vac" if vac else "vapor", "S1",
                 pr.ideal_gas_volume_flow(V, Tt, P), Tt, P,
                 pr.ideal_gas_density(MWd, Tt, P), pr.VAPOR_VISCOSITY, 20.0,
                 "Colunas (auxiliares)", src, mass_kg_h=V * MWd),
            Line(n(2), "P", f"Condensado total da {col}", cond, drum, "L",
                 "gravity", "S1", V * MWd / rhod / 3600.0, Tt, P, rhod, mud, 5.0,
                 "Colunas (auxiliares)", src, mass_kg_h=V * MWd),
            Line(n(3), "P", f"Sucção da bomba de refluxo da {col}", drum,
                 f"Bomba de refluxo {col}", "L", "suction_vac" if vac else "suction",
                 "S1", L * MWd / rhod / 3600.0, Tt, P, rhod, mud, 5.0,
                 "Colunas (auxiliares)", src, mass_kg_h=L * MWd),
            Line(n(4), "P", f"Refluxo da {col}", f"Bomba de refluxo {col}",
                 f"{col} (topo)", "L", "discharge", "S1",
                 L * MWd / rhod / 3600.0, Tt, P, rhod, mud, 25.0,
                 "Colunas (auxiliares)", src, mass_kg_h=L * MWd),
            Line(n(5), "P", f"Alimentação do refervedor da {col}", f"{col} (fundo)",
                 reb, "L", "reboiler_feed", "S1", m_reb_feed / rhob / 3600.0,
                 Tb, P, rhob, mub, 5.0, "Colunas (auxiliares)", src,
                 mass_kg_h=m_reb_feed, notes=list(reb_note)),
            Line(n(6), "PV", f"Retorno de vapor do refervedor da {col}", reb,
                 f"{col} (fundo)", "V", "vapor_vac" if vac else "vapor", "S1",
                 pr.ideal_gas_volume_flow(Vb, Tb, P), Tb, P,
                 pr.ideal_gas_density(MWv, Tb, P), pr.VAPOR_VISCOSITY, 5.0,
                 "Colunas (auxiliares)", src, mass_kg_h=Vb * MWv),
        ]
    return lines


def utility_lines():
    util = {u["codigo"]: u for u in _read("utilidades.csv")}
    lines = []
    users = [(r["equipamento"], r["descricao"], float(r["Q_cal_s"]))
             for r in _read("resfriadores.csv")]
    users += [(f"Condensador {c['coluna']}", f"Condensador de topo da {c['coluna']}",
               float(c["Q_cond_cal_s"])) for c in _read("colunas.csv")]
    num = 201
    for equip, desc, q_cal in users:
        q_kw = abs(q_cal) * 4.184e-3
        m = q_kw / (CP_WATER * (CW_T_OUT - CW_T_IN))        # kg/s
        for kind, T in (("suprimento", CW_T_IN), ("retorno", CW_T_OUT)):
            rho, mu = pr.water_density(T), pr.water_viscosity(T)
            orig, dest = ("Rede de AR", equip) if kind == "suprimento" else (equip, "Rede de AR")
            lines.append(Line(str(num), "AR", f"Água de resfriamento - {kind} - {equip} "
                              f"({_kw(q_kw)})",
                              orig, dest, "L", "cw", "C1", m / rho, T, 400.0, rho, mu,
                              40.0, "Utilidades", "Relatório PIQ I - Tabela 6",
                              mass_kg_h=m * 3600.0))
            num += 1
    for k, c in enumerate(_read("colunas.csv"), start=1):
        u = util[c["utilidade_reb"]]
        q_kw = float(c["Q_reb_cal_s"]) * 4.184e-3
        m = q_kw / float(u["h_fg_kJ_kg"])
        T, P = float(u["T_C"]), float(u["P_kPa_abs"])
        spec = "C2" if c["utilidade_reb"] == "VA" else "C1"
        reb = f"Refervedor {c['coluna']}"
        lines.append(Line(f"30{k}", c["utilidade_reb"],
                          f"{u['descricao'].split(' (')[0]} - {reb} ({_kw(q_kw)})",
                          f"Rede de {c['utilidade_reb']}",
                          reb, "V", "steam", spec, m / float(u["rho_vapor_kg_m3"]), T, P,
                          float(u["rho_vapor_kg_m3"]), float(u["mu_vapor_Pa_s"]), 30.0,
                          "Utilidades", "Relatório PIQ I - Tabela 6", mass_kg_h=m * 3600.0))
        rho_c = float(u["rho_condensado_kg_m3"])
        lines.append(Line(f"40{k}", "CD", f"Condensado de {c['utilidade_reb']} - {reb}",
                          reb, "Purgador / rede de condensado", "L", "condensate", spec,
                          m / rho_c, T, P, rho_c, pr.water_viscosity(T), 10.0,
                          "Utilidades", "Relatório PIQ I - Tabela 6", mass_kg_h=m * 3600.0))
    return lines


def build_line_list(mu_factor=1.0):
    streams = load_streams()
    return (process_lines(streams, mu_factor) + column_lines(streams, mu_factor)
            + utility_lines())
