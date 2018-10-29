function shakemaps(mat,n)
%SHAKEMAPS Traitement des s�ismes ressentis
%       SHAKEMAPS traite le dernier s�isme localis� (hypoovsg.txt) et calcule le PGA th�orique
%       sur l'archipel de Guadeloupe (loi d'att�nuation [OVSG, 2004;2009]). Si une zone d�passe 
%       un seuil d'acc�l�ration, un communiqu� est produit et envoy� par e-mail.
%
%       SHAKEMAPS(MAT,N) recharge les informations g�ographiques (lignes de cotes, villes, etc...)
%       si MAT == 0 et fait le traitement sur les N derniers s�ismes localis�s. Si N <= 0, fait
%       le calcul sur un s�isme test -N.

%   Auteur: F. Beauducel, OVSG-IPGP
%   Cr�ation : 2005-01-12
%   Mise � jour : 2009-08-17

%   Autres fonctions n�cessaires � ce script:
%       WEBOBS: readconf.m, timelog.m, readhyp.m
%       G�n�rales: attenuation.m, pga2msk.m, msk2str.m, arrondi.m, pcontour.m

X = readconf;

rcode = 'SHAKEMAPS';
timelog(rcode,1);

if nargin < 1,  mat = 1;  end
if nargin < 2,  n = 1;  end

if n <= 0
    test = abs(n) + 1;
    n = 1;
else
    test = 0;
end

% ---------------------------------------------------------------------- %
% D�finition des variables
% ---------------------------------------------------------------------- %

pgra = sprintf('%s/%s',X.RACINE_FTP,X.SHAKEMAPS_PATH_FTP);
pres = sprintf('%s/%s',X.SHAKEMAPS_PATH_FTP,X.SHAKEMAPS_PATH_FELT);


lieu = X.LIEU_VILLE;                            % Lieu de r�daction du communiqu�
loi = 2;                                        % loi d'att�nuation utilis�e (voir attenuation.m)
% limites carte hypo (en �)
xylim = [str2double(X.SHAKEMAPS_MAP_LON1), ...
         str2double(X.SHAKEMAPS_MAP_LON2), ...
         str2double(X.SHAKEMAPS_MAP_LAT1), ...
         str2double(X.SHAKEMAPS_MAP_LAT2)];
dxy = str2double(X.SHAKEMAPS_MAP_DXY);           % pas de la grille XY (en �)
pgamin = str2double(X.SHAKEMAPS_PGA_MIN);       % PGA minimum (en milli g)
nbsig = 2;                                       % nombre de chiffres significatifs pour PGA affich�s
dhpmin = str2double(X.SHAKEMAPS_MIN_DISTANCE);	% distance hypocentrale minimale (effet de saturation) en km
f = sprintf('%s/%s',X.RACINE_FICHIERS_CONFIGURATION,X.SHAKEMAPS_MAGNITUDE_FILE);
[xmag,nommag] = textread(f,'%n%q','commentstyle','shell');
fprintf('WEBOBS: %s imported.\n',f);
f = sprintf('%s/%s',X.RACINE_FICHIERS_CONFIGURATION,X.SHAKEMAPS_MSK_FILE);
[mskscale,lwmsk,nommsk,nomres,nomdeg] = textread(f,'%n%n%q%q%q','commentstyle','shell');
fprintf('WEBOBS: %s imported.\n',f);
pgamsk = (10.^((mskscale - 1.5)/3));       % limites PGA [Gutenberg &  Richter, 1942]
txtb3 = sprintf('WEBOBS %s %s - %s',X.SHAKEMAPS_COPYRIGHT,datestr(now,'yyyy'),X.SHAKEMAPS_INFOS);

latkm = 6370*pi/180;                            % valeur du degr� latitude (en km)
lonkm = latkm*cos(16*pi/180);                   % valeur du degr� longitude (en km)
gris = .8*[1,1,1];                              % couleur gris clair
mer = [.7,.9,1];                                % couleur bleu mer
ppi = 150;                                      % r�solution PPI

