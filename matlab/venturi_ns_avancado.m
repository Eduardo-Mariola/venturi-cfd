function venturi_ns_avancado(modo, paramsExternos)
%% =======================================================================
%  VENTURI CFD AVANCADO - NAVIER-STOKES COMPLETO RESOLVIDO DO ZERO
%  Iniciacao Cientifica / Projeto Pessoal
%  Eduardo Mariola Shouga Mendes (UNESP/IQ) - Lavadores Venturi
%
%  Este codigo NAO usa o PDE Toolbox: as equacoes de NAVIER-STOKES
%  incompressiveis AXISSIMETRICAS (r,z) sao resolvidas do zero em MATLAB
%  puro pelo METODO DA PROJECAO (fractional-step) em GRADE DESLOCADA (MAC):
%
%    du/dt + (u.grad)u = -(1/rho) grad(p) + nu * Lap(u)     (momento)
%    div(u) = 0                                              (continuidade)
%
%   - Adveccao: upwind de 1a ordem      - Difusao: centrada, axissimetrica
%   - Acoplamento pressao-velocidade: projecao de Chorin
%       1) preditor u* (momento sem pressao)
%       2) Poisson  Lap(p) = (rho/dt) div(u*)   [matriz esparsa, LU direto]
%       3) correcao u = u* - (dt/rho) grad(p)   -> div(u)=0
%   - Parede do Venturi r=R(z) por mascara de celulas (no-slip real)
%   - Perfil de entrada PARABOLICO (Poiseuille desenvolvido) ou uniforme
%   - Marcha no tempo com dt adaptativo (CFL) ate o ESTADO ESTACIONARIO
%
%  Por ser viscoso e com nao-deslizamento na parede, o modelo captura o
%  que o escoamento potencial nao captura: camada limite, atrito real,
%  recuperacao PARCIAL de pressao no difusor e PERDA DE CARGA liquida.
%
%  ENTRADA PERSONALIZADA (todos os campos tem valor PADRAO):
%   fluido (rho, mu), material do tubo (rugosidade -> comparacao de
%   atrito), diametro do tubo, diametro da garganta, comprimento total,
%   comprimento da garganta, ANGULOS dos cones convergente/divergente,
%   velocidade de entrada e perfil de entrada.
%
%  USO
%   >> venturi_ns_avancado               % interativo (ENTER = padrao)
%   >> venturi_ns_avancado('padrao')     % roda direto com os defaults
%   >> venturi_ns_avancado('padrao', S)  % struct S com parametros
%   >> venturi_ns_avancado('rapido')     % malha grosseira (teste)
%
%  VALIDADE: solver LAMINAR resolvido diretamente (sem modelo de
%  turbulencia). Se Reynolds da garganta > ~2300 o codigo avisa e fornece
%  a estimativa turbulenta de Darcy-Weisbach/Swamee-Jain com a rugosidade
%  do material como referencia complementar.
% =======================================================================

clc; close all;
fprintf('===================================================================\n');
fprintf('  VENTURI CFD AVANCADO - NAVIER-STOKES do zero (projecao / MAC)\n');
fprintf('  Solver viscoso incompressivel axissimetrico em MATLAB puro\n');
fprintf('===================================================================\n\n');

if nargin<1 || isempty(modo), modo='interativo'; end
quick = strcmpi(modo,'rapido');

%% -----------------------------------------------------------------------
%  1) ENTRADA DE DADOS (com valores PADRAO)
%  -----------------------------------------------------------------------
if nargin>=2 && ~isempty(paramsExternos)
    P = preencherPadroes(paramsExternos);
    fprintf('>> Parametros recebidos via struct externo.\n\n');
elseif strcmpi(modo,'padrao') || quick
    P = preencherPadroes(struct());
    fprintf('>> Modo %s: usando valores default.\n\n',upper(modo));
else
    P = lerParametrosInterativo();
end

rho=P.rho; mu=P.mu; nu=mu/rho; v_in=P.v_in; g=9.81; eps_abs=P.eps_abs;

