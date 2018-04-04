function [] = firingsmda2mat(directory)
% convert the firings.mda file output from MountainSort back to MATLAB
%  format for data analysis

% call this code from within the directory

% fileID = fopen('fileName.txt','r');
% fileName1 = fscanf(fileID,'%s');

files = dir('firing*.mda');
numFiles = length(files);

spikeTimes = cell(numFiles,1);
totalUnits = 0;
for ii=1:numFiles
    firingFile = files(ii).name;
    A = readmda(firingFile);
    
    units = unique(A(3,:));
    numUnits = length(units);
    
    spikeTimes{ii} = cell(numUnits,1);
    
    count = 1;
    pseudo_event_times = A(2,:);
    unitcode = A(3,:);
    unitIDs = unique(unitcode);
    nunits = length(unitIDs);
    for kk=1:nunits
        spikeTimes{ii}{count} = pseudo_event_times(unitcode==unitIDs(kk))+1;
        totalUnits = totalUnits+1;
        count = count+1;
    end
end

clearvars -except spikeTimes numFiles directory totalUnits

cd ..

fileName1 = strcat(directory,'-mda.mat');
load(fileName1)

% convert from pseudo event times to experimental time
newts = cell(totalUnits,1);
newwaves = cell(totalUnits,1);

count = 0;
for ii=1:numFiles
   spikeTimeTempArray = spikeTimes{ii};
   numUnits = size(spikeTimeTempArray,1);
   
   trueEventTimes = allts{ii};
   trueWaves = allwaves{ii};
   correspondingEventIndices = double(allEventTimes{ii}');
   for jj=1:numUnits 
       count = count+1;
       
       pseudo_event_times = unique(spikeTimeTempArray{jj});
       indices = zeros(length(pseudo_event_times),1);
       for kk=1:length(pseudo_event_times)
          [difference,ind] = min(abs(correspondingEventIndices-pseudo_event_times(kk)));
          if abs(difference)<10
            indices(kk) = ind;
          end
       end
       indices = indices(indices>0);
       newwaves{count} = trueWaves(:,:,indices);
       newts{count} = trueEventTimes(indices);
   end
end
clear difference ind trueWaves count;

% include and exclude units
%  criterion for inclusion: 
%     1) <=2% of spikes within a 2ms refractory period
%     2) <0.8 correlation with all other recorded neurons
%     3) average firing rate for the whole session > 0.1 Hz

timeMultiplier = 1000;
nonemptyad = ~cellfun(@isempty,allad);
temp = allad(nonemptyad);temp2 = adfreqs(nonemptyad);

if length(temp{1})>10
    totalTime = length(temp{1})/temp2(1);
else
   totalTime = 10;
   for ii=1:totalUnits
       totalTime = max(totalTime,max(newts{ii})+1);
   end
end

pointProcessSpikes = zeros(round(totalTime*timeMultiplier),totalUnits);
for ii=1:totalUnits
   spikeTimes = max(1,round(newts{ii}.*timeMultiplier));
   for jj=1:length(spikeTimes)
      pointProcessSpikes(spikeTimes(jj),ii) = 1;
   end
end

refractory_cutoff = 2/1000;
refractory_inclusion = 0.02;
spikeHz_cutoff = 0.1;spikeNum_cutoff = spikeHz_cutoff*totalTime;
correlation_inclusion = 0.8;
toInclude = ones(totalUnits,1);

for ii=1:totalUnits
   spikeTimes = newts{ii};
   for jj=ii+1:totalUnits
       [r,~] = corrcoef(pointProcessSpikes(:,ii),pointProcessSpikes(:,jj));
       if r(1,2) >= correlation_inclusion
          toInclude(jj) = 0; 
          pointProcessSpikes(:,ii) = (pointProcessSpikes(:,ii)+pointProcessSpikes(:,jj))>0;
          pointProcessSpikes(:,jj) = 0;
          temp = newts{jj};
          newts{ii} = unique(round([spikeTimes;temp].*timeMultiplier))./timeMultiplier;
          newts{jj} = 0;
       end
   end
end

for ii=1:totalUnits
    spikeTimes = newts{ii};
    if length(spikeTimes) < spikeNum_cutoff
        toInclude(ii) = 0;
    end
    isi = diff([0;spikeTimes]);
%     figure();subplot(2,1,1);plot(spikeTimes);
%     subplot(2,1,2);histogram(isi);
    criterion1 = sum(isi<=refractory_cutoff)/length(isi);
    fprintf('\nProportion refractory violations: %3.2e\n',criterion1);
    if criterion1 > refractory_inclusion || isnan(criterion1)
        toInclude(ii) = 0;
    end
end

totalUnits = sum(toInclude);
allts = cell(totalUnits,1);
allwaves = cell(totalUnits,1);
meanWaves = cell(totalUnits,1);

inds = find(toInclude==1);
for ii=1:totalUnits
   allts{ii} = newts{inds(ii)};
   allwaves{ii} = newwaves{inds(ii)};
   
   temp = allwaves{ii};
   meanWaves{ii} = mean(temp,3);
end

clear pointProcessSpikes temp temp2 ii jj timeMultiplier newts spikeTimes ...
    trueEventTimes spikeTimeTempArray correspondingEventIndices toInclude r ...
    criterion1 allEventTimes inds isi kk index indices nonemptyad pseudo_event_times ...
    newwaves;

fprintf('\nTotal Units: %d\n',totalUnits);

try
    timeStamps = tsevs{33};
catch
    timeStamps = tsevs{3};
end

pause(1);

if totalUnits>0
    newFileName = sprintf('%s-mounsort.mat',fileName1(1:end-8));
    save(newFileName,'allts','allwaves','allad','tsevs','timeStamps','svStrobed',...
        'chansPerTrode','totalUnits','totalTime','DateTime');
end
end