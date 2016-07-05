function [  ] = fitIlModel( recomputeTex, recomputeLbTemp, recomputeDT )
% TODO: -Korjaa lämpötilaprofiili Bates-Walkeriksi (z0 = 120 km) ja painovoima 9.447:ksi.

rng(1, 'twister');
%import java.lang.*
%r = Runtime.getRuntime;
%numThreads = r.availableProcessors;
numThreads = 64;

global numCoeffs;
numCoeffs = 103;

clear mex;

poolobj = gcp('nocreate'); % If no pool, do not create new one.
if isempty(poolobj)
    parpool(24);
end

% Check the existence of the data file.
if exist('ilData.mat', 'file')
    load ilData.mat
else
    error('File ilData.mat not found!')
end

[TempStruct, OStruct, N2Struct, HeStruct, ArStruct, O2Struct, rhoStruct, lbDTStruct, lbT0Struct] = removeAndFixData(TempStruct, OStruct, N2Struct, HeStruct, ArStruct, O2Struct, rhoStruct, lbDTStruct, lbT0Struct);
if ~exist('dTCoeffs', 'var') || recomputeDT
    dTCoeffs = fitTemeratureGradient(lbDTStruct); 
    save('ilData.mat', 'dTCoeffs', '-append')
end

if ~exist('T0Coeffs', 'var') || recomputeLbTemp
    T0Coeffs = fitLbTemerature(lbT0Struct, lbDTStruct); 
    save('ilData.mat', 'T0Coeffs', '-append')
end

if ~exist('TexStruct', 'var') || recomputeTex
    TexStruct = computeExosphericTemperatures(TempStruct, dTCoeffs, T0Coeffs);
    save('ilData.mat', 'TexStruct', '-append')
end


opt = optimoptions('lsqnonlin', 'Jacobian', 'on', 'Algorithm', 'trust-region-reflective', 'TolFun', 1E-3, ...
                 'TolX', 1E-7, 'Display', 'iter');
%opt = psoptimset('Display', 'iter', 'CompletePoll', 'on', 'InitialMeshSize', 1E-1, 'TolX', 1E-11, 'TolMesh', 1E-11, 'TolFun', 1E-5, 'UseParallel', true, 'Cache', 'on', 'CacheTol', 1E-12, 'MaxMeshSize', 1.0);


%dataLen = length(TexStruct.data) + length(OStruct.data) + length(N2Struct.data) + length(HeStruct.data) + length(rhoStruct.data);
%opt = optimoptions('fmincon', 'Display', 'iter', 'FinDiffType', 'central', 'MaxFunEvals', 1000*numCoeffs, 'TolFun', 1E-3, 'Algorithm', 'sqp', ...
%    'TolX', 1E-11, 'UseParallel', true, 'Hessian', 'bfgs', 'ScaleProblem', 'obj-and-constr', 'OutputFcn', @(x,y,z)outfun(x,y,z,dataLen));

ms = MultiStart('Display', 'iter', 'UseParallel', true);
numStartPoints = 1;

% % !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
% fprintf('\nFitting the IL Model\n\n')
% for iter = 1:maxIter
%     fprintf('\nIteration %d:\n', iter)
%     
%     TexStruct = fitTex(TexStruct, opt, ms, numStartPoints);
% 
%     OStruct = fitSpecies(OStruct, TexStruct, opt, ms, numStartPoints);
%     
%     printProgressInfo(TexStruct, OStruct, rhoStruct);
%     
%     if iter < maxIter
%         [TexStruct, OStruct] = estimateTexAndDensities(TexStruct, OStruct, rhoStruct);
%     end
% 
% end
% % !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

fitModelVariables(TexStruct, OStruct, N2Struct, HeStruct, ArStruct, O2Struct, rhoStruct, dTCoeffs, T0Coeffs, opt, ms, numStartPoints, numThreads)

end

