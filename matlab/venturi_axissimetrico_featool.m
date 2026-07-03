%% =======================================================================
%  SIMULACAO DE ESCOAMENTO DE AGUA EM UM TUBO VENTURI (AXISSIMETRICO)
%  Iniciacao Cientifica - Eduardo Mariola Shouga Mendes (UNESP/IQ)
%  Modelagem matematica no controle de emissoes - Lavadores Venturi
%
%  Ferramenta : FEATool Multiphysics (MATLAB) - modo Navier-Stokes
%  Modelo     : Escoamento laminar, incompressivel, estacionario
%               Formulacao AXISSIMETRICA (coordenadas cilindricas r,z)
%  Saidas     : Campos de VELOCIDADE e PRESSAO (PERDA DE CARGA) em
%               gradientes visuais (contornos coloridos) + perfis na linha
%               de centro + verificacao analitica (continuidade/Bernoulli).
%
%  Referencia metodologica:
%   Said Ali, Sheikh Suleimany, Ibrahim (2023). "Numerical Modeling of the
%   Flow around a Cylinder using FEATool Multiphysics", ETASR 13(4),
%   11290-11297. (mesma abordagem: NS 2D laminar resolvido no FEATool).
%
%  COMO EXECUTAR:
%   1) Instale o FEATool Multiphysics e adicione-o ao path do MATLAB
%      (no FEATool: menu  File > Set up Toolbox Paths,  ou  >> featool).
%   2) Coloque este arquivo na pasta de trabalho e rode:  >> venturi_axissimetrico_featool
%   3) As figuras (velocidade, pressao e perfis) sao geradas e salvas em PNG.
%
%  OBS. IMPORTANTE (axissimetria):
%   No FEATool, nomear a dimensao espacial como 'r' ja ativa a
%   formulacao axissimetrica das equacoes de Navier-Stokes. O dominio
%   representa METADE do tubo (de r=0, eixo, ate r=R, parede). O eixo r=0
%   recebe condicao de SIMETRIA; a parede recebe NAO-DESLIZAMENTO.
% =======================================================================

clear fea
close all
clc


%% ----------------------------------------------------------------------
%  1) PROPRIEDADES DO FLUIDO (AGUA a ~20 C) E CONDICAO DE ENTRADA
%  ----------------------------------------------------------------------
rho  = 998;        % densidade da agua [kg/m^3]
mu   = 1.002e-3;   % viscosidade dinamica da agua [Pa.s]
v_in = 0.015;      % velocidade media axial na ENTRADA [m/s]
%   -> velocidade baixa o suficiente para manter o regime LAMINAR mesmo
%      apos a aceleracao na garganta (ver verificacao de Reynolds abaixo).
%      Para estudar vazoes maiores (regime turbulento, tipico de lavadores
%      industriais) use o modo k-epsilon do FEATool.

%% ----------------------------------------------------------------------
%  2) GEOMETRIA DO VENTURI (perfil do raio ao longo do eixo z)
%     Tubo vertical: escoamento de baixo (z=0) para cima (z=L).
%     r e a coordenada radial (horizontal), z a coordenada axial (vertical).
%  ----------------------------------------------------------------------
R1 = 0.025;   % raio da tubulacao de entrada/saida [m]  (D1 = 50 mm)
Rt = 0.010;   % raio da GARGANTA [m]                    (Dt = 20 mm)
%   razao de diametros beta = Dt/D1 = 0.4 ; razao de areas (R1/Rt)^2 = 6.25

L_in   = 0.05;   % trecho reto de entrada            [m]
L_conv = 0.05;   % cone convergente                  [m]  (semi-angulo ~16.7 graus)
L_th   = 0.02;   % garganta                          [m]
L_div  = 0.10;   % cone divergente (difusor)         [m]  (semi-angulo ~8.5 graus)
L_out  = 0.08;   % trecho reto de saida              [m]

% estacoes axiais (acumuladas)
z1 = L_in;                 % fim do trecho reto de entrada
z2 = z1 + L_conv;          % fim do convergente / inicio da garganta
z3 = z2 + L_th;            % fim da garganta / inicio do divergente
z4 = z3 + L_div;           % fim do divergente / inicio do trecho de saida
L  = z4 + L_out;           % comprimento total do dominio

% Poligono que descreve o dominio (vertices em sentido anti-horario,
% interior do dominio sempre a esquerda do percurso). Formato: [r , z].
%   V1 topo do eixo -> desce o eixo -> entrada -> sobe a parede -> topo
p = [ 0   L  ;   % V1 - topo do eixo de simetria
      0   0  ;   % V2 - base do eixo de simetria   (aresta V1-V2 = EIXO r=0)
      R1  0  ;   % V3 - canto da ENTRADA           (aresta V2-V3 = ENTRADA z=0)
      R1  z1 ;   % V4 - fim trecho reto entrada    (parede)
      Rt  z2 ;   % V5 - inicio da garganta         (parede convergente)
      Rt  z3 ;   % V6 - fim da garganta            (parede garganta)
      R1  z4 ;   % V7 - fim do divergente          (parede divergente)
      R1  L  ];  % V8 - canto da SAIDA             (parede reta de saida)
