function [] = plx2mda(fileName,chansPerTrode,directory)

if nargin == 1
    chansPerTrode = 1;
    directory = pwd;
elseif nargin == 2
    directory = pwd;
end

readall(fileName);pause(1);

load(strcat(fileName(1:end-4),'.mat'),'allts','allwaves',...
    'wfcounts','Freq','nunits1','npw','allad','svStrobed','tsevs','adfreqs');

index = regexp(fileName,'_');
Date = fileName(index-8:index-1);
AnimalName = fileName(index+1:end-4);

% REORGANIZE SPIKING DATA
temp = ~cellfun(@isempty,allts);
Chans = find(sum(temp,1));numChans = length(Chans);
totalUnits = sum(sum(temp));

unitChannel = zeros(totalUnits,1);
temp = cell(totalUnits,1);
temp2 = cell(totalUnits,1);
count = 1;
for ii=1:numChans
   for jj=1:nunits1
       if isempty(allts{jj,Chans(ii)}) == 0
           temp{count} = allts{jj,Chans(ii)};
           unitChannel(count) = ii;
           temp2{count} = allwaves{jj,Chans(ii)};
           count = count+1;
       end
   end
end

allts = temp;
allwaves = temp2;

clear temp temp2;

allEventTimes = cell(totalUnits,1);
for ii=1:totalUnits
   waves = allwaves{ii}; 
   waves = waves'; % number of samples in the snippet by number of events,
            % if a tetrode, should be 4 by number of samples by number of
            % events
   tmpwaves = reshape(waves,[chansPerTrode,size(waves,1),size(waves,2)]);
   clear waves;
   
   [peaks,i] = min(tmpwaves,[],2); % i is the column index of the peak of each channel
   [maxpeak,j] =min(peaks,[],1); % j is the row index of the peak across channel peaks
   
   % use j to index i, find the index of the peak of each waveform across channels
   j = reshape(j,1,size(j,3));
   i = reshape(i,chansPerTrode,size(i,3));
   peak_inds =  zeros(1,size(i,2));
   for q = 1:size(i,2)
       peak_inds(q) = i(j(q),q);
   end
   
   raw=reshape(cat(2,tmpwaves,zeros(size(tmpwaves))),chansPerTrode,2*npw*size(tmpwaves,3));
   event_times=peak_inds+(0:size(tmpwaves,3)-1)*2*npw;
   event_times = int32(event_times);
   
   allEventTimes{ii} = event_times;
   if ~exist(sprintf('%s.mda',fileName(1:end-4)),'dir')
       mkdir(sprintf('%s.mda',fileName(1:end-4)))
   end
   cd(sprintf('%s.mda',fileName(1:end-4)));
   
   %write mda files
   writemda(event_times,sprintf('event_times.nt%02d.mda',ii),'int32');
   writemda(raw,sprintf('raw.nt%02d.mda',ii),'float64');
   
   cd(directory);
end

clear ii i j jj q raw event_times tmpwaves maxpeak peak_inds peaks

save(sprintf('%s-mda.mat',fileName(1:end-4)));