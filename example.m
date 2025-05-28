classdef M2K_GUI_App < matlab.apps.AppBase

    % Properties that correspond to app components
    properties (Access = public)
        UIFigure                     matlab.ui.Figure
        ConnectionSetupPanel         matlab.ui.container.Panel
        ConnectM2KButton             matlab.ui.control.Button
        CalibrateM2KButton           matlab.ui.control.Button
        PowerSupplyVoltageEditFieldLabel matlab.ui.control.Label
        PowerSupplyVoltageEditField  matlab.ui.control.NumericEditField
        SetPowerSupplyButton         matlab.ui.control.Button
        DisconnectM2KButton          matlab.ui.control.Button
        MeasurementControlPanel      matlab.ui.container.Panel
        SampleRateHzEditFieldLabel   matlab.ui.control.Label
        SampleRateEditField          matlab.ui.control.NumericEditField
        TotalDurationsEditFieldLabel matlab.ui.control.Label
        TotalDurationEditField       matlab.ui.control.NumericEditField
        IntervalDurationsEditFieldLabel matlab.ui.control.Label
        IntervalDurationEditField    matlab.ui.control.NumericEditField
        StartAcquisitionButton       matlab.ui.control.Button
        InstantVoltageLabel          matlab.ui.control.Label
        StatusOutputPanel            matlab.ui.container.Panel
        StatusTextLabel              matlab.ui.control.Label
        StatusText                   matlab.ui.control.TextArea
        MeanVoltageUIAxes            matlab.ui.control.UIAxes
        StdDevUIAxes                 matlab.ui.control.UIAxes
    end

    % Properties that correspond to app data
    properties (Access = private)
        m2kDevice                   % Handle for the M2K device context
        analogInput                 % Handle for analog input object
        powerSupply                 % Handle for power supply object

        meanVals                    % Array to store mean values
        stdVals                     % Array to store standard deviation values
        timeVec                     % Time vector for plotting

        currentSampleRate           % To store current sample rate
        currentTotalDuration        % To store current total duration
        currentIntervalDuration     % To store current interval duration
        currentPowerSupplyVoltage   % To store current power supply voltage

        isConnected = false         % Flag to track M2K connection status
    end

    % Callbacks that handle component events
    methods (Access = private)

        % Code that executes after component creation
        function startupFcn(app)
            app.StatusText.Value = {'App Started. Please connect to M2K.'};
            updateButtonStates(app); % Set initial button states
            app.UIFigure.Name = "M2K Data Acquisition GUI";
        end

        % Button pushed function: ConnectM2KButton
        function ConnectM2KButtonPushed(app, event)
            app.StatusText.Value = {'Connecting to M2K...'};
            drawnow; % Update UI

            try
                app.m2kDevice = clib.libm2k.libm2k.context.m2kOpen();
                pause(1); % Give some time for the device to open

                if clibIsNull(app.m2kDevice)
                    clib.libm2k.libm2k.context.contextCloseAll(); % Clean up if open failed
                    app.m2kDevice = []; % Ensure it's empty
                    app.StatusText.Value = {'Error: M2K object is null. Restart MATLAB or check device connection and libm2k search path.'};
                    app.isConnected = false;
                else
                    app.analogInput = app.m2kDevice.getAnalogIn();
                    app.powerSupply = app.m2kDevice.getPowerSupply();
                    app.StatusText.Value = {'M2K Connected Successfully.'};
                    app.isConnected = true;
                end
            catch ME
                app.StatusText.Value = {['Connection Error: ', ME.message], 'Ensure libm2k is set up correctly and device is plugged in.'};
                app.m2kDevice = []; % Ensure it's empty on error
                app.isConnected = false;
                % Attempt to close any potentially open contexts if an error occurred mid-open
                try
                    clib.libm2k.libm2k.context.contextCloseAll();
                catch
                    % Ignore errors during this cleanup attempt
                end
            end
            updateButtonStates(app);
        end

        % Button pushed function: CalibrateM2KButton
        function CalibrateM2KButtonPushed(app, event)
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
                app.StatusText.Value = {['Error during M2K calibration: ', ME.message]};
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
                app.powerSupply.enableChannel(0, true); % Channel 0 is V+
                app.powerSupply.pushChannel(0, app.currentPowerSupplyVoltage);
                app.StatusText.Value = {['Power supply V+ set to ', num2str(app.currentPowerSupplyVoltage), 'V.']};
            catch ME
                app.StatusText.Value = {['Error setting power supply: ', ME.message]};
            end
        end

        % Button pushed function: StartAcquisitionButton
        function StartAcquisitionButtonPushed(app, event)
            if ~app.isConnected || isempty(app.analogInput)
                app.StatusText.Value = {'Error: M2K not connected or analog input object not available.'};
                return;
            end
            app.StatusText.Value = {'Starting acquisition...'};
            drawnow;

            try
                % Enable analog input channel 0 (1+ and 1-)
                app.analogInput.enableChannel(0, true);

                % Display one instantaneous reading
                instVoltage = app.analogInput.getVoltage(0);
                app.InstantVoltageLabel.Text = ['Instantaneous Voltage: ', num2str(instVoltage, '%.4f'), ' V'];

                % Read parameters from GUI
                app.currentSampleRate = app.SampleRateEditField.Value;
                app.currentTotalDuration = app.TotalDurationEditField.Value;
                app.currentIntervalDuration = app.IntervalDurationEditField.Value;

                if app.currentIntervalDuration <= 0 || app.currentTotalDuration <= 0 || app.currentSampleRate <=0
                    app.StatusText.Value = {'Error: Durations and Sample Rate must be positive.'};
                    return;
                end
                if app.currentIntervalDuration > app.currentTotalDuration
                    app.StatusText.Value = {'Error: Interval duration cannot exceed total duration.'};
                    return;
                end


                app.analogInput.setSampleRate(app.currentSampleRate);

                samplesPerInterval = round(app.currentIntervalDuration * app.currentSampleRate);
                if samplesPerInterval == 0
                    app.StatusText.Value = {'Error: samplesPerInterval is zero. Increase interval duration or sample rate.'};
                    return;
                end
                numIntervals = floor(app.currentTotalDuration / app.currentIntervalDuration); % Use floor to ensure integer
                 if numIntervals == 0
                    app.StatusText.Value = {'Error: numIntervals is zero. Increase total duration or decrease interval duration.'};
                    return;
                end


                % Prepare for acquisition
                app.analogInput.setKernelBuffersCount(1); % Use 1 kernel buffer

                % Allocate arrays
                app.meanVals = zeros(1, numIntervals);
                app.stdVals = zeros(1, numIntervals);
                app.timeVec = (0:numIntervals - 1) * app.currentIntervalDuration;

                % Main acquisition loop
                for i = 1:numIntervals
                    % Update status for current interval
                    app.StatusText.Value = {['Acquiring interval ', num2str(i), '/', num2str(numIntervals)]};
                    drawnow; % Allow UI to update

                    % Get samples. For interleaved, buffer size is samplesPerInterval * numChannels
                    % Since we enabled only channel 0, libm2k might still expect space for 2 if it's 1+/1- pair.
                    % The getSamplesInterleaved_matlab expects total number of points (samples*channels)
                    % If channel 0 means (1+ AND 1-), it's effectively 2 channels from hardware perspective
                    % but getVoltage(0) gives one value.
                    % The example script uses samplesPerInterval * 2. Let's stick to that.
                    clibSamples = app.analogInput.getSamplesInterleaved_matlab(samplesPerInterval * 2);
                    clibSamplesArray = double(clibSamples);

                    % Assuming channel 0 (1+) is the first in the interleaved data
                    ch1Samples = clibSamplesArray(1:2:end); % Extract samples for channel 1+

                    if isempty(ch1Samples)
                         app.StatusText.Value = {['Warning: No samples received for interval ', num2str(i)]};
                         app.meanVals(i) = NaN;
                         app.stdVals(i) = NaN;
                         continue; % Skip to next interval
                    end

                    app.meanVals(i) = mean(ch1Samples);
                    app.stdVals(i) = std(ch1Samples);
                end
                disp(app.meanVals(1:i)); % Display mean for debugging
                app.StatusText.Value = {'Measurement complete. Plotting results...'};
                drawnow;

                plotResults(app);
                app.StatusText.Value = {'Measurement and plotting complete.'};

            catch ME
                app.StatusText.Value = {['Error during acquisition: ', ME.message], ME.getReport('basic', 'hyperlinks','off')};
            end
        end

        % Button pushed function: DisconnectM2KButton
        function DisconnectM2KButtonPushed(app, event)
            app.StatusText.Value = {'Disconnecting M2K...'};
            drawnow;
            cleanupM2K(app);
            app.StatusText.Value = {'M2K Disconnected.'};
            updateButtonStates(app);
        end

        % UIFigure close request function
        function UIFigureCloseRequest(app, event)
            app.StatusText.Value = {'Closing App and Disconnecting M2K...'};
            drawnow;
            cleanupM2K(app);
            delete(app); % Close the app
        end

        % Helper function to update button enable/disable states
        function updateButtonStates(app)
            if app.isConnected
                app.ConnectM2KButton.Enable = 'off';
                app.CalibrateM2KButton.Enable = 'on';
                app.SetPowerSupplyButton.Enable = 'on';
                app.StartAcquisitionButton.Enable = 'on';
                app.DisconnectM2KButton.Enable = 'on';
            else
                app.ConnectM2KButton.Enable = 'on';
                app.CalibrateM2KButton.Enable = 'off';
                app.SetPowerSupplyButton.Enable = 'off';
                app.StartAcquisitionButton.Enable = 'off';
                app.DisconnectM2KButton.Enable = 'off';
            end
        end

        % Helper function to plot results
        function plotResults(app)
            % Clear previous plots
            cla(app.MeanVoltageUIAxes);
            cla(app.StdDevUIAxes);

            % Plot mean values
            plot(app.MeanVoltageUIAxes, app.timeVec, app.meanVals, '-o', 'LineWidth', 1.5, 'MarkerFaceColor', 'b');
            title(app.MeanVoltageUIAxes, 'Mean Voltage Over Time');
            xlabel(app.MeanVoltageUIAxes, 'Time (s)');
            ylabel(app.MeanVoltageUIAxes, 'Mean Voltage (V)');
            grid(app.MeanVoltageUIAxes, 'on');
            app.MeanVoltageUIAxes.XLim = [min(app.timeVec), max(app.timeVec)];

            % Plot standard deviation values
            plot(app.StdDevUIAxes, app.timeVec, app.stdVals, '-o', 'LineWidth', 1.5, 'MarkerFaceColor', 'r');
            title(app.StdDevUIAxes, 'Standard Deviation Over Time');
            xlabel(app.StdDevUIAxes, 'Time (s)');
            ylabel(app.StdDevUIAxes, 'Voltage Std Dev (V)');
            grid(app.StdDevUIAxes, 'on');
            app.StdDevUIAxes.XLim = [min(app.timeVec), max(app.timeVec)];
        end

        % Helper function for M2K cleanup
        function cleanupM2K(app)
            if ~isempty(app.m2kDevice) && ~clibIsNull(app.m2kDevice)
                try
                    % Optionally disable power supply channels before closing
                    if ~isempty(app.powerSupply)
                         app.powerSupply.enableChannel(0, false); % V+
                         % app.powerSupply.enableChannel(1, false); % V- if used
                    end
                     % Optionally disable analog input channels
                    if ~isempty(app.analogInput)
                        app.analogInput.enableChannel(0, false);
                    end

                    clib.libm2k.libm2k.context.contextCloseAll(); % Closes all open M2K contexts
                catch ME_cleanup
                    disp(['Warning: Error during M2K cleanup: ', ME_cleanup.message]);
                end
            end
            app.m2kDevice = [];
            app.analogInput = [];
            app.powerSupply = [];
            app.isConnected = false;

            % Clear plots and labels
            cla(app.MeanVoltageUIAxes);
            title(app.MeanVoltageUIAxes, 'Mean Voltage Over Time');
            xlabel(app.MeanVoltageUIAxes, 'Time (s)');
            ylabel(app.MeanVoltageUIAxes, 'Mean Voltage (V)');

            cla(app.StdDevUIAxes);
            title(app.StdDevUIAxes, 'Standard Deviation Over Time');
            xlabel(app.StdDevUIAxes, 'Time (s)');
            ylabel(app.StdDevUIAxes, 'Voltage Std Dev (V)');

            app.InstantVoltageLabel.Text = 'Instantaneous Voltage: -- V';
        end
    end

    % App initialization and construction
    methods (Access = private)

        % Create UIFigure and components
        function createComponents(app)

            % Create UIFigure and hide until all components are created
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [100 100 900 650]; % Adjusted figure size
            app.UIFigure.Name = 'M2K Data Acquisition GUI';
            app.UIFigure.CloseRequestFcn = createCallbackFcn(app, @UIFigureCloseRequest, true);

            % Create ConnectionSetupPanel
            app.ConnectionSetupPanel = uipanel(app.UIFigure);
            app.ConnectionSetupPanel.Title = 'Connection & Setup';
            app.ConnectionSetupPanel.Position = [20 480 400 150]; % Adjusted panel size & position

            % Create ConnectM2KButton
            app.ConnectM2KButton = uibutton(app.ConnectionSetupPanel, 'push');
            app.ConnectM2KButton.ButtonPushedFcn = createCallbackFcn(app, @ConnectM2KButtonPushed, true);
            app.ConnectM2KButton.Text = 'Connect to M2K';
            app.ConnectM2KButton.Position = [20 100 150 23];

            % Create CalibrateM2KButton
            app.CalibrateM2KButton = uibutton(app.ConnectionSetupPanel, 'push');
            app.CalibrateM2KButton.ButtonPushedFcn = createCallbackFcn(app, @CalibrateM2KButtonPushed, true);
            app.CalibrateM2KButton.Text = 'Calibrate M2K ADC/DAC';
            app.CalibrateM2KButton.Position = [200 100 160 23];

            % Create PowerSupplyVoltageEditFieldLabel
            app.PowerSupplyVoltageEditFieldLabel = uilabel(app.ConnectionSetupPanel);
            app.PowerSupplyVoltageEditFieldLabel.HorizontalAlignment = 'right';
            app.PowerSupplyVoltageEditFieldLabel.Text = 'Target V+ (Volts)';
            app.PowerSupplyVoltageEditFieldLabel.Position = [20 60 100 22];

            % Create PowerSupplyVoltageEditField
            app.PowerSupplyVoltageEditField = uieditfield(app.ConnectionSetupPanel, 'numeric');
            app.PowerSupplyVoltageEditField.Limits = [-5 5];
            app.PowerSupplyVoltageEditField.ValueDisplayFormat = '%.2f';
            app.PowerSupplyVoltageEditField.Value = 1.7;
            app.PowerSupplyVoltageEditField.Position = [130 60 100 22];

            % Create SetPowerSupplyButton
            app.SetPowerSupplyButton = uibutton(app.ConnectionSetupPanel, 'push');
            app.SetPowerSupplyButton.ButtonPushedFcn = createCallbackFcn(app, @SetPowerSupplyButtonPushed, true);
            app.SetPowerSupplyButton.Text = 'Set Power Supply';
            app.SetPowerSupplyButton.Position = [240 60 120 23];
            
            % Create DisconnectM2KButton
            app.DisconnectM2KButton = uibutton(app.ConnectionSetupPanel, 'push');
            app.DisconnectM2KButton.ButtonPushedFcn = createCallbackFcn(app, @DisconnectM2KButtonPushed, true);
            app.DisconnectM2KButton.Text = 'Disconnect M2K';
            app.DisconnectM2KButton.Position = [20 20 150 23]; % Adjusted position

            % Create MeasurementControlPanel
            app.MeasurementControlPanel = uipanel(app.UIFigure);
            app.MeasurementControlPanel.Title = 'Measurement Control';
            app.MeasurementControlPanel.Position = [20 280 400 180]; % Adjusted panel size & position

            % Create SampleRateHzEditFieldLabel
            app.SampleRateHzEditFieldLabel = uilabel(app.MeasurementControlPanel);
            app.SampleRateHzEditFieldLabel.HorizontalAlignment = 'right';
            app.SampleRateHzEditFieldLabel.Text = 'Sample Rate (Hz)';
            app.SampleRateHzEditFieldLabel.Position = [20 130 100 22];

            % Create SampleRateEditField
            app.SampleRateEditField = uieditfield(app.MeasurementControlPanel, 'numeric');
            app.SampleRateEditField.Limits = [1 Inf];
            app.SampleRateEditField.ValueDisplayFormat = '%d';
            app.SampleRateEditField.Value = 100000;
            app.SampleRateEditField.Position = [130 130 100 22];

            % Create TotalDurationsEditFieldLabel
            app.TotalDurationsEditFieldLabel = uilabel(app.MeasurementControlPanel);
            app.TotalDurationsEditFieldLabel.HorizontalAlignment = 'right';
            app.TotalDurationsEditFieldLabel.Text = 'Total Duration (s)';
            app.TotalDurationsEditFieldLabel.Position = [20 90 100 22];

            % Create TotalDurationEditField
            app.TotalDurationEditField = uieditfield(app.MeasurementControlPanel, 'numeric');
            app.TotalDurationEditField.Limits = [0.001 Inf];
            app.TotalDurationEditField.ValueDisplayFormat = '%.2f';
            app.TotalDurationEditField.Value = 5;
            app.TotalDurationEditField.Position = [130 90 100 22];

            % Create IntervalDurationsEditFieldLabel
            app.IntervalDurationsEditFieldLabel = uilabel(app.MeasurementControlPanel);
            app.IntervalDurationsEditFieldLabel.HorizontalAlignment = 'right';
            app.IntervalDurationsEditFieldLabel.Text = 'Interval Duration (s)';
            app.IntervalDurationsEditFieldLabel.Position = [20 50 110 22];

            % Create IntervalDurationEditField
            app.IntervalDurationEditField = uieditfield(app.MeasurementControlPanel, 'numeric');
            app.IntervalDurationEditField.Limits = [0.001 Inf];
            app.IntervalDurationEditField.ValueDisplayFormat = '%.2f';
            app.IntervalDurationEditField.Value = 0.5;
            app.IntervalDurationEditField.Position = [140 50 90 22];

            % Create StartAcquisitionButton
            app.StartAcquisitionButton = uibutton(app.MeasurementControlPanel, 'push');
            app.StartAcquisitionButton.ButtonPushedFcn = createCallbackFcn(app, @StartAcquisitionButtonPushed, true);
            app.StartAcquisitionButton.Text = 'Start Acquisition';
            app.StartAcquisitionButton.Position = [250 90 120 23]; % Adjusted position

            % Create InstantVoltageLabel
            app.InstantVoltageLabel = uilabel(app.MeasurementControlPanel);
            app.InstantVoltageLabel.Text = 'Instantaneous Voltage: -- V';
            app.InstantVoltageLabel.Position = [20 10 350 22]; % Adjusted position

            % Create StatusOutputPanel
            app.StatusOutputPanel = uipanel(app.UIFigure);
            app.StatusOutputPanel.Title = 'Status & Output';
            app.StatusOutputPanel.Position = [20 20 400 240]; % Adjusted panel size & position

            % Create StatusTextLabel
            app.StatusTextLabel = uilabel(app.StatusOutputPanel);
            app.StatusTextLabel.Text = 'Status:';
            app.StatusTextLabel.Position = [10 200 50 22];

            % Create StatusText
            app.StatusText = uitextarea(app.StatusOutputPanel);
            app.StatusText.Editable = 'off';
            app.StatusText.Position = [10 20 380 180]; % Adjusted size

            % Create MeanVoltageUIAxes
            app.MeanVoltageUIAxes = uiaxes(app.UIFigure);
            title(app.MeanVoltageUIAxes, 'Mean Voltage Over Time')
            xlabel(app.MeanVoltageUIAxes, 'Time (s)')
            ylabel(app.MeanVoltageUIAxes, 'Mean Voltage (V)')
            app.MeanVoltageUIAxes.Position = [450 340 430 290]; % Adjusted position & size

            % Create StdDevUIAxes
            app.StdDevUIAxes = uiaxes(app.UIFigure);
            title(app.StdDevUIAxes, 'Standard Deviation Over Time')
            xlabel(app.StdDevUIAxes, 'Time (s)')
            ylabel(app.StdDevUIAxes, 'Voltage Std Dev (V)')
            app.StdDevUIAxes.Position = [450 20 430 290]; % Adjusted position & size

            % Show the figure after all components are created
            app.UIFigure.Visible = 'on';
        end
    end

    % App creation and deletion
    methods (Access = public)

        % Construct app
        function app = M2K_GUI_App()

            % Create UIFigure and components
            createComponents(app)

            % Register the app with App Designer
            registerApp(app, app.UIFigure)

            % Execute M2K_GUI_App startup function
            runStartupFcn(app, @startupFcn)

            if nargout == 0
                clear app
            end
        end

        % Code that executes before app deletion
        function delete(app)
            % Ensure M2K is cleaned up if app is deleted unexpectedly
            cleanupM2K(app);
            % Delete UIFigure when app is deleted
            delete(app.UIFigure)
        end
    end
end