%   aresta V8-V1 (de volta a V1) = SAIDA (z=L)

fea.sdim = { 'r', 'z' };                 % <-- 'r' ativa a AXISSIMETRIA
fea.geom.objects = { gobj_polygon(p) };  % cria o objeto geometrico

%% ----------------------------------------------------------------------
%  3) MALHA (elementos triangulares; refinada o suficiente na garganta)
%  ----------------------------------------------------------------------
hmax = 0.0025;                       % tamanho maximo de elemento [m]
fea.grid = gridgen( fea, 'hmax', hmax );
fprintf('Malha gerada: %d elementos, %d nos.\n', ...
        size(fea.grid.c,2), size(fea.grid.p,2));

% Visualizacao das fronteiras numeradas (CONFIRA antes de prosseguir):
figure('Name','Fronteiras / Malha','Color','w');
subplot(1,2,1); plotbdr(fea); axis equal tight; title('Numeracao das fronteiras');
subplot(1,2,2); plotgrid(fea); axis equal tight; title('Malha');

%% ----------------------------------------------------------------------
%  4) FISICA: Navier-Stokes (incompressivel, laminar)
%  ----------------------------------------------------------------------
fea = addphys( fea, @navierstokes );
fea.phys.ns.eqn.coef{1,end} = { rho };   % densidade  (rho)
fea.phys.ns.eqn.coef{2,end} = { mu  };   % viscosidade (miu)

%% ----------------------------------------------------------------------
%  5) CONDICOES DE CONTORNO
%     Identificadas por COORDENADA (robusto, independe da numeracao):
%       - EIXO     : r = 0          -> Simetria/escorregamento (sel = 4)
%       - ENTRADA  : z = 0          -> Velocidade prescrita     (sel = 2)
%       - SAIDA    : z = L          -> Pressao (saida livre)    (sel = 3)
%       - PAREDES  : demais         -> Nao-deslizamento         (sel = 1)
%  ----------------------------------------------------------------------
n_b = max( fea.grid.b(3,:) );             % numero de fronteiras
fea.phys.ns.bdr.sel = ones(1, n_b);       % padrao = 1 (parede, nao-desliza)

i_eixo   = findbdr( fea, 'r<1e-6' );                       % eixo de simetria
i_in     = findbdr( fea, 'z<1e-6' );                       % entrada
i_out    = findbdr( fea, ['z>', num2str(L-1e-6)] );        % saida

fea.phys.ns.bdr.sel(i_eixo) = 4;   % simetria no eixo (u_r = 0, sem cisalhamento)
fea.phys.ns.bdr.sel(i_in)   = 2;   % entrada de velocidade
fea.phys.ns.bdr.sel(i_out)  = 3;   % saida de pressao (p = 0 de referencia)

% Velocidade prescrita na ENTRADA (escoamento axial, na direcao +z):
%   coef linha 2 = componente radial (u_r) ; linha 3 = componente axial (u_z)
fea.phys.ns.bdr.coef{2,end}{1,i_in} = 0;       % u_r = 0
fea.phys.ns.bdr.coef{3,end}{1,i_in} = v_in;    % u_z = v_in (perfil uniforme)

%% ----------------------------------------------------------------------
%  6) MONTAGEM E SOLUCAO (solver estacionario nao-linear)
%  ----------------------------------------------------------------------
fea = parsephys( fea );
fea = parseprob( fea );
fprintf('\nResolvendo Navier-Stokes (estacionario, laminar)...\n');
fea.sol.u = solvestat( fea, 'fid', 1, 'nlrlx', 0.9, 'maxnit', 50 );

%% ----------------------------------------------------------------------
%  7) POS-PROCESSAMENTO - GRADIENTES VISUAIS
%  ----------------------------------------------------------------------
Umag = 'sqrt(u^2+v^2)';   % modulo da velocidade (u=u_r, v=u_z)

% (a) Campo de VELOCIDADE em gradiente + vetores
figure('Name','Velocidade','Color','w');
postplot( fea, 'surfexpr', Umag, 'isoexpr', Umag, 'arrowexpr', {'u','v'} );
colormap('jet'); colorbar;
axis equal tight; xlabel('r [m]'); ylabel('z [m]');
title('Modulo da velocidade |U| [m/s] - aceleracao na garganta');

