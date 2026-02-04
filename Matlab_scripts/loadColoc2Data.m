function [PCC, data] = loadColoc2Data(varargin)
% LOADCOLOC2DATA  Load Pearson correlation results exported by Fiji Coloc2
%
%   [PCC, data] = loadColoc2Data(...) scans a condition directory for
%   Coloc2 output text files (named like "coloc_<ID>..."), extracts Pearson's
%   R values ("Pearson's R value (no threshold)"), and returns:
%       PCC  - numeric matrix (observations x wells) with NaN padding
%       data - struct array with fields:
%               .Source (well path), .fPath (file paths examined),
%               .Ch (the channel/file ID used), .PCC (cell array of values)
%
% Usage examples:
%   [PCC, data] = loadColoc2Data('condDir','/data/exp1','Ch','GFP');
%   [PCC, data] = loadColoc2Data(); % interactive: prompts for condDir and Ch
%
% Name-value options (all optional):
%   'condDir'        - top-level condition folder (string). If omitted, a
%                      GUI prompt is shown.
%   'Ch'             - File ID string used in coloc file names (default: ask).
%   'FolderSelector' - regex to identify top-level folders/wells (default: 'res').
%   'SubfolderSelector'- regex to identify intermediate subfolders (default: 'Process').
%   'FileSelector'   - regex to identify folder containing coloc text files (default: 'coloc2').
%   'StrictSelector' - logical, require selector to match at folder start (default: true).
%   'IgnoreEmptyFolders' - logical, skip empty wells instead of erroring (default: false).
%   'FilePattern'    - file glob for coloc files inside file folders (default: 'coloc_*').
%   'SaveFigures'    - logical, save generated figures to condDir (default: false).
%   'Verbose'        - logical, print progress messages (default: true).
%
% Notes:
%  - Expects Coloc2 output text files containing a line with:
%       "Pearson's R value (no threshold)" followed by the numeric value.
%  - The function uses helper functions recursiveDir and getDirFromPath if present;
%    robust fallbacks are included.
%
% Author: Audun Kvalvaag
% Version: 1.0
% Date: 2026-02-02
% ---------------------------------------------------------------------

%% Parse inputs
ip = inputParser;
ip.FunctionName = mfilename;
ip.CaseSensitive = false;
ip.addParameter('condDir', [], @(x) ischar(x) || isstring(x));
ip.addParameter('Ch', '', @ischar);
ip.addParameter('FolderSelector', 'res', @ischar);
ip.addParameter('SubfolderSelector', 'Process', @ischar);
ip.addParameter('FileSelector', 'coloc2', @ischar);
ip.addParameter('StrictSelector', true, @islogical);
ip.addParameter('IgnoreEmptyFolders', false, @islogical);
ip.addParameter('FilePattern', 'coloc_*', @ischar);
ip.addParameter('SaveFigures', true, @islogical);
ip.addParameter('Verbose', true, @islogical);

ip.parse(varargin{:});
opts = ip.Results;

%% Get condition directory
condDir = opts.condDir;
if isempty(condDir)
    condDir = uigetdir(pwd, 'Select the condition folder:');
    if isequal(condDir,0)
        PCC = []; data = []; return;
    end
end
condDir = char(condDir);
if condDir(end) ~= filesep, condDir = [condDir filesep]; end
if opts.Verbose, fprintf('Root directory: %s\n', condDir); end

%% Ask for channel/file ID if not provided
Ch = strtrim(opts.Ch);
if isempty(Ch)
    Ch = input('Enter the File ID (string used in coloc filenames): ', 's');
    if isempty(Ch)
        error('File ID (Ch) is required to identify coloc files.');
    end
end

%% Discover folder hierarchy (try helpers, fallback otherwise)
wPath = recursiveDir(condDir, 1); % wells / first-level
sPath = recursiveDir(condDir, 2); % subfolders / second-level
fPath = recursiveDir(condDir, 3); % file-containing folders / third-level

% Extract folder names for pattern matching
try
    [cellDirs, cellPar] = cellfun(@(i) getDirFromPath(i), fPath, 'UniformOutput', false);
