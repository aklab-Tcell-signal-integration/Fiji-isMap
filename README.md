The Fiji and MATLAB based isMap module is based on one main Fiji macro for the image processing and feature extraction named imageProcessing.ijm. This macro is supplemented by two supporting Fiji macros for radial averaging and colocalization analysis and two MATLAB script for data visualization. This section describes their use.

1.1 Data organization <br>

The imageProcessing.ijm macro requires the data organization illustrated below for automatic parsing: + Images from the same condition should be stored in the same directory. + The images should be stored as individual files with a file format supported by the BioFormats plugin in Fiji. + A list of supported formats can be found here. + Condition folders should be stored in an input directory that the user will select when the macro starts.

Input_Directory/
  Condition_A/
    Image_1.vsi
    Image_2.vsi
    ...
  Condition_B/
    ...
    
1.2 Image processing

1.2.1 How the macro works

For each multichannel microscopy file in your dataset, the macro: 1. Imports the file using Bio-Formats, then crops a fixed region of interest (ROI) to standardize the field of view. 2. Splits channels and renames them based on user input. 3. Performs segmentation on a selected “mask channel” using background subtraction + smoothing + thresholding. 4. For each channel image, performs background subtraction, optionally normalizes intensities to extracellular background, then measures the ROIs. + Choose the measurement parameters in Fiji via Analyze → Set Measurements + It is recommended to include: Area, Standard deviation, Min & max gray value, Shape descriptors, Integrated density, Mean gray value, Median, and Display label 5. Saves (i) segmentation products, (ii) ROI sets, (iii) per-ROI cropped images, and (iv) per-condition summary tables.

1.2.2 Running the imageProcessing.ijm macro

Open imageProcessing.ijm in Fiji by either dragging and dropping the macro file into the Fiji window, or selecting File → Open….

Run the macro. The user will be prompted for:

Input directory: the parent folder containing your dataset.
Output directory: where results will be written.
File suffix: file extension to analyze.
Mask channel: the channel used for segmentation.
Options:
Watershed (Yes/No): split touching objects in the binary mask.
Fit circle (Yes/No): forces each ROI to a fitted circle before exporting ROI crops. Necessary for radial averaging.
NormExt (Yes/No): divides intensities by the mean background outside the combined ROI mask (see “Normalization” below).
zStack (Yes/No): if enabled, the macro will iterate through slices and save an additional per-ROI “zStack” results file.
Name the channels.

The macro opens a representative file and asks you to enter channel names in the correct order. These names are used to rename split-channel windows and to name outputs.
The user will also be asked: “Check threshold?” (Yes/No)
Yes: the macro opens the mask channel and shows the Threshold tool so you can manually pick a threshold. When satisfied, you click OK to proceed; the chosen (lower, upper) threshold is then reused for the full batch.
No: the macro applies an automatic threshold (Default dark) and proceeds without user intervention.
Set the threshold (if “Check threshold = Yes”) on the mask channel.

Adjust the sliders in the until the desired objects are highlighted.
Automatic thresholding is conducted if “Check threshold = No”.
The results are saved in the output directory.

1.2.3 Normalization

If enabled (normExt = Yes), the macro normalizes to the background intensity. The macro estimates the background intensity by:

Inverting the mask selection to get “everything outside the ROIs”.
Measuring the mean intensity outside.
Dividing the image by that mean value (so values become relative to extracellular background).
Measuring ROI intensities on this normalized image.

1.2.4 Output structure

For each subfolder inside your Input directory, the macro creates a matching results folder:

Output_Directory/
  res_Condition_A/
    Process_Image_1.vsi
    Process_Image_2.vsi
    ...
  res_Condition_B/
    ...
    
Inside each "Process_FileName" folder you will typically find: + masks.tif + Binary mask image produced from the mask channel (after thresholding). + ROI.zip + ROI Manager export of all detected objects for that image. This can be reopened later via ROI Manager → More → Open… or dragged and dropped into Fiji. + Per-channel processed images (*.tif) + The macro saves each channel image as a TIFF after background subtraction (and after normalization if normExt=Yes). + Per-ROI cropped images are exported into a subfolder for each channel: + Each file corresponds to a single ROI from ROI Manager.

Process_Image_01/
  fiji_ChannelA/
    Cell_ChannelA_0.tif
    Cell_ChannelA_1.tif
    Cell_ChannelA_2.tif
    ...
Inside each "res_CondtionName" folder, the global results file is saved as a text file. This is the main summary table for the condition folder. The rows correspond to the individual ROI measurements and the columns correspond to the measured metrics.

1.2.5 Visualizing the results

The MATLABscript loadFijiData.m loads Fiji results tables saved as .txt from a condition folder, extracts per-object measurements for a chosen input channel name, and returns: + MFI (mean fluorescence intensity) + IntDen (integrated density) + Area + StdDev (standard deviation)

