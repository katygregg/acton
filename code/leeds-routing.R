# get route data associated with a development - reproducible

library(dplyr)
library(stplanr)
library(sf)
library(mapview)
library(units)

# make data available
# sites = readRDS("~/NewDevelopmentsCycling/data/leeds-sites.Rds")
# sf::write_sf(sites, "sites-leeds.geojson")
# piggyback::pb_upload("sites-leeds.geojson")

# get sites data
# piggyback::pb_download_url("sites-leeds.geojson")
sites = sf::read_sf("https://github.com/cyipt/acton/releases/download/0.0.1/sites-leeds.geojson")
# identify centroid closest to


# Create desire lines from development site to common destinations from nearest centroid

c = pct::get_pct_centroids(region = "west-yorkshire", geography = "lsoa") %>% rename(LA_Code = lad11cd)
m = pct::get_centroids_ew() %>% st_transform(4326)
lines_pct_lsoa = pct::get_pct_lines(region = "west-yorkshire", geography = "lsoa")
# lines_pct_msoa = pct::get_pct_lines(region = "west-yorkshire", geography = "msoa") # not needed


# MSOA data ---------------------------------------------------------------

#this can find all OD pairs (even beyond west yorkshire and >20km away)

od_all_en_wales = pct::get_od(omit_intrazonal = TRUE)

centroids_nearest_site_m = sites$msoa_code

# why does this produce so many more lines, even within west yorkshire? it produces 1352 lines (and 2816 when doing both directions), while the lsoa version only produces 115 (135 in both directions). even for msoa lines under 20km there are still 588. Is this just because the MSOAs have more commuters going to more places?
od_from_centroids_nr_sites_m = od_all_en_wales %>%
  filter(geo_code1 %in% centroids_nearest_site_m
         , geo_code2 %in% m$msoa11cd # there are some geo_code2 that aren't listed in m. probably scottish?
         )

# od_from_centroids_nr_sites_m = lines_pct_msoa %>%
#   select(geo_code1, geo_code2, all, bicycle, car_driver, car_passenger
#          # bus, taxi etc
#          ) %>%
#   filter(geo_code1 %in% centroids_nearest_site_m, geo_code2 %in% m$geo_code)

# # add on the site_id (first column)
sites_m = sites %>%
  select(msoa_code, geo_code, everything())

lines_m = stplanr::od2line(flow = od_from_centroids_nr_sites_m, sites_m, m)#why doesn't this work?
plot(lines_m)
mapview::mapview(lines_m)


# LSOA data ---------------------------------------------------------------

##this has the limitations that only sites from west yorkshire, with journeys of less than 20km are selected

centroids_nearest_site = sites$geo_code

od_from_centroids_near_sites1 = lines_pct_lsoa %>%
  select(geo_code1, geo_code2, all, bicycle, car_driver, car_passenger
         # bus, taxi etc
  ) %>%
  filter(geo_code1 %in% centroids_nearest_site, geo_code2 %in% c$geo_code) %>%
  sf::st_drop_geometry()

`%notin%` <- Negate(`%in%`)

# adding in lines where geo_code2 matches the sites, instead of geo_code1
od_from_centroids_near_sites2 = lines_pct_lsoa %>%
  select(geo_code1, geo_code2, all, bicycle, car_driver, car_passenger
         # bus, taxi etc
  ) %>%
  filter(geo_code2 %in% centroids_nearest_site & geo_code1 %in% c$geo_code & geo_code1 %notin% centroids_nearest_site ) %>%
  rename(geo_code1 = geo_code2, geo_code2 = geo_code1) %>%
  sf::st_drop_geometry()

od_from_centroids_near_sites = rbind(od_from_centroids_near_sites1, od_from_centroids_near_sites2)

dim(od_from_centroids_near_sites)


# # add on the site_id (first column)
sites_column_name_updated = sites %>%
  select(geo_code, everything())

lines_to_sites = stplanr::od2line(od_from_centroids_near_sites, sites_column_name_updated, c)
plot(lines_to_sites)
mapview::mapview(lines_to_sites)


# Distances (LSOA)---------------------------------------------------------------

lines_to_sites = lines_to_sites %>%
  st_transform(27700) %>%
  mutate(distance_crow_full = drop_units(st_length(geometry)/1000)) %>%
  st_transform(4326)

wmean = lines_to_sites %>%
  group_by(geo_code1) %>%
  summarise(mdist = weighted.mean(distance_crow_full, all),
            n_employed = sum(all)) %>%
  st_drop_geometry() %>%
  rename(geo_code = geo_code1)

places = sites[,1:4] %>%
  st_drop_geometry()

