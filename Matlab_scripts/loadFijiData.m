function [MFI, IntDen, data] = loadFijiData(varargin)
% LOADFIJIDATA Aggregate and plot Fiji-exported per-cell measurement tables
%
%   [MFI, IntDen, data] = loadFijiData(...)
%
% Description
%   Scans a "condition" directory containing subfolders of per-cell exports
%   (TXT tables), extracts measurements (Mean fluorescence intensity,
%   Integrated density, Area, etc.), filters ROIs by user criteria and
%   returns aggregated matrices suitable for downstream statistics and
%   plotting.
%
% Inputs (name-value pairs)
%   'condDir'          - (char) top-level folder path. If omitted, GUI prompt opens.
%   'FileSelector'    - (char) regex used to pick subfolders (default: 'res').
%   'StrictSelector'   - (logical) require match at start (default: true).
%   'IgnoreEmptyFolders'- (logical) skip folders without matching data (default: false).
%   'Rescale'          - (logical) rescale outputs to [0 1] (default: true).
%   'removeOutliers'   - (logical) remove outliers prior to rescale (default: true).
%   'plotIntDen'       - (logical) plot integrated density (default: true).
%   'plotArea'         - (logical) plot area (default: true).
%   'plotStDev'        - (logical) plot standard deviation (default: false).
%   'plotMax'          - (logical) plot max intensity (default: false).
%   'minCirc'          - (numeric) minimum circularity threshold (default: 0.10).
%   'minArea'          - (numeric) minimum area threshold (default: 20).
%   'maxArea'          - (numeric) maximum area threshold (default: 200).
%   'FilePattern'      - (char) custom file glob for measurement tables (TXT prompt).
%   'DatasetLabel'     - (char) label to match in the 'Label' column (recommended).
%   'SaveFigures'      - (logical) save generated figures to condDir (default: true).
%   'Verbose'          - (logical) print progress messages (default: true).
%
% Outputs
%   MFI    - matrix (L x N) of Mean Fluorescence Intensities (NaN-padded).
%   IntDen - matrix (L x N) of Integrated Density values (NaN-padded).
%   data   - structure array with per-folder fields:
%            .Name, .MFI, .Area, .IntDen, .stDev, .Max, .Circ
%
% Example:
%   [MFI, IntDen, data] = loadFijiData('condDir','/data/exp1','FileSelector','res','DatasetLabel','GFP','FilePattern','*.csv');
%   or simply [MFI, IntDen, data] = loadFijiData;
%
% Author: Audun Kvalvaag
% Version: 1.0
% Date:    2026-02-02
% License: MIT-compatible
%
% Notes:
%  - Expects exported table columns named: Label, Area, Mean, IntDen, StdDev, Max, Circ_
% ---------------------------------------------------------------------

%% Parse inputs
p = inputParser;
p.FunctionName = mfilename;
p.CaseSensitive = false;
addParameter(p,'condDir',[], @(x) ischar(x) || isstring(x));
addParameter(p,'FileSelector','res', @ischar);
addParameter(p,'StrictSelector',true, @islogical);
addParameter(p,'IgnoreEmptyFolders',false, @islogical);
addParameter(p,'Rescale',false, @islogical);
addParameter(p,'removeOutliers',false, @islogical);
addParameter(p,'plotIntDen',true, @islogical);
addParameter(p,'plotArea',true, @islogical);
addParameter(p,'plotStDev',false, @islogical);
addParameter(p,'plotMax',false, @islogical);
addParameter(p,'minCirc',0.10, @isnumeric);
addParameter(p,'minArea',20, @isnumeric);
addParameter(p,'maxArea',200, @isnumeric);
addParameter(p,'FilePattern','', @ischar);
addParameter(p,'DatasetLabel','', @ischar);
addParameter(p,'SaveFigures',true, @islogical);
addParameter(p,'Verbose',true, @islogical);

parse(p,varargin{:});
opts = p.Results;

minCirc = opts.minCirc;
minArea = opts.minArea;
maxArea = opts.maxArea;

%% Obtain condition directory
condDir = opts.condDir;
if isempty(condDir)
    condDir = uigetdir(pwd, 'Select the condition folder:');
    if isequal(condDir,0)
        error('No condition directory selected. Aborting.');
    end
