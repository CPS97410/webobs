function DOUT=sismolb(mat,tlim,OPT,nograph)
%SISMOLB Graphes de la sismicit� continue Large-Bande OVSG.
%       SISMOLB sans option charge les donn�es les plus r�centes du FTP
%       et retrace tous les graphes pour le WEB.
%
%       SISMOLB(MAT,TLIM,OPT,NOGRAPH) effectue les op�rations suivantes:
%           MAT = 1 (d�faut) utilise la sauvegarde Matlab (+ rapide);
%           MAT = 0 force l'importation de toutes les donn�es anciennes �
%               partir des fichiers FTP et recr�� la sauvegarde Matlab.
%           TLIM = DT ou [T1;T2] trace un graphe sp�cifique ('_xxx') sur 
%               les DT derniers jours, ou entre les dates T1 et T2, au format 
%               vectoriel [YYYY MM DD] ou [YYYY MM DD hh mm ss].
%           TLIM = 'all' trace un graphe de toutes les donn�es ('_all').
%           OPT.fmt = format de date (voir DATETICK).
%           OPT.mks = taille des marqueurs.
%           OPT.cum = p�riode de cumul pour les histogrammes (en jour).
%           OPT.dec = d�cimation des donn�es (en nombre d'�chantillons).
%           NOGRAPH = 1 (optionnel) ne trace pas les graphes.
%
%       DOUT = SISMOLB(...) renvoie une structure DOUT contenant toutes les 
%       donn�es :
%           DOUT.code = code station
%           DOUT.time = vecteur temps
%           DOUT.data = matrice de donn�es trait�es (NaN = invalide)
%
%       Sp�cificit�s du traitement:
%           - lecture des fichiers binaires GeoSIG *.DAT grace � la fonction "loadgsig.m"
%           - �tat des stations sismiques par calcul du bruit et de l'offset
%           - tambour 24 h par station (signaux amplifi�s et corrig�s de l'offset)
%
%   Auteurs: F. Beauducel + S. Bazin, OVSG-IPGP
%   Cr�ation : 2003-04-30
%   Mise � jour : 2013-01-11

% ===================== Chargement de toutes les donn�es disponibles

X = readconf;

if nargin < 1, mat = 1; end
if nargin < 2, tlim = []; end
if nargin < 4, nograph = 0; end

% Initialisation des variables

rcode = 'SISMOLB';
timelog(rcode,1)
stype = 'T';

G = readgr(rcode);
tnow = datevec(G.now);
ST = readst(G.cod,G.obs);

G.sta = {rcode};
G.ali = {rcode};

% Initialisation des constantes
fhz = 100;                                  % fr�quence d'�chantillonnage (Hz)
samp = 1/(86400*fhz);                       % pas d'�chantillonnage des donn�es (en jour)
vmm = 1;                                    % offset max
vsn = 0;                                    % bruit min
vsm = 2;                                    % bruit max (pour �chelle tambour uniquement)
gris = .8*[1,1,1];                          % couleur grise

tlim = 1;                                   % tampon donn�es (en jour)
dec = 20;                                   % d�cimation des donn�es (ATTENTION: d�finit la taille du tampon)
sz = round(tlim/samp/dec);                  % taille du tampon
dt = 15/1440;                               % largeur des tambours (et arrondi)
dtf = 6/1440;                               % d�lai de recouvrement entre fichiers

sname = 'Sismologie Large-Bande';
G.cpr = 'OVSG-IPGP';
pftp = sprintf('%s/%s',X.RACINE_FTP,G.ftp);
ftmp = sprintf('%s/tmp/sismolb_lst.dat',X.RACINE_OUTPUT_MATLAB);
pdon = sprintf('%s/geosig',X.RACINE_SIGNAUX_SISMO);
ptam = sprintf('%s/graphes/tambours',X.RACINE_SIGNAUX_SISMO);
prog = X.PRGM_CONVERT;

% Importation des stations sismiques
ix = find(~strcmp(ST.dat,'-'));
nx = length(ix);
nbv = 3;
vn0 = {'Z','NS','EW'};  vn = vn0;
vu0 = 'mm/s';  vu = {vu0,vu0,vu0};
tlv = nan(1,nbv);
etats = zeros(length(ST.cod),1);
acquis = zeros(length(ST.cod),1);
tmmax = zeros(length(ST.cod),1);

for si = 1:nx
    st = ix(si);
    scode = lower(ST.cod{st});
    
    % Test: chargement si la sauvegarde Matlab existe
    f_save = sprintf('%s/past/%s_past.mat',X.RACINE_OUTPUT_MATLAB,scode)
    if mat & exist(f_save,'file')
        load(f_save,'t','d','vn','vu','tlv');
        disp(sprintf('Fichier: %s import�.',f_save))
        % date plus ancienne donn�e sauv�e
        for i = 1:length(tlv)
		if ~isnan(tlv(i))
		    disp(sprintf('- Derni�re mesure voie n�%d : %s',i,datestr(tlv(i))))
		else
		    disp(sprintf('- Derni�re mesure voie n�%d : unknown',i))
		end
        end
        tdeb = rmin(tlv);
        if isnan(tdeb)
            tdeb = datenum(tnow) - tlim;
            tlv = [tdeb,tdeb,tdeb];
        end
        disp(sprintf('- Date d�but chargement : %s',datestr(tdeb)))
        % effacement des donn�es anciennes (arrondi � dt)
        %k = find(t > rmax(tlv) | t < ceil((datenum(tnow) - tlim)/dt)*dt);
        k = find(t > rmax(tlv) | t < (datenum(tnow) - tlim));
        t(k) = NaN;
        d(k,:) = NaN;
    else
        disp('Pas de sauvegarde Matlab. Chargement de toutes les donn�es...');
        tdeb = datenum(tnow) - tlim;
        t = NaN*zeros(sz,1);
        d = NaN*zeros(sz,nbv+1);
    end

    tt0 = datevec(tdeb);

    % Importation des fichiers de donn�es GeoSIG (.DAT)
    sn = ST.dat{st};
    %dir0 = sprintf('%s/%s/',pdon,sn);
    for i = 0:2
        [s,ss] = unix(sprintf('find %s -type f -name "%s*.dat" -mtime -1 -printf "%%f\\n"',pdon,sn));
		if ~isempty(ss)
	        fn = strread(ss,'%s');
		else
			fn = [];
		end
        %unix(sprintf('ls -t %s%s__CH%d* > %s',dir0,sn,i,ftmp));
        %fn = flipud(textread(ftmp,[dir0 '%s']));
        for j = 1:length(fn)
            tz = sscanf(fn{j},[sprintf('%s__CH%d_',sn,i) '%04d%02d%02d_%02d%02d%02d'])';
            if datenum(tz) >= (tdeb - dtf)
                [dd,bb,ss,fs] = loadgsig(sprintf('%s/%d%02d%02d/%s/%s',pdon,tz(1:3),sn,fn{j}));
                if ~isempty(dd)
                    ii = [bb(:,3);length(dd)+1];
                    for ib = 1:size(bb,1)
                        ddb = dd(ii(ib):(ii(ib+1)-1));
                        ttb = bb(ib,1) + (0:(diff(ii(ib:(ib+1))))-1)*samp;
                        ttt = ttb(1:dec:end);
                        ddd = ddb(1:dec:end);
                        %ttt = rdecim(ttb,dec);
                        %ddd = rdecim(ddb,dec);
                        ccc = ones(size(ddd))*(bb(ib,2) == 2);
                        k = floor(mod(ttt,1)/samp/dec) + 1;
                        %kv = find(strcmp(deblank(ss(2)),vn0));
                        t(k) = ttt;
                        d(k,i+1) = ddd;
                        if i == 0
                            d(k,nbv+1) = ccc;
                        end
                        vn(i+1) = deblank(ss(2));
                        vu(i+1) = deblank(ss(3));
                    end
                    disp(sprintf('Fichier: %s import�.',fn{j}))
                end
                tlv(i+1) = ttt(end);
            end
        end
        %delete(ftmp);
    end
 
    % Sauvegarde Matlab
    save(f_save);
    disp(sprintf('Fichier: %s cr��.',f_save))

    tm = rmax(tlv);
    tmmax(st) = tm;

    k = find(t > (tm - G.lst));
    if ~isempty(k)
        % Calcul d'offset et de bruit
        mx = minmax(d(k,1:nbv));
        moy = rmean(d(k,1:nbv));
        ety = rstd(d(k,1:nbv));
        eac = tm > (datenum(tnow)-G.lst);
        eta = (abs(moy) <= vmm) & (ety >= vsn & ety <= 2*vsm);
    else
        eta = zeros(1,nbv);
        eac = 0;
        moy = NaN*zeros(1,nbv);
        ety = NaN*zeros(1,nbv);
    end

    % Etat des voies
    etats(st) = 100*mean(eta)*eac;
    acquis(st) = 100*length(find(~isnan(t)))/sz;;
    sd = sprintf('%s %1.4f � %1.5f %s, %s %1.4f � %1.5f %s, %s %1.4f � %1.5f %s', ...
                  vn{1},moy(1),ety(1),vu{1},vn{2},moy(2),ety(2),vu{2},vn{3},moy(3),ety(3),vu{3});
    if mat ~= -1
        mketat(etats(st),tm,sd,lower(ST.cod{st}),G.utc,acquis(st))
    end

    t2 = ceil(datenum(tnow)/dt)*dt;
    t1 = t2 - tlim - dt;
    scd = 1;
    rsx = dt/samp/dec;
    itnow = floor(mod(t2,1)/samp/dec) + 1;
    kt = mod((1:sz)' + itnow,sz) + 1;

    % ====================================================================================================
    % Graphes des tambours 24 h
    tt = reshape(t(kt),[rsx sz/rsx])';
    ttt = (t1:dt:t2)';
    rcol = [0,0,0;1,0,0;0,0,.8;0,.6,0];
    stn = ST.cod{st};
    for iv = 0:2
        stitre = sprintf('%s\\_%d: %s %s',upper(ST.ali{st}),iv,ST.nom{st},vn{iv+1});
        dd = reshape(d(kt,iv+1),[rsx sz/rsx])';
        bruit = rstd(dd(:));
        scdd = scd;
        if bruit > vsm
            scdd = scd*5;
        end
        figure(1), clf, orient tall

        G.tit = gtitle(stitre,'24h');
        G.eta = [t2,etats(st),acquis(st)];
		
        if ~isempty(find(~isnan(d)))
            k = find(d(:,end) == 0);
            if ~isempty(k)
                co = sprintf('{\\bfHorloge:} Probl�me de GPS (%d%%) !',round(100*length(k)/length(t)));
			else
			    co = ' ';
            end
            G.inf = {sprintf('Derni�re mesure: {\\bf%s} {\\it%+d}',datestr(tlv(iv+1)),G.utc), ...
                    sprintf('Composante n�%d = {\\bf%s}',iv,vn{iv+1}), ...
                    sprintf('Echelle = {\\bf1/%g}',scdd/scd), ...
                    co, ...
                    sprintf('Offset signal = {\\bf%+1.4f} %s',moy(iv+1),vu{iv+1}), ...
                    sprintf('Bruit signal = {\\bf\\pm%1.5f} %s',ety(iv+1),vu{iv+1}), ...
                    sprintf('Bruit total = {\\bf%+1.5f} %s',bruit,vu{iv+1}), ...
                };
    
            subplot(1,1,1), extaxes
			pos = get(gca,'position');
			set(gca,'Position',[pos(1)-.01,pos(2)-.01,pos(3:4)])
			
            i5 = (1:14)'/(samp*dec*1440);
            plot([i5,i5]',[t1*ones(size(i5)),t2*ones(size(i5))]','Color',gris,'LineWidth',1)
            hold on
            for i = 1:(length(ttt) - 1)
                c = rcol(mod(floor(ttt(i)/dt),4)+1,:);
                %if find(~d(i,end)), c = gris; end
                if i == 1, ii = size(tt,1); else ii = i - 1; end
                ddd = NaN*dd(ii,:);
                k = find(tt(ii,:) > ttt(i) & tt(ii,:) < ttt(i+1));
                if ~isempty(k)
                    ddd(k) = dd(ii,k);
                    plot(ddd/scdd + ttt(i) - rmean(ddd)/scdd,'Color',c)
                end
            end
            hold off
            box on
            set(gca,'YLim',[t1-dt t2],'FontSize',8)
            set(gca,'XLim',[0 rsx],'XTick',0:(1/(samp*dec*1440)):sz,'XTickLabel',num2str((0:15)'))
            datetick('y',15,'keeplimits')
            tlabel([t1,t2],G.utc)
            h1 = gca;
            ytl = get(h1,'YTickLabel');
            if size(ytl,2) == 5, ytl(:,4:5) = repmat('15',length(ytl),1); end
            h2 = axes('Position',get(h1,'Position'));
            set(h2,'YLim',get(h1,'YLim'),'Color','none','Layer','top')
            set(h2,'XLim',get(h1,'XLim'),'XTick',get(h1,'XTick'),'XTickLabel',get(h1,'XTickLabel'),'XAxisLocation','top')
            set(h2,'YTick',get(h1,'YTick'),'YTickLabel',ytl,'YAxisLocation','right')
            set(h2,'FontSize',8)
        end

        mkgraph(sprintf('%s_%d_24h',lower(ST.cod{st}),iv),G)
        G.sta = [G.sta;{sprintf('%s_%d',lower(ST.cod{st}),iv)}];
        G.ali = [G.ali;{sprintf('%s_%s',ST.ali{st},vn{iv+1})}];

        % Copie des images pour gravure quotidienne (jour courant)
	thier = datevec(datenum(tnow)-1);
        rep_tambours = sprintf('%s/%4d%02d%02d',ptam,thier(1:3));
        if ~exist(rep_tambours,'dir')
            unix(sprintf('mkdir -p %s',rep_tambours));
	end
        f = sprintf('%s/%4d%02d%02d_%s_%d_24h.png',rep_tambours,thier(1:3),lower(ST.cod{st}),iv);
        if ~exist(f,'file')
            unix(sprintf('cp -fpu %s/%s/%s_%d_24h.png %s',pftp,X.MKGRAPH_PATH_FTP,lower(ST.cod{st}),iv,f));
            disp(sprintf('Graphe: %s archiv� pour gravure.',f));
        end
        
    end

end


% ====================================================================================================
% Graphe de synth�se r�seau

%t2 = rmax(tmmax);
t2 = datenum(tnow);
t1 = t2 - tlim;
ddec = 5;          % d�cimation suppl�mentaire (= 1 Hz)
xlim = [0 sz/ddec];
dtt = 1/24;
tti = ((ceil(t1/dtt)*dtt):dtt:(floor(t2/dtt)*dtt))';
itt = (tti - t1)/samp/dec/ddec;
tts = datestr(tti,15);

etat = mean(etats(ix));
acqui = max(acquis(ix));
if mat ~= -1
    mketat(etat,t2,sprintf('%s %d stations',stype,nx),rcode,G.utc,acqui)
end

figure(1), clf, orient tall
stitre = sprintf('%s: %s',rcode,sname);
G.tit = gtitle(stitre,'24h');
G.eta = [t2,etat,acqui];
G.inf = {'Derni�re mesure:',sprintf('{\\bf%s} {\\it%+d}',datestr(t2),G.utc),' ',' '};
for i = 1:nx
    G.inf = [G.inf,{sprintf('%02d. {\\bf%s} : %s',i,ST.ali{ix(i)},ST.nom{ix(i)})}];
end

for si = 1:nx
    st = ix(si);
    scode = lower(ST.cod{st});
    
    f_save = sprintf('%s/past/%s_past.mat',X.RACINE_OUTPUT_MATLAB,scode);
    load(f_save,'t','d','vn','vu');
    disp(sprintf('Fichier: %s import�.',f_save))
    itnow = floor(mod(t2,1)/samp/dec) + 1;
    kt = mod((1:sz)' + itnow,sz) + 1;
    dd = d(kt,1:3);

    subplot(2*nx,1,2*(si-1)+(1:2)), extaxes
    plot(dd(1:ddec:end,:))
    set(gca,'XLim',xlim,'XTick',itt,'XTickLabel',tts(:,1:2))
    set(gca,'FontSize',8)
    ylabel(sprintf('%s (%s)',ST.ali{st},vu{1}))
    if isempty(find(~isnan(dd))), nodata(xlim), end
    if si == 1
        h = legend(vn,2);
    end
end
tlabel([t1,t2],G.utc)
    
mkgraph(sprintf('%s_24h',rcode),G)

close(1)

G.ext = [{'ico'};G.ext];
htmgraph(G);


timelog(rcode,2)
