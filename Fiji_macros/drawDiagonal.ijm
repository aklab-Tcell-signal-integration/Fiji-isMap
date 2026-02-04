// Macro to draw a centered diagonal line ROI across an image,
// plot the intensity profile, and save the measurement

// Define the length of the diagonal line
length = 90;

// Get the width and height of the active image
width = getWidth();
height = getHeight();

// Calculate the starting and ending points for the diagonal line
startX = (width - length) / 2;
startY = (height - length) / 2;
endX = startX + length;
endY = startY + length;

// Create a new image with the same dimensions as the active image
makeLine(width, height, width, height);

// Set the foreground color to white
setColor(255, 255, 255);

// Draw the diagonal line ROI
makeLine(startX, startY, endX, endY);

// Measure the intensity profile along the line ROI
run("Plot Profile");