catch
    % fallback: use basename
    cellDirs = cellfun(@(p) char(fileparts(p)), fPath, 'UniformOutput', false);
    cellPar = cellDirs;
end

%% Apply selectors to choose file paths (fPath), subfolders (sPath) and wells (wPath)
% Identify which fPath entries correspond to FileSelector
idx = regexpi(cellDirs, opts.FileSelector, 'once');
idx(cellfun(@isempty, idx)) = {NaN};
idx = vertcat(idx{:});
% For wells and subfolders, extract and match names if available
% Match wells (wPath) and subfolders (sPath) by their dirnames
wNames = cellfun(@(x) getBaseNameSafe(x), wPath, 'UniformOutput', false);
sNames = cellfun(@(x) getBaseNameSafe(x), sPath, 'UniformOutput', false);

wIdx = regexpi(wNames, opts.FolderSelector, 'once');
wIdx(cellfun(@isempty, wIdx)) = {NaN};
wIdx = vertcat(wIdx{:});

sIdx = regexpi(sNames, opts.SubfolderSelector, 'once');
sIdx(cellfun(@isempty, sIdx)) = {NaN};
sIdx = vertcat(sIdx{:});

% If strict, require match at start
if opts.StrictSelector
    idx(idx~=1) = NaN;
    wIdx(wIdx~=1) = NaN;
    sIdx(sIdx~=1) = NaN;
end

% Convert to logical selections
fMask = ~isnan(idx);
wMask = ~isnan(wIdx);
sMask = ~isnan(sIdx);

fPath = fPath(fMask);
wPath = wPath(wMask);
sPath = sPath(sMask);

if isempty(fPath)
    error('No coloc file paths found under %s with the given selectors.', condDir);
end

%% Build data struct skeleton
nWells = numel(wPath);
data = repmat(struct('Source',[],'fPath',{{}},'Ch',Ch,'PCC',{{}}), 1, nWells);

% Associate fPath entries to wells where possible: naive grouping by parent folder
% If sPath is non-empty, group fPath by which sPath parent they belong to.
for w = 1:nWells
    data(w).Source = wPath{w};
    % find fPath entries that are children of this well (string containment)
    isChild = cellfun(@(p) startsWith(fullfile(p,filesep), fullfile(wPath{w},filesep)), fPath);
    data(w).fPath = fPath(isChild);
end

%% Parse coloc files per well / per file
PCCcell = cell(nWells,1);

