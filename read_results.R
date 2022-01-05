## Script name: read_results.R
##
## Purpose of script: Example how to read in csv results dataframe into R for year month of interest
##
## Date Created: 01-05-2022
## Last Modified: n/a
##
## Author:Nicole Keeney
## Email: nicolejkeeney@gmail.com
## GitHub: nicolejkeeney

# Dependencies 
source("utils.R") # For checking that path exists 

# User inputs
DATA_DIR <- "data/results/" 
year <- 2016 # Year of interest as integer value
month <- 3 # Month of interest as integer value (i.e 3 for March)

# Get date from year month and get filepath 
date <- paste0(as.character(year),"-", as.character(month),"-01") %>%  # Get year-mon 
  as.Date("%Y-%m-%d")
FILEPATH <- paste0(DATA_DIR,format(date,"%Y%m"),".csv") %>% check_path # Define filepath and check that it exists 

# Read in dataframe
df <- read_csv(FILEPATH)

# Display first few rows 
#head(df)
