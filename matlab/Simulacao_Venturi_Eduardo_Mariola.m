function Simulacao_Venturi_Eduardo_Mariola(quick)
%% =======================================================================
%  SIMULACAO CFD DE ESCOAMENTO DE AGUA EM UM TUBO VENTURI (AXISSIMETRICO)
%  Iniciacao Cientifica - Eduardo Mariola Shouga Mendes (UNESP/IQ)
%  Modelagem matematica no controle de emissoes - Lavadores Venturi
%
%  Solver : Navier-Stokes incompressivel AXISSIMETRICO (r,z) resolvido por
%           METODO DA PROJECAO (fractional-step) em GRADE DESLOCADA (MAC),
%           em MATLAB PURO. NAO requer FEATool/PDE Toolbox nem add-ons.
%  Modelo : Laminar, incompressivel; marcha no tempo ate o estacionario.
%           Parede do tubo em r=R(z) (convergente-garganta-divergente)
%           imposta por mascara de celulas.
%  Saidas : Campos de VELOCIDADE e PRESSAO (PERDA DE CARGA) em gradientes
%           visuais (contornos) sobre o tubo espelhado + linhas de corrente,
%           perfis no eixo, perda de carga e verificacao analitica
%           (continuidade / Bernoulli / Reynolds / Cd / K).
%
%  Referencia metodologica:
%   Said Ali, Sheikh Suleimany, Ibrahim (2023). "Numerical Modeling of the
%   Flow around a Cylinder using FEATool Multiphysics", ETASR 13(4),
%   11290-11297.
%
%  USO:  >> venturi_cfd_solver        % malha de producao
%        >> venturi_cfd_solver(true)  % malha grosseira (teste rapido)
% =======================================================================

if nargin<1, quick=false; end
clc; close all;
fprintf('=== Venturi CFD - NS axissimetrico, projecao em grade MAC ===\n');

%% 1) FLUIDO (AGUA ~20 C) E ENTRADA
rho=998; mu=1.002e-3; nu=mu/rho; v_in=0.015; g=9.81;

%% 2) GEOMETRIA  R(z)  (mesmas cotas do modelo FEATool)
R1=0.025; Rt=0.010;
L_in=0.05; L_conv=0.05; L_th=0.02; L_div=0.10; L_out=0.08;
z1=L_in; z2=z1+L_conv; z3=z2+L_th; z4=z3+L_div; L=z4+L_out;
Rprofile=@(z) Rwall_profile(z,R1,Rt,z1,z2,z3,z4);

%% 3) MALHA MAC (z,r): p em centros; u_z em faces-z; u_r em faces-r
if quick, Nz=160; Nr=34; Tfinal=6; else, Nz=300; Nr=60; Tfinal=9; end
dz=L/Nz; dr=R1/Nr;
zc=((1:Nz)-0.5)*dz;  rc=((1:Nr)-0.5)*dr;     % centros
rf=(0:Nr)*dr;                                 % faces-r (rf(1)=0 eixo)
Rw=Rprofile(zc(:));                            % parede por coluna i
fluid=repmat(rc,Nz,1) < Rw;                    % celula fluida se rc<R(z)
inletcol=fluid(1,:);                           % celulas fluidas na entrada
% faces ativas (1 entre duas celulas fluidas; 0 = parede)
activeU=false(Nz+1,Nr);                         % u_z em I=1..Nz+1, col j
activeU(2:Nz,:)=fluid(1:Nz-1,:)&fluid(2:Nz,:);
activeU(1,:)=inletcol;                           % entrada
activeU(Nz+1,:)=fluid(Nz,:);                      % saida
activeV=false(Nz,Nr+1);                          % u_r em i, J=1..Nr+1
activeV(:,2:Nr)=fluid(:,1:Nr-1)&fluid(:,2:Nr);
fprintf('Malha MAC %dx%d (%d celulas fluidas).  dz=%.2g  dr=%.2g\n',...
        Nz,Nr,nnz(fluid),dz,dr);

%% 4) OPERADOR DE PRESSAO (Poisson axissimetrico compacto) - 1x
[Adec,idmap]=build_poisson(fluid,Nz,Nr,dz,dr,rc); %#ok<ASGLU>

%% 5) PASSO DE TEMPO (estabilidade explicita; convectivo recalculado)
umax=v_in*(R1/Rt)^2;
dt_visc=0.20*0.25*dr^2/nu;                      % limite viscoso (fixo)
dt=min(dt_visc, 0.20*min(dz,dr)/umax);          % CFL convectivo inicial
nsteps=ceil(Tfinal/dt)*3;                         % teto generoso (parada por estado est.)
fprintf('dt0=%.3g s  dt_visc=%.3g s  (t_final~%.1f s)\n',dt,dt_visc,Tfinal);

