function readFiles()
%
if matlabpool('size') <= 0
    matlabpool open
end

[ae, timestampsAeDatenum] = readAeFiles();

apAll = readApFile(timestampsAeDatenum);

[F107values, F107datenum] = readF107File();

[absB, timestampsAbsB, timestampsAbsBDatenum, akasofuEpsilon, epsilonQualityFlag, timestampsEpsilon, timestampsEpsilonDatenum] = readSolarParameterFiles(timestampsAeDatenum);

[density, averagedDensity, averagedDensityNoBg, density3h, longitude, latitude, altitude, solarTime, magneticLatitude, crwindEast, crwindNorth, crwindUp, ...
    timestamps10sFixed, timestamps1min, timestamps1minFixed, timestamps1minFixedDatenum, timestampsDensityDatenum, firstDatenum] = readDensityFile(timestampsAeDatenum);

[F107A81Days, F107Yesterday] = giveF107ValsForMSIS(F107values, F107datenum, timestampsDensityDatenum);

[apNow, ap3h, ap6h, ap9h, apAver12To33h, apAver36To57h, ApDaily, ap, timestamps3h, timestamps3hFixed] =...
    giveApValsForMSIS(apAll, timestamps10sFixed, timestamps1minFixed, timestamps1min, timestampsDensityDatenum);

[densityNoBg, msisDensityVariableAlt, msisDensity270km] = relateMsisToDensity(density, altitude, timestampsDensityDatenum, timestamps10sFixed,...
    timestamps1min, latitude, longitude, F107A81Days, F107Yesterday, ae, ApDaily, apNow, ap3h, ap6h, ap9h, apAver12To33h, apAver36To57h);
measuredDensity = density;


if fclose('all') ~= 0
    display('File close unsuccesful - check if some of the files are reserved by another editor.')
end
               
save('GoceVariables.mat', 'ae', '-v6')
save('GoceVariables.mat', 'ap', '-v6', '-append')
save('GoceVariables.mat', 'absB', '-v6', '-append')
save('GoceVariables.mat', 'averagedDensity', '-v6', '-append')
save('GoceVariables.mat', 'averagedDensityNoBg', '-v6', '-append')
save('GoceVariables.mat', 'density3h', '-v6', '-append')
save('GoceVariables.mat', 'akasofuEpsilon', '-v6', '-append')
save('GoceVariables.mat', 'epsilonQualityFlag', '-v6', '-append')
save('GoceVariables.mat', 'longitude', '-v6', '-append')
save('GoceVariables.mat', 'latitude', '-v6', '-append')
save('GoceVariables.mat', 'altitude', '-v6', '-append')
save('GoceVariables.mat', 'solarTime', '-v6', '-append')
save('GoceVariables.mat', 'crwindEast', '-v6', '-append')
save('GoceVariables.mat', 'crwindNorth', '-v6', '-append')
save('GoceVariables.mat', 'crwindUp', '-v6', '-append')
save('GoceVariables.mat', 'magneticLatitude', '-v6', '-append')
save('GoceVariables.mat', 'densityNoBg', '-v6', '-append')
save('GoceVariables.mat', 'msisDensityVariableAlt', '-v6', '-append')
save('GoceVariables.mat', 'msisDensity270km', '-v6', '-append')
save('GoceVariables.mat', 'measuredDensity', '-v6', '-append')
save('GoceVariables.mat', 'timestamps10sFixed', '-v6', '-append')
save('GoceVariables.mat', 'timestamps1min', '-v6', '-append')
save('GoceVariables.mat', 'timestamps1minFixed', '-v6', '-append')
save('GoceVariables.mat', 'timestamps3h', '-v6', '-append')
save('GoceVariables.mat', 'timestamps3hFixed', '-v6', '-append')
save('GoceVariables.mat', 'timestampsAbsB', '-v6', '-append')
save('GoceVariables.mat', 'timestampsAbsBDatenum', '-v6', '-append')
save('GoceVariables.mat', 'timestampsDensityDatenum', '-v6', '-append')
save('GoceVariables.mat', 'timestampsAeDatenum', '-v6', '-append')
save('GoceVariables.mat', 'timestampsEpsilon', '-v6', '-append')
save('GoceVariables.mat', 'timestampsEpsilonDatenum', '-v6', '-append')
save('GoceVariables.mat', 'firstDatenum', '-v6', '-append')

