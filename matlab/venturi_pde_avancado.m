function venturi_pde_avancado(modo, paramsExternos)
%% =======================================================================
%  VENTURI CFD AVANCADO - PDE TOOLBOX (ELEMENTOS FINITOS) - PARAMETRICO
%  Iniciacao Cientifica / Projeto Pessoal
%  Eduardo Mariola Shouga Mendes (UNESP/IQ) - Lavadores Venturi
%
%  AMPLIACAO do modelo "venturi_pde_toolbox.m": agora o usuario descreve
%  um tubo Venturi REALISTA fornecendo geometria, material (rugosidade ->
%  atrito), condicoes de entrada e propriedades do fluido. Ha SEMPRE um
%  valor PADRAO: basta apertar ENTER para aceitar o default de cada campo,
%  ou escolher o modo 'padrao' para nao inserir nada.
%
%  METODO
%   Escoamento potencial axissimetrico resolvido por ELEMENTOS FINITOS com
%   o Partial Differential Equation Toolbox. Para fluido incompressivel e
%   irrotacional a velocidade deriva de um potencial u = grad(phi) e a
%   conservacao de massa em coordenadas cilindricas vira
%        div( r * grad(phi) ) = 0     (forma de coeficientes, c = r)
%   A pressao sai de Bernoulli e a PERDA DE CARGA irreversivel e estimada
%   por Darcy-Weisbach com fator de atrito f dependente de Reynolds e da
%   RUGOSIDADE do material (laminar: 64/Re ; turbulento: Swamee-Jain).
%
%  USO
%   >> venturi_pde_avancado              % modo interativo (pergunta tudo)
%   >> venturi_pde_avancado('padrao')    % roda direto com valores default
%   >> venturi_pde_avancado('padrao', S) % roda com struct S de parametros
%
%  A geometria (comprimentos do convergente e do divergente) e derivada
%  dos ANGULOS de garganta informados, de forma consistente com o
%  comprimento total, diametro do tubo e diametro da garganta.
% =======================================================================

clc; close all;
fprintf('===================================================================\n');
fprintf('  VENTURI CFD AVANCADO  -  PDE Toolbox (Elementos Finitos / FEM)\n');
fprintf('  Escoamento potencial axissimetrico + perda de carga realista\n');
fprintf('===================================================================\n\n');
assert(exist('createpde','file')>0, 'PDE Toolbox nao encontrado no path.');

if nargin<1 || isempty(modo), modo='interativo'; end

%% -----------------------------------------------------------------------
%  1) ENTRADA DE DADOS  (com valores PADRAO em [colchetes])
%  -----------------------------------------------------------------------
if nargin>=2 && ~isempty(paramsExternos)
    P = preencherPadroes(paramsExternos);        % usa struct fornecido
    fprintf('>> Parametros recebidos via struct externo.\n\n');
elseif strcmpi(modo,'padrao')
    P = preencherPadroes(struct());               % tudo default
    fprintf('>> Modo PADRAO: usando todos os valores default.\n\n');
else
    P = lerParametrosInterativo();                % pergunta ao usuario
end

%% -----------------------------------------------------------------------
%  2) PROPRIEDADES DO FLUIDO E DO MATERIAL
%  -----------------------------------------------------------------------
rho = P.rho;  mu = P.mu;  nu = mu/rho;  v_in = P.v_in;  g = 9.81;
eps_abs = P.eps_abs;                              % rugosidade absoluta [m]

%% -----------------------------------------------------------------------
%  3) GEOMETRIA  R(z)  DERIVADA DOS ANGULOS
%  -----------------------------------------------------------------------
R1 = P.D_in/2;                                     % raio do tubo
Rt = P.D_th/2;                                     % raio da garganta
assert(Rt < R1, 'A garganta (D_th) deve ser menor que o tubo (D_in).');

% Comprimentos dos cones a partir dos meio-angulos informados (graus):
%   L_cone = (R1 - Rt) / tan(theta)
thc = deg2rad(P.ang_conv);  thd = deg2rad(P.ang_div);
L_conv = (R1-Rt)/tan(thc);
L_div  = (R1-Rt)/tan(thd);
L_th   = P.L_throat;                               % comprimento da garganta

% Trechos retos de entrada/saida: preenchem o restante do comprimento total.
L_reto = P.L_total - (L_conv + L_th + L_div);
if L_reto < 0
    warning(['Comprimento total insuficiente para os cones+garganta. ' ...
             'Ajustando L_total para acomodar a geometria.']);
    L_in = 0.5*L_conv; L_out = 0.8*L_div;          % minimos razoaveis
