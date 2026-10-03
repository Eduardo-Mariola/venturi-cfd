# Dimensionamento das tubulações do P&ID — Planta de álcool benzílico (Área 2)

Cálculo do **diâmetro nominal, schedule e material** de todas as linhas do P&ID da
unidade de hidrólise do acetato de benzila (Projeto Base, 2,37 t/d — Projetos de
Indústrias Químicas I, UNESP), pelo **método da velocidade (vazão) econômica**.

| Entregável | Arquivo |
|---|---|
| Memorial de cálculo (método, premissas, cálculo passo a passo, verificações, referências) | [`memorial_calculo_tubulacoes.md`](memorial_calculo_tubulacoes.md) · [`.docx`](resultados/memorial_calculo_tubulacoes.docx) |
| Lista de linhas para o P&ID (tag, material, NPS, schedule, vazões, velocidades, ΔP) | [`resultados/lista_de_linhas.xlsx`](resultados/lista_de_linhas.xlsx) · [`.csv`](resultados/lista_de_linhas.csv) |
| Figuras | [`resultados/`](resultados/) |

## Escopo

- **34 correntes do PFD** (tabela de correntes do Aspen Plus);
- **30 linhas auxiliares das colunas T-101 a T-105**: vapor de topo, condensado,
  sucção e recalque de refluxo, alimentação e retorno do refervedor;
- **28 linhas de utilidades**: água de resfriamento, vapor (VB/VM/VA) e condensado.

## Método (resumo)

1. Vazão de projeto = 1,30 × normal (cenário +30 % do relatório).
2. Diâmetro econômico pelas heurísticas de Walas (1988) / Turton et al. (2018):
   recalque (5 + D/3) ft/s, sucção (1,3 + D/6) ft/s, gás/vapor 20·D ft/s, com os
   limites de ΔP/100 ft correspondentes.
3. Varredura dos diâmetros comerciais (ASME B36.19M / B36.10M, DN mínimo 3/4") e
   adoção do primeiro que atende a todos os critérios, incluindo ΔP ≤ 1 % de P
   em vácuo, autoventilação de Simpson (Fr ≤ 0,31) e velocidade erosional
   (API RP 14E) nas linhas bifásicas.
4. Verificações: Colebrook/Darcy, espessura (ASME B31.3), flambagem sob vácuo,
   NPSH em sucções saturadas, correlações de diâmetro ótimo (Peters–Timmerhaus,
   Sinnott), comparação com o APEA e análise de sensibilidade.

Classes de material: **S1** inox 316L (processo), **S2** inox 304L (alimentações
limpas), **C1** aço carbono A106 Gr. B Classe 150 (água de resfriamento, vapor de
baixa e média), **C2** aço carbono A106 Gr. B Classe 600 (vapor de alta).

## Como rodar

```bash
pip install -r requirements.txt
python extrair_dados.py caminho/BZOH_BASE_CORRENTES.xlsx   # só se a simulação mudar
python run_dimensionamento.py
```

Para outro cenário (por exemplo, +30 % ou −30 %), basta atualizar os arquivos em
`dados/` (`correntes_aspen.csv`, `colunas.csv`, `resfriadores.csv`,
`utilidades.csv`) e rodar de novo; o memorial e a lista de linhas são regenerados.
Para refinar a alimentação dos refervedores, preencha `MM_vapor_fundo` ou
`L_fundo_kg_h` em `dados/colunas.csv` com o perfil do RadFrac (último estágio).

## Estrutura

```
tubulacoes_bzoh/
├── dados/                 entradas (Aspen, colunas, resfriadores, utilidades)
├── bzoh_pipes/            propriedades, tabelas de tubos, hidráulica, seleção, relatório
├── resultados/            lista de linhas (xlsx/csv), figuras, memorial (.docx)
├── extrair_dados.py       planilha do Aspen → dados/correntes_aspen.csv
├── run_dimensionamento.py executa todo o cálculo
└── memorial_calculo_tubulacoes.md
```
