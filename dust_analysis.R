library(tidyverse)
library(ncdf4)
library(raster)  
library(sf)      
library(lubridate)
library(exactextractr)
library(plyr)
library(dplyr)
library(parallel)
source("utils.R")

# Set locations to data 
WUSTL_FOLDER <- "data/SOIL" # Path to WUSTL data 
CROPSCAPE_FOLDER <- "data/cropscape" # Path to folder containing cropscape rasters 
SHAPEFILE_PATH <- "data/CA_Counties" # Path to counties shapefile
OUTPUT_DIR <- "data/results"
year <- 2016 # Year to run analysis for 
months <- 1:2 # Months to run analysis for 

# Check that paths exist 
dir.create(OUTPUT_DIR, showWarnings=FALSE)
lapply(c(WUSTL_FOLDER, CROPSCAPE_FOLDER, SHAPEFILE_PATH, OUTPUT_DIR), check_path)

# Loop through each year and perform analysis 
cat("Starting analysis for", year,"...")
start.time = Sys.time()

# Read in cropscape raster & shapefile 
cat("\nReading in cropscape raster & central valley shapefile (time invariant)...")
counties <- read_centralValley(SHAPEFILE_PATH) # Read in shapefile of Central Valley counties of interest 
cropscape_raster <- read_cropscape(CROPSCAPE_FOLDER=CROPSCAPE_FOLDER, # Read in CropScape raster
                                   year=as.character(year), 
                                   geom=counties)
cat("complete.")

# ------------------ Make cluster & run analysis ------------------

ncores <- as.numeric(Sys.getenv('SLURM_CPUS_ON_NODE'))
if (is.na(ncores)) { ncores <- 4 }
outfile <- "log.txt"
unlink(outfile)
cl <- makeCluster(ncores, outfile=outfile)
cat("\nMade cluster with", ncores,"cores.\nOutfile will be saved to", outfile)

# Load desired packages into each cluster
clusterEvalQ(cl, c(library(ncdf4),
                   library(tidyverse),
                   library(raster), 
                   library(sf),      
                   library(lubridate),
                   library(exactextractr),
                   library(plyr), 
                   library(dplyr), 
                   source("utils.R")))
clusterExport(cl=cl, varlist=c("WUSTL_FOLDER","counties", "OUTPUT_DIR","cropscape_raster"), envir=environment())

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
  output_filepath = paste0(OUTPUT_DIR,"/",format(date, "%Y%m"),".csv")
  cat("\n", format(date,"%B %Y"),": Saving results as a csv file to ", output_filepath, "...")
  write.csv(results_all, output_filepath, row.names=FALSE)
  
  cat("\n", format(date,"%B %Y"),": COMPLETED ANALYSIS. Total time elapsed:", time_elapsed_pretty(start.time.month, Sys.time()), "\n")
  
}, year=year, cropscape_raster=cropscape_raster, WUSTL_FOLDER=WUSTL_FOLDER, counties=counties)

cat("Completed analysis for", year, "\nTotal time elapsed:", time_elapsed_pretty(start.time, Sys.time()))
stopCluster(cl)