else
    L_in  = 0.35*L_reto;                           % 35% antes
    L_out = 0.65*L_reto;                           % 65% depois (difusor longo)
end

z1=L_in; z2=z1+L_conv; z3=z2+L_th; z4=z3+L_div; L=z4+L_out;

% Poligono (z,r) do meio-dominio (anti-horario, interior a esquerda):
xs=[0,  L,  L,  z4, z3, z2, z1, 0 ];
ys=[0,  0,  R1, R1, Rt, Rt, R1, R1];

%% -----------------------------------------------------------------------
%  4) GEOMETRIA E MALHA DE ELEMENTOS FINITOS
%  -----------------------------------------------------------------------
model = createpde(1);
gd=[2; numel(xs); xs(:); ys(:)];
[dl,~]=decsg(gd,'P1',double('P1')');
geometryFromEdges(model,dl);

% Classifica arestas por coordenada (robusto):
tol=1e-7; eIn=[]; eOut=[]; eAxis=[]; eWall=[];
for e=1:size(dl,2)
    x1=dl(2,e); x2=dl(3,e); y1=dl(4,e); y2=dl(5,e);
    if abs(y1)<tol && abs(y2)<tol,           eAxis(end+1)=e; %#ok<AGROW>
    elseif abs(x1)<tol && abs(x2)<tol,       eIn(end+1)=e;   %#ok<AGROW>
    elseif abs(x1-L)<tol && abs(x2-L)<tol,   eOut(end+1)=e;  %#ok<AGROW>
    else,                                    eWall(end+1)=e; %#ok<AGROW>
    end
end

% Tamanho de malha proporcional a garganta (resolve o gargalo):
Hmax = max(Rt/5, L/300);  Hmin = Rt/25;
generateMesh(model,'Hmax',Hmax,'Hmin',Hmin,'GeometricOrder','quadratic');
fprintf('Malha de EF: %d nos, %d elementos (triangulos quadraticos).\n',...
    size(model.Mesh.Nodes,2), size(model.Mesh.Elements,2));

%% -----------------------------------------------------------------------
%  5) COEFICIENTES E CONDICOES DE CONTORNO
%     div( r*grad(phi) ) = 0   ->   c = r = y
%  -----------------------------------------------------------------------
specifyCoefficients(model,'m',0,'d',0,'c',@(loc,st) loc.y,'a',0,'f',0);
applyBoundaryCondition(model,'neumann','Edge',eIn,   'g',@(loc,st) -v_in.*loc.y,'q',0);
applyBoundaryCondition(model,'dirichlet','Edge',eOut,'u',0);
applyBoundaryCondition(model,'neumann','Edge',[eWall eAxis],'g',0,'q',0);

%% -----------------------------------------------------------------------
%  6) SOLUCAO (FEM, estacionaria)
%  -----------------------------------------------------------------------
fprintf('Resolvendo Laplace axissimetrico (potencial)...\n');
Rsol = solvepde(model);

%% -----------------------------------------------------------------------
%  7) VELOCIDADE = grad(phi) E PRESSAO POR BERNOULLI
%  -----------------------------------------------------------------------
nodes=model.Mesh.Nodes;
[uz,ur]=evaluateGradient(Rsol,nodes(1,:),nodes(2,:));
uz=uz(:)'; ur=ur(:)'; Umag=hypot(uz,ur);
p_node = 0.5*rho*(v_in^2 - Umag.^2);

%% -----------------------------------------------------------------------
%  8) CAMPOS EM GRADE + ESPELHAMENTO DO TUBO
%  -----------------------------------------------------------------------
zg=linspace(0,L,460); rg=((1:140)-0.5)/140*R1;
[Zg,Rg]=meshgrid(zg,rg);
[uxg,uyg]=evaluateGradient(Rsol,Zg(:)',Rg(:)');
Uzg=reshape(uxg,size(Zg)); Urg=reshape(uyg,size(Zg));
Umg=hypot(Uzg,Urg);  Pmg=0.5*rho*(v_in^2-Umg.^2);
Rw=venturiR(zg,R1,Rt,z1,z2,z3,z4);