wmean = inner_join(places, wmean, by = "geo_code")
wmean

# distance_crow_fulls (MSOA)---------------------------------------------------------------

lines_m = lines_m %>%
  st_transform(27700) %>%
  mutate(distance_crow_full = drop_units(st_length(geometry)/1000)) %>%
  st_transform(4326)

under20 = lines_m %>%
  filter(distance_crow_full <= 20)

wmean_m = under20 %>%
  group_by(geo_code1) %>%
  summarise(mdist = weighted.mean(distance_crow_full, all),
            n_employed = sum(all)) %>%
  st_drop_geometry() %>%
  rename(msoa_code = geo_code1)

# places = sites[,1:4] %>%
  # st_drop_geometry()

wmean_m = inner_join(places, wmean_m, by = "msoa_code")
wmean_m

mapview(under20)

###find the proportion of these that are outside west yorkshire


# Creating routes ---------------------------------------------------------

library(stplanr)
library(parallel)
cl <- makeCluster(detectCores())
clusterExport(cl, c("journey"))#not needed and not working
routes_to_site = route(l = lines_to_sites, route_fun = cyclestreets::journey, cl = cl)


routes_to_site_quietest = route(l = lines_to_sites, route_fun = cyclestreets::journey, cl = cl, plan = "quietest")

mapview::mapview(routes_to_site)
mapview::mapview(routes_to_site_quietest)
identical(routes_to_site, routes_to_site_quietest)

###for msoa data
routes_to_site_m = route(l = under20, route_fun = cyclestreets::journey, cl = cl)
mapview::mapview(routes_to_site_m)

s1 = unique(routes_to_site$geo_code1)[1]
s2 = unique(routes_to_site$geo_code1)[2]
s3 = unique(routes_to_site$geo_code1)[3]
s4 = unique(routes_to_site$geo_code1)[4]

# Busyness and speed----------------------------------------------------------------

routes_to_site$busyness = routes_to_site$busynance / routes_to_site$distances

routes_to_site_m$busyness = routes_to_site_m$busynance / routes_to_site_m$distances

routes_to_site_quietest$busyness = routes_to_site_quietest$busynance / routes_to_site_quietest$distances

#####Add in site names####

routes_to_site = routes_to_site %>%
  mutate(site = ifelse(geo_code1 == s1, "Tyersal",ifelse(
    geo_code1 == s2, "Micklefield",ifelse(
      geo_code1 == s3, "Allerton_Bywater","LCID"))))

routes_to_site_quietest = routes_to_site_quietest %>%
  mutate(site = ifelse(geo_code1 == s1, "Tyersal",ifelse(
    geo_code1 == s2, "Micklefield",ifelse(
      geo_code1 == s3, "Allerton_Bywater","LCID"))))

routes_to_site_m = routes_to_site_m %>%
  mutate(site = ifelse(geo_code1 == s1, "Tyersal",ifelse(
    geo_code1 == s2, "Micklefield",ifelse(
      geo_code1 == s3, "Allerton_Bywater","LCID"))))

############

routes_to_site_quietest = routes_to_site_quietest %>% mutate(speed=distances/time)
routes_to_site = routes_to_site %>% mutate(speed=distances/time)

write_sf(routes_to_site,"leeds-routes.geojson")
write_sf(routes_to_site_m,"leeds-routes-msoa.geojson")
write_sf(routes_to_site_quietest,"leeds-routes-quiet.geojson")

# mapview(routes_to_site["busyness"],lwd = routes_to_site$all, scale = 1) + mapview(sites_column_name_updated[1,])

# Create route network and calculate Go Dutch scenario----------------------------------------------------

# r_grouped_by_segment = routes_to_site %>%
#   group_by(name, distances, busynance) %>%
#   summarise(n = n(), all = sum(all), bicycle = sum(bicycle), busyness = mean(busyness))

r_grouped_tyersal = routes_to_site[routes_to_site$geo_code1 == s1,] %>%
  rename(fx = start_longitude, fy = start_latitude, tx = finish_longitude, ty = finish_latitude) %>%
  group_by(fx, fy, tx, ty) %>%
  summarise(
    n = n(),
    all = mean(all),
    average_incline = sum(abs(diff(elevations))) / sum(distances),
    distance_m = sum(distances),
    busyness = weighted.mean(busyness, distances)
  ) %>%
  ungroup()

# summary(r_grouped)

r_grouped_tyersal$go_dutch = pct::uptake_pct_godutch(distance = r_grouped_tyersal$distance_m, gradient = r_grouped_tyersal$average_incline) *
  r_grouped_tyersal$all