function S = computeDensityRHS(S, Tex, dT0, T0)
%global modelLbHeight
numBiasesOrig = S.numBiases; S.numBiases = 0;
S.numBiases = numBiasesOrig;
u2kg = 1.660538921E-27;
k = 1.38064852E-23;
g = 9.418; 
if strcmpi(S.name, 'O')
    molecMass = 16 * u2kg;
    alpha = 0;
elseif strcmpi(S.name, 'N2')
    molecMass = 28 * u2kg;
    alpha = 0;
elseif strcmpi(S.name, 'O2')
    molecMass = 32 * u2kg;
    alpha = 0;
elseif strcmpi(S.name, 'Ar')
    molecMass = 40 * u2kg;
    alpha = 0;
elseif strcmpi(S.name, 'He')
    molecMass = 4 * u2kg;
    alpha = -0.38;
else
    error('Incorrect name for gas species!')
end

sigma = dT0 ./ (Tex - T0);
T = Tex - (Tex - T0) .* exp(-sigma .* (S.Z));
gamma = molecMass * g ./ (k * sigma * 1E-3 .* Tex);
altTerm = (1 + gamma + alpha) .* log(T0 ./ T) - gamma .* sigma .* (S.Z);
S.rhs = log(S.data) - altTerm;

if any(~isfinite(S.rhs))
     a = 1;
end

end

function [TexStruct] = computeExosphericTemperatures(TempStruct, dTCoeffs, T0Coeffs)

fprintf('%s\n', 'Computing exospheric temperatures')

TexVec = zeros(length(TempStruct.data),1);
% Set solution accuracy to 0.001.
options = optimoptions('fmincon', 'TolX', 1E-6, 'display', 'none');
% Loop over the temperature data.
S = computeVariablesForFit(TempStruct);
Z = S.Z;
T0 = evalT0(S, T0Coeffs); 
data = S.data; data = clamp(T0+1, data, 10000);
dT0 = clamp(1, evalDT(S, dTCoeffs), 30);

targetCount = round(length(TexVec) / 1000);
barWidth = 50;
p = TimedProgressBar( targetCount, barWidth, ...
                'Computing Tex, ETA ', ...
                '. Now at ', ...
                'Completed in ' );
parfor i = 1:length(TexVec);
    % Because the Bates profile is nonlinear, use numerical root
    % finding.
    minFunc = @(Tex)TexFunc(Tex, Z(i), data(i), T0(i), dT0(i));
    TexVec(i) = fmincon(minFunc, 1000, [],[],[],[],data(i),10000,[], options);
    if mod(i,1000) == 0
        p.progress;
    end
end
p.stop;

TexStruct = TempStruct;
% Remove clear outliers.
removeInd = (TexVec - data) > 3000;
TexStruct = removeDataPoints(TexStruct, removeInd);
satInd = zeros(1, length(removeInd));
satInd(TexStruct.de2) = 1;
satInd(TexStruct.aeC) = 2;
satInd(TexStruct.aeE) = 3;
satInd(removeInd) = [];
TexStruct.de2 = find(satInd == 1);
TexStruct.aeC = find(satInd == 2);
TexStruct.aeE = find(satInd == 3);
TexStruct.data = TexVec(~removeInd);
TexStruct.dataEnd = length(TexStruct.data);
TexStruct.Z = TexStruct.Z(~removeInd);

end

function dTCoeffs = fitTemeratureGradient(lbDTStruct)

fprintf('%s\n', 'Fitting Temperature gradient')

lbDTStruct = computeVariablesForFit(lbDTStruct);

numCoeffs = 50;
dTCoeffs = zeros(numCoeffs, 1);

dTCoeffs(1) = mean(lbDTStruct.data);
dTCoeffs([17, 25, 28, 32, 35, 39, 41, 45, 46, 50]) = 0.01;

opt = optimoptions('lsqnonlin', 'Jacobian', 'on', 'Algorithm', 'Levenberg-Marquardt', 'TolFun', 1E-8, ...
                 'TolX', 1E-6, 'Display', 'iter');

