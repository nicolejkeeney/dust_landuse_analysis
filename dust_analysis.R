## Script name: dust_analysis.R
##
## Purpose of script: Compute the fraction dust concentration per land use type across coccidiomycosis endemic regions in California
##
## Date Created: 12-20-2021
## Last Modified: 
##    - Added flexibility for using script for multiple years (01-18-2022)
##
## Author:Nicole Keeney
## Email: nicolejkeeney@gmail.com
## GitHub: nicolejkeeney


# ------------------ Dependencies ------------------

library(tidyverse)
library(ncdf4)
library(raster)  
library(sf)      
library(lubridate)
library(exactextractr)
library(plyr)
library(dplyr)
library(parallel)
source("utils.R") # Helper functions

# ------------------ USER INPUTS ------------------


args <- (commandArgs(TRUE)) # Input year from BASH file (see Rscript.txt)
if (length(args) == 0) { # This condition is TRUE if running code interactively in RStudio 
  year <- 2016 # Supply default value for year  
} else { 
  year <- eval( parse(text=args[1]) ) # Read in command line argument
  year <- as.integer(year) # Convert string input to integer  
}

months <- 1:12 # Months to run analysis for 


# ------------------ Define filepaths, create outfile & output directory  ------------------

# Set locations to data and check that paths exits
WUSTL_FOLDER <- paste("data/SOIL", as.character(year), sep="/") %>% check_path # Path to WUSTL data 
CROPSCAPE_FOLDER <- "data/cropscape" %>% check_path # Path to folder containing cropscape rasters 
SHAPEFILE_PATH <- "data/CA_Counties" %>% check_path # Path to counties shapefile
OUTPUT_DIR <- paste("data/results", as.character(year), sep="/") # Where to save csv results 

# Create outfile for storing info about code 
outfile <- paste0(as.character(year), "_log", ".txt")
if (file.exists(outfile)) { unlink(outfile) } # Remove file if it already exists 
cat("Created outfile", outfile, file = outfile, append = TRUE)

# Create output directory 
dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)

# Start timer
cat("\nPerforming analysis for", year,"...", file = outfile, append = TRUE)
start.time = Sys.time()

# ------------------ Read in cropscape raster & CA counties shapefile ------------------

# Read in cropscape raster & shapefile 
cat("\nReading in cropscape raster & central valley shapefile (time invariant)...", file = outfile, append = TRUE)
counties <- read_centralValley(SHAPEFILE_PATH) # Read in shapefile of Central Valley counties of interest 
cropscape_raster <- read_cropscape(CROPSCAPE_FOLDER=CROPSCAPE_FOLDER, # Read in CropScape raster
                                   year=as.character(year), 
                                   geom=counties)
cat("complete.\n", file = outfile, append = TRUE)

# ------------------ Set up cluster ------------------

# Make cluster 
ncores <- as.numeric(Sys.getenv('SLURM_CPUS_ON_NODE')) # Detect number of cores. This should be set in Rscript.txt if running in savio 
if (is.na(ncores)) { ncores <- 4 } # Set to 4 cores if no SLURM_CPUS_ON_NODE environment variable detected (i.e running on personal laptop)
cl <- makeCluster(ncores, outfile=outfile) # Make cluster using outfile defined earlier
cat("\nMade cluster with", ncores,"cores.", file = outfile, append = TRUE)

# Load desired packages into each cluster
invisible(clusterEvalQ(cl, c(library(ncdf4),
                   library(tidyverse),
                   library(raster), 
                   library(sf),      
                   library(lubridate),
                   library(exactextractr),
                   library(plyr), 
                   library(dplyr), 
                   source("utils.R"))))

# Export time-invariant variables to each cluster 
clusterExport(cl=cl, varlist=c("WUSTL_FOLDER","counties", "OUTPUT_DIR","cropscape_raster"), envir=environment())


# ------------------ PARALLELIZED ANALYSIS ------------------

# Analysis is performed for each month in parallel using parSapply from R parallel package 
parSapply(cl, months, FUN=function(month, year, cropscape_raster, WUSTL_FOLDER, counties) { 
  
  start.time.month = Sys.time()
  date <- paste0(as.character(year),"-", as.character(month),"-01") %>%  # Get year-mon of analysis as date
    as.Date("%Y-%m-%d")
  cat("\n", format(date,"%B %Y"),": Starting analysis...")
  
  # ------------------ Read in WUSTL raster ------------------
  
  cat("\n", format(date,"%B %Y"),": Reading in WUSTL raster...")
  wustl_raster <- read_wustl(WUSTL_FOLDER=WUSTL_FOLDER, 
                             year=as.character(year), 
                             month=format(date,"%m"), 
                             geom=counties)
  cat("complete.")
  
  # ------------------ Perform pixel analysis on WUSTL raster ------------------
  # Convert raster to data frame of points and determine which county each point (pixel) is in 
  cat("\n", format(date,"%B %Y"),": Converting WUSTL raster to points & determining county of each point...")
  wustl_results <- wuslt_raster_analysis(wustl_raster=wustl_raster, counties=counties)
  cat("complete.")
  
  # ------------------ Perform land type analysis ------------------
  # Pixel ID is assigned by looping through each polygon 
  # See the function cov_frac_df for more details on the code 
  cat("\n", format(date,"%B %Y"),": Computing fraction land use type in each WUSTL pixel...")
  crop_results <- crop_extraction_wustl_polys(wustl_raster=wustl_raster, cropscape_raster=cropscape_raster)
  cat("complete.")
  
  # ------------------ Combine results and save as csv file ------------------
  
  # Combine results 
  cat("\n", format(date,"%B %Y"),": Combining WUSTL and cropscape analyses...")
  results_all <- left_join(wustl_results, crop_results, on=c("pixel_ID","SOIL")) %>% 
    dplyr::rename("dust(ug/m3)" = SOIL) # Rename column
  
  # Save data frame as csv 
  output_filepath = paste0(OUTPUT_DIR,"/", format(date, "%Y%m"),".csv")
  cat("\n", format(date,"%B %Y"),": Saving results as a csv file to ", output_filepath, "...")
  write.csv(results_all, output_filepath, row.names=FALSE)
  
  cat("\n", format(date,"%B %Y"),": COMPLETED ANALYSIS. Total time elapsed:", time_elapsed_pretty(start.time.month, Sys.time()), "\n")
  
}, year=year, cropscape_raster=cropscape_raster, WUSTL_FOLDER=WUSTL_FOLDER, counties=counties)


# ------------------ End of script. Stop cluster ------------------

cat("Completed analysis for", year, "\nTotal time elapsed:", time_elapsed_pretty(start.time, Sys.time()))
stopCluster(cl)