%% -----------------------------------------------------------------------
%  2) GEOMETRIA R(z) DERIVADA DOS ANGULOS
%  -----------------------------------------------------------------------
R1=P.D_in/2; Rt=P.D_th/2;
assert(Rt<R1,'A garganta (D_th) deve ser menor que o tubo (D_in).');
thc=deg2rad(P.ang_conv); thd=deg2rad(P.ang_div);
L_conv=(R1-Rt)/tan(thc); L_div=(R1-Rt)/tan(thd); L_th=P.L_throat;
L_reto=P.L_total-(L_conv+L_th+L_div);
if L_reto<0
    warning(['L_total insuficiente para cones+garganta com esses angulos. ' ...
             'Estendendo o comprimento total.']);
    L_in=0.5*L_conv; L_out=0.8*L_div;
else
    L_in=0.35*L_reto; L_out=0.65*L_reto;
end
z1=L_in; z2=z1+L_conv; z3=z2+L_th; z4=z3+L_div; L=z4+L_out;
Rprofile=@(z) Rwall_profile(z,R1,Rt,z1,z2,z3,z4);

%% -----------------------------------------------------------------------
%  3) MALHA MAC (z,r): p em centros; u_z em faces-z; u_r em faces-r
%     Resolucao adaptada a garganta: >= ~12 celulas radiais no gargalo
%  -----------------------------------------------------------------------
if quick
    Nr=34; Nz=160;
else
    Nr=min(100, max(48, ceil(12*R1/Rt/2)*2));      % garante gargalo resolvido
    Nz=min(420, max(200, round(L/(R1/Nr)*0.9)));   % dz ~ dr
end
dz=L/Nz; dr=R1/Nr;
zc=((1:Nz)-0.5)*dz;  rc=((1:Nr)-0.5)*dr;
rf=(0:Nr)*dr;
Rw=Rprofile(zc(:));
fluid=repmat(rc,Nz,1) < Rw;
inletcol=fluid(1,:);
activeU=false(Nz+1,Nr);
activeU(2:Nz,:)=fluid(1:Nz-1,:)&fluid(2:Nz,:);
activeU(1,:)=inletcol;
activeU(Nz+1,:)=fluid(Nz,:);
activeV=false(Nz,Nr+1);
activeV(:,2:Nr)=fluid(:,1:Nr-1)&fluid(:,2:Nr);
fprintf('Malha MAC %dx%d (%d celulas fluidas).  dz=%.3g m  dr=%.3g m\n',...
        Nz,Nr,nnz(fluid),dz,dr);
fprintf('Celulas radiais na garganta: %d\n', nnz(rc<Rt));

% Perfil de entrada (mesma vazao Q = v_in*A1 nos dois casos)
if P.perfil==2
    uin=v_in*ones(1,Nr);                            % uniforme (plug)
    perfilNome='uniforme (plug)';
else
    uin=2*v_in*(1-(rc/R1).^2);                      % Poiseuille desenvolvido
    perfilNome='parabolico (Poiseuille desenvolvido)';
end
uin(~inletcol)=0;

%% -----------------------------------------------------------------------
%  4) OPERADOR DE PRESSAO (Poisson axissimetrico, esparso, LU direto)
%  -----------------------------------------------------------------------
[Adec,~]=build_poisson(fluid,Nz,Nr,dz,dr,rc);

%% -----------------------------------------------------------------------
%  5) PASSO DE TEMPO E CRITERIOS
%  -----------------------------------------------------------------------
fac=1; if P.perfil~=2, fac=2; end                   % pico do perfil parabolico
umax=fac*v_in*(R1/Rt)^2;
dt_visc=0.20*0.25*dr^2/nu;
dt=min(dt_visc,0.20*min(dz,dr)/umax);
Tfinal=max(6, 1.5*L/max(v_in,1e-9));                % teto fisico
nmax=120000;                                        % teto de passos
fprintf('dt0=%.3g s   dt_visc=%.3g s   T_final(max)=%.1f s\n',dt,dt_visc,Tfinal);

