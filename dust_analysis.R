library(tidyverse)
library(ncdf4)
library(raster)  
library(sf)      
library(lubridate)
library(exactextractr)
library(rasterVis)
library(plyr)
library(dplyr)
source("utils.R")

# Download cropscape layers here: https://nassgeodata.gmu.edu/CropScape/
# Select state of CA, and 

# Set locations to data 
WUSTL_FOLDER <- "data/SOIL" # Path to WUSTL data 
CROPSCAPE_FOLDER <- "data/cropscape" # Path to folder containing cropscape rasters 
SHAPEFILE_PATH <- "data/CA_Counties" # Path to counties shapefile
OUTPUT_DIR <- "data/results"
year <- 2016 # Year to run analysis for 
months <- 1:2 # Months to run analysis for 

# ---------------- Perform analysis ----------------

# Check that paths exist 
lapply(c(WUSTL_FOLDER, CROPSCAPE_FOLDER, SHAPEFILE_PATH, OUTPUT_DIR), check_path)

# Read in shapefile of Central Valley counties of interest 
counties <- read_centralValley(SHAPEFILE_PATH)

# Loop through each year and perform analysis 
cat("Starting analysis for", year,"...")
start.time = Sys.time()
  
# ------------------ Read in cropscape raster ------------------
cat("\nReading in cropscape raster...")
cropscape_raster <- read_cropscape(CROPSCAPE_FOLDER=CROPSCAPE_FOLDER, 
                                   year=as.character(year), 
                                   geom=counties)
cat("complete.")

lapply(months, FUN=function(month, year, cropscape_raster, WUSTL_FOLDER, counties) { 
  
  start.time.month = Sys.time()
  date <- paste0(as.character(year),"-", as.character(month),"-01") %>%  # Get year-mon of analysis as date
    as.Date("%Y-%m-%d")
  cat("\nStarting analysis for", format(date,"%B %Y"),"...")
  
  # ------------------ Read in WUSTL raster ------------------
  cat("\nReading in WUSTL raster...")
  wustl_raster <- read_wustl(WUSTL_FOLDER=WUSTL_FOLDER, 
                             year=as.character(year), 
                             month=format(date,"%m"), 
                             geom=counties)
  cat("complete.")
  
  # ------------------ Perform pixel analysis on WUSTL raster ------------------
  # Convert raster to data frame of points and determine which county each point (pixel) is in 
  cat("\nConverting WUSTL raster to points & determining county of each point...")
  wustl_results <- wuslt_raster_analysis(wustl_raster=wustl_raster, counties=counties)
  cat("complete.")
  
  # ------------------ Perform land type analysis ------------------
  # Pixel ID is assigned by looping through each polygon 
  # See the function cov_frac_df for more details on the code 
  cat("\nComputing fraction land use type in each WUSTL pixel...")
  crop_results <- crop_extraction_wustl_polys(wustl_raster=wustl_raster, cropscape_raster=cropscape_raster)
  cat("complete.")
  
  # ------------------ Combine results and save as csv file ------------------
  
  # Combine results 
  cat("\nCombining WUSTL and cropscape analyses...")
  results_all <- left_join(wustl_results, crop_results, on=c("pixel_ID","SOIL")) %>% 
    dplyr::rename("dust(ug/m3)" = SOIL) # Rename column
  
  # Save data frame as csv 
  output_filepath = paste0(OUTPUT_DIR,"/",format(date, "%Y%m"),".csv")
  cat("\nSaving results as a csv file to ", output_filepath, "...")
  write.csv(results_all, output_filepath, row.names=FALSE)
  
  cat("\nCompleted analysis for", format(date,"%B %Y"), "\nTotal time elapsed:", time_elapsed_pretty(start.time.month, Sys.time()), "\n")
  
}, year, cropscape_raster, WUSTL_FOLDER, counties) 

cat("Completed analysis for", year, "\nTotal time elapsed:", time_elapsed_pretty(start.time, Sys.time()))