end

function [ae, timestampsAeDatenum] = readAeFiles()
%
fprintf('%s\n', 'Began reading AE files')

ae = [];
timestampsAeDatenum = [];

aeFiles = dir('ae*');
parfor i = 1:length(aeFiles)
    aeFile = fopen(aeFiles(i).name);
    if aeFile == -1
        error('aeFile open unsuccesful')
    end

    aeData = textscan(aeFile, '%s %s %f %f %f %f %f', 'MultipleDelimsAsOne',1, 'HeaderLines',15);

    ae = [ae; aeData{4}];
    timestampsAeDatenum = [timestampsAeDatenum; datenum(strcat(aeData{1}, aeData{2}), 'yyyy-mm-ddHH:MM:SS.FFF')];
end
[timestampsAeDatenum, indicesToConserve, ~] = unique(timestampsAeDatenum);
ae = ae(indicesToConserve);

interpIndices = ae > 50000;
aeInterp = ae(~interpIndices);
tInterp = timestampsAeDatenum(~interpIndices);
ae = interp1(tInterp, aeInterp, timestampsAeDatenum, 'linear', 'extrap');

end

function ap = readApFile(timestampsAeDatenum)
%
fprintf('%s\n', 'Began reading ap file')

apFile = fopen('apData');
if apFile == -1
    error('ap File open unsuccesful! Check that you have a file "apData" in your WORKING DIRECTORY.')
end

apData = textscan(apFile, '%s %s %s %s %s %s %s %s %s %s %f %f %f %f %f %f %f %f %f', ...
    'delimiter', {' ', '+', '-'}, 'MultipleDelimsAsOne',1, 'HeaderLines',1);
apValues = horzcat(apData{11:18});

[row, ~] = find(isnan(apValues) | apValues >= 1000);
row = unique(row);
for i = 1:length(row)
    frewind(apFile);
    nanLine = textscan(apFile, '%s', 1, 'delimiter', '\n', 'HeaderLines', row(i));
    nanLine = nanLine{1}(1);
    correctValue = nan(52, 1);
    for k = 31:3:52
     correctValue(k) = str2double(horzcat(nanLine{1}(k-2), nanLine{1}(k-1), nanLine{1}(k)));
    end
    correctValue = correctValue(~isnan(correctValue));
    apValues(row(i), :) = correctValue;
end

