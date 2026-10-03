"""Dimensionamento das tubulações do P&ID da planta de álcool benzílico (Área 2).

Uso:
    python run_dimensionamento.py

Lê os dados em dados/, dimensiona todas as linhas pelo método da velocidade
econômica e gera:
    resultados/lista_de_linhas.xlsx   lista de linhas para o P&ID (formatada)
    resultados/lista_de_linhas.csv    mesma lista (separador ';', decimal ',')
    resultados/fig_velocidade_diametro.png, resultados/fig_distribuicao_dn.png
    memorial_calculo_tubulacoes.md    memorial de cálculo completo
    resultados/memorial_calculo_tubulacoes.docx  versão Word (se pypandoc-binary
                                      estiver instalado)
"""

import copy
import pathlib

from bzoh_pipes.figures import plot_dn_distribution, plot_velocity_vs_diameter
from bzoh_pipes.lines import build_line_list
from bzoh_pipes.report import export_docx, write_csv, write_memorial, write_xlsx
from bzoh_pipes.sizing import sensitivity, size_all, size_line

ROOT = pathlib.Path(__file__).resolve().parent
OUT = ROOT / "resultados"

# Streams that need a pump not drawn in the PFD (atmospheric columns, decanter)
PUMPED_WITHOUT_PUMP = ["014", "015", "018", "019", "025", "026", "028", "029"]


def main():
    OUT.mkdir(exist_ok=True)
    lines = build_line_list()
    results = size_all(lines)

    extra = []
    for ln in lines:
        if ln.number in PUMPED_WITHOUT_PUMP:
            s = copy.deepcopy(ln)
            s.number, s.service, s.L_eq = ln.number + "S", "suction", 5.0
            s.description = f"Sucção da bomba da corrente {int(ln.number)}"
            extra.append(size_line(s))

    sens = sensitivity(build_line_list, results)

    write_csv(results, OUT / "lista_de_linhas.csv")
    write_xlsx(results, OUT / "lista_de_linhas.xlsx")
    plot_velocity_vs_diameter(results, OUT / "fig_velocidade_diametro.png")
    plot_dn_distribution(results, OUT / "fig_distribuicao_dn.png")
    memorial = ROOT / "memorial_calculo_tubulacoes.md"
    write_memorial(results, sens, extra, memorial,
                   ["resultados/fig_velocidade_diametro.png",
                    "resultados/fig_distribuicao_dn.png"])
    if not export_docx(memorial, OUT / "memorial_calculo_tubulacoes.docx"):
        print("pypandoc-binary não instalado: versão .docx não gerada.")

    print(f"{len(results)} linhas dimensionadas.")
    for r in results:
        print(f"  {r.tag:24s} {r.line.description[:46]:46s} {r.governing}")
    print(f"\nSaídas em {OUT} e {ROOT / 'memorial_calculo_tubulacoes.md'}")


if __name__ == "__main__":
    main()