Rf=[ -flipud(Rg) ; Rg ];
Zc=repmat(zg,2*numel(rg),1);
Um=[flipud(Umg); Umg]; Pm=[flipud(Pmg); Pmg];
Uzc=[flipud(Uzg); Uzg]; Urc=[-flipud(Urg); Urg];

% (a) VELOCIDADE
f1=figure('Name','Velocidade (PDE)','Color','w','Position',[60 90 1180 380]);
contourf(Zc,Rf,Um,26,'LineStyle','none'); hold on; axis equal tight;
colormap(gca,jet); cb=colorbar; cb.Label.String='|U| [m/s]';
sy=linspace(-0.9*R1,0.9*R1,16);
set(streamline(Zc,Rf,Uzc,Urc,zeros(size(sy)),sy),'Color',[0 0 0 0.35]);
plot(zg,Rw,'k','LineWidth',1.2); plot(zg,-Rw,'k','LineWidth',1.2);
xlabel('z [m]'); ylabel('r [m]');
title(sprintf('Velocidade |U| - Venturi (D=%.0f mm, garganta=%.0f mm, %s)',...
    P.D_in*1e3, P.D_th*1e3, P.material));

% (b) PRESSAO
f2=figure('Name','Pressao (PDE)','Color','w','Position',[60 90 1180 380]);
contourf(Zc,Rf,Pm,26,'LineStyle','none'); hold on; axis equal tight;
colormap(gca,jet); cb=colorbar; cb.Label.String='p [Pa]';
plot(zg,Rw,'k','LineWidth',1.2); plot(zg,-Rw,'k','LineWidth',1.2);
xlabel('z [m]'); ylabel('r [m]');
title('Pressao de Bernoulli: depressao na garganta');

% (c) MALHA FEM + vetores
f3=figure('Name','Malha FEM e velocidade','Color','w','Position',[100 110 900 420]);
subplot(2,1,1);
pdemesh(model); axis equal tight; title('Malha de elementos finitos (PDE Toolbox)');
xlabel('z [m]'); ylabel('r [m]');
subplot(2,1,2);
pdeplot(model,'XYData',Umag,'FlowData',[uz(:) ur(:)],'ColorMap','jet','Mesh','off');
axis equal tight; title('|U| [m/s] e vetores de velocidade (FEM)');
xlabel('z [m]'); ylabel('r [m]');

% (d) PERFIS NO EIXO
zc=linspace(0,L,400);
[uxe,uye]=evaluateGradient(Rsol, zc, 1e-4*ones(size(zc)));
ueix=hypot(uxe(:)',uye(:)'); peix=0.5*rho*(v_in^2-ueix.^2);
f4=figure('Name','Perfis no eixo (PDE)','Color','w','Position',[120 120 760 460]);
yyaxis left;  plot(zc,ueix,'LineWidth',2); ylabel('|U| no eixo [m/s]');
yyaxis right; plot(zc,peix,'LineWidth',2); ylabel('Pressao (Bernoulli) [Pa]');
xlabel('z [m]'); grid on; xline(z2,'--'); xline(z3,'--');
title('Perfis no eixo: velocidade maxima e pressao minima na garganta');

% (e) PERDA DE CARGA VISCOSA (Darcy-Weisbach com rugosidade do material)
A1=pi*R1^2; Q=v_in*A1;
Rz=venturiR(zc,R1,Rt,z1,z2,z3,z4); Az=pi*Rz.^2; Vz=Q./Az; Dz=2*Rz;
Rez=rho*Vz.*Dz/mu;
fz=fatorAtrito(Rez, eps_abs./Dz);                  % f(Re, rugosidade relativa)
dhf=fz./Dz.*Vz.^2/(2*g);
hf=cumtrapz(zc,dhf);
f5=figure('Name','Perda de carga (PDE)','Color','w','Position',[140 140 760 420]);
plot(zc,hf*1000,'LineWidth',2); grid on; xline(z2,'--'); xline(z3,'--');
xlabel('z [m]'); ylabel('Perda de carga acumulada h_f [mm c.a.]');
title(sprintf('Perda de carga (Darcy-Weisbach) - material: %s (\\epsilon=%.3g mm)',...
    P.material, eps_abs*1e3));

%% -----------------------------------------------------------------------
%  9) VERIFICACAO ANALITICA E RELATORIO
%  -----------------------------------------------------------------------
beta=Rt/R1; At=pi*Rt^2;
vt_teo=v_in*(R1/Rt)^2;
Re_in=rho*v_in*(2*R1)/mu; Re_th=rho*vt_teo*(2*Rt)/mu;
Umax=max(Umag); dP_bern=0.5*rho*(vt_teo^2-v_in^2);
hf_tot=hf(end); dPf_tot=rho*g*hf_tot;
regime = @(Re) ternario(Re<2300,'laminar', ternario(Re<4000,'transicao','turbulento'));

