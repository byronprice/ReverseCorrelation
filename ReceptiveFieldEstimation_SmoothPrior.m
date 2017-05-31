% ReceptiveFieldEstimation_SmoothPrior.m

% INITIALIZE VARIABLES AND MAKE SEQUENCE VIDEO, binned at 1ms
fileName = sprintf('5Min_PinkNoiseMovie%d.mat',1);
load(fileName);
xaxis = linspace(-maxPix/2,maxPix/2,DIM(2));
yaxis = linspace(-minPix/4,3*minPix/4,DIM(1));

%S = normrnd(0,1,[N,N,numStimuli]);

totalCentisecs = 5*60*100;

stimTimes = round((0:1/60:5*60-1/60).*100);
pointProcessStimTimes = zeros(totalCentisecs,1);
for ii=1:numStimuli-1
    pointProcessStimTimes(stimTimes(ii)+1:stimTimes(ii+1)) = ii;
end
pointProcessStimTimes(stimTimes(numStimuli):stimTimes(numStimuli)+15) = numStimuli;

% DEFINE SPATIOTEMPORAL RECEPTIVE FIELD (STRF) AND PLOT EXAMPLE CONVOLUTION
%   OF STRF WITH SEQUENCE STIMULUS
%  the temporal component is a zero-gain, time-causal filter, which
%  endows the "neuron" with its preferred temporal frequency, its transient
%  responses to visual images, and its latency
%   if the v (velocity) is zero, then this is a space-time separable
%   filter, but if v ~= 0, it's space-time inseparable
gaborFun = @(x,y,t,k,n,v,A,xc,yc,sigmax,sigmay,spatFreq,theta,phi) ...
    exp(-((x-xc).*cos(A)-(y-yc).*sin(A)).^2./(2*sigmax*sigmax)-...
    ((x-xc).*sin(A)+(y-yc).*cos(A)).^2/(2*sigmay*sigmay))...
    .*sin((2*pi.*spatFreq).*(cos(theta-pi/2).*(x-xc)+sin(theta-pi/2).*(y-yc)+v.*t)-phi)...
    .*(k.*t).^n.*exp(-k.*t).*(1/gamma(n+1)-(k.*t).^2./(gamma(n+3)));

t = 200:-1:0;
sigmax = 125; % size (arbitrary units) of the spatial Gabor
sigmay = 100;
k = 0.3; % k and n define the temporal filter
n = 20;
A = pi/4;
spatFreq = 0.05;
theta = 60*pi/180; % neuron's preferred orientation
phi = 0; % phase of the sinusoid
v = 0; % velocity (shift in the phase over time)


[X,Y,T] = meshgrid(xaxis,yaxis,t);
filter1 = gaborFun(X,Y,T,k,n,v,A,0,0,sigmax,sigmay,spatFreq,theta,phi);

filterLen = length(t);
convResult = zeros(totalCentisecs,1);
y = zeros(totalCentisecs,1); % neural response

sigmoid = @(x,A,B,C) A.*exp((x-B).*C)./(1+exp((x-B).*C));
historyB = [-2,-1,-0.3,-0.1,0,0.1,0.3,0.4,0.3,0.25,0.2,0.15,0.1,0.05,0.025,0,0,0,0,0]';
baseRate = 5/100;

