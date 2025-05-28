classdef JellyBeanScaleGUI_App < matlab.apps.AppBase

    % Properties that correspond to app components
    properties (Access = public)
        UIFigure                        matlab.ui.Figure
        MainGridLayout                  matlab.ui.container.GridLayout

        % M2K Connection Panel
        M2KPanel                        matlab.ui.container.Panel
        ConnectM2KButton_Scale          matlab.ui.control.Button
        M2KStatusLabel_Scale            matlab.ui.control.Label
        DisconnectM2KButton_Scale       matlab.ui.control.Button

        % Simulation Panel (For Check-off #2)
        SimulationPanel                 matlab.ui.container.Panel
        SimulatedWeightEditFieldLabel   matlab.ui.control.Label
        SimulatedWeightEditField        matlab.ui.control.NumericEditField
        SetSimulatedLoadButton          matlab.ui.control.Button
        SimulatedVoltageLabel           matlab.ui.control.Label % To show what DAC is set to

        % Calibration Panel
        CalibrationPanel                matlab.ui.container.Panel
        RecordZeroPointButton           matlab.ui.control.Button
        CalibrationMassEditFieldLabel   matlab.ui.control.Label
        CalibrationMassEditField        matlab.ui.control.NumericEditField
        RecordCalWeightButton           matlab.ui.control.Button
        CalibrationStatusLabel          matlab.ui.control.Label

        % Measurement Panel
        MeasurementPanel                matlab.ui.container.Panel
        TareButton                      matlab.ui.control.Button
        TareStatusLabel                 matlab.ui.control.Label
        StartStopMeasurementButton      matlab.ui.control.StateButton % Toggle button
        MeasurementStatusLabel          matlab.ui.control.Label

        % Display Panel
        DisplayPanel                    matlab.ui.container.Panel
        CurrentVoltageDisplayLabel      matlab.ui.control.Label
        RawWeightDisplayLabel           matlab.ui.control.Label
        TaredWeightDisplayLabel         matlab.ui.control.Label
        BeanCountDisplayLabel           matlab.ui.control.Label
        
        % Statistical Display Panel (For Check-off #2)
        StatsPanel                      matlab.ui.container.Panel
        MeanErrorDisplayLabel           matlab.ui.control.Label
        StdDevDisplayLabel              matlab.ui.control.Label
        ConfidenceIntervalDisplayLabel  matlab.ui.control.Label
        
        % Live Plot
        LivePlotUIAxes                  matlab.ui.control.UIAxes
        
        % General Status Text Area
        GeneralStatusTextArea           matlab.ui.control.TextArea
    end

    % Properties that correspond to app data
    properties (Access = private)
        % M2K Objects
        m2kDevice_scale             % Handle for the M2K device context
        analogInput_scale           % Handle for analog input object
        analogOutput_scale          % Handle for analog output (DAC for simulation)
        powerSupply_scale           % Handle for power supply (if needed for M2K Vcc)

        isM2KConnected = false      % Flag for M2K connection

        % Calibration Data
        zeroVoltage                 % Voltage reading for 0 grams
        calWeightVoltage            % Voltage reading for known calibration mass
        knownCalMassGrams           % Known calibration mass in grams
        calibrationSlope            % (calWeightVoltage - zeroVoltage) / knownCalMassGrams
        isCalibrated = false

        % Tare Data
        tareOffsetGrams = 0         % Weight to subtract after taring
        isTared = false

        % Measurement Data & Timer
        measurementTimer            % Timer for real-time updates
        currentVoltage              % Last read voltage
        currentRawWeightGrams       % Last calculated raw weight
        currentTaredWeightGrams     % Last calculated tared weight
        currentBeanCount
        
        plotDataBuffer              % For live plot
        maxPlotPoints = 100         % Number of points to show on live plot

        % Constants
        AVERAGE_BEAN_WEIGHT_GRAMS = 1.10 % From project document

        % Simulation parameters
        maxSimulatedWeightGrams = 2000 % Corresponds to max scale capacity
        maxDacVoltage = 2.5            % Max voltage for DAC simulation (e.g. 0-2.5V for 0-2kg)
                                       % This is an assumption, actual INA output range will differ
        minDacVoltage = 0.0

        % For statistical display (Check-off #2)
        measurementBufferForStats   % Buffer to store recent measurements for stats
        maxStatsBufferSize = 50     % Number of measurements for stats calculation
    end

    methods (Access = private)

        % Code that executes after component creation
        function startupFcn(app)
            app.UIFigure.Name = "Jelly Bean Counting Scale GUI";
            app.GeneralStatusTextArea.Value = {'App Started. Please connect to M2K for simulation or operation.'};
            app.plotDataBuffer = [];
            app.measurementBufferForStats = [];
            updateComponentStates(app);
        end
        
        % --- M2K AND SIMULATION CALLBACKS ---
        function ConnectM2KButton_ScalePushed(app, event)
            app.GeneralStatusTextArea.Value = {'Connecting to M2K...'};
            drawnow;
            try
                app.m2kDevice_scale = clib.libm2k.libm2k.context.m2kOpen();
                pause(1);
                if clibIsNull(app.m2kDevice_scale)
                    error('M2K connection failed. Device not found or libm2k error.');
                end
                app.analogInput_scale = app.m2kDevice_scale.getAnalogIn();
                app.analogOutput_scale = app.m2kDevice_scale.getAnalogOut(); % For DAC simulation
                app.powerSupply_scale = app.m2kDevice_scale.getPowerSupply(); % If M2K needs its own Vcc setup

                % Basic M2K setup (minimal for now, expand as needed)
                app.m2kDevice_scale.calibrateADC();
                app.m2kDevice_scale.calibrateDAC();
                
                % Enable Analog Input Channel 0 (1+/-)
                app.analogInput_scale.enableChannel(0, true);
                app.analogInput_scale.setSampleRate(100000); % Default sample rate
                app.analogInput_scale.setKernelBuffersCount(1);

                % Enable Analog Output Channel 0 (W1)
                app.analogOutput_scale.enableChannel(0, true);
                % Set DAC to a default (e.g., 0V for 0g simulation)
                app.analogOutput_scale.setVoltage(0, app.minDacVoltage); 
                app.SimulatedVoltageLabel.Text = ['DAC W1 Output: ',num2str(app.minDacVoltage, '%.3f'),' V (Simulating 0g)'];


                app.isM2KConnected = true;
                app.M2KStatusLabel_Scale.Text = 'M2K Status: Connected';
                app.GeneralStatusTextArea.Value = {'M2K Connected. Ready for simulation or operation.'};
            catch ME
                app.isM2KConnected = false;
                app.M2KStatusLabel_Scale.Text = 'M2K Status: Disconnected';
                app.GeneralStatusTextArea.Value = {['M2K Connection Error: ', ME.message]};
                cleanupM2K_scale(app); % Ensure partial connections are closed
            end
            updateComponentStates(app);
        end

        function DisconnectM2KButton_ScalePushed(app, event)
            app.GeneralStatusTextArea.Value = {'User initiated M2K Disconnect.'};
            cleanupM2K_scale(app);
            updateComponentStates(app);
        end

        function SetSimulatedLoadButtonPushed(app, event)
            if ~app.isM2KConnected
                app.GeneralStatusTextArea.Value = {'Error: M2K not connected. Cannot set simulated load.'};
                return;
            end
            simWeight = app.SimulatedWeightEditField.Value;
            if simWeight < 0
                simWeight = 0;
                app.SimulatedWeightEditField.Value = 0;
            elseif simWeight > app.maxSimulatedWeightGrams
                simWeight = app.maxSimulatedWeightGrams;
                app.SimulatedWeightEditField.Value = app.maxSimulatedWeightGrams;
            end

            % Simple linear mapping for DAC voltage based on simulated weight
            dacVoltage = app.minDacVoltage + (simWeight / app.maxSimulatedWeightGrams) * (app.maxDacVoltage - app.minDacVoltage);
            
            try
                if ~isempty(app.analogOutput_scale) && isobject(app.analogOutput_scale) && isvalid(app.analogOutput_scale)
                    app.analogOutput_scale.setVoltage(0, dacVoltage); % Set DAC W1
                    app.SimulatedVoltageLabel.Text = ['DAC W1 Output: ',num2str(dacVoltage, '%.3f'),' V (Simulating ', num2str(simWeight), 'g)'];
                    app.GeneralStatusTextArea.Value = {['Simulated load set. DAC outputting ', num2str(dacVoltage, '%.3f'), 'V.']};
                else
                    app.GeneralStatusTextArea.Value = {'Error: Analog output object not valid for setting DAC.'};
                end
            catch ME
                app.GeneralStatusTextArea.Value = {['Error setting DAC voltage: ', ME.message]};
            end
        end
        
        % --- CALIBRATION CALLBACKS ---
        function RecordZeroPointButtonPushed(app, event)
            if ~app.isM2KConnected
                app.GeneralStatusTextArea.Value = {'Error: M2K not connected.'}; return;
            end
            app.GeneralStatusTextArea.Value = {'Recording zero point voltage...'};
            drawnow;
            
            if ~isempty(app.SimulatedWeightEditField) 
                 app.SimulatedWeightEditField.Value = 0;
                 SetSimulatedLoadButtonPushed(app, []); 
                 pause(0.1); 
            end

            voltages = readAverageVoltage(app, 10); 
            if ~isnan(voltages)
                app.zeroVoltage = mean(voltages);
                app.GeneralStatusTextArea.Value = {['Zero point recorded. Voltage: ', num2str(app.zeroVoltage, '%.4f'), ' V']};
                app.isCalibrated = false; 
                app.CalibrationStatusLabel.Text = 'Status: Zero Point Recorded';
            else
                app.GeneralStatusTextArea.Value = {'Error reading zero point voltage.'};
            end
            updateComponentStates(app);
        end

        function RecordCalWeightButtonPushed(app, event)
            if ~app.isM2KConnected
                app.GeneralStatusTextArea.Value = {'Error: M2K not connected.'}; return;
            end
            if isempty(app.zeroVoltage)
                app.GeneralStatusTextArea.Value = {'Error: Please record zero point first.'}; return;
            end
            
            app.knownCalMassGrams = app.CalibrationMassEditField.Value;
            if app.knownCalMassGrams <= 0
                app.GeneralStatusTextArea.Value = {'Error: Calibration mass must be positive.'}; return;
            end

            app.GeneralStatusTextArea.Value = {['Recording voltage for ', num2str(app.knownCalMassGrams), 'g...']};
            drawnow;

             if ~isempty(app.SimulatedWeightEditField) 
                 app.SimulatedWeightEditField.Value = app.knownCalMassGrams;
                 SetSimulatedLoadButtonPushed(app, []); 
                 pause(0.1); 
             end

            voltages = readAverageVoltage(app, 10);
            if ~isnan(voltages)
                app.calWeightVoltage = mean(voltages);
                
                if abs(app.calWeightVoltage - app.zeroVoltage) < 1e-6 
                    app.GeneralStatusTextArea.Value = {'Error: Voltage difference for calibration is too small. Check setup or calibration mass.'};
                    app.isCalibrated = false;
                else
                    app.calibrationSlope = (app.calWeightVoltage - app.zeroVoltage) / app.knownCalMassGrams; % Units: Volts/gram
                    
                    if app.calibrationSlope == 0
                         app.GeneralStatusTextArea.Value = {'Error: Calibration slope is zero. Check readings.'};
                         app.isCalibrated = false;
                    else
                        app.isCalibrated = true;
                        app.CalibrationStatusLabel.Text = ['Status: Calibrated (Slope: ', num2str(app.calibrationSlope, '%.2e'), ' V/g)'];
                        app.GeneralStatusTextArea.Value = {['Calibration complete. Voltage: ', num2str(app.calWeightVoltage, '%.4f'), ' V for ', num2str(app.knownCalMassGrams), 'g.']};
                    end
                end
            else
                app.GeneralStatusTextArea.Value = {'Error reading calibration weight voltage.'};
                app.isCalibrated = false;
            end
            updateComponentStates(app);
        end

        % --- MEASUREMENT CALLBACKS ---
        function TareButtonPushed(app, event)
            if ~app.isCalibrated
                app.GeneralStatusTextArea.Value = {'Error: Scale not calibrated. Cannot tare.'}; return;
            end
            if isempty(app.currentRawWeightGrams) 
                tempVoltage = readAverageVoltage(app, 5);
                if ~isnan(tempVoltage) && ~isempty(app.calibrationSlope) && app.calibrationSlope ~= 0
                    tempRawWeight = (mean(tempVoltage) - app.zeroVoltage) / app.calibrationSlope;
                    app.tareOffsetGrams = tempRawWeight;
                else
                    app.GeneralStatusTextArea.Value = {'Error: Could not read current weight for taring.'}; return;
                end
            else
                app.tareOffsetGrams = app.currentRawWeightGrams;
            end
            app.isTared = true;
            app.TareStatusLabel.Text = ['Status: Tared (Offset: ', num2str(app.tareOffsetGrams, '%.2f'), 'g)'];
            app.GeneralStatusTextArea.Value = {['Scale tared. Offset: ', num2str(app.tareOffsetGrams, '%.2f'), 'g']};
            
            if ~isempty(app.currentVoltage)
                updateMeasurementDisplays(app, app.currentVoltage);
            end
        end

        function StartStopMeasurementButtonValueChanged(app, event)
            if app.StartStopMeasurementButton.Value 
                if ~app.isM2KConnected
                    app.GeneralStatusTextArea.Value = {'Error: M2K not connected.'};
                    app.StartStopMeasurementButton.Value = false; 
                    return;
                end
                if ~app.isCalibrated
                    app.GeneralStatusTextArea.Value = {'Error: Scale not calibrated.'};
                    app.StartStopMeasurementButton.Value = false; 
                    return;
                end
                
                app.StartStopMeasurementButton.Text = 'Stop Measurement';
                app.MeasurementStatusLabel.Text = 'Status: Measuring...';
                app.GeneralStatusTextArea.Value = {'Real-time measurement started.'};
                
                app.plotDataBuffer = []; 
                app.measurementBufferForStats = []; 

                if isempty(app.measurementTimer) || ~isvalid(app.measurementTimer)
                    app.measurementTimer = timer(...
                        'ExecutionMode', 'fixedRate', ...
                        'Period', 0.2, ... 
                        'TimerFcn', @(~,~) app.measurementTimerTick());
                end
                start(app.measurementTimer);
                
            else 
                if ~isempty(app.measurementTimer) && isvalid(app.measurementTimer)
                    stop(app.measurementTimer);
                end
                app.StartStopMeasurementButton.Text = 'Start Measurement';
                app.MeasurementStatusLabel.Text = 'Status: Stopped';
                app.GeneralStatusTextArea.Value = {'Real-time measurement stopped.'};
            end
            updateComponentStates(app);
        end
        
        function measurementTimerTick(app)
            if ~app.isM2KConnected || ~app.isCalibrated
                if app.StartStopMeasurementButton.Value
                    app.StartStopMeasurementButton.Value = false; 
                else 
                     if ~isempty(app.measurementTimer) && isvalid(app.measurementTimer)
                        stop(app.measurementTimer);
                     end
                end
                app.GeneralStatusTextArea.Value = {'Measurement stopped due to M2K disconnect or loss of calibration.'};
                return;
            end

            voltages = readAverageVoltage(app, 3); 
            if ~isnan(voltages)
                app.currentVoltage = mean(voltages);
                updateMeasurementDisplays(app, app.currentVoltage);
                updateLivePlot(app, app.currentTaredWeightGrams);
                updateStatsDisplays(app, app.currentTaredWeightGrams); 
            else
                app.CurrentVoltageDisplayLabel.Text = 'Voltage: Error';
            end
        end

        % --- HELPER FUNCTIONS ---
        function voltages = readAverageVoltage(app, numSamples)
            if ~app.isM2KConnected || isempty(app.analogInput_scale) || ~isobject(app.analogInput_scale) || ~isvalid(app.analogInput_scale)
                voltages = NaN; return;
            end
            samplesBuffer = zeros(1, numSamples);
            try
                for k = 1:numSamples
                    rawSamples = app.analogInput_scale.getSamplesInterleaved_matlab(10*2); 
                    samplesBuffer(k) = mean(double(rawSamples(1:2:end))); 
                    pause(0.005); 
                end
                voltages = samplesBuffer;
            catch ME
                app.GeneralStatusTextArea.Value = {['Error reading voltage from M2K: ', ME.message]};
                voltages = NaN;
            end
        end

        function updateMeasurementDisplays(app, voltage)
            app.CurrentVoltageDisplayLabel.Text = ['Voltage: ', num2str(voltage, '%.4f'), ' V'];
            
            if app.isCalibrated && ~isempty(app.calibrationSlope) && app.calibrationSlope ~= 0
                app.currentRawWeightGrams = (voltage - app.zeroVoltage) / app.calibrationSlope;
                app.RawWeightDisplayLabel.Text = ['Raw Wt: ', num2str(app.currentRawWeightGrams, '%.2f'), ' g'];
                
                app.currentTaredWeightGrams = app.currentRawWeightGrams - app.tareOffsetGrams;
                app.TaredWeightDisplayLabel.Text = ['Net Wt: ', num2str(app.currentTaredWeightGrams, '%.2f'), ' g'];
                
                if app.currentTaredWeightGrams > 0
                    app.currentBeanCount = round(app.currentTaredWeightGrams / app.AVERAGE_BEAN_WEIGHT_GRAMS);
                else
                    app.currentBeanCount = 0;
                end
                app.BeanCountDisplayLabel.Text = ['Bean Count: ~', num2str(app.currentBeanCount)];
            else
                app.RawWeightDisplayLabel.Text = 'Raw Wt: --- g (Not Calibrated)';
                app.TaredWeightDisplayLabel.Text = 'Net Wt: --- g';
                app.BeanCountDisplayLabel.Text = 'Bean Count: ---';
            end
        end
        
        function updateLivePlot(app, newWeightValue)
            app.plotDataBuffer = [app.plotDataBuffer, newWeightValue];
            if length(app.plotDataBuffer) > app.maxPlotPoints
                app.plotDataBuffer = app.plotDataBuffer(end-app.maxPlotPoints+1:end);
            end
            plot(app.LivePlotUIAxes, app.plotDataBuffer, '-b');
            xlabel(app.LivePlotUIAxes, 'Time (samples)');
            ylabel(app.LivePlotUIAxes, 'Net Weight (g)');
            title(app.LivePlotUIAxes, 'Live Weight Reading');
            grid(app.LivePlotUIAxes, 'on');
            if ~isempty(app.plotDataBuffer)
                 ylim(app.LivePlotUIAxes, 'auto'); 
            end
        end

        function updateStatsDisplays(app, newWeightValue)
            app.measurementBufferForStats = [app.measurementBufferForStats, newWeightValue];
            if length(app.measurementBufferForStats) > app.maxStatsBufferSize
                app.measurementBufferForStats = app.measurementBufferForStats(end-app.maxStatsBufferSize+1:end);
            end

            if length(app.measurementBufferForStats) >= 2 
                currentMean = mean(app.measurementBufferForStats);
                currentStdDev = std(app.measurementBufferForStats);
                app.StdDevDisplayLabel.Text = ['Meas. Std Dev: ', num2str(currentStdDev, '%.3f'), ' g'];

                trueSimulatedWeight = app.SimulatedWeightEditField.Value; 
                meanError = currentMean - trueSimulatedWeight;
                app.MeanErrorDisplayLabel.Text = ['Mean Error (vs Sim): ', num2str(meanError, '%.3f'), ' g'];
                
                N = length(app.measurementBufferForStats);
                SEM = currentStdDev / sqrt(N); 
                if N > 1 % t-critical requires N-1 > 0
                    t_critical = tinv(0.975, N-1); 
                    CI_lower = currentMean - t_critical * SEM;
                    CI_upper = currentMean + t_critical * SEM;
                    app.ConfidenceIntervalDisplayLabel.Text = ['95% CI: [', num2str(CI_lower,'%.2f'), ', ', num2str(CI_upper,'%.2f'), '] g'];
                else
                    app.ConfidenceIntervalDisplayLabel.Text = '95% CI: [---, ---] g (N too small)';
                end
            else
                app.StdDevDisplayLabel.Text = 'Meas. Std Dev: --- g';
                app.MeanErrorDisplayLabel.Text = 'Mean Error (vs Sim): --- g';
                app.ConfidenceIntervalDisplayLabel.Text = '95% CI: [---, ---] g';
            end
        end

        function updateComponentStates(app)
            if app.isM2KConnected
                app.ConnectM2KButton_Scale.Enable = 'off';
                app.DisconnectM2KButton_Scale.Enable = 'on';
                app.SetSimulatedLoadButton.Enable = 'on'; 
                app.RecordZeroPointButton.Enable = 'on';
            else
                app.ConnectM2KButton_Scale.Enable = 'on';
                app.DisconnectM2KButton_Scale.Enable = 'off';
                app.SetSimulatedLoadButton.Enable = 'off';
                app.RecordZeroPointButton.Enable = 'off';
                app.RecordCalWeightButton.Enable = 'off';
                app.TareButton.Enable = 'off';
                app.StartStopMeasurementButton.Enable = 'off';
                 if app.StartStopMeasurementButton.Value 
                    app.StartStopMeasurementButton.Value = false;
                    app.StartStopMeasurementButton.Text = 'Start Measurement';
                    app.MeasurementStatusLabel.Text = 'Status: Stopped';
                 end
            end

            if app.isM2KConnected && ~isempty(app.zeroVoltage)
                app.RecordCalWeightButton.Enable = 'on';
            else
                app.RecordCalWeightButton.Enable = 'off';
            end

            if app.isCalibrated
                app.TareButton.Enable = 'on';
                app.StartStopMeasurementButton.Enable = 'on';
            else
                app.TareButton.Enable = 'off';
                app.StartStopMeasurementButton.Enable = 'off';
                 if app.StartStopMeasurementButton.Value 
                    app.StartStopMeasurementButton.Value = false;
                    app.StartStopMeasurementButton.Text = 'Start Measurement';
                    app.MeasurementStatusLabel.Text = 'Status: Stopped';
                 end
            end
            
            if app.StartStopMeasurementButton.Value
                app.RecordZeroPointButton.Enable = 'off';
                app.RecordCalWeightButton.Enable = 'off';
                app.TareButton.Enable = 'off';
                app.SetSimulatedLoadButton.Enable = 'off'; 
            elseif app.isM2KConnected 
                app.SetSimulatedLoadButton.Enable = 'on';
                 app.RecordZeroPointButton.Enable = 'on'; % Re-enable if not measuring
                if ~isempty(app.zeroVoltage)
                     app.RecordCalWeightButton.Enable = 'on'; % Re-enable if not measuring
                end
                if app.isCalibrated
                    app.TareButton.Enable = 'on';
                end
            end
        end
        
        function cleanupM2K_scale(app)
            % Stop and delete timer
            if ~isempty(app.measurementTimer) && isvalid(app.measurementTimer)
                if strcmp(app.measurementTimer.Running, 'on')
                    stop(app.measurementTimer);
                end
                delete(app.measurementTimer);
                app.measurementTimer = [];
            end

            currentStatus = app.GeneralStatusTextArea.Value;
            if ~iscell(currentStatus) % Ensure it's a cell for appending
                currentStatus = {currentStatus};
            end
            currentStatus{end+1} = 'Attempting M2K cleanup...';
            app.GeneralStatusTextArea.Value = currentStatus;
            drawnow;

            % Only proceed with hardware interaction if m2kDevice was potentially valid
            if ~isempty(app.m2kDevice_scale) && ~clibIsNull(app.m2kDevice_scale)
                % Try to disable analog output channel
                try
                    if ~isempty(app.analogOutput_scale) && isobject(app.analogOutput_scale) && isvalid(app.analogOutput_scale)
                        app.analogOutput_scale.setVoltage(0, 0); % Reset DAC to 0V
                        app.analogOutput_scale.enableChannel(0, false);
                        currentStatus{end+1} = 'Analog output channel disabled.';
                        app.GeneralStatusTextArea.Value = currentStatus;
                    end
                catch ME_ao
                    disp(['Warning: Error disabling analog output: ', ME_ao.message]);
                    currentStatus{end+1} = ['Warning: Error disabling analog output: ', ME_ao.message];
                    app.GeneralStatusTextArea.Value = currentStatus;
                end

                % Try to disable analog input channel
                try
                    if ~isempty(app.analogInput_scale) && isobject(app.analogInput_scale) && isvalid(app.analogInput_scale)
                        app.analogInput_scale.enableChannel(0, false);
                         currentStatus{end+1} = 'Analog input channel disabled.';
                         app.GeneralStatusTextArea.Value = currentStatus;
                    end
                catch ME_ai
                    disp(['Warning: Error disabling analog input: ', ME_ai.message]);
                    currentStatus{end+1} = ['Warning: Error disabling analog input: ', ME_ai.message];
                    app.GeneralStatusTextArea.Value = currentStatus;
                end
                
                % Try to close the M2K context(s)
                try
                    clib.libm2k.libm2k.context.contextCloseAll(); % Closes all open M2K contexts
                    currentStatus{end+1} = 'M2K contextCloseAll called.';
                    app.GeneralStatusTextArea.Value = currentStatus;
                catch ME_context
                    disp(['Warning: Error calling contextCloseAll: ', ME_context.message]);
                    currentStatus{end+1} = ['Warning: Error calling contextCloseAll: ', ME_context.message];
                    app.GeneralStatusTextArea.Value = currentStatus;
                end
            else
                 currentStatus{end+1} = 'M2K device was not valid or already null before hardware cleanup.';
                 app.GeneralStatusTextArea.Value = currentStatus;
            end

            % Nullify all M2K related app properties
            app.m2kDevice_scale = [];
            app.analogInput_scale = [];
            app.analogOutput_scale = [];
            app.powerSupply_scale = []; % Added this
            app.isM2KConnected = false;

            % Update UI elements
            if isvalid(app.UIFigure) % Check if UI is still valid
                app.M2KStatusLabel_Scale.Text = 'M2K Status: Disconnected';
                app.SimulatedVoltageLabel.Text = 'DAC W1 Output: --- V';
                currentStatus{end+1} = 'M2K cleanup complete. App properties reset.';
                app.GeneralStatusTextArea.Value = currentStatus;


                % Reset calibration and tare states
                app.isCalibrated = false; app.CalibrationStatusLabel.Text = 'Status: Not Calibrated';
                app.isTared = false; app.tareOffsetGrams = 0; app.TareStatusLabel.Text = 'Status: Not Tared';
                app.zeroVoltage = []; app.calWeightVoltage = [];
            end
        end


        function UIFigureCloseRequest(app, event)
            currentStatus = app.GeneralStatusTextArea.Value;
            if ~iscell(currentStatus) currentStatus = {currentStatus}; end
            currentStatus{end+1} = 'Closing app and disconnecting M2K...';
            app.GeneralStatusTextArea.Value = currentStatus;
            drawnow;
            cleanupM2K_scale(app);
            delete(app); % Closes the app
        end
    end

    % App creation and deletion
    methods (Access = public)
        % Construct app
        function app = JellyBeanScaleGUI_App()
            createComponents(app)
            registerApp(app, app.UIFigure)
            runStartupFcn(app, @startupFcn)
            if nargout == 0
                clear app
            end
        end

        % Code that executes before app deletion
        function delete(app)
            cleanupM2K_scale(app); % Ensure cleanup on deletion
            delete(app.UIFigure)
        end
    end

    % App component setup
    methods (Access = private)
        function createComponents(app)
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [50 50 1000 750]; 
            app.UIFigure.Name = 'Jelly Bean Counting Scale';
            app.UIFigure.CloseRequestFcn = createCallbackFcn(app, @UIFigureCloseRequest, true);

            app.MainGridLayout = uigridlayout(app.UIFigure);
            app.MainGridLayout.ColumnWidth = {'1x', '1x', '1.5x'}; % Adjusted plot width
            app.MainGridLayout.RowHeight = {120, 160, 150, '1x', 80}; 

            % --- M2K Panel ---
            app.M2KPanel = uipanel(app.MainGridLayout);
            app.M2KPanel.Layout.Row = 1;
            app.M2KPanel.Layout.Column = 1;
            app.M2KPanel.Title = 'M2K Connection';
            
            uilabel(app.M2KPanel, 'Text', 'M2K Status:', 'Position', [10 70 80 22]);
            app.M2KStatusLabel_Scale = uilabel(app.M2KPanel, 'Text', 'Disconnected', 'Position', [100 70 180 22], 'FontWeight', 'bold'); % Increased width
            app.ConnectM2KButton_Scale = uibutton(app.M2KPanel, 'push', 'Text', 'Connect M2K', 'Position', [10 30 120 23], 'ButtonPushedFcn', createCallbackFcn(app, @ConnectM2KButton_ScalePushed, true));
            app.DisconnectM2KButton_Scale = uibutton(app.M2KPanel, 'push', 'Text', 'Disconnect M2K', 'Position', [140 30 120 23], 'ButtonPushedFcn', createCallbackFcn(app, @DisconnectM2KButton_ScalePushed, true));

            % --- Simulation Panel ---
            app.SimulationPanel = uipanel(app.MainGridLayout);
            app.SimulationPanel.Layout.Row = 2;
            app.SimulationPanel.Layout.Column = 1;
            app.SimulationPanel.Title = 'Simulation Control (Check-off #2)';
            
            app.SimulatedWeightEditFieldLabel = uilabel(app.SimulationPanel, 'Text', 'Simulated Wt (g):', 'Position', [10 110 120 22]); % Adjusted Y
            app.SimulatedWeightEditField = uieditfield(app.SimulationPanel, 'numeric', 'Position', [140 110 100 22], 'Value', 0, 'Limits', [0 app.maxSimulatedWeightGrams]); % Adjusted Y
            app.SetSimulatedLoadButton = uibutton(app.SimulationPanel, 'push', 'Text', 'Set Simulated Load', 'Position', [10 70 150 23], 'ButtonPushedFcn', createCallbackFcn(app, @SetSimulatedLoadButtonPushed, true)); % Adjusted Y
            app.SimulatedVoltageLabel = uilabel(app.SimulationPanel, 'Text', 'DAC W1 Output: --- V', 'Position', [10 30 250 22]); % Adjusted Y

            % --- Calibration Panel ---
            app.CalibrationPanel = uipanel(app.MainGridLayout);
            app.CalibrationPanel.Layout.Row = 3;
            app.CalibrationPanel.Layout.Column = 1;
            app.CalibrationPanel.Title = 'Scale Calibration';

            app.RecordZeroPointButton = uibutton(app.CalibrationPanel, 'push', 'Text', 'Record Zero Point (0g)', 'Position', [10 90 160 23], 'ButtonPushedFcn', createCallbackFcn(app, @RecordZeroPointButtonPushed, true));
            app.CalibrationMassEditFieldLabel = uilabel(app.CalibrationPanel, 'Text', 'Cal. Mass (g):', 'Position', [10 50 90 22]);
            app.CalibrationMassEditField = uieditfield(app.CalibrationPanel, 'numeric', 'Position', [110 50 80 22], 'Value', 100, 'Limits', [0.1, app.maxSimulatedWeightGrams]);
            app.RecordCalWeightButton = uibutton(app.CalibrationPanel, 'push', 'Text', 'Record Cal. Weight', 'Position', [200 50 140 23], 'ButtonPushedFcn', createCallbackFcn(app, @RecordCalWeightButtonPushed, true));
            uilabel(app.CalibrationPanel, 'Text', 'Status:', 'Position', [10 10 50 22]);
            app.CalibrationStatusLabel = uilabel(app.CalibrationPanel, 'Text', 'Not Calibrated', 'Position', [70 10 250 22], 'FontWeight', 'bold');

            % --- Measurement Panel (Column 2, Row 1) ---
            app.MeasurementPanel = uipanel(app.MainGridLayout);
            app.MeasurementPanel.Layout.Row = 1;
            app.MeasurementPanel.Layout.Column = 2;
            app.MeasurementPanel.Title = 'Measurement';

            app.TareButton = uibutton(app.MeasurementPanel, 'push', 'Text', 'Tare Scale', 'Position', [10 70 100 23], 'ButtonPushedFcn', createCallbackFcn(app, @TareButtonPushed, true));
            uilabel(app.MeasurementPanel, 'Text', 'Tare:', 'Position', [120 70 40 22]);
            app.TareStatusLabel = uilabel(app.MeasurementPanel, 'Text', 'Not Tared', 'Position', [170 70 150 22], 'FontWeight', 'bold');
            app.StartStopMeasurementButton = uibutton(app.MeasurementPanel, 'state', 'Text', 'Start Measurement', 'Position', [10 30 150 23], 'ValueChangedFcn', createCallbackFcn(app, @StartStopMeasurementButtonValueChanged, true));
            uilabel(app.MeasurementPanel, 'Text', 'Status:', 'Position', [170 30 50 22]);
            app.MeasurementStatusLabel = uilabel(app.MeasurementPanel, 'Text', 'Stopped', 'Position', [230 30 100 22], 'FontWeight', 'bold');
            
            % --- Display Panel (Column 2, Row 2) ---
            app.DisplayPanel = uipanel(app.MainGridLayout);
            app.DisplayPanel.Layout.Row = 2;
            app.DisplayPanel.Layout.Column = 2;
            app.DisplayPanel.Title = 'Live Readings';
            
            app.CurrentVoltageDisplayLabel = uilabel(app.DisplayPanel, 'Text', 'Voltage: --- V', 'Position', [10 110 250 22], 'FontSize', 12); % Adjusted Y
            app.RawWeightDisplayLabel = uilabel(app.DisplayPanel, 'Text', 'Raw Wt: --- g', 'Position', [10 80 250 22], 'FontSize', 12); % Adjusted Y
            app.TaredWeightDisplayLabel = uilabel(app.DisplayPanel, 'Text', 'Net Wt: --- g', 'Position', [10 50 280 22], 'FontSize', 14, 'FontWeight', 'bold');
            app.BeanCountDisplayLabel = uilabel(app.DisplayPanel, 'Text', 'Bean Count: ---', 'Position', [10 20 280 22], 'FontSize', 14, 'FontWeight', 'bold');

            % --- Statistical Display Panel (Column 2, Row 3) ---
            app.StatsPanel = uipanel(app.MainGridLayout);
            app.StatsPanel.Layout.Row = 3;
            app.StatsPanel.Layout.Column = 2;
            app.StatsPanel.Title = 'Statistical Info (for Check-off #2)';

            app.MeanErrorDisplayLabel = uilabel(app.StatsPanel, 'Text', 'Mean Error (vs Sim): --- g', 'Position', [10 90 280 22]);
            app.StdDevDisplayLabel = uilabel(app.StatsPanel, 'Text', 'Meas. Std Dev: --- g', 'Position', [10 50 280 22]);
            app.ConfidenceIntervalDisplayLabel = uilabel(app.StatsPanel, 'Text', '95% CI: [---, ---] g', 'Position', [10 10 280 22]);
            
            % --- Live Plot UIAxes (Column 3, Row 1, Span 3 Rows) ---
            app.LivePlotUIAxes = uiaxes(app.MainGridLayout);
            app.LivePlotUIAxes.Layout.Row = [1 3]; 
            app.LivePlotUIAxes.Layout.Column = 3;
            title(app.LivePlotUIAxes, 'Live Weight Reading');
            xlabel(app.LivePlotUIAxes, 'Time (samples)');
            ylabel(app.LivePlotUIAxes, 'Net Weight (g)');
            grid(app.LivePlotUIAxes, 'on');

            % --- General Status TextArea (Row 4, Span all Columns) ---
            app.GeneralStatusTextArea = uitextarea(app.MainGridLayout);
            app.GeneralStatusTextArea.Layout.Row = 4; 
            app.GeneralStatusTextArea.Layout.Column = [1 3]; 
            app.GeneralStatusTextArea.Editable = 'off';
            app.GeneralStatusTextArea.Value = {'App Initialized.'};

            app.UIFigure.Visible = 'on';
        end
    end
end
