function venturi_pde_toolbox
%% =======================================================================
%  ESCOAMENTO DE AGUA EM TUBO VENTURI - PDE TOOLBOX (ELEMENTOS FINITOS)
%  Iniciacao Cientifica - Eduardo Mariola Shouga Mendes (UNESP/IQ)
%  Modelagem matematica no controle de emissoes - Lavadores Venturi
%
%  Metodo : ESCOAMENTO POTENCIAL AXISSIMETRICO resolvido por ELEMENTOS
%           FINITOS com o Partial Differential Equation Toolbox.
%
%  Por que escoamento potencial?
%   O PDE Toolbox resolve EDPs na forma de coeficientes
%        -div(c*grad(u)) + a*u = f
%   (eliptica/parabolica/hiperbolica). Ele NAO possui um solver acoplado
%   de Navier-Stokes (pressao-velocidade). Para fluido incompressivel e
%   irrotacional, a velocidade deriva de um POTENCIAL  u = grad(phi), e a
%   conservacao de massa em coordenadas cilindricas (axissimetria) vira
%        div( r * grad(phi) ) = 0      <-- forma de coeficientes com c = r
%   resolvida exatamente pelo PDE Toolbox. A pressao sai de BERNOULLI e a
%   PERDA DE CARGA viscosa e estimada por Darcy-Weisbach ao longo do tubo.
%
%  Referencia metodologica:
%   "MATLAB code for potential flow around a ..." (pasta da IC) e
%   Said Ali et al. (2023), "Numerical Modeling of the Flow around a
%   Cylinder using FEATool Multiphysics", ETASR 13(4) (estilo de
%   apresentacao: Reynolds, contornos de velocidade/pressao, perfis).
%
%  Saidas : campos de VELOCIDADE e PRESSAO em gradientes visuais (tubo
%           espelhado) + malha de EF + perfis no eixo + curva de perda de
%           carga acumulada + relatorio com verificacao analitica.
%
%  USO:  >> venturi_pde_toolbox
% =======================================================================

clc; close all;
fprintf('=== Venturi - Escoamento potencial axissimetrico (PDE Toolbox / FEM) ===\n');
assert(exist('createpde','file')>0, 'PDE Toolbox nao encontrado no path.');

%% 1) FLUIDO (AGUA ~20 C) E ENTRADA
rho=998; mu=1.002e-3; nu=mu/rho; v_in=0.015; g=9.81;

%% 2) GEOMETRIA  R(z)  (mesmas cotas dos modelos anteriores)
R1=0.025; Rt=0.010;
L_in=0.05; L_conv=0.05; L_th=0.02; L_div=0.10; L_out=0.08;
z1=L_in; z2=z1+L_conv; z3=z2+L_th; z4=z3+L_div; L=z4+L_out;

% Poligono (z,r) do meio-dominio, sentido anti-horario (interior a esquerda):
%   eixo (r=0) -> saida (z=L) -> parede (perfil do venturi) -> entrada (z=0)
xs=[0,  L,  L,  z4, z3, z2, z1, 0 ];     % z dos vertices
ys=[0,  0,  R1, R1, Rt, Rt, R1, R1];     % r dos vertices

%% 3) GEOMETRIA E MALHA DE ELEMENTOS FINITOS (PDE Toolbox)
model = createpde(1);
gd=[2; numel(xs); xs(:); ys(:)];          % '2' = poligono (formato decsg)
[dl,~]=decsg(gd,'P1',double('P1')');      % geometria decomposta
geometryFromEdges(model,dl);

% Identifica as arestas por coordenada (robusto, independe da numeracao)
tol=1e-7; eIn=[]; eOut=[]; eAxis=[]; eWall=[];
for e=1:size(dl,2)
    x1=dl(2,e); x2=dl(3,e); y1=dl(4,e); y2=dl(5,e);
    if abs(y1)<tol && abs(y2)<tol,             eAxis(end+1)=e;  %#ok<AGROW> eixo r=0
    elseif abs(x1)<tol && abs(x2)<tol,         eIn(end+1)=e;    %#ok<AGROW> entrada z=0
    elseif abs(x1-L)<tol && abs(x2-L)<tol,     eOut(end+1)=e;   %#ok<AGROW> saida z=L
    else,                                      eWall(end+1)=e;  %#ok<AGROW> parede
    end
end
fprintf('Arestas -> entrada:%s  saida:%s  eixo:%s  parede:%s\n',...
    mat2str(eIn),mat2str(eOut),mat2str(eAxis),mat2str(eWall));

generateMesh(model,'Hmax',0.0020,'Hmin',4e-4,'GeometricOrder','quadratic');
fprintf('Malha de EF: %d nos, %d elementos (triangulos quadraticos).\n',...
    size(model.Mesh.Nodes,2), size(model.Mesh.Elements,2));

%% 4) COEFICIENTES:  div( r*grad(phi) ) = 0   ->  c = r = y
specifyCoefficients(model,'m',0,'d',0,'c',@(loc,st) loc.y,'a',0,'f',0);