fprintf('\n=============== RESULTADOS (PDE Toolbox / FEM) ===============\n');
fprintf('FLUIDO ... rho=%.1f kg/m^3, mu=%.3e Pa.s, nu=%.3e m^2/s\n',rho,mu,nu);
fprintf('MATERIAL . %s  (rugosidade eps=%.3g mm)\n',P.material,eps_abs*1e3);
fprintf('GEOMETRIA  D_tubo=%.1f mm, D_garganta=%.1f mm, L_total=%.1f mm\n',...
    P.D_in*1e3,P.D_th*1e3,L*1e3);
fprintf('           ang.convergente=%.1f deg, ang.divergente=%.1f deg, L_garganta=%.1f mm\n',...
    P.ang_conv,P.ang_div,L_th*1e3);
fprintf('           L_conv=%.1f mm, L_div=%.1f mm\n',L_conv*1e3,L_div*1e3);
fprintf('-------------------------------------------------------------\n');
fprintf('beta=Dt/D1 ....................... %.3f   (A1/At=%.2f)\n',beta,A1/At);
fprintf('Reynolds entrada ................. %.0f  (%s)\n',Re_in,regime(Re_in));
fprintf('Reynolds garganta ................ %.0f  (%s)\n',Re_th,regime(Re_th));
fprintf('Vazao Q .......................... %.3e m^3/s = %.3f L/min\n',Q,Q*6e4);
fprintf('--- Velocidade ---\n');
fprintf('v_entrada (imposta) .............. %.4f m/s\n',v_in);
fprintf('v_garganta (continuidade) ........ %.4f m/s\n',vt_teo);
fprintf('|U|_max (FEM, potencial) ......... %.4f m/s\n',Umax);
fprintf('--- Pressao / Perda de carga ---\n');
fprintf('Queda ent->garganta (Bernoulli) .. %.3f Pa\n',dP_bern);
fprintf('Pressao minima na garganta (FEM) . %.3f Pa\n',min(peix));
fprintf('Perda de carga irreversivel ...... %.3f Pa  (%.3f mm c.a.)\n',dPf_tot,hf_tot*1000);
fprintf('=============================================================\n');

%% 10) SALVAR FIGURAS
saveas(f1,'venturi_adv_velocidade.png'); saveas(f2,'venturi_adv_pressao.png');
saveas(f3,'venturi_adv_malha_fem.png');  saveas(f4,'venturi_adv_perfis_eixo.png');
saveas(f5,'venturi_adv_perdacarga.png');
fprintf('\nFiguras salvas: venturi_adv_velocidade/pressao/malha_fem/perfis_eixo/perdacarga.png\n');
end

% =======================================================================
%  FUNCOES AUXILIARES
% =======================================================================
function P = lerParametrosInterativo()
% Pergunta cada parametro ao usuario; ENTER aceita o valor padrao.
D = preencherPadroes(struct());        % defaults de referencia
fprintf('--- ENTRADA DE DADOS (aperte ENTER para aceitar o [padrao]) ---\n\n');

% Fluido (menu de presets ou personalizado)
fprintf('Fluido de trabalho:\n');
fprintf('  1) Agua 20 C  (padrao)   rho=998, mu=1.002e-3\n');
fprintf('  2) Ar 20 C               rho=1.204, mu=1.82e-5\n');
fprintf('  3) Glicerina 20 C        rho=1261, mu=1.41\n');
fprintf('  4) Oleo SAE30 20 C       rho=891,  mu=0.29\n');
fprintf('  5) Personalizado (informar rho e mu)\n');
opf = perguntarNum('  Escolha [1]', 1);
switch opf
    case 2, P.rho=1.204; P.mu=1.82e-5;
    case 3, P.rho=1261;  P.mu=1.41;
    case 4, P.rho=891;   P.mu=0.29;
    case 5
        P.rho = perguntarNum('  Densidade rho [kg/m^3]', D.rho);
        P.mu  = perguntarNum('  Viscosidade dinamica mu [Pa.s]', D.mu);
    otherwise, P.rho=998; P.mu=1.002e-3;
end

