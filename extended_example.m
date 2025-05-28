classdef JellyBeanScaleGUI_App < matlab.apps.AppBase

    % Properties that correspond to app components
    properties (Access = public)
        UIFigure                     matlab.ui.Figure
        ConnectionSetupPanel         matlab.ui.container.Panel
        ConnectM2KButton             matlab.ui.control.Button
        CalibrateADCDACButton        matlab.ui.control.Button % Renamed
        PowerSupplyVoltageEditFieldLabel matlab.ui.control.Label
        PowerSupplyVoltageEditField  matlab.ui.control.NumericEditField
        SetPowerSupplyButton         matlab.ui.control.Button
        DisconnectM2KButton          matlab.ui.control.Button

        ScaleSettingsPanel           matlab.ui.container.Panel
        WeighingDurationEditFieldLabel matlab.ui.control.Label
        WeighingDurationEditField    matlab.ui.control.NumericEditField % Replaces TotalDuration
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
        MeasureWeightButton          matlab.ui.control.Button % Replaces StartAcquisitionButton
        TareStatusLabel              matlab.ui.control.Label

        OutputDisplayPanel           matlab.ui.container.Panel
        InstantVoltageLabel          matlab.ui.control.Label % Kept for quick check
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
        currentPowerSupplyVoltage   % To store current power supply voltage
    end

    % Callbacks that handle component events
    methods (Access = private)

        % Code that executes after component creation
        function startupFcn(app)
            app.StatusText.Value = {'App Started. Please connect to M2K.'};
            app.AvgJellyBeanWeightGramsEditField.Value = app.avgJellyBeanWeightGrams;
            updateButtonStates(app);
            updateStatusLabels(app);
            updateOutputDisplays(app); % Initialize display text
            app.UIFigure.Name = "M2K Weighing Scale GUI";
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
                    % Reset scale status on new connection
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

        % Button pushed function: CalibrateADCDACButton (formerly CalibrateM2KButton)
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

            app.StatusText.Value = {'Calibration Started: Ensure scale is empty and press Tare.'};
            % For a more guided UI, you might disable other buttons and enable a "Confirm Tare for Calibration" button.
            % Here, we'll assume the user tares next, then places weight, then measures.
            % A more robust approach involves multiple steps/buttons.

            % Step 1: Tare (User should press Tare Button)
            app.StatusText.Value = {[' Ensure scale is empty, then press Tare button in Operation Panel.']};
            uiwait(msgbox('Ensure scale is empty, then press the "Tare" button. Once tared, place the calibration weight and press "Measure Weight" to capture calibration voltage. Then accept.', 'Calibration Step 1', 'modal'));
            
            % After taring and measuring the known weight:
            % This button would ideally trigger a sequence, or be part of a multi-step wizard.
            % For this simplified version, let's assume the user has:
            % 1. Tared the scale (app.tareVoltage is set).
            % 2. Placed the app.CalibrationMassGramsEditField.Value on the scale.
            % 3. Pressed "Measure Weight" so app.lastAverageVoltage now holds the voltage for the calib weight.
            
            % We need a way to confirm this voltage is for calibration.
            % Let's add a dialog for this.
            choice = questdlg(['Ensure you have: \n1. Tared the empty scale. \n2. Placed ', num2str(calibMass), 'g on the scale. \n3. Pressed "Measure Weight" to get the current reading. \n\nIs the current Average Voltage (', num2str(app.lastAverageVoltage, '%.4f'), ' V) correct for this mass?'], ...
                              'Confirm Calibration Measurement', ...
                              'Yes, use this voltage', 'No, cancel calibration', 'No, cancel calibration');
            if strcmp(choice, 'Yes, use this voltage')
                voltageWithMass = app.lastAverageVoltage;
                voltageDifference = voltageWithMass - app.tareVoltage; % Assumes tare was done
                
                if abs(voltageDifference) < 1e-6 % Avoid division by zero or tiny numbers
                    app.StatusText.Value = {'Error: Voltage difference for calibration is too small. Check connections or weight.'};
                    app.isScaleCalibrated = false;
                else
                    app.gramsPerVolt = calibMass / voltageDifference;
                    app.isScaleCalibrated = true;
                    app.StatusText.Value = {['Scale calibrated successfully. Factor: ', num2str(app.gramsPerVolt, '%.4f'), ' g/V']};
                end
            else
                app.StatusText.Value = {'Calibration cancelled by user.'};
                app.isScaleCalibrated = false;
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
            app.StatusText.Value = {['Scale calibrated with direct factor. Factor: ', num2str(app.gramsPerVolt, '%.4f'), ' g/V']};
            
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
                % Perform a short acquisition to get a stable tare voltage
                % This is similar to MeasureWeight but might be shorter/dedicated
                app.analogInput.enableChannel(0, true);
                app.analogInput.setSampleRate(app.currentSampleRate); % Use current sample rate
                
                tareDuration = 1.0; % Use a 1-second average for taring
                samplesForTare = round(tareDuration * app.currentSampleRate);
                if samplesForTare == 0
                    app.StatusText.Value = {'Error: Samples for tare is zero. Check sample rate.'};
                    return;
                end
                app.analogInput.setKernelBuffersCount(1);
                
                clibSamples = app.analogInput.getSamplesInterleaved_matlab(samplesForTare * 2); % Assuming channel 0 is 1+/1-
                ch1Samples = double(clibSamples(1:2:end));

                if isempty(ch1Samples)
                    app.StatusText.Value = {'Warning: No samples received for taring.'};
                    return;
                end

                app.tareVoltage = mean(ch1Samples);
                app.isTared = true;
                app.StatusText.Value = {['Scale Tared. Tare Voltage: ', num2str(app.tareVoltage, '%.4f'), ' V']};
                
            catch ME
                app.StatusText.Value = {['Error during taring: ', ME.message]};
                app.isTared = false;
            end
            updateStatusLabels(app);
            updateOutputDisplays(app); % Update weight to 0 g
        end

        % Button pushed function: MeasureWeightButton (formerly StartAcquisitionButton)
        function MeasureWeightButtonPushed(app, event)
            if ~app.isConnected || isempty(app.analogInput)
                app.StatusText.Value = {'Error: M2K not connected or analog input object not available.'};
                return;
            end
            if ~app.isScaleCalibrated && ~app.isTared
                % Allow measurement even if not calibrated/tared, but weight will be off/not meaningful
                 app.StatusText.Value = {'Warning: Scale not calibrated or tared. Voltage will be shown, weight may be inaccurate.'};
            elseif ~app.isScaleCalibrated
                 app.StatusText.Value = {'Warning: Scale not calibrated. Voltage will be shown, weight may be inaccurate.'};
            elseif ~app.isTared
                 app.StatusText.Value = {'Warning: Scale not tared. Weight will be relative to initial state or last tare for calibration.'};
            end
            app.StatusText.Value = {'Measuring weight...'};
            drawnow;

            try
                app.analogInput.enableChannel(0, true);
                instVoltage = app.analogInput.getVoltage(0); % Quick check
                app.InstantVoltageLabel.Text = ['Inst. Voltage: ', num2str(instVoltage, '%.4f'), ' V'];

                app.currentSampleRate = app.SampleRateEditField.Value;
                app.currentWeighingDuration = app.WeighingDurationEditField.Value;
                app.avgJellyBeanWeightGrams = app.AvgJellyBeanWeightGramsEditField.Value;


                if app.currentWeighingDuration <= 0 || app.currentSampleRate <=0
                    app.StatusText.Value = {'Error: Weighing duration and Sample Rate must be positive.'};
                    return;
                end

                app.analogInput.setSampleRate(app.currentSampleRate);
                samplesToAcquire = round(app.currentWeighingDuration * app.currentSampleRate);
                if samplesToAcquire == 0
                    app.StatusText.Value = {'Error: samplesToAcquire is zero. Increase duration or sample rate.'};
                    return;
                end

                app.analogInput.setKernelBuffersCount(1);
                
                app.StatusText.Value = {['Acquiring data for ', num2str(app.currentWeighingDuration), 's...']};
                drawnow;
                
                clibSamples = app.analogInput.getSamplesInterleaved_matlab(samplesToAcquire * 2);
                ch1Samples = double(clibSamples(1:2:end));

                if isempty(ch1Samples)
                     app.StatusText.Value = {'Warning: No samples received for measurement.'};
                     app.lastAverageVoltage = 0;
                else
                    app.lastAverageVoltage = mean(ch1Samples);
                end
                
                app.StatusText.Value = {'Measurement complete. Updating displays.'};
                updateOutputDisplays(app);

            catch ME
                app.StatusText.Value = {['Error during measurement: ', ME.message], ME.getReport('basic', 'hyperlinks','off')};
            end
        end

        % Button pushed function: DisconnectM2KButton
        function DisconnectM2KButtonPushed(app, event)
            app.StatusText.Value = {'Disconnecting M2K...'};
            drawnow;
            cleanupM2K(app);
            app.StatusText.Value = {'M2K Disconnected.'};
            app.isScaleCalibrated = false;
            app.isTared = false;
            app.tareVoltage = 0;
            app.gramsPerVolt = 0;
            updateButtonStates(app);
            updateStatusLabels(app);
            updateOutputDisplays(app);
        end

        % UIFigure close request function
        function UIFigureCloseRequest(app, event)
            app.StatusText.Value = {'Closing App and Disconnecting M2K...'};
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
            % Calibration dependent buttons
            % For simplicity, MeasureWeight is always enabled if connected.
            % User will get warnings if not calibrated/tared.
        end

        % Helper function to update status labels
        function updateStatusLabels(app)
            if app.isScaleCalibrated
                app.CalibrationStatusLabel.Text = ['Calibration Status: Calibrated (', num2str(app.gramsPerVolt, '%.2e'), ' g/V)'];
                app.CalibrationStatusLabel.FontColor = [0 0.5 0]; % Dark Green
            else
                app.CalibrationStatusLabel.Text = 'Calibration Status: Not Calibrated';
                app.CalibrationStatusLabel.FontColor = [0.8 0 0]; % Red
            end

            if app.isTared
                app.TareStatusLabel.Text = ['Tare Status: Tared (at ', num2str(app.tareVoltage, '%.4f'), ' V)'];
                app.TareStatusLabel.FontColor = [0 0.5 0]; % Dark Green
            else
                app.TareStatusLabel.Text = 'Tare Status: Not Tared';
                app.TareStatusLabel.FontColor = [0.8 0 0]; % Red
            end
        end
        
        % Helper function to update all output displays based on current state
        function updateOutputDisplays(app)
            app.AverageVoltageDisplayLabel.Text = ['Avg. Voltage: ', num2str(app.lastAverageVoltage, '%.4f'), ' V'];

            if app.isScaleCalibrated
                % Calculate weight relative to tare voltage if tared, otherwise relative to zero or initial tare.
                % If not explicitly tared for the current measurement session, tareVoltage might be from calibration.
                % For best results, tare before each set of measurements or if conditions change.
                voltageAboveTare = app.lastAverageVoltage - app.tareVoltage;
                app.currentWeightGrams = voltageAboveTare * app.gramsPerVolt;
                app.WeightDisplayLabel.Text = ['Weight: ', num2str(app.currentWeightGrams, '%.2f'), ' g'];

                if app.avgJellyBeanWeightGrams > 0
                    app.currentJellyBeanCount = round(app.currentWeightGrams / app.avgJellyBeanWeightGrams);
                    % Prevent negative counts if weight is negative due to drift/tare issues
                    if app.currentJellyBeanCount < 0 
                        app.currentJellyBeanCount = 0;
                    end
                    app.JellyBeanCountDisplayLabel.Text = ['Jelly Beans: ~', num2str(app.currentJellyBeanCount)];
                else
                    app.JellyBeanCountDisplayLabel.Text = 'Jelly Beans: Enter avg. weight';
                end
            else
                app.WeightDisplayLabel.Text = 'Weight: --- g (Not Calibrated)';
                app.JellyBeanCountDisplayLabel.Text = 'Jelly Beans: --- (Not Calibrated)';
            end
        end

        % Helper function for M2K cleanup
        function cleanupM2K(app)
            if ~isempty(app.m2kDevice) && ~clibIsNull(app.m2kDevice)
                try
                    if ~isempty(app.powerSupply)
                         app.powerSupply.enableChannel(0, false);
                    end
                    if ~isempty(app.analogInput)
                        app.analogInput.enableChannel(0, false);
                    end
                    clib.libm2k.libm2k.context.contextCloseAll();
                catch ME_cleanup
                    disp(['Warning: Error during M2K cleanup: ', ME_cleanup.message]);
                end
            end
            app.m2kDevice = [];
            app.analogInput = [];
            app.powerSupply = [];
            app.isConnected = false;

            % Check if the app object and the specific UI control are still valid
            if isvalid(app) && isprop(app, 'InstantVoltageLabel') && isvalid(app.InstantVoltageLabel)
                app.InstantVoltageLabel.Text = 'Inst. Voltage: -- V';
            end
            app.lastAverageVoltage = 0;
            % Do not reset calibration/tare status here, only on disconnect or app close.
            % updateOutputDisplays(app); % Refresh displays to show disconnected state potentially
        end
    end

    % App initialization and construction
    methods (Access = private)

        % Create UIFigure and components
        function createComponents(app)
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [100 100 850 700]; % Adjusted figure size for more components
            app.UIFigure.Name = 'M2K Weighing Scale GUI';
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
            
            app.CalibrateADCDACButton = uibutton(app.ConnectionSetupPanel, 'push'); % Renamed
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
            app.PowerSupplyVoltageEditField.Value = 2.5; % Default Power Supply
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
            app.SampleRateEditField.Value = app.currentSampleRate; % Use property default
            app.SampleRateEditField.Position = [120 80 100 22];

            app.WeighingDurationEditFieldLabel = uilabel(app.ScaleSettingsPanel);
            app.WeighingDurationEditFieldLabel.HorizontalAlignment = 'right';
            app.WeighingDurationEditFieldLabel.Text = 'Weighing Avg. Time (s)';
            app.WeighingDurationEditFieldLabel.Position = [10 50 130 22]; % Adjusted label width

            app.WeighingDurationEditField = uieditfield(app.ScaleSettingsPanel, 'numeric');
            app.WeighingDurationEditField.Limits = [0.01 Inf]; % Min 0.01s
            app.WeighingDurationEditField.ValueDisplayFormat = '%.2f';
            app.WeighingDurationEditField.Value = app.currentWeighingDuration; % Use property default
            app.WeighingDurationEditField.Position = [150 50 70 22]; % Adjusted position

            app.AvgJellyBeanWeightGramsEditFieldLabel = uilabel(app.ScaleSettingsPanel);
            app.AvgJellyBeanWeightGramsEditFieldLabel.HorizontalAlignment = 'right';
            app.AvgJellyBeanWeightGramsEditFieldLabel.Text = 'Avg. Jelly Bean Wt. (g)';
            app.AvgJellyBeanWeightGramsEditFieldLabel.Position = [10 20 130 22];

            app.AvgJellyBeanWeightGramsEditField = uieditfield(app.ScaleSettingsPanel, 'numeric');
            app.AvgJellyBeanWeightGramsEditField.Limits = [0.001 Inf];
            app.AvgJellyBeanWeightGramsEditField.ValueDisplayFormat = '%.3f';
            app.AvgJellyBeanWeightGramsEditField.Value = app.avgJellyBeanWeightGrams; % Use property default
            app.AvgJellyBeanWeightGramsEditField.Position = [150 20 70 22];
            app.AvgJellyBeanWeightGramsEditField.ValueChangedFcn = @(src, event) app.avgJellyBeanWeightChanged(src, event);


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
            app.CalibrationMassGramsEditField.Value = 100; % Default 100g
            app.CalibrationMassGramsEditField.Position = [105 190 70 22];

            app.StartReferenceCalibrationButton = uibutton(app.CalibrationPanel, 'push');
            app.StartReferenceCalibrationButton.ButtonPushedFcn = createCallbackFcn(app, @StartReferenceCalibrationButtonPushed, true);
            app.StartReferenceCalibrationButton.Text = 'Calibrate with Reference Mass';
            app.StartReferenceCalibrationButton.Position = [190 190 190 23];
            
            app.CalibrationStatusLabel = uilabel(app.CalibrationPanel);
            app.CalibrationStatusLabel.Text = 'Calibration Status: Not Calibrated';
            app.CalibrationStatusLabel.Position = [10 160 380 22];
            app.CalibrationStatusLabel.FontWeight = 'bold';

            % Direct Factor Calibration Sub-Panel
            app.DirectFactorPanel = uipanel(app.CalibrationPanel);
            app.DirectFactorPanel.Title = 'Direct Factor Calibration (Alternative)';
            app.DirectFactorPanel.Position = [10 50 380 100];

            app.ReferenceVoltageMvEditFieldLabel = uilabel(app.DirectFactorPanel);
            app.ReferenceVoltageMvEditFieldLabel.HorizontalAlignment = 'right';
            app.ReferenceVoltageMvEditFieldLabel.Text = 'If change of (mV):';
            app.ReferenceVoltageMvEditFieldLabel.Position = [5 60 110 22];

            app.ReferenceVoltageMvEditField = uieditfield(app.DirectFactorPanel, 'numeric');
            app.ReferenceVoltageMvEditField.Value = 100; % Default 100 mV
            app.ReferenceVoltageMvEditField.Position = [125 60 70 22];

            app.EquivalentGramsEditFieldLabel = uilabel(app.DirectFactorPanel);
            app.EquivalentGramsEditFieldLabel.HorizontalAlignment = 'right';
            app.EquivalentGramsEditFieldLabel.Text = 'Equals (grams):';
            app.EquivalentGramsEditFieldLabel.Position = [5 30 110 22];

            app.EquivalentGramsEditField = uieditfield(app.DirectFactorPanel, 'numeric');
            app.EquivalentGramsEditField.Limits = [0.001 Inf];
            app.EquivalentGramsEditField.Value = 50; % Default 50g for 100mV
            app.EquivalentGramsEditField.Position = [125 30 70 22];

            app.ApplyDirectFactorButton = uibutton(app.DirectFactorPanel, 'push');
            app.ApplyDirectFactorButton.ButtonPushedFcn = createCallbackFcn(app, @ApplyDirectFactorButtonPushed, true);
            app.ApplyDirectFactorButton.Text = 'Apply Direct Factor';
            app.ApplyDirectFactorButton.Position = [210 45 150 23];


            % --- Operation Panel (Tare & Measure) ---
            app.OperationPanel = uipanel(app.UIFigure);
            app.OperationPanel.Title = 'Operation';
            app.OperationPanel.Position = [450 470 380 220]; % Top right

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
            app.MeasureWeightButton.Position = [30 80 320 40]; % Prominent button

            app.InstantVoltageLabel = uilabel(app.OperationPanel); % Moved here from old MeasurementControl
            app.InstantVoltageLabel.Text = 'Inst. Voltage: -- V';
            app.InstantVoltageLabel.Position = [30 40 200 22];


            % --- Output Display Panel ---
            app.OutputDisplayPanel = uipanel(app.UIFigure);
            app.OutputDisplayPanel.Title = 'Live Output';
            app.OutputDisplayPanel.Position = [450 160 380 300]; % Below Operation

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
            % Reusing StatusText and its label, just repositioning its panel
            app.StatusTextLabel = uilabel(app.UIFigure); % No panel, directly on figure or new panel
            app.StatusTextLabel.Text = 'System Log:';
            app.StatusTextLabel.Position = [20 125 400 22];

            app.StatusText = uitextarea(app.UIFigure);
            app.StatusText.Editable = 'off';
            app.StatusText.Position = [20 20 400 100]; % Main status log area

            % Show the figure after all components are created
            app.UIFigure.Visible = 'on';
        end
        
        % Value changed function for AverageJellyBeanWeightGramsEditField
        function avgJellyBeanWeightChanged(app, src, event)
            app.avgJellyBeanWeightGrams = app.AvgJellyBeanWeightGramsEditField.Value;
            if app.avgJellyBeanWeightGrams <= 0
                app.StatusText.Value = {'Warning: Average jelly bean weight must be positive.'};
                % Optionally reset to a default or last valid value
                % app.AvgJellyBeanWeightGramsEditField.Value = 1.0;
                % app.avgJellyBeanWeightGrams = 1.0;
            end
            updateOutputDisplays(app); % Recalculate jelly bean count if weight is already measured
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
            cleanupM2K(app);
            delete(app.UIFigure)
        end
    end
end