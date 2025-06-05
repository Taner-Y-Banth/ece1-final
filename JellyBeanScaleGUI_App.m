classdef JellyBeanScaleGUI_App < matlab.apps.AppBase
    % Properties that correspond to app components
    properties (Access = public)
        UIFigure                     matlab.ui.Figure
        MainGridLayout               matlab.ui.container.GridLayout % For overall layout

        ConnectionSetupPanel         matlab.ui.container.Panel
        ConnectM2KButton             matlab.ui.control.Button
        CalibrateADCDACButton        matlab.ui.control.Button
        PowerSupplyVoltageEditFieldLabel matlab.ui.control.Label
        PowerSupplyVoltageEditField  matlab.ui.control.NumericEditField
        SetPowerSupplyButton         matlab.ui.control.Button
        DisconnectM2KButton          matlab.ui.control.Button
        ScaleSettingsPanel           matlab.ui.container.Panel
        WeighingDurationEditFieldLabel matlab.ui.control.Label
        WeighingDurationEditField    matlab.ui.control.NumericEditField
        SampleRateHzEditFieldLabel   matlab.ui.control.Label
        SampleRateEditField          matlab.ui.control.NumericEditField
        AvgJellyBeanWeightGramsEditFieldLabel matlab.ui.control.Label
        AvgJellyBeanWeightGramsEditField matlab.ui.control.NumericEditField
        CalibrationPanel             matlab.ui.container.Panel
        CalibrationMassGramsEditFieldLabel matlab.ui.control.Label
        CalibrationMassGramsEditField matlab.ui.control.NumericEditField
        StartCalibrationProcessButton matlab.ui.control.Button
        CalibrationStepInstructionLabel matlab.ui.control.Label
        ConfirmTareStepButton         matlab.ui.control.Button
        ConfirmMeasurementStepButton  matlab.ui.control.Button
        CancelCalibrationButton       matlab.ui.control.Button
        CalibrationStatusLabel       matlab.ui.control.Label
        DirectFactorPanel            matlab.ui.container.Panel
        ReferenceVoltageMvEditFieldLabel matlab.ui.control.Label
        ReferenceVoltageMvEditField  matlab.ui.control.NumericEditField
        EquivalentGramsEditFieldLabel matlab.ui.control.Label
        EquivalentGramsEditField     matlab.ui.control.NumericEditField
        ApplyDirectFactorButton      matlab.ui.control.Button
        OperationPanel               matlab.ui.container.Panel
        TareButton                   matlab.ui.control.Button
        MeasureWeightButton          matlab.ui.control.Button
        TareStatusLabel              matlab.ui.control.Label
        OutputDisplayPanel           matlab.ui.container.Panel
        InstantVoltageLabel          matlab.ui.control.Label
        AverageVoltageDisplayLabel   matlab.ui.control.Label
        WeightDisplayLabel           matlab.ui.control.Label
        JellyBeanCountDisplayLabel   matlab.ui.control.Label
        StatusTextLabel              matlab.ui.control.Label
        StatusText                   matlab.ui.control.TextArea
        
        SimulationPanel_App         matlab.ui.container.Panel 
        SimulatedWeightEditFieldLabel_App matlab.ui.control.Label
        SimulatedWeightEditField_App matlab.ui.control.NumericEditField
        SetSimulatedLoadButton_App  matlab.ui.control.Button
        SimulatedVoltageLabel_App   matlab.ui.control.Label
        EnableSimulationCheckBox    matlab.ui.control.CheckBox 

        % Graphing Axes
        StdDevOverTimePlotAxes       matlab.ui.control.UIAxes 
        CalibrationCurveAxes         matlab.ui.control.UIAxes
    end

    % Properties that correspond to app data
    properties (Access = private)
        m2kDevice
        analogInput
        powerSupply
        analogOutput 
        
        tareVoltage                  = 0; 
        gramsPerVolt                 = 0;
        isScaleCalibrated            = false;
        isTared                      = false;
        avgJellyBeanWeightGrams      = 1.10; 
        currentSampleRate            = 100000;
        currentWeighingDuration      = 1.0; % Duration for averaging voltage for weight
        lastAverageVoltage           = 0;   
        currentWeightGrams           = 0;
        currentJellyBeanCount        = 0;
        isConnected                  = false;
        currentPowerSupplyVoltage    = 2.5; 
        initComponentsComplete       = false;
        
        calibrationState             = 0;    
        calibrationTareVoltage       = 0;    

        maxSimulatedWeightGrams_App = 2000 
        maxDacVoltage_App = 2.5            
        minDacVoltage_App = 0.0

        % Data for plots
        calibrationPlotVoltages     = [];
        calibrationPlotWeights      = [];

        intraRunTimePoints          = []; % Time points within a single measurement run for StdDev plot
        intraRunStdDevs             = []; % StdDev values for each chunk in a single run
    end

    methods (Access = private)

        function startupFcn(app)
            disp('StartupFcn starting...');
            app.StatusText.Value = {'App Started. Please connect to M2K.'};
            updateButtonStates(app);
            updateStatusLabels(app);
            updateOutputDisplays(app); 
            updateCalibrationUIState(app);
            app.initComponentsComplete = true;
            resetStdDevPlot(app);     
            resetCalibrationPlot(app);  
            disp('StartupFcn completed. initComponentsComplete=true.');
        end

        function updateCalibrationUIState(app)
            isIdle = (app.calibrationState == 0);
            isStep1_AwaitUserTareConfirm = (app.calibrationState == 1);
            isStep2_AwaitUserMeasureConfirm = (app.calibrationState == 2);
            canProceedWithCal = app.isConnected; 

            app.CalibrationMassGramsEditField.Enable = escritura((isIdle && canProceedWithCal), 'on', 'off');
            app.StartCalibrationProcessButton.Enable = escritura(canProceedWithCal, 'on', 'off');
            
            if isIdle
                app.StartCalibrationProcessButton.Text = 'Start New Calibration';
            else
                app.StartCalibrationProcessButton.Text = 'Restart Calibration Process'; 
            end
            
            app.ConfirmTareStepButton.Enable = escritura((isStep1_AwaitUserTareConfirm && canProceedWithCal), 'on', 'off');
            app.ConfirmTareStepButton.Visible = escritura(isStep1_AwaitUserTareConfirm, 'on', 'off');
            
            app.ConfirmMeasurementStepButton.Enable = escritura((isStep2_AwaitUserMeasureConfirm && canProceedWithCal), 'on', 'off');
            app.ConfirmMeasurementStepButton.Visible = escritura(isStep2_AwaitUserMeasureConfirm, 'on', 'off');

            app.CancelCalibrationButton.Enable = escritura((~isIdle && canProceedWithCal), 'on', 'off');
            app.CancelCalibrationButton.Visible = escritura(~isIdle, 'on', 'off');

            if ~canProceedWithCal && isIdle 
                app.CalibrationStepInstructionLabel.Text = 'Connect M2K to enable calibration.';
            elseif isIdle
                app.CalibrationStepInstructionLabel.Text = 'Enter Ref. Mass & click "Start New Calibration".';
            elseif isStep1_AwaitUserTareConfirm
                app.CalibrationStepInstructionLabel.Text = '1. Ensure scale is EMPTY. Press main "Tare Scale" button, THEN click "Confirm Scale is Tared" above.';
            elseif isStep2_AwaitUserMeasureConfirm
                mass_val = app.CalibrationMassGramsEditField.Value;
                app.CalibrationStepInstructionLabel.Text = ['2. Place ', num2str(mass_val), 'g on physical scale. Press main "Measure Weight" button, THEN click "Confirm Mass is Measured" above.'];
            end
        end

        function StartCalibrationProcessButtonPushed(app, event)
            if ~app.isConnected
                app.StatusText.Value = [app.StatusText.Value; {'Error: M2K not connected for calibration.'}];
                return;
            end
            calibMass = app.CalibrationMassGramsEditField.Value;
            if calibMass <= 0
                app.StatusText.Value = [app.StatusText.Value; {'Error: Reference mass must be positive.'}];
                return;
            end
            
            app.calibrationState = 1; 
            app.isScaleCalibrated = false; 
            app.gramsPerVolt = 0;
            resetCalibrationPlot(app); 
            app.StatusText.Value = {['Reference weight calibration started. Reference Mass: ', num2str(calibMass), 'g.']};
            app.StatusText.Value = [app.StatusText.Value; {'Please follow instructions in the Calibration panel.'}];
            updateCalibrationUIState(app);
            updateStatusLabels(app); 
        end

        function ConfirmTareStepButtonPushed(app, event)
            if ~app.isConnected || app.calibrationState ~= 1
                return; 
            end

            if ~app.isTared 
                app.StatusText.Value = [app.StatusText.Value; {'Error: Scale not tared. Press main "Tare Scale" button first.'}];
                uiwait(msgbox('Please press the main "Tare Scale" button in the Operation Panel before confirming this step.', 'Tare Required', 'warn'));
                return;
            end

            app.calibrationTareVoltage = app.tareVoltage; 
            app.StatusText.Value = [app.StatusText.Value; {['Tare confirmed for calibration. Tare Voltage used: ', num2str(app.calibrationTareVoltage, '%.4f'), ' V']}];
            
            app.calibrationPlotVoltages = [app.calibrationTareVoltage];
            app.calibrationPlotWeights = [0]; 
            updateCalibrationPlot(app);

            app.calibrationState = 2; 
            updateCalibrationUIState(app);
        end

        function ConfirmMeasurementStepButtonPushed(app, event)
            if ~app.isConnected || app.calibrationState ~= 2
                return;
            end
            
            voltageWithMass = app.lastAverageVoltage; 
            app.StatusText.Value = [app.StatusText.Value; {['Measurement with mass confirmed for calibration. Voltage used: ', num2str(voltageWithMass, '%.4f'), ' V']}];
            
            calibMass = app.CalibrationMassGramsEditField.Value;
            voltageDifference = voltageWithMass - app.calibrationTareVoltage;

            if abs(voltageDifference) < 1e-7 
                app.StatusText.Value = [app.StatusText.Value; {'Error: Voltage difference for calibration is too small. Check signal conditioning.'}];
                app.isScaleCalibrated = false;
                app.gramsPerVolt = 0;
            else
                app.gramsPerVolt = calibMass / voltageDifference;
                app.isScaleCalibrated = true;
                app.StatusText.Value = [app.StatusText.Value; {['Scale calibrated successfully! Factor: ', num2str(app.gramsPerVolt, '%.4f'), ' g/V.']}];
                
                app.calibrationPlotVoltages = [app.calibrationPlotVoltages, voltageWithMass];
                app.calibrationPlotWeights = [app.calibrationPlotWeights, calibMass];
                updateCalibrationPlot(app); 
            end
            
            app.calibrationState = 0; 
            updateCalibrationUIState(app);
            updateStatusLabels(app); 
            updateOutputDisplays(app); 
        end

        function CancelCalibrationButtonPushed(app, event)
            app.calibrationState = 0;
            resetCalibrationPlot(app);
            app.StatusText.Value = [app.StatusText.Value; {'Reference weight calibration process cancelled.'}];
            updateCalibrationUIState(app);
        end
        
        function ConnectM2KButtonPushed(app, event)
            app.StatusText.Value = {'Connecting to M2K...'}; drawnow;
            try
                app.m2kDevice = clib.libm2k.libm2k.context.m2kOpen(); pause(1);
                if clibIsNull(app.m2kDevice)
                    clib.libm2k.libm2k.context.contextCloseAll(); app.m2kDevice = [];
                    app.StatusText.Value = {'Error: M2K object is null. Check connection & libm2k path.'}; app.isConnected = false;
                else
                    app.analogInput = app.m2kDevice.getAnalogIn(); 
                    app.powerSupply = app.m2kDevice.getPowerSupply();
                    app.analogOutput = app.m2kDevice.getAnalogOut(); 

                    app.m2kDevice.calibrateADC();
                    app.m2kDevice.calibrateDAC();

                    app.analogInput.enableChannel(0, true);
                    app.analogInput.setSampleRate(app.currentSampleRate); 
                    app.analogInput.setKernelBuffersCount(1);
                    
                    if ~isempty(app.analogOutput) && isobject(app.analogOutput) && isvalid(app.analogOutput)
                        app.analogOutput.enableChannel(0,true);
                        app.analogOutput.setVoltage(0, app.minDacVoltage_App);
                         if isvalid(app.SimulatedVoltageLabel_App)
                            app.SimulatedVoltageLabel_App.Text = ['DAC W1: ',num2str(app.minDacVoltage_App, '%.3f'),'V (0g)'];
                         end
                    end

                    app.StatusText.Value = {'M2K Connected.'}; app.isConnected = true;
                    app.isScaleCalibrated = false; app.isTared = false; 
                    app.tareVoltage = 0; app.gramsPerVolt = 0;
                    app.calibrationState = 0; 
                    resetStdDevPlot(app); 
                    resetCalibrationPlot(app);
                end
            catch ME
                app.StatusText.Value = {['Connection Error: ', ME.message], ME.getReport('basic','hyperlinks','off')};
                app.m2kDevice = []; app.isConnected = false; 
                try clib.libm2k.libm2k.context.contextCloseAll(); catch; end 
            end
            updateButtonStates(app); 
            updateStatusLabels(app); 
            updateOutputDisplays(app);
            updateCalibrationUIState(app);
        end

        function DisconnectM2KButtonPushed(app, event)
            app.StatusText.Value = {'Disconnecting M2K...'}; drawnow;
            cleanupM2K(app); 
            app.StatusText.Value = {'M2K Disconnected.'};
            app.isScaleCalibrated = false; 
            app.isTared = false; 
            app.tareVoltage = 0; 
            app.gramsPerVolt = 0;
            app.lastAverageVoltage = 0; 
            app.currentWeightGrams = 0; 
            app.currentJellyBeanCount = 0;
            app.calibrationState = 0; 
            resetStdDevPlot(app); 
            resetCalibrationPlot(app);
            updateButtonStates(app); 
            updateStatusLabels(app); 
            updateOutputDisplays(app);
            updateCalibrationUIState(app);
        end

        function CalibrateADCDACButtonPushed(app, event)
            if ~app.isConnected || isempty(app.m2kDevice) || clibIsNull(app.m2kDevice)
                app.StatusText.Value = [app.StatusText.Value; {'Error: M2K not connected for ADC/DAC calibration.'}];
                return; 
            end
            app.StatusText.Value = [app.StatusText.Value; {'Calibrating M2K ADC/DAC...'}]; drawnow;
            try
                app.m2kDevice.calibrateADC(); 
                app.m2kDevice.calibrateDAC();
                app.StatusText.Value = [app.StatusText.Value; {'M2K ADC/DAC Calibrated.'}];
            catch ME
                app.StatusText.Value = [app.StatusText.Value; {['Error during M2K ADC/DAC calibration: ', ME.message]}];
            end
        end

        function SetPowerSupplyButtonPushed(app, event)
            if ~app.isConnected || isempty(app.powerSupply)
                app.StatusText.Value = [app.StatusText.Value; {'Error: M2K not connected or power supply unavailable.'}];
                return; 
            end
            app.currentPowerSupplyVoltage = app.PowerSupplyVoltageEditField.Value;
            app.StatusText.Value = [app.StatusText.Value; {['Setting V+ to ', num2str(app.currentPowerSupplyVoltage), 'V...']}]; 
            drawnow;
            try
                app.powerSupply.enableChannel(0, true); 
                app.powerSupply.pushChannel(0, app.currentPowerSupplyVoltage);
                app.StatusText.Value = [app.StatusText.Value; {['V+ set to ', num2str(app.currentPowerSupplyVoltage), 'V. This should excite your load cell circuit.']}];
            catch ME
                app.StatusText.Value = [app.StatusText.Value; {['Error setting power supply: ', ME.message]}];
            end
        end
        
        function ApplyDirectFactorButtonPushed(app, event)
            if ~app.isConnected 
                app.StatusText.Value = [app.StatusText.Value; {'Error: M2K should be connected to apply direct factor (for consistency).'}];
                return;
            end

            refMv = app.ReferenceVoltageMvEditField.Value;
            eqGrams = app.EquivalentGramsEditField.Value;

            if refMv == 0 
                app.StatusText.Value = [app.StatusText.Value; {'Error: Reference mV cannot be zero for direct factor.'}];
                return;
            end
            if eqGrams <= 0
                app.StatusText.Value = [app.StatusText.Value; {'Error: Equivalent grams must be positive for direct factor.'}];
                return;
            end
            
            app.gramsPerVolt = eqGrams / (refMv / 1000); 
            app.isScaleCalibrated = true;
            app.isTared = false; 
            app.tareVoltage = 0; 
            app.calibrationState = 0; 
            resetCalibrationPlot(app); 
            
            app.StatusText.Value = {['Direct calibration factor applied. New Factor: ', num2str(app.gramsPerVolt, '%.4f'), ' g/V.']};
            app.StatusText.Value = [app.StatusText.Value; {'Please press "Tare Scale" if needed.'}];
            
            updateStatusLabels(app);
            updateButtonStates(app); 
            updateOutputDisplays(app);
        end
        
        function TareButtonPushed(app, event)
            if ~app.isConnected || isempty(app.analogInput)
                app.StatusText.Value = [app.StatusText.Value; {'Error: M2K not connected for Tare.'}];
                return;
            end
            
            app.StatusText.Value = [app.StatusText.Value; {'Taring Scale (reading current voltage as zero reference)...'}];
            drawnow;
            
            try
                app.analogInput.enableChannel(0, true);
                activeSampleRate = app.SampleRateEditField.Value;
                app.analogInput.setSampleRate(activeSampleRate);
                
                tareDuration = 0.5; 
                samplesForTare = round(tareDuration * activeSampleRate);

                if samplesForTare <= 0
                    app.StatusText.Value = [app.StatusText.Value; {'Error: Samples for tare would be zero. Check sample rate/duration.'}];
                    return;
                end
                app.analogInput.setKernelBuffersCount(1);
                
                numTareReadings = 5;
                tareVoltageReadings = zeros(1, numTareReadings);
                validReadingCount = 0;
                for k = 1:numTareReadings
                    rawSamplesToRequest = max(200, samplesForTare); 
                    clibSamples = app.analogInput.getSamplesInterleaved_matlab(rawSamplesToRequest * 2); 
                    
                    if isempty(clibSamples)
                        app.StatusText.Value = [app.StatusText.Value; {['Warning: No samples received during tare reading #', num2str(k)]}];
                        if k==1 && numTareReadings > 1 
                             app.isTared = false; updateStatusLabels(app); return; 
                        end
                        break; 
                    end
                    ch1Samples = double(clibSamples(1:2:end)); 
                    if ~isempty(ch1Samples)
                        tareVoltageReadings(k) = mean(ch1Samples);
                        validReadingCount = validReadingCount + 1;
                    else
                         app.StatusText.Value = [app.StatusText.Value; {['Warning: Empty ch1Samples during tare reading #', num2str(k)]}];
                         if k==1 && numTareReadings > 1, app.isTared = false; updateStatusLabels(app); return; end
                         break;
                    end
                    pause(0.02); 
                end
                
                if validReadingCount > 0
                    app.tareVoltage = mean(tareVoltageReadings(1:validReadingCount)); 
                    app.isTared = true;
                    app.lastAverageVoltage = app.tareVoltage; 
                    app.StatusText.Value = [app.StatusText.Value; {['Scale Tared. New Tare Voltage: ', num2str(app.tareVoltage, '%.4f'), ' V']}];
                else
                     app.StatusText.Value = [app.StatusText.Value; {'Error: Failed to get any valid readings for tare.'}];
                     app.isTared = false;
                end
                
            catch ME
                app.StatusText.Value = [app.StatusText.Value; {['Error during tare: ', ME.message], ME.getReport('basic','hyperlinks','off')}];
                app.isTared = false;
            end
            
            updateStatusLabels(app);
            updateOutputDisplays(app); 
        end

        function MeasureWeightButtonPushed(app, event)
            if ~app.isConnected || isempty(app.analogInput)
                app.StatusText.Value = [app.StatusText.Value; {'Error: M2K not connected for Measurement.'}];
                return;
            end
        
            statusMsg = {};
            if ~app.isScaleCalibrated
                statusMsg{end+1} = 'Warning: Scale not calibrated.';
            end
            if ~app.isTared
                statusMsg{end+1} = 'Warning: Scale not tared.';
            end
            if app.calibrationState == 2 
                 statusMsg{end+1} = 'Measurement for calibration step 2.';
            end
            app.StatusText.Value = [statusMsg, {'Measuring weight...'}];
            drawnow;
        
            resetStdDevPlot(app); % Clear previous run's std dev plot
            app.intraRunTimePoints = [];
            app.intraRunStdDevs = [];
            allSamplesForRun = []; % To store all samples for overall average
        
            try
                app.analogInput.enableChannel(0, true);
                
                % Instantaneous voltage (optional, can be removed if too slow)
                try
                    instVoltage = app.analogInput.getVoltage(0);
                    if isvalid(app.InstantVoltageLabel)
                        app.InstantVoltageLabel.Text = ['Inst. V: ', num2str(instVoltage, '%.4f')];
                    end
                catch me_inst
                     if isvalid(app.InstantVoltageLabel), app.InstantVoltageLabel.Text = 'Inst. V: Error'; end
                     disp(['Warn: Inst. V: ', me_inst.message]);
                end
        
                app.currentSampleRate = app.SampleRateEditField.Value;
                totalDurationSec = app.WeighingDurationEditField.Value; % This is the total duration for averaging
                
                chunkDurationSec = 0.5; % Process in 0.5s chunks for StdDev plot
                numChunks = floor(totalDurationSec / chunkDurationSec);
                if numChunks == 0, numChunks = 1; end % Ensure at least one chunk
                
                samplesPerChunk = round(chunkDurationSec * app.currentSampleRate);
                if samplesPerChunk <= 0
                     app.StatusText.Value = [app.StatusText.Value; {'Error: Samples per chunk is zero. Check Sample Rate and 0.5s chunk time.'}]; return;
                end

                app.analogInput.setSampleRate(app.currentSampleRate);
                app.analogInput.setKernelBuffersCount(1); 
        
                for k_chunk = 1:numChunks
                    currentTimeInRun = (k_chunk -1) * chunkDurationSec;
                    app.StatusText.Value = [statusMsg, {['Measuring chunk ', num2str(k_chunk), '/', num2str(numChunks), '...']}]; drawnow;

                    clibSamplesChunk = app.analogInput.getSamplesInterleaved_matlab(samplesPerChunk * 2);
                    ch1SamplesChunk = double(clibSamplesChunk(1:2:end));
        
                    if isempty(ch1SamplesChunk)
                        app.StatusText.Value = [app.StatusText.Value; {['Warning: No samples in chunk ', num2str(k_chunk)]}];
                        currentChunkStdDev = NaN;
                    else
                        currentChunkStdDev = std(ch1SamplesChunk);
                        allSamplesForRun = [allSamplesForRun; ch1SamplesChunk(:)]; % Append to total samples
                    end
                    
                    app.intraRunTimePoints = [app.intraRunTimePoints, currentTimeInRun + chunkDurationSec/2]; % Midpoint of chunk
                    app.intraRunStdDevs = [app.intraRunStdDevs, currentChunkStdDev];
                    updateStdDevPlot(app); % Update plot for each chunk
                end
        
                if isempty(allSamplesForRun)
                    app.StatusText.Value = [app.StatusText.Value; {'Warning: No samples received during entire measurement run.'}];
                    app.lastAverageVoltage = app.tareVoltage; 
                else
                    app.lastAverageVoltage = mean(allSamplesForRun);
                end
                
                app.StatusText.Value = [app.StatusText.Value; {'Measurement complete.'}];
                updateOutputDisplays(app);
        
            catch ME
                app.StatusText.Value = {['Error during measurement: ', ME.message], ME.getReport('basic', 'hyperlinks','off')};
                app.lastAverageVoltage = app.tareVoltage; 
                updateOutputDisplays(app); 
            end
        end

        function UIFigureCloseRequest(app, event)
            if isvalid(app) && isprop(app,'StatusText') && isvalid(app.StatusText)
                app.StatusText.Value = {'Closing App & Disconnecting M2K...'}; 
            end
            drawnow; 
            cleanupM2K(app); 
            delete(app);
        end

        function updateButtonStates(app)
            isConnectedState = app.isConnected;
            
            app.ConnectM2KButton.Enable = escritura(~isConnectedState, 'on', 'off');
            app.DisconnectM2KButton.Enable = escritura(isConnectedState, 'on', 'off');
            app.CalibrateADCDACButton.Enable = escritura(isConnectedState, 'on', 'off');
            app.SetPowerSupplyButton.Enable = escritura(isConnectedState, 'on', 'off');
            
            app.ApplyDirectFactorButton.Enable = escritura(isConnectedState, 'on', 'off');
            app.TareButton.Enable = escritura(isConnectedState, 'on', 'off');
            app.MeasureWeightButton.Enable = escritura(isConnectedState, 'on', 'off');
            
            if isprop(app, 'SetSimulatedLoadButton_App') && isvalid(app.SetSimulatedLoadButton_App)
                app.SetSimulatedLoadButton_App.Enable = escritura(isConnectedState && app.EnableSimulationCheckBox.Value, 'on', 'off');
            end
            if isprop(app, 'EnableSimulationCheckBox') && isvalid(app.EnableSimulationCheckBox)
                app.EnableSimulationCheckBox.Enable = escritura(isConnectedState, 'on', 'off');
            end

            updateCalibrationUIState(app); 
        end

        function updateStatusLabels(app)
            if app.isScaleCalibrated
                app.CalibrationStatusLabel.Text = ['Calibration: Calibrated (', num2str(app.gramsPerVolt, '%.2e'), ' g/V)'];
                app.CalibrationStatusLabel.FontColor = [0 0.5 0]; 
            else
                app.CalibrationStatusLabel.Text = 'Calibration: Not Calibrated';
                app.CalibrationStatusLabel.FontColor = [0.8 0 0]; 
            end

            if app.isTared
                app.TareStatusLabel.Text = ['Tare: Tared (Offset V: ', num2str(app.tareVoltage, '%.4f'), ')'];
                app.TareStatusLabel.FontColor = [0 0.5 0]; 
            else
                app.TareStatusLabel.Text = 'Tare: Not Tared';
                app.TareStatusLabel.FontColor = [0.8 0 0]; 
            end
        end
        
        function updateOutputDisplays(app)
            if isvalid(app.AverageVoltageDisplayLabel)
                app.AverageVoltageDisplayLabel.Text = ['Avg. Voltage: ', num2str(app.lastAverageVoltage, '%.4f'), ' V'];
            end

            if app.isScaleCalibrated && ~isempty(app.gramsPerVolt) && app.gramsPerVolt ~= 0
                app.currentWeightGrams = (app.lastAverageVoltage - app.tareVoltage) * app.gramsPerVolt;
                if isvalid(app.WeightDisplayLabel)
                    app.WeightDisplayLabel.Text = ['Weight: ', num2str(app.currentWeightGrams, '%.2f'), ' g'];
                end

                if app.avgJellyBeanWeightGrams > 0
                    app.currentJellyBeanCount = round(app.currentWeightGrams / app.avgJellyBeanWeightGrams);
                    app.currentJellyBeanCount(app.currentJellyBeanCount < 0) = 0; 
                    if isvalid(app.JellyBeanCountDisplayLabel)
                        app.JellyBeanCountDisplayLabel.Text = ['Jelly Beans: ~', num2str(app.currentJellyBeanCount)];
                    end
                else
                    if isvalid(app.JellyBeanCountDisplayLabel)
                        app.JellyBeanCountDisplayLabel.Text = 'Jelly Beans: Enter avg. bean wt.';
                    end
                end
            else
                if isvalid(app.WeightDisplayLabel)
                    app.WeightDisplayLabel.Text = 'Weight: --- g (Not Calibrated)';
                end
                if isvalid(app.JellyBeanCountDisplayLabel)
                    app.JellyBeanCountDisplayLabel.Text = 'Jelly Beans: --- (Not Calibrated)';
                end
            end
        end

        function cleanupM2K(app)
            if isvalid(app) 
                try
                    if isprop(app, 'analogOutput') && ~isempty(app.analogOutput) && isobject(app.analogOutput) && isvalid(app.analogOutput)
                        app.analogOutput.setVoltage(0,0); 
                        app.analogOutput.enableChannel(0, false); 
                         if isprop(app,'StatusText') && isvalid(app.StatusText), app.StatusText.Value = [app.StatusText.Value; {'Analog output channel disabled.'}]; end
                    end
                catch ME_ao_disable
                    if isprop(app,'StatusText') && isvalid(app.StatusText), app.StatusText.Value = [app.StatusText.Value; {['Warn: AO disable: ', ME_ao_disable.message]}]; else, disp(['Warn: AO disable: ', ME_ao_disable.message]); end
                end
                try
                    if isprop(app, 'analogInput') && ~isempty(app.analogInput) && isobject(app.analogInput) && isvalid(app.analogInput)
                        app.analogInput.enableChannel(0, false); 
                         if isprop(app,'StatusText') && isvalid(app.StatusText), app.StatusText.Value = [app.StatusText.Value; {'Analog input channel disabled.'}]; end
                    end
                catch ME_ai_disable
                    if isprop(app,'StatusText') && isvalid(app.StatusText), app.StatusText.Value = [app.StatusText.Value; {['Warn: AI disable: ', ME_ai_disable.message]}]; else, disp(['Warn: AI disable: ', ME_ai_disable.message]); end
                end
                try
                    if isprop(app, 'powerSupply') && ~isempty(app.powerSupply) && isobject(app.powerSupply) && isvalid(app.powerSupply)
                         app.powerSupply.enableChannel(0, false); 
                         if isprop(app,'StatusText') && isvalid(app.StatusText), app.StatusText.Value = [app.StatusText.Value; {'Power supply V+ channel disabled.'}]; end
                    end
                catch ME_ps_disable
                    if isprop(app,'StatusText') && isvalid(app.StatusText), app.StatusText.Value = [app.StatusText.Value; {['Warn: PS disable: ', ME_ps_disable.message]}]; else, disp(['Warn: PS disable: ', ME_ps_disable.message]); end
                end

                if ~isempty(app.m2kDevice) && ~clibIsNull(app.m2kDevice)
                    try
                        clib.libm2k.libm2k.context.contextCloseAll();
                        if isprop(app,'StatusText') && isvalid(app.StatusText), app.StatusText.Value = [app.StatusText.Value; {'M2K contextCloseAll called.'}]; end
                    catch ME_context
                        dispMsg = {['ERROR: M2K contextCloseAll: ', ME_context.message]};
                        if isprop(app,'StatusText') && isvalid(app.StatusText)
                             app.StatusText.Value = [app.StatusText.Value; dispMsg]; 
                        else, disp(dispMsg{1}); 
                        end
                    end
                end
                
                app.m2kDevice = []; 
                app.analogInput = []; 
                app.powerSupply = []; 
                app.analogOutput = [];
                app.isConnected = false;

                if isprop(app, 'InstantVoltageLabel') && isvalid(app.InstantVoltageLabel)
                    app.InstantVoltageLabel.Text = 'Inst. Voltage: -- V'; 
                end
                 if isprop(app, 'SimulatedVoltageLabel_App') && isvalid(app.SimulatedVoltageLabel_App)
                    app.SimulatedVoltageLabel_App.Text = 'DAC W1: ---V';
                end
            end
        end

        function avgJellyBeanWeightChanged(app, src, event)
            if ~app.initComponentsComplete, return; end 

            if isvalid(app) && isprop(app, 'AvgJellyBeanWeightGramsEditField') && isvalid(app.AvgJellyBeanWeightGramsEditField)
                newWeight = app.AvgJellyBeanWeightGramsEditField.Value;
                if newWeight <= 0
                    if isprop(app, 'StatusText') && isvalid(app.StatusText)
                        app.StatusText.Value = [app.StatusText.Value; {'Warning: Avg. jelly bean weight must be positive.'}];
                    end
                else
                    app.avgJellyBeanWeightGrams = newWeight;
                end
            end
            updateOutputDisplays(app); 
        end

        function SetSimulatedLoadButton_AppPushed(app, event)
            if ~app.isConnected || isempty(app.analogOutput) || ~isobject(app.analogOutput) || ~isvalid(app.analogOutput) || ~app.EnableSimulationCheckBox.Value
                app.StatusText.Value = [app.StatusText.Value; {'Error: M2K not connected, DAC not available, or simulation not enabled.'}];
                return;
            end
            simWeight = app.SimulatedWeightEditField_App.Value;
            if simWeight < 0, simWeight = 0; app.SimulatedWeightEditField_App.Value = 0; end
            if simWeight > app.maxSimulatedWeightGrams_App, simWeight = app.maxSimulatedWeightGrams_App; app.SimulatedWeightEditField_App.Value = app.maxSimulatedWeightGrams_App; end

            dacVoltage = app.minDacVoltage_App + (simWeight / app.maxSimulatedWeightGrams_App) * (app.maxDacVoltage_App - app.minDacVoltage_App);
            try
                app.analogOutput.setVoltage(0, dacVoltage);
                app.SimulatedVoltageLabel_App.Text = ['DAC W1: ',num2str(dacVoltage, '%.3f'),'V (', num2str(simWeight), 'g)'];
                app.StatusText.Value = [app.StatusText.Value; {['Simulation: DAC set to ', num2str(dacVoltage, '%.3f'), 'V for ', num2str(simWeight),'g.']}];
            catch ME
                app.StatusText.Value = [app.StatusText.Value; {['Error setting sim DAC: ', ME.message]}];
            end
        end
        
        function EnableSimulationCheckBoxValueChanged(app, event)
            if ~app.initComponentsComplete, return; end
            simModeEnabled = app.EnableSimulationCheckBox.Value;
            if isprop(app, 'SetSimulatedLoadButton_App') && isvalid(app.SetSimulatedLoadButton_App)
                app.SetSimulatedLoadButton_App.Enable = escritura(app.isConnected && simModeEnabled, 'on', 'off');
            end
            if isprop(app, 'SimulatedWeightEditField_App') && isvalid(app.SimulatedWeightEditField_App)
                app.SimulatedWeightEditField_App.Enable = escritura(app.isConnected && simModeEnabled, 'on', 'off');
            end
            if simModeEnabled
                app.StatusText.Value = [app.StatusText.Value; {'Simulation Mode for Calibration ENABLED. Calibration will use DAC output.'}];
            else
                app.StatusText.Value = [app.StatusText.Value; {'Simulation Mode for Calibration DISABLED. Calibration will use ADC input from physical scale.'}];
            end
             updateButtonStates(app); 
        end

        % --- Plotting Helper Functions ---
        function resetStdDevPlot(app) 
            app.intraRunStdDevs = [];
            app.intraRunTimePoints = [];
            if ishandle(app.StdDevOverTimePlotAxes) && isvalid(app.StdDevOverTimePlotAxes)
                cla(app.StdDevOverTimePlotAxes);
                title(app.StdDevOverTimePlotAxes, 'Voltage Std. Dev. (within current run)');
                xlabel(app.StdDevOverTimePlotAxes, 'Time within Run (s)');
                ylabel(app.StdDevOverTimePlotAxes, 'Std. Dev. of Voltage (V)');
                grid(app.StdDevOverTimePlotAxes, 'on');
            end
        end

        function updateStdDevPlot(app) 
            if ishandle(app.StdDevOverTimePlotAxes) && isvalid(app.StdDevOverTimePlotAxes) && ~isempty(app.intraRunTimePoints) && ~isempty(app.intraRunStdDevs)
                plot(app.StdDevOverTimePlotAxes, app.intraRunTimePoints, app.intraRunStdDevs, 'o-m', 'MarkerFaceColor', 'm');
                xlabel(app.StdDevOverTimePlotAxes, 'Time within Run (s)');
                ylabel(app.StdDevOverTimePlotAxes, 'Std. Dev. of Voltage (V)');
                title(app.StdDevOverTimePlotAxes, 'Voltage Std. Dev. (within current run)');
                grid(app.StdDevOverTimePlotAxes, 'on');
                if ~isempty(app.intraRunTimePoints)
                    xlim(app.StdDevOverTimePlotAxes, [0, max(app.intraRunTimePoints) + 0.25]); % Extend x-axis a bit
                end
                ylim(app.StdDevOverTimePlotAxes, 'auto');
            end
        end

        function resetCalibrationPlot(app)
            app.calibrationPlotVoltages = [];
            app.calibrationPlotWeights = [];
            if ishandle(app.CalibrationCurveAxes) && isvalid(app.CalibrationCurveAxes)
                cla(app.CalibrationCurveAxes);
                title(app.CalibrationCurveAxes, 'Calibration Curve (Voltage vs. Weight)');
                xlabel(app.CalibrationCurveAxes, 'Voltage (V)');
                ylabel(app.CalibrationCurveAxes, 'Weight (g)');
                grid(app.CalibrationCurveAxes, 'on');
                legend(app.CalibrationCurveAxes, 'off'); 
            end
        end

        function updateCalibrationPlot(app)
            if ishandle(app.CalibrationCurveAxes) && isvalid(app.CalibrationCurveAxes) && ~isempty(app.calibrationPlotVoltages) && ~isempty(app.calibrationPlotWeights)
                plot(app.CalibrationCurveAxes, app.calibrationPlotVoltages, app.calibrationPlotWeights, 'o', 'MarkerSize', 8, 'MarkerFaceColor', 'b', 'DisplayName', 'Calibration Points');
                hold(app.CalibrationCurveAxes, 'on');
                
                if app.isScaleCalibrated && ~isempty(app.gramsPerVolt) && app.gramsPerVolt ~= 0 
                    v_at_0g = app.calibrationTareVoltage;
                    v_at_2000g = app.calibrationTareVoltage + (2000 / app.gramsPerVolt);
                    
                    all_voltages_for_range = [app.calibrationPlotVoltages, v_at_0g, v_at_2000g];
                    v_plot_min_overall = min(all_voltages_for_range);
                    v_plot_max_overall = max(all_voltages_for_range);

                    padding = 0.1 * (v_plot_max_overall - v_plot_min_overall);
                    if padding == 0, padding = 0.1; end 
                    
                    v_line_plot_vals = linspace(v_plot_min_overall - padding, v_plot_max_overall + padding, 100);
                    weight_fit_extended = (v_line_plot_vals - app.calibrationTareVoltage) * app.gramsPerVolt;
                    
                    plot(app.CalibrationCurveAxes, v_line_plot_vals, weight_fit_extended, 'r--', 'LineWidth', 1.5, 'DisplayName', 'Fitted Line');
                    legend(app.CalibrationCurveAxes, 'show', 'Location', 'best');
                else
                    legend(app.CalibrationCurveAxes, 'off'); 
                end
                
                hold(app.CalibrationCurveAxes, 'off');
                xlabel(app.CalibrationCurveAxes, 'Voltage (V)');
                ylabel(app.CalibrationCurveAxes, 'Weight (g)');
                title(app.CalibrationCurveAxes, 'Calibration Curve (Voltage vs. Weight)');
                grid(app.CalibrationCurveAxes, 'on');
                ylim(app.CalibrationCurveAxes, [-100 2100]); 
                xlim(app.CalibrationCurveAxes, 'auto'); 
            end
        end
    end
    
    methods (Access = private)

        function createComponents(app)
            disp('createComponents starting...');
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [50 50 1250 750]; 
            app.UIFigure.Name = 'M2K Weighing Scale GUI - Final Demo with Graphs';
            app.UIFigure.Scrollable = 'on'; 
            app.UIFigure.CloseRequestFcn = createCallbackFcn(app, @UIFigureCloseRequest, true);

            app.MainGridLayout = uigridlayout(app.UIFigure);
            app.MainGridLayout.ColumnWidth = {'1x', '1x', '1.5x'}; 
            app.MainGridLayout.RowHeight = {'fit', 'fit', 'fit', '1x', 'fit'}; 

            app.ConnectionSetupPanel = uipanel(app.MainGridLayout, 'Title', 'M2K Connection & Power', 'Scrollable', 'on');
            app.ConnectionSetupPanel.Layout.Row = 1;
            app.ConnectionSetupPanel.Layout.Column = 1;
            gl_conn = uigridlayout(app.ConnectionSetupPanel); 
            gl_conn.RowHeight = {'fit','fit','fit'}; gl_conn.ColumnWidth = {'fit','1x','fit'};
            app.ConnectM2KButton = uibutton(gl_conn, 'push', 'Text', 'Connect M2K', 'ButtonPushedFcn', createCallbackFcn(app, @ConnectM2KButtonPushed, true));
            app.ConnectM2KButton.Layout.Row = 1; app.ConnectM2KButton.Layout.Column = 1;
            app.DisconnectM2KButton = uibutton(gl_conn, 'push', 'Text', 'Disconnect M2K', 'ButtonPushedFcn', createCallbackFcn(app, @DisconnectM2KButtonPushed, true));
            app.DisconnectM2KButton.Layout.Row = 1; app.DisconnectM2KButton.Layout.Column = 2;
            app.CalibrateADCDACButton = uibutton(gl_conn, 'push', 'Text', 'Calibrate ADC/DAC', 'ButtonPushedFcn', createCallbackFcn(app, @CalibrateADCDACButtonPushed, true));
            app.CalibrateADCDACButton.Layout.Row = 1; app.CalibrateADCDACButton.Layout.Column = 3;
            app.PowerSupplyVoltageEditFieldLabel = uilabel(gl_conn, 'Text', 'V+ (V):', 'HorizontalAlignment', 'right');
            app.PowerSupplyVoltageEditFieldLabel.Layout.Row = 2; app.PowerSupplyVoltageEditFieldLabel.Layout.Column = 1;
            app.PowerSupplyVoltageEditField = uieditfield(gl_conn, 'numeric', 'Limits', [-5 5], 'ValueDisplayFormat', '%.2f', 'Value', app.currentPowerSupplyVoltage);
            app.PowerSupplyVoltageEditField.Layout.Row = 2; app.PowerSupplyVoltageEditField.Layout.Column = 2;
            app.SetPowerSupplyButton = uibutton(gl_conn, 'push', 'Text', 'Set V+', 'ButtonPushedFcn', createCallbackFcn(app, @SetPowerSupplyButtonPushed, true));
            app.SetPowerSupplyButton.Layout.Row = 2; app.SetPowerSupplyButton.Layout.Column = 3;

            app.ScaleSettingsPanel = uipanel(app.MainGridLayout, 'Title', 'Scale Measurement Settings', 'Scrollable', 'on');
            app.ScaleSettingsPanel.Layout.Row = 2;
            app.ScaleSettingsPanel.Layout.Column = 1;
            gl_scale = uigridlayout(app.ScaleSettingsPanel); gl_scale.RowHeight = {'fit','fit','fit'}; gl_scale.ColumnWidth = {'fit','1x'};
            app.SampleRateHzEditFieldLabel = uilabel(gl_scale, 'Text', 'Sample Rate (Hz):', 'HorizontalAlignment', 'right');
            app.SampleRateHzEditFieldLabel.Layout.Row=1; app.SampleRateHzEditFieldLabel.Layout.Column=1;
            app.SampleRateEditField = uieditfield(gl_scale, 'numeric', 'Limits', [1 Inf], 'ValueDisplayFormat', '%d', 'Value', app.currentSampleRate);
            app.SampleRateEditField.Layout.Row=1; app.SampleRateEditField.Layout.Column=2;
            app.WeighingDurationEditFieldLabel = uilabel(gl_scale, 'Text', 'Weighing Avg. Time (s):', 'HorizontalAlignment', 'right');
            app.WeighingDurationEditFieldLabel.Layout.Row=2; app.WeighingDurationEditFieldLabel.Layout.Column=1;
            app.WeighingDurationEditField = uieditfield(gl_scale, 'numeric', 'Limits', [0.01 Inf], 'ValueDisplayFormat', '%.2f', 'Value', app.currentWeighingDuration);
            app.WeighingDurationEditField.Layout.Row=2; app.WeighingDurationEditField.Layout.Column=2;
            app.AvgJellyBeanWeightGramsEditFieldLabel = uilabel(gl_scale, 'Text', 'Avg. Jelly Bean Wt. (g):', 'HorizontalAlignment', 'right');
            app.AvgJellyBeanWeightGramsEditFieldLabel.Layout.Row=3; app.AvgJellyBeanWeightGramsEditFieldLabel.Layout.Column=1;
            app.AvgJellyBeanWeightGramsEditField = uieditfield(gl_scale, 'numeric', 'Limits', [0.001 Inf], 'ValueDisplayFormat', '%.3f', 'Value', app.avgJellyBeanWeightGrams, 'ValueChangedFcn', createCallbackFcn(app, @avgJellyBeanWeightChanged, true));
            app.AvgJellyBeanWeightGramsEditField.Layout.Row=3; app.AvgJellyBeanWeightGramsEditField.Layout.Column=2;

            app.CalibrationPanel = uipanel(app.MainGridLayout, 'Title', 'Scale Calibration', 'Scrollable', 'on');
            app.CalibrationPanel.Layout.Row = 3;
            app.CalibrationPanel.Layout.Column = 1;
            gl_calib = uigridlayout(app.CalibrationPanel); 
            uilabel(gl_calib, 'Text', 'Reference Weight Method:', 'FontWeight', 'bold');
            gl_calib_mass_row = uigridlayout(gl_calib); gl_calib_mass_row.ColumnWidth = {'fit','1x','fit'}; gl_calib_mass_row.Padding = [0 0 0 0];
            app.CalibrationMassGramsEditFieldLabel = uilabel(gl_calib_mass_row, 'Text', 'Ref. Mass (g):', 'HorizontalAlignment', 'right');
            app.CalibrationMassGramsEditField = uieditfield(gl_calib_mass_row, 'numeric', 'Limits', [0.001 Inf], 'Value', 100);
            app.StartCalibrationProcessButton = uibutton(gl_calib_mass_row, 'push', 'Text', 'Start New Calibration', 'ButtonPushedFcn', createCallbackFcn(app, @StartCalibrationProcessButtonPushed, true));
            app.CalibrationStepInstructionLabel = uilabel(gl_calib, 'Text', 'Instructions appear here.', 'HorizontalAlignment', 'center');
            app.ConfirmTareStepButton = uibutton(gl_calib, 'push', 'Text', 'Confirm Scale is Tared', 'ButtonPushedFcn', createCallbackFcn(app, @ConfirmTareStepButtonPushed, true), 'Visible', 'off');
            app.ConfirmMeasurementStepButton = uibutton(gl_calib, 'push', 'Text', 'Confirm Mass is Measured', 'ButtonPushedFcn', createCallbackFcn(app, @ConfirmMeasurementStepButtonPushed, true), 'Visible', 'off');
            app.CalibrationStatusLabel = uilabel(gl_calib, 'Text', 'Calibration: Not Calibrated', 'FontWeight', 'bold');
            app.DirectFactorPanel = uipanel(gl_calib, 'Title', 'Direct Factor Input (Alternative)');
                gl_direct = uigridlayout(app.DirectFactorPanel, [2,3]); 
                gl_direct.RowHeight={'fit','fit'}; gl_direct.ColumnWidth = {'fit','1x','fit'};
                app.ReferenceVoltageMvEditFieldLabel = uilabel(gl_direct, 'Text', 'If change of (mV):', 'HorizontalAlignment', 'right');
                app.ReferenceVoltageMvEditFieldLabel.Layout.Row=1; app.ReferenceVoltageMvEditFieldLabel.Layout.Column=1;
                app.ReferenceVoltageMvEditField = uieditfield(gl_direct, 'numeric', 'Value', 100);
                app.ReferenceVoltageMvEditField.Layout.Row=1; app.ReferenceVoltageMvEditField.Layout.Column=2;
                app.EquivalentGramsEditFieldLabel = uilabel(gl_direct, 'Text', 'Equals (grams):', 'HorizontalAlignment', 'right');
                app.EquivalentGramsEditFieldLabel.Layout.Row=2; app.EquivalentGramsEditFieldLabel.Layout.Column=1;
                app.EquivalentGramsEditField = uieditfield(gl_direct, 'numeric', 'Limits', [0.001 Inf], 'Value', 50);
                app.EquivalentGramsEditField.Layout.Row=2; app.EquivalentGramsEditField.Layout.Column=2;
                app.ApplyDirectFactorButton = uibutton(gl_direct, 'push', 'Text', 'Apply Direct Factor', 'ButtonPushedFcn', createCallbackFcn(app, @ApplyDirectFactorButtonPushed, true));
                app.ApplyDirectFactorButton.Layout.Row=1; app.ApplyDirectFactorButton.Layout.Column=3; 
            app.CancelCalibrationButton = uibutton(gl_calib, 'push', 'Text', 'Cancel Ref. Wt. Cal', 'ButtonPushedFcn', createCallbackFcn(app, @CancelCalibrationButtonPushed, true), 'BackgroundColor', [0.92 0.8 0.8], 'Visible', 'off');

            app.OperationPanel = uipanel(app.MainGridLayout, 'Title', 'Operation', 'Scrollable', 'on');
            app.OperationPanel.Layout.Row = 1;
            app.OperationPanel.Layout.Column = 2;
            gl_op = uigridlayout(app.OperationPanel); gl_op.RowHeight = {'fit','fit','fit','fit'};
            app.TareButton = uibutton(gl_op, 'push', 'Text', 'Tare Scale', 'FontSize', 14, 'FontWeight', 'bold', 'ButtonPushedFcn', createCallbackFcn(app, @TareButtonPushed, true));
            app.TareStatusLabel = uilabel(gl_op, 'Text', 'Tare: Not Tared', 'FontWeight', 'bold');
            app.MeasureWeightButton = uibutton(gl_op, 'push', 'Text', 'Measure Weight', 'FontSize', 14, 'FontWeight', 'bold', 'ButtonPushedFcn', createCallbackFcn(app, @MeasureWeightButtonPushed, true));
            app.InstantVoltageLabel = uilabel(gl_op, 'Text', 'Inst. Voltage: -- V');

            app.OutputDisplayPanel = uipanel(app.MainGridLayout, 'Title', 'Live Output', 'Scrollable', 'on');
            app.OutputDisplayPanel.Layout.Row = 2;
            app.OutputDisplayPanel.Layout.Column = 2;
            gl_out = uigridlayout(app.OutputDisplayPanel); gl_out.RowHeight = {'fit','fit','fit','fit'};
            app.AverageVoltageDisplayLabel = uilabel(gl_out, 'Text', 'Avg. Voltage: -- V', 'FontSize', 14);
            app.WeightDisplayLabel = uilabel(gl_out, 'Text', 'Weight: -- g', 'FontSize', 18, 'FontWeight', 'bold');
            app.JellyBeanCountDisplayLabel = uilabel(gl_out, 'Text', 'Jelly Beans: --', 'FontSize', 18, 'FontWeight', 'bold');

            app.SimulationPanel_App = uipanel(app.MainGridLayout, 'Title', 'DAC Simulation (for Testing)', 'Scrollable', 'on');
            app.SimulationPanel_App.Layout.Row = 3;
            app.SimulationPanel_App.Layout.Column = 2;
            gl_sim = uigridlayout(app.SimulationPanel_App); gl_sim.RowHeight = {'fit','fit','fit','fit'};
            app.EnableSimulationCheckBox = uicheckbox(gl_sim, 'Text', 'Enable Simulation for Calibration Steps', 'ValueChangedFcn', createCallbackFcn(app, @EnableSimulationCheckBoxValueChanged, true));
            app.SimulatedWeightEditFieldLabel_App = uilabel(gl_sim, 'Text', 'Simulated Wt (g):');
            app.SimulatedWeightEditField_App = uieditfield(gl_sim, 'numeric', 'Value', 0, 'Limits', [0 app.maxSimulatedWeightGrams_App], 'Enable', 'off');
            app.SetSimulatedLoadButton_App = uibutton(gl_sim, 'push', 'Text', 'Set Simulated Load (DAC)', 'ButtonPushedFcn', createCallbackFcn(app, @SetSimulatedLoadButton_AppPushed, true), 'Enable', 'off');
            app.SimulatedVoltageLabel_App = uilabel(gl_sim, 'Text', 'DAC W1: ---V');

            % --- Graphs (Column 3) ---
            app.StdDevOverTimePlotAxes = uiaxes(app.MainGridLayout); 
            app.StdDevOverTimePlotAxes.Layout.Row = [1 2]; 
            app.StdDevOverTimePlotAxes.Layout.Column = 3;
            title(app.StdDevOverTimePlotAxes, 'Voltage Std. Dev. (within current run)'); % Updated Title
            xlabel(app.StdDevOverTimePlotAxes, 'Time within Run (s)'); % Updated XLabel
            ylabel(app.StdDevOverTimePlotAxes, 'Std. Dev. of Voltage (V)');
            grid(app.StdDevOverTimePlotAxes, 'on');

            app.CalibrationCurveAxes = uiaxes(app.MainGridLayout);
            app.CalibrationCurveAxes.Layout.Row = [3 4]; 
            app.CalibrationCurveAxes.Layout.Column = 3;
            title(app.CalibrationCurveAxes, 'Calibration Curve (Voltage vs. Weight)');
            xlabel(app.CalibrationCurveAxes, 'Voltage (V)');
            ylabel(app.CalibrationCurveAxes, 'Weight (g)');
            grid(app.CalibrationCurveAxes, 'on');
            
            app.StatusTextLabel = uilabel(app.MainGridLayout, 'Text', 'System Log:');
            app.StatusTextLabel.Layout.Row = 4; 
            app.StatusTextLabel.Layout.Column = 1;

            app.StatusText = uitextarea(app.MainGridLayout, 'Editable', 'off');
            app.StatusText.Layout.Row = 5; 
            app.StatusText.Layout.Column = [1 2]; 

            app.UIFigure.Visible = 'on';
            disp('createComponents finished. UIFigure should be visible.');
        end
    end

    methods (Access = public)
        function app = JellyBeanScaleGUI_App()
            createComponents(app)
            registerApp(app, app.UIFigure)
            runStartupFcn(app, @startupFcn)
            if nargout == 0
                clear app
            end
        end
        function delete(app)
            cleanupM2K(app);
            if isvalid(app) && isprop(app, 'UIFigure') && isvalid(app.UIFigure)
                 delete(app.UIFigure)
            end
        end
    end
end

function val = escritura(condition, trueVal, falseVal)
    if condition
        val = trueVal;
    else
        val = falseVal;
    end
end