%% 6) MARCHA NO TEMPO (projecao)
u=zeros(Nz+1,Nr); v=zeros(Nz,Nr+1); p=zeros(Nz,Nr);
u(1,inletcol)=v_in;
RC=repmat(rc,Nz,1);  RFa=repmat(rf(2:Nr+1),Nz,1); RFb=repmat(rf(1:Nr),Nz,1);
fprintf('Resolvendo...\n'); t0=tic; uold=u; tcur=0;
for n=1:nsteps
    % --- passo de tempo adaptativo (CFL convectivo + limite viscoso) ---
    smax=max(max(abs(u(:))),max(abs(v(:))));
    dt=min(dt_visc, 0.40*min(dz,dr)/max(smax,umax));   % CFL convectivo + limite viscoso
    tcur=tcur+dt; if tcur>Tfinal, break; end
    % --- preditor (adveccao upwind + difusao central axissimetrica) ---
    us=u; vs=v;
    % u_z momentum (faces internas I=2..Nz)
    II=2:Nz;
    uRpad=[u(:,1) u zeros(Nz+1,1)];                 % eixo: espelho ; parede: 0
    d2uz=(u(II+1,:)-2*u(II,:)+u(II-1,:))/dz^2;
    d2ur=(uRpad(II,3:end)-2*uRpad(II,2:end-1)+uRpad(II,1:end-2))/dr^2;
    durdr=(uRpad(II,3:end)-uRpad(II,1:end-2))/(2*dr);
    rcU=repmat(rc,Nz-1,1);
    diffU=nu*(d2uz+d2ur+durdr./rcU);
    uP=u(II,:);
    duz_b=(uP-u(II-1,:))/dz; duz_f=(u(II+1,:)-uP)/dz;
    duz=duz_b; duz(uP<=0)=duz_f(uP<=0);
    uS=uRpad(II,1:end-2); uN=uRpad(II,3:end); uC=uRpad(II,2:end-1);
    dur_b=(uC-uS)/dr; dur_f=(uN-uC)/dr;
    vbar=0.25*(v(II-1,1:Nr)+v(II,1:Nr)+v(II-1,2:Nr+1)+v(II,2:Nr+1));
    dur=dur_b; dur(vbar<=0)=dur_f(vbar<=0);
    us(II,:)=uP+dt*(-(uP.*duz+vbar.*dur)+diffU);
    % u_r momentum (faces internas J=2..Nr)
    JJ=2:Nr;
    vZpad=[v(1,:);v;v(end,:)];                        % entrada/saida: dv/dz=0
    d2vz=(vZpad(3:end,JJ)-2*v(:,JJ)+vZpad(1:end-2,JJ))/dz^2;
    d2vr=(v(:,JJ+1)-2*v(:,JJ)+v(:,JJ-1))/dr^2;
    dvrdr=(v(:,JJ+1)-v(:,JJ-1))/(2*dr);
    rfV=repmat(rf(JJ),Nz,1);
    diffV=nu*(d2vz+d2vr+dvrdr./rfV-v(:,JJ)./rfV.^2);
    vP=v(:,JJ);
    ubar=0.25*(u(1:Nz,JJ-1)+u(1:Nz,JJ)+u(2:Nz+1,JJ-1)+u(2:Nz+1,JJ));
    dvz_b=(vP-vZpad(1:end-2,JJ))/dz; dvz_f=(vZpad(3:end,JJ)-vP)/dz;
    dvz=dvz_b; dvz(ubar<=0)=dvz_f(ubar<=0);
    dvr_b=(vP-v(:,JJ-1))/dr; dvr_f=(v(:,JJ+1)-vP)/dr;
    dvr=dvr_b; dvr(vP<=0)=dvr_f(vP<=0);
    vs(:,JJ)=vP+dt*(-(ubar.*dvz+vP.*dvr)+diffV);
    % --- BC no campo preditor ---
    us=us.*activeU; us(1,inletcol)=v_in;
    us(Nz+1,:)=us(Nz,:).*activeU(Nz+1,:);     % saida: estimativa dv/dz=0 (corrigida p/ pressao)
    vs=vs.*activeV;                            % eixo (J=1) e parede ja sao 0
    % --- divergencia axissimetrica de (us,vs) ---
    D=(us(2:Nz+1,:)-us(1:Nz,:))/dz + (RFa.*vs(:,2:Nr+1)-RFb.*vs(:,1:Nr))./(RC*dr);
    D(~fluid)=0;
    % --- Poisson:  Lap(p)=(rho/dt)D ---
    pv=Adec\((rho/dt)*D(fluid)); p(:)=0; p(fluid)=pv;
    % --- correcao ---
    u=us; v=vs;
    u(II,:)=us(II,:)-dt/rho*(p(II,:)-p(II-1,:))/dz;
    v(:,JJ)=vs(:,JJ)-dt/rho*(p(:,JJ)-p(:,JJ-1))/dr;
    u(Nz+1,:)=us(Nz+1,:)+dt/rho*p(Nz,:)/dz;    % saida: pressao-outlet (p_fantasma=0)
    % --- BC final ---
    u=u.*activeU; u(1,inletcol)=v_in;
    v=v.*activeV;
    if any(~isfinite(u(:))), error('Divergiu (NaN/Inf) no passo %d. Reduza o CFL.',n); end
    if mod(n,max(1,round(nsteps/12)))==0 || n==1
        Dc=(u(2:Nz+1,:)-u(1:Nz,:))/dz+(RFa.*v(:,2:Nr+1)-RFb.*v(:,1:Nr))./(RC*dr);
        chg=max(abs(u(:)-uold(:)))/max(v_in,1e-9);
        fprintf('  passo %6d/%d  |div|max=%.2e  Umax=%.4f  d(u)/Uin=%.2e\n',...
                n,nsteps,max(abs(Dc(fluid))),max(abs(u(:))),chg);
        if any(~isfinite(u(:))), error('Divergiu (NaN/Inf).'); end
        if chg<1e-4 && n>50, fprintf('  -> estado estacionario.\n'); break; end
        uold=u;
    end