fun = @(X) temperatureGradientMinimization(lbDTStruct, X);
[dTCoeffs] = lsqnonlin(fun, dTCoeffs, [], [], opt);

end

function lbT0Coeffs = fitLbTemerature(lbT0Struct, TempStruct)

fprintf('%s\n', 'Fitting lower boundary temperature')

Nobs = length(lbT0Struct.data);
Nmsis = length(TempStruct.data);

TempStruct.altitude = 130 * ones(size(TempStruct.data));
TempStruct = computeVariablesForFit(TempStruct);
[~,~,~,~,~,T] = computeMsis(TempStruct);
lbT0Struct.data = [lbT0Struct.data; T];
lbT0Struct.timestamps = [lbT0Struct.timestamps; TempStruct.timestamps];
lbT0Struct.latitude = [lbT0Struct.latitude; TempStruct.latitude];
lbT0Struct.longitude = [lbT0Struct.longitude; TempStruct.longitude];
lbT0Struct.solarTime = [lbT0Struct.solarTime; TempStruct.solarTime];
lbT0Struct.altitude = [lbT0Struct.altitude; TempStruct.altitude];
lbT0Struct.aeInt = [lbT0Struct.aeInt; TempStruct.aeInt];
lbT0Struct.F = [lbT0Struct.F; TempStruct.F];
lbT0Struct.FA = [lbT0Struct.FA; TempStruct.FA];
lbT0Struct.apNow = [lbT0Struct.apNow; TempStruct.apNow];
lbT0Struct.ap3h = [lbT0Struct.ap3h; TempStruct.ap3h];
lbT0Struct.ap6h = [lbT0Struct.ap6h; TempStruct.ap6h];
lbT0Struct.ap9h = [lbT0Struct.ap9h; TempStruct.ap9h];
lbT0Struct.ap12To33h = [lbT0Struct.ap12To33h; TempStruct.ap12To33h];
lbT0Struct.ap36To57h = [lbT0Struct.ap36To57h; TempStruct.ap36To57h];
lbT0Struct.Ap = [lbT0Struct.Ap; TempStruct.Ap];
lbT0Struct.type = [lbT0Struct.type; 3*ones(size(TempStruct.data))];

lbT0Struct = computeVariablesForFit(lbT0Struct);

weights = ones(size(lbT0Struct.data));
weights(Nobs+1:end) = Nobs / Nmsis;
weights = sqrt(weights);

numCoeffs = 50;
lbT0Coeffs = zeros(numCoeffs, 1);

lbT0Coeffs(1) = mean(lbT0Struct.data);
lbT0Coeffs([17, 25, 28, 32, 35, 39, 41, 45, 46, 50]) = 0.01;
ub = [550, 0.5*ones(1, numCoeffs-1)];
lb = [450, -0.5*ones(1, numCoeffs-1)];

opt = optimoptions('lsqnonlin', 'Jacobian', 'on', 'Algorithm', 'trust-region-reflective', 'TolFun', 1E-8, ...
                 'TolX', 1E-7, 'Display', 'iter', 'MaxIter', 10000);

fun = @(X) lbTemperatureMinimization(lbT0Struct, weights, X);
lbT0Coeffs = lsqnonlin(fun, lbT0Coeffs, lb, ub, opt);

end

% Function, whose root gives the Tex.
function y = TexFunc(Tex, Z, Tz, T0, dT0)
    %global modelLbHeight
    y = abs(Tex - (Tex - T0).*exp(-Z .* dT0 ./ (Tex-T0)) - Tz);
end

function [removeStruct] = removeFitVariables(removeStruct)

removeStruct.P10 = [];
removeStruct.P20 = [];
removeStruct.P30 = [];
removeStruct.P40 = [];

removeStruct.yv = [];

end

function [lb, ub] = G_bounds()