% Colormap JET d�grad�e
sjet = jet(256);
z = repmat(linspace(0,.9,length(sjet))',1,3);
sjet = sjet.*z + (1-z);

% Construction de la grille XY
[x,y] = meshgrid(xylim(1):dxy:xylim(2),xylim(3):dxy:xylim(4));


%!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
% DEBUG
% Faire une boucle pour utiliser tous les hypoovsg_* ou remplacer tail
%!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
f1 = sprintf('%s/%s/%s',X.RACINE_FTP,X.SISMOHYP_PATH_FTP,X.SHAKEMAPS_HYPO_FILE);
f2 = sprintf('%s/lasthypo.txt',pgra);
f3 = sprintf('%s/lasthypo.pdf',pgra);
f4 = sprintf('%s/lasthypo.jpg',pgra);
ftmp = '/tmp/lasthypo.ps';
mtmp = '/tmp/mailb3.txt';
ttmp = '/tmp/hypob3.txt';
flogo1 = sprintf('%s/%s',X.RACINE_DATA_MATLAB,X.SHAKEMAPS_LOGO1);
%flogo2 = sprintf('%s/%s',X.RACINE_WEB,X.IMAGE_LOGO_OVSG);
flogo3 = sprintf('%s/%s',X.RACINE_DATA_MATLAB,X.SHAKEMAPS_LOGO2);

% ---------------------------------------------------------------------- %
% Chargement de la sauvegarde Matlab ou reconstruction
% ---------------------------------------------------------------------- %

f_save = sprintf('%s/past/%s_past.mat',X.RACINE_OUTPUT_MATLAB,rcode);
if mat & exist(f_save,'file')
    load(f_save,'c_pta','A1','A3');
    disp(sprintf('File: %s imported.',f_save))
else
    disp('No Matlab backup (or forced). Loading all data...');
    f = sprintf('%s/antille2.bln',X.RACINE_DATA_MATLAB);
    c_ant = ibln(f);
    c_pta = econtour(c_ant,[],xylim);
    A1 = imread(flogo1);
    %A2 = imread(flogo2);
    A3 = imread(flogo3);
   
    save(f_save);
    disp(sprintf('File: %s saved.',f_save))
end

f = sprintf('%s/%s',X.RACINE_FICHIERS_CONFIGURATION,X.SHAKEMAPS_COMMUNES_FILE);
[IC.typ,IC.lon,IC.lat,IC.nom,IC.ile,IC.efs] = textread(f,'%n%n%n%q%q%n','delimiter','|','commentstyle','shell');
CS = codeseisme;
tsok = find(~strcmp(CS.cb3,''));			% types de s�isme OK pour calcul B3 (voir "codeseisme.m")


% ---------------------------------------------------------------------- %
% Chargement des derniers s�ismes localis�s ou des simulations
% ---------------------------------------------------------------------- %

if test
    f = sprintf('%s/%s',X.RACINE_DATA_MATLAB,X.SHAKEMAPS_HYPOSIMUL_FILE);
    DH = readhyp(f);
    if test > length(DH.tps)
        error('%s: simulation n�%d does not exist in %s',rcode,test,f);
    end
    i_loop = test-2;
else
	% le tail syr hypoovsg_* renvoie les N derniers depouillements de chaque fichier
    unix(sprintf('tail -q -n %d %s > %s',n + 1,f1,ttmp));    % NB: N + 1 car READHYP ignore la premi�re ligne du fichier TTMP
    DH = readhyp(ttmp);
    i_loop = 1:length(DH.tps);
    fprintf('%d events found in %s...\n',length(DH.tps),f1);
end

% ---------------------------------------------------------------------- %
% Boucle principale sur tous les s�ismes � traiter
% ---------------------------------------------------------------------- %

i_first = 1;

for i = i_loop

	vtps = datevec(DH.tps(i));
    fnam = sprintf('%4d%02d%02dT%02d%02d%02.0f_b3',vtps);
	pam = sprintf('%4d/%02d',vtps(1:2));
    if test
        fgra = sprintf('%s/%s/%s.pdf',pgra,X.SHAKEMAPS_PATH_SIMULATION,fnam);
		ftxt = sprintf('%s/%s/%s.txt',pgra,X.SHAKEMAPS_PATH_SIMULATION,fnam);
		fgse = sprintf('%s/%s/%15s_gse.txt',pgra,X.SHAKEMAPS_PATH_SIMULATION,fnam);
        fico = sprintf('%s/%s/%s.jpg',pgra,X.SHAKEMAPS_PATH_SIMULATION,fnam);
    else
        fgra = sprintf('%s/%s/%s/%s.pdf',pgra,X.SHAKEMAPS_PATH_FELT,pam,fnam);
		unix(sprintf('mkdir -p %s/%s/%s',pgra,X.SHAKEMAPS_PATH_FELT,pam));
		ftxt = sprintf('%s/%s/%s/%s.txt',pgra,X.SHAKEMAPS_PATH_TREATED,pam,fnam);
		unix(sprintf('mkdir -p %s/%s/%s',pgra,X.SHAKEMAPS_PATH_TREATED,pam));
		fgse = sprintf('%s/%s/%s/%15s_gse.txt',pgra,X.SHAKEMAPS_PATH_GSE,pam,fnam);
		unix(sprintf('mkdir -p %s/%s/%s',pgra,X.SHAKEMAPS_PATH_GSE,pam));
        fico = sprintf('%s/%s/%s/%s.jpg',pgra,X.SHAKEMAPS_PATH_FELT,pam,fnam);
    end

    if i_first
        figure, orient('tall')
        set(gcf,'PaperUnit','inches','PaperType','A4');
        pps = [.2,.25,7.8677,11.2929];
        set(gcf,'PaperPosition',pps);
        i_first = 0;
    end
   
    
    if (~exist(ftxt,'file') | test) & ~isempty(find(DH.typ(i) == tsok))
		tnow = now;
		%Pour mettre � jour les cartes en gardant la date de cr�ation du communiqu�...
		%if ~test & exist(fgra,'file')
		%    D = dir(fgra);
		%    tnow = datesys2num(D.date);
		%end

        lonkm = latkm*cos(DH.lat(i)*pi/180);    % longueur du degr� de longitude � hauteur de l'�picentre
        
        % calcul des distances hypocentrales pour toutes les communes
		vdhp = sqrt(((IC.lon - DH.lon(i))*lonkm).^2 + ((IC.lat - DH.lat(i))*latkm).^2 + DH.dep(i).^2);
		
        % saturation en champ proche (dhpmin)
        k = find(vdhp < dhpmin);
		vdhp(k) = dhpmin;
        
        % calcul du PGA moyen et des intensit�s (min,moy,max) pour toutes les communes
		vpga = 1000*attenuation(loi,DH.mag(i),vdhp);
        vmsk = pga2msk(repmat(vpga,1,3).*[1./IC.efs,ones(size(vpga)),IC.efs],'gutenberg');
        vmsk(find(vmsk < 1)) = 1;
		
        
        % tri toutes les communes par ordre d�croissant des PGA (avec effets de site): iv = indices tri�s
        [xx,iv] = sort(-vpga.*IC.efs);
        
        % d�cide si on fabrique un communiqu� (s�isme potentiellement ressenti)
        % -- note: volontairement, le crit�re n'est pas intensit� >= II, mais PGA >= PGAmin, 
        % afin de pouvoir sortir un communiqu� ind�pendamment de la relation PGA/intensit�s.
        % on fabrique �galement le commnuniqu� si le code msk est sup�rieur ou �gal � 2 - JMS
        [max_pga,imax] = max(vpga.*IC.efs);
        if (max_pga >= pgamin & (str2double(X.SHAKEMAPS_FELTOTHERPLACES_OK) | IC.typ(imax) == str2double(X.SHAKEMAPS_COMMUNES_PLACE))) | (DH.msk(i) >= 2)
            ress = 1;
        else
            ress = 0;
        end

        % archivage du traitement (toutes les communes)
        fid = fopen(ftxt,'wt');
        fprintf(fid,repmat('#',1,80));
        fprintf(fid,'\n# Automatic shakemaps using B3 attenuation law [Beauducel et al., 2004, 2009]\n');
        fprintf(fid,'# Date: %s (local time)\n',datestr(tnow));
        fprintf(fid,'# Hypocenter OVSG-IPGP:\n');
        fprintf(fid,'#\tTime (UT) = %s\n#\tMD = %1.1f\n#\tType = %s\n',datestr(DH.tps(i)),DH.mag(i),CS.nom{DH.typ(i)});
        fprintf(fid,'#\tLatitude = %g N\n#\tLongitude = %g E\n#\tDepth = %g km\n',DH.lat(i),DH.lon(i),DH.dep(i));
        fprintf(fid,'#\n# Hypocentral distances (km) and computed PGA (mg), using site effets\n');
        fprintf(fid,'# for each town, and corresponding intensity MSK [Gutenberg & Richter, 1942]:\n#\n');
        fprintf(fid,'#                    Town/Island, site,  dHyp, PGA_min, PGA_mean, PGA_max, MSK_min, MSK_mean, MSK_max\n#\n');
        for ii = 1:length(vpga)
            fprintf(fid,'%35s, %g, %5.1f, %8.4f, %8.4f, %8.4f, %6s, %6s, %6s\n', ...
                [IC.nom{iv(ii)},'/',IC.ile{iv(ii)}],IC.efs(iv(ii)),vdhp(iv(ii)),vpga(iv(ii))*[1/IC.efs(iv(ii)),1,IC.efs(iv(ii))], ...
                msk2str(vmsk(iv(ii),1)),msk2str(vmsk(iv(ii),2)),msk2str(vmsk(iv(ii),3)));
        end
        fprintf(fid,repmat('#',1,80));
        fclose(fid);
        disp(sprintf('File: %s created.',ftxt));
        
        % ------------------------------------------------------------------------------
        % Si ressenti, contruction du communiqu� et traitements
        if ress | test
            clf            
            
            % tri des communes du d�partement local
            kdpt = iv(find(IC.typ(iv) == str2double(X.SHAKEMAPS_COMMUNES_PLACE)));
            % indice de la commune la plus proche
            kepi = kdpt(1);
            % s�lection des communes du d�partement � afficher
            kcom = kdpt(find(vpga(kdpt).*IC.efs(kdpt) >= pgamin));

            % s�lection des communes des autres �les � afficher
            kile = iv(find((vpga(iv).*IC.efs(iv) >= pgamin) & (IC.typ(iv) ~= str2double(X.SHAKEMAPS_COMMUNES_PLACE))));           
            % unification (1 seule commune par �le)
            %[xx,k] = unique(IC.typ(kile),'first'); % NOTE: option inexistante sous Matlab 6...
            [xx,k] = unique(flipud(IC.typ(kile)));
            kile = kile(length(kile)-k+1);
            [xx,k] = sort(-vpga(kile).*IC.efs(kile));
            kile = kile(k);
                        
            isz1 = size(A1);
            %isz2 = size(A2);
            isz3 = size(A3);

            pos = [0.03,1-isz1(1)/(ppi*pps(4)),isz1(2)/(ppi*pps(3)),isz1(1)/(ppi*pps(4))];
            % logo
            h1 = axes('Position',pos,'Visible','off');
            image(A1), axis off
            %pos = [sum(pos([1,3])),1-isz2(1)/(ppi*pps(4)),isz2(2)/(ppi*pps(3)),isz2(1)/(ppi*pps(4))];
            %h2 = axes('Position',pos,'Visible','off');
            %image(A2), axis off
            % en-tete
            h3 = axes('Position',[sum(pos([1,3]))+.03,pos(2),.95-sum(pos([1,3])),pos(4)]);
            if test
                text(.3,0,'SIMULATION','FontSize',72,'FontWeight','bold','Color',[1,.8,.8],'Rotation',15,'HorizontalAlignment','center');
            end
            text(0,1,{'Rapport pr�liminaire de s�isme concernant',sprintf('%s',X.SHAKEMAPS_PLACE)}, ...
                'VerticalAlignment','top','FontSize',16,'FontWeight','bold','Color',.3*[0,0,0]);
            text(0,0,{X.SHAKEMAPS_ADDRESS1,X.SHAKEMAPS_ADDRESS2,X.SHAKEMAPS_ADDRESS3}, ...
                 'VerticalAlignment','bottom','FontSize',8,'Color',.3*[0,0,0]);
            set(gca,'YLim',[0,1]), axis off
            % logo B3
            pos = [.95 - isz3(2)/(ppi*pps(4)),1-isz3(1)/(ppi*pps(4)),isz3(2)/(ppi*pps(3)),isz3(1)/(ppi*pps(4))];
            h4 = axes('Position',pos,'Visible','off');
            image(A3), axis off

            % titre
            h5 = axes('Position',[.05,.73,.9,.17]);
            if ress
                text(1,1,sprintf('%s, le %s %s %s %s locales',lieu,datestr(tnow,'dd'),traduc(datestr(tnow,'mmm')),datestr(tnow,'yyyy'),datestr(tnow,'HH:MM')), ...
                     'horizontalAlignment','right','VerticalAlignment','top','FontSize',10);
            end
            dtiso = sprintf('%s-%s-%s %s TU',datestr(DH.tps(i),'yyyy'),datestr(DH.tps(i),'mm'),datestr(DH.tps(i),'dd'),datestr(DH.tps(i),'HH:MM:SS'));
            dtu = sprintf('%s %s %s %s %s TU',traduc(datestr(DH.tps(i),'ddd')),datestr(DH.tps(i),'dd'),traduc(datestr(DH.tps(i),'mmm')),datestr(DH.tps(i),'yyyy'),datestr(DH.tps(i),'HH:MM:SS'));
            dtl = sprintf('{\\bf%s %s %s %s � %s}',traduc(datestr(DH.tps(i)-4/24,'ddd')),datestr(DH.tps(i)-4/24,'dd'),traduc(datestr(DH.tps(i)-4/24,'mmm')),datestr(DH.tps(i)-4/24,'yyyy'),datestr(DH.tps(i)-4/24,'HH:MM'));
            text(.5,.7,{sprintf('Magnitude %1.1f, %05.2f�N, %05.2f�W, profondeur %1.0f km',DH.mag(i),DH.lat(i),-DH.lon(i),DH.dep(i)),dtu}, ...
                 'horizontalAlignment','center','VerticalAlignment','middle','FontSize',14,'FontWeight','bold');
            
            % Texte du communiqu� : param�tres � afficher
            s_qua = nommag{max([1,floor(DH.mag(i))])};
            s_mag = sprintf('%1.1f',DH.mag(i));
            s_vaz = boussole(atan2(DH.lat(i) - IC.lat(kepi),DH.lon(i) - IC.lon(kepi)),1);
			epi = sqrt(((IC.lon(kepi) - DH.lon(i))*lonkm).^2 + ((IC.lat(kepi) - DH.lat(i))*latkm).^2);
            %epi = sqrt(vdhp(iv(1))^2 - DH.dep(i)^2);
            if epi < 1
                s_epi = 'moins de 1 km';
            else
                s_epi = sprintf('%1.0f km',epi);
            end
            if ress
                s_gua = IC.nom{kepi};
            else
                s_gua = '???';
                vmsk = [1,1,1];
            end
            if DH.dep(i) < 1
                s_dep = 'moins de 1 km';
            else
                s_dep = sprintf('%1.0f km',DH.dep(i));
            end
			s_dhp = sprintf('%1.0f km',sqrt(epi^2 + DH.dep(i)^2));
	        s_typ = CS.cb3{DH.typ(i)};

            pga_aff = arrondi(vpga(kepi),nbsig);
            s_msk_aff = sprintf('de {\\bf%s} (%s)',msk2str(vmsk(kepi,2)),nommsk{floor(vmsk(kepi,2))});
            s_msk_max = sprintf('{\\bf%s} (%s)',msk2str(vmsk(kepi,3)),nommsk{floor(vmsk(kepi,3))});
            s_txt = {sprintf('Un %s (magnitude {\\bf%s} sur l''�chelle de Richter) a �t� enregistr� le %s',s_qua,s_mag,dtl), ...
                         sprintf('(heure locale) et identifi� d''origine {\\bf%s}. L''�picentre a �t� localis� �  {\\bf%s} %s de',s_typ,s_epi,s_vaz), ...
                         sprintf('{\\bf%s}, � %s de profondeur (soit une distance hypocentrale d''environ %s). Ce s�isme a pu',s_gua,s_dep,s_dhp), ...
                         sprintf('g�n�rer, dans les zones concern�es les plus proches, une acc�l�ration moyenne du sol de  {\\bf%g mg} (*),',pga_aff), ...
                         sprintf('correspondant � une intensit� macrosismique %s. Suivant le type de sols, les ',s_msk_aff), ...
                         sprintf('intensit�s peuvent cependant avoir atteint localement l''intensit� %s.',s_msk_max)};
                         %sprintf('intensit�s r�elles peuvent cependant varier de plus ou moins un degr�.entre %s et %s.',msk2str(vmsk(1,1)),msk2str(vmsk(1,3)))};
                         text(0,0,s_txt,'horizontalAlignment','left','VerticalAlignment','bottom','FontSize',10);
            set(gca,'XLim',[0,1],'YLim',[0,1]), axis off
            
            % ===========================================================
            % ---- carte
            % distance hypocentrale sur la grille XY
            dhp = sqrt(((x - DH.lon(i))*lonkm).^2 + ((y - DH.lat(i))*latkm).^2 + DH.dep(i).^2);
            % PGA sur la grille XY
            pga = 1000*attenuation(loi,DH.mag(i),dhp);

            %pos0 = [.092,.08,.836,.646];
            pos0 = [.055,.115,.9,.600];
            h5 = axes('Position',pos0);
            pcolor(x,y,log10(pga)), shading flat, colormap(sjet), caxis(log10(pgamsk([1,10])))
            hold on
            pcontour(c_pta,[],gris), axis(xylim)
            h = dd2dms(gca,0);
            set(h,'FontSize',7)
            msk = pga2msk(pga,'gutenberg');
            for ii = 2:10
                [cs,h] = contour(x,y,msk,[ii,ii]);
                set(h,'LineWidth',lwmsk(ii),'EdgeColor','k');
                if ~isempty(h)
                    hl = clabel(cs,h,'FontSize',40);
                    lb = get(hl,'UserData');
                    % replacing numbers by roman
                    for iii = 1:length(hl)
                        if iscell(lb)
                            lbb = lb{iii};
                        else
                            lbb = lb(iii);
                        end
                        set(hl(iii),'String',sprintf('%s',msk2str(lbb)),'FontWeight','bold','FontSize',12);
                    end
                end
            end
            % courbe limite ressenti avec effets de site
           [cs,h] = contour(x,y,pga2msk(pga*max(IC.efs),'gutenberg'),[2,2]);
            set(h,'LineStyle',':','LineWidth',.25,'EdgeColor','k');
                
            % �picentre
            plot(DH.lon(i),DH.lat(i),'p','MarkerSize',10,'MarkerEdgeColor','k','MarkerFaceColor','w','LineWidth',1.5)
            
            
            % ===========================================================
            % ---- tableau des communes et intensit�s moyennes et maximales
            hligne = .07;
            lrect = 1.3;
            if numel(kcom)
                ncom = numel(kcom);
            else
                ncom = 2;
            end
            hrect = (ncom + length(kile) + 2*(~isempty(kile)) + 3)*hligne;
            posx = xylim(1) + lrect/2 + .06;
            h = rectangle('Position',[xylim(1)+.05,xylim(3)+.05,lrect,hrect]);
            set(h,'FaceColor','w')
            h = rectangle('Position',[xylim(1)+.05,xylim(3)+hrect+.05-.16,lrect,.16]);
            set(h,'FaceColor','k')
            
            text(xylim(1)+.05+lrect/2,xylim(3)+.05+hrect, ...
                    {'{\bfIntensit�s probables moyennes}';'{\bf(et maximales) :}'}, ...
                    'HorizontalAlignment','center','VerticalAlignment','top','FontSize',8,'Color','w');
            %text(posx,xylim(3)+hrect-4*0.08,'moyenne','HorizontalAlignment','left','VerticalAlignment','bottom','FontSize',7);
            %text(posx+.32,xylim(3)+hrect-4*0.08,'(max.)','HorizontalAlignment','left','VerticalAlignment','bottom','FontSize',7);
            if numel(kcom) == 0
                posy = xylim(3)+hrect-4*hligne;
                text(posx,posy,{'Non ressenti dans les communes',sprintf('de %s.',X.SHAKEMAPS_PLACE)},'HorizontalAlignment','center','VerticalAlignment','bottom','FontSize',8)
            else
                for ii = 1:numel(kcom)
                    posy = xylim(3)+hrect-(ii+2)*hligne;
                    text(posx,posy,IC.nom{kcom(ii)},'HorizontalAlignment','right','VerticalAlignment','bottom','FontSize',8);
                    text(posx,posy,sprintf(' : {\\bf%s}',msk2str(vmsk(kcom(ii),2))),'HorizontalAlignment','left','VerticalAlignment','bottom','FontSize',8);
                    text(posx+.32,posy,sprintf('(%s)',msk2str(vmsk(kcom(ii),3))),'HorizontalAlignment','left','VerticalAlignment','bottom','FontSize',8);
                 end
            end
            
            if ~isempty(kile)
                text(posx,xylim(3)+hrect-(ncom+3.7)*hligne,sprintf('{\\bfHors %s}',X.SHAKEMAPS_PLACE)...
                    ,'HorizontalAlignment','center','VerticalAlignment','bottom','FontSize',7);
            end
            for ii = 1:length(kile)
                 posy = xylim(3)+hrect-(ncom+ii+4)*hligne;
                 text(posx,posy,IC.ile{kile(ii)},'HorizontalAlignment','right','VerticalAlignment','bottom','FontSize',8);
                 text(posx,posy,sprintf(' : {\\bf%s}',msk2str(vmsk(kile(ii),2))),'HorizontalAlignment','left','VerticalAlignment','bottom','FontSize',8);
                 text(posx+.32,posy,sprintf('(%s)',msk2str(vmsk(kile(ii),3))),'HorizontalAlignment','left','VerticalAlignment','bottom','FontSize',8);
            end
            hold off
            
            % copyright
            text(xylim(2)+.03,xylim(3),txtb3,'Rotation',90,'HorizontalAlignment','left','VerticalAlignment','top','FontSize',7);
            
            % ===========================================================
            % ---- encart zoom zone �picentrale
            if epi < 20
                if epi > 8
                    depi = 20;  % largeur de l'encart (en km)
                    dsc = 10;   % �chelle des distances (en km)
                    fsv = 8;    % taille police noms villes
                    msv = 8;    % taille marqueurs villes
                else
                    depi = 10;
                    dsc = 5;
                    fsv = 11;
                    msv = 10;
                end
                ect = [DH.lon(i) + depi/lonkm*[-1,1],DH.lat(i) + depi/latkm*[-1,1]];
                % trac� du carr� sur la carte principale
                hold on
                plot(ect([1,2,2,1,1]),ect([3,3,4,4,3]),'w-','LineWidth',2);
                plot(ect([1,2,2,1,1]),ect([3,3,4,4,3]),'k-','LineWidth',.1);
                hold off
                w1 = .3;    % taille relative de l'encart (par rapport � la page)
                h6 = axes('Position',[pos0(1)+pos0(3)-(w1+.01),pos0(2)+pos0(4)-(w1+.01)*pps(3)/pps(4),w1,w1*pps(3)/pps(4)]);
                pcontour(c_pta,[],gris), axis(ect), set(gca,'FontSize',6,'XTick',[],'YTick',[])
                hold on
                plot(ect([1,2,2,1,1]),ect([3,3,4,4,3]),'k-','LineWidth',2);
                plot(DH.lon(i),DH.lat(i),'p','MarkerSize',20,'MarkerEdgeColor','k','MarkerFaceColor','w','LineWidth',2)
                k = find(IC.lon > ect(1) & IC.lon < ect(2) & IC.lat > ect(3) & IC.lat < ect(4));
                plot(IC.lon(k),IC.lat(k),'s','MarkerSize',msv,'MarkerEdgeColor','k','MarkerFaceColor','k')
                text(IC.lon(k),IC.lat(k)+.05*depi/latkm,IC.nom(k),'HorizontalAlignment','center','VerticalAlignment','bottom','FontSize',fsv,'FontWeight','bold')
                xsc = ect(1) + .75*diff(ect(1:2));
                ysc = ect(3)+.03*diff(ect(3:4));
                plot(xsc+dsc*[-.5,.5]/lonkm,[ysc,ysc],'-k','LineWidth',2)
                text(xsc,ysc,sprintf('%d km',dsc),'HorizontalAlignment','center','VerticalAlignment','bottom','FontWeight','bold')
      			% nouvelle grille + serr�e
				[xz,yz] = meshgrid(linspace(ect(1),ect(2),100),linspace(ect(3),ect(4),100));
				dhpz = sqrt(((xz - DH.lon(i))*lonkm).^2 + ((yz - DH.lat(i))*latkm).^2 + DH.dep(i).^2);
				pgaz = 1000*attenuation(loi,DH.mag(i),dhpz);
				mskz = pga2msk(pgaz,'gutenberg');
				for ii = 2:10
                    [cs,h] = contour(xz,yz,mskz,[ii,ii]);
					set(h,'LineWidth',.1,'EdgeColor','k');
					if ~isempty(h)
						hl = clabel(cs,h,'FontSize',14);
                        lb = get(hl,'UserData');
                        % replacing numbers by roman
                        for iii = 1:length(hl)
                            if iscell(lb)
                                lbb = lb{iii};
                            else
                                lbb = lb(iii);
                            end
                            set(hl(iii),'String',sprintf('%s',msk2str(lbb)),'FontWeight','bold','FontSize',10);
                        end
					end
                end
                % courbe limite ressenti avec effets de site
                [cs,h] = contour(xz,yz,pga2msk(pgaz*max(IC.efs),'gutenberg'),[2,2]);
                set(h,'LineStyle',':','LineWidth',.25,'EdgeColor','k');

                hold off
            end
            
            
            % ===========================================================
            % ---- Tableau l�gende des intensit�s / PGA
            h7 = axes('Position',[.03,.022,.95,.068]);
            sz = length(pgamsk) - 1;
            % �chelle de couleurs
            xx = linspace(2,sz+2,256)/(sz+2);
            pcolor(xx,repmat([0;1/4],[1,length(xx)]),repmat(linspace(log10(pgamsk(1)),log10(pgamsk(10)),length(xx)),[2,1]))
            shading flat, caxis(log10(pgamsk([1,10])))
            hold on
            % bordures
            plot([0,0,1,1,0],[0,1,1,0,0],'-k','LineWidth',2);
            for ii = 1:3
                plot([0,1],[ii,ii]/4,'-k','LineWidth',.1);
            end
            for ii = 2:(sz+1)
                plot([ii,ii]/(sz+2),[0,1],'-k','LineWidth',.1);
            end
            text(1/(sz+2),3.5/4,'{\bfPerception Humaine}','HorizontalAlignment','center','VerticalAlignment','middle','FontSize',7);
            for ii = 1:sz
                xx = (ii + 1.5)/(sz+2);
                text(xx,3.5/4,nomres{ii},'HorizontalAlignment','center','VerticalAlignment','middle','FontSize',7);
            end
            text(1/(sz+2),2.5/4,'{\bfD�g�ts Potentiels}','HorizontalAlignment','center','VerticalAlignment','middle','FontSize',7);
            for ii = 1:sz
                xx = (ii + 1.5)/(sz+2);
                text(xx,2.5/4,nomdeg{ii},'HorizontalAlignment','center','VerticalAlignment','middle','FontSize',7);
            end
            text(1/(sz+2),1.5/4,'{\bfAcc�l�rations (mg)}','HorizontalAlignment','center','VerticalAlignment','middle','FontSize',7);
            for ii = 1:sz
                xx = (ii + 1.5)/(sz+2);
                switch ii
                case 1 
                    ss = sprintf('< %g',arrondi(pgamsk(ii+1),nbsig));
                case sz
                    ss = sprintf('> %g',arrondi(pgamsk(ii),nbsig));
                otherwise
                    ss = sprintf('%g - %g',arrondi(pgamsk([ii,ii+1]),nbsig));
                end
                text(xx,1.5/4,ss,'FontWeight','bold','HorizontalAlignment','center','VerticalAlignment','middle','FontSize',7);
            end
            text(1/(sz+2),.5/4,'{\bfIntensit�s EMS98}','HorizontalAlignment','center','VerticalAlignment','middle','FontSize',7);
            for ii = 1:sz
                xx = (ii + 1.5)/(sz+2);
                switch ii
                case sz
                    ss = sprintf('%s+',msk2str(ii));
                otherwise
                    ss = msk2str(ii);
                end
                text(xx,.5/4,ss,'FontWeight','bold','HorizontalAlignment','center','VerticalAlignment','middle','FontSize',9);
            end
            text(0,0,{'(*) {\bfmg} = "milli g�" est une unit� d''acc�l�ration correspondant au milli�me de la pesanteur terrestre', ...
                'La ligne pointill�e d�limite la zone o� le s�isme a pu �tre potentiellement ressenti.'}, ...
                'HorizontalAlignment','left','VerticalAlignment','top','FontSize',7);
            hold off
            set(gca,'XLim',[0,1],'YLim',[0,1]), axis off                    
            %h7 = axes('Position',[.05,0,.88,.05]);
            %text(0,0,{'(*) {\bfmg} = "milli g�" est une unit� d''acc�l�ration correspondant au milli�me de la pesanteur terrestre', ...
            %          '(**) D�finition de l''Echelle des Intensit�s: {\bfI} = non ressenti, {\bfII} = rarement ressenti, {\bfIII} = faiblement ressenti, {\bfIV} = largement ressenti,', ...
            %          '{\bfV} = secousse forte, {\bfVI} = d�g�ts l�gers, {\bfVII} = d�g�ts, {\bfVIII} = d�g�ts importants, {\bfIX} = destructions, {\bfX} = destructions importantes, ', ...
            %          '{\bfXI} = catastrophe, {\bfXII} = catastrophe g�n�ralis�e'}, ...
            %        'HorizontalAlignment','left','VerticalAlignment','bottom','FontSize',8);
            %set(gca,'XLim',[0,1],'YLim',[0,1]), axis off

            % Image Postscript + envoi sur l'imprimante + lien symbolique "lasthypo.png"
            print('-dpsc',ftmp);
            disp(sprintf('Graph: %s created.',ftmp));
            unix(sprintf('%s -sPAPERSIZE=a4 %s %s',X.PRGM_PS2PDF,ftmp,fgra));
            %unix(sprintf('%s -density 100x100 %s %s',X.PRGM_CONVERT,ftmp,fgra));
            disp(sprintf('Graph: %s created.',fgra));
            ss = sprintf('%s -scale 71x105 %s %s',X.PRGM_CONVERT,fgra,fico);
            unix(ss);
            disp(sprintf('Unix: %s',ss));

            if ~test
                if str2double(X.SHAKEMAPS_AUTOPRINT_OK)
                    unix(sprintf('lpr %s',ftmp));
                    disp(sprintf('Graph: %s printed.',ftmp));
                end
                if str2double(X.SHAKEMAPS_AUTOMAIL_OK)
                    % envoi d'un e-mail � sismo...
                    fid0 = fopen(mtmp,'wt');
                    for ii = 1:length(s_txt)
                        fprintf(fid0,[strrep(strrep(s_txt{ii},'{\bf',''),'}',''),' ']);
                    end
                    fprintf(fid0,'\n\nCommuniqu� complet sur ce s�isme :\n\nhttp://%s%s/%s/%s/%s.pdf \n\n',X.RACINE_URL,X.WEB_RACINE_FTP,pres,pam,fnam);
                    fprintf(fid0,'\n\nValeurs d�taill�es des PGA et distances hypocentrales :\n\nhttp://%s%s/%s/%s/%s.txt \n\n',X.RACINE_URL,X.WEB_RACINE_FTP,pres,pam,fnam);				fclose(fid0);
                    unix(sprintf('cat %s >> %s',ftxt,mtmp));