%% 5) CONDICOES DE CONTORNO
%   Entrada (z=0): Neumann  n.(c grad phi) = c*u_n = -v_in*r   (u_z=+v_in)
%   Saida   (z=L): Dirichlet phi=0 (potencial de referencia)
%   Parede e eixo: Neumann g=0 (impenetrabilidade / simetria)
applyBoundaryCondition(model,'neumann','Edge',eIn,  'g',@(loc,st) -v_in.*loc.y,'q',0);
applyBoundaryCondition(model,'dirichlet','Edge',eOut,'u',0);
applyBoundaryCondition(model,'neumann','Edge',[eWall eAxis],'g',0,'q',0);

%% 6) SOLUCAO (FEM, estacionaria, linear)
fprintf('Resolvendo Laplace axissimetrico (potencial)...\n');
R = solvepde(model);

%% 7) VELOCIDADE = grad(phi) NOS NOS  E  PRESSAO POR BERNOULLI
nodes=model.Mesh.Nodes;
[uz,ur]=evaluateGradient(R,nodes(1,:),nodes(2,:));     % u_z=dphi/dz , u_r=dphi/dr
uz=uz(:)'; ur=ur(:)'; Umag=hypot(uz,ur);
p_node = 0.5*rho*(v_in^2 - Umag.^2);                   % Bernoulli (ref. entrada)

%% 8) CAMPOS EM GRADE ESTRUTURADA (para contornos + espelhamento do tubo)
zg=linspace(0,L,420); rg=((1:130)-0.5)/130*R1;   % r>0 (evita eixo duplicado no espelho)
[Zg,Rg]=meshgrid(zg,rg);
[uxg,uyg]=evaluateGradient(R,Zg(:)',Rg(:)');           % NaN fora do dominio
Uzg=reshape(uxg,size(Zg)); Urg=reshape(uyg,size(Zg));
Umg=hypot(Uzg,Urg);  Pmg=0.5*rho*(v_in^2-Umg.^2);
Rw=venturiR(zg,R1,Rt,z1,z2,z3,z4);

% espelhamento em torno do eixo r=0
rfull=[-fliplr(rg) rg];
Zc=repmat(zg,2*numel(rg),1); Rf=[ -flipud(Rg) ; Rg ];
Um=[flipud(Umg); Umg]; Pm=[flipud(Pmg); Pmg];
Uzc=[flipud(Uzg); Uzg]; Urc=[-flipud(Urg); Urg];

% (a) VELOCIDADE - gradiente + linhas de corrente
f1=figure('Name','Velocidade (PDE)','Color','w','Position',[60 90 1180 380]);
contourf(Zc,Rf,Um,26,'LineStyle','none'); hold on; axis equal tight;
colormap(gca,jet); cb=colorbar; cb.Label.String='|U| [m/s]';
sy=linspace(-0.9*R1,0.9*R1,16);
set(streamline(Zc,Rf,Uzc,Urc,zeros(size(sy)),sy),'Color',[0 0 0 0.35]);
plot(zg,Rw,'k','LineWidth',1.2); plot(zg,-Rw,'k','LineWidth',1.2);
xlabel('z [m] (sentido do escoamento)'); ylabel('r [m]');
title('PDE Toolbox - Velocidade |U|: aceleracao na garganta (linhas de corrente)');

% (b) PRESSAO (Bernoulli) - gradiente
f2=figure('Name','Pressao (PDE)','Color','w','Position',[60 90 1180 380]);
contourf(Zc,Rf,Pm,26,'LineStyle','none'); hold on; axis equal tight;
colormap(gca,jet); cb=colorbar; cb.Label.String='p [Pa]';
plot(zg,Rw,'k','LineWidth',1.2); plot(zg,-Rw,'k','LineWidth',1.2);
xlabel('z [m]'); ylabel('r [m]');
title('PDE Toolbox - Pressao de Bernoulli: depressao na garganta');

% (c) MALHA DE EF + campo de velocidade (visao nativa do PDE Toolbox)
f3=figure('Name','Malha FEM e velocidade','Color','w','Position',[100 110 900 420]);
subplot(2,1,1);
pdemesh(model); axis equal tight; title('Malha de elementos finitos (PDE Toolbox)');
xlabel('z [m]'); ylabel('r [m]');
subplot(2,1,2);
pdeplot(model,'XYData',Umag,'FlowData',[uz(:) ur(:)],'ColorMap','jet','Mesh','off');
axis equal tight; title('|U| [m/s] e vetores de velocidade (FEM)');
xlabel('z [m]'); ylabel('r [m]');

