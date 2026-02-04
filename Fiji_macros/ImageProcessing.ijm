// This macro is designed to automatically segment, subtract
// the background and measure standard parameters from 2D
// micrographs of the immunological synapse.
//
// A reference file will then automatically open along with
// a dialog box. Fill in the channel names in the correct order
// (according to the reference file). The macro will then analyse and save
// the images accordingly.
//
// Written by Audun Kvalvaag. Last modified
// 07.10.2022.
//
// -----------------------------
// Setup / initialization
// -----------------------------
run("Close All");                                // Close all open images
if (roiManager("count") > 0) {                   // If ROI Manager contains ROIs, clear them
	roiManager("deselect");
	roiManager("delete");
}

// User-facing input parameters (Fiji script parameters)
#@ File (label = "Input directory", style = "directory") dir
#@ File (label = "Output directory", style = "directory") dirOut
#@ String (label = "File suffix", value = "vsi") filetype
#@ String (label = "Mask channel", value ="BF") maskCh
#@ String(choices={"Yes","No"}, style="radioButtonHorizontal") Watershed
//#@ String(choices={"Yes","No"}, style="radioButtonHorizontal") blackBg  // unused (commented out)
#@ String(choices={"Yes","No"}, style="radioButtonHorizontal") fitCircle
#@ String(choices={"Yes","No"}, style="radioButtonHorizontal") normExt
#@ String(choices={"Yes","No"}, style="radioButtonHorizontal") zStack

// -----------------------------
// Parameters for thresholding & pre-processing
// -----------------------------
sBg = 10;        // rolling ball radius (background subtraction)
eC1 = 0.35;      // first contrast enhancement saturation value (for Enhance Contrast)
sigma = 20;      // Gaussian blur sigma
eC2 = 0.1;       // second contrast enhancement saturation value

// Ensure directory path ends with a separator
dir = dir+File.separator;
print("dir: ", dir);
print("maskCh: ", maskCh);

// Get subfolders in input directory
subfolders = getFileList(dir);
Array.print(subfolders);
nS = subfolders.length;
print(nS);

// For convenience: open the first subfolder to pick a reference file (used later to build dialog)
folder = dir+subfolders[0];
files = getFileList(folder);
Array.print(files);

// Locate the first file that endsWith the given suffix (filetype)
for (i = 0; i < files.length; i++) {
	if (endsWith(files[i], filetype)) {
		ch_file = folder + files[i];   // reference file used for dialog and threshold checking
	}
}

// Import the reference file using Bio-Formats (keeps metadata)
run("Bio-Formats Importer", "open=[ch_file]");
getDimensions(width, height, channels, slices, frames); // read dimensions
//makeRectangle(205, 202, 789, 789); // optional crop (left commented)

/* Build a dialog that asks the user to name each channel.
   This lets the macro later identify channels by user-provided names.
*/
nC = channels;
print(nC);
Channels = newArray(nC);

Dialog.create("Channels")
for (c=0; c < nC; c++) {
	Dialog.addString("Ch" + c, " ");     // a text field for each channel
}
Dialog.addChoice("Check threshold?", newArray("Yes", "No"), "Yes"); // allow manual threshold check
Dialog.show();

checkThreshold = Dialog.getChoice();
for (c=0; c < nC; c++) {
	Channels[c] = Dialog.getString();     // collect channel names input by user
}
Array.print(Channels);
close();