r_grouped_lines_tyersal = r_grouped_tyersal %>% st_cast("LINESTRING")
rnet_go_dutch_tyersal = overline2(r_grouped_lines_tyersal, "go_dutch")

routes_to_site_tyersal = routes_to_site[routes_to_site$geo_code1 == s1,]
rnet_all_tyersal = overline2(routes_to_site_tyersal, "all")

# summary(rnet_go_dutch$go_dutch)

tm_shape(rnet_go_dutch_tyersal) +
  tm_lines("go_dutch", lwd = "go_dutch", scale = 9, palette = "plasma", breaks = c(0, 10, 50, 100, 200))

tm_shape(rnet_all_tyersal) +
  tm_lines("all", lwd = "all", scale = 9, palette = "plasma", breaks = c(0, 10, 50, 100, 200))

####

r_grouped_micklefield = routes_to_site[routes_to_site$geo_code1 == s2,] %>%
  rename(fx = start_longitude, fy = start_latitude, tx = finish_longitude, ty = finish_latitude) %>%
  group_by(fx, fy, tx, ty) %>%
  summarise(
    n = n(),
    all = mean(all),
    average_incline = sum(abs(diff(elevations))) / sum(distances),
    distance_m = sum(distances),
    busyness = weighted.mean(busyness, distances)
  ) %>%
  ungroup()

r_grouped_micklefield$go_dutch = pct::uptake_pct_godutch(distance = r_grouped_micklefield$distance_m, gradient = r_grouped_micklefield$average_incline) *
  r_grouped_micklefield$all
r_grouped_lines_micklefield = r_grouped_micklefield %>% st_cast("LINESTRING")
rnet_go_dutch_micklefield = overline2(r_grouped_lines_micklefield, "go_dutch")

routes_to_site_micklefield = routes_to_site[routes_to_site$geo_code1 == s2,]
rnet_all_micklefield = overline2(routes_to_site_micklefield, "all")

summary(rnet_go_dutch$go_dutch)

tm_shape(rnet_go_dutch_micklefield) +
  tm_lines("go_dutch", lwd = "go_dutch", scale = 9, palette = "plasma", breaks = c(0, 10, 50, 100, 200))

tm_shape(rnet_all_micklefield) +
  tm_lines("all", lwd = "all", scale = 9, palette = "plasma", breaks = c(0, 10, 50, 100, 200))

######

r_grouped_allerton = routes_to_site[routes_to_site$geo_code1 == s3,] %>%
  rename(fx = start_longitude, fy = start_latitude, tx = finish_longitude, ty = finish_latitude) %>%
  group_by(fx, fy, tx, ty) %>%
  summarise(
    n = n(),
    all = mean(all),
    average_incline = sum(abs(diff(elevations))) / sum(distances),
    distance_m = sum(distances),
    busyness = weighted.mean(busyness, distances)
  ) %>%
  ungroup()

r_grouped_allerton$go_dutch = pct::uptake_pct_godutch(distance = r_grouped_allerton$distance_m, gradient = r_grouped_allerton$average_incline) *
  r_grouped_allerton$all
r_grouped_lines_allerton = r_grouped_allerton %>% st_cast("LINESTRING")
rnet_go_dutch_allerton = overline2(r_grouped_lines_allerton, "go_dutch")

routes_to_site_allerton = routes_to_site[routes_to_site$geo_code1 == s3,]
rnet_all_allerton = overline2(routes_to_site_allerton, "all")




# summary(rnet_go_dutch$go_dutch)

tm_shape(rnet_go_dutch_allerton) +
  tm_lines("go_dutch", lwd = "go_dutch", scale = 9, palette = "plasma", breaks = c(0, 10, 50, 100, 200))

tm_shape(rnet_all_allerton) +
  tm_lines("all", lwd = "all", scale = 10, palette = "plasma", breaks = c(0, 10, 50, 100, 200))


####


r_grouped_lcid = routes_to_site[routes_to_site$geo_code1 == s4,] %>%
  rename(fx = start_longitude, fy = start_latitude, tx = finish_longitude, ty = finish_latitude) %>%
  group_by(fx, fy, tx, ty) %>%
  summarise(
    n = n(),
    all = mean(all),
    average_incline = sum(abs(diff(elevations))) / sum(distances),
    distance_m = sum(distances),
    busyness = weighted.mean(busyness, distances)
  ) %>%
  ungroup()

r_grouped_lcid$go_dutch = pct::uptake_pct_godutch(distance = r_grouped_lcid$distance_m, gradient = r_grouped_lcid$average_incline) *
  r_grouped_lcid$all