% (b) Campo de PRESSAO em gradiente (relacionado a PERDA DE CARGA)
figure('Name','Pressao','Color','w');
postplot( fea, 'surfexpr', 'p', 'isoexpr', 'p' );
colormap('jet'); colorbar;
axis equal tight; xlabel('r [m]'); ylabel('z [m]');
title('Campo de pressao p [Pa] - queda na garganta e recuperacao no difusor');

%% ----------------------------------------------------------------------
%  8) PERFIS NA LINHA DE CENTRO (eixo) - velocidade e pressao vs z
%  ----------------------------------------------------------------------
zc  = linspace(0, L, 400);
pts = [ 1e-4*ones(1,numel(zc)) ; zc ];        % pontos sobre o eixo (r~0)
v_axis = evalexpr( Umag, pts, fea );          % |U| na linha de centro
p_axis = evalexpr( 'p',  pts, fea );          % pressao na linha de centro

figure('Name','Perfis na linha de centro','Color','w');
yyaxis left
plot(zc, v_axis, 'LineWidth', 2); ylabel('|U| [m/s]');
yyaxis right
plot(zc, p_axis, 'LineWidth', 2); ylabel('Pressao [Pa]');
xlabel('z [m] (sentido do escoamento)');
title('Perfis no eixo: velocidade maxima e pressao minima na garganta');
grid on
% marcadores das estacoes (garganta)
xline(z2,'--'); xline(z3,'--');

%% ----------------------------------------------------------------------
%  9) VERIFICACAO ANALITICA (continuidade + Bernoulli) e RELATORIO
%  ----------------------------------------------------------------------
A1 = pi*R1^2;   At = pi*Rt^2;
vt_teo  = v_in * (R1/Rt)^2;                      % continuidade: A1 v1 = At vt
Re_in   = rho * v_in   * (2*R1) / mu;            % Reynolds na entrada
Re_th   = rho * vt_teo * (2*Rt) / mu;            % Reynolds na garganta
dP_bern = 0.5*rho*(vt_teo^2 - v_in^2);           % Bernoulli ideal (entrada->garganta)

% Resultados numericos (campos resolvidos):
Vmax_num = max( evalexpr(Umag, fea.grid.p, fea) );
p_in_num  = mean( evalexpr('p', [linspace(1e-4,R1*0.98,20); zeros(1,20)], fea) );
p_out_num = mean( evalexpr('p', [linspace(1e-4,R1*0.98,20); L*ones(1,20)], fea) );
dP_loss   = p_in_num - p_out_num;                % PERDA DE CARGA liquida [Pa]
hL        = dP_loss / (rho*9.81);                % perda de carga em altura [m]

fprintf('\n================ RESULTADOS ================\n');
fprintf('Razao de areas A1/At ............ %.2f\n', A1/At);
fprintf('Reynolds na entrada ............. %.0f  (laminar se < ~2300)\n', Re_in);
fprintf('Reynolds na garganta ............ %.0f  (laminar se < ~2300)\n', Re_th);
fprintf('--- Velocidade ---\n');
fprintf('v_entrada (imposta) ............. %.4f m/s\n', v_in);
fprintf('v_garganta (continuidade) ....... %.4f m/s\n', vt_teo);
fprintf('|U|_max (CFD) ................... %.4f m/s\n', Vmax_num);
fprintf('--- Pressao / Perda de carga ---\n');
fprintf('Queda ideal (Bernoulli) ......... %.3f Pa\n', dP_bern);
fprintf('Perda de carga liquida (CFD) .... %.3f Pa  (%.4f m de coluna d''agua)\n', dP_loss, hL);
fprintf('============================================\n');

%% ----------------------------------------------------------------------
% 10) SALVAR FIGURAS
%  ----------------------------------------------------------------------
saveas(figure(2),'venturi_velocidade.png');
saveas(figure(3),'venturi_pressao.png');
saveas(figure(4),'venturi_perfis_centro.png');
fprintf('\nFiguras salvas: venturi_velocidade.png, venturi_pressao.png, venturi_perfis_centro.png\n');

% =======================================================================
%  NOTAS / SOLUCAO DE PROBLEMAS
%  - Se a numeracao das fronteiras (figura 1) nao bater com as condicoes,
%    verifique os indices retornados por findbdr (i_eixo, i_in, i_out).
%  - Convergencia lenta: reduza 'nlrlx' (ex. 0.7) e/ou refine a malha
%    (hmax menor, sobretudo na garganta).
%  - Para o tubo COMPLETO na visualizacao, revolva o resultado no GUI do
%    FEATool (Postprocessing) ou espelhe o campo em torno de r=0.
%  - Para vazoes industriais (Re elevado), troque @navierstokes pelo modo
%    de turbulencia k-epsilon do FEATool e refine a malha junto a parede.
% =======================================================================
