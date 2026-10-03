"""Extrai a tabela de correntes do Aspen Plus (planilha BZOH_BASE_CORRENTES.xlsx).

Uso:
    python extrair_dados.py caminho/para/BZOH_BASE_CORRENTES.xlsx

Gera dados/correntes_aspen.csv com as grandezas usadas no dimensionamento
(fase, T, P, vazões, massa específica, massa molar e composição molar).
A planilha original não é versionada; o CSV gerado é a entrada do cálculo.
"""

import csv
import pathlib
import sys

import openpyxl

COMPONENTES = ["AGUA", "HAC", "BZOAC", "BZOH"]


def _rows(ws):
    """Mapa 'rótulo da linha' -> lista de valores (colunas E..) da aba Material."""
    rows, section, comp_block = {}, "MIXED", None
    for row in ws.iter_rows(values_only=True):
        label, unit, vals = row[2], row[3], list(row[4:])
        if label is None:
            continue
        label = str(label).strip()
        if label.endswith("Substream") or (label.endswith(" Phase") and unit is None
                                           and all(v is None for v in vals)):
            section = label.split()[0].upper()   # MIXED, VAPOR, LIQUID, LIQUID1...
            comp_block = None
            continue
        if label in ("Mole Flows", "Mass Flows", "Mole Fractions", "Mass Fractions"):
            comp_block = label
        key = f"{section}|{comp_block}|{label}" if label in COMPONENTES else f"{section}|{label}"
        rows.setdefault(key, vals)
    return rows


def main(path):
    ws = openpyxl.load_workbook(path, data_only=True)["Material"]
    r = _rows(ws)
    names = [str(v) for v in r["MIXED|Stream Name"] if v is not None]
    n = len(names)

    def get(key, i, default=""):
        vals = r.get(key)
        if vals is None or i >= len(vals) or vals[i] is None:
            return default
        return vals[i]

    out = pathlib.Path(__file__).resolve().parent / "dados" / "correntes_aspen.csv"
    cols = (["corrente", "de", "para", "T_C", "P_bar", "frac_vapor_massica",
             "vazao_massica_kg_h", "vazao_molar_kmol_h", "vazao_vol_L_min",
             "rho_mistura_kg_m3", "rho_liquido_kg_m3", "MM_media",
             "vazao_vol_vapor_L_min", "rho_vapor_kg_m3"]
            + [f"x_{c}" for c in COMPONENTES])
    with open(out, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(cols)
        for i in range(n):
            w.writerow([
                names[i], get("MIXED|From", i), get("MIXED|To", i),
                get("MIXED|Temperature", i), get("MIXED|Pressure", i),
                get("MIXED|Mass Vapor Fraction", i, 0.0),
                get("MIXED|Mass Flows", i), get("MIXED|Mole Flows", i),
                get("MIXED|Volume Flow", i),
                float(get("MIXED|Mass Density", i)) * 1000.0,
                float(get("LIQUID|Mass Density", i)) * 1000.0,
                get("MIXED|Average MW", i),
                get("VAPOR|Volume Flow", i, 0.0),
                float(get("VAPOR|Mass Density", i, 0.0) or 0.0) * 1000.0,
            ] + [get(f"MIXED|Mole Fractions|{c}", i) for c in COMPONENTES])
    print(f"{n} correntes gravadas em {out}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "BZOH_BASE_CORRENTES.xlsx")