end
fprintf('Concluido em %.1f s de CPU.\n',toc(t0));

%% 7) CAMPOS CENTRADOS E VISUALIZACAO
uc=0.5*(u(1:Nz,:)+u(2:Nz+1,:)); vc=0.5*(v(:,1:Nr)+v(:,2:Nr+1));
Umag=hypot(uc,vc); Umag(~fluid)=NaN; pp=p; pp(~fluid)=NaN;
rfull=[-fliplr(rc) rc]; Zc=repmat(zc(:),1,2*Nr); Rf=repmat(rfull,Nz,1);
Umir=[fliplr(Umag) Umag]; Pmir=[fliplr(pp) pp];
Uu=[fliplr(-vc) vc]; Uv=[fliplr(uc) uc];

f1=figure('Name','Velocidade','Color','w','Position',[60 90 1180 380]);
contourf(Zc',Rf',Umir',26,'LineStyle','none'); hold on; axis equal tight;
colormap(gca,jet); cb=colorbar; cb.Label.String='|U| [m/s]';
sy=linspace(-0.9*R1,0.9*R1,16);
set(streamline(Zc',Rf',Uv',Uu',zeros(size(sy)),sy),'Color',[0 0 0 0.35]);
plot(zc,Rw,'k','LineWidth',1.2); plot(zc,-Rw,'k','LineWidth',1.2);
xlabel('z [m] (sentido do escoamento)'); ylabel('r [m]');
title('Campo de velocidade |U| - aceleracao na garganta (linhas de corrente)');

f2=figure('Name','Pressao','Color','w','Position',[60 90 1180 380]);
contourf(Zc',Rf',Pmir',26,'LineStyle','none'); hold on; axis equal tight;
colormap(gca,jet); cb=colorbar; cb.Label.String='p [Pa]';
plot(zc,Rw,'k','LineWidth',1.2); plot(zc,-Rw,'k','LineWidth',1.2);
xlabel('z [m]'); ylabel('r [m]');
title('Campo de pressao p [Pa] - queda na garganta e recuperacao no difusor');

ua=Umag(:,1); pa=p(:,1);
f3=figure('Name','Perfis no eixo','Color','w','Position',[120 120 760 460]);
yyaxis left;  plot(zc,ua,'LineWidth',2); ylabel('|U| no eixo [m/s]');
yyaxis right; plot(zc,pa,'LineWidth',2); ylabel('Pressao no eixo [Pa]');
xlabel('z [m]'); grid on; xline(z2,'--'); xline(z3,'--');
title('Perfis no eixo: velocidade maxima e pressao minima na garganta');

hpiezo=(pa-pa(end))/(rho*g);
f4=figure('Name','Perda de carga','Color','w','Position',[140 140 760 420]);
plot(zc,hpiezo*1000,'LineWidth',2); grid on; xline(z2,'--'); xline(z3,'--');
xlabel('z [m]'); ylabel('(p-p_{saida})/\rho g  [mm c.a.]');
title('Perda de carga ao longo do Venturi (recuperacao parcial no difusor)');

%% 8) VERIFICACAO ANALITICA E RELATORIO
A1=pi*R1^2; At=pi*Rt^2; beta=Rt/R1;
Q=2*pi*sum(u(1,inletcol).*rc(inletcol))*dr;
v1_cfd=Q/A1; vt_teo=v_in*(R1/Rt)^2;
Re_in=rho*v_in*(2*R1)/mu; Re_th=rho*vt_teo*(2*Rt)/mu;
p_in=areaMeanP(p,fluid,rc,dr,zc,zc(1));
p_th=areaMeanP(p,fluid,rc,dr,zc,(z2+z3)/2);
p_out=areaMeanP(p,fluid,rc,dr,zc,zc(end));
dP_inth=p_in-p_th; dP_bern=0.5*rho*(vt_teo^2-v_in^2);
dP_loss=p_in-p_out; hL=dP_loss/(rho*g);
if dP_inth>0, Qideal=At*sqrt(2*dP_inth/(rho*(1-beta^4))); Cd=Q/Qideal; else, Cd=NaN; end
Kloss=dP_loss/(0.5*rho*vt_teo^2); Umax_cfd=max(Umag(fluid));

fprintf('\n================= RESULTADOS (CFD) =================\n');
fprintf('beta=Dt/D1 ....................... %.3f   (A1/At=%.2f)\n',beta,A1/At);
fprintf('Reynolds entrada / garganta ...... %.0f / %.0f  (laminar < ~2300)\n',Re_in,Re_th);
fprintf('Vazao Q (CFD) .................... %.3e m^3/s = %.3f L/min\n',Q,Q*6e4);
fprintf('v_entrada imposta / CFD .......... %.4f / %.4f m/s\n',v_in,v1_cfd);
fprintf('v_garganta (continuidade) ........ %.4f m/s\n',vt_teo);
fprintf('|U|_max (CFD) .................... %.4f m/s\n',Umax_cfd);
fprintf('dP ent->garg: Bernoulli / CFD .... %.3f / %.3f Pa\n',dP_bern,dP_inth);
fprintf('Perda de carga liquida (CFD) ..... %.3f Pa  (%.3f mm c.a.)\n',dP_loss,hL*1000);
fprintf('Coef. de descarga Cd ............. %.4f\n',Cd);
fprintf('Coef. de perda K (ref. garganta) . %.4f\n',Kloss);
fprintf('===================================================\n');

%% 9) SALVAR FIGURAS
saveas(f1,'venturi_cfd_velocidade.png'); saveas(f2,'venturi_cfd_pressao.png');
saveas(f3,'venturi_cfd_perfis_eixo.png'); saveas(f4,'venturi_cfd_perdacarga.png');
fprintf('\nFiguras salvas: venturi_cfd_velocidade/pressao/perfis_eixo/perdacarga.png\n');
end