latitude = ones(1,14);
solarActivity = ones(1,5);
annual = ones(1,15); annual(1) = 0.001; annual(8) = 0.0001;
diurnal = ones(1, 21); diurnal([8, 19]) = 0.001;
semidiurnal = ones(1,16);
terdiurnal = ones(1,8);
quaterdiurnal = ones(1,2);
geomagnetic = ones(1,21); geomagnetic([1,9,12,17]) = 0.0001;

ub = [latitude, solarActivity, annual, diurnal, semidiurnal, terdiurnal, quaterdiurnal, geomagnetic];
lb = -ub;

end

function [startPoints] = createRandomStartPoints(lb, ub, numPoints)

if (any(lb > ub))
    error('Not all lower bound values were smaller than their corresponding upper bound!')
end

pd = makedist('Beta', 'a', 0.5, 'b', 0.5);

numVars = length(lb);
pointMat = zeros(numPoints, numVars);

boundMean = mean([lb;ub],1);
boundDiff = ub - lb;

for i = 1:numPoints
     for j = 1:numVars
         pointMat(i,j) = (boundDiff(j) * (random(pd)-0.5)) + boundMean(j);
     end
end

startPoints = CustomStartPointSet(pointMat);

end

function printModelStats(TexStruct, OStruct, rhoStruct)

T0 = TexStruct.T0; dT0 = TexStruct.dT0;
Z = rhoStruct.Z;
rhoStruct = computeVariablesForFit(rhoStruct);
OlbDens = OStruct.evalLb(rhoStruct);
Tex = TexStruct.eval(rhoStruct);
observations = rhoStruct.data;

rhoModel = computeRho(T0, dT0, Tex, Z, OlbDens);
ratio = rhoStruct.weights .* observations ./ rhoModel;
failedInd = (Tex <= T0 | ~isfinite(rhoModel));
ratio = ratio(~failedInd);

modelRms = rms(ratio);
modelStd = std(ratio);
obsToModel = mean(ratio);

numFailed = sum(failedInd);

fprintf('rms             std             O/C\n')
fprintf('%f        %f        %f          %d        %E        %E\n\n', modelRms, modelStd, obsToModel, numFailed, max(rhoModel(~failedInd)), min(rhoModel(~failedInd)));

end

function [residual] = computeSpeciesResidual(varStruct, Tex, dT0, T0, coeff)

varStruct = computeDensityRHS(varStruct, Tex, dT0, T0);
Gvec = G_major(coeff, varStruct);

if varStruct.numBiases == 0
    residual = (varStruct.rhs ./ max(coeff(1) + Gvec, 1)) - 1;
elseif varStruct.numBiases > 0
    residual = (varStruct.rhs ./ max(coeff(1) + sum(bsxfun(@times, coeff(2:varStruct.numBiases+1), varStruct.biases), 2) + Gvec, 1)) - 1;
else
    error('Incorrect number of biases!')
end

end

function [residual, Jacobian] = modelMinimizationFunction(TexStruct, OStruct, N2Struct, HeStruct, ArStruct, O2Struct, rhoStruct, dTCoeffs, T0Coeffs, weights, tolX, coeff)

dataLen = length(TexStruct.data) + length(OStruct.data) + length(N2Struct.data) + length(HeStruct.data) + length(rhoStruct.data) ...
    + length(ArStruct.data) + length(O2Struct.data);
residual = zeros(dataLen, 1);

T0 = evalT0(TexStruct, T0Coeffs);
TexMesuredEstimate = clamp(T0+1, evalTex(TexStruct, coeff(TexStruct.coeffInd)), 5000);
residInd = 1:length(TexStruct.data);
residual(residInd) = TexStruct.data./TexMesuredEstimate - 1;

[Tex, dT0, T0] = findTempsForFit(OStruct, TexStruct, dTCoeffs, T0Coeffs, coeff);
residInd = residInd(end) + (1:length(OStruct.data));
residual(residInd) = computeSpeciesResidual(OStruct, Tex, dT0, T0, coeff(OStruct.coeffInd));