%                     unix(sprintf('mail %s -s "S�isme %s MD=%s - B3=%s (%s max) � %s" < %s',X.SISMO_EMAIL,dtiso,s_mag,msk2str(vmsk(kepi,2)),msk2str(vmsk(kepi,3)),s_gua,mtmp));
                    disp('E-mail envoy� � sismo...');
                end
            end

            % Lien symbolique sur le dernier ressenti
            if ~test
                [s,w] = unix(sprintf('find %s/%s/ -type f -name "*.pdf"|sort |tail -1',X.RACINE_FTP,pres));
		if s == 0
			ss = sprintf('ln -sf %s %s',deblank(w),f3);
			disp(sprintf('Unix: %s',ss));
			[s,w] = unix(ss);
			if s
				fprintf('!problem to execute command: "%s"\n',w);
			end
		else
			sprintf('!problem to execute command: "%s"\n',w);
		end
                [s,w] = unix(sprintf('find %s/%s/%s/ -type f -name "*.txt"|sort |tail -1',X.RACINE_FTP,X.SHAKEMAPS_PATH_FTP,X.SHAKEMAPS_PATH_TREATED));
                ss = sprintf('ln -sf %s %s',deblank(w),f2);
                unix(ss);
                disp(sprintf('Unix: %s',ss));
                ss = sprintf('ln -sf %s %s',fico,f4);
                %ss = sprintf('%s -scale 71x105 %s %s',X.PRGM_CONVERT,f3,f4);
                unix(ss);
                disp(sprintf('Unix: %s',ss));
            end
        end
        % Cr�ation du message GSE si r�ellement ressenti : msk >= 2
        if DH.msk(i) >= 2
            fid = fopen(fgse,'wt');
            fprintf(fid,'BEGIN GSE2.0\n');
            fprintf(fid,'MSG_TYPE DATA\n');
            fprintf(fid,'MSG_ID %s OVSM\n',fnam);
            fprintf(fid,'DATA_TYPE EVENT GSE2.0\n');
            fprintf(fid,'Guadeloupe : %s %s � %s %s de %s (Guadeloupe)\n',s_qua,s_typ,s_epi,s_vaz,s_gua);
            fprintf(fid,'EVENT %s\n',fnam);
            fprintf(fid,'   Date       Time       Latitude Longitude    Depth    Ndef Nsta Gap    Mag1  N    Mag2  N    Mag3  N  Author          ID \n');
            fprintf(fid,'     rms   OT_Error      Smajor Sminor Az        Err   mdist  Mdist     Err        Err        Err     Quality\n\n');
            fprintf(fid,'%4d/%02d/%02d %02d:%02d:%04.1f    %8.4f %9.4f    %5.1f              %03d  Md%4.1f                           OVSM      %02.0f%03.0f%03.0f\n',vtps,DH.lat(i),DH.lon(i),DH.dep(i),DH.gap(i),DH.mag(i),DH.lat(i),DH.lon(i),DH.dep(i));
            fprintf(fid,'     %5.2f   +-          %6.1f %6.1f         +-%5.1f                                                  m i ke\n',DH.rms(i),DH.erh(i),DH.erh(i),DH.erz(i));
            fprintf(fid,'\n%s DE %s (GUADELOUPE)\n',upper(s_vaz),upper(s_gua));
            fprintf(fid,'\n\nSTOP\n',fnam);
            fclose(fid);
            disp(sprintf('File: %s created.',fgse));
        end
    end
end
close

timelog(rcode,2);