% (d) PERFIS NO EIXO (r ~ 0)
zc=linspace(0,L,400);
[uxe,uye]=evaluateGradient(R, zc, 1e-4*ones(size(zc)));
ueix=hypot(uxe(:)',uye(:)'); peix=0.5*rho*(v_in^2-ueix.^2);
f4=figure('Name','Perfis no eixo (PDE)','Color','w','Position',[120 120 760 460]);
yyaxis left;  plot(zc,ueix,'LineWidth',2); ylabel('|U| no eixo [m/s]');
yyaxis right; plot(zc,peix,'LineWidth',2); ylabel('Pressao (Bernoulli) [Pa]');
xlabel('z [m]'); grid on; xline(z2,'--'); xline(z3,'--');
title('Perfis no eixo: velocidade maxima e pressao minima na garganta');

% (e) PERDA DE CARGA VISCOSA (Darcy-Weisbach laminar) ao longo do tubo
A1=pi*R1^2; Q=v_in*A1;
Rz=venturiR(zc,R1,Rt,z1,z2,z3,z4); Az=pi*Rz.^2; Vz=Q./Az; Dz=2*Rz;
Rez=rho*Vz.*Dz/mu; fz=64./Rez;                       % atrito laminar
dhf=fz./Dz.*Vz.^2/(2*g);                              % dh_f/dz
hf=cumtrapz(zc,dhf);                                  % perda acumulada [m]
f5=figure('Name','Perda de carga (PDE)','Color','w','Position',[140 140 760 420]);
plot(zc,hf*1000,'LineWidth',2); grid on; xline(z2,'--'); xline(z3,'--');
xlabel('z [m]'); ylabel('Perda de carga acumulada h_f [mm c.a.]');
title('Perda de carga viscosa (Darcy-Weisbach laminar) ao longo do Venturi');

%% 9) VERIFICACAO ANALITICA E RELATORIO
beta=Rt/R1; At=pi*Rt^2;
vt_teo=v_in*(R1/Rt)^2;
Re_in=rho*v_in*(2*R1)/mu; Re_th=rho*vt_teo*(2*Rt)/mu;
Umax=max(Umag); dP_bern=0.5*rho*(vt_teo^2-v_in^2);    % queda ideal ent->garganta
hf_tot=hf(end); dPf_tot=rho*g*hf_tot;                 % perda viscosa total

fprintf('\n=============== RESULTADOS (PDE Toolbox / FEM) ===============\n');
fprintf('beta=Dt/D1 ....................... %.3f   (A1/At=%.2f)\n',beta,A1/At);
fprintf('Reynolds entrada / garganta ...... %.0f / %.0f  (laminar < ~2300)\n',Re_in,Re_th);
fprintf('Vazao Q .......................... %.3e m^3/s = %.3f L/min\n',Q,Q*6e4);
fprintf('--- Velocidade ---\n');
fprintf('v_entrada (imposta) .............. %.4f m/s\n',v_in);
fprintf('v_garganta (continuidade) ........ %.4f m/s\n',vt_teo);
fprintf('|U|_max (FEM, potencial) ......... %.4f m/s\n',Umax);
fprintf('--- Pressao / Perda de carga ---\n');
fprintf('Queda ent->garganta (Bernoulli) .. %.3f Pa\n',dP_bern);
fprintf('Pressao minima na garganta (FEM) . %.3f Pa\n',min(peix));
fprintf('Perda de carga viscosa total ..... %.3f Pa  (%.3f mm c.a.)\n',dPf_tot,hf_tot*1000);
fprintf('=============================================================\n');
fprintf('Obs.: o escoamento potencial e invISCido (a pressao se recupera\n');
fprintf('   totalmente no difusor). A perda de carga IRREVERSIVEL e estimada\n');
fprintf('   por Darcy-Weisbach (curva acima) e/ou pelo solver Navier-Stokes\n');
fprintf('   (venturi_cfd_solver.m), que da dP_liquido ~ 5-6 Pa.\n');

%% 10) SALVAR FIGURAS
saveas(f1,'venturi_pde_velocidade.png'); saveas(f2,'venturi_pde_pressao.png');
saveas(f3,'venturi_pde_malha_fem.png');  saveas(f4,'venturi_pde_perfis_eixo.png');
saveas(f5,'venturi_pde_perdacarga.png');
fprintf('\nFiguras salvas: venturi_pde_velocidade/pressao/malha_fem/perfis_eixo/perdacarga.png\n');
end

% =======================================================================
function R=venturiR(z,R1,Rt,z1,z2,z3,z4)
% Perfil do raio da parede ao longo de z (convergente-garganta-divergente)
R=R1*ones(size(z));
m1=z>=z1&z<z2; R(m1)=R1+(Rt-R1).*(z(m1)-z1)./(z2-z1);
m2=z>=z2&z<z3; R(m2)=Rt;
m3=z>=z3&z<z4; R(m3)=Rt+(R1-Rt).*(z(m3)-z3)./(z4-z3);
end