end
condDir = char(condDir);
if ~strcmp(condDir(end), filesep)
    condDir = [condDir filesep];
end
if opts.Verbose, fprintf('Root directory: %s\n', condDir); end

%% Discover candidate folders (3-level depth)
cellPath = recursiveDir(condDir,3);
if isempty(cellPath)
    error('No subfolders found under %s', condDir);
end

%% Dataset label and file pattern selection
datasetLabel = opts.DatasetLabel;
if isempty(datasetLabel)
    datasetLabel = input('Select input channel: ','s');
    if isempty(datasetLabel), datasetLabel = ''; end
end

filePattern = opts.FilePattern;
if isempty(filePattern)
    filePattern = '*.txt';
end

%% Filter candidate folders by FileSelector
try
    [cellDirs, ~] = cellfun(@(x) getDirFromPath(x), cellPath, 'UniformOutput', false); 
catch
    % fallback: extract final folder names
    [~, cellDirs] = cellfun(@fileparts, cellPath, 'UniformOutput', false);
end

idxMatches = regexpi(cellDirs, opts.FileSelector, 'once');
idxMatches(cellfun(@isempty, idxMatches)) = {NaN};
idxVec = vertcat(idxMatches{:});
if opts.StrictSelector
    idxVec(idxVec~=1) = NaN;
end
sel = ~isnan(idxVec);
cellPath = cellPath(sel);
cellDirs = cellDirs(sel);
if isempty(cellPath)
    error('No data found after applying FileSelector ''%s'' in %s.', opts.FileSelector, condDir);
end
nFolders = numel(cellPath);

%% Initialize containers
data = repmat(struct('Name',[],'MFI',[],'Area',[],'IntDen',[],'stDev',[],'Max',[],'Circ',[]), 1, nFolders);
nPerFolder = zeros(1,nFolders);

requiredCols = {'Label','Area','Mean','IntDen','StdDev','Max','Circ_'};

%% Read files and collect measurements
for k = 1:nFolders
    folder = cellPath{k};
    listing = dir(fullfile(folder, filePattern));
    if isempty(listing)
        if opts.IgnoreEmptyFolders
            if opts.Verbose, warning('Skipping empty folder: %s', folder); end
            continue;
        else
            error('No measurement files matching "%s" in "%s".', filePattern, folder);
        end
    end

    % Pick file which contains datasetLabel in name if possible
    names = {listing.name};
    chosen = 1;
    if ~isempty(datasetLabel)
        for n = 1:numel(names)
            if contains(names{n}, datasetLabel, 'IgnoreCase', true)
                chosen = n; break;
            end
        end
    end
    chosenName = names{chosen};
    fullFile = fullfile(folder, chosenName);
    if opts.Verbose, fprintf('Reading: %s\n', fullFile); end
    try
        tbl = readtable(fullFile);
    catch ME
        error('Failed to read %s: %s', fullFile, ME.message);
    end
    temp(k).file = tbl;
    data(k).Name = chosenName;
end

%% Extract and filter measurements per folder
for k = 1:nFolders
    tbl = temp(k).file;
    if isempty(tbl), continue; end
    % Check required columns
    miss = setdiff(requiredCols, tbl.Properties.VariableNames);
    if ~isempty(miss)
        error('Missing required columns in %s: %s', data(k).Name, strjoin(miss,','));
    end
    % Row selection
    if isempty(datasetLabel)
        idxLabel = true(height(tbl),1); % keep all if no label specified
    else
        idxLabel = contains(tbl.Label, datasetLabel, 'IgnoreCase', true);
    end
    idxAmax = tbl.Area < maxArea;
    idxAmin = tbl.Area > minArea;
    idxCirc = tbl.Circ_ > minCirc;
    idxKeep = idxLabel & idxAmax & idxAmin & idxCirc;

    nSel = sum(idxKeep);
    nPerFolder(k) = nSel;
    if nSel == 0
        data(k).MFI = []; data(k).Area = []; data(k).IntDen = [];
        data(k).stDev = []; data(k).Max = []; data(k).Circ = [];
        continue;
    end

    data(k).MFI   = tbl.Mean(idxKeep);
    data(k).Area  = tbl.Area(idxKeep);
    data(k).IntDen= tbl.IntDen(idxKeep);
    data(k).stDev = tbl.StdDev(idxKeep);
    data(k).Max   = tbl.Max(idxKeep);
    data(k).Circ  = tbl.Circ_(idxKeep);