timestampsAp = datenum(apData{1}, 'yyyymmdd');
apRows = find(timestampsAp >= timestampsAeDatenum(1) - 3 & timestampsAp <= timestampsAeDatenum(end));
ap = reshape(apValues(apRows, :)', numel(apValues(apRows, :)), 1);

end

function [F107values, F107datenum] = readF107File
%
fprintf('%s\n', 'Began reading F107 file')

F107File = fopen('F107data');
if F107File == -1
    error('F10.7 File open unsuccesful! Check that you have a file "F107data" in your WORKING DIRECTORY.')
end

F10data = textscan(F107File, '%f %f %f %f', 'MultipleDelimsAsOne',1);
F107values = F10data{4};
F10year = F10data{1};
F10dayOfYear = F10data{2};
F107datenum = datenum(F10year, 1, 1) + F10dayOfYear - 1;

indicesToConserve = find(F107values < 990);
tF107ToInterpolate = F107datenum(indicesToConserve);
F107valuesToInterpolate = F107values(indicesToConserve);
F107values = interp1(tF107ToInterpolate, F107valuesToInterpolate, F107datenum, 'linear', 'extrap');

end

function [absB, timestampsAbsB, timestampsAbsBDatenum, akasofuEpsilon, epsilonQualityFlag, timestampsEpsilon, timestampsEpsilonDatenum] = readSolarParameterFiles(timestampsAeDatenum)
%
fprintf('%s\n', 'Began reading IMF and SW files')

imfFiles = dir('ac_h0s_mfi*');

if isempty(imfFiles)
    error('No IMF B files found! Make sure there are files beginning "ac_h0s_mfi_*" in the WORKING DIRECTORY')
end

timestampsBDatenum = [];
Bx = [];
By = [];
Bz = [];
for i = 1:length(imfFiles)
     data = cdfread(imfFiles(i).name, 'CombineRecords',true, 'ConvertEpochToDatenum',true);
     timestampsBDatenum = [timestampsBDatenum; data{1}];
     Bx = [Bx; data{2}(1:3:end)'];
     By = [By; data{2}(2:3:end)'];
     Bz = [Bz; data{2}(3:3:end)'];
end
[timestampsBDatenum, indicesToConserve, ~] = unique(timestampsBDatenum);
Bx = Bx(indicesToConserve);
By = By(indicesToConserve);
Bz = Bz(indicesToConserve);
B2 = Bx.^2 + By.^2 + Bz.^2;
theta = atan(By ./ Bz);

indicesToConserve = find(Bx > -1e30 & By > -1e30 & Bz > -1e30);

tBNoNans = timestampsBDatenum(indicesToConserve);
thetaNoNans = theta(indicesToConserve);
B2NoNans = B2(indicesToConserve);

tBToInterpolate = timestampsAeDatenum(timestampsAeDatenum>=min(timestampsBDatenum) & timestampsAeDatenum<=max(timestampsBDatenum));
tThetaToInterpolate = tBToInterpolate;
B2Interpolated = interp1(tBNoNans, B2NoNans, tBToInterpolate, 'linear', 'extrap');
thetaInterpolated = interp1(tBNoNans, thetaNoNans, tThetaToInterpolate, 'linear', 'extrap');

secondsInDay = 24 * 60 * 60;
absB = sqrt(B2Interpolated);
timestampsAbsB = round((tBToInterpolate-tBToInterpolate(1))*secondsInDay + find(timestampsAeDatenum<tBToInterpolate(1), 1, 'last') * 60);
timestampsAbsBDatenum = tBToInterpolate;

solarWindFiles = dir('ac_h0s_swe*');

if isempty(solarWindFiles)
    error('No Solar Wind files found! Make sure there are files beginning "ac_h0s_swe_*" in the WORKING DIRECTORY')
end

timestampsVDatenum = [];
Vx = [];
Vy = [];
Vz = [];
for i = 1:length(solarWindFiles)
     data = cdfread(solarWindFiles(i).name, 'CombineRecords',true, 'ConvertEpochToDatenum',true);
     timestampsVDatenum = [timestampsVDatenum; data{1}];
     Vx = [Vx; data{2}(1:3:end)'];
     Vy = [Vy; data{2}(2:3:end)'];
     Vz = [Vz; data{2}(3:3:end)'];
end
[timestampsVDatenum, indicesToConserve, ~] = unique(timestampsVDatenum);
Vx = Vx(indicesToConserve);
Vy = Vy(indicesToConserve);
Vz = Vz(indicesToConserve);
V = sqrt(Vx.^2 + Vy.^2 + Vz.^2);
indicesToConserve = find(Vx > -1e30 & Vy > -1e30 & Vz > -1e30);
tVNoNans = timestampsVDatenum(indicesToConserve);
VNoNans = V(indicesToConserve);

tVToInterpolate = timestampsAeDatenum(timestampsAeDatenum>=min(timestampsVDatenum) & timestampsAeDatenum<=max(timestampsVDatenum));
VInterpolated = interp1(tVNoNans, VNoNans, tVToInterpolate, 'linear', 'extrap');
% timesToNeareastNonNan = arrayfun(@(x) min(abs(tVNoNans - x)), tVToInterpolate);
% epsilonQualityFlag = ones(length(tVToInterpolate), 1);
% epsilonQualityFlag(timesToNeareastNonNan > oneMinuteInDays) = 0;  
commonIndices = timestampsVDatenum >= min(tVToInterpolate) & timestampsVDatenum <= max(tVToInterpolate);
badDataIndices = ~ismember(timestampsVDatenum(commonIndices), tVNoNans);
epsilonQualityFlag = ones(length(tVToInterpolate), 1);
epsilonQualityFlag(badDataIndices) = 0; 

VInterpolated = VInterpolated(ismember(tVToInterpolate, tBToInterpolate)) * 1000;
epsilonQualityFlag = epsilonQualityFlag(ismember(tVToInterpolate, tBToInterpolate));
B2Interpolated = B2Interpolated(ismember(tBToInterpolate, tVToInterpolate)) * 1e-9;
thetaInterpolated = thetaInterpolated(ismember(tThetaToInterpolate, tVToInterpolate));

akasofuEpsilon = VInterpolated .* B2Interpolated .* sin(thetaInterpolated * 0.5).^4; 
tVToInterpolate = tVToInterpolate(ismember(tVToInterpolate, tBToInterpolate));
timestampsEpsilon = round((tVToInterpolate-tVToInterpolate(1))*secondsInDay + find(timestampsAeDatenum<tVToInterpolate(1), 1, 'last') * 60);
timestampsEpsilonDatenum = tVToInterpolate;

end

function [density, averagedDensity, averagedDensityNoBg, density3h, longitude, latitude, altitude, solarTime, magneticLatitude, crwindEast, crwindNorth, crwindUp,...
    timestamps10sFixed, timestamps1min, timestamps1minFixed, timestamps1minFixedDatenum, timestampsDensityDatenum, firstDatenum] = ...
    readDensityFile(timestampsAeDatenum)
%
fprintf('%s\n', 'Began reading density files')

densityFiles = dir('goce_dens*');

density = [];
longitude = [];
latitude = [];
altitude = [];
solarTime = [];
crwindEast = [];
crwindNorth = [];
crwindUp = [];
timestampsDensityDatenum = [];

secondsInDay = 60 * 60 * 24;
parfor i = 1:length(densityFiles)
    densityFile = fopen(densityFiles(i).name);

    if densityFile == -1
        error('densityFile open unsuccesful')
    end

    densityData = textscan(densityFile, '%s %s %s %f %f %f %f %f %f %f %f %f', 'commentStyle','#');

    density = [density; densityData{9} * power(10, 11)];
    longitude = [longitude; densityData{5}];
    latitude = [latitude; densityData{6}];
    altitude = [altitude; densityData{4}];
    solarTime = [solarTime; densityData{7}];
    crwindEast = [crwindEast; densityData{8}];
    crwindNorth = [crwindNorth; densityData{9}];
    crwindUp = [crwindUp; densityData{10}];
    
    timestampsDensityDatenum = [timestampsDensityDatenum; datenum(strcat(densityData{1}, densityData{2}), 'yyyy-mm-ddHH:MM:SS.FFF')];
end

[timestampsDensityDatenum, indicesToConserve, ~] = unique(timestampsDensityDatenum);
density = density(indicesToConserve);
longitude = longitude(indicesToConserve);
latitude = latitude(indicesToConserve);
altitude = altitude(indicesToConserve);
solarTime = solarTime(indicesToConserve);
crwindEast = crwindEast(indicesToConserve);
crwindNorth = crwindNorth(indicesToConserve);
crwindUp = crwindUp(indicesToConserve);

magneticLatitude = convertToMagneticCoordinates(latitude, longitude, altitude);

averagedDensity = smooth(density, 7);
averagedDensity = averagedDensity(ismember(timestampsDensityDatenum, timestampsAeDatenum));
averagedDensityNoBg = removePeriodicBackground(averagedDensity, 125, 1, 0);
averagedDensityNoBg = normalize(averagedDensityNoBg, averagedDensity);

timestamps10sFixed = timestampsDensityDatenum * secondsInDay;
timestamps1minFixed = timestamps10sFixed(ismember(timestampsDensityDatenum, timestampsAeDatenum));
timestamps1minFixedDatenum = timestampsDensityDatenum(ismember(timestampsDensityDatenum, timestampsAeDatenum));
firstDatenum = datenum(datestr(timestampsDensityDatenum(1), 'yyyy-mm-dd'), 'yyyy-mm-dd');
timestamps10sFixed = timestamps10sFixed - firstDatenum * secondsInDay;
timestamps1minFixed = timestamps1minFixed - firstDatenum * secondsInDay;
timestamps10sFixed = round(timestamps10sFixed);
timestamps1minFixed = round(timestamps1minFixed);
timestamps1min = round((timestampsAeDatenum - firstDatenum) * secondsInDay);

lastDatenum = datenum(datestr(timestampsDensityDatenum(end), 'yyyy-mm-dd'), 'yyyy-mm-dd');
threeHinSec = 3 * 60 * 60;
timestamps3h = threeHinSec : threeHinSec : ceil(lastDatenum - firstDatenum + 1) * secondsInDay;
density3h = smooth(averagedDensity, 179);
density3h = density3h(find(ismember(timestamps1minFixed, timestamps3h)) - 90);

end

function [F107A81Days, F107Yesterday] = giveF107ValsForMSIS(F107values, F107datenum, timestampsDensityDatenum)
%
fprintf('%s\n', 'Computing F107 values for msis')

F107beginDay = floor(timestampsDensityDatenum(1)) - 81;
F107endDay = floor(timestampsDensityDatenum(end));
F107values = F107values(F107datenum >= F107beginDay & F107datenum <= F107endDay);
F107datenum = (F107beginDay:F107endDay)';
F107smoothed = smooth(F107values, 81);
yesterdayDatenums = floor(timestampsDensityDatenum) - 1;
uniqueDatenums = unique(yesterdayDatenums, 'stable');
F107Yesterday = zeros(length(yesterdayDatenums), 1);
F107A81Days = zeros(length(yesterdayDatenums), 1);
k = 1;
for i = 1:length(uniqueDatenums)
    numOfOccurences = length(find(yesterdayDatenums == uniqueDatenums(i)));
    F107Yesterday(k:numOfOccurences + k - 1) = F107values(F107datenum == uniqueDatenums(i));
    F107A81Days(k:numOfOccurences + k - 1) = F107smoothed(find(F107datenum == uniqueDatenums(i)) - 40);
    k = k + numOfOccurences;
end

end

function [apNow, ap3h, ap6h, ap9h, apAver12To33h, apAver36To57h, ApDaily, apAllFixed, timestamps3h, timestamps3hFixed] = ...
    giveApValsForMSIS(apAll, timestamps10sFixed, timestamps1minFixed, timestamps1min, timestampsDensityDatenum)
% 
fprintf('%s\n', 'Computing ap values for msis')

threeHinSec = 3 * 60 * 60;
secondsInDay = 24 * 60 * 60;
firstDatenum = datenum(datestr(timestampsDensityDatenum(1), 'yyyy-mm-dd'));
lastDatenum = datenum(datestr(timestampsDensityDatenum(end), 'yyyy-mm-dd'));
timestamps3h = -3 * 8 * threeHinSec + threeHinSec : threeHinSec : ceil(lastDatenum - firstDatenum + 1) * secondsInDay;
timestamps10s = min(timestamps10sFixed) : 10 : max(timestamps10sFixed);
% nextThreeHStamp = threeHinSec * floor(timestamps10s / threeHinSec) + threeHinSec;
nextThreeHStamp = threeHinSec * ceil(timestamps10s / threeHinSec);

ap10s = reshape(repmat(apAll', 180 * 6, 1),[],1);
apTime10s = reshape(repmat(timestamps3h, 180 * 6, 1),[],1);
ap10s(1) = [];
apTime10s(1) = [];
apNow = ap10s(ismember(apTime10s, nextThreeHStamp));
ap3h = ap10s(ismember(apTime10s, nextThreeHStamp - threeHinSec));
ap6h = ap10s(ismember(apTime10s, nextThreeHStamp - 2 * threeHinSec));
ap9h = ap10s(ismember(apTime10s, nextThreeHStamp - 3 * threeHinSec));
ap10sSmoothed = reshape(repmat(smooth(apAll, 9)', 180 * 6, 1),[],1);
ap10sSmoothed(1) = [];
apAver12To33h = ap10sSmoothed(ismember(apTime10s, nextThreeHStamp - 8 * threeHinSec));
apAver36To57h = ap10sSmoothed(ismember(apTime10s, nextThreeHStamp - 16 * threeHinSec));
ApDaily = ap10sSmoothed(ismember(apTime10s, nextThreeHStamp - 4 * threeHinSec));

finalIndices = ismember(timestamps10s, timestamps10sFixed);
apNow = apNow(finalIndices);
ap3h = ap3h(finalIndices);
ap6h = ap6h(finalIndices);
ap9h = ap9h(finalIndices);
apAver12To33h = apAver12To33h(finalIndices);
apAver36To57h = apAver36To57h(finalIndices);
ApDaily = ApDaily(finalIndices);

timestamps3h(timestamps3h <= 0) = -1;
apAllFixed = apAll(ismember(timestamps3h, timestamps1min));
timestamps3hFixed = timestamps3h(ismember(timestamps3h, timestamps1minFixed))';
timestamps3h = timestamps3h(ismember(timestamps3h, timestamps1min))';

end

function [correctedDensity, msisDensityVariableAlt, msisDensity270km] = relateMsisToDensity(density, altitude, timestampsDatenum, timestamps10s, ...
    timestamps1min, latitude,longtitude, F107A, F107, ae, ApDaily, apNow, ap3h, ap6h, ap9h, apAver12To33h, apAver36To57h)
% [correctedDensity] = subtractMsisFromDensity(density, altitude,
% timestampsDatenum, latitude, longtitude, F107A, F107, ap)
fprintf('%s\n', 'Computing normalized densities with msis')

correctedDensity = zeros(size(density));
msisDensity270km = zeros(size(density));
msisDensityVariableAlt = zeros(size(density));

modelingIndices = 1:length(density);

altitudeKm = altitude / 1000;

parfor i = modelingIndices
    modelVariableAlt = run_nrlmsise00(altitudeKm(i), timestampsDatenum(i), latitude(i), longtitude(i), F107A(i), F107(i),...
        ApDaily(i), apNow(i), ap3h(i), ap6h(i), ap9h(i), apAver12To33h(i), apAver36To57h(i));
    modelConst270km = run_nrlmsise00(270, timestampsDatenum(i), latitude(i), longtitude(i), F107A(i), F107(i),...
        ApDaily(i), apNow(i), ap3h(i), ap6h(i), ap9h(i), apAver12To33h(i), apAver36To57h(i));
    correctedDensity(i) = density(i) * modelConst270km(:,7) / modelVariableAlt(:,7);
    msisDensity270km(i) = 1000 * modelConst270km(:,7);
    msisDensityVariableAlt(i) = 1000 * modelVariableAlt(:,7);
end

msisDensityVariableAlt = msisDensityVariableAlt * power(10, 11);
msisDensity270km = msisDensity270km * power(10, 11);

plot(timestamps10s, density, timestamps10s, msisDensityVariableAlt);

plotCorrelation(msisDensityVariableAlt, density, 'NRLMSISE00 density', 'GOCE measured density')

end

function plotCorrelation(xvals, yvals, xvalName, yvalName)
%

r = corr(xvals, yvals);
r2 = r * r;
fprintf('%s %f\n', 'Pearson correlation: ', r)
fprintf('%s %d %s\n', 'Thus, ', round(r2 * 100), ['% of variation in ', yvalName, ' can be explained by changes in ', xvalName])

end

function [values] = removePeriodicBackground( values, removeShorterPeriods, samplingFreq, plotOrNot )
% [averagedDensity] = removePeriodicBackground( values, removeShorterPeriods, samplingFreq, plotOrNot )

numOfSamples = length(values);
valueFFT = fft(values);
Freq = (0:numOfSamples - 1) * samplingFreq / numOfSamples;
period = 1 ./ Freq;

if plotOrNot > 0
    figure;
    plotIndices = find(period < 500);
    plot(period(plotIndices), abs(valueFFT(plotIndices)))
    title('Density FFT')
    xlabel('T / min')
end

indicesToRemove = period < removeShorterPeriods;
valueFFT(indicesToRemove) = 0;

values = abs(ifft(valueFFT));

end

function [magneticLatitude] = convertToMagneticCoordinates(latitude, longitude, altitude)
% [magneticLatitude] = convertToMagneticCoordinates(latitude, longitude, altitude)

ecefXYZ = geod2ecef(latitude, longitude, altitude)';
ecefToMagTransform = [0.33907 -0.91964 -0.19826; ...
                      0.93826  0.34594  0      ; ...
                      0.06859  0.18602  0.98015];
magXYZ = ecefToMagTransform * ecefXYZ;
r = sqrt(magXYZ(1,:).^2 + magXYZ(2,:).^2 + magXYZ(3,:).^2);
magneticLatitude = pi/2 - acos(magXYZ(3,:) ./ r);
magneticLatitude = magneticLatitude' * 180 / pi;

end

function [x, y, z] = geod2ecef(latitude, longitude, altitude)

% GEOD2ECEF Convert geodetic coordinates to ECEF coordinates.
% 
% Usage: [X, Y, Z] = GEOD2ECEF(LATITUDE, LONGITUDE, ALTITUDE)
%     or [X, Y, Z] = GEOD2ECEF(LLA)
%     or XYZ = GEOD2ECEF(LATITUDE, LONGITUDE, ALTITUDE)
%     or XYZ = GEOD2ECEF(LLA)
% 
% Converts geodetic coordinates LATITUDE, LONGITUDE, and ALTITUDE to
% Earth-centered, Earth fixed (ECEF) coordinates X, Y, and Z. The inputs
% can either be three separate arguments or 1 matrix. For a matrix input,
% the first dimension with length 3 is assumed to have the three separate
% LATITUDE, LONGITUDE, and ALTITUDE inputs across it. The World Geodetic
% System 1984 (WGS84) ellipsoid model of the Earth is assumed.
% 
% Inputs:
%   -LATITUDE: Geodetic latitude in degrees.
%   -LONGITUDE: Geodetic longitude in degrees.
%   -ALTITUDE: Height above the Earth in meters.
%   -LLA: Matrix with at least one dimension with length 3, the first of
%   which corresponding to the dimension across which the three inputs
%   above go.
% 
% Ouputs:
%   -X: x coordinates of the point in meters.
%   -Y: y coordinates of the point in meters.
%   -Z: z coordinates of the point in meters.
%   -XYZ: When just one output is requested, the three outputs above are
%   returned as a row vector for scalar inputs, an M-by-3 matrix for column
%   vector inputs, a 3-by-M matrix for row vector inputs, or the three
%   outputs concatenated either along the next largest dimension when the
%   inputs are separate arguments or the same dimension that the inputs
%   went across when a single matrix is input.
% 
% Copyright (c) 2011, Drew Compston
% All rights reserved.
% 
% Redistribution and use in source and binary forms, with or without
% modification, are permitted provided that the following conditions are
% met:
% 
%     * Redistributions of source code must retain the above copyright
%       notice, this list of conditions and the following disclaimer.
%     * Redistributions in binary form must reproduce the above copyright
%       notice, this list of conditions and the following disclaimer in
%       the documentation and/or other materials provided with the distribution
% 
% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
% AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
% IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
% ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
% LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
% CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
% SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
% INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
% CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
% ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
% POSSIBILITY OF SUCH DAMAGE.


% Input checking/conversion.
narginchk(1, 3);
if nargin == 1
    sizelatitude = size(latitude);
    first3 = find(sizelatitude == 3, 1, 'first');
    latitude = reshape(permute(latitude, [first3, 1:(first3 - 1), ...
        (first3 + 1):ndims(latitude)]), 3, []);
    sizelatitude(first3) = 1;
    longitude = reshape(latitude(2, :), sizelatitude);
    altitude = reshape(latitude(3, :), sizelatitude);
    latitude = reshape(latitude(1, :), sizelatitude);
end
latitude = latitude*pi/180; longitude = longitude*pi/180;

% WGS84 parameters.
a = 6378137; f = 1/298.257223563; b = a*(1 - f); e2 = 1 - (b/a)^2;

% Conversion from:
% en.wikipedia.org/wiki/Geodetic_system#Conversion_calculations
Nphi = a ./ sqrt(1 - e2*sin(latitude).^2);
x = (Nphi + altitude).*cos(latitude).*cos(longitude);
y = (Nphi + altitude).*cos(latitude).*sin(longitude);
z = (Nphi.*(1 - e2) + altitude).*sin(latitude);

% Shape output according to number of arguments.
if nargout <= 1
    if nargin == 1
        x = cat(first3, x, y, z);
    else
        dims = ndims(x);
        if dims == 2
            if size(x, 2) == 1
                x = [x, y, z];
            else
                x = [x; y; x];
            end
        else
            x = cat(dims + 1, x, y, z);
        end
    end
end

end