%% -----------------------------------------------------------------------
%  6) MARCHA NO TEMPO (PROJECAO DE CHORIN)
%  -----------------------------------------------------------------------
u=zeros(Nz+1,Nr); v=zeros(Nz,Nr+1); p=zeros(Nz,Nr);
u(1,:)=uin;
RC=repmat(rc,Nz,1); RFa=repmat(rf(2:Nr+1),Nz,1); RFb=repmat(rf(1:Nr),Nz,1);
fprintf('Resolvendo Navier-Stokes (marcha ao estacionario)...\n');
t0=tic; uold=u; tcur=0; nchk=250;
for n=1:nmax
    smax=max(max(abs(u(:))),max(abs(v(:))));
    dt=min(dt_visc,0.40*min(dz,dr)/max(smax,umax));
    tcur=tcur+dt; if tcur>Tfinal, fprintf('  -> teto de tempo fisico atingido.\n'); break; end

    % --- PREDITOR: momento u_z (faces internas I=2..Nz) ---
    us=u; vs=v;
    II=2:Nz;
    uRpad=[u(:,1) u zeros(Nz+1,1)];                 % eixo: simetria ; parede: 0
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

    % --- PREDITOR: momento u_r (faces internas J=2..Nr) ---
    JJ=2:Nr;
    vZpad=[v(1,:);v;v(end,:)];
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

    % --- BC no preditor ---
    us=us.*activeU; us(1,:)=uin;
    us(Nz+1,:)=us(Nz,:).*activeU(Nz+1,:);
    vs=vs.*activeV;

    % --- divergencia axissimetrica ---
    D=(us(2:Nz+1,:)-us(1:Nz,:))/dz + (RFa.*vs(:,2:Nr+1)-RFb.*vs(:,1:Nr))./(RC*dr);
    D(~fluid)=0;

    % --- POISSON: Lap(p) = (rho/dt) div(u*) ---
    pv=Adec\((rho/dt)*D(fluid)); p(:)=0; p(fluid)=pv;

    % --- CORRECAO (projecao no espaco de divergencia nula) ---
    u=us; v=vs;
    u(II,:)=us(II,:)-dt/rho*(p(II,:)-p(II-1,:))/dz;
    v(:,JJ)=vs(:,JJ)-dt/rho*(p(:,JJ)-p(:,JJ-1))/dr;
    u(Nz+1,:)=us(Nz+1,:)+dt/rho*p(Nz,:)/dz;        % saida: p_fantasma=0

    % --- BC final ---
    u=u.*activeU; u(1,:)=uin;
    v=v.*activeV;
    if any(~isfinite(u(:))), error('Divergiu (NaN/Inf) no passo %d.',n); end

    % --- monitoramento e criterio de estado estacionario ---
    if mod(n,nchk)==0 || n==1
        Dc=(u(2:Nz+1,:)-u(1:Nz,:))/dz+(RFa.*v(:,2:Nr+1)-RFb.*v(:,1:Nr))./(RC*dr);
        chg=max(abs(u(:)-uold(:)))/max(v_in,1e-9);
        fprintf('  passo %6d  t=%.3fs  |div|max=%.2e  Umax=%.4f  d(u)/Uin=%.2e\n',...
                n,tcur,max(abs(Dc(fluid))),max(abs(u(:))),chg);
        if chg<1e-4 && n>nchk, fprintf('  -> ESTADO ESTACIONARIO atingido.\n'); break; end
        uold=u;
    end
end
fprintf('Concluido em %.1f s de CPU (%d passos).\n',toc(t0),n);