end

%% Build output matrices (NaN-padded)
if all(nPerFolder==0)
    error('No ROIs matched the selection criteria across all folders.');
end
L = max(nPerFolder);
MFI    = NaN(L, nFolders);
IntDen = NaN(L, nFolders);
AreaM  = NaN(L, nFolders);
stDev  = NaN(L, nFolders);
MaxM   = NaN(L, nFolders);

labels = cell(1,nFolders);
for k = 1:nFolders
    [~, labels{k}, ~] = fileparts(data(k).Name);
    if ~isempty(data(k).MFI)
        n = numel(data(k).MFI);
        MFI(1:n,k) = data(k).MFI;
        IntDen(1:n,k) = data(k).IntDen;
        AreaM(1:n,k) = data(k).Area;
        stDev(1:n,k) = data(k).stDev;
        MaxM(1:n,k) = data(k).Max;
    end
end

% Replace zeros with NaN (defensive)
MFI(MFI==0) = NaN;
IntDen(IntDen==0) = NaN;
AreaM(AreaM==0) = NaN;

%% Optional outlier removal and rescaling
if opts.Rescale
    if opts.removeOutliers
        MFI = filloutliers(MFI, NaN, "percentiles", [10 90]);
        IntDen = filloutliers(IntDen, NaN, "percentiles", [10 90]);
    end
    % rescale ignoring NaNs
    MFI = rescaleNanSafe(MFI);
    IntDen = rescaleNanSafe(IntDen);
end

%% Plot results
if opts.Verbose, fprintf('Plotting results...\n'); end
categoricalPlot(MFI, labels, sprintf('MFI (%s)', datasetLabel));
if opts.SaveFigures
    try
    exportgraphics(gcf, fullfile(condDir, sprintf('MFI %s.png', datasetLabel)), 'Resolution',300);
    catch
    warning('Failed to save figure.');
    end
end

%% ----------------- Helper functions ----------------------------------
    function out = recursiveDir(root, depth)
        % Return a cell array of subfolders up to a given depth (simple)
        out = {};
        if depth <= 0, return; end
        d = dir(root);
        dirs = d([d.isdir] & ~startsWith({d.name},'.'));
        for ii = 1:numel(dirs)
            sub = fullfile(root, dirs(ii).name);
            out{end+1,1} = sub;
            out = [out; recursiveDir(sub, depth-1)]; 
        end
    end

    function y = rescaleNanSafe(x)
        % Rescale vector x to [0,1] while preserving NaNs
        y = x;
        if all(isnan(x)), return; end
        idx = ~isnan(x);
        y(idx) = rescale(x(idx));
    end

    function categoricalPlot(matrixData, labelsIn, figTitle)
        % Categorical scatter/box plot
        if isempty(matrixData) || all(all(isnan(matrixData))), return; end
        f = figure('Visible','on','Units','normalized','Position',[0.2 0.2 0.5 0.5]);
        ax = axes(f);
        hold(ax,'on');
        % Use boxplot + jittered scatter for clarity
        validCols = find(~all(isnan(matrixData),1));
        if isempty(validCols), return; end
        processed = matrixData(:,validCols);
        % Vectorize for boxplot
        vec = [];
        grp = [];
        for cc = 1:size(processed,2)
            col = processed(:,cc);
            vec = [vec; col(~isnan(col))];
            grp = [grp; repmat(cc, sum(~isnan(col)), 1)];
        end
        boxplot(ax, vec, grp, 'Labels', labelsIn(validCols), 'Symbol','');
        % Jittered scatter overlay
        for cc = 1:size(processed,2)
            col = processed(:,cc);
            xv = cc + (rand(sum(~isnan(col)),1)-0.5)*0.15;
            scatter(ax, xv, col(~isnan(col)), 12, 'filled', 'MarkerFaceAlpha', 0.6);
        end
        title(ax, figTitle, 'Interpreter','none');
        ax.FontSize = 12;
        ax.TickLabelInterpreter = 'none';
        xtickangle(ax,45);
        box(ax,'on');
        hold(ax,'off');
    end

end % function