// -----------------------------
// Optional threshold check step
// -----------------------------
if (checkThreshold == "Yes") {
	// Re-open the reference file, split channels and let the user visually check thresholds.
	run("Bio-Formats Importer", "open=[ch_file]");
	run("Split Channels");                      // split multi-channel image into separate windows
	ImgArray = getList("image.titles");         // get list of split-channel window titles
	for (s = 0; s < nC; s++) {
		selectWindow(ImgArray[s]);
		rename(Channels[s]);                    // rename windows to the names user gave
  	}

	// Choose the mask channel and do a preview pre-processing depending on channel type
	selectWindow(maskCh);
	if (maskCh == "SIRC") {
		// If SIRC is mask channel, use specific heavy preprocessing
		run("Subtract Background...", "rolling=300 light");
		run("Enhance Contrast...", "saturated=0.1 normalize");
		run("Add...", "value=10000");
		run("Median...", "radius=10");
	} else {
		// Default lighter pipeline for other mask channels
		run("Enhance Contrast...", "saturated=" + eC1);
		run("Despeckle");
		run("Subtract Background...", "rolling=" + sBg);
		run("Gaussian Blur...", "sigma=" + sigma);
		run("Enhance Contrast...", "saturated=" + eC2);
	}

	// Open the threshold dialog so user can set/inspect threshold visually
	run("Threshold...");
	waitForUser("Press OK when threshold check is complete");   // user inspects / adjusts threshold
	getThreshold(lower, upper);   // store chosen lower/upper threshold values
} else {
	// Automatic threshold: set a default dark auto threshold and get its numeric bounds
	setAutoThreshold("Default dark");
	getThreshold(lower, upper);
	print("threshold_low: ", lower);
	print("threshold_high: ", upper);
}

// Clean up opened windows before batch processing
run("Close All");

// Turn off batch mode for initial processing
sortCh(dir);
setBatchMode(false);