%% -----------------------------------------------------------------------
%  7) CAMPOS CENTRADOS + VISUALIZACAO (tubo espelhado)
%  -----------------------------------------------------------------------
uc=0.5*(u(1:Nz,:)+u(2:Nz+1,:)); vc=0.5*(v(:,1:Nr)+v(:,2:Nr+1));
Umag=hypot(uc,vc); Umag(~fluid)=NaN; pp=p; pp(~fluid)=NaN;
rfull=[-fliplr(rc) rc]; Zc=repmat(zc(:),1,2*Nr); Rf=repmat(rfull,Nz,1);
Umir=[fliplr(Umag) Umag]; Pmir=[fliplr(pp) pp];
Uu=[fliplr(-vc) vc]; Uv=[fliplr(uc) uc];

f1=figure('Name','Velocidade (NS)','Color','w','Position',[60 90 1180 380]);
contourf(Zc',Rf',Umir',26,'LineStyle','none'); hold on; axis equal tight;
colormap(gca,jet); cb=colorbar; cb.Label.String='|U| [m/s]';
sy=linspace(-0.9*R1,0.9*R1,16);
set(streamline(Zc',Rf',Uv',Uu',zeros(size(sy)),sy),'Color',[0 0 0 0.35]);
plot(zc,Rw,'k','LineWidth',1.2); plot(zc,-Rw,'k','LineWidth',1.2);
xlabel('z [m] (sentido do escoamento)'); ylabel('r [m]');
title(sprintf('Navier-Stokes: |U| com camada limite (D=%.0f mm, garganta=%.0f mm, %s)',...
    P.D_in*1e3,P.D_th*1e3,P.material));

f2=figure('Name','Pressao (NS)','Color','w','Position',[60 90 1180 380]);
contourf(Zc',Rf',Pmir',26,'LineStyle','none'); hold on; axis equal tight;
colormap(gca,jet); cb=colorbar; cb.Label.String='p [Pa]';
plot(zc,Rw,'k','LineWidth',1.2); plot(zc,-Rw,'k','LineWidth',1.2);
xlabel('z [m]'); ylabel('r [m]');
title('Navier-Stokes: pressao com recuperacao PARCIAL no difusor (perda real)');

ua=Umag(:,1); pa=p(:,1);
f3=figure('Name','Perfis no eixo (NS)','Color','w','Position',[120 120 760 460]);
yyaxis left;  plot(zc,ua,'LineWidth',2); ylabel('|U| no eixo [m/s]');
yyaxis right; plot(zc,pa,'LineWidth',2); ylabel('Pressao no eixo [Pa]');
xlabel('z [m]'); grid on; xline(z2,'--'); xline(z3,'--');
title('Perfis no eixo: aceleracao na garganta e pressao nao recuperada');

hpiezo=(pa-pa(end))/(rho*g);
f4=figure('Name','Perda de carga (NS)','Color','w','Position',[140 140 760 420]);
plot(zc,hpiezo*1000,'LineWidth',2); grid on; xline(z2,'--'); xline(z3,'--');
xlabel('z [m]'); ylabel('(p-p_{saida})/\rho g  [mm c.a.]');
title(sprintf('Perda de carga (NS resolvido) - fluido: rho=%.0f, mu=%.2g',rho,mu));

% Perfis radiais de velocidade (entrada, garganta, saida) - realismo visivel
[~,ie]=min(abs(zc-z1/2)); [~,it]=min(abs(zc-(z2+z3)/2)); [~,is]=min(abs(zc-(z4+L)/2));
f5=figure('Name','Perfis radiais (NS)','Color','w','Position',[160 160 760 420]);
plot(uc(ie,:),rc*1e3,'LineWidth',2); hold on;
plot(uc(it,:),rc*1e3,'LineWidth',2);
plot(uc(is,:),rc*1e3,'LineWidth',2); grid on;
legend(sprintf('entrada z=%.0f mm',zc(ie)*1e3),...
       sprintf('garganta z=%.0f mm',zc(it)*1e3),...
       sprintf('saida z=%.0f mm',zc(is)*1e3),'Location','best');
xlabel('u_z [m/s]'); ylabel('r [mm]');
title('Perfis radiais de velocidade: camada limite e nao-deslizamento na parede');

%% -----------------------------------------------------------------------
%  8) VERIFICACAO ANALITICA E RELATORIO
%  -----------------------------------------------------------------------
A1=pi*R1^2; At=pi*Rt^2; beta=Rt/R1;
Q=2*pi*sum(u(1,inletcol).*rc(inletcol))*dr;
v1_cfd=Q/A1; vt_teo=v1_cfd*(R1/Rt)^2;
Re_in=rho*v1_cfd*(2*R1)/mu; Re_th=rho*vt_teo*(2*Rt)/mu;
p_in=areaMeanP(p,fluid,rc,dr,zc,zc(1));
p_th=areaMeanP(p,fluid,rc,dr,zc,(z2+z3)/2);
p_out=areaMeanP(p,fluid,rc,dr,zc,zc(end));
dP_inth=p_in-p_th; dP_bern=0.5*rho*(vt_teo^2-v1_cfd^2);
dP_loss=p_in-p_out; hL=dP_loss/(rho*g);
if dP_inth>0, Qideal=At*sqrt(2*dP_inth/(rho*(1-beta^4))); Cd=Q/Qideal; else, Cd=NaN; end
Kloss=dP_loss/(0.5*rho*vt_teo^2); Umax_cfd=max(Umag(fluid));

% Estimativa Darcy-Weisbach com rugosidade do material (referencia)
zq=linspace(0,L,400); Rq=Rprofile(zq); Aq=pi*Rq.^2; Vq=Q./Aq; Dq=2*Rq;
Req=rho*Vq.*Dq/mu; fq=fatorAtrito(Req,eps_abs./Dq);
dPdw=rho*g*trapz(zq,fq./Dq.*Vq.^2/(2*g));

regime=@(Re) ternario(Re<2300,'laminar',ternario(Re<4000,'transicao','turbulento'));
fprintf('\n========== RESULTADOS (NAVIER-STOKES resolvido do zero) ==========\n');
fprintf('FLUIDO ... rho=%.1f kg/m^3, mu=%.3e Pa.s, nu=%.3e m^2/s\n',rho,mu,nu);
fprintf('MATERIAL . %s (eps=%.3g mm)\n',P.material,eps_abs*1e3);
fprintf('PERFIL DE ENTRADA: %s\n',perfilNome);
fprintf('GEOMETRIA  D=%.1f mm, garganta=%.1f mm, L=%.1f mm\n',P.D_in*1e3,P.D_th*1e3,L*1e3);
fprintf('           ang.conv=%.1f deg (L=%.1f mm), ang.div=%.1f deg (L=%.1f mm)\n',...
    P.ang_conv,L_conv*1e3,P.ang_div,L_div*1e3);
fprintf('------------------------------------------------------------------\n');
fprintf('beta=Dt/D1 ....................... %.3f   (A1/At=%.2f)\n',beta,A1/At);
fprintf('Reynolds entrada ................. %.0f  (%s)\n',Re_in,regime(Re_in));
fprintf('Reynolds garganta ................ %.0f  (%s)\n',Re_th,regime(Re_th));
fprintf('Vazao Q .......................... %.3e m^3/s = %.3f L/min\n',Q,Q*6e4);
fprintf('--- Velocidade ---\n');
fprintf('v_entrada media (CFD) ............ %.4f m/s\n',v1_cfd);
fprintf('v_garganta media (continuidade) .. %.4f m/s\n',vt_teo);
fprintf('|U|_max (CFD, com camada limite) . %.4f m/s\n',Umax_cfd);
fprintf('--- Pressao / Perda de carga ---\n');
fprintf('dP ent->garganta: Bernoulli/CFD .. %.3f / %.3f Pa\n',dP_bern,dP_inth);
fprintf('PERDA DE CARGA LIQUIDA (NS) ...... %.3f Pa  (%.3f mm c.a.)\n',dP_loss,hL*1000);
fprintf('Estimativa Darcy-Weisbach ........ %.3f Pa  (material: %s)\n',dPdw,P.material);
fprintf('Coef. de descarga Cd ............. %.4f\n',Cd);
fprintf('Coef. de perda K (ref. garganta) . %.4f\n',Kloss);
fprintf('==================================================================\n');
if Re_th>2300
    fprintf(['AVISO: Re_garganta=%.0f > 2300 (%s). Este solver e laminar\n' ...
             '  (sem modelo de turbulencia): a perda real tende a ser MAIOR.\n' ...
             '  Use a estimativa Darcy-Weisbach acima (inclui rugosidade do\n' ...
             '  material via Swamee-Jain) como referencia complementar.\n'],Re_th,regime(Re_th));
else
    fprintf(['Obs.: regime laminar - o atrito e resolvido DIRETAMENTE pelo\n' ...
             '  nao-deslizamento na parede; a rugosidade do material tem efeito\n' ...
             '  despresivel abaixo da transicao (tubo hidraulicamente liso).\n']);
end

%% 9) SALVAR FIGURAS
saveas(f1,'venturi_ns_adv_velocidade.png'); saveas(f2,'venturi_ns_adv_pressao.png');
saveas(f3,'venturi_ns_adv_perfis_eixo.png'); saveas(f4,'venturi_ns_adv_perdacarga.png');
saveas(f5,'venturi_ns_adv_perfis_radiais.png');
fprintf('\nFiguras salvas: venturi_ns_adv_velocidade/pressao/perfis_eixo/perdacarga/perfis_radiais.png\n');
end