The script calls to additional helper functions that must reside in the same MATLAB path. These include: + recursiveDir.m + getDirFromPath.m + CategoricalScatterplot.m

1.3 Colocalization

Colocalization with the coloc2.ijm macro uses the Coloc2 plugin to perform ROI-based colocalization analysis between two channels. The macro uses the output folder from the imageProcessing.ijm macro as input. Coloc2 does intensity-based colocalization by comparing the pixel values in channel A and channel B within the same region. The Pearson's correlation coefficient (PCC) is a measure of how linearly related the two channels are across pixels: + R = 1: high intensity in channel A perfectly correlates with high intensity in channel B + R = 0: No linear relationship. + R = -1: Anti-correlation.

1.3.1 How the macro works

For every Process_* folder it finds, the macro: 1. Loads the ROI set (ROI*.zip) into the ROI Manager. 2. Opens Channel 1 and Channel 2 images (Channel1.tif and Channel2.tif). 3. Loops over each ROI and runs Coloc2. 4. Saves the Coloc 2 log output for each ROI as a separate text file.

Notes: + The macro only processes folders whose names start with Process. Maintain the same folder structure as the output from the imageProcessing.ijm. + It identifies the channel images by filenames that start with the channel names the user enters (Ch1 / Ch2) and ends with .tif. They should match the channel names used during image processing.

1.3.2 Running the macro

Open the coloc2.ijm macro in Fiji.
Run the macro.
Select the Input Directory (the folder containing your res_* folders).
In the Channels dialog, enter the names of the two channels to use for the colocalization measurement.
The macro will run automatically over all res_Condition* → Process_Image* folders.

1.3.3 Output

For each Process_* folder analyzed, the macro creates a subfolder named coloc2. Inside, the macro writes one text file per ROI:

coloc_<Channel1>_<Channel2>_<ROIindex>.txt

Each *.txt file is the saved “Log” window output from Coloc 2 for that ROI.

1.3.4 Visualizing the results

The results from the colocalization can be visualized using the loadColoc2Data.m MATLAB script. This script loads ROI-level Pearson colocalization values from the Fiji Coloc 2 output text files (the ones saved by your coloc2 Fiji macro), organizes them by well / experiment folder, and returns a matrix and boxplots.

The script calls to the same additional helper functions as loadFijiData.m (see section 2.2.5), in addition to sortByToken.m.

How to use loadColoc2Data.m:

Open the script in MATLAB.
Run the script.
Select the output folder that contains the res_Condtion* folders.
The user is prompted to Enter the File ID:.Enter the name of the channels as it appears in the coloc2 results files produced my the coloc2.ijm Fiji macro.
Press enter.

1.4 Radial averaging

The radAv.ijm macro creates radially averaged synapse images by rotating each cropped ROI image through 0–359° and averaging the rotated stack. It then pools all radial averages within each condition and generates a condition-level average.

1.4.1 How the macro works

For each cropped single-cell ROI image, the macro: 1. Opens the image. 2. Duplicates it 360 times and rotates each duplicate by n degrees (n = 0…359). 3. Converts the 360 rotated images into a stack and computes a Z-projection (Average Intensity). 4. Saves the result as a new image: *_radAv.tif. 5. After all cells are processed within a condition, it: + Opens all *_radAv.tif images for that condition. + Stacks them and saves: + Stack of all radial averages + Montage overview + Condition-level average (average intensity projection across all cells)

Tips: + Input images must be square. This is achieved by "FitCirle = Yes" during image processing. + Use the output folder from image processing and keep the same folder structure.

1.4.2 Running the macro

Open the radAv.ijm macro in Fiji.
Run the macro.
Choose: Scale images? (Yes/No)
No = stack images by copying to center (default)
Yes = stack images by scaling to the largest (useful if ROI crops differ in size)
Select the Input Directory (the folder containing your res_* folders)
Fill in the dialog fields:
Channel: channel prefix used in filenames (e.g., aCD3, Actin, K63)
Parental folder ID: default res
Condition folder ID: default Process

1.4.3 Output

For each individual ROI input file, the macro saves Cell_Channel*_radAv.tif in the corresponding fiji_Channel* folder. This file is the radially averaged image for that one cell/ROI.

Once all *_radAv.tif images are generated and re-opened for a condition, the macro creates: + Channel*_radStack.tif: A stack containing all *_radAv.tif images pooled for that condition. + Channel*_radMontage.tif: A montage overview of the stack + Channel*_radTotAv.tif_radTotAv.tif: The condition-level average radial image.

1.4.4 Radial intensity profiles

The intensity profiles of the individual ROI radial averages and the total average for the condition can be visualized in Fiji. 1. Open the desired radial average .tiff file. 2. Draw a line along the diameter of the radial average. + Select the straight line tool. + Optional: To reduce noise, increase the line width to average across several pixels. + Double-click the line tool. + Set Line width (e.g., 3–10 pixels). 3. Plot the intensity profile by running the drawDiagonal macro