r_grouped_lines_lcid = r_grouped_lcid %>% st_cast("LINESTRING")
rnet_go_dutch_lcid = overline2(r_grouped_lines_lcid, "go_dutch")

routes_to_site_lcid = routes_to_site[routes_to_site$geo_code1 == s4,]
rnet_all_lcid = overline2(routes_to_site_lcid, "all")

# summary(rnet_go_dutch$go_dutch)

tm_shape(rnet_go_dutch_lcid) +
  tm_lines("go_dutch", lwd = "go_dutch", scale = 9, palette = "plasma", breaks = c(0, 10, 50, 100, 200))

tm_shape(rnet_all_lcid) +
  tm_lines("all", lwd = "all", scale = 9, palette = "plasma", breaks = c(0, 10, 50, 100, 200))




# Busyness and speed ------------------------------------------------------



### For the busyness maps as recorded in github issue and website case study
tm_shape(routes_to_site[routes_to_site$geo_code1 == s3,]) +
  tm_lines(col = "busyness", palette = "-magma", lwd = "all", scale = 5, legend.lwd.show = TRUE, legend.col.show = FALSE)


#####Allerton Bywater quiet routes
tm_shape(routes_to_site_quietest[routes_to_site_quietest$geo_code1 == s3,]) +
  tm_lines(col = "busyness", palette = "-magma", lwd = "all", scale = 5, legend.lwd.show = TRUE, legend.col.show = FALSE)


## Speed
routes_to_site_quietest = routes_to_site_quietest %>% mutate(speed=distances/time)

##Map of sections with speed <1m/s
walking_pace = routes_to_site_quietest %>%
  filter(speed < 1,
         geo_code1 == s3 # Allerton Bywater
         )

tm_shape(walking_pace) +
  tm_lines(col = "blue", lwd = 2)

routes_to_site = routes_to_site %>% mutate(speed=distances/time)

##Group route segments by destination - obtain entire routes

r_whole_routes = routes_to_site %>%
  group_by(geo_code1, geo_code2, site) %>%
  summarise(
    all = mean(all),
    average_incline = sum(abs(diff(elevations))) / sum(distances),
    distance_km = sum(distances)/1000,
    busyness = mean(busyness),
    time_mins = sum(time)/60
  ) %>%
  ungroup()

r_whole_routes = r_whole_routes %>%
  mutate(speed_mph = (distance_km*1000)/(time_mins*60)*2.237)

r_whole_weighted = r_whole_routes %>%
  group_by(geo_code1, site) %>%
  st_drop_geometry() %>%
  summarise(mean_speed = weighted.mean(speed_mph,all))
r_whole_weighted

summary(r_whole_routes[r_whole_routes$geo_code1 == s1,])
summary(r_whole_routes[r_whole_routes$geo_code1 == s2,])
summary(r_whole_routes[r_whole_routes$geo_code1 == s3,])
summary(r_whole_routes[r_whole_routes$geo_code1 == s4,])

r_whole_routes_quiet = routes_to_site_quietest %>%
  group_by(geo_code1, geo_code2, site) %>%
  summarise(
    all = mean(all),
    average_incline = sum(abs(diff(elevations))) / sum(distances),
    distance_km = sum(distances)/1000,
    busyness = mean(busyness),
    time_mins = sum(time)/60
  ) %>%
  ungroup()

r_whole_routes_quiet = r_whole_routes_quiet %>%
  mutate(speed_mph = (distance_km*1000)/(time_mins*60)*2.237)

r_whole_quiet_weighted = r_whole_routes_quiet %>%
  group_by(geo_code1, site) %>%
  st_drop_geometry() %>%
  summarise(mean_speed = weighted.mean(speed_mph,all))
r_whole_quiet_weighted

summary(r_whole_routes_quiet[r_whole_routes_quiet$geo_code1 == s1,])
summary(r_whole_routes_quiet[r_whole_routes_quiet$geo_code1 == s2,])
summary(r_whole_routes_quiet[r_whole_routes_quiet$geo_code1 == s3,])
summary(r_whole_routes_quiet[r_whole_routes_quiet$geo_code1 == s4,])

###Speed maps - quiet and fast routes

routes_to_site_quietest = routes_to_site_quietest %>%
  mutate(speed_mph = speed*2.237)

tm_shape(routes_to_site_quietest[routes_to_site_quietest$geo_code1 == s3,]) +
  tm_lines(col = "speed_mph", palette = "-magma", lwd = "all", scale = 5, legend.col.show = TRUE)

tm_shape(routes_to_site[routes_to_site$geo_code1 == s3,]) +
  tm_lines(col = "speed", palette = "-magma", lwd = "all", scale = 5, legend.col.show = TRUE)