// -----------------------------
// Main function that iterates through subfolders and processes each file
// -----------------------------
function sortCh(dir) {
	for (sf=0; sf < subfolders.length; sf++) {
		subfolder = dir+subfolders[sf];
		print("subfolder: ");
		print(subfolder);

		datafiles = getFileList(subfolder);   // list files in current subfolder
		print("Datafiles:");
		Array.print(datafiles);

		// Prepare output folder for this subfolder
		resFolder = dirOut + File.separator + "res_" + subfolders[sf];
		print("resFolder:", resFolder);
  		File.makeDirectory(resFolder);        // create results folder
		Name = File.getName(resFolder);       // basename for result files
		print(Name);

		// Loop over all files in the data subfolder
		for (i = 0; i < datafiles.length; i++) {
			if (endsWith(datafiles[i], filetype)) {   // process only matching filetype
				file = subfolder + datafiles[i];
				run("Bio-Formats Importer", "open=[file]");  // open file
				//makeRectangle(205, 202, 789, 789); // optional cropping
				//run("Crop");
				Img = resFolder + File.separator + "Process_" + datafiles[i];  // create per-file results dir
  				print(Img);
				File.makeDirectory(Img);

				// Split channels and rename windows according to user-provided names
				run("Split Channels");
				ImgArray = getList("image.titles");
				for (s = 0; s < nC; s++) {
					selectWindow(ImgArray[s]);
					rename(Channels[s]);
  				}

				// Debug: print channel/window list
				ImgArray2 = getList("image.titles");
				Array.print(ImgArray2);

				// n = nImages;  // note: nImages is a built-in variable set by ImageJ; used later for iterating slices etc.
				n = nImages;
				selectWindow(maskCh);

				// Duplicate the mask channel window (work on a duplicate so original channel stays intact)
				run("Duplicate...", " ");

				// Pre-processing pipeline for mask channel (stack-aware where possible)
				if (maskCh == "SIRC") {
					// Heavier pipeline if mask channel is SIRC (includes normalize and median)
					run("Subtract Background...", "rolling=300 light stack");
					run("Enhance Contrast...", "saturated=0.1 normalize process_all");
					run("Add...", "value=10000 stack");
					run("Median...", "radius=10 stack");
				} else {
					// Default preprocessing (contrast, despeckle, rolling ball, blur, contrast)
					run("Enhance Contrast...", "saturated=" + eC1);
					run("Despeckle");
					run("Subtract Background...", "rolling=" + sBg);
					run("Gaussian Blur...", "sigma=" + sigma);
					run("Enhance Contrast...", "saturated=" + eC2);
				}

				// Apply threshold determined earlier and convert to binary mask
				setThreshold(lower, upper);
				run("Convert to Mask");
				run("Close-");   // close the temporary duplicate (the mask window remains in memory/ROI manager)

				// Optional morphological operations before particle analysis
				if (fitCircle == "Yes") {
					// Dilate twice to smooth/enlarge particles (useful before Fit Circle)
					run("Dilate");
					run("Dilate");
				}
				if (Watershed == "Yes") {
					// Run watershed to separate touching particles
					run("Watershed");
				}

				// Analyze Particles: detect ROIs (size and circularity filters)
				// Options: include, exclude (holes vs. particles), add (to ROI Manager)
				run("Analyze Particles...", "size=35-5000 circularity=0.20-1.00 include exclude add");

				// Save mask image for debugging/tracking
				saveAs("Tiff", Img + File.separator + "masks");
				close();   // close the mask image

				// Count ROIs found
				ROIn = roiManager("count");

				if (ROIn > 0) {
					// Save ROI manager contents as a zip for later reference
					roiManager("Save", Img + File.separator + "ROI.zip");

					// Loop over each image window (channels) to measure inside ROIs, etc.
					for (m = 0; m < n; m++) {
						ImgName = getTitle();                       // current image title
						print("ImgName: ", ImgName);
						i2 = replace(ImgName, ".tif", "_files");   // create an output folder name based on ImgName

						// Background subtraction on the image stack before measurement
						run("Subtract Background...", "rolling=10 stack");

						if (normExt == "Yes") {
							// Normalization option: measure background and divide image by its background before measuring
							run("Duplicate...", "title=Bg_" + ImgName + " ignore");
							roiManager("deselect");
							roiManager("combine");    // combine ROIs into one selection to measure background
							run("Make Inverse");      // invert selection to sample background around ROIs
							run("Measure");           // measure on the inverted selection
							Bg = getResult("Mean", nResults-1); // get last measurement (background mean)
							run("Select None");
							run("Divide...", "value=" + Bg);    // divide image by background mean (normalize)
							rename("@" + ImgName);
							roiManager("measure");    // measure each ROI on normalized image
							close();
						} else {
							// If normalization not requested, just measure ROIs directly
							roiManager("deselect");
							roiManager("measure");
						}

						// Create an output folder for per-ROI images for this ImgName
						outFolder = Img + File.separator + "fiji_" + i2;
						print("outFolder: ", outFolder);
						File.makeDirectory(outFolder);

						setBatchMode(true);   // speed up repeated operations by hiding window updates
						wait(50);

						// Iterate over each ROI in ROI Manager, duplicate the ROI area and save as TIFF
						for (o = 0; o < roiManager("count"); o++) {
							roiManager("select", o);    // select ROI
							if (fitCircle == "Yes") {
								run("Fit Circle");     // optionally fit a circle to the ROI
							}
							run("Duplicate...", "duplicate");  // duplicate the ROI area to a new image
							cell = getTitle();
							saveAs("Tiff", outFolder + File.separator + o + "_" + i2 + "-1");  // save per-ROI image

							// If zStack flag: step through slices, measure and save results
							if (zStack == "Yes") {
								for (sl = 0; sl < nSlices; sl++) {
									run("Next Slice [>]");
								}
								run("Measure");
								selectWindow("Results");
								saveAs("text", outFolder + File.separator + Name + "_" + i2 + "_zStack_" + o);
								run("Close");
							}
							close(); // close duplicated ROI image
						}

						// Save the full original image (tiff) into the per-file folder
						saveAs("Tiff", Img + File.separator + ImgName);
						close();
					}

					// After processing all images and ROIs, clear ROI manager and close everything
					roiManager("deselect");
					roiManager("delete");
					run("Close All");
				} else {
					// No ROIs found: just close all and continue
					run("Close All");
				}
			}
		}

		// Save results table named after the results folder
		selectWindow("Results");
		saveAs("text", resFolder + File.separator + Name);
		run("Close");
		run("Collect Garbage");   // free memory
	}
}
