## Script name: utils.R
##
## Purpose of script: Helper functions for dust analysis
##
## Date Created: 12-20-2021
## Last Modified: n/a
##
## Author:Nicole Keeney
## Email: nicolejkeeney@gmail.com
## GitHub: nicolejkeeney

check_path <- function(path) { 
  # Raise error if path does not exist 
  if ((length(path) == 0) || (!file.exists(path))) { 
    stop(paste0("The path ",path," does not exist")) 
  } 
  else { return(path)}
}

time_elapsed_pretty <- function(start, end) {
  # Print time elapsed in pretty format 
  dsec <- as.numeric(difftime(end, start, unit = "secs"))
  hours <- floor(dsec / 3600)
  minutes <- floor((dsec - 3600 * hours) / 60)
  seconds <- dsec - 3600*hours - 60*minutes
  paste0(
    sapply(c(hours, minutes, seconds), function(x) {
      formatC(x, width = 2, format = "d", flag = "0")
    }), collapse = ":")
}

read_cropscape <- function(CROPSCAPE_FOLDER, year, geom) { 
  # Read in cropscape data for a given year, and crop to input geometry 
  # CROPSCAPE_FOLDER (char): path to folder containing cropscape data 
  # year (char): year to grab data for 
  # geom (sf): geometry to crop raster to
  
  wildcard <- paste0(CROPSCAPE_FOLDER ,"/*", year,"*/*",year,"*.tif")
  filepath <- Sys.glob(wildcard) # Get file path
  if (length(filepath) == 0) { stop(paste0("File with wildcard ",wildcard," does not exist")) } # Raise error if file doesn't exist
  
  cropscape_raster <- raster(filepath) %>% # Read in raster 
    crop(geom) # Crop raster to Central Valley counties  
  return(cropscape_raster)
}


read_wustl <- function(WUSTL_FOLDER, year, month, geom) { 
  # Read in WUSTL data as a raster for a given year and month, and crop to input geometry 
  # WUSTL_FOLDER (char): path to folder containing WUSTL data 
  # year (char): year to grab data for 
  # month (char): month to grab data for 
  # geom (sf): geometry to crop raster to
  
  wildcard <- paste0(WUSTL_FOLDER ,"/*", year, month,"*.nc") # Pattern matching
  filepath <- Sys.glob(wildcard) # Get file path 
  if (length(filepath) == 0) { stop(paste0("File with wildcard ",wildcard," does not exist")) } # Raise error if file doesn't exist
  
  wustl_raster <- raster(filepath) %>% # Read in raster 
    crop(geom) %>% 
    mask(geom) 
  return(wustl_raster)
}


read_centralValley <- function(shapefilePath) {
  # Read in CA shapefile. Restrict to CA central valley. Convert to crs=4326 
  
  central_valley <- c("Contra Costa","Fresno","Imperial","Kern","Kings","Los Angeles",
                      "Madera","Merced","Monterey","Orange","Riverside","San Bernardino",
                      "San Diego","San Joaquin","San Luis Obispo","Santa Barbara",
                      "Santa Cruz","Stanislaus","Tulare","Ventura")
  
  ca_tract <- sf::read_sf(shapefilePath) %>% # Read in shapefile 
    st_set_crs("EPSG:3857") %>% 
    dplyr::filter(NAME  %in% central_valley) %>% # Just get census tracts in the Central Valley
    dplyr::select(COUNTYFP, NAME, geometry) # Select columns of interest
  ca_tract$geometry <- sf::st_transform(ca_tract$geometry, crs=4326) # Convert geometry to 4326 CRS
  return(ca_tract)
}


crop_extraction_wustl_polys <- function(wustl_raster, cropscape_raster){ 
  # Compute fraction coverage for each unique land type in each WUSTL polygon 
  # wustl_raster (raster): WUSTL raster for a given year and month
  # cropscape_raster (raster): cropscape data for that year
  
  wustl_grid <- rasterToPolygons(wustl_raster, n=4) # Convert to polygons 
  
  # wustl_grid <- wustl_grid[1:5,] # FOR TESTING ONLY. 
  
  # Get coverage area by polygon 
  crops_extracted <- exactextractr::exact_extract(cropscape_raster, # Raster data 
                                                  wustl_grid, # Polygons to extract raster to 
                                                  coverage_area=TRUE, # Get area instead of fraction
                                                  default_value=999, # Replace NA with 999
                                                  progress=FALSE) # Don't show progress bar
  crop_results <- lapply(1:length(wustl_grid), FUN = function(pixel_i, extracted, wustl_polygons) { 
    cov_frac_df = get_coverage_fraction(cov_area_in_poly=extracted[[pixel_i]], poly=wustl_polygons[pixel_i,]) %>% 
      add_column(pixel_ID = pixel_i)
  }, crops_extracted, wustl_grid) %>% 
    plyr::rbind.fill() # Bind list of data frames
  
  return(crop_results)
}


get_coverage_fraction <- function(cov_area_in_poly, poly, sigfigs=4) { 
  # Get coverage fraction of each land use type in a single pixel/polygon 
  # Get value of wustl raster in that polygon 
  # Output results in a combined dataframe 
  # Columns are % land type for each land type in that pixel/polygon
  poly_varname = names(poly) # Get variable name from raster 
  df_agg <- aggregate(cov_area_in_poly[c("coverage_area")], by=list(cov_area_in_poly$value), FUN=sum) %>% # Get sum of coverage area in that polygon for each unique land type 
    dplyr::rename(value = Group.1) 
  df_agg$coverage_percent = (df_agg$coverage_area / sum(df_agg$coverage_area)) * 100 # Compute percent land type (coverage area / total area in polygon)
  df_agg$value[df_agg$value == 999] = "missing" # Replace 999 with NAN
  df_T <- t(data.frame(index = round(as.numeric(df_agg$coverage_percent), sigfigs))) %>%  # Transpose dataframe and round coverage percent
    as.data.frame
  colnames(df_T) <- paste0("%",df_agg$value) # Rename columns using % 
  df_final <- df_T %>% add_column(!!(poly_varname) := poly[[poly_varname]]) # Add wustl raster information as a column 
  return(df_final)
}


wuslt_raster_analysis <- function(wustl_raster, counties) { 
  # Convert raster to dataframe of points and determine which county each point (pixel) is in 
  # Code modified from Stack Exchange response from user dof1985
  # https://gis.stackexchange.com/questions/282750/identify-polygon-containing-point-with-r-sf-package
  
  wustl_df <- rasterToPoints(wustl_raster) %>% # Convert raster to data frame of coordinates
    as.data.frame
  pnts_sf <- do.call("st_sfc",c(lapply(1:nrow(wustl_df),  function(i) { # Convert each lat, lon point to sf Point object with a CRS 
    st_point(as.numeric(wustl_df[i,1:2])) 
  }), list("crs" = 4326))) %>% 
    st_transform(2163) # Transform to planar 
  counties_trans <- st_transform(counties, 2163) # Transform to planar 
  wustl_df$COUNTY <- apply(st_intersects(counties_trans, pnts_sf, sparse = FALSE), 2, # Check which county the point intersects with 
                           function(col) {counties[which(col), ]$NAME})
  df_results <- wustl_df %>% # Beautify final dataframe output 
    dplyr::rename(longitude = x, latitude = y) %>% # Rename columns to longitude, latitude 
    cbind(pixel_ID = as.numeric(rownames(wustl_df)))  # Get pixel ID from dataframe index 
  df_results <- df_results[,c("pixel_ID","COUNTY","latitude","longitude",names(wustl_raster))] # Reorder columns 
  return(df_results)
}