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
        tareVoltage                  = 0;
        gramsPerVolt                 = 0;
        isScaleCalibrated            = false;
        isTared                      = false;
        avgJellyBeanWeightGrams      = 1.0;

        % Measurement parameters
        currentSampleRate            = 100000;
        currentWeighingDuration      = 5;

        % Output values
        lastAverageVoltage           = 0;
        currentWeightGrams           = 0;
        currentJellyBeanCount        = 0;

        isConnected = false
        currentPowerSupplyVoltage = 2.5 % Initialized to default of its edit field

        initComponentsComplete = false; % Flag to manage initialization sequence
    end

    % Callbacks that handle component events
    methods (Access = private)

        function startupFcn(app)
            disp('StartupFcn starting...'); % For debugging
            app.StatusText.Value = {'App Started. Please connect to M2K.'};
            
            updateButtonStates(app);
            updateStatusLabels(app);
            updateOutputDisplays(app); 

            app.initComponentsComplete = true; % Set flag at the end of startup
            disp('StartupFcn completed. initComponentsComplete=true.'); % For debugging
        end

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

        function CalibrateADCDACButtonPushed(app, event)
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

        function SetPowerSupplyButtonPushed(app, event)
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

        function StartReferenceCalibrationButtonPushed(app, event)
            if ~app.isConnected, app.StatusText.Value = {'Error: M2K not connected.'}; return; end
            calibMass = app.CalibrationMassGramsEditField.Value;
            if calibMass <= 0, app.StatusText.Value = {'Error: Calibration mass must be positive.'}; return; end

            app.StatusText.Value = {['Ensure scale is empty, press Tare. Then place ', num2str(calibMass), 'g, press Measure Weight, then confirm below.']};
            choice = questdlg(['Calibration Steps: \n1. Ensure scale is EMPTY and press "Tare Scale". \n2. Place known mass (', num2str(calibMass), 'g). \n3. Press "Measure Weight". \n\nIs current Avg. Voltage (', num2str(app.lastAverageVoltage, '%.4f'), 'V) for this mass?'], ...
                              'Confirm Calibration Measurement', 'Yes, use this voltage', 'No, cancel', 'No, cancel');
            if strcmp(choice, 'Yes, use this voltage')
                if ~app.isTared 
                     app.StatusText.Value = {'Error: Tare empty scale before confirming calibration.'};
                     uiwait(msgbox('Error: Tare empty scale first.', 'Tare Required', 'warn')); return;
                end
                voltageDifference = app.lastAverageVoltage - app.tareVoltage;
                if abs(voltageDifference) < 1e-6
                    app.StatusText.Value = {'Error: Voltage difference for calibration too small.'}; app.isScaleCalibrated = false;
                else
                    app.gramsPerVolt = calibMass / voltageDifference; app.isScaleCalibrated = true;
                    app.StatusText.Value = {['Scale calibrated. Factor: ', num2str(app.gramsPerVolt, '%.4f'), ' g/V']};
                end
            else
                app.StatusText.Value = {'Reference calibration cancelled.'}; app.isScaleCalibrated = false;
            end
            updateStatusLabels(app); updateButtonStates(app); updateOutputDisplays(app);
        end

        function ApplyDirectFactorButtonPushed(app, event)
            refMv = app.ReferenceVoltageMvEditField.Value; eqGrams = app.EquivalentGramsEditField.Value;
            if refMv == 0, app.StatusText.Value = {'Error: Ref. mV cannot be zero.'}; return; end
            if eqGrams <= 0, app.StatusText.Value = {'Error: Equivalent grams must be positive.'}; return; end
            
            app.gramsPerVolt = eqGrams / (refMv / 1000); app.isScaleCalibrated = true;
            app.isTared = false; app.tareVoltage = 0; % Reset tare after direct calibration
            app.StatusText.Value = {['Direct factor calibrated. Factor: ', num2str(app.gramsPerVolt, '%.4f'), ' g/V. Please Tare.']};
            updateStatusLabels(app); updateButtonStates(app); updateOutputDisplays(app);
        end
        
        function TareButtonPushed(app, event)
            if ~app.isConnected || isempty(app.analogInput), app.StatusText.Value = {'Error: M2K not connected.'}; return; end
            app.StatusText.Value = {'Taring... Acquiring baseline...'}; drawnow;
            try
                app.analogInput.enableChannel(0, true); app.analogInput.setSampleRate(app.currentSampleRate);
                tareDuration = 1.0; samplesForTare = round(tareDuration * app.currentSampleRate);
                if samplesForTare <= 0, app.StatusText.Value = {'Error: Samples for tare is zero.'}; return; end
                app.analogInput.setKernelBuffersCount(1);
                clibSamples = app.analogInput.getSamplesInterleaved_matlab(samplesForTare * 2);
                ch1Samples = double(clibSamples(1:2:end));
                if isempty(ch1Samples), app.StatusText.Value = {'Warning: No samples for taring.'}; return; end
                app.tareVoltage = mean(ch1Samples); app.isTared = true;
                app.lastAverageVoltage = app.tareVoltage; % Display tare voltage as current average
                app.StatusText.Value = {['Scale Tared. Tare Voltage: ', num2str(app.tareVoltage, '%.4f'), ' V']};
            catch ME
                app.StatusText.Value = {['Error during taring: ', ME.message]}; app.isTared = false;
            end
            updateStatusLabels(app); updateOutputDisplays(app);
        end

        function MeasureWeightButtonPushed(app, event)
            if ~app.isConnected || isempty(app.analogInput), app.StatusText.Value = {'Error: M2K not connected.'}; return; end
            statusMsg = {};
            if ~app.isScaleCalibrated, statusMsg{end+1} = 'Warning: Not calibrated.'; end
            if ~app.isTared, statusMsg{end+1} = 'Warning: Not tared.'; end
            app.StatusText.Value = [statusMsg, {'Measuring weight...'}]; drawnow;
            try
                app.analogInput.enableChannel(0, true);
                instVoltage = app.analogInput.getVoltage(0);
                if isvalid(app.InstantVoltageLabel), app.InstantVoltageLabel.Text = ['Inst. V: ', num2str(instVoltage, '%.4f')]; end
                app.currentSampleRate = app.SampleRateEditField.Value;
                app.currentWeighingDuration = app.WeighingDurationEditField.Value;
                if app.currentWeighingDuration <= 0 || app.currentSampleRate <=0, app.StatusText.Value = {'Error: Duration/Rate must be positive.'}; return; end
                app.analogInput.setSampleRate(app.currentSampleRate);
                samplesToAcquire = round(app.currentWeighingDuration * app.currentSampleRate);
                if samplesToAcquire <= 0, app.StatusText.Value = {'Error: samplesToAcquire is zero.'}; return; end
                app.analogInput.setKernelBuffersCount(1);
                app.StatusText.Value = [app.StatusText.Value; {['Acquiring for ', num2str(app.currentWeighingDuration), 's...']}]; drawnow;
                clibSamples = app.analogInput.getSamplesInterleaved_matlab(samplesToAcquire * 2);
                ch1Samples = double(clibSamples(1:2:end));
                if isempty(ch1Samples)
                     app.StatusText.Value = [app.StatusText.Value; {'Warning: No samples received.'}];
                     app.lastAverageVoltage = app.tareVoltage; % Default to tare if no samples
                else
                    app.lastAverageVoltage = mean(ch1Samples);
                end
                app.StatusText.Value = [app.StatusText.Value; {'Measurement complete.'}];
                updateOutputDisplays(app);
            catch ME
                app.StatusText.Value = {['Error during measurement: ', ME.message], ME.getReport('basic', 'hyperlinks','off')};
            end
        end

        function DisconnectM2KButtonPushed(app, event)
            app.StatusText.Value = {'Disconnecting M2K...'}; drawnow;
            cleanupM2K(app);
            app.StatusText.Value = {'M2K Disconnected.'};
            app.isScaleCalibrated = false; app.isTared = false; app.tareVoltage = 0; app.gramsPerVolt = 0;
            app.lastAverageVoltage = 0; app.currentWeightGrams = 0; app.currentJellyBeanCount = 0;
            updateButtonStates(app); updateStatusLabels(app); updateOutputDisplays(app);
        end

        function UIFigureCloseRequest(app, event)
            if isvalid(app) && isprop(app,'StatusText') && isvalid(app.StatusText)
                app.StatusText.Value = {'Closing App & Disconnecting M2K...'};
            end
            drawnow; cleanupM2K(app); delete(app);
        end

        function updateButtonStates(app)
            state = app.isConnected;
            app.ConnectM2KButton.Enable = ~state;
            app.CalibrateADCDACButton.Enable = state;
            app.SetPowerSupplyButton.Enable = state;
            app.DisconnectM2KButton.Enable = state;
            app.StartReferenceCalibrationButton.Enable = state;
            app.ApplyDirectFactorButton.Enable = state;
            app.TareButton.Enable = state;
            app.MeasureWeightButton.Enable = state;
        end

        function updateStatusLabels(app)
            if app.isScaleCalibrated
                app.CalibrationStatusLabel.Text = ['Calibration: Calibrated (', num2str(app.gramsPerVolt, '%.2e'), ' g/V)'];
                app.CalibrationStatusLabel.FontColor = [0 0.5 0]; % Dark Green
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

        function avgJellyBeanWeightChanged(app, src, event)
            if isvalid(app) && isprop(app, 'AvgJellyBeanWeightGramsEditField') && isvalid(app.AvgJellyBeanWeightGramsEditField)
                app.avgJellyBeanWeightGrams = app.AvgJellyBeanWeightGramsEditField.Value;
            end
            if ~app.initComponentsComplete, return; end % IMPORTANT CHECK
            if app.avgJellyBeanWeightGrams <= 0 && isprop(app, 'StatusText') && isvalid(app.StatusText)
                app.StatusText.Value = [app.StatusText.Value; {'Warning: Avg. jelly bean weight must be positive.'}];
            end
            updateOutputDisplays(app);
        end
    end

    % App initialization and construction
    methods (Access = private)
        function createComponents(app)
            disp('createComponents starting...'); % For debugging
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [100 100 850 700];
            app.UIFigure.Name = 'M2K Weighing Scale GUI';
            app.UIFigure.CloseRequestFcn = createCallbackFcn(app, @UIFigureCloseRequest, true);

            % --- Connection & M2K Setup Panel ---
            app.ConnectionSetupPanel = uipanel(app.UIFigure);
            app.ConnectionSetupPanel.Title = 'M2K Connection & Power';
            app.ConnectionSetupPanel.Position = [20 600 400 90];
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
            app.WeighingDurationEditFieldLabel = uilabel(app.ScaleSettingsPanel, 'Text', 'Weighing Avg. Time (s):', 'Position', [10 50 M2K_GUI_App130 22], 'HorizontalAlignment', 'right');
            app.WeighingDurationEditField = uieditfield(app.ScaleSettingsPanel, 'numeric', 'Limits', [0.01 Inf], 'ValueDisplayFormat', '%.2f', 'Value', app.currentWeighingDuration, 'Position', [150 50 70 22]);
            app.AvgJellyBeanWeightGramsEditFieldLabel = uilabel(app.ScaleSettingsPanel, 'Text', 'Avg. Jelly Bean Wt. (g):', 'Position', [10 20 130 22], 'HorizontalAlignment', 'right');
            app.AvgJellyBeanWeightGramsEditField = uieditfield(app.ScaleSettingsPanel, 'numeric', 'Limits', [0.001 Inf], 'ValueDisplayFormat', '%.3f', 'Value', app.avgJellyBeanWeightGrams, 'Position', [150 20 70 22], 'ValueChangedFcn', createCallbackFcn(app, @avgJellyBeanWeightChanged, true));

            % --- Calibration Panel ---
            app.CalibrationPanel = uipanel(app.UIFigure, 'Title', 'Scale Calibration', 'Position', [20 230 400 230]);
            app.CalibrationMassGramsEditFieldLabel = uilabel(app.CalibrationPanel, 'Text', 'Ref. Mass (g):', 'Position', [10 190 85 22], 'HorizontalAlignment', 'right');
            app.CalibrationMassGramsEditField = uieditfield(app.CalibrationPanel, 'numeric', 'Limits', [0.001 Inf], 'Value', 100, 'Position', [105 190 70 22]);
            app.StartReferenceCalibrationButton = uibutton(app.CalibrationPanel, 'push', 'Text', 'Calibrate with Reference Mass', 'Position', [190 190 190 23], 'ButtonPushedFcn', createCallbackFcn(app, @StartReferenceCalibrationButtonPushed, true));
            app.CalibrationStatusLabel = uilabel(app.CalibrationPanel, 'Text', 'Calibration: Not Calibrated', 'Position', [10 160 380 22], 'FontWeight', 'bold');
            app.DirectFactorPanel = uipanel(app.CalibrationPanel, 'Title', 'Direct Factor Calibration (Alternative)', 'Position', [10 50 380 100]);
            app.ReferenceVoltageMvEditFieldLabel = uilabel(app.DirectFactorPanel, 'Text', 'If change of (mV):', 'Position', [5 60 110 22], 'HorizontalAlignment', 'right');
            app.ReferenceVoltageMvEditField = uieditfield(app.DirectFactorPanel, 'numeric', 'Value', 100, 'Position', [125 60 70 22]);
            app.EquivalentGramsEditFieldLabel = uilabel(app.DirectFactorPanel, 'Text', 'Equals (grams):', 'Position', [5 30 110 22], 'HorizontalAlignment', 'right');
            app.EquivalentGramsEditField = uieditfield(app.DirectFactorPanel, 'numeric', 'Limits', [0.001 Inf], 'Value', 50, 'Position', [125 30 70 22]);
            app.ApplyDirectFactorButton = uibutton(app.DirectFactorPanel, 'push', 'Text', 'Apply Direct Factor', 'Position', [210 45 150 23], 'ButtonPushedFcn', createCallbackFcn(app, @ApplyDirectFactorButtonPushed, true));

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
            app.StatusTextLabel = uilabel(app.UIFigure, 'Text', 'System Log:', 'Position', [20 125 400 22]);
            app.StatusText = uitextarea(app.UIFigure, 'Editable', 'off', 'Position', [20 20 400 100]);
            
            app.UIFigure.Visible = 'on';
            disp('createComponents finished. UIFigure should be visible.'); % For debugging
        end
    end

    % App creation and deletion
    methods (Access = public)
        function app = M2K_GUI_App()
            createComponents(app)
            registerApp(app, app.UIFigure) % Should be called after UIFigure handle is created
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