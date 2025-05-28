classdef JellyBeanScaleGUI_App < matlab.apps.AppBase

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
        StartCalibrationProcessButton matlab.ui.control.Button % Changed from StartReferenceCalibrationButton
        CalibrationStepInstructionLabel matlab.ui.control.Label % New
        RecordEmptyScaleButton        matlab.ui.control.Button   % New
        RecordWeightWithMassButton    matlab.ui.control.Button   % New
        CancelCalibrationButton       matlab.ui.control.Button   % New
        CalibrationStatusLabel       matlab.ui.control.Label     % Existing, shows final status
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

        tareVoltage                  = 0;
        gramsPerVolt                 = 0;
        isScaleCalibrated            = false;
        isTared                      = false;
        avgJellyBeanWeightGrams      = 1.0;

        currentSampleRate            = 100000;
        currentWeighingDuration      = 5;

        lastAverageVoltage           = 0;
        currentWeightGrams           = 0;
        currentJellyBeanCount        = 0;

        isConnected = false
        currentPowerSupplyVoltage = 2.5

        initComponentsComplete = false;
        
        % For guided calibration
        calibrationState          = 0;     % 0:idle, 1:await_empty_tare, 2:await_mass_measurement
        calibrationTareVoltage    = 0;     % Tare voltage specific to calibration sequence
    end

    % Callbacks that handle component events
    methods (Access = private)

        function startupFcn(app)
            disp('StartupFcn starting...');
            app.StatusText.Value = {'App Started. Please connect to M2K.'};
            
            updateButtonStates(app);
            updateStatusLabels(app);
            updateOutputDisplays(app); 
            updateCalibrationUI(app); % Initialize calibration UI state

            app.initComponentsComplete = true;
            disp('StartupFcn completed. initComponentsComplete=true.');
        end

        % --- New Helper Function for Calibration UI ---
        function updateCalibrationUI(app)
            isIdle = (app.calibrationState == 0);
            isStep1_AwaitEmpty = (app.calibrationState == 1);
            isStep2_AwaitMass = (app.calibrationState == 2);
            canProceed = app.isConnected; % Calibration needs M2K connection

            % Enable/disable edit field
            app.CalibrationMassGramsEditField.Enable = (isIdle && canProceed);

            % Start/Restart button
            app.StartCalibrationProcessButton.Enable = canProceed; % Always enabled if connected, text changes
            if isIdle
                app.StartCalibrationProcessButton.Text = 'Start New Calibration';
            else
                app.StartCalibrationProcessButton.Text = 'Restart Calibration Process';
            end
            
            % Step-specific buttons
            app.RecordEmptyScaleButton.Enable = (isStep1_AwaitEmpty && canProceed);
            app.RecordWeightWithMassButton.Enable = (isStep2_AwaitMass && canProceed);
            app.CancelCalibrationButton.Enable = (~isIdle && canProceed);

            % Instruction Label
            if ~canProceed && isIdle % Only show "connect M2K" if idle and not connected.
                app.CalibrationStepInstructionLabel.Text = 'Connect to M2K to enable calibration.';
            elseif isIdle
                app.CalibrationStepInstructionLabel.Text = 'Enter Ref. Mass & click "Start New Calibration".';
            elseif isStep1_AwaitEmpty
                app.CalibrationStepInstructionLabel.Text = '1. Ensure scale is EMPTY. Then click button below.';
            elseif isStep2_AwaitMass
                mass_val = app.CalibrationMassGramsEditField.Value;
                app.CalibrationStepInstructionLabel.Text = ['2. Place ', num2str(mass_val), 'g on scale. Then click button below.'];
            end
        end

        % --- Modified Calibration Callbacks ---
        function StartCalibrationProcessButtonPushed(app, event)
            if ~app.isConnected, app.StatusText.Value = {'Error: M2K not connected.'}; return; end
            
            calibMass = app.CalibrationMassGramsEditField.Value;
            if calibMass <= 0
                app.StatusText.Value = {'Error: Reference mass must be positive.'};
                return;
            end
            
            app.calibrationState = 1; % Move to step 1: Awaiting empty scale tare
            app.isScaleCalibrated = false; % Reset calibration status at start
            app.gramsPerVolt = 0;
            app.StatusText.Value = {['Calibration process started. Ref Mass: ', num2str(calibMass), 'g.']};
            updateCalibrationUI(app);
            updateStatusLabels(app); % Reflect that it's no longer calibrated
        end

        function RecordEmptyScaleButtonPushed(app, event)
            if ~app.isConnected || app.calibrationState ~= 1, return; end % Safety check
            app.StatusText.Value = [app.StatusText.Value; {'Recording empty scale voltage (tare for calibration)...'}];
            drawnow;

            voltage = acquireAverageVoltage(app, 1.0); % Use helper for 1s acquisition
            if isempty(voltage)
                app.StatusText.Value = [app.StatusText.Value; {'Error: Failed to acquire empty scale voltage.'}];
                % Optionally reset calibrationState to 0 or handle error
                % For now, user can try again or cancel.
                return;
            end

            app.calibrationTareVoltage = voltage;
            app.StatusText.Value = [app.StatusText.Value; {['Empty scale voltage recorded: ', num2str(app.calibrationTareVoltage, '%.4f'), ' V.']}];
            app.calibrationState = 2; % Move to step 2: Awaiting measurement with mass
            updateCalibrationUI(app);
        end

        function RecordWeightWithMassButtonPushed(app, event)
            if ~app.isConnected || app.calibrationState ~= 2, return; end % Safety check
            app.StatusText.Value = [app.StatusText.Value; {'Recording voltage with reference mass...'}];
            drawnow;

            voltageWithMass = acquireAverageVoltage(app, app.currentWeighingDuration); % Use app's weighing duration
             if isempty(voltageWithMass)
                app.StatusText.Value = [app.StatusText.Value; {'Error: Failed to acquire voltage with mass.'}];
                return;
            end

            app.StatusText.Value = [app.StatusText.Value; {['Voltage with mass recorded: ', num2str(voltageWithMass, '%.4f'), ' V.']}];
            
            calibMass = app.CalibrationMassGramsEditField.Value;
            voltageDifference = voltageWithMass - app.calibrationTareVoltage;

            if abs(voltageDifference) < 1e-6
                app.StatusText.Value = [app.StatusText.Value; {'Error: Voltage difference for calibration is too small. Check setup.'}];
                app.isScaleCalibrated = false; % Ensure status reflects failure
                % Optionally reset calibrationState to 1 to retry mass measurement, or 0 to restart full.
                % For now, user might cancel or restart.
            else
                app.gramsPerVolt = calibMass / voltageDifference;
                app.isScaleCalibrated = true;
                
                % Crucially, set the main app tare to this calibration tare
                app.tareVoltage = app.calibrationTareVoltage;
                app.isTared = true;
                app.lastAverageVoltage = voltageWithMass; % Update last measured voltage for display

                app.StatusText.Value = [app.StatusText.Value; {['Scale calibrated successfully! Factor: ', num2str(app.gramsPerVolt, '%.4f'), ' g/V. Scale is now tared.']}];
            end
            
            app.calibrationState = 0; % Reset to idle
            updateCalibrationUI(app);
            updateStatusLabels(app); % Update both cal and tare status
            updateOutputDisplays(app); % Reflect new calibration and weight
        end

        function CancelCalibrationButtonPushed(app, event)
            app.calibrationState = 0; % Reset to idle
            app.StatusText.Value = [app.StatusText.Value; {'Reference weight calibration cancelled by user.'}];
            updateCalibrationUI(app);
        end
        
        % --- Helper function to acquire voltage ---
        function avgVoltage = acquireAverageVoltage(app, duration)
            avgVoltage = []; % Default to empty if error
            if ~app.isConnected || isempty(app.analogInput)
                app.StatusText.Value = [app.StatusText.Value; {'M2K not connected for acquisition.'}];
                return;
            end
            try
                app.analogInput.enableChannel(0, true);
                currentSR = app.SampleRateEditField.Value; % Use current sample rate from UI
                app.analogInput.setSampleRate(currentSR);
                
                samplesToAcquire = round(duration * currentSR);
                if samplesToAcquire <= 0
                    app.StatusText.Value = [app.StatusText.Value; {['Error: Invalid samples to acquire (',num2str(samplesToAcquire),'). Check rate/duration.']}];
                    return;
                end
                app.analogInput.setKernelBuffersCount(1);
                
                clibSamples = app.analogInput.getSamplesInterleaved_matlab(samplesToAcquire * 2);
                ch1Samples = double(clibSamples(1:2:end));

                if isempty(ch1Samples)
                    app.StatusText.Value = [app.StatusText.Value; {'Warning: No samples received during acquisition helper.'}];
                else
                    avgVoltage = mean(ch1Samples);
                end
            catch ME
                app.StatusText.Value = [app.StatusText.Value; {['Error during voltage acquisition: ', ME.message]}];
            end
        end


        % --- Existing Callbacks (ensure they are compatible, e.g. Connect/Disconnect calls updateCalibrationUI) ---
        function ConnectM2KButtonPushed(app, event)
            app.StatusText.Value = {'Connecting to M2K...'}; drawnow;
            try
                app.m2kDevice = clib.libm2k.libm2k.context.m2kOpen(); pause(1);
                if clibIsNull(app.m2kDevice)
                    clib.libm2k.libm2k.context.contextCloseAll(); app.m2kDevice = [];
                    app.StatusText.Value = {'Error: M2K object is null.'}; app.isConnected = false;
                else
                    app.analogInput = app.m2kDevice.getAnalogIn(); app.powerSupply = app.m2kDevice.getPowerSupply();
                    app.StatusText.Value = {'M2K Connected.'}; app.isConnected = true;
                    app.isScaleCalibrated = false; app.isTared = false; app.tareVoltage = 0; app.gramsPerVolt = 0;
                end
            catch ME
                app.StatusText.Value = {['Connection Error: ', ME.message]};
                app.m2kDevice = []; app.isConnected = false; try clib.libm2k.libm2k.context.contextCloseAll(); catch; end
            end
            updateButtonStates(app); updateStatusLabels(app); updateOutputDisplays(app); updateCalibrationUI(app); % Update cal UI
        end

        function DisconnectM2KButtonPushed(app, event)
            app.StatusText.Value = {'Disconnecting M2K...'}; drawnow;
            cleanupM2K(app);
            app.StatusText.Value = {'M2K Disconnected.'};
            app.isScaleCalibrated = false; app.isTared = false; app.tareVoltage = 0; app.gramsPerVolt = 0;
            app.lastAverageVoltage = 0; app.currentWeightGrams = 0; app.currentJellyBeanCount = 0;
            app.calibrationState = 0; % Reset calibration state
            updateButtonStates(app); updateStatusLabels(app); updateOutputDisplays(app); updateCalibrationUI(app); % Update cal UI
        end

        function CalibrateADCDACButtonPushed(app, event) % Unchanged
            if ~app.isConnected || isempty(app.m2kDevice) || clibIsNull(app.m2kDevice)
                app.StatusText.Value = {'Error: M2K not connected.'}; return;
            end
            app.StatusText.Value = {'Calibrating M2K ADC/DAC...'}; drawnow;
            try
                app.m2kDevice.calibrateADC();
                app.m2kDevice.calibrateDAC();
                app.StatusText.Value = {'M2K ADC/DAC Calibrated.'};
            catch ME
                app.StatusText.Value = {['Error during M2K ADC/DAC calibration: ', ME.message]};
            end
        end

        function SetPowerSupplyButtonPushed(app, event) % Unchanged
            if ~app.isConnected || isempty(app.powerSupply)
                app.StatusText.Value = {'Error: M2K not connected or power supply object not available.'}; return;
            end
            app.currentPowerSupplyVoltage = app.PowerSupplyVoltageEditField.Value;
            app.StatusText.Value = {['Setting power supply V+ to ', num2str(app.currentPowerSupplyVoltage), 'V...']}; drawnow;
            try
                app.powerSupply.enableChannel(0, true);
                app.powerSupply.pushChannel(0, app.currentPowerSupplyVoltage);
                app.StatusText.Value = {['Power supply V+ set to ', num2str(app.currentPowerSupplyVoltage), 'V.']};
            catch ME
                app.StatusText.Value = {['Error setting power supply: ', ME.message]};
            end
        end
        
        function ApplyDirectFactorButtonPushed(app, event) % Largely unchanged, ensures tare reset
            refMv = app.ReferenceVoltageMvEditField.Value; eqGrams = app.EquivalentGramsEditField.Value;
            if refMv == 0, app.StatusText.Value = {'Error: Ref. mV cannot be zero.'}; return; end
            if eqGrams <= 0, app.StatusText.Value = {'Error: Equivalent grams must be positive.'}; return; end
            
            app.gramsPerVolt = eqGrams / (refMv / 1000); app.isScaleCalibrated = true;
            app.isTared = false; app.tareVoltage = 0; % Reset tare after direct calibration
            app.calibrationState = 0; % Reset ref weight cal state too
            app.StatusText.Value = {['Direct factor calibrated. Factor: ', num2str(app.gramsPerVolt, '%.4f'), ' g/V. Please Tare the scale.']};
            updateStatusLabels(app); updateButtonStates(app); updateOutputDisplays(app); updateCalibrationUI(app);
        end
        
        function TareButtonPushed(app, event) % General Tare
            app.calibrationState = 0; % Cancel any ongoing ref weight calibration if general tare is pressed
            updateCalibrationUI(app); 

            voltage = acquireAverageVoltage(app, 1.0);
            if ~isempty(voltage)
                app.tareVoltage = voltage;
                app.isTared = true;
                app.lastAverageVoltage = app.tareVoltage;
                app.StatusText.Value = [app.StatusText.Value; {['Scale Tared (General). Tare Voltage: ', num2str(app.tareVoltage, '%.4f'), ' V']}];
            else
                 app.StatusText.Value = [app.StatusText.Value; {'Error: Failed to tare (General).'}];
                 app.isTared = false; % Ensure it's marked not tared on failure
            end
            updateStatusLabels(app); updateOutputDisplays(app);
        end

        function MeasureWeightButtonPushed(app, event) % Uses acquireAverageVoltage
            if ~app.isConnected, app.StatusText.Value = {'Error: M2K not connected.'}; return; end
            statusMsg = {};
            if ~app.isScaleCalibrated, statusMsg{end+1} = 'Warning: Not calibrated.'; end
            if ~app.isTared, statusMsg{end+1} = 'Warning: Not tared.'; end
            app.StatusText.Value = [statusMsg, {'Measuring weight...'}]; drawnow;

            instVoltage = app.analogInput.getVoltage(0); % Quick check still useful
            if isvalid(app.InstantVoltageLabel), app.InstantVoltageLabel.Text = ['Inst. V: ', num2str(instVoltage, '%.4f')]; end

            app.currentWeighingDuration = app.WeighingDurationEditField.Value;
            avgVoltage = acquireAverageVoltage(app, app.currentWeighingDuration);

            if ~isempty(avgVoltage)
                app.lastAverageVoltage = avgVoltage;
                app.StatusText.Value = [app.StatusText.Value; {'Measurement complete.'}];
            else
                app.StatusText.Value = [app.StatusText.Value; {'Warning: Failed to get valid measurement.'}];
                % app.lastAverageVoltage remains unchanged or reset if desired
            end
            updateOutputDisplays(app);
        end

        function UIFigureCloseRequest(app, event) % Unchanged
            if isvalid(app) && isprop(app,'StatusText') && isvalid(app.StatusText)
                app.StatusText.Value = {'Closing App & Disconnecting M2K...'};
            end
            drawnow; cleanupM2K(app); delete(app);
        end

        function updateButtonStates(app) % Unchanged from previous working version
            state = app.isConnected;
            app.ConnectM2KButton.Enable = ~state;
            app.CalibrateADCDACButton.Enable = state;
            app.SetPowerSupplyButton.Enable = state;
            app.DisconnectM2KButton.Enable = state;
            % Specific calibration buttons are handled by updateCalibrationUI
            app.ApplyDirectFactorButton.Enable = state;
            app.TareButton.Enable = state;
            app.MeasureWeightButton.Enable = state;
        end

        function updateStatusLabels(app) % Unchanged
            if app.isScaleCalibrated
                app.CalibrationStatusLabel.Text = ['Calibration: Calibrated (', num2str(app.gramsPerVolt, '%.2e'), ' g/V)'];
                app.CalibrationStatusLabel.FontColor = [0 0.5 0];
            else
                app.CalibrationStatusLabel.Text = 'Calibration: Not Calibrated'; app.CalibrationStatusLabel.FontColor = [0.8 0 0];
            end
            if app.isTared
                app.TareStatusLabel.Text = ['Tare: Tared (at ', num2str(app.tareVoltage, '%.4f'), ' V)'];
                app.TareStatusLabel.FontColor = [0 0.5 0];
            else
                app.TareStatusLabel.Text = 'Tare: Not Tared'; app.TareStatusLabel.FontColor = [0.8 0 0];
            end
        end
        
        function updateOutputDisplays(app) % Unchanged
            app.AverageVoltageDisplayLabel.Text = ['Avg. Voltage: ', num2str(app.lastAverageVoltage, '%.4f'), ' V'];
            if app.isScaleCalibrated
                app.currentWeightGrams = (app.lastAverageVoltage - app.tareVoltage) * app.gramsPerVolt;
                app.WeightDisplayLabel.Text = ['Weight: ', num2str(app.currentWeightGrams, '%.2f'), ' g'];
                if app.avgJellyBeanWeightGrams > 0
                    app.currentJellyBeanCount = round(app.currentWeightGrams / app.avgJellyBeanWeightGrams);
                    app.currentJellyBeanCount(app.currentJellyBeanCount < 0) = 0;
                    app.JellyBeanCountDisplayLabel.Text = ['Jelly Beans: ~', num2str(app.currentJellyBeanCount)];
                else
                    app.JellyBeanCountDisplayLabel.Text = 'Jelly Beans: Enter avg. bean wt.';
                end
            else
                app.WeightDisplayLabel.Text = 'Weight: --- g (Not Calibrated)';
                app.JellyBeanCountDisplayLabel.Text = 'Jelly Beans: --- (Not Calibrated)';
            end
        end

        function cleanupM2K(app) % Unchanged from previous working version
            if isvalid(app) && ~isempty(app.m2kDevice) && ~clibIsNull(app.m2kDevice)
                try
                    if isprop(app, 'powerSupply') && ~isempty(app.powerSupply) && isvalid(app.powerSupply)
                         app.powerSupply.enableChannel(0, false); end
                    if isprop(app, 'analogInput') && ~isempty(app.analogInput) && isvalid(app.analogInput)
                        app.analogInput.enableChannel(0, false); end
                    clib.libm2k.libm2k.context.contextCloseAll();
                catch ME_cleanup
                    dispMsg = {['Warning: Error during M2K cleanup: ', ME_cleanup.message]};
                    if isvalid(app) && isprop(app,'StatusText') && isvalid(app.StatusText)
                         app.StatusText.Value = [app.StatusText.Value; dispMsg]; else, disp(dispMsg{1}); end
                end
            end
            if isvalid(app)
                app.m2kDevice = []; app.analogInput = []; app.powerSupply = []; app.isConnected = false;
                if isprop(app, 'InstantVoltageLabel') && isvalid(app.InstantVoltageLabel)
                    app.InstantVoltageLabel.Text = 'Inst. Voltage: -- V'; end
            end
        end

        function avgJellyBeanWeightChanged(app, src, event) % Unchanged from previous working version
            if isvalid(app) && isprop(app, 'AvgJellyBeanWeightGramsEditField') && isvalid(app.AvgJellyBeanWeightGramsEditField)
                app.avgJellyBeanWeightGrams = app.AvgJellyBeanWeightGramsEditField.Value;
            end
            if ~app.initComponentsComplete, return; end 
            if app.avgJellyBeanWeightGrams <= 0 && isprop(app, 'StatusText') && isvalid(app.StatusText)
                app.StatusText.Value = [app.StatusText.Value; {'Warning: Avg. jelly bean weight must be positive.'}];
            end
            updateOutputDisplays(app);
        end
    end

    % App initialization and construction
    methods (Access = private)
        function createComponents(app)
            disp('createComponents starting...');
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [100 100 850 700]; % May need adjustment for new cal panel layout
            app.UIFigure.Name = 'M2K Weighing Scale GUI';
            app.UIFigure.CloseRequestFcn = createCallbackFcn(app, @UIFigureCloseRequest, true);

            % --- Connection & M2K Setup Panel ---
            app.ConnectionSetupPanel = uipanel(app.UIFigure, 'Title', 'M2K Connection & Power', 'Position', [20 600 400 90]);
            app.ConnectM2KButton = uibutton(app.ConnectionSetupPanel, 'push', 'Text', 'Connect M2K', 'Position', [10 50 100 23], 'ButtonPushedFcn', createCallbackFcn(app, @ConnectM2KButtonPushed, true));
            app.DisconnectM2KButton = uibutton(app.ConnectionSetupPanel, 'push', 'Text', 'Disconnect M2K', 'Position', [120 50 110 23], 'ButtonPushedFcn', createCallbackFcn(app, @DisconnectM2KButtonPushed, true));
            app.CalibrateADCDACButton = uibutton(app.ConnectionSetupPanel, 'push', 'Text', 'Calibrate ADC/DAC', 'Position', [240 50 140 23], 'ButtonPushedFcn', createCallbackFcn(app, @CalibrateADCDACButtonPushed, true));
            app.PowerSupplyVoltageEditFieldLabel = uilabel(app.ConnectionSetupPanel, 'Text', 'V+ (V):', 'Position', [10 15 45 22], 'HorizontalAlignment', 'right');
            app.PowerSupplyVoltageEditField = uieditfield(app.ConnectionSetupPanel, 'numeric', 'Limits', [-5 5], 'ValueDisplayFormat', '%.2f', 'Value', app.currentPowerSupplyVoltage, 'Position', [65 15 70 22]);
            app.SetPowerSupplyButton = uibutton(app.ConnectionSetupPanel, 'push', 'Text', 'Set V+', 'Position', [145 15 80 23], 'ButtonPushedFcn', createCallbackFcn(app, @SetPowerSupplyButtonPushed, true));
            
            % --- Scale Settings Panel ---
            app.ScaleSettingsPanel = uipanel(app.UIFigure, 'Title', 'Scale Measurement Settings', 'Position', [20 470 400 120]);
            app.SampleRateHzEditFieldLabel = uilabel(app.ScaleSettingsPanel, 'Text', 'Sample Rate (Hz):', 'Position', [10 80 100 22], 'HorizontalAlignment', 'right');
            app.SampleRateEditField = uieditfield(app.ScaleSettingsPanel, 'numeric', 'Limits', [1 Inf], 'ValueDisplayFormat', '%d', 'Value', app.currentSampleRate, 'Position', [120 80 100 22]);
            app.WeighingDurationEditFieldLabel = uilabel(app.ScaleSettingsPanel, 'Text', 'Weighing Avg. Time (s):', 'Position', [10 50 130 22], 'HorizontalAlignment', 'right');
            app.WeighingDurationEditField = uieditfield(app.ScaleSettingsPanel, 'numeric', 'Limits', [0.01 Inf], 'ValueDisplayFormat', '%.2f', 'Value', app.currentWeighingDuration, 'Position', [150 50 70 22]);
            app.AvgJellyBeanWeightGramsEditFieldLabel = uilabel(app.ScaleSettingsPanel, 'Text', 'Avg. Jelly Bean Wt. (g):', 'Position', [10 20 130 22], 'HorizontalAlignment', 'right');
            app.AvgJellyBeanWeightGramsEditField = uieditfield(app.ScaleSettingsPanel, 'numeric', 'Limits', [0.001 Inf], 'ValueDisplayFormat', '%.3f', 'Value', app.avgJellyBeanWeightGrams, 'Position', [150 20 70 22], 'ValueChangedFcn', createCallbackFcn(app, @avgJellyBeanWeightChanged, true));

            % --- MODIFIED Calibration Panel ---
            % Height increased to accommodate new elements for reference method
            app.CalibrationPanel = uipanel(app.UIFigure, 'Title', 'Scale Calibration', 'Position', [20 150 400 310]); % Increased height from 230 to 310

            % Reference Weight Method Section (within CalibrationPanel)
            uilabel(app.CalibrationPanel, 'Text', 'Reference Weight Method:', 'FontWeight', 'bold', 'Position', [10 275 380 22]);
            app.CalibrationMassGramsEditFieldLabel = uilabel(app.CalibrationPanel, 'Text', 'Ref. Mass (g):', 'Position', [10 250 85 22], 'HorizontalAlignment', 'right');
            app.CalibrationMassGramsEditField = uieditfield(app.CalibrationPanel, 'numeric', 'Limits', [0.001 Inf], 'Value', 100, 'Position', [105 250 70 22]);
            app.StartCalibrationProcessButton = uibutton(app.CalibrationPanel, 'push', 'Text', 'Start New Calibration', 'Position', [190 250 190 23], 'ButtonPushedFcn', createCallbackFcn(app, @StartCalibrationProcessButtonPushed, true));
            
            app.CalibrationStepInstructionLabel = uilabel(app.CalibrationPanel, 'Text', 'Instructions appear here.', 'Position', [10 220 380 22], 'HorizontalAlignment', 'center');
            
            app.RecordEmptyScaleButton = uibutton(app.CalibrationPanel, 'push', 'Text', '1. Record Empty Scale Voltage', 'Position', [10 190 380 23], 'ButtonPushedFcn', createCallbackFcn(app, @RecordEmptyScaleButtonPushed, true));
            app.RecordWeightWithMassButton = uibutton(app.CalibrationPanel, 'push', 'Text', '2. Record Voltage with Reference Mass', 'Position', [10 160 380 23], 'ButtonPushedFcn', createCallbackFcn(app, @RecordWeightWithMassButtonPushed, true));
            
            app.CalibrationStatusLabel = uilabel(app.CalibrationPanel, 'Text', 'Calibration: Not Calibrated', 'Position', [10 130 380 22], 'FontWeight', 'bold'); % Shows final status of Ref Wt Cal

            % Direct Factor Panel (Nested inside CalibrationPanel, below Ref Wt method elements)
            app.DirectFactorPanel = uipanel(app.CalibrationPanel, 'Title', 'Direct Factor Input (Alternative)', 'Position', [10 50 380 70]); % Reduced height, positioned lower
            app.ReferenceVoltageMvEditFieldLabel = uilabel(app.DirectFactorPanel, 'Text', 'If change of (mV):', 'Position', [5 35 110 22], 'HorizontalAlignment', 'right');
            app.ReferenceVoltageMvEditField = uieditfield(app.DirectFactorPanel, 'numeric', 'Value', 100, 'Position', [125 35 70 22]);
            app.EquivalentGramsEditFieldLabel = uilabel(app.DirectFactorPanel, 'Text', 'Equals (grams):', 'Position', [5 5 110 22], 'HorizontalAlignment', 'right');
            app.EquivalentGramsEditField = uieditfield(app.DirectFactorPanel, 'numeric', 'Limits', [0.001 Inf], 'Value', 50, 'Position', [125 5 70 22]);
            app.ApplyDirectFactorButton = uibutton(app.DirectFactorPanel, 'push', 'Text', 'Apply Direct Factor', 'Position', [210 20 150 23], 'ButtonPushedFcn', createCallbackFcn(app, @ApplyDirectFactorButtonPushed, true));
            
            app.CancelCalibrationButton = uibutton(app.CalibrationPanel, 'push', 'Text', 'Cancel Ref. Wt. Cal', 'Position', [10 15 180 23], 'ButtonPushedFcn', createCallbackFcn(app, @CancelCalibrationButtonPushed, true), 'BackgroundColor', [0.92 0.8 0.8]);


            % --- Operation Panel ---
            app.OperationPanel = uipanel(app.UIFigure, 'Title', 'Operation', 'Position', [450 470 380 220]);
            app.TareButton = uibutton(app.OperationPanel, 'push', 'Text', 'Tare Scale', 'Position', [30 170 150 30], 'FontSize', 14, 'FontWeight', 'bold', 'ButtonPushedFcn', createCallbackFcn(app, @TareButtonPushed, true));
            app.TareStatusLabel = uilabel(app.OperationPanel, 'Text', 'Tare: Not Tared', 'Position', [30 140 320 22], 'FontWeight', 'bold');
            app.MeasureWeightButton = uibutton(app.OperationPanel, 'push', 'Text', 'Measure Weight', 'Position', [30 80 320 40], 'FontSize', 14, 'FontWeight', 'bold', 'ButtonPushedFcn', createCallbackFcn(app, @MeasureWeightButtonPushed, true));
            app.InstantVoltageLabel = uilabel(app.OperationPanel, 'Text', 'Inst. Voltage: -- V', 'Position', [30 40 200 22]);

            % --- Output Display Panel ---
            app.OutputDisplayPanel = uipanel(app.UIFigure, 'Title', 'Live Output', 'Position', [450 160 380 300]);
            app.AverageVoltageDisplayLabel = uilabel(app.OutputDisplayPanel, 'Text', 'Avg. Voltage: -- V', 'Position', [20 250 340 22], 'FontSize', 14);
            app.WeightDisplayLabel = uilabel(app.OutputDisplayPanel, 'Text', 'Weight: -- g', 'Position', [20 210 340 25], 'FontSize', 18, 'FontWeight', 'bold');
            app.JellyBeanCountDisplayLabel = uilabel(app.OutputDisplayPanel, 'Text', 'Jelly Beans: --', 'Position', [20 170 340 25], 'FontSize', 18, 'FontWeight', 'bold');

            % --- Status Text Area ---
            app.StatusTextLabel = uilabel(app.UIFigure, 'Text', 'System Log:', 'Position', [20 115 400 22]); % Adjusted Y position due to taller Cal panel
            app.StatusText = uitextarea(app.UIFigure, 'Editable', 'off', 'Position', [20 20 400 90]); % Adjusted Y and Height
            
            app.UIFigure.Visible = 'on';
            disp('createComponents finished. UIFigure should be visible.');
        end
    end

    % App creation and deletion
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