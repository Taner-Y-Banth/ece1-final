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
        StartCalibrationProcessButton matlab.ui.control.Button
        CalibrationStepInstructionLabel matlab.ui.control.Label
        ConfirmTareStepButton         matlab.ui.control.Button   % New
        ConfirmMeasurementStepButton  matlab.ui.control.Button   % New
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
    end

    % Properties that correspond to app data
    properties (Access = private)
        m2kDevice
        analogInput
        powerSupply

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
        
        calibrationState          = 0;     % 0:idle, 1:await_user_tare_confirm, 2:await_user_measure_confirm
        calibrationTareVoltage    = 0;
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
            disp('StartupFcn completed. initComponentsComplete=true.');
        end

        function updateCalibrationUIState(app)
            isIdle = (app.calibrationState == 0);
            isStep1_AwaitUserTareConfirm = (app.calibrationState == 1);
            isStep2_AwaitUserMeasureConfirm = (app.calibrationState == 2);
            canProceed = app.isConnected;

            app.CalibrationMassGramsEditField.Enable = escritura((isIdle && canProceed), 'on', 'off');
            app.StartCalibrationProcessButton.Enable = escritura(canProceed, 'on', 'off');
            if isIdle
                app.StartCalibrationProcessButton.Text = 'Start New Calibration';
            else
                app.StartCalibrationProcessButton.Text = 'Restart Calibration Process';
            end
            
            app.ConfirmTareStepButton.Enable = escritura((isStep1_AwaitUserTareConfirm && canProceed), 'on', 'off');
            app.ConfirmTareStepButton.Visible = escritura(isStep1_AwaitUserTareConfirm, 'on', 'off');
            
            app.ConfirmMeasurementStepButton.Enable = escritura((isStep2_AwaitUserMeasureConfirm && canProceed), 'on', 'off');
            app.ConfirmMeasurementStepButton.Visible = escritura(isStep2_AwaitUserMeasureConfirm, 'on', 'off');

            app.CancelCalibrationButton.Enable = escritura((~isIdle && canProceed), 'on', 'off');
            app.CancelCalibrationButton.Visible = escritura(~isIdle, 'on', 'off');

            if ~canProceed && isIdle
                app.CalibrationStepInstructionLabel.Text = 'Connect M2K to enable calibration.';
            elseif isIdle
                app.CalibrationStepInstructionLabel.Text = 'Enter Ref. Mass & click "Start New Calibration".';
            elseif isStep1_AwaitUserTareConfirm
                app.CalibrationStepInstructionLabel.Text = '1. Ensure scale is EMPTY. Press main "Tare Scale" button, THEN click "Confirm Scale is Tared" above.';
            elseif isStep2_AwaitUserMeasureConfirm
                mass_val = app.CalibrationMassGramsEditField.Value;
                app.CalibrationStepInstructionLabel.Text = ['2. Place ', num2str(mass_val), 'g. Press main "Measure Weight" button, THEN click "Confirm Mass is Measured" above.'];
            end
        end

        function StartCalibrationProcessButtonPushed(app, event)
            if ~app.isConnected, app.StatusText.Value = {'Error: M2K not connected.'}; return; end
            calibMass = app.CalibrationMassGramsEditField.Value;
            if calibMass <= 0, app.StatusText.Value = {'Error: Reference mass must be positive.'}; return; end
            
            app.calibrationState = 1; 
            app.isScaleCalibrated = false; app.gramsPerVolt = 0;
            app.StatusText.Value = {['Calibration started. Ref Mass: ', num2str(calibMass), 'g. Follow instructions.']};
            updateCalibrationUIState(app);
            updateStatusLabels(app);
        end

        function ConfirmTareStepButtonPushed(app, event)
            if ~app.isConnected || app.calibrationState ~= 1, return; end

            if ~app.isTared 
                app.StatusText.Value = [app.StatusText.Value; {'Error: Scale not tared. Press main "Tare Scale" button first.'}];
                uiwait(msgbox('Please press the main "Tare Scale" button in the Operation Panel before confirming.', 'Tare Required', 'warn'));
                return;
            end

            app.calibrationTareVoltage = app.tareVoltage; 
            app.StatusText.Value = [app.StatusText.Value; {['Tare confirmed for cal. Tare V: ', num2str(app.calibrationTareVoltage, '%.4f')]}];
            app.calibrationState = 2; 
            updateCalibrationUIState(app);
        end

        function ConfirmMeasurementStepButtonPushed(app, event)
            if ~app.isConnected || app.calibrationState ~= 2, return; end
            
            voltageWithMass = app.lastAverageVoltage; 
            app.StatusText.Value = [app.StatusText.Value; {['Measurement confirmed for cal. Voltage with mass: ', num2str(voltageWithMass, '%.4f')]}];
            
            calibMass = app.CalibrationMassGramsEditField.Value;
            voltageDifference = voltageWithMass - app.calibrationTareVoltage;

            if abs(voltageDifference) < 1e-6
                app.StatusText.Value = [app.StatusText.Value; {'Error: Voltage difference too small. Ensure mass was measured correctly after taring.'}];
                app.isScaleCalibrated = false;
            else
                app.gramsPerVolt = calibMass / voltageDifference;
                app.isScaleCalibrated = true;
                app.StatusText.Value = [app.StatusText.Value; {['Scale calibrated! Factor: ', num2str(app.gramsPerVolt, '%.4f'), ' g/V.']}];
            end
            
            app.calibrationState = 0; 
            updateCalibrationUIState(app);
            updateStatusLabels(app); 
            updateOutputDisplays(app); 
        end

        function CancelCalibrationButtonPushed(app, event)
            app.calibrationState = 0;
            app.StatusText.Value = [app.StatusText.Value; {'Reference weight calibration cancelled.'}];
            updateCalibrationUIState(app);
        end
        
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
            updateButtonStates(app); updateStatusLabels(app); updateOutputDisplays(app); updateCalibrationUIState(app);
        end

        function DisconnectM2KButtonPushed(app, event)
            app.StatusText.Value = {'Disconnecting M2K...'}; drawnow;
            cleanupM2K(app);
            app.StatusText.Value = {'M2K Disconnected.'};
            app.isScaleCalibrated = false; app.isTared = false; app.tareVoltage = 0; app.gramsPerVolt = 0;
            app.lastAverageVoltage = 0; app.currentWeightGrams = 0; app.currentJellyBeanCount = 0;
            app.calibrationState = 0; 
            updateButtonStates(app); updateStatusLabels(app); updateOutputDisplays(app); updateCalibrationUIState(app);
        end

        function CalibrateADCDACButtonPushed(app, event)
            if ~app.isConnected || isempty(app.m2kDevice) || clibIsNull(app.m2kDevice), app.StatusText.Value = {'Error: M2K not connected.'}; return; end
            app.StatusText.Value = {'Calibrating M2K ADC/DAC...'}; drawnow;
            try
                app.m2kDevice.calibrateADC(); app.m2kDevice.calibrateDAC();
                app.StatusText.Value = {'M2K ADC/DAC Calibrated.'};
            catch ME
                app.StatusText.Value = {['Error M2K ADC/DAC calibration: ', ME.message]};
            end
        end

        function SetPowerSupplyButtonPushed(app, event)
            if ~app.isConnected || isempty(app.powerSupply), app.StatusText.Value = {'Error: M2K not connected or power supply unavailable.'}; return; end
            app.currentPowerSupplyVoltage = app.PowerSupplyVoltageEditField.Value;
            app.StatusText.Value = {['Setting V+ to ', num2str(app.currentPowerSupplyVoltage), 'V...']}; drawnow;
            try
                app.powerSupply.enableChannel(0, true); app.powerSupply.pushChannel(0, app.currentPowerSupplyVoltage);
                app.StatusText.Value = {['V+ set to ', num2str(app.currentPowerSupplyVoltage), 'V.']};
            catch ME
                app.StatusText.Value = {['Error setting power supply: ', ME.message]};
            end
        end
        
        function ApplyDirectFactorButtonPushed(app, event)
            refMv = app.ReferenceVoltageMvEditField.Value; eqGrams = app.EquivalentGramsEditField.Value;
            if refMv == 0, app.StatusText.Value = {'Error: Ref. mV cannot be zero.'}; return; end
            if eqGrams <= 0, app.StatusText.Value = {'Error: Equivalent grams must be positive.'}; return; end
            
            app.gramsPerVolt = eqGrams / (refMv / 1000); app.isScaleCalibrated = true;
            app.isTared = false; app.tareVoltage = 0; 
            app.calibrationState = 0; 
            app.StatusText.Value = {['Direct factor calibrated. Factor: ', num2str(app.gramsPerVolt, '%.4f'), ' g/V. Please Tare.']};
            updateStatusLabels(app); updateButtonStates(app); updateOutputDisplays(app); updateCalibrationUIState(app);
        end
        
        function TareButtonPushed(app, event)
            if ~app.isConnected || isempty(app.analogInput), app.StatusText.Value = {'Error: M2K not connected.'}; return; end
            
            if app.calibrationState == 1 % If in calibration step 1
                 app.StatusText.Value = [app.StatusText.Value; {'Main Tare pressed during calibration step 1.'}];
            else % If not in that specific calibration step, cancel any ongoing ref. cal.
                app.calibrationState = 0; 
            end
            updateCalibrationUIState(app); % Update cal UI based on new state
            app.StatusText.Value = [app.StatusText.Value; {'Taring (General)...'}]; drawnow;

            try
                app.analogInput.enableChannel(0, true);
                activeSampleRate = app.SampleRateEditField.Value; 
                app.analogInput.setSampleRate(activeSampleRate);
                
                tareDuration = 1.0; samplesForTare = round(tareDuration * activeSampleRate);
                if samplesForTare <= 0, app.StatusText.Value = [app.StatusText.Value; {'Error: Samples for tare zero.'}]; return; end
                app.analogInput.setKernelBuffersCount(1); 
                
                clibSamples = app.analogInput.getSamplesInterleaved_matlab(samplesForTare * 2);
                ch1Samples = double(clibSamples(1:2:end));

                if isempty(ch1Samples), app.StatusText.Value = [app.StatusText.Value; {'Warning: No samples for tare.'}]; app.isTared = false; return; end
                
                app.tareVoltage = mean(ch1Samples); app.isTared = true;
                app.lastAverageVoltage = app.tareVoltage;
                app.StatusText.Value = [app.StatusText.Value; {['Scale Tared. Tare V: ', num2str(app.tareVoltage, '%.4f')]}];
            catch ME
                app.StatusText.Value = [app.StatusText.Value; {['Error during tare: ', ME.message]}]; app.isTared = false;
            end
            updateStatusLabels(app); updateOutputDisplays(app);
        end

        function MeasureWeightButtonPushed(app, event)
            if ~app.isConnected || isempty(app.analogInput), app.StatusText.Value = {'Error: M2K not connected.'}; return; end
            statusMsg = {};
            if ~app.isScaleCalibrated, statusMsg{end+1} = 'Warning: Not calibrated.'; end
            if ~app.isTared, statusMsg{end+1} = 'Warning: Not tared.'; end
            
            if app.calibrationState == 2 % If in calibration step 2
                 statusMsg = [statusMsg, {'Main Measure Weight pressed during calibration step 2.'}];
            end
            app.StatusText.Value = [statusMsg, {'Measuring weight...'}]; drawnow;

            try
                app.analogInput.enableChannel(0, true); 
                instVoltage = app.analogInput.getVoltage(0); 
                if isvalid(app.InstantVoltageLabel), app.InstantVoltageLabel.Text = ['Inst. V: ', num2str(instVoltage, '%.4f')]; end

                app.currentSampleRate = app.SampleRateEditField.Value;
                app.currentWeighingDuration = app.WeighingDurationEditField.Value;
                
                app.analogInput.setSampleRate(app.currentSampleRate);
                samplesToAcquire = round(app.currentWeighingDuration * app.currentSampleRate);
                if samplesToAcquire <= 0, app.StatusText.Value = [app.StatusText.Value; {'Error: samplesToAcquire zero.'}]; return; end
                app.analogInput.setKernelBuffersCount(1); 

                clibSamples = app.analogInput.getSamplesInterleaved_matlab(samplesToAcquire * 2);
                ch1Samples = double(clibSamples(1:2:end));

                if isempty(ch1Samples)
                     app.StatusText.Value = [app.StatusText.Value; {'Warning: No samples received.'}];
                else
                    app.lastAverageVoltage = mean(ch1Samples);
                end
                app.StatusText.Value = [app.StatusText.Value; {'Measurement complete.'}];
                updateOutputDisplays(app);
            catch ME
                app.StatusText.Value = {['Error during measurement: ', ME.message], ME.getReport('basic', 'hyperlinks','off')};
            end
        end

        function UIFigureCloseRequest(app, event)
            if isvalid(app) && isprop(app,'StatusText') && isvalid(app.StatusText)
                app.StatusText.Value = {'Closing App & Disconnecting M2K...'}; end
            drawnow; cleanupM2K(app); delete(app);
        end

        function updateButtonStates(app)
            state = app.isConnected;
            app.ConnectM2KButton.Enable = escritura(~state, 'on', 'off');
            app.CalibrateADCDACButton.Enable = escritura(state, 'on', 'off');
            app.SetPowerSupplyButton.Enable = escritura(state, 'on', 'off');
            app.DisconnectM2KButton.Enable = escritura(state, 'on', 'off');
            app.ApplyDirectFactorButton.Enable = escritura(state, 'on', 'off');
            app.TareButton.Enable = escritura(state, 'on', 'off');
            app.MeasureWeightButton.Enable = escritura(state, 'on', 'off');
            updateCalibrationUIState(app); 
        end

        function updateStatusLabels(app)
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
        
        function updateOutputDisplays(app)
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

        function cleanupM2K(app)
            if isvalid(app) && ~isempty(app.m2kDevice) && ~clibIsNull(app.m2kDevice)
                try
                    if isprop(app, 'analogInput') && ~isempty(app.analogInput) && isobject(app.analogInput) && isvalid(app.analogInput)
                        app.analogInput.enableChannel(0, false); 
                    end
                    if isprop(app, 'powerSupply') && ~isempty(app.powerSupply) && isobject(app.powerSupply) && isvalid(app.powerSupply)
                         app.powerSupply.enableChannel(0, false); 
                    end
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

        function avgJellyBeanWeightChanged(app, src, event)
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
            app.UIFigure.Position = [100 100 850 700];
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

            % --- Calibration Panel (Layout for simplified flow) ---
            app.CalibrationPanel = uipanel(app.UIFigure, 'Title', 'Scale Calibration', 'Position', [20 150 400 310]); 
            uilabel(app.CalibrationPanel, 'Text', 'Reference Weight Method:', 'FontWeight', 'bold', 'Position', [10 275 380 22]);
            app.CalibrationMassGramsEditFieldLabel = uilabel(app.CalibrationPanel, 'Text', 'Ref. Mass (g):', 'Position', [10 250 85 22], 'HorizontalAlignment', 'right');
            app.CalibrationMassGramsEditField = uieditfield(app.CalibrationPanel, 'numeric', 'Limits', [0.001 Inf], 'Value', 100, 'Position', [105 250 70 22]);
            app.StartCalibrationProcessButton = uibutton(app.CalibrationPanel, 'push', 'Text', 'Start New Calibration', 'Position', [190 250 190 23], 'ButtonPushedFcn', createCallbackFcn(app, @StartCalibrationProcessButtonPushed, true));
            app.CalibrationStepInstructionLabel = uilabel(app.CalibrationPanel, 'Text', 'Instructions appear here.', 'Position', [10 220 380 22], 'HorizontalAlignment', 'center');
            app.ConfirmTareStepButton = uibutton(app.CalibrationPanel, 'push', 'Text', 'Confirm Scale is Tared', 'Position', [10 190 380 23], 'ButtonPushedFcn', createCallbackFcn(app, @ConfirmTareStepButtonPushed, true));
            app.ConfirmMeasurementStepButton = uibutton(app.CalibrationPanel, 'push', 'Text', 'Confirm Mass is Measured', 'Position', [10 160 380 23], 'ButtonPushedFcn', createCallbackFcn(app, @ConfirmMeasurementStepButtonPushed, true));
            app.CalibrationStatusLabel = uilabel(app.CalibrationPanel, 'Text', 'Calibration: Not Calibrated', 'Position', [10 130 380 22], 'FontWeight', 'bold');
            app.CancelCalibrationButton = uibutton(app.CalibrationPanel, 'push', 'Text', 'Cancel Ref. Wt. Cal', 'Position', [10 15 180 23], 'ButtonPushedFcn', createCallbackFcn(app, @CancelCalibrationButtonPushed, true), 'BackgroundColor', [0.92 0.8 0.8]);
            app.DirectFactorPanel = uipanel(app.CalibrationPanel, 'Title', 'Direct Factor Input (Alternative)', 'Position', [10 50 380 70]);
            app.ReferenceVoltageMvEditFieldLabel = uilabel(app.DirectFactorPanel, 'Text', 'If change of (mV):', 'Position', [5 35 110 22], 'HorizontalAlignment', 'right');
            app.ReferenceVoltageMvEditField = uieditfield(app.DirectFactorPanel, 'numeric', 'Value', 100, 'Position', [125 35 70 22]);
            app.EquivalentGramsEditFieldLabel = uilabel(app.DirectFactorPanel, 'Text', 'Equals (grams):', 'Position', [5 5 110 22], 'HorizontalAlignment', 'right');
            app.EquivalentGramsEditField = uieditfield(app.DirectFactorPanel, 'numeric', 'Limits', [0.001 Inf], 'Value', 50, 'Position', [125 5 70 22]);
            app.ApplyDirectFactorButton = uibutton(app.DirectFactorPanel, 'push', 'Text', 'Apply Direct Factor', 'Position', [210 20 150 23], 'ButtonPushedFcn', createCallbackFcn(app, @ApplyDirectFactorButtonPushed, true));
            
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
            app.StatusTextLabel = uilabel(app.UIFigure, 'Text', 'System Log:', 'Position', [20 115 400 22]);
            app.StatusText = uitextarea(app.UIFigure, 'Editable', 'off', 'Position', [20 20 400 90]);
            
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

% Helper function to handle 'on'/'off' for Enable/Visible properties
function val = escritura(condition, trueVal, falseVal)
    if condition
        val = trueVal;
    else
        val = falseVal;
    end
end