% Material (rugosidade -> atrito)
fprintf('\nMaterial do tubo (define a rugosidade e o atrito):\n');
fprintf('  1) PVC / plastico liso (padrao)  eps=0.0015 mm\n');
fprintf('  2) Aco inoxidavel                eps=0.015 mm\n');
fprintf('  3) Aco comercial                 eps=0.045 mm\n');
fprintf('  4) Ferro fundido                 eps=0.26 mm\n');
fprintf('  5) Concreto                      eps=1.0 mm\n');
fprintf('  6) Vidro (liso)                  eps=0.0 mm\n');
fprintf('  7) Personalizado (informar eps)\n');
opm = perguntarNum('  Escolha [1]', 1);
[P.material, P.eps_abs] = materialInfo(opm, D);

% Geometria e entrada
fprintf('\nGeometria e condicoes de entrada:\n');
P.D_in     = perguntarNum('  Diametro do tubo D_in [m]', D.D_in);
P.D_th     = perguntarNum('  Diametro da garganta D_th [m]', D.D_th);
P.L_total  = perguntarNum('  Comprimento total do tubo L_total [m]', D.L_total);
P.L_throat = perguntarNum('  Comprimento da garganta L_throat [m]', D.L_throat);
P.ang_conv = perguntarNum('  Angulo do cone convergente [graus]', D.ang_conv);
P.ang_div  = perguntarNum('  Angulo do cone divergente [graus]', D.ang_div);
P.v_in     = perguntarNum('  Velocidade de entrada v_in [m/s]', D.v_in);

P = preencherPadroes(P);               % garante todos os campos
fprintf('\n');
end

% -----------------------------------------------------------------------
function P = preencherPadroes(P)
% Completa os campos faltantes com os valores PADRAO (agua + PVC).
d.rho=998; d.mu=1.002e-3; d.v_in=0.015;
d.D_in=0.050; d.D_th=0.020; d.L_total=0.30; d.L_throat=0.02;
d.ang_conv=21; d.ang_div=7; d.material='PVC/plastico liso'; d.eps_abs=1.5e-6;
f=fieldnames(d);
for k=1:numel(f)
    if ~isfield(P,f{k}) || isempty(P.(f{k})), P.(f{k})=d.(f{k}); end
end
end

% -----------------------------------------------------------------------
function [nome, eps] = materialInfo(op, D)
switch op
    case 2, nome='Aco inoxidavel'; eps=0.015e-3;
    case 3, nome='Aco comercial';  eps=0.045e-3;
    case 4, nome='Ferro fundido';  eps=0.26e-3;
    case 5, nome='Concreto';       eps=1.0e-3;
    case 6, nome='Vidro (liso)';   eps=0.0;
    case 7
        eps = perguntarNum('  Rugosidade absoluta eps [mm]', D.eps_abs*1e3)*1e-3;
        nome='Personalizado';
    otherwise, nome='PVC/plastico liso'; eps=0.0015e-3;
end
end

% -----------------------------------------------------------------------
function v = perguntarNum(txt, padrao)
% Le um numero; ENTER (vazio) devolve o valor padrao.
resp = input(sprintf('%s [%g]: ', txt, padrao));
if isempty(resp) || ~isnumeric(resp), v = padrao; else, v = resp(1); end
end

% -----------------------------------------------------------------------
function f = fatorAtrito(Re, epsRel)
% Fator de atrito de Darcy. Laminar: 64/Re. Turbulento: Swamee-Jain
% (aproximacao explicita da equacao de Colebrook-White).
Re = max(Re, 1e-6);
f_lam = 64./Re;
f_turb = 0.25 ./ (log10(epsRel/3.7 + 5.74./Re.^0.9)).^2;
lam = Re < 2300;
f = f_turb;
f(lam) = f_lam(lam);
end

% -----------------------------------------------------------------------
function R=venturiR(z,R1,Rt,z1,z2,z3,z4)
% Perfil do raio da parede: reto - convergente - garganta - divergente - reto
R=R1*ones(size(z));
m1=z>=z1&z<z2; R(m1)=R1+(Rt-R1).*(z(m1)-z1)./(z2-z1);
m2=z>=z2&z<z3; R(m2)=Rt;
m3=z>=z3&z<z4; R(m3)=Rt+(R1-Rt).*(z(m3)-z3)./(z4-z3);
end

% -----------------------------------------------------------------------
function out = ternario(cond, a, b)
if cond, out=a; else, out=b; end
end