% =======================================================================
%  ENTRADA DE DADOS
% =======================================================================
function P = lerParametrosInterativo()
D = preencherPadroes(struct());
fprintf('--- ENTRADA DE DADOS (aperte ENTER para aceitar o [padrao]) ---\n\n');

fprintf('Fluido de trabalho:\n');
fprintf('  1) Agua 20 C  (padrao)   rho=998, mu=1.002e-3\n');
fprintf('  2) Ar 20 C               rho=1.204, mu=1.82e-5\n');
fprintf('  3) Glicerina 20 C        rho=1261, mu=1.41\n');
fprintf('  4) Oleo SAE30 20 C       rho=891,  mu=0.29\n');
fprintf('  5) Personalizado (informar rho e mu)\n');
opf = perguntarNum('  Escolha [1]',1);
switch opf
    case 2, P.rho=1.204; P.mu=1.82e-5;
    case 3, P.rho=1261;  P.mu=1.41;
    case 4, P.rho=891;   P.mu=0.29;
    case 5
        P.rho=perguntarNum('  Densidade rho [kg/m^3]',D.rho);
        P.mu =perguntarNum('  Viscosidade dinamica mu [Pa.s]',D.mu);
    otherwise, P.rho=998; P.mu=1.002e-3;
end

fprintf('\nMaterial do tubo (rugosidade -> comparacao de atrito):\n');
fprintf('  1) PVC / plastico liso (padrao)  eps=0.0015 mm\n');
fprintf('  2) Aco inoxidavel                eps=0.015 mm\n');
fprintf('  3) Aco comercial                 eps=0.045 mm\n');
fprintf('  4) Ferro fundido                 eps=0.26 mm\n');
fprintf('  5) Concreto                      eps=1.0 mm\n');
fprintf('  6) Vidro (liso)                  eps=0.0 mm\n');
fprintf('  7) Personalizado (informar eps)\n');
opm = perguntarNum('  Escolha [1]',1);
[P.material,P.eps_abs]=materialInfo(opm,D);

