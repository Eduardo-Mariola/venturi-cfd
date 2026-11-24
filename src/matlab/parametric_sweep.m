function parametric_sweep()
%PARAMETRIC_SWEEP  Ten-case sensitivity study with venturi_ns_avancado.
%   Runs the parameterized Navier-Stokes solver (Model B) on the production
%   mesh, changing one parameter at a time with respect to the reference case
%   (water, v_in = 0.015 m/s, D_in = 50 mm, D_th = 20 mm, 21/7 deg cones,
%   Poiseuille inlet). The console report of each case is appended to
%   results/sweep/sweep_log.txt and the figures are copied with a case tag.
%   These are the cases of Table 2 in the SoftwareX article.
%
%   Usage (from src/matlab):  >> parametric_sweep

outdir = fullfile(pwd, '..', '..', 'results', 'sweep');
if ~exist(outdir, 'dir'), mkdir(outdir); end
logf = fullfile(outdir, 'sweep_log.txt');
fid = fopen(logf, 'w'); fclose(fid);

C = {};
C{end+1} = struct('tag', 'reference_v015',  'p', struct());
C{end+1} = struct('tag', 'v010',            'p', struct('v_in', 0.010));
C{end+1} = struct('tag', 'v020',            'p', struct('v_in', 0.020));
C{end+1} = struct('tag', 'v030',            'p', struct('v_in', 0.030));
C{end+1} = struct('tag', 'dth15_beta030',   'p', struct('D_th', 0.015));
C{end+1} = struct('tag', 'dth25_beta050',   'p', struct('D_th', 0.025));
C{end+1} = struct('tag', 'angdiv05',        'p', struct('ang_div', 5));
C{end+1} = struct('tag', 'angdiv12',        'p', struct('ang_div', 12));
C{end+1} = struct('tag', 'plug_inlet',      'p', struct('perfil', 2));
C{end+1} = struct('tag', 'air20C',          'p', struct('rho', 1.204, 'mu', 1.82e-5));

for k = 1:numel(C)
    tag = C{k}.tag;
    fprintf('\n>>>>>> CASE %d/%d : %s\n', k, numel(C), tag);
    t0 = tic;
    try
        out = evalc('venturi_ns_avancado(''padrao'', C{k}.p)');
    catch ME
        out = sprintf('ERROR: %s\n', ME.message);
    end
    dt = toc(t0);
    fid = fopen(logf, 'a');
    fprintf(fid, '\n\n########## CASE: %s  (%.1f s) ##########\n', tag, dt);
    fprintf(fid, '%s', out);
    fclose(fid);
    figs = {'velocidade', 'pressao', 'perfis_eixo', 'perdacarga', 'perfis_radiais'};
    for j = 1:numel(figs)
        src = sprintf('venturi_ns_adv_%s.png', figs{j});
        if exist(src, 'file')
            copyfile(src, fullfile(outdir, sprintf('%s_%s.png', tag, figs{j})));
        end
    end
    fprintf('   done in %.1f s\n', dt);
end
fprintf('\nSweep finished. Log: %s\n', logf);
end