historyLen = length(historyB);
y(1:filterLen) = poissrnd(baseRate,[filterLen,1]);
currentHistory = fliplr(y(filterLen-historyLen+1:filterLen)');
A = 3;B = 75;C = 0.1;

startTime = filterLen+1;
for ii=startTime:totalCentisecs
%     onScreenStims = pointProcessStimTimes(ii-filterLen+1:ii);
%     temp = double(S(:,:,onScreenStims));

%     temp1 = temp.*filter1;
%     convResult(ii) = sum(temp1(:));
    lambda = baseRate*exp(currentHistory*historyB);%*exp(sigmoid(convResult(ii),A,B,C));
    y(ii) = poissrnd(lambda);
    currentHistory = [y(ii),currentHistory(1:end-1)];
end
%y = logical(y);
historyParams = historyLen;
historyDesign = zeros(totalCentisecs,historyParams);

for kk=1:historyParams
    temp = y;shift = zeros(kk,1);
    history = [shift;temp];
    historyDesign(:,kk) = history(1:(end-kk));
end

y = y(filterLen+1:end);
historyDesign = historyDesign(filterLen+1:end,:);

numBasis = 10;
basisFuns = zeros(historyParams,numBasis);
centerPoints = linspace(1,historyParams,numBasis);
basisStd = 1.5;
for ii=1:numBasis
   time = 1:historyParams;
   temp = exp(-(time-centerPoints(ii)).^2./(2*basisStd^2));
   temp = temp./max(temp);
   basisFuns(:,ii) = temp';
end

X = historyDesign*basisFuns;
[b,dev,stats] = glmfit(X,y,'poisson');
[yhat,dylo,dyhi] = glmval(b,basisFuns,'log',stats);
ytrue = baseRate*exp(historyB);

ytrue = ytrue*100;yhat = yhat*100;dylo = dylo*100;dyhi = dyhi*100;
figure(1);subplot(2,1,1);
boundedline(1:historyParams,yhat,[dylo,dyhi],'c');hold on;plot(ytrue,'r','LineWidth',2);
title('GLM Fit, with 95% Confidence Interval');legend('ML','True Values');
ylabel('Firing Rate (Hz');xlabel('Lag (centisecs)');

% INTIALIZE VARIABLES AND PRIORS FOR MCMC
X = [ones(length(historyDesign),1),historyDesign];

baseFiring = sum(y)/length(y);
numIter = 2e5;burnIn = 5e4;numParams = historyParams+1;
params = zeros(numParams,numIter);
posteriorProb = zeros(numIter,1);

priorMu = zeros(numParams,1);
priorSigma = diag(ones(numParams,1));
priorMu(1) = log(baseFiring);
priorSigma(1,1) = 2;
for ii=2:numParams
   priorMu(ii) = 0;
   priorSigma(ii,ii) = 2;
end

smoothPriorMu = zeros(numParams-1,1);
smoothPriorSigma = zeros(numParams-1,numParams-1);
beta = 1;

for ii=1:numParams-1
    smoothPriorSigma(ii,ii) = beta;
end

params(:,1) = mvnrnd(priorMu,priorSigma)';

logPoissonPDF = @(y,mu) y.*mu-exp(mu);
% calculate likelihood
spikeTimes = find(y==1);

L = zeros(historyParams,historyParams);

for ii=1:historyParams
   if ii>1 && ii<historyParams
       L(ii,ii-1:ii+1) = [1,-2,1];
   elseif ii==1
       L(ii,1) = -1;L(ii,2) = 1;
   elseif ii==historyParams
       L(ii,end-1) = 1;L(ii,end) = -1;
   end
end

tempMu = X*params(:,1);
prevLogLikelihood = sum(logPoissonPDF(y,tempMu));

smoothPrior = L*params(2:end,1);
prevLogPrior = log(mvnpdf(params(:,1)',priorMu',priorSigma))+...
    log(mvnpdf(smoothPrior',smoothPriorMu',smoothPriorSigma));

posteriorProb(1) = prevLogLikelihood+prevLogPrior;

% figure();subplot(2,1,1);scatter(1,prevLogLikelihood+prevLogPrior);hold on;
% subplot(2,1,2);histogram(params(1,1));pause(1);
% figure();scatter(1,0.1);pause(0.1);hold on;

% FOR AUTOMATIC CREATION OF UPDATE MATRIX
updateParam = 1e-3;%temp = logspace(-1,-6,burnIn);
% updateShift = temp(2)/temp(1);clear temp;
mu = zeros(numParams,1);sigma = priorSigma;
% loglambda = log(2.38^2/numParams).*diag(ones(numParams,1));
loglambda = log(2.38^2/numParams);
updateMu = mvnrnd(priorMu,priorSigma)';
optimalAccept = 0.234;

% error = zeros(burnIn,1);
% error(1) = mean(abs([log(baseRate);historyB]-updateMu));
for ii=2:burnIn
%     Z = mvnrnd(mu,sqrt(exp(loglambda))*sigma*sqrt(exp(loglambda)))';
    Z = mvnrnd(mu,exp(loglambda)*sigma)';
    pStar = params(:,ii-1)+Z;
    tempMu = X*pStar;
    pStarLogLikelihood = sum(logPoissonPDF(y,tempMu));
    smoothPrior = L*pStar(2:end);
    pStarLogPrior = log(mvnpdf(pStar',priorMu',priorSigma))+...
        log(mvnpdf(smoothPrior',smoothPriorMu',smoothPriorSigma));
    
    logA = (pStarLogLikelihood+pStarLogPrior)-posteriorProb(ii-1);
    
    if log(rand) < logA
        params(:,ii) = pStar;
        posteriorProb(ii) = pStarLogLikelihood+pStarLogPrior;
    else
        params(:,ii) = params(:,ii-1);
        posteriorProb(ii) = posteriorProb(ii-1);
    end
%     sigma = sigma+updateParam*(acceptRate/ii-optimalAccept); %
%       exponentiate sigma in mvnrnd
    sigma = sigma+updateParam.*((params(:,ii)-updateMu)*...
        (params(:,ii)-updateMu)'-sigma);
    updateMu = updateMu+updateParam.*(params(:,ii)-updateMu);
    loglambda = loglambda+updateParam.*(exp(min(0,logA))-optimalAccept);
    
%     for jj=1:numParams
%         myVec = zeros(numParams,1);myVec(jj) = 1;
%         
%         pStar = params(:,ii-1)+Z.*myVec;
%         tempMu = X*pStar;
%         pStarLogLikelihood = sum(logPoissonPDF(y,tempMu));
%         smoothPrior = L*pStar(2:end);
%         pStarLogPrior = log(mvnpdf(pStar',priorMu',priorSigma))+...
%             log(mvnpdf(smoothPrior',smoothPriorMu',smoothPriorSigma));
%         
%         logA = (pStarLogLikelihood+pStarLogPrior)-posteriorProb(ii-1);
%         loglambda(jj,jj) = loglambda(jj,jj)+updateParam.*(exp(min(0,logA))-optimalAccept);
%     end
%     updateParam = updateParam*updateShift;
    
%     error(ii) = mean(abs([log(baseRate);historyB]-updateMu));
%     scatter(ii,error);hold on;pause(0.01);
%     subplot(2,1,1);scatter(ii,posteriorProb(ii));title(sprintf('%3.2f',sigma(1,1)));
%     subplot(2,1,2);histogram(params(1,1:ii));pause(0.05);
end

sigma = exp(loglambda).*sigma;
% sigma = sqrt(exp(loglambda))*sigma*sqrt(exp(loglambda));
acceptRate = 0;
for ii=burnIn+1:numIter
    pStar = params(:,ii-1)+mvnrnd(mu,sigma)';
    tempMu = X*pStar;
    pStarLogLikelihood = sum(logPoissonPDF(y,tempMu));
    smoothPrior = L*pStar(2:end);
    pStarLogPrior = log(mvnpdf(pStar',priorMu',priorSigma))+...
        log(mvnpdf(smoothPrior',smoothPriorMu',smoothPriorSigma));
    
    logA = (pStarLogLikelihood+pStarLogPrior)-posteriorProb(ii-1);
    
    if log(rand) < logA
        params(:,ii) = pStar;
        posteriorProb(ii) = pStarLogLikelihood+pStarLogPrior;
        acceptRate = acceptRate+1;
    else
        params(:,ii) = params(:,ii-1);
        posteriorProb(ii) = posteriorProb(ii-1);
    end
    
end
    
figure();autocorr(params(2,:),100);
% figure();plot(error);
skipRate = 100;
fprintf('Final Acceptance Rate: %3.2f\n',acceptRate/(numIter-burnIn-1));
posteriorSamples = params(:,burnIn+1:skipRate:end);
% figure();histogram(posteriorSamples(2,:));

[~,ind] = max(posteriorProb);
MAP = params(:,ind);
posteriorMean = mean(posteriorSamples,2);
posteriorMedian = median(posteriorSamples,2);

alpha = 0.05;
posteriorInterval = quantile(posteriorSamples,[alpha/2,1-alpha/2],2);

figure();plot(historyB,'LineWidth',2);hold on;
plot(b(2:end)'*basisFuns','LineWidth',2);plot(MAP(2:end),'LineWidth',2);
legend('True Values','ML','MAP','Location','northwest');
title('History-Dependent Point Process Model Comparison');

figure(1);subplot(2,1,2);
temp = baseRate.*100.*exp(posteriorMedian(2:end));
temp1 = baseRate.*100.*exp(posteriorInterval(2:end,1));
temp2 = baseRate.*100.*exp(posteriorInterval(2:end,2));
boundedline(1:length(historyB),temp,...
    [temp-temp1,temp2-temp]);
hold on;plot(baseRate*100*exp(historyB),'r','LineWidth',2);
title('Posterior Median, with 95% Posterior Interval');
legend('Bayes','True Values');ylabel('Firing Rate (Hz)');
xlabel('Lag (centisecs)');

totalErrorGLM = mean(abs([log(baseRate),historyB']-[b(1),b(2:end)'*basisFuns']));
totalErrorBayesMAP = mean(abs([log(baseRate);historyB]-MAP));
totalErrorBayesMedian = mean(abs([log(baseRate);historyB]-posteriorMedian));

fprintf('GLM ML Error: %3.2f\n',totalErrorGLM);
fprintf('Bayes'' MAP Error: %3.2f\n',totalErrorBayesMAP);
fprintf('Bayes'' Posterior Median Error: %3.2f\n',totalErrorBayesMedian);