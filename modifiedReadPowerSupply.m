%{
 libm2k API documentation: https://analogdevicesinc.github.io/libm2k/index.html
 libm2k toolbox download: https://www.mathworks.com/matlabcentral/fileexchange/74385-libm2k-matlab
 Analog Device ADALM-2000 with MATLAB: https://wiki.analog.com/university/tools/m2k/matlab

 To set up the programming environment for interfacing ADALM-2000 using
 MATLAB, please follow these steps:
    1. Download MATLAB 2024b (you must use the 2024b version).
    2. Download the M2K driver on your computer.
    3. Download libm2k toolbox.
    4. Add the libm2k library folder to the MATLAB search path.
 
 Please refer to the document, "Libm2k library Setup in MATLAB 2024b.pdf", for 
 more details regarding step 3 and step 4.

 This script:
 1. Connects to ADALM-2000
 2. Sets power supply voltage to 1.7V
 3. Reads Analog Input 1
 4. Computes and plots mean and std dev every 0.5s for 5s total
%}

clear

% Open m2k context
m2k = clib.libm2k.libm2k.context.m2kOpen();
pause(1)

% Check if device is connected
if clibIsNull(m2k)
    clib.libm2k.libm2k.context.contextCloseAll();
    clear m2k
    error("m2k object is null. Restart MATLAB or check device connection and search path.")
end

% Get analog input and power supply objects
analogInputObj = m2k.getAnalogIn();
powerSupplyObj = m2k.getPowerSupply();

% Calibrate ADC and DAC
m2k.calibrateADC();
m2k.calibrateDAC();

% Enable power supply and set V+ to 1.7V
powerSupplyObj.enableChannel(0, true);
powerSupplyObj.pushChannel(0, 1.7);

% Enable analog input channel 0 (1+ and 1-)
analogInputObj.enableChannel(0, true);

% Display one instantaneous reading
disp("Instantaneous voltage reading from channel 1:");
disp(analogInputObj.getVoltage(0));

% Set up acquisition parameters
sampleRate = 100000; % 100k samples/sec
analogInputObj.setSampleRate(sampleRate);

totalDurationSec = 5;
intervalSec = 0.5;
samplesPerInterval = round(intervalSec * sampleRate);
numIntervals = totalDurationSec / intervalSec;

% Prepare for acquisition
analogInputObj.setKernelBuffersCount(1);
% Allocate arrays
meanVals = zeros(1, numIntervals);
stdVals = zeros(1, numIntervals);
timeVec = (0:numIntervals - 1) * intervalSec;

% Main acquisition loop
disp("Starting measurement over 5 seconds...");
for i = 1:numIntervals
    clibSamples = analogInputObj.getSamplesInterleaved_matlab(samplesPerInterval * 2);
    clibSamplesArray = double(clibSamples);
    ch1Samples = clibSamplesArray(1:2:end); % Channel 1 only

    meanVals(i) = mean(ch1Samples);
    stdVals(i) = std(ch1Samples);
end
disp("Measurement complete.");

% Plot results
figure;
subplot(2,1,1);
plot(timeVec, meanVals, '-o', 'LineWidth', 1.5);
title('Mean Voltage Over Time');
xlabel('Time (s)');
ylabel('Mean Voltage (V)');
grid on;

subplot(2,1,2);
plot(timeVec, stdVals, '-o', 'LineWidth', 1.5);
title('Standard Deviation Over Time');
xlabel('Time (s)');
ylabel('Voltage Std Dev (V)');
grid on;

% Clean up
clib.libm2k.libm2k.context.contextCloseAll();
clear m2k