[Tex, dT0, T0] = findTempsForFit(N2Struct, TexStruct, dTCoeffs, T0Coeffs, coeff);
residInd = residInd(end) + (1:length(N2Struct.data));
residual(residInd) = computeSpeciesResidual(N2Struct, Tex, dT0, T0, coeff(N2Struct.coeffInd));

[Tex, dT0, T0] = findTempsForFit(HeStruct, TexStruct, dTCoeffs, T0Coeffs, coeff);
residInd = residInd(end) + (1:length(HeStruct.data));
residual(residInd) = computeSpeciesResidual(HeStruct, Tex, dT0, T0, coeff(HeStruct.coeffInd));

[Tex, dT0, T0] = findTempsForFit(ArStruct, TexStruct, dTCoeffs, T0Coeffs, coeff);
residInd = residInd(end) + (1:length(ArStruct.data));
residual(residInd) = computeSpeciesResidual(ArStruct, Tex, dT0, T0, coeff(ArStruct.coeffInd));

[Tex, dT0, T0] = findTempsForFit(O2Struct, TexStruct, dTCoeffs, T0Coeffs, coeff);
residInd = residInd(end) + (1:length(O2Struct.data));
residual(residInd) = computeSpeciesResidual(O2Struct, Tex, dT0, T0, coeff(O2Struct.coeffInd));

[Tex, dT0, T0] = findTempsForFit(rhoStruct, TexStruct, dTCoeffs, T0Coeffs, coeff);
residInd = residInd(end) + (1:length(rhoStruct.data));
OlbDens = clamp(10, evalMajorSpecies(rhoStruct, coeff(OStruct.coeffInd)), 1E20);
N2lbDens = clamp(10, evalMajorSpecies(rhoStruct, coeff(N2Struct.coeffInd)), 1E20);
HelbDens = clamp(10, evalMajorSpecies(rhoStruct, coeff(HeStruct.coeffInd)), 1E20);
ArlbDens = clamp(10, evalMajorSpecies(rhoStruct, coeff(ArStruct.coeffInd)), 1E20);
O2lbDens = clamp(10, evalMajorSpecies(rhoStruct, coeff(O2Struct.coeffInd)), 1E20);
modelRho = clamp(1E-20, computeRho(T0, dT0, Tex, rhoStruct.Z, OlbDens, N2lbDens, HelbDens, ArlbDens, O2lbDens), 0.1);
residual(residInd) = (log(rhoStruct.data)./log(modelRho)) - 1;

if any(abs(residual) > 100)
    a=1;
end

residual = weights .* residual;

if nargout == 2
    fun = @(X)modelMinimizationFunction(TexStruct, OStruct, N2Struct, HeStruct, ArStruct, O2Struct, rhoStruct, dTCoeffs, T0Coeffs, weights, tolX, X);
    Jacobian = computeJAC(fun, coeff, dataLen, tolX);
end

end

function [residual, Jacobian] = temperatureGradientMinimization(lbDTStruct, coeff)

modelDT = evalDT(lbDTStruct, coeff);
residual = lbDTStruct.data - modelDT;

if nargout == 2
    fun = @(X)temperatureGradientMinimization(lbDTStruct, X);
    Jacobian = computeJAC(fun, coeff, length(lbDTStruct.data), 1E-5);
end

end

function [residual, Jacobian] = lbTemperatureMinimization(lbT0Struct, weights, coeff)

modelT0 = evalT0(lbT0Struct, coeff);
residual = weights .* (lbT0Struct.data - modelT0);

if nargout == 2
    fun = @(X)lbTemperatureMinimization(lbT0Struct, weights, X);
    Jacobian = computeJAC(fun, coeff, length(lbT0Struct.data), 1E-5);
end

end

function JAC = computeJAC(fun, x, dataLen, tolX)

JAC = zeros(dataLen, length(x));
dx = max(0.25*tolX*abs(x), 1E-10);