fprintf('\nGeometria e condicoes de entrada:\n');
P.D_in    =perguntarNum('  Diametro do tubo D_in [m]',D.D_in);
P.D_th    =perguntarNum('  Diametro da garganta D_th [m]',D.D_th);
P.L_total =perguntarNum('  Comprimento total L_total [m]',D.L_total);
P.L_throat=perguntarNum('  Comprimento da garganta L_throat [m]',D.L_throat);
P.ang_conv=perguntarNum('  Angulo do cone convergente [graus]',D.ang_conv);
P.ang_div =perguntarNum('  Angulo do cone divergente [graus]',D.ang_div);
P.v_in    =perguntarNum('  Velocidade media de entrada v_in [m/s]',D.v_in);

fprintf('\nPerfil de velocidade na entrada:\n');
fprintf('  1) Parabolico - escoamento desenvolvido (padrao, mais realista)\n');
fprintf('  2) Uniforme (plug)\n');
P.perfil=perguntarNum('  Escolha [1]',1);

P=preencherPadroes(P);
fprintf('\n');
end

function P = preencherPadroes(P)
d.rho=998; d.mu=1.002e-3; d.v_in=0.015;
d.D_in=0.050; d.D_th=0.020; d.L_total=0.30; d.L_throat=0.02;
d.ang_conv=21; d.ang_div=7; d.material='PVC/plastico liso'; d.eps_abs=1.5e-6;
d.perfil=1;
f=fieldnames(d);
for k=1:numel(f)
    if ~isfield(P,f{k}) || isempty(P.(f{k})), P.(f{k})=d.(f{k}); end
