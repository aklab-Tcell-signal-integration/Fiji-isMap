// ------------------------------------------------------------------
// PCC batch coloc script
// ------------------------------------------------------------------
// Purpose: Walk input directory, find processed "Process_*" folders,
// open ROI.zip files and matching channel TIFFs, then run the Coloc 2
// plugin per-ROI and save the resulting Log files into a `coloc2` folder.
//
// Notes:
// - The script expects a folder structure where each cell has a
//   "Process_*" folder containing ROI.zip and channel TIFFs named
//   starting with the channel names you enter in the dialog.
// - Uses roiManager(...) extensively: make sure ROI.zip contents are
//   compatible with current ROI Manager in ImageJ/Fiji.
// ------------------------------------------------------------------

// Ask user to choose the top-level input directory and print it
dir = getDirectory("Choose a Input Directory");
print(dir);

// List subfolders in input directory and print (top-level entries)
subfolders = getFileList(dir);
Array.print(subfolders);

// Ask the user to name the two channels that will be used for colocalization.
// The channel TIFF filenames must start with these strings.
Dialog.create("Channels");
Dialog.addString("Ch1", " ");
Dialog.addString("Ch2", " ");
Dialog.show();

Ch1 = Dialog.getString();  // channel 1 name prefix
Ch2 = Dialog.getString();  // channel 2 name prefix
print(Ch1);
print(Ch2);

// The main function that performs per-cell colocalization processing
PCC(dir);

function PCC(dir) {
	// Iterate through each entry in the top-level input directory
	for (sf = 0; sf < subfolders.length; sf++) {
		subfolder = dir + subfolders[sf];

		// Only process entries that are directories (skip files)
		if (File.isDirectory(subfolder)) {
			// Get the list of folders/files inside this subfolder
			cellFolders = getFileList(subfolder);
			print("subfolder: ", subfolder);
			Array.print(cellFolders);

			// Look for folders beginning with "Process"
			for (cf = 0; cf < cellFolders.length; cf++) {
				if (startsWith(cellFolders[cf], "Process")) {
					cellFolder = subfolder + cellFolders[cf];

					// Only proceed if this Process* entry is a directory
					if (File.isDirectory(cellFolder)) {
						datafiles = getFileList(cellFolder);
						print("cellFolder: ", cellFolder);
						Array.print(datafiles);

						// Create a results folder "coloc2" inside the cell folder
						resFolder = cellFolder + File.separator + "coloc2";
						print(resFolder);
						File.makeDirectory(resFolder);

						// Open any ROI.zip files found in the Process folder
						for (i = 0; i < datafiles.length; i++) {
							if (startsWith(datafiles[i], "ROI") && endsWith(datafiles[i], ".zip")) {
								file = cellFolder + datafiles[i];
								open(file);         // opens ROI.zip into ROI Manager
							}
						}

						// If ROI Manager contains ROIs, we proceed to open channel images
						if (roiManager("count") > 0) {
							// Find and open the channel 1 TIFF (filename startsWith Ch1 and endsWith .tif)
							for (i = 0; i < datafiles.length; i++) {
								if (startsWith(datafiles[i], Ch1) && endsWith(datafiles[i], ".tif")) {
									file1 = cellFolder + datafiles[i];
									open(file1);   // opens Ch1 TIFF (window titled e.g. "Ch1name.tif")
								}
							}
							// Find and open the channel 2 TIFF (filename startsWith Ch2 and endsWith .tif)
							for (i = 0; i < datafiles.length; i++) {
								if (startsWith(datafiles[i], Ch2) && endsWith(datafiles[i], ".tif")) {
									file2 = cellFolder + datafiles[i];
									open(file2);   // opens Ch2 TIFF
								}
							}
						}

						// Detect ROIs
						if (roiManager("count") > 0) {
							// Close any "Log" window from previous runs to avoid conflicts
							selectWindow("Log");
							run("Close");

							// Iterate ROIs in ROI Manager, running Coloc 2 per-ROI
							for (n = 0; n < roiManager("count"); n++) {
								// Ensure Ch1 image is the active window for the plugin dialog
								selectWindow(Ch1 + ".tif");

								// Select the ROI number n in the ROI Manager
								roiManager("Select", n);

								// Run Coloc 2 plugin:
								// - channel_1 and channel_2 arguments reference file names
								// - roi points Coloc2 to use ROI Manager entries
								// - threshold_regression, psf and costes_randomisations are options used here
								run("Coloc 2", "channel_1=[Ch1].tif channel_2=[Ch2].tif roi_or_mask=[ROI Manager] threshold_regression=Bisection psf=3 costes_randomisations=100");

								// After Coloc2 completes it writes a "Log" window
								selectWindow("Log");
								saveAs("text", resFolder + File.separator + "coloc_" + Ch1 + "_" + Ch2 + "_" + n);
								run("Close");   // close the Log window so next ROI doesn't get appended
							}

							// Close the channel image windows that were opened for this micrograph
							selectWindow(Ch1 + ".tif");
							close();
							selectWindow(Ch2 + ".tif");
							close();

							// Clear ROI Manager to prepare for next micrograph
							if (roiManager("count") > 0) {
								roiManager("deselect");
								roiManager("delete");
							}
						}
						
						// Close ROI Manager window
						close("ROI Manager");
					} // end if File.isDirectory(cellFolder)
				} // end if startsWith("Process")
				// After each Process folder's loop ends, tidy up open windows
				run("Close All");
				run("Dispose All Windows", "/all image non-image");
			} // end for cellFolders
		} // end if File.isDirectory(subfolder)
	} // end for subfolders
} // end function PCC