parfor i = 1:length(x)
    xForw = x; xBackw = x;
    xForw(i) = x(i) + dx(i);
    xBackw(i) = x(i) - dx(i);
    
    F_forw = feval(fun, xForw);
    F_backw = feval(fun, xBackw);
    
    result = (F_forw - F_backw) / (2*dx(i));
    
    infInd = ~isfinite(result);
    if any(infInd)
        result(infInd) = mean(result(~infInd));
    end
    
    JAC(:,i) = result;
end

end

function [] = fitModelVariables(TexStruct, OStruct, N2Struct, HeStruct, ArStruct, O2Struct, rhoStruct, dTCoeffs, T0Coeffs, options, multiStartSolver, numStartPoints, numThreads)
global numCoeffs;

fprintf('%s\n', 'Computing final fit')

%dataLen = length(TexStruct.data) + length(OStruct.data) +
%length(N2Struct.data) + length(HeStruct.data) + length(rhoStruct.data);

TexStruct = computeVariablesForFit(TexStruct);
OStruct = computeVariablesForFit(OStruct);
N2Struct = computeVariablesForFit(N2Struct);
HeStruct = computeVariablesForFit(HeStruct);
ArStruct = computeVariablesForFit(ArStruct);
O2Struct = computeVariablesForFit(O2Struct);
rhoStruct = computeVariablesForFit(rhoStruct);

weights = computeWeights(TexStruct, OStruct, N2Struct, HeStruct, ArStruct, O2Struct, rhoStruct);

[G_lb, G_ub] = G_bounds();
G_lb = 4 * G_lb; G_ub = 4 * G_ub;

TexStruct.coeffInd = 1:numCoeffs;
lb = [500, 125*G_lb]; ub = [1500, 125*G_ub];

OStruct.coeffInd = TexStruct.coeffInd(end) + (1:numCoeffs+OStruct.numBiases);
lb = [lb, log(0.5E10), zeros(1, OStruct.numBiases), G_lb]; % MUISTA LISATA BIASET!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
ub = [ub, log(1E11), zeros(1, OStruct.numBiases), G_ub];

N2Struct.coeffInd = OStruct.coeffInd(end) + (1:numCoeffs+N2Struct.numBiases);
lb = [lb, log(0.5E11), zeros(1, N2Struct.numBiases), G_lb]; % MUISTA LISATA BIASET!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
ub = [ub, log(1E12), zeros(1, N2Struct.numBiases), G_ub];

HeStruct.coeffInd = N2Struct.coeffInd(end) + (1:numCoeffs+HeStruct.numBiases);
lb = [lb, log(0.5E7), zeros(1, HeStruct.numBiases), G_lb]; % MUISTA LISATA BIASET!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
ub = [ub, log(1E8), zeros(1, HeStruct.numBiases), G_ub];

ArStruct.coeffInd = HeStruct.coeffInd(end) + (1:numCoeffs+ArStruct.numBiases);
lb = [lb, log(0.5E7), zeros(1, ArStruct.numBiases), G_lb]; % MUISTA LISATA BIASET!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
ub = [ub, log(1E8), zeros(1, ArStruct.numBiases), G_ub]; % KORJAA

O2Struct.coeffInd = ArStruct.coeffInd(end) + (1:numCoeffs+O2Struct.numBiases);
lb = [lb, log(0.5E7), zeros(1, O2Struct.numBiases), G_lb]; % MUISTA LISATA BIASET!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
ub = [ub, log(1E8), zeros(1, O2Struct.numBiases), G_ub]; % KORJAA