for w = 1:nWells
    fpList = data(w).fPath;
    if isempty(fpList)
        if opts.IgnoreEmptyFolders
            if opts.Verbose, warning('No file paths for well %s (skipping).', data(w).Source); end
            continue;
        else
            error('No file paths found for well: %s', data(w).Source);
        end
    end

    pccValsAll = {}; % will collect numeric PCCs (per file-group)
    for f = 1:numel(fpList)
        % list files in folder
        listing = dir(fpList{f});
        listing = listing(~[listing.isdir]);
        names = {listing.name}';
        % select files with pattern and file ID Ch (case-insensitive)
        matched = names(~cellfun(@isempty, regexpi(names, [opts.FilePattern '.*' Ch], 'once')));
        for m = 1:numel(matched)
            fullFile = fullfile(fpList{f}, matched{m});
            try
                tbl = readtable(fullFile,'FileType','text','ReadVariableNames',false,'Delimiter','\t');
            catch
                % fallback: read as lines
                txt = readlines(fullFile);
                tbl = cellstr(txt);
            end
            % parse lines for "Pearson's R value (no threshold)"
            pccFound = [];
            if istable(tbl)
                for r = 1:height(tbl)
                    line = tbl{r,1};
                    if iscell(line), line = line{1}; end
                    if contains(line, 'Pearson''s R value (no threshold)', 'IgnoreCase', true)
                        % get numeric from the same row, second column if present
                        if size(tbl,2) >= 2
                            val = tbl{r,2};
                            if iscell(val), val = val{1}; end
                            pccFound(end+1) = str2double(val); 
                        else
                            % try to extract numeric substring from line
                            numStr = regexp(line, '([+\-]?\d*\.?\d+([eE][+\-]?\d+)?)','match');
                            if ~isempty(numStr)
                                pccFound(end+1) = str2double(numStr{end}); 
                            end
                        end
                    end
                end
            else
                % tbl is cellstr lines
                for r = 1:numel(tbl)
                    line = tbl{r};
                    if contains(line, 'Pearson''s R value (no threshold)', 'IgnoreCase', true)
                        ns = regexp(line, '([+\-]?\d*\.?\d+([eE][+\-]?\d+)?)','match');
                        if ~isempty(ns)
                            pccFound(end+1) = str2double(ns{end}); 
                        end
                    end
                end
            end
            if ~isempty(pccFound)
                pccValsAll{end+1} = pccFound; 
            end
        end
    end
    % flatten and store
    if ~isempty(pccValsAll)
        flattened = cell2mat(cellfun(@(c) c(:)', pccValsAll, 'UniformOutput', false));
        data(w).PCC = flattened(:);
        PCCcell{w} = data(w).PCC;
    else
        data(w).PCC = [];
        PCCcell{w} = [];
    end
end

%% Combine into matrix (pad shorter columns with NaN)
maxLen = max(cellfun(@numel, PCCcell));
if isempty(maxLen) || maxLen == 0
    PCC = [];
    warning('No PCC values were found in any well.');
else
    PCC = NaN(maxLen, nWells);
    for w = 1:nWells
        v = PCCcell{w};
        if ~isempty(v)
            PCC(1:numel(v), w) = v;
        end
    end
end

%% Plot if multiple wells
if nWells > 1 && ~isempty(PCC)
    PCC(PCC==0) = NaN;
    labels = cellfun(@(p) getBaseNameSafe(p), wPath, 'UniformOutput', false);
    figure;
    categoricalPlot(PCC, labels, sprintf('PCC %s', Ch));
    if opts.SaveFigures
        try
            exportgraphics(gcf, fullfile(condDir, sprintf('PCC_%s.png', Ch)), 'Resolution',300);
        catch
            warning('Failed to save figure.');
        end
    end
end

if opts.Verbose, fprintf('Done. Extracted PCC values for %d wells.\n', nWells); end

end % function


%% ---------------- Helper subfunctions --------------------------------
function out = recursiveDir(root, depth)
out = {};
if depth <= 0, return; end
d = dir(root);
dirs = d([d.isdir] & ~startsWith({d.name}, '.'));
for ii = 1:numel(dirs)
    sub = fullfile(root, dirs(ii).name);
    out{end+1,1} = sub; 
    out = [out; recursiveDir(sub, depth-1)]; 
end
end

function name = getBaseNameSafe(path)
% return final folder name (basename) safely
try
    [p, name] = fileparts(char(path));
    if isempty(name)
        % if path ends with filesep, try removing it
        p2 = char(path);
        if p2(end) == filesep, p2 = p2(1:end-1); end
        [~, name] = fileparts(p2);
    end
catch
    name = char(path);
end
end

function categoricalPlot(matrixData, labelsIn, figTitle)
% Simple categorical plot wrapper (boxplot + jitter)
if isempty(matrixData) || all(all(isnan(matrixData))), return; end
validCols = find(~all(isnan(matrixData),1));
if isempty(validCols), return; end
processed = matrixData(:,validCols);

vec = [];
grp = [];
for cc = 1:size(processed,2)
    col = processed(:,cc);
    vec = [vec; col(~isnan(col))];
    grp = [grp; repmat(cc, sum(~isnan(col)), 1)];
end
boxplot(vec, grp, 'Labels', labelsIn(validCols), 'Symbol','');
hold on;
for cc = 1:size(processed,2)
    col = processed(:,cc);
    xv = cc + (rand(sum(~isnan(col)),1)-0.5)*0.15;
    scatter(xv, col(~isnan(col)), 12, 'filled', 'MarkerFaceAlpha', 0.6);
end
title(figTitle, 'Interpreter', 'none');
ax = gca;
ax.FontSize = 12;
xtickangle(45);
hold off;
end
