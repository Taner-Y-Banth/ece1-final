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
            cleanupM2K_scale(app);
            app.GeneralStatusTextArea.Value = {'M2K Disconnected.'};
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
            % This is a placeholder. The actual V/g relationship from your hardware will be different.
            dacVoltage = app.minDacVoltage + (simWeight / app.maxSimulatedWeightGrams) * (app.maxDacVoltage - app.minDacVoltage);
            
            try
                app.analogOutput_scale.setVoltage(0, dacVoltage); % Set DAC W1
                app.SimulatedVoltageLabel.Text = ['DAC W1 Output: ',num2str(dacVoltage, '%.3f'),' V (Simulating ', num2str(simWeight), 'g)'];
                app.GeneralStatusTextArea.Value = {['Simulated load set. DAC outputting ', num2str(dacVoltage, '%.3f'), 'V.']};
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
            
            % For simulation, ensure simulated weight is 0g
            if ~isempty(app.SimulatedWeightEditField) % Check if simulation panel exists
                 app.SimulatedWeightEditField.Value = 0;
                 SetSimulatedLoadButtonPushed(app, []); % Trigger DAC update
                 pause(0.1); % Allow DAC to settle
            end

            voltages = readAverageVoltage(app, 10); % Read average of 10 samples
            if ~isnan(voltages)
                app.zeroVoltage = mean(voltages);
                app.GeneralStatusTextArea.Value = {['Zero point recorded. Voltage: ', num2str(app.zeroVoltage, '%.4f'), ' V']};
                app.isCalibrated = false; % Reset calibration status until full calibration
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

            % For simulation, set simulated weight to calibration mass
             if ~isempty(app.SimulatedWeightEditField) % Check if simulation panel exists
                 app.SimulatedWeightEditField.Value = app.knownCalMassGrams;
                 SetSimulatedLoadButtonPushed(app, []); % Trigger DAC update
                 pause(0.1); % Allow DAC to settle
             end

            voltages = readAverageVoltage(app, 10);
            if ~isnan(voltages)
                app.calWeightVoltage = mean(voltages);
                
                if abs(app.calWeightVoltage - app.zeroVoltage) < 1e-6 % Avoid division by zero or tiny number
                    app.GeneralStatusTextArea.Value = {'Error: Voltage difference for calibration is too small. Check setup or calibration mass.'};
                    app.isCalibrated = false;
                else
                    % Slope: grams per Volt (if voltage increases with weight)
                    % Or Volt per gram: (app.calWeightVoltage - app.zeroVoltage) / app.knownCalMassGrams
                    % Let's use V/g for slope, then weight = (V - V0)/slope_Vg
                    % Or g/V for slope, then weight = (V - V0) * slope_gV
                    % Let's define slope as (change in voltage / change in mass)
                    % So, voltage = slope_Vg * mass + zeroVoltage
                    % mass = (voltage - zeroVoltage) / slope_Vg
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
            if isempty(app.currentRawWeightGrams) % If no measurement has been taken yet
                % Take a single reading to determine tare offset
                tempVoltage = readAverageVoltage(app, 5);
                if ~isnan(tempVoltage)
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
            
            % Update displays immediately with new tare
            if ~isempty(app.currentVoltage)
                updateMeasurementDisplays(app, app.currentVoltage);
            end
        end

        function StartStopMeasurementButtonValueChanged(app, event)
            if app.StartStopMeasurementButton.Value % If pressed (True)
                if ~app.isM2KConnected
                    app.GeneralStatusTextArea.Value = {'Error: M2K not connected.'};
                    app.StartStopMeasurementButton.Value = false; % Reset button state
                    return;
                end
                if ~app.isCalibrated
                    app.GeneralStatusTextArea.Value = {'Error: Scale not calibrated.'};
                    app.StartStopMeasurementButton.Value = false; % Reset button state
                    return;
                end
                
                app.StartStopMeasurementButton.Text = 'Stop Measurement';
                app.MeasurementStatusLabel.Text = 'Status: Measuring...';
                app.GeneralStatusTextArea.Value = {'Real-time measurement started.'};
                
                % Initialize or clear plot buffer
                app.plotDataBuffer = []; 
                app.measurementBufferForStats = []; % Clear stats buffer

                if isempty(app.measurementTimer) || ~isvalid(app.measurementTimer)
                    app.measurementTimer = timer(...
                        'ExecutionMode', 'fixedRate', ...
                        'Period', 0.2, ... % Update rate (e.g., 5 times per second)
                        'TimerFcn', @(~,~) app.measurementTimerTick());
                end
                start(app.measurementTimer);
                
            else % If released (False)
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
                % Stop timer if conditions are no longer met
                if app.StartStopMeasurementButton.Value
                    app.StartStopMeasurementButton.Value = false; % This will trigger ValueChangedFcn
                else % If already trying to stop, just ensure timer is stopped
                     if ~isempty(app.measurementTimer) && isvalid(app.measurementTimer)
                        stop(app.measurementTimer);
                     end
                end
                app.GeneralStatusTextArea.Value = {'Measurement stopped due to M2K disconnect or loss of calibration.'};
                return;
            end

            voltages = readAverageVoltage(app, 3); % Read average of 3 samples for speed
            if ~isnan(voltages)
                app.currentVoltage = mean(voltages);
                updateMeasurementDisplays(app, app.currentVoltage);
                updateLivePlot(app, app.currentTaredWeightGrams);
                updateStatsDisplays(app, app.currentTaredWeightGrams); % For Check-off #2
            else
                app.CurrentVoltageDisplayLabel.Text = 'Voltage: Error';
                % Consider stopping timer on repeated errors
            end
        end

        % --- HELPER FUNCTIONS ---
        function voltages = readAverageVoltage(app, numSamples)
            if ~app.isM2KConnected || isempty(app.analogInput_scale)
                voltages = NaN; return;
            end
            samplesBuffer = zeros(1, numSamples);
            try
                for k = 1:numSamples
                    % The getSamplesInterleaved_matlab expects total number of points (samples*channels)
                    % For a single differential channel (0), it might still be 2 points (1+ and 1-)
                    % We need 1 actual voltage reading. Let's take a small buffer.
                    rawSamples = app.analogInput_scale.getSamplesInterleaved_matlab(10*2); % Get 10 samples
                    samplesBuffer(k) = mean(double(rawSamples(1:2:end))); % Average the 10 for robustness
                    pause(0.005); % Small pause between samples if needed
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
                 ylim(app.LivePlotUIAxes, 'auto'); % Adjust Y limits dynamically or set fixed
            end
        end

        function updateStatsDisplays(app, newWeightValue)
            % For Software Check-off #2: Calculate and display Mean Error, Std Dev, CI
            % This requires a "true" or "expected" weight if calculating mean error.
            % For simulation, the "true" weight is app.SimulatedWeightEditField.Value

            app.measurementBufferForStats = [app.measurementBufferForStats, newWeightValue];
            if length(app.measurementBufferForStats) > app.maxStatsBufferSize
                app.measurementBufferForStats = app.measurementBufferForStats(end-app.maxStatsBufferSize+1:end);
            end

            if length(app.measurementBufferForStats) >= 2 % Need at least 2 points for std dev
                currentMean = mean(app.measurementBufferForStats);
                currentStdDev = std(app.measurementBufferForStats);
                app.StdDevDisplayLabel.Text = ['Meas. Std Dev: ', num2str(currentStdDev, '%.3f'), ' g'];

                % Mean Error (requires a "true" value)
                trueSimulatedWeight = app.SimulatedWeightEditField.Value; % Get current simulated target
                meanError = currentMean - trueSimulatedWeight;
                app.MeanErrorDisplayLabel.Text = ['Mean Error (vs Sim): ', num2str(meanError, '%.3f'), ' g'];
                
                % Confidence Interval (95% CI for the mean of the buffered measurements)
                N = length(app.measurementBufferForStats);
                SEM = currentStdDev / sqrt(N); % Standard Error of the Mean
                t_critical = tinv(0.975, N-1); % t-score for 95% CI, N-1 degrees of freedom
                CI_lower = currentMean - t_critical * SEM;
                CI_upper = currentMean + t_critical * SEM;
                app.ConfidenceIntervalDisplayLabel.Text = ['95% CI: [', num2str(CI_lower,'%.2f'), ', ', num2str(CI_upper,'%.2f'), '] g'];
            else
                app.StdDevDisplayLabel.Text = 'Meas. Std Dev: --- g';
                app.MeanErrorDisplayLabel.Text = 'Mean Error (vs Sim): --- g';
                app.ConfidenceIntervalDisplayLabel.Text = '95% CI: [---, ---] g';
            end
        end

        function updateComponentStates(app)
            % M2K Connection
            if app.isM2KConnected
                app.ConnectM2KButton_Scale.Enable = 'off';
                app.DisconnectM2KButton_Scale.Enable = 'on';
                app.SetSimulatedLoadButton.Enable = 'on'; % Assuming simulation panel is always active if M2K connected
                app.RecordZeroPointButton.Enable = 'on';
            else
                app.ConnectM2KButton_Scale.Enable = 'on';
                app.DisconnectM2KButton_Scale.Enable = 'off';
                app.SetSimulatedLoadButton.Enable = 'off';
                app.RecordZeroPointButton.Enable = 'off';
                app.RecordCalWeightButton.Enable = 'off';
                app.TareButton.Enable = 'off';
                app.StartStopMeasurementButton.Enable = 'off';
                 if app.StartStopMeasurementButton.Value % If it was on, turn it off
                    app.StartStopMeasurementButton.Value = false;
                    app.StartStopMeasurementButton.Text = 'Start Measurement';
                    app.MeasurementStatusLabel.Text = 'Status: Stopped';
                 end
            end

            % Calibration
            if app.isM2KConnected && ~isempty(app.zeroVoltage)
                app.RecordCalWeightButton.Enable = 'on';
            else
                app.RecordCalWeightButton.Enable = 'off';
            end

            % Measurement
            if app.isCalibrated
                app.TareButton.Enable = 'on';
                app.StartStopMeasurementButton.Enable = 'on';
            else
                app.TareButton.Enable = 'off';
                app.StartStopMeasurementButton.Enable = 'off';
                 if app.StartStopMeasurementButton.Value % If it was on, turn it off
                    app.StartStopMeasurementButton.Value = false;
                    app.StartStopMeasurementButton.Text = 'Start Measurement';
                    app.MeasurementStatusLabel.Text = 'Status: Stopped';
                 end
            end
            
            % If measuring, disable calibration and tare
            if app.StartStopMeasurementButton.Value
                app.RecordZeroPointButton.Enable = 'off';
                app.RecordCalWeightButton.Enable = 'off';
                app.TareButton.Enable = 'off';
                app.SetSimulatedLoadButton.Enable = 'off'; % Don't change simulated load during measurement
            elseif app.isM2KConnected % Re-enable if not measuring but connected
                app.SetSimulatedLoadButton.Enable = 'on';
                if app.isCalibrated
                    app.TareButton.Enable = 'on';
                end
            end
        end
        
        function cleanupM2K_scale(app)
            % Stop timer if running
            if ~isempty(app.measurementTimer) && isvalid(app.measurementTimer) && strcmp(app.measurementTimer.Running, 'on')
                stop(app.measurementTimer);
            end
            % Delete timer
            if ~isempty(app.measurementTimer) && isvalid(app.measurementTimer)
                delete(app.measurementTimer);
                app.measurementTimer = [];
            end

            if ~isempty(app.m2kDevice_scale) && ~clibIsNull(app.m2kDevice_scale)
                try
                    if ~isempty(app.analogOutput_scale)
                        app.analogOutput_scale.setVoltage(0, 0); % Reset DAC to 0V
                        app.analogOutput_scale.enableChannel(0, false);
                    end
                    if ~isempty(app.analogInput_scale)
                        app.analogInput_scale.enableChannel(0, false);
                    end
                    clib.libm2k.libm2k.context.contextCloseAll();
                catch ME_clean
                    disp(['Warning: Error during M2K cleanup: ', ME_clean.message]);
                end
            end
            app.m2kDevice_scale = [];
            app.analogInput_scale = [];
            app.analogOutput_scale = [];
            app.powerSupply_scale = [];
            app.isM2KConnected = false;
            app.M2KStatusLabel_Scale.Text = 'M2K Status: Disconnected';
            app.SimulatedVoltageLabel.Text = 'DAC W1 Output: --- V';

            % Reset calibration and tare states
            app.isCalibrated = false; app.CalibrationStatusLabel.Text = 'Status: Not Calibrated';
            app.isTared = false; app.tareOffsetGrams = 0; app.TareStatusLabel.Text = 'Status: Not Tared';
            app.zeroVoltage = []; app.calWeightVoltage = [];
        end

        function UIFigureCloseRequest(app, event)
            app.GeneralStatusTextArea.Value = {'Closing app and disconnecting M2K...'};
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
            app.UIFigure.Position = [50 50 1000 750]; % Adjusted size
            app.UIFigure.Name = 'Jelly Bean Counting Scale';
            app.UIFigure.CloseRequestFcn = createCallbackFcn(app, @UIFigureCloseRequest, true);

            app.MainGridLayout = uigridlayout(app.UIFigure);
            app.MainGridLayout.ColumnWidth = {'1x', '1x', '1x'};
            app.MainGridLayout.RowHeight = {120, 160, 150, '1x', 80}; % M2K, Sim, Cal, Plot+Display, Status

            % --- M2K Panel ---
            app.M2KPanel = uipanel(app.MainGridLayout);
            app.M2KPanel.Layout.Row = 1;
            app.M2KPanel.Layout.Column = 1;
            app.M2KPanel.Title = 'M2K Connection';
            
            uilabel(app.M2KPanel, 'Text', 'M2K Status:', 'Position', [10 70 80 22]);
            app.M2KStatusLabel_Scale = uilabel(app.M2KPanel, 'Text', 'Disconnected', 'Position', [100 70 150 22], 'FontWeight', 'bold');
            app.ConnectM2KButton_Scale = uibutton(app.M2KPanel, 'push', 'Text', 'Connect M2K', 'Position', [10 30 120 23], 'ButtonPushedFcn', createCallbackFcn(app, @ConnectM2KButton_ScalePushed, true));
            app.DisconnectM2KButton_Scale = uibutton(app.M2KPanel, 'push', 'Text', 'Disconnect M2K', 'Position', [140 30 120 23], 'ButtonPushedFcn', createCallbackFcn(app, @DisconnectM2KButton_ScalePushed, true));

            % --- Simulation Panel ---
            app.SimulationPanel = uipanel(app.MainGridLayout);
            app.SimulationPanel.Layout.Row = 2;
            app.SimulationPanel.Layout.Column = 1;
            app.SimulationPanel.Title = 'Simulation Control (Check-off #2)';
            
            app.SimulatedWeightEditFieldLabel = uilabel(app.SimulationPanel, 'Text', 'Simulated Wt (g):', 'Position', [10 100 120 22]);
            app.SimulatedWeightEditField = uieditfield(app.SimulationPanel, 'numeric', 'Position', [140 100 100 22], 'Value', 0, 'Limits', [0 app.maxSimulatedWeightGrams]);
            app.SetSimulatedLoadButton = uibutton(app.SimulationPanel, 'push', 'Text', 'Set Simulated Load', 'Position', [10 60 150 23], 'ButtonPushedFcn', createCallbackFcn(app, @SetSimulatedLoadButtonPushed, true));
            app.SimulatedVoltageLabel = uilabel(app.SimulationPanel, 'Text', 'DAC W1 Output: --- V', 'Position', [10 20 250 22]);

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
            
            app.CurrentVoltageDisplayLabel = uilabel(app.DisplayPanel, 'Text', 'Voltage: --- V', 'Position', [10 110 250 22], 'FontSize', 12);
            app.RawWeightDisplayLabel = uilabel(app.DisplayPanel, 'Text', 'Raw Wt: --- g', 'Position', [10 80 250 22], 'FontSize', 12);
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
            app.LivePlotUIAxes.Layout.Row = [1 3]; % Span rows 1 to 3
            app.LivePlotUIAxes.Layout.Column = 3;
            title(app.LivePlotUIAxes, 'Live Weight Reading');
            xlabel(app.LivePlotUIAxes, 'Time (samples)');
            ylabel(app.LivePlotUIAxes, 'Net Weight (g)');
            grid(app.LivePlotUIAxes, 'on');

            % --- General Status TextArea (Row 4, Span all Columns) ---
            app.GeneralStatusTextArea = uitextarea(app.MainGridLayout);
            app.GeneralStatusTextArea.Layout.Row = 4;
            app.GeneralStatusTextArea.Layout.Column = [1 3]; % Span all 3 columns
            app.GeneralStatusTextArea.Editable = 'off';
            app.GeneralStatusTextArea.Value = {'App Initialized.'};

            app.UIFigure.Visible = 'on';
        end
    end
end