% =======================================================================
function R=Rwall_profile(z,R1,Rt,z1,z2,z3,z4)
R=R1*ones(size(z));
m1=z>=z1&z<z2; R(m1)=R1+(Rt-R1).*(z(m1)-z1)./(z2-z1);
m2=z>=z2&z<z3; R(m2)=Rt;
m3=z>=z3&z<z4; R(m3)=Rt+(R1-Rt).*(z(m3)-z3)./(z4-z3);
end

function [Adec,idmap]=build_poisson(fluid,Nz,Nr,dz,dr,rc)
idmap=zeros(Nz,Nr); idmap(fluid)=1:nnz(fluid); N=nnz(fluid);
I=zeros(5*N,1); J=I; S=I; c=0; az=1/dz^2;
for i=1:Nz
  for j=1:Nr
    if ~fluid(i,j), continue; end
    n=idmap(i,j);
    arP=1/dr^2+1/(2*dr*rc(j)); arM=1/dr^2-1/(2*dr*rc(j)); d=0;
    % --- vizinho i-1 (z menor) ---
    if i>1 && fluid(i-1,j), c=c+1; I(c)=n; J(c)=idmap(i-1,j); S(c)=az; d=d-az; end
    % --- vizinho i+1 (z maior): interior, ou fantasma Dirichlet p=0 na saida ---
    if i<Nz && fluid(i+1,j), c=c+1; I(c)=n; J(c)=idmap(i+1,j); S(c)=az; d=d-az;
    elseif i==Nz,           d=d-az; end                      % saida: p_fantasma=0
    if j<Nr && fluid(i,j+1),c=c+1; I(c)=n; J(c)=idmap(i,j+1); S(c)=arP; d=d-arP; end
    if j>1 && fluid(i,j-1), c=c+1; I(c)=n; J(c)=idmap(i,j-1); S(c)=arM; d=d-arM; end
    c=c+1; I(c)=n; J(c)=n; S(c)=d;
  end
end
A=sparse(I(1:c),J(1:c),S(1:c),N,N); Adec=decomposition(A,'lu');
end

function pm=areaMeanP(p,fluid,rc,dr,zc,zq)
[~,i]=min(abs(zc-zq)); row=p(i,:); m=fluid(i,:);
w=2*pi*rc(m)*dr; pm=sum(row(m).*w)/sum(w);
end
