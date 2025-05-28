classdef M2K_GUI_App < matlab.apps.AppBase

    % Properties that correspond to app components
    properties (Access = public)
        UIFigure                     matlab.ui.Figure
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
        StartReferenceCalibrationButton matlab.ui.control.Button
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
    end

    % Properties that correspond to app data
    properties (Access = private)
        m2kDevice                   % Handle for the M2K device context
        analogInput                 % Handle for analog input object
        powerSupply                 % Handle for power supply object

        % Scale specific properties
        tareVoltage                  = 0;    % Voltage at tare
        gramsPerVolt                 = 0;    % Calibration factor (grams / Volt)
        isScaleCalibrated            = false;% Flag for scale calibration status
        isTared                      = false;% Flag for taring status
        avgJellyBeanWeightGrams      = 1.0;  % Default average jelly bean weight

        % Measurement parameters
        currentSampleRate            = 100000; % Default
        currentWeighingDuration      = 5;      % Default 5 seconds for weighing average

        % Output values
        lastAverageVoltage           = 0;
        currentWeightGrams           = 0;
        currentJellyBeanCount        = 0;

        isConnected = false         % Flag to track M2K connection status
        currentPowerSupplyVoltage = 2.5 % Initialized to default of its edit field

        initComponentsComplete = false; % Flag to manage initialization sequence
    end

    % Callbacks that handle component events
    methods (Access = private)

        % Code that executes after component creation
        function startupFcn(app)
            try
                disp('StartupFcn starting...');
                app.StatusText.Value = {'App Started. Please connect to M2K.'};
                % AvgJellyBeanWeightGramsEditField.Value is set in createComponents

                updateButtonStates(app);
                updateStatusLabels(app);
                updateOutputDisplays(app); % Initialize display text

                app.initComponentsComplete = true; % Set flag at the end of startup
                disp('StartupFcn completed successfully. initComponentsComplete=true');
            catch ME
                disp('%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%');
                disp('ERROR DURING APP STARTUPFCN:');
                disp(getReport(ME, 'extended', 'hyperlinks', 'off'));
                disp('%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%');
                if isvalid(app) && isprop(app, 'UIFigure') && isvalid(app.UIFigure)
                    delete(app.UIFigure); % Attempt to close app on critical startup error
                end
                rethrow(ME);
            end
        end

        % Button pushed function: ConnectM2KButton
        function ConnectM2KButtonPushed(app, event)
            app.StatusText.Value = {'Connecting to M2K...'};
            drawnow;

            try
                app.m2kDevice = clib.libm2k.libm2k.context.m2kOpen();
                pause(1);

                if clibIsNull(app.m2kDevice)
                    clib.libm2k.libm2k.context.contextCloseAll();
                    app.m2kDevice = [];
                    app.StatusText.Value = {'Error: M2K object is null. Restart MATLAB or check device connection and libm2k search path.'};
                    app.isConnected = false;
                else
                    app.analogInput = app.m2kDevice.getAnalogIn();
                    app.powerSupply = app.m2kDevice.getPowerSupply();
                    app.StatusText.Value = {'M2K Connected Successfully.'};
                    app.isConnected = true;
                    app.isScaleCalibrated = false;
                    app.isTared = false;
                    app.tareVoltage = 0;
                    app.gramsPerVolt = 0;
                end
            catch ME
                app.StatusText.Value = {['Connection Error: ', ME.message], 'Ensure libm2k is set up correctly and device is plugged in.'};
                app.m2kDevice = [];
                app.isConnected = false;
                try
                    clib.libm2k.libm2k.context.contextCloseAll();
                catch
                end
            end
            updateButtonStates(app);
            updateStatusLabels(app);
            updateOutputDisplays(app);
        end

        % Button pushed function: CalibrateADCDACButton
        function CalibrateADCDACButtonPushed(app, event)
            if ~app.isConnected || isempty(app.m2kDevice) || clibIsNull(app.m2kDevice)
                app.StatusText.Value = {'Error: M2K not connected.'};
                return;
            end
            app.StatusText.Value = {'Calibrating M2K ADC/DAC...'};
            drawnow;

            try
                app.m2kDevice.calibrateADC();
                app.m2kDevice.calibrateDAC();
                app.StatusText.Value = {'M2K ADC/DAC Calibrated.'};
            catch ME
                app.StatusText.Value = {['Error during M2K ADC/DAC calibration: ', ME.message]};
            end
        end

        % Button pushed function: SetPowerSupplyButton
        function SetPowerSupplyButtonPushed(app, event)
            if ~app.isConnected || isempty(app.powerSupply)
                app.StatusText.Value = {'Error: M2K not connected or power supply object not available.'};
                return;
            end
            app.currentPowerSupplyVoltage = app.PowerSupplyVoltageEditField.Value;
            app.StatusText.Value = {['Setting power supply V+ to ', num2str(app.currentPowerSupplyVoltage), 'V...']};
            drawnow;

            try
                app.powerSupply.enableChannel(0, true);
                app.powerSupply.pushChannel(0, app.currentPowerSupplyVoltage);
                app.StatusText.Value = {['Power supply V+ set to ', num2str(app.currentPowerSupplyVoltage), 'V.']};
            catch ME
                app.StatusText.Value = {['Error setting power supply: ', ME.message]};
            end
        end

        % Button pushed function: StartReferenceCalibrationButton
        function StartReferenceCalibrationButtonPushed(app, event)
            if ~app.isConnected
                app.StatusText.Value = {'Error: M2K not connected for calibration.'};
                return;
            end
            
            calibMass = app.CalibrationMassGramsEditField.Value;
            if calibMass <= 0
                app.StatusText.Value = {'Error: Calibration mass must be positive.'};
                return;
            end

            app.StatusText.Value = {['Ensure scale is empty, press Tare. Then place ', num2str(calibMass), 'g, press Measure Weight, then confirm below.']};
            
            choice = questdlg(['Calibration Steps: \n1. Ensure scale is EMPTY and press "Tare Scale" button. \n2. Place the known reference mass (', num2str(calibMass), 'g) on the scale. \n3. Press the "Measure Weight" button. \n\nOnce "Avg. Voltage" updates, is the current Average Voltage (', num2str(app.lastAverageVoltage, '%.4f'), ' V) correct for this mass?'], ...
                              'Confirm Calibration Measurement', ...
                              'Yes, use this voltage for calibration', 'No, cancel calibration', 'No, cancel calibration');
            if strcmp(choice, 'Yes, use this voltage for calibration')
                voltageWithMass = app.lastAverageVoltage;
                % Ensure tare was done recently, app.tareVoltage should be the voltage of the empty scale
                if ~app.isTared 
                     app.StatusText.Value = {'Error: Please Tare the empty scale first before confirming calibration.'};
                     uiwait(msgbox('Error: Please Tare the empty scale first before confirming calibration measurement.', 'Tare Required', 'warn'));
                     return;
                end

                voltageDifference = voltageWithMass - app.tareVoltage;
                
                if abs(voltageDifference) < 1e-6 % Avoid division by zero or tiny numbers
                    app.StatusText.Value = {'Error: Voltage difference for calibration is too small. Check connections, weight, or ensure tare and measurement were done correctly.'};
                    app.isScaleCalibrated = false;
                else
                    app.gramsPerVolt = calibMass / voltageDifference;
                    app.isScaleCalibrated = true;
                    app.StatusText.Value = {['Scale calibrated successfully. Factor: ', num2str(app.gramsPerVolt, '%.4f'), ' g/V']};
                end
            else
                app.StatusText.Value = {'Reference weight calibration cancelled or measurement not confirmed.'};
                app.isScaleCalibrated = false; % Ensure it's marked not calibrated if cancelled
            end
            updateStatusLabels(app);
            updateButtonStates(app);
            updateOutputDisplays(app);
        end

        % Button pushed function: ApplyDirectFactorButton
        function ApplyDirectFactorButtonPushed(app, event)
            refMv = app.ReferenceVoltageMvEditField.Value;
            eqGrams = app.EquivalentGramsEditField.Value;

            if refMv == 0
                app.StatusText.Value = {'Error: Reference millivolts cannot be zero for direct factor calibration.'};
                return;
            end
            if eqGrams <= 0
                app.StatusText.Value = {'Error: Equivalent grams must be positive.'};
                return;
            end
            
            refVolts = refMv / 1000; % Convert mV to V
            app.gramsPerVolt = eqGrams / refVolts;
            app.isScaleCalibrated = true;
            % Explicitly mark as not tared if direct factor is applied, user should re-tare.
            app.isTared = false; 
            app.tareVoltage = 0; % Reset tare voltage as calibration changes things
            app.StatusText.Value = {['Scale calibrated with direct factor. Factor: ', num2str(app.gramsPerVolt, '%.4f'), ' g/V. Please Tare the scale.']};
            
            updateStatusLabels(app);
            updateButtonStates(app);
            updateOutputDisplays(app);
        end
        
        % Button pushed function: TareButton
        function TareButtonPushed(app, event)
            if ~app.isConnected || isempty(app.analogInput)
                app.StatusText.Value = {'Error: M2K not connected to tare.'};
                return;
            end
            app.StatusText.Value = {'Taring... Acquiring baseline voltage...'};
            drawnow;

            try
                app.analogInput.enableChannel(0, true);
                app.analogInput.setSampleRate(app.currentSampleRate);
                
                tareDuration = 1.0; % 1-second average for taring
                samplesForTare = round(tareDuration * app.currentSampleRate);
                if samplesForTare <= 0 % Check for non-positive samples
                    app.StatusText.Value = {'Error: Samples for tare is zero or negative. Check sample rate.'};
                    return;
                end
                app.analogInput.setKernelBuffersCount(1);
                
                clibSamples = app.analogInput.getSamplesInterleaved_matlab(samplesForTare * 2);
                ch1Samples = double(clibSamples(1:2:end));

                if isempty(ch1Samples)
                    app.StatusText.Value = {'Warning: No samples received for taring.'};
                    return;
                end

                app.tareVoltage = mean(ch1Samples);
                app.isTared = true;
                app.lastAverageVoltage = app.tareVoltage; % After taring, the "current" voltage is the tare voltage
                app.StatusText.Value = {['Scale Tared. Tare Voltage: ', num2str(app.tareVoltage, '%.4f'), ' V']};
                
            catch ME
                app.StatusText.Value = {['Error during taring: ', ME.message]};
                app.isTared = false;
            end
            updateStatusLabels(app);
            updateOutputDisplays(app); % Update weight to 0 g
        end

        % Button pushed function: MeasureWeightButton
        function MeasureWeightButtonPushed(app, event)
            if ~app.isConnected || isempty(app.analogInput)
                app.StatusText.Value = {'Error: M2K not connected or analog input object not available.'};
                return;
            end
            
            currentStatus = {};
            if ~app.isScaleCalibrated
                 currentStatus{end+1} = 'Warning: Scale not calibrated. Weight may be inaccurate.';
            end
            if ~app.isTared
                 currentStatus{end+1} = 'Warning: Scale not tared. Weight may be relative to an old tare.';
            end
            if isempty(currentStatus)
                currentStatus = {'Measuring weight...'};
            else
                currentStatus = [currentStatus, {'Measuring weight...'}];
            end
            app.StatusText.Value = currentStatus;
            drawnow;

            try
                app.analogInput.enableChannel(0, true);
                instVoltage = app.analogInput.getVoltage(0);
                if isvalid(app) && isprop(app, 'InstantVoltageLabel') && isvalid(app.InstantVoltageLabel)
                    app.InstantVoltageLabel.Text = ['Inst. Voltage: ', num2str(instVoltage, '%.4f'), ' V'];
                end

                app.currentSampleRate = app.SampleRateEditField.Value;
                app.currentWeighingDuration = app.WeighingDurationEditField.Value;
                % app.avgJellyBeanWeightGrams is updated by its ValueChangedFcn directly

                if app.currentWeighingDuration <= 0 || app.currentSampleRate <=0
                    app.StatusText.Value = {'Error: Weighing duration and Sample Rate must be positive.'};
                    return;
                end

                app.analogInput.setSampleRate(app.currentSampleRate);
                samplesToAcquire = round(app.currentWeighingDuration * app.currentSampleRate);
                if samplesToAcquire <= 0 % Check for non-positive samples
                    app.StatusText.Value = {'Error: samplesToAcquire is zero or negative. Increase duration or sample rate.'};
                    return;
                end

                app.analogInput.setKernelBuffersCount(1);
                app.StatusText.Value = [app.StatusText.Value; {['Acquiring data for ', num2str(app.currentWeighingDuration), 's...']}];
                drawnow;
                
                clibSamples = app.analogInput.getSamplesInterleaved_matlab(samplesToAcquire * 2);
                ch1Samples = double(clibSamples(1:2:end));

                if isempty(ch1Samples)
                     app.StatusText.Value = [app.StatusText.Value; {'Warning: No samples received for measurement.'}];
                     app.lastAverageVoltage = app.tareVoltage; % Or some other default if no samples
                else
                    app.lastAverageVoltage = mean(ch1Samples);
                end
                
                app.StatusText.Value = [app.StatusText.Value; {'Measurement complete. Updating displays.'}];
                updateOutputDisplays(app);

            catch ME
                app.StatusText.Value = {['Error during measurement: ', ME.message], ME.getReport('basic', 'hyperlinks','off')};
            end
        end

        % Button pushed function: DisconnectM2KButton
        function DisconnectM2KButtonPushed(app, event)
            app.StatusText.Value = {'Disconnecting M2K...'};
            drawnow;
            cleanupM2K(app); % Call cleanup before resetting flags
            app.StatusText.Value = {'M2K Disconnected.'};
            app.isScaleCalibrated = false;
            app.isTared = false;
            app.tareVoltage = 0;
            app.gramsPerVolt = 0;
            app.lastAverageVoltage = 0;
            app.currentWeightGrams = 0;
            app.currentJellyBeanCount = 0;
            updateButtonStates(app);
            updateStatusLabels(app);
            updateOutputDisplays(app); % Reset displays
        end

        % UIFigure close request function
        function UIFigureCloseRequest(app, event)
            if isvalid(app) && isprop(app,'StatusText') && isvalid(app.StatusText)
                app.StatusText.Value = {'Closing App and Disconnecting M2K...'};
            end
            drawnow;
            cleanupM2K(app);
            delete(app);
        end

        % Helper function to update button enable/disable states
        function updateButtonStates(app)
            if app.isConnected
                app.ConnectM2KButton.Enable = 'off';
                app.CalibrateADCDACButton.Enable = 'on';
                app.SetPowerSupplyButton.Enable = 'on';
                app.DisconnectM2KButton.Enable = 'on';
                app.StartReferenceCalibrationButton.Enable = 'on';
                app.ApplyDirectFactorButton.Enable = 'on';
                app.TareButton.Enable = 'on';
                app.MeasureWeightButton.Enable = 'on';
            else
                app.ConnectM2KButton.Enable = 'on';
                app.CalibrateADCDACButton.Enable = 'off';
                app.SetPowerSupplyButton.Enable = 'off';
                app.DisconnectM2KButton.Enable = 'off';
                app.StartReferenceCalibrationButton.Enable = 'off';
                app.ApplyDirectFactorButton.Enable = 'off';
                app.TareButton.Enable = 'off';
                app.MeasureWeightButton.Enable = 'off';
            end
        end

        % Helper function to update status labels
        function updateStatusLabels(app)
            if app.isScaleCalibrated
                app.CalibrationStatusLabel.Text = ['Calibration: Calibrated (', num2str(app.gramsPerVolt, '%.2e'), ' g/V)'];
                app.CalibrationStatusLabel.FontColor = [0 0.5 0]; % Dark Green
            else
                app.CalibrationStatusLabel.Text = 'Calibration: Not Calibrated';
                app.CalibrationStatusLabel.FontColor = [0.8 0 0]; % Red
            end

            if app.isTared
                app.TareStatusLabel.Text = ['Tare: Tared (at ', num2str(app.tareVoltage, '%.4f'), ' V)'];
                app.TareStatusLabel.FontColor = [0 0.5 0]; % Dark Green
            else
                app.TareStatusLabel.Text = 'Tare: Not Tared';
                app.TareStatusLabel.FontColor = [0.8 0 0]; % Red
            end
        end
        
        % Helper function to update all output displays
        function updateOutputDisplays(app)
            app.AverageVoltageDisplayLabel.Text = ['Avg. Voltage: ', num2str(app.lastAverageVoltage, '%.4f'), ' V'];

            if app.isScaleCalibrated
                voltageAboveTare = app.lastAverageVoltage - app.tareVoltage;
                app.currentWeightGrams = voltageAboveTare * app.gramsPerVolt;
                app.WeightDisplayLabel.Text = ['Weight: ', num2str(app.currentWeightGrams, '%.2f'), ' g'];

                if app.avgJellyBeanWeightGrams > 0
                    app.currentJellyBeanCount = round(app.currentWeightGrams / app.avgJellyBeanWeightGrams);
                    if app.currentJellyBeanCount < 0 
                        app.currentJellyBeanCount = 0;
                    end
                    app.JellyBeanCountDisplayLabel.Text = ['Jelly Beans: ~', num2str(app.currentJellyBeanCount)];
                else
                    app.JellyBeanCountDisplayLabel.Text = 'Jelly Beans: Enter avg. bean wt.';
                end
            else
                app.WeightDisplayLabel.Text = 'Weight: --- g (Not Calibrated)';
                app.JellyBeanCountDisplayLabel.Text = 'Jelly Beans: --- (Not Calibrated)';
            end
        end

        % Helper function for M2K cleanup
        function cleanupM2K(app)
            if isvalid(app) && ~isempty(app.m2kDevice) && ~clibIsNull(app.m2kDevice)
                try
                    if isprop(app, 'powerSupply') && ~isempty(app.powerSupply) && isvalid(app.powerSupply)
                         app.powerSupply.enableChannel(0, false);
                    end
                    if isprop(app, 'analogInput') && ~isempty(app.analogInput) && isvalid(app.analogInput)
                        app.analogInput.enableChannel(0, false);
                    end
                    clib.libm2k.libm2k.context.contextCloseAll();
                catch ME_cleanup
                    if isvalid(app) && isprop(app,'StatusText') && isvalid(app.StatusText) % Check if StatusText is still valid
                         app.StatusText.Value = [app.StatusText.Value; {['Warning: Error during M2K cleanup: ', ME_cleanup.message]}];
                    else
                        disp(['Warning: Error during M2K cleanup: ', ME_cleanup.message]);
                    end
                end
            end
            if isvalid(app)
                app.m2kDevice = [];
                app.analogInput = [];
                app.powerSupply = [];
                app.isConnected = false;

                if isprop(app, 'InstantVoltageLabel') && isvalid(app.InstantVoltageLabel)
                    app.InstantVoltageLabel.Text = 'Inst. Voltage: -- V';
                end
            end
        end

        % Value changed function for AverageJellyBeanWeightGramsEditField
        function avgJellyBeanWeightChanged(app, src, event)
            if isvalid(app) && isprop(app, 'AvgJellyBeanWeightGramsEditField') && isvalid(app.AvgJellyBeanWeightGramsEditField)
                app.avgJellyBeanWeightGrams = app.AvgJellyBeanWeightGramsEditField.Value;
            end

            if ~app.initComponentsComplete % Check the flag
                return;
            end

            if app.avgJellyBeanWeightGrams <= 0
                if isprop(app, 'StatusText') && isvalid(app.StatusText)
                    app.StatusText.Value = [app.StatusText.Value; {'Warning: Average jelly bean weight must be positive.'}];
                end
            end
            updateOutputDisplays(app);
        end
    end

    % App initialization and construction
    methods (Access = private)

        % Create UIFigure and components
        function createComponents(app)
            try
                app.UIFigure = uifigure('Visible', 'off');
                app.UIFigure.Position = [100 100 850 700];
                app.UIFigure.Name = 'M2K Weighing Scale GUI'; % Set name early
                app.UIFigure.CloseRequestFcn = createCallbackFcn(app, @UIFigureCloseRequest, true);

                % --- Connection & M2K Setup Panel ---
                app.ConnectionSetupPanel = uipanel(app.UIFigure);
                app.ConnectionSetupPanel.Title = 'M2K Connection & Power';
                app.ConnectionSetupPanel.Position = [20 600 400 90];

                app.ConnectM2KButton = uibutton(app.ConnectionSetupPanel, 'push');
                app.ConnectM2KButton.ButtonPushedFcn = createCallbackFcn(app, @ConnectM2KButtonPushed, true);
                app.ConnectM2KButton.Text = 'Connect M2K';
                app.ConnectM2KButton.Position = [10 50 100 23];

                app.DisconnectM2KButton = uibutton(app.ConnectionSetupPanel, 'push');
                app.DisconnectM2KButton.ButtonPushedFcn = createCallbackFcn(app, @DisconnectM2KButtonPushed, true);
                app.DisconnectM2KButton.Text = 'Disconnect M2K';
                app.DisconnectM2KButton.Position = [120 50 110 23];
                
                app.CalibrateADCDACButton = uibutton(app.ConnectionSetupPanel, 'push');
                app.CalibrateADCDACButton.ButtonPushedFcn = createCallbackFcn(app, @CalibrateADCDACButtonPushed, true);
                app.CalibrateADCDACButton.Text = 'Calibrate ADC/DAC';
                app.CalibrateADCDACButton.Position = [240 50 140 23];

                app.PowerSupplyVoltageEditFieldLabel = uilabel(app.ConnectionSetupPanel);
                app.PowerSupplyVoltageEditFieldLabel.HorizontalAlignment = 'right';
                app.PowerSupplyVoltageEditFieldLabel.Text = 'V+ (V)';
                app.PowerSupplyVoltageEditFieldLabel.Position = [10 15 40 22];

                app.PowerSupplyVoltageEditField = uieditfield(app.ConnectionSetupPanel, 'numeric');
                app.PowerSupplyVoltageEditField.Limits = [-5 5];
                app.PowerSupplyVoltageEditField.ValueDisplayFormat = '%.2f';
                app.PowerSupplyVoltageEditField.Value = app.currentPowerSupplyVoltage; % Use property default
                app.PowerSupplyVoltageEditField.Position = [60 15 70 22];

                app.SetPowerSupplyButton = uibutton(app.ConnectionSetupPanel, 'push');
                app.SetPowerSupplyButton.ButtonPushedFcn = createCallbackFcn(app, @SetPowerSupplyButtonPushed, true);
                app.SetPowerSupplyButton.Text = 'Set V+';
                app.SetPowerSupplyButton.Position = [140 15 80 23];
                
                % --- Scale Settings Panel ---
                app.ScaleSettingsPanel = uipanel(app.UIFigure);
                app.ScaleSettingsPanel.Title = 'Scale Measurement Settings';
                app.ScaleSettingsPanel.Position = [20 470 400 120];

                app.SampleRateHzEditFieldLabel = uilabel(app.ScaleSettingsPanel);
                app.SampleRateHzEditFieldLabel.HorizontalAlignment = 'right';
                app.SampleRateHzEditFieldLabel.Text = 'Sample Rate (Hz)';
                app.SampleRateHzEditFieldLabel.Position = [10 80 100 22];

                app.SampleRateEditField = uieditfield(app.ScaleSettingsPanel, 'numeric');
                app.SampleRateEditField.Limits = [1 Inf];
                app.SampleRateEditField.ValueDisplayFormat = '%d';
                app.SampleRateEditField.Value = app.currentSampleRate;
                app.SampleRateEditField.Position = [120 80 100 22];

                app.WeighingDurationEditFieldLabel = uilabel(app.ScaleSettingsPanel);
                app.WeighingDurationEditFieldLabel.HorizontalAlignment = 'right';
                app.WeighingDurationEditFieldLabel.Text = 'Weighing Avg. Time (s)';
                app.WeighingDurationEditFieldLabel.Position = [10 50 130 22];

                app.WeighingDurationEditField = uieditfield(app.ScaleSettingsPanel, 'numeric');
                app.WeighingDurationEditField.Limits = [0.01 Inf];
                app.WeighingDurationEditField.ValueDisplayFormat = '%.2f';
                app.WeighingDurationEditField.Value = app.currentWeighingDuration;
                app.WeighingDurationEditField.Position = [150 50 70 22];

                app.AvgJellyBeanWeightGramsEditFieldLabel = uilabel(app.ScaleSettingsPanel);
                app.AvgJellyBeanWeightGramsEditFieldLabel.HorizontalAlignment = 'right';
                app.AvgJellyBeanWeightGramsEditFieldLabel.Text = 'Avg. Jelly Bean Wt. (g)';
                app.AvgJellyBeanWeightGramsEditFieldLabel.Position = [10 20 130 22];

                app.AvgJellyBeanWeightGramsEditField = uieditfield(app.ScaleSettingsPanel, 'numeric');
                app.AvgJellyBeanWeightGramsEditField.Limits = [0.001 Inf];
                app.AvgJellyBeanWeightGramsEditField.ValueDisplayFormat = '%.3f';
                app.AvgJellyBeanWeightGramsEditField.Value = app.avgJellyBeanWeightGrams;
                app.AvgJellyBeanWeightGramsEditField.Position = [150 20 70 22];
                app.AvgJellyBeanWeightGramsEditField.ValueChangedFcn = createCallbackFcn(app, @avgJellyBeanWeightChanged, true);

                % --- Calibration Panel ---
                app.CalibrationPanel = uipanel(app.UIFigure);
                app.CalibrationPanel.Title = 'Scale Calibration';
                app.CalibrationPanel.Position = [20 230 400 230];

                app.CalibrationMassGramsEditFieldLabel = uilabel(app.CalibrationPanel);
                app.CalibrationMassGramsEditFieldLabel.HorizontalAlignment = 'right';
                app.CalibrationMassGramsEditFieldLabel.Text = 'Ref. Mass (g):';
                app.CalibrationMassGramsEditFieldLabel.Position = [10 190 85 22];

                app.CalibrationMassGramsEditField = uieditfield(app.CalibrationPanel, 'numeric');
                app.CalibrationMassGramsEditField.Limits = [0.001 Inf];
                app.CalibrationMassGramsEditField.Value = 100;
                app.CalibrationMassGramsEditField.Position = [105 190 70 22];

                app.StartReferenceCalibrationButton = uibutton(app.CalibrationPanel, 'push');
                app.StartReferenceCalibrationButton.ButtonPushedFcn = createCallbackFcn(app, @StartReferenceCalibrationButtonPushed, true);
                app.StartReferenceCalibrationButton.Text = 'Calibrate with Reference Mass';
                app.StartReferenceCalibrationButton.Position = [190 190 190 23];
                
                app.CalibrationStatusLabel = uilabel(app.CalibrationPanel);
                app.CalibrationStatusLabel.Text = 'Calibration Status: Not Calibrated';
                app.CalibrationStatusLabel.Position = [10 160 380 22];
                app.CalibrationStatusLabel.FontWeight = 'bold';

                app.DirectFactorPanel = uipanel(app.CalibrationPanel);
                app.DirectFactorPanel.Title = 'Direct Factor Calibration (Alternative)';
                app.DirectFactorPanel.Position = [10 50 380 100];

                app.ReferenceVoltageMvEditFieldLabel = uilabel(app.DirectFactorPanel);
                app.ReferenceVoltageMvEditFieldLabel.HorizontalAlignment = 'right';
                app.ReferenceVoltageMvEditFieldLabel.Text = 'If change of (mV):';
                app.ReferenceVoltageMvEditFieldLabel.Position = [5 60 110 22];

                app.ReferenceVoltageMvEditField = uieditfield(app.DirectFactorPanel, 'numeric');
                app.ReferenceVoltageMvEditField.Value = 100;
                app.ReferenceVoltageMvEditField.Position = [125 60 70 22];

                app.EquivalentGramsEditFieldLabel = uilabel(app.DirectFactorPanel);
                app.EquivalentGramsEditFieldLabel.HorizontalAlignment = 'right';
                app.EquivalentGramsEditFieldLabel.Text = 'Equals (grams):';
                app.EquivalentGramsEditFieldLabel.Position = [5 30 110 22];

                app.EquivalentGramsEditField = uieditfield(app.DirectFactorPanel, 'numeric');
                app.EquivalentGramsEditField.Limits = [0.001 Inf];
                app.EquivalentGramsEditField.Value = 50;
                app.EquivalentGramsEditField.Position = [125 30 70 22];

                app.ApplyDirectFactorButton = uibutton(app.DirectFactorPanel, 'push');
                app.ApplyDirectFactorButton.ButtonPushedFcn = createCallbackFcn(app, @ApplyDirectFactorButtonPushed, true);
                app.ApplyDirectFactorButton.Text = 'Apply Direct Factor';
                app.ApplyDirectFactorButton.Position = [210 45 150 23];

                % --- Operation Panel (Tare & Measure) ---
                app.OperationPanel = uipanel(app.UIFigure);
                app.OperationPanel.Title = 'Operation';
                app.OperationPanel.Position = [450 470 380 220];

                app.TareButton = uibutton(app.OperationPanel, 'push');
                app.TareButton.ButtonPushedFcn = createCallbackFcn(app, @TareButtonPushed, true);
                app.TareButton.Text = 'Tare Scale';
                app.TareButton.FontSize = 14;
                app.TareButton.FontWeight = 'bold';
                app.TareButton.Position = [30 170 150 30];

                app.TareStatusLabel = uilabel(app.OperationPanel);
                app.TareStatusLabel.Text = 'Tare Status: Not Tared';
                app.TareStatusLabel.Position = [30 140 320 22];
                app.TareStatusLabel.FontWeight = 'bold';

                app.MeasureWeightButton = uibutton(app.OperationPanel, 'push');
                app.MeasureWeightButton.ButtonPushedFcn = createCallbackFcn(app, @MeasureWeightButtonPushed, true);
                app.MeasureWeightButton.Text = 'Measure Weight';
                app.MeasureWeightButton.FontSize = 14;
                app.MeasureWeightButton.FontWeight = 'bold';
                app.MeasureWeightButton.Position = [30 80 320 40];

                app.InstantVoltageLabel = uilabel(app.OperationPanel);
                app.InstantVoltageLabel.Text = 'Inst. Voltage: -- V';
                app.InstantVoltageLabel.Position = [30 40 200 22];

                % --- Output Display Panel ---
                app.OutputDisplayPanel = uipanel(app.UIFigure);
                app.OutputDisplayPanel.Title = 'Live Output';
                app.OutputDisplayPanel.Position = [450 160 380 300];

                app.AverageVoltageDisplayLabel = uilabel(app.OutputDisplayPanel);
                app.AverageVoltageDisplayLabel.Text = 'Avg. Voltage: -- V';
                app.AverageVoltageDisplayLabel.FontSize = 14;
                app.AverageVoltageDisplayLabel.Position = [20 250 340 22];

                app.WeightDisplayLabel = uilabel(app.OutputDisplayPanel);
                app.WeightDisplayLabel.Text = 'Weight: -- g';
                app.WeightDisplayLabel.FontSize = 18;
                app.WeightDisplayLabel.FontWeight = 'bold';
                app.WeightDisplayLabel.Position = [20 210 340 25];

                app.JellyBeanCountDisplayLabel = uilabel(app.OutputDisplayPanel);
                app.JellyBeanCountDisplayLabel.Text = 'Jelly Beans: --';
                app.JellyBeanCountDisplayLabel.FontSize = 18;
                app.JellyBeanCountDisplayLabel.FontWeight = 'bold';
                app.JellyBeanCountDisplayLabel.Position = [20 170 340 25];

                % --- Status Text Panel (bottom left) ---
                app.StatusTextLabel = uilabel(app.UIFigure);
                app.StatusTextLabel.Text = 'System Log:';
                app.StatusTextLabel.Position = [20 125 400 22];

                app.StatusText = uitextarea(app.UIFigure);
                app.StatusText.Editable = 'off';
                app.StatusText.Position = [20 20 400 100];

                app.UIFigure.Visible = 'on';
                disp('createComponents finished successfully, UIFigure should be visible.');
            catch ME
                disp('%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%');
                disp('ERROR DURING APP CREATECOMPONENTS:');
                disp(getReport(ME, 'extended', 'hyperlinks', 'off'));
                disp('%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%');
                if isvalid(app) && isprop(app, 'UIFigure') && isvalid(app.UIFigure) % Check if app and UIFigure are valid
                    delete(app.UIFigure);
                end
                rethrow(ME);
            end
        end
    end

    % App creation and deletion
    methods (Access = public)
        % Construct app
        function app = M2K_GUI_App()
            createComponents(app)
            registerApp(app, app.UIFigure)
            runStartupFcn(app, @startupFcn)
            if nargout == 0
                clear app
            end
        end

        % Code that executes before app deletion
        function delete(app)
            cleanupM2K(app); % Call cleanup before deleting UIFigure
            if isvalid(app) && isprop(app, 'UIFigure') && isvalid(app.UIFigure)
                 delete(app.UIFigure)
            end
        end
    end
end