startPoints = createRandomStartPoints(lb, ub, numStartPoints);
%initGuess = list(startPoints);
ind = ub < 0.5;
ind(1:numCoeffs) = ub(1:numCoeffs) < 100;
initGuess = mean([lb;ub]);% - 0.001;
initGuess(ind) = -ub(ind);
ub(ind) = mode(ub(~ind));
TexInd = 2:numCoeffs; ub(TexInd) = mode(ub(TexInd));
lb = -ub;
tolX = options.TolX;
%fun = @(coeff)sum(modelMinimizationFunction(TexStruct, OStruct, N2Struct, HeStruct, rhoStruct, weights, tolX, coeff).^2);
fun = @(coeff)modelMinimizationFunction(TexStruct, OStruct, N2Struct, HeStruct, ArStruct, O2Struct, rhoStruct, dTCoeffs, T0Coeffs, weights, tolX, coeff);
%problem = createOptimProblem('lsqnonlin', 'x0', initGuess, 'objective', fun, 'options', options);

%tic;[optCoeff, fmin, flag, output, allmins] = run(multiStartSolver, problem, startPoints);toc;

%tic;[optCoeff, fval, flag, output] = patternsearch(fun, initGuess, [],[],[],[], lb, ub, [], options);toc
%tic;[optCoeff, fval, flag, output] = patternsearch(fun, initGuess, [],[],[],[], [], [], [], options);toc

%tic;[optCoeff, fval, flag, output] = fmincon(fun, initGuess, [],[],[],[], lb, ub, [], options);toc

setenv('OMP_NUM_THREADS', num2str(numThreads))
disp('Calling LM solver')
%tic;optCoeff = levenbergMarquardt_mex(TexStruct, OStruct, N2Struct, HeStruct, rhoStruct, dTCoeffs, T0Coeffs, weights, initGuess);toc;
[comp,J] = fun(initGuess); %disp([comp(1), optCoeff]);
JTJ_diag = diag(J'*J);

%tic; [optCoeff] = lsqnonlin(fun, initGuess, lb, ub, options);toc;

save('optCoeff.mat', 'optCoeff', '-v7.3');
TexInd = TexStruct.coeffInd; save('optCoeff.mat', 'TexInd', '-append');
HeInd = HeStruct.coeffInd; save('optCoeff.mat', 'HeInd', '-append');
OInd = OStruct.coeffInd; save('optCoeff.mat', 'OInd', '-append');
N2Ind = N2Struct.coeffInd; save('optCoeff.mat', 'N2Ind', '-append');
ArInd = ArStruct.coeffInd; save('optCoeff.mat', 'ArInd', '-append');
O2Ind = O2Struct.coeffInd; save('optCoeff.mat', 'O2Ind', '-append');
save('optCoeff.mat', 'dTCoeffs', '-append');
save('optCoeff.mat', 'T0Coeffs', '-append');

end

function weights = computeWeights(TexStruct, OStruct, N2Struct, HeStruct, ArStruct, O2Struct, rhoStruct)

dataLen = length(TexStruct.data) + length(OStruct.data) + length(N2Struct.data) + length(HeStruct.data) + length(rhoStruct.data)...
    + length(ArStruct.data) + length(O2Struct.data);
TempAndSpectrometerLen = dataLen - length(rhoStruct.data);
weights = ones(dataLen, 1);

meanRhoWeight = mean(rhoStruct.weights); numRho = length(rhoStruct.weights);

w = meanRhoWeight * (numRho / TempAndSpectrometerLen);
wInd = 1:TempAndSpectrometerLen;
weights(wInd) = w;
weights(1:length(TexStruct.data)) = 0.5 * w;

weights(wInd(end)+1:end) = rhoStruct.weights;

ae16h = [TexStruct.aeInt(:,4); OStruct.aeInt(:,4); N2Struct.aeInt(:,4); HeStruct.aeInt(:,4); ...
    ArStruct.aeInt(:,4); O2Struct.aeInt(:,4); rhoStruct.aeInt(:,4)];
aeNormalized = 1 + (2 * ae16h / max(ae16h));
weights = weights .* aeNormalized;

weights = sqrt(weights);

end

function stop = outfun(x, optimValues, state, dataLen)

t = sqrt(abs(optimValues.firstorderopt)/dataLen);
fprintf('%s\n', ['Normalized first-order opt.: ', num2str(t)])
stop = t < 0.005;

end