end
end

function [nome,eps]=materialInfo(op,D)
switch op
    case 2, nome='Aco inoxidavel'; eps=0.015e-3;
    case 3, nome='Aco comercial';  eps=0.045e-3;
    case 4, nome='Ferro fundido';  eps=0.26e-3;
    case 5, nome='Concreto';       eps=1.0e-3;
    case 6, nome='Vidro (liso)';   eps=0.0;
    case 7
        eps=perguntarNum('  Rugosidade absoluta eps [mm]',D.eps_abs*1e3)*1e-3;
        nome='Personalizado';
    otherwise, nome='PVC/plastico liso'; eps=0.0015e-3;
end
end

function v = perguntarNum(txt,padrao)
resp=input(sprintf('%s [%g]: ',txt,padrao));
if isempty(resp) || ~isnumeric(resp), v=padrao; else, v=resp(1); end
end

% =======================================================================
%  NUMERICA
% =======================================================================
function R=Rwall_profile(z,R1,Rt,z1,z2,z3,z4)
R=R1*ones(size(z));
m1=z>=z1&z<z2; R(m1)=R1+(Rt-R1).*(z(m1)-z1)./(z2-z1);
m2=z>=z2&z<z3; R(m2)=Rt;
m3=z>=z3&z<z4; R(m3)=Rt+(R1-Rt).*(z(m3)-z3)./(z4-z3);
end

function [Adec,idmap]=build_poisson(fluid,Nz,Nr,dz,dr,rc)
% Matriz do Laplaciano axissimetrico de pressao (Neumann em paredes/eixo/
% entrada; Dirichlet p=0 fantasma na saida), fatorada uma unica vez.
idmap=zeros(Nz,Nr); idmap(fluid)=1:nnz(fluid); N=nnz(fluid);
I=zeros(5*N,1); J=I; S=I; c=0; az=1/dz^2;
for i=1:Nz
  for j=1:Nr
    if ~fluid(i,j), continue; end
    n=idmap(i,j);
    arP=1/dr^2+1/(2*dr*rc(j)); arM=1/dr^2-1/(2*dr*rc(j)); d=0;
    if i>1 && fluid(i-1,j), c=c+1; I(c)=n; J(c)=idmap(i-1,j); S(c)=az; d=d-az; end
    if i<Nz && fluid(i+1,j), c=c+1; I(c)=n; J(c)=idmap(i+1,j); S(c)=az; d=d-az;
    elseif i==Nz,           d=d-az; end
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

function f=fatorAtrito(Re,epsRel)
% Darcy: laminar 64/Re; turbulento Swamee-Jain (Colebrook explicita)
Re=max(Re,1e-6);
f_lam=64./Re;
f_turb=0.25./(log10(epsRel/3.7+5.74./Re.^0.9)).^2;
lam=Re<2300; f=f_turb; f(lam)=f_lam(lam);
end

function out=ternario(cond,a,b)
if cond, out=a; else, out=b; end
end
