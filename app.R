#################################
# Author: Daniela Cuba
# Date: 25/10/2018
# Project: Groundwater Droughts Initiative - BGS
# Input: 2 .csv files: data (id,date,gwl),coordinates (id, longitude, latitude)
# Output: 1 .xlsx tabs: sgis (date,stand.gw.index per bh, 5% c.i. and 95% c.i. per bh), interpolatedTS (interpolated gwl per bh, precipitation used per bh),
#                       IRFparameters (Impulse Response Function parameters per bh), coords&clusters (id, longitude, latitude, variance explained by model (measure of goodness of interpolation), cluster member (if clusters have been assigned)) 
# Version: 6
#################################

################################################ Run once and comment out ###############################################
# install.packages(c("shiny","xlsx","readxl","openxlsx","dplyr","lubridate","stringr","shinydashboard",
#                    "shinyjs","geoR","sp","rlist","leaflet","htmltools","htmlwidgets","rgdal","leaflet.extras",
#                    "tidyverse","ncdf4","rworldxtra","shinyalert","rgeos","rJava")) 
#########################################################################################################################

# Libraries
library(shiny)
library(xlsx)
library(readxl)
library(openxlsx)
library(optimx)
library(dplyr)
library(lubridate)
library(stringr)
library(shinydashboard)
library(shinyjs)
library(geoR)
library(sp)
library(rlist)
library(leaflet)
library(htmltools)
library(htmlwidgets)
library(rgdal)
library(leaflet.extras)
library(tidyverse)
library(ncdf4)
library(rworldxtra)
library(shinyalert)
library(rgeos)
library(rJava)



# setwd("N:/SGI2018") ####


ui <- function() {
  
  navbarPage("SGI Conversion",id = "nav",
             theme = shinythemes::shinytheme("united"), 
             ### DataTab ----           
             tabPanel("Data",icon = icon("file", class = NULL, lib = "font-awesome"),
                      tags$style(HTML(".sidebar {
                                      height: 90vh; overflow-y: auto;}"
                        ) # close HTML       
                      ), #tabs$style
                      
                      div(class="outer",
                          
                          tags$head(
                            includeCSS("styles.css"),
                            includeCSS(path = "AdminLTE.css"), #
                            includeCSS(path = "shinydashboard.css"), #
                            includeScript(path = "app.js"),
                            includeScript(path = "locationfilter.js")
                          ),
                          
                          fluidPage(style = "padding:0px; max-height: 100vh; overflow-y: auto;" ,
                                    
                                    # Set up leaflet map
                                    leafletOutput("mymap", width="100%", height="500px"),
                                    
                                    # Shiny versions prior to 0.11 should use class = "modal" instead.
                                    absolutePanel(id = "controls", class = "panel panel-default",
                                                  draggable = TRUE, top = 20, left = "auto", right = 20, bottom = "auto",
                                                  width = 330, height = "auto",
                                                  
                                                  h2("Import Data"),
                                                  
                                                  fileInput("file_data", "Choose data file", 
                                                            multiple = F, accept = c(".xlsx", "text/csv",".csv")),
                                                  fileInput("file_coord", "Choose coordinates file", 
                                                            multiple = F, accept = c(".xlsx", "text/csv",".csv")),
                                                  selectInput("select_country", "Select Country","",
                                                              multiple = T,selectize = T), ## should this be in a conditional panel?
                                                  checkboxInput("show_box","Show selected sites",value = T),
                                                  checkboxInput("show_omitted","Show omitted sites",value = F),
                                                  useShinyalert()
                                    ),
                                    conditionalPanel(
                                      condition = "input.show_box == true",
                                      verbatimTextOutput("test_my_patience")
                                    ), 
                                    
                                    conditionalPanel(
                                      condition = "input.show_omitted== true",
                                      verbatimTextOutput("please_work")
                                    ),
       
                                    br(),
                                    
                                    box(title = "Data Quality",
                                        status = "primary",
                                        collapsible = T,
                                        solidHeader = T,
                                        width = 12,
                                        collapsed = T,
                                        plotOutput("dq_plot")
                                    ),
                                  
                                    box(title = "Time Series Plots",
                                        status = "primary",
                                        collapsible = T,
                                        solidHeader = T,
                                        width = 12,
                                        collapsed = T,
                                        fluidRow(
                                          h4(div(style="text-align:center","Time Period")),
                                          htmltools::tagAppendAttributes(sliderInput("slide_years","", min = 1950, 
                                                                                     max = 2017,value = c(1950,2017),width = "80%",sep = ""),
                                                                         style="margin-left:auto;margin-right:auto;"),
                                          uiOutput("tsplots_boxes")
                              )
                            ),
                            br()
                          )
                        )
                      ),
             
             ### InterpolationTab ----
             tabPanel("Interpolation",icon = icon("magic",class = NULL,lib = "font-awesome"),
                      fluidPage(
                        sidebarLayout(
                          sidebarPanel(
                            width = 3,
                            selectInput("select_in2","Select Site","",multiple = T),
                            checkboxInput("check_int1","Select all", value = T),
                            h6("* Site was excluded or data for the site was not found. These sites will not be interpolated."),
                            actionButton("irf_butt","Fit IRF",icon = icon("magic", lib = "font-awesome")
                                         ,class = "btn btn-primary"
                                         #,style="color: #fff; background-color: #E74C3C  ; border-color: #2e6da4"
                            ), ### follow up with an event reactive
                            hr(),
                            checkboxGroupInput("checkbox_2","Plot Type",choices = c("Points","Lines"),selected = "Lines"),
                            hr(),
                            textInput("numeric_2","Outlier Threshold",value = 50, width = "25%", placeholder = "50"),
                            selectInput("select_refit","Select Site to Refit:","", multiple = T),
                            checkboxInput("check_intint","Select all",value = T),
                            actionButton("outlier_butt","Remove & Re-fit", 
                                         class = "btn btn-primary",
                                         icon  = icon("cut",lib = "font-awesome")
                            )
                          ),
                          #Something seems to be wrong with adding a second box, fileInput does not seems to work
                          fluidRow(
                            box(title = "Plots",
                                status = "primary",
                                collapsible = T,
                                solidHeader = T,
                                width = 8,
                                collapsed = T,
                                uiOutput("plots_2b")

                              ),
                            tags$head(
                              HTML(
                                "
                                <script>
                                var socket_timeout_interval
                                var n = 0
                                $(document).on('shiny:connected', function(event) {
                                socket_timeout_interval = setInterval(function(){
                                Shiny.onInputChange('count', n++)
                                }, 15000)
                                });
                                $(document).on('shiny:disconnected', function(event) {
                                clearInterval(socket_timeout_interval)
                                });
                                </script>
                                "
                              )
                            ),
                            textOutput("keepAlive")
                            )
                            
                          )
          
                      )
              
             ),
             
             ### SGIConversionTab ----
             tabPanel("SGI Conversion & Clustering",icon = icon("bar-chart", class = NULL, lib = "font-awesome"),
                      tags$style(HTML(".sidebar {
                                      height: 90vh; overflow-y: auto;}"
                      ) # close HTML       
                      ), #tabs$style
                      
                      div(class="outer",
                          
                          tags$head(
                            includeCSS("styles.css"),
                            includeCSS(path = "AdminLTE.css"), #
                            includeCSS(path = "shinydashboard.css"), #
                            includeScript(path = "app.js"),
                            includeScript(path = "locationfilter.js")
                          ),
                          
                          fluidPage(style = "padding:0px; max-height: 100vh; overflow-y: auto;",
                                    
                                    # Set up leaflet map
                                    leafletOutput("clustermap", width="100%", height="500px"),
                                    
                                    # Shiny versions prior to 0.11 should use class = "modal" instead.
                                    absolutePanel(id = "controls", class = "panel panel-default", #controls is id that calls css
                                                  draggable = TRUE, top = 20, left = "auto", right = 20, bottom = "auto",
                                                  width = 330, height = "auto",
                                                  h2("Cluster Analysis"),
                                                  checkboxInput("upload_clusters","Upload your own SGI data for clustering"),
                                                  conditionalPanel(
                                                    condition = "input.upload_clusters==true",
                                                    fileInput("cluster_data","Choose data file",
                                                              multiple = T, accept = c(".xlsx","text/csv", ".csv"))
                                                  ),
                                                  hr(),
                                                  numericInput("n_cluster","Numer of Clusters", 2,min = 2,max = 9,step = 1, width = "25%"),
                                                  selectInput("select_clusters","Show Clusters",choices = "",
                                                              selected = NULL, multiple = T),
                                                  checkboxInput("showcluster_box","Show selected sites"),
                                                  hr(),
                                                  downloadButton("downloads",label = "Download")
                                    ),
                                    
                                    conditionalPanel(
                                      condition = "input.showcluster_box == true",
                                      verbatimTextOutput("behave_please")
                                    ), 
                                    
                                    br(),
                                    
                                    box(title = "Cluster Analysis",
                                        status = "primary",
                                        collapsible = T,
                                        solidHeader = T,
                                        width = 12,
                                        collapsed = T,
                                        fluidRow(
                                          uiOutput("cluster_plots"),
                                          uiOutput("cluster_irfs")
                                        )
                                    ),
                                    box(title = "SGI Plots",
                                        status = "primary",
                                        collapsible = T,
                                        solidHeader = T,
                                        width = 12,
                                        collapsed = T,
                                        fluidRow(
                                          uiOutput("sgi_plots")
                                        )
                                    )
                                )
                            )
                        )
                    )
}

server <- function(input, output, session) {
  options(shiny.maxRequestSize=30*1024^2,
          warn = -1,#turn warnings back on warn = 0 
          java.parameters = "- Xmx1024m") 
  # Data tab ----
  # ** Map & coordinates code ----
  ## make leaflet map
  
  jgc <- function() {
    gc()
    .jcall("java/lang/System", method = "gc")
  }   
  
  output$mymap <- renderLeaflet({
    leaflet() %>%
      addTiles() %>%
      fitBounds(-15.39,36.4,31.02,60.38) %>%
      addDrawToolbar(
        targetGroup='Selected',
        polylineOptions = FALSE,
        markerOptions = FALSE,
        polygonOptions = drawPolygonOptions(shapeOptions=drawShapeOptions(fillColor = 'white',fillOpacity = 0.3
                                                                          ,color = 'red'
                                                                          ,weight = 3)),
        rectangleOptions = drawRectangleOptions(shapeOptions=drawShapeOptions(fillColor = 'white',fillOpacity = 0.3
                                                                              ,color = 'red'
                                                                              ,weight = 3)),
        circleOptions = drawCircleOptions(shapeOptions = drawShapeOptions(fillColor = 'white',fillOpacity = 0.3
                                                                          ,color = 'red'
                                                                          ,weight = 3)),
        editOptions = editToolbarOptions(edit = FALSE, selectedPathOptions = selectedPathOptions()))
  })
  
  
  ## check coordinates file
  data_inFile <- reactive({
    if (is.null(input$file_data)) {
      return(NULL)
    } else {
      input$file_data
    }
  })
  
  coords_inFile <- reactive({
    if (is.null(input$file_coord)) {
      return(NULL)
    } else {
      input$file_coord
    }
  })
  
  ## read in coordinates file and assign country

  file_coords <- reactive({
    
    #import countries map
    data("countriesHigh")
    
    #read data files
    if(is.null(coords_inFile())){
      return(NULL)
    } else {
        dat <- read.csv(coords_inFile()$datapath,
                        header = T,
                        colClasses = NA,
                        stringsAsFactors = F)
        jgc()

        if(is.list(dat)) {
          dat_nam <- names(dat)
          dat <- data.frame(do.call(cbind,dat),
                            stringsAsFactors = F)
          names(dat) <- dat_nam
        }
        dat2 <- data.frame("Longitude" = as.numeric(dat[,which(grepl("lon",tolower(names(dat))))]),
                          "Latitude" = as.numeric(dat[,which(grepl("lat",tolower(names(dat))))]),
                          "Names" = as.character(as.vector(dat[,which(grepl("id",tolower(names(dat))))])),
                          stringsAsFactors = F)
    #transform to the same projection as world map and assign country
    sp.datframe <- SpatialPointsDataFrame(dat2[,1:2],dat2,
                                          proj4string = CRS(" +proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs +towgs84=0,0,0"))
    dat2$Country <- as.vector((sp.datframe %over% countriesHigh)$NAME)
    if(any(is.na(dat2$Country))) {
      for(i in which(is.na(dat2$Country))) {
        dat2$Country[i] <- as.character(countriesHigh$NAME[which.min(gDistance(sp.datframe[i,], countriesHigh, byid=TRUE))])
        }
      }
    } 
    return(dat2)
  }) #file_coords
  
  
  ## update country selection
  observe({
    updateSelectInput(session,"select_country", 
                      choices = unique(file_coords()$Country),
                      selected = unique(file_coords()$Country))
  }) 
  
  ## update data based on country selection and area
  selected_by_country <- reactive({
    selsies <- which(file_coords()$Country %in% input$select_country)
    sel_country <- data.frame(Longitude = file_coords()$Longitude[selsies],
                              Latitude = file_coords()$Latitude[selsies],
                              Name = file_coords()$Name[selsies],
                              Country = as.vector(file_coords()$Country[selsies]), stringsAsFactors = F)
## is this half necessary????
    
    if(!is.null(myData())) {
      sel_country <- sel_country[sel_country$Name %in% names(myData()),]
    }
    return(sel_country)
  })
  
  omitted <- reactive({
    if(length(omit$bh) !=0) {
      a <- file_coords()[which(file_coords()$Country %in% input$select_country),]
      a <- a[a$Name %in% omit$bh,]
      
      selected <- data.frame(Longitude = a$Longitude,
                             Latitude = a$Latitude,
                             Name = a$Name,
                             Country = as.vector(a$Country), stringsAsFactors = F)
      return(selected)
    } else {
      return(NULL)
    }
  })
  
  ## Add Markers to Leaflet map of selected countries
  my_iconstoo = makeAwesomeIcon(icon = 'ban-circle',
                                library = "glyphicon",
                                markerColor = 'orange', 
                                iconColor = 'white')
      
  observe({
    if(length(input$select_country)==0) {
      leafletProxy('mymap') %>% 
        clearMarkers()
    } else if(!input$show_omitted) {
      leafletProxy('mymap') %>% 
        clearMarkers() %>%
        addMarkers(layerId = selected_by_country()$Name,
                   lng=selected_by_country()$Longitude,
                   lat=selected_by_country()$Latitude,
                   label = selected_by_country()$Name)
    } else if(input$show_omitted & !is.null(omitted())) {
      leafletProxy('mymap') %>% 
        addMarkers(layerId = selected_by_country()$Name,
                   lng=selected_by_country()$Longitude,
                   lat=selected_by_country()$Latitude,
                   label = selected_by_country()$Name) %>%
        addAwesomeMarkers(layerId = omitted()$Name,
                          lng = omitted()$Longitude,
                          lat = omitted()$Latitude,
                          label = omitted()$Name,
                          icon = my_iconstoo)
    }
  })
  
  ##  Marker selection by drawing 
  
  spatial_selection <- reactive({
    #site vector
    sel_sites <- vector("character")
    if(!is.null(selected_by_country()) & (length(input$mymap_draw_all_features$features)!=0)) {
      #turn dataframe into SpatialPointsDataFrame
      pts <- selected_by_country()
      sp.pts <- SpatialPointsDataFrame(pts[,1:2],pts,
                                       proj4string = CRS("+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs" ))
      
      for(i in 1:length(input$mymap_draw_all_features$features)){
        
        feature_type <- input$mymap_draw_all_features$features[[i]]$properties$feature_type
        
        if(feature_type %in% c("rectangle","polygon")) {
          #get coordinates
          poly_coords <- input$mymap_draw_all_features$features[[i]]$geometry$coordinates[[1]]
          
          #transform to sp Polygon
          drawn_poly <- Polygon(do.call(rbind,lapply(poly_coords,
                                                     function(x){c(x[[1]][1],x[[2]][1])}))) #Longitude, Latitude 
          
          #find points in map
          selected_sites <- sp.pts %over% SpatialPolygons(list(Polygons(list(drawn_poly),"drawn_poly")),
                                                          proj4string = CRS("+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs" ))
          
          #print cities in selected area
          if(length(sel_sites)==0){
            sel_sites <- as.vector(pts$Name[which(!is.na(as.vector(selected_sites)))])
          } else{
            sel_sites <- c(sel_sites,as.vector(pts$Name[which(!is.na(as.vector(selected_sites)))]))
          }
        } else if(feature_type=="circle") {
          #get coordinates for the center
          center_coords <- matrix(c(input$mymap_draw_all_features$features[[i]]$geometry$coordinates[[1]],
                                    input$mymap_draw_all_features$features[[i]]$geometry$coordinates[[2]]),ncol=2)
          
          #calculate the distance of the cities to the center
          dist_to_center <- spDistsN1(sp.pts,center_coords,longlat=TRUE)
          
          #select the cities that are closer to the center than the radius of the circle
          if(length(sel_sites)==0){
            sel_sites <- as.vector(pts$Name[dist_to_center < input$mymap_draw_all_features$features[[i]]$properties$radius/1000])
          } else{
            sel_sites <- c(sel_sites,
                           as.vector(pts$Name[dist_to_center < input$mymap_draw_all_features$features[[i]]$properties$radius/1000]))
          }
        }
      }
    } 
    sel_sites
  })
  
  ## Make final vector with selected sites
  sites_selected <- reactive({
    sites <- vector("character")
    if(length(input$select_country)==0 & length(spatial_selection())==0){
      sites <- vector("character")
    } else if(length(input$select_country)!=0 & length(spatial_selection())==0){
      sites <- selected_by_country()$Name
    } else if(length(input$select_country)==0 & length(spatial_selection())!=0){
      sites <- vector("character")
    } else if(length(input$select_country)!=0 & length(spatial_selection())!=0){
      sites <- spatial_selection()
    }
    return(sites)
  })
  
  ## Show names of selected sites
  output$test_my_patience <- renderText({
    if(is.null(matched_to_coords())) {
      paste("Selected sites: ",paste(sites_selected(),collapse = ", "),sep = "")
    } else {
      match_indicator <- ifelse(length(sites_selected()) == 0,NULL,paste(" .       *Data match not found."))
      sites_matched <- sites_selected()[matched_to_coords()]
      #sites_matched[!matched_to_coords()] <- paste(sites_matched[!matched_to_coords()],"*",sep = "")
      paste("Selected sites: ", paste(sites_matched,collapse = ", "), match_indicator, sep = "")
    }
  })
  
  ### Show notification in case of omitting sites
  observe({
    omit$bh
    if(length(omit$bh) > 0){
      shinyalert("Just FYI", 
                 "The data you uploaded contains boreholes with less than 15 years of measurements (180 monthly observations). 
                  Consequently, these boreholes will not be considered in the rest of the analysis. 
                  If you want to know which specific boreholes we are talking about, check the 'Show omitted sites' box in the panel.",
                 type = "warning",
                 closeOnEsc = T,
                 closeOnClickOutside = T,
                 showConfirmButton = T,
                 confirmButtonText = "Cool, thanks",
                 animation = "pop")
      }
  })
  
  output$please_work <- renderText({
    if(length(omit$bh)==0){
      paste("Omitted sites: ", "No omitted sites.", sep = "")
    } else {
#browser()
      paste("Omitted sites: ",paste(omit$bh, collapse = ", "), ". ", sep = "")
    }
  })
  
  # ** Read Data files ----
  omit <- reactiveValues(bh = list())
  approx <- reactiveValues(prep = list())
  
  ## read data files
  myData <- reactive({
    df <- list()
    if (is.null(data_inFile()) | is.null(coords_inFile())) {
      return(NULL)
    } else {
      
       if(grepl("csv", data_inFile()$datapath)){
 
         data <- read.csv(data_inFile()$datapath, 
                          header = T,
                          colClasses = NA,
                          stringsAsFactors = F)
         names(data)[1] <- "ID"
#browser()         
         
         jgc()
         
         data$ID <- as.character(data$ID)
         ids <- as.character(as.vector(unique(data$ID)))
         temp_omit <- vector("character")
         
         validate(
           need(all(data$ID %in% file_coords()$Names), "Coordinate IDs do not match data IDs"
           )
         )
 #browser()        
         #vector of dates 1950-2018
         date_vector <- data.frame(date = seq.Date(from = as.Date(paste("1950","01","01",sep = "-"), format = "%Y-%m-%d"),
                                                   to = as.Date(paste("2017","12","01",sep = "-"), format = "%Y-%m-%d"),
                                                   by = "month"),
                                   stringsAsFactors = F)

         #long and lat for precipitation file
         longs <- c(-40.375, -40.125, -39.875, -39.625, -39.375, -39.125,
                    -38.875, -38.625, -38.375, -38.125, -37.875, -37.625, -37.375,
                    -37.125, -36.875, -36.625, -36.375, -36.125, -35.875, -35.625,
                    -35.375, -35.125, -34.875, -34.625, -34.375, -34.125, -33.875,
                    -33.625, -33.375, -33.125, -32.875, -32.625, -32.375, -32.125,
                    -31.875, -31.625, -31.375, -31.125, -30.875, -30.625, -30.375,
                    -30.125, -29.875, -29.625, -29.375, -29.125, -28.875, -28.625,
                    -28.375, -28.125, -27.875, -27.625, -27.375, -27.125, -26.875,
                    -26.625, -26.375, -26.125, -25.875, -25.625, -25.375, -25.125,
                    -24.875, -24.625, -24.375, -24.125, -23.875, -23.625, -23.375,
                    -23.125, -22.875, -22.625, -22.375, -22.125, -21.875, -21.625,
                    -21.375, -21.125, -20.875, -20.625, -20.375, -20.125, -19.875,
                    -19.625, -19.375, -19.125, -18.875, -18.625, -18.375, -18.125,
                    -17.875, -17.625, -17.375, -17.125, -16.875, -16.625, -16.375,
                    -16.125, -15.875, -15.625, -15.375, -15.125, -14.875, -14.625,
                    -14.375, -14.125, -13.875, -13.625, -13.375, -13.125, -12.875,
                    -12.625, -12.375, -12.125, -11.875, -11.625, -11.375, -11.125,
                    -10.875, -10.625, -10.375, -10.125, -9.875, -9.625, -9.375, -9.125,
                    -8.875, -8.625, -8.375, -8.125, -7.875, -7.625, -7.375, -7.125,
                    -6.875, -6.625, -6.375, -6.125, -5.875, -5.625, -5.375, -5.125,
                    -4.875, -4.625, -4.375, -4.125, -3.875, -3.625, -3.375, -3.125,
                    -2.875, -2.625, -2.375, -2.125, -1.875, -1.625, -1.375, -1.125,
                    -0.875, -0.625, -0.375, -0.125, 0.125, 0.375, 0.625, 0.875, 1.125,
                    1.375, 1.625, 1.875, 2.125, 2.375, 2.625, 2.875, 3.125, 3.375,
                    3.625, 3.875, 4.125, 4.375, 4.625, 4.875, 5.125, 5.375, 5.625,
                    5.875, 6.125, 6.375, 6.625, 6.875, 7.125, 7.375, 7.625, 7.875,
                    8.125, 8.375, 8.625, 8.875, 9.125, 9.375, 9.625, 9.875, 10.125,
                    10.375, 10.625, 10.875, 11.125, 11.375, 11.625, 11.875, 12.125,
                    12.375, 12.625, 12.875, 13.125, 13.375, 13.625, 13.875, 14.125,
                    14.375, 14.625, 14.875, 15.125, 15.375, 15.625, 15.875, 16.125,
                    16.375, 16.625, 16.875, 17.125, 17.375, 17.625, 17.875, 18.125,
                    18.375, 18.625, 18.875, 19.125, 19.375, 19.625, 19.875, 20.125,
                    20.375, 20.625, 20.875, 21.125, 21.375, 21.625, 21.875, 22.125,
                    22.375, 22.625, 22.875, 23.125, 23.375, 23.625, 23.875, 24.125,
                    24.375, 24.625, 24.875, 25.125, 25.375, 25.625, 25.875, 26.125,
                    26.375, 26.625, 26.875, 27.125, 27.375, 27.625, 27.875, 28.125,
                    28.375, 28.625, 28.875, 29.125, 29.375, 29.625, 29.875, 30.125,
                    30.375, 30.625, 30.875, 31.125, 31.375, 31.625, 31.875, 32.125,
                    32.375, 32.625, 32.875, 33.125, 33.375, 33.625, 33.875, 34.125,
                    34.375, 34.625, 34.875, 35.125, 35.375, 35.625, 35.875, 36.125,
                    36.375, 36.625, 36.875, 37.125, 37.375, 37.625, 37.875, 38.125,
                    38.375, 38.625, 38.875, 39.125, 39.375, 39.625, 39.875, 40.125,
                    40.375, 40.625, 40.875, 41.125, 41.375, 41.625, 41.875, 42.125,
                    42.375, 42.625, 42.875, 43.125, 43.375, 43.625, 43.875, 44.125,
                    44.375, 44.625, 44.875, 45.125, 45.375, 45.625, 45.875, 46.125,
                    46.375, 46.625, 46.875, 47.125, 47.375, 47.625, 47.875, 48.125,
                    48.375, 48.625, 48.875, 49.125, 49.375, 49.625, 49.875, 50.125,
                    50.375, 50.625, 50.875, 51.125, 51.375, 51.625, 51.875, 52.125,
                    52.375, 52.625, 52.875, 53.125, 53.375, 53.625, 53.875, 54.125,
                    54.375, 54.625, 54.875, 55.125, 55.375, 55.625, 55.875, 56.125,
                    56.375, 56.625, 56.875, 57.125, 57.375, 57.625, 57.875, 58.125,
                    58.375, 58.625, 58.875, 59.125, 59.375, 59.625, 59.875, 60.125,
                    60.375, 60.625, 60.875, 61.125, 61.375, 61.625, 61.875, 62.125,
                    62.375, 62.625, 62.875, 63.125, 63.375, 63.625, 63.875, 64.125,
                    64.375, 64.625, 64.875, 65.125, 65.375, 65.625, 65.875, 66.125,
                    66.375, 66.625, 66.875, 67.125, 67.375, 67.625, 67.875, 68.125,
                    68.375, 68.625, 68.875, 69.125, 69.375, 69.625, 69.875, 70.125,
                    70.375, 70.625, 70.875, 71.125, 71.375, 71.625, 71.875, 72.125,
                    72.375, 72.625, 72.875, 73.125, 73.375, 73.625, 73.875, 74.125,
                    74.375, 74.625, 74.875, 75.125, 75.375)
         lats <- c(25.375, 25.625, 25.875, 26.125, 26.375, 26.625, 26.875, 
                           27.125, 27.375, 27.625, 27.875, 28.125, 28.375, 28.625, 28.875, 
                           29.125, 29.375, 29.625, 29.875, 30.125, 30.375, 30.625, 30.875, 
                           31.125, 31.375, 31.625, 31.875, 32.125, 32.375, 32.625, 32.875, 
                           33.125, 33.375, 33.625, 33.875, 34.125, 34.375, 34.625, 34.875, 
                           35.125, 35.375, 35.625, 35.875, 36.125, 36.375, 36.625, 36.875, 
                           37.125, 37.375, 37.625, 37.875, 38.125, 38.375, 38.625, 38.875, 
                           39.125, 39.375, 39.625, 39.875, 40.125, 40.375, 40.625, 40.875, 
                           41.125, 41.375, 41.625, 41.875, 42.125, 42.375, 42.625, 42.875, 
                           43.125, 43.375, 43.625, 43.875, 44.125, 44.375, 44.625, 44.875, 
                           45.125, 45.375, 45.625, 45.875, 46.125, 46.375, 46.625, 46.875, 
                           47.125, 47.375, 47.625, 47.875, 48.125, 48.375, 48.625, 48.875, 
                           49.125, 49.375, 49.625, 49.875, 50.125, 50.375, 50.625, 50.875, 
                           51.125, 51.375, 51.625, 51.875, 52.125, 52.375, 52.625, 52.875, 
                           53.125, 53.375, 53.625, 53.875, 54.125, 54.375, 54.625, 54.875, 
                           55.125, 55.375, 55.625, 55.875, 56.125, 56.375, 56.625, 56.875, 
                           57.125, 57.375, 57.625, 57.875, 58.125, 58.375, 58.625, 58.875, 
                           59.125, 59.375, 59.625, 59.875, 60.125, 60.375, 60.625, 60.875, 
                           61.125, 61.375, 61.625, 61.875, 62.125, 62.375, 62.625, 62.875, 
                           63.125, 63.375, 63.625, 63.875, 64.125, 64.375, 64.625, 64.875, 
                           65.125, 65.375, 65.625, 65.875, 66.125, 66.375, 66.625, 66.875, 
                           67.125, 67.375, 67.625, 67.875, 68.125, 68.375, 68.625, 68.875, 
                           69.125, 69.375, 69.625, 69.875, 70.125, 70.375, 70.625, 70.875, 
                           71.125, 71.375, 71.625, 71.875, 72.125, 72.375, 72.625, 72.875, 
                           73.125, 73.375, 73.625, 73.875, 74.125, 74.375, 74.625, 74.875, 
                           75.125, 75.375)
         
         #read precipitation file
         nc <- nc_open("./month_rain")
         rain <- ncvar_get(nc,"rain")
         available_rain <- rain[,,1]
         available <- which(!is.na(available_rain),arr.ind = T) #1 is long, 2 is lat

         
         #create storage list
         bh_list <- list()

          for(i in 1:length(ids)) { #iterating through borehole IDs

            #extract precipitation at coordinates closest to bh
            bh_prep <- rain[which.min(abs(as.numeric(as.vector(file_coords()$Longitude[which(file_coords()$Names == ids[i])]))-longs)),
                            which.min(abs(as.numeric(as.vector(file_coords()$Latitude[which(file_coords()$Names == ids[i])]))-lats)),]
            
            if(all(is.na(bh_prep))) {
              min_long <- available[which.min(abs(file_coords()$Longitude[which(file_coords()$Names == ids[i])] - longs[available[,1]])),1]
                bh_prep <- rain[min_long,
                                available[available[,1]==min_long,2][which.min(abs(file_coords()$Latitude[which(file_coords()$Names == ids[i])]-lats[available[available[,1]==min_long,2]]))],]
            }
            
            #prepare data
            
            temp_bh <- data[data$ID %in% ids[i],]
            old_date <- as.Date(temp_bh$date,
                                format = "%d/%m/%Y")
            temp_bh <- temp_bh %>%
              mutate(year = substr(old_date,1,4),
                     month = substr(old_date,6,7))
            temp_bh <- aggregate(gwl ~ month + year, temp_bh, mean)
            temp_bh <- temp_bh %>%
              mutate(date = as.Date(paste("01",month,year,sep = "-"),
                                    format = "%d-%m-%Y"))
            
                      
#browser()            
            if(nrow(temp_bh) < 180 | any(is.na(bh_prep))) {
              temp_omit <- c(temp_omit, ids[i])
           
            } else {
            #merge gwl, date, and precipitation
              bh_list[[ids[i]]] <- data.frame(merge(date_vector, temp_bh[,c("gwl","date")], by = "date", all.x = T ), 
                                              ppt = bh_prep,
                                              year = as.numeric(substr(date_vector$date,1,4)),
                                              stringsAsFactors = F)
            }
          }
        } else {
          warning(paste(data_inFile()$datapath, " is not a compatible format")) ### provides warning if file is not csv or xlsx
        }
    }
#browser()   
    isolate({omit$bh <- temp_omit})
    return(bh_list)
  })
  
  ## match data to coordinates
  matched_to_coords <- reactive({
    if(!is.null(file_coords()) & !is.null(myData())){
      matched <- sites_selected() %in% names(myData()) ###### gives boolean vectors of data or no data of selected sites
      return(matched)
    } else{
      return(NULL)
    }
  })
  
  ## Name of selected sites with data
  final_selected <- reactive({
    fs <- sites_selected()[matched_to_coords()]
    fs
  })
  
  
  ## make data match slide input
  timedData <- reactive({
  if(is.null(myData())) {
    return(NULL)
  } else {
    tdata <- list()
    for(i in 1:length(final_selected())){
      dd <- myData()[[final_selected()[i]]]
      tdata[[i]] <- dd[which(dd$year %in% seq(input$slide_years[1],input$slide_years[2])),]
    }
    names(tdata) <- final_selected()
    return(tdata) 
    }
  })
  
  # ** Time Series box ----
  
  #Plot time series - raw data
  max.p <- 1000
  output$tsplots_boxes <- renderUI({
    
    plot_output_list <- lapply(1:length(sites_selected()), function(i) {
      plotname <- paste("plotbox", i, sep="")
      boxname <- paste("boxbox", i, sep="")
      
      fluidRow(
        column(10,
               offset = 1,
               style = "padding:0px;",
               plotOutput(plotname, height = 250, width = 1600)),
        column(1,
               style = "padding-top:40px;",
               checkboxGroupInput(boxname,"",choices = c("Highlight","Exclude"),selected = ifelse(matched_to_coords()[i],"","Exclude"),
                                  inline = F))
      )
    })
    do.call(tagList, plot_output_list)
  })
  
  ## plot ts
  for (i in 1:max.p) {
    
    local({
      
      my_i <- i
      
      plotname <- paste("plotbox", my_i, sep="")
      
      output[[plotname]] <- renderPlot({
        if(sites_selected()[my_i] %in% names(timedData())){
          plot(timedData()[[sites_selected()[my_i]]]$gwl~timedData()[[sites_selected()[my_i]]]$date,
               main = sites_selected()[my_i],
               type = "l",
               xlab = "Date (monthly)",
               ylab = "GroundWater Level (meters)"
          )
          #################################################################################################################
        }else if(!(sites_selected()[my_i] %in% names(timedData())) | any(boxyboxes_list()[[my_i]] == "Exclude")) { #missing data or excluded box
          plot(rep(-999,length.out = nrow(timedData()[[1]])) ~ timedData()[[1]]$date,
               main = paste(sites_selected()[my_i],sep = ""),
               type = "n",
               xlab = "Date (monthly)",
               ylab = "GroundWater Level (meters)"
          )
        }
      })
    })
  }
  
  ## list of highlighted and excluded 
  boxyboxes_list <- reactive({
    bb_list <- list()
    if(length(sites_selected())!=0){
      for(j in 1:length(sites_selected())){
        if(is.null(input[[paste("boxbox",j,sep = "")]] )) {
          bb_list[[sites_selected()[j]]] <- list(NULL)
        } else {
          bb_list[[sites_selected()[j]]] <- input[[paste("boxbox",j,sep = "")]] 
        }
      }
    }#
    return(bb_list)
  })
  
  ## new icon style
  my_icon = makeAwesomeIcon(icon = 'flag', 
                            markerColor = 'red', 
                            iconColor = 'white')
  
  ## change marker on highlighted sites
  observeEvent(boxyboxes_list(), {
    
    if(length(boxyboxes_list())!=0){
      selected <- which(sapply(boxyboxes_list(), function(e) is.element('Highlight', e)))
      if(length(selected)==0 & !input$show_omitted) {
        leafletProxy('mymap') %>%
          clearMarkers() %>%
          addMarkers(layerId = selected_by_country()$Name,
                     lng=selected_by_country()$Longitude,
                     lat=selected_by_country()$Latitude,
                     label = selected_by_country()$Name)
        
      } else if(length(selected)==0 & (input$show_omitted & !is.null(omitted()))) {
        leafletProxy('mymap') %>% 
          clearMarkers() %>%
          addMarkers(layerId = selected_by_country()$Name,
                     lng=selected_by_country()$Longitude,
                     lat=selected_by_country()$Latitude,
                     label = selected_by_country()$Name) %>%
          addAwesomeMarkers(layerId = omitted()$Name,
                            lng = omitted()$Longitude,
                            lat = omitted()$Latitude,
                            label = omitted()$Name,
                            icon = my_iconstoo)
          
      }else if(length(selected) > 0 & length(input$select_country)!=0 & !input$show_omitted){
        sel_names <- sites_selected()[selected]
        highlighted <- selected_by_country()[selected_by_country()$Name %in% sites_selected()[selected],]
        normal <- selected_by_country()[!(selected_by_country()$Name %in% sites_selected()[selected]),]
        leafletProxy('mymap') %>%
          clearMarkers()%>%
          addAwesomeMarkers(layerId = highlighted$Name,
                            lng=highlighted$Longitude,
                            lat=highlighted$Latitude,
                            label = highlighted$Name,
                            icon = my_icon) %>%
          addMarkers(layerId = normal$Name,
                     lng = normal$Longitude,
                     lat = normal$Latitude,
                     label = normal$Name)
      } else if(length(selected) > 0 & length(input$select_country)!=0 & (input$show_omitted & !is.null(omitted()))) {
        sel_names <- sites_selected()[selected]
        highlighted <- selected_by_country()[selected_by_country()$Name %in% sites_selected()[selected],]
        normal <- selected_by_country()[!(selected_by_country()$Name %in% sites_selected()[selected]),]
        leafletProxy('mymap') %>%
          clearMarkers()%>%
          addAwesomeMarkers(layerId = highlighted$Name,
                            lng=highlighted$Longitude,
                            lat=highlighted$Latitude,
                            label = highlighted$Name,
                            icon = my_icon) %>%
          addAwesomeMarkers(layerId = omitted()$Name,
                            lng = omitted()$Longitude,
                            lat = omitted()$Latitude,
                            label = omitted()$Name,
                            icon = my_iconstoo) %>%
          addMarkers(layerId = normal$Name,
                     lng = normal$Longitude,
                     lat = normal$Latitude,
                     label = normal$Name)
      }
    }
  }
  )
  
  
  
  # ** Data Quality box ----
  ## Merge all gwls by date
  merged_gwls <- reactive({
    new_data <- myData() %>% 
      reduce(full_join, by = "date")
    gwl_cols <- grep("gwl",names(new_data),ignore.case = T)
    new_data <- new_data[,c(1,gwl_cols)]
    names(new_data)[-1] <- names(myData())
    new_data
  }) #works
  
  ## Convert to ref_number
  merged_n_by_refnum <- reactive ({
    new_merged <- merged_gwls()
    for(i in 2:ncol(new_merged)) {
      new_merged[which(!is.na(new_merged[,i])),i] <- rep(i,length.out = length(which(!is.na(new_merged[,i]))))
    }
    new_merged
  })
  
  ## Plot for data quality
  output$dq_plot <- renderPlot({
    countries <- file_coords()$Country
    clcols <- c("gold", "darkorange2","dodgerblue2","yellowgreen","mediumpurple1" ,
                "lightpink","tan3","darkgrey","red3","darkorchid3","darkslategray2",
                "deeppink2","lightsalmon","black","pink","forestgreen","firebrick1")
    par(mfrow = c(1,2))
#browser()
    matplot(merged_n_by_refnum(),
            type = "p",
            pch = 20,
            cex = 0.1,
            col = clcols[as.numeric(as.factor(as.vector(countries)))],
            xaxt = "n",
            ylab = "Reference Number")
    timelabels <- format(merged_n_by_refnum()$date,"%Y")
    axis(1,at=seq(1,nrow(merged_n_by_refnum()),60),labels=timelabels[seq(1,nrow(merged_n_by_refnum()),60)])
    legend("topright",legend = unique(as.factor(as.vector(countries))), col = unique(clcols[as.numeric(as.factor(as.vector(countries)))]),pch = 16, cex = 0.8 )
    
    num_obs <- lapply(myData(), function(x) sum(complete.cases(x)))
    num_obs <- as.vector(unlist(num_obs))
    x_obs <- seq(0,12*100,1)
    y_prop <- vector("numeric")
    
    for(i in 1:length(x_obs)) {
      y_prop[i] <- length(which(num_obs < x_obs[i]))
    }

    plot(x_obs,y_prop/length(num_obs),
         type = "l",
         xlab = "Number of observations",
         ylab = "Proportion")
    par(mfrow = c(1,1))
  })
  
  
  # Interpolation tab ----
  #Keep alive
  
  output$keepAlive <- renderText({
    req(input$count)
    paste("keep alive ", input$count)
  })
  
  # ** Site selection options only with selected sites not excluded ----
  interp_options <- reactive({
    if(length(boxyboxes_list()) > 0) {
      select <- sites_selected()
      for(i in 1:length(select)){
        #browser()
        if(is.element("Exclude",boxyboxes_list()[[select[i]]])) {
          select[i] <- paste(select[i],"*",sep = "")
        }
      }
      select
    }
  })
  
  observe({
    updateSelectInput(session, "select_in2",choices = interp_options(),
                      selected = if(input$check_int1) interp_options() else NULL)
  })
  
  #selected that have data
  actual_selected <- reactive({
    actual <- final_selected()[final_selected() %in% input$select_in2]
    actual
  })
  
  # ** Interpolation functions ----
  ## type of plot
  lines_or_points2 <- reactive({
    if(length(input$checkbox_2)==0){
      boxies2 <- "n" 
    }else if((length(input$checkbox_2)==1) & is.element("Points",input$checkbox_2)){
      boxies2 <- "p"
    }else if((length(input$checkbox_2)==1) & is.element("Lines",input$checkbox_2)){
      boxies2 <- "l"
    } else if(length(input$checkbox_2)==2) {
      boxies2 <- "b"
    }
    return(boxies2)
  })
  
  # ** fit IRF ----
  fit.IRF <- function(GWL.mis,rain) { #takes both GWL and precipitation vectors
    ##Construct R matrix
    n <- length(rain)
    R.sin <- matrix(NA,ncol = 66,nrow = (n-60))
    for(i in 1:(n-60)) {
      R.sin[i,] <- c(1,sin((2*pi*i)/12),cos((2*pi*i)/12),sin((2*pi*i)/6),cos((2*pi*i)/6),rain[(60+i):i])
    }
    
    ##Functions to optimise IRF fit
    irf.sin <- function(ps.b,R.sin) {
      irfs.beta <- vector("double",length = ncol(R.sin))
      for(i in 1:ncol(R.sin)){
        irfs.beta[i] <- ps.b[2]*(ps.b[3]^ps.b[4])*(i^(ps.b[4]-1))*exp(-(ps.b[3]*(i-2)))/gamma(ps.b[4])
      }
      return(irfs.beta)
    }
    
    beta.coeffs.sin <- function(ps.b,n.acc,R.sin) {
      beta <- vector("double", length = ncol(R.sin))
      beta[1] <- ps.b[1]
      beta[2:5] <- ps.b[5:8]
      beta[6:length(beta)] <- irf.sin(ps.b,R.sin)[1:(length(beta)-5)]
      # beta[6:(n.acc+5)] <- irf.sin(ps.b,R.sin)[1:(n.acc)]
      # beta[(n.acc+6):length(beta)] <- 0
      return(beta)
    }
    
    min.se.sin <- function(ps.b,n.acc,R.sin,bts) {
      beta <- vector("double", length = ncol(R.sin))
      beta[1] <- ps.b[1]
      beta[2:5] <- ps.b[5:8]
      #browser()    
      beta[6:length(beta)] <- irf.sin(ps.b,R.sin)[1:(length(beta)-5)]
      # beta[6:(5+n.acc)] <- irf.sin(ps.b,R.sin)[1:(n.acc)]
      # beta[(n.acc+7):length(beta)] <- 0
      a <- mean(((GWL.mis - R.sin%*%beta)^2),na.rm = T)/var(GWL.mis,na.rm = T)
      #print(a)
      return(a)
    }
    
    min.se.sin.6par <- function(ps.6,n.acc,R.sin) {
      beta <- vector("double", length = ncol(R.sin))
      beta[1:6] <- ps.6[1:6]
      beta[7:length(beta)] <- 0
      a <- mean(((GWL.mis - R.sin%*%beta)^2),na.rm = T)/var(GWL.mis,na.rm = T)   #### 
      #print(a)
      return(a)
    }
    
    min.irf <- function(p,R,beta2) {
      beta <- vector("double",length = ncol(R))
      for(i in 1:ncol(R)){
        beta[i] <- p[1]*(p[2]^p[3])*(i^(p[3]-1))*exp(-(p[3]*(i-2)))/gamma(p[3])
      }
      a <- (beta[1] - beta2)^2 
      #print(a)
      return(a)
    }
    
    #browser()
    set.seed(123)
    
    ##Optimize IRF parameters
#browser()    
    first_run <- lapply(1:10,function(i) {
      try(optimx(c(mean(GWL.mis,na.rm = T), runif(4,min = 0, max = 5),sample(1:10,1)),min.se.sin.6par,n.acc = sample(1:59,1),R.sin = R.sin,
                 method = "L-BFGS-B",lower = c(0.005,-Inf,-Inf,-Inf,-Inf,0.005), itnmax = 1000)
      )
    })
    
    vals_1 <- vector("numeric")
    try(
      vals_1 <- as.vector(unlist(lapply(first_run,function(x) x$value)))
    )
    
    sin1.6pars <- vector("numeric")
    try(
      sin1.6pars <- as.numeric(lapply(first_run,function(x) x[1:6])[[which.min(vals_1)]])
    )
    
    #find IRF function parameters that optimize for beta1
    
    if(length(sin1.6pars)!=0){
      irfs <- lapply(1:10, function(i) {
        try(optimx(c(runif(2,min = 0, max = 10),sample(1:10,1)),min.irf,R = R.sin, beta2 = sin1.6pars[6],
                   method = "L-BFGS-B",lower = c(0.005,0.005,0.005), itnmax = 1000)#initial values chosen at random
        )
      })
      vals_irf <- as.vector(unlist(lapply(irfs,function(x) x$value)))
      irfsin.pars <- as.numeric(lapply(irfs,function(x) x[1:3])[[which.min(vals_irf)]])
    }
    
    #find minimizing n.acc
    
    optsin2.par <- vector("numeric")
    count <- 0
    while(length(optsin2.par) == 0 | all(is.na(optsin2.par))){
      if((count <= 100) & (length(sin1.6pars) != 0)){
      try(
        optsin2.par <- optimx(c(as.numeric(sin1.6pars[1]),as.numeric(irfsin.pars),as.numeric(sin1.6pars[2:5])),min.se.sin,n.acc = sample(1:59,1),R.sin = R.sin,
                              method = "L-BFGS-B",lower = c(-Inf,0.005,0.005,0.005,-Inf,-Inf,-Inf,-Inf), itnmax = 1000)[,1:8]
      )
      count <- count + 1
      } else {
#browser()        
        try(
          optsin2.par <- optimx(c(rnorm(1,mean = mean(GWL.mis,na.rm = T),sd = 10),c(runif(2,min = 0, max = 10),sample(1:10,1)),runif(4,min = 0, max = 5)),min.se.sin,n.acc = sample(1:59,1),R.sin = R.sin,
                                method = "L-BFGS-B",lower = c(-Inf,0.005,0.005,0.005,-Inf,-Inf,-Inf,-Inf), itnmax = 1000)[,1:8]
        )
      count <- count + 1  
      }
      print(count)
    }
    
    par.hold.sin2 <- matrix(NA,nrow = 59,ncol = 8)
    optsin2.vals <- vector("numeric", length = 59)
    
    
    for(ii in 1:59) {
      loop_pars_vals <- lapply(1:4, function(ii) {
        if(ii == 1) {
          try(optimx(as.numeric(optsin2.par),min.se.sin,n.acc = ii ,R.sin = R.sin,
                 method = "L-BFGS-B",lower = c(-Inf,0.001,0.001,0.001,-Inf,-Inf,-Inf,-Inf), itnmax = 1000))
        } else {
          try(optimx(c(as.numeric(optsin2.par[1]),runif(2,min = 0, max = 10),sample(1:10,1),runif(4,0,2)),min.se.sin,n.acc = ii ,R.sin = R.sin,
                            method = "L-BFGS-B",lower = c(-Inf,0.001,0.001,0.001,-Inf,-Inf,-Inf,-Inf), itnmax = 1000))
        }
      })
      
#browser()
      loop_vals <- as.vector(unlist(lapply(loop_pars_vals, function(j) try(j$value))))
      optsin2.vals[ii] <- as.numeric(min(loop_vals))
      par.hold.sin2[ii,] <- as.numeric(lapply(loop_pars_vals, function(x) x[1:8])[[which.min(loop_vals)]])
      optsin2.par <- par.hold.sin2[ii,]
      print(ii)
    }
    
    #Obtain beta vector
#browser()
    beta.sin <- beta.coeffs.sin(as.numeric(par.hold.sin2[which.min(optsin2.vals),]),which.min(optsin2.vals),R.sin = R.sin)
    
    return(beta.sin)
  }
  
  # ** Predict GWL ----
  predict.GWL <- function(rain,beta) {
    n <- length(rain)
    R.sin <- matrix(NA,ncol = 66,nrow = (n-60))
    for(i in 1:(n-60)) {
      R.sin[i,] <- c(1,sin((2*pi*i)/12),cos((2*pi*i)/12),sin((2*pi*i)/6),cos((2*pi*i)/6),rain[(60+i):i])
    }
    return(R.sin%*%beta)
  }
  
  # ** Model Residuals ----
  model.residuals <- function(GWL.mis,GWL.pred) {
    #get residuals
    
    res1 <- GWL.mis - GWL.pred
    
    #data frame with residual "coordinates", same for residuals without NA
    residuals <- data.frame(res = res1,x = seq(from = 1, to = length(res1), by = 1),y = rep(1,length(res1)))
    
    nna.residuals <- residuals[!is.na(residuals$res),] #fixed
    
    #transform residuals - (shift by min+0.1)/sd
    min.res <- min(residuals$res, na.rm = T)
    sd.res <- sd(residuals$res, na.rm = T)
    residuals$res <- (residuals$res + (abs(min.res)+0.1))/sd.res
    nna.residuals$res <- (nna.residuals$res + (abs(min.res)+0.1))/sd.res
    
    #Convert to geodata object

    res.geodata <- as.geodata(list.cbind(residuals),coords.col = 2:3,data.col = 1,na.action = "none") #### list.cbind should not be in the code; however, this started malfunctioning yesterday and i cannot find another way to fix it
    nnares.geodata <- as.geodata(list.cbind(nna.residuals),coords.col = 2:3,data.col = 1,na.action = "none")
    
    #Make bounds
    bounds <- seq(0.5,30,1)
    
    #Fit variogram
    incProgress(1/5, detail = "Modelling variogram")

    ml <- likfit(coords = nnares.geodata$coords,data = nnares.geodata$data,  ################
                 ini.cov.pars=c(0.5,5),nugget=0.5,cov.model="exp",fix.lambda=FALSE,lambda = 1)
    
    #Prepare for kriging
    KC<-krige.control(obj.model=ml, type.krige="OK")
    OC<-output.control(simulations.predictive=FALSE,moments=F)
    
    #Prepare prediction locations
    missing.in <- which(is.na(GWL.mis))
    pred.locs <- pred.locs <- residuals[,2:3]#data.frame(x = missing.in, y = rep(1,length(missing.in)))
    
    #Krige
    krigeCD <- krige.conv(coords=nnares.geodata$coords,data=nnares.geodata$data,locations=pred.locs, out=OC,krige=KC) ############ takes 6 seconds
    
    ########## Cross validation ##########
    incProgress(1/5, detail = "Cross-validating")
    
    gwl.xval <- xvalid(nnares.geodata,model = ml,location.xvalid = "all",messages = T)
    
    
    #Compile output: locations, prediction, variance
    #backtransform simulation values
    out <- list()
    out[["cross.validation"]] <- gwl.xval
    
    krig.sim.backtrans <- krigeCD$simulations*sd.res - abs(min.res) - 0.1
  
    krige.output <- cbind(as.vector(pred.locs[,1]),
                          GWL.pred,
                          ((krigeCD$predict*sd.res)-abs(min.res)-0.1),
                          apply(krig.sim.backtrans,1,stats::quantile,0.05),
                          apply(krig.sim.backtrans,1,stats::quantile,0.95))#excluded simulations
    colnames(krige.output) <- c("Index","Predicted_GWL","Residuals","Sim0.05","Sim0.95")
    krige.output <- as.data.frame(krige.output)
    out[["krige.output"]] <- krige.output
    out[["Simulations"]] <- krig.sim.backtrans + as.vector(GWL.pred)
    out[["Complete.Predicted"]]  <- ((krigeCD$predict*sd.res)-abs(min.res)-0.1) + as.vector(GWL.pred) ### filling in missing indeces -  residuals
    out[["missing"]] <- missing.in

    return(out)
  }
  
  # ** FIT SGI BUTTON ----
  
  ### Loop selected and fit IRFs 
  
  #storage lists
  to.SGI <- reactiveValues(sgi_ready = list()) #
  irfs <- reactiveValues(fitted = list())
  res.md <- list() # so that results from running IRF can be referenced out of scope
  
  ## Set up renderUi
  ######## Filling render UI2 with max of 150 plots (3 plots for every site)
  max.p <- 1000

  #Plot time series - raw data
  output$plots_2b <- renderUI({
    plot_output_list <- lapply(1:(length(actual_selected())), function(i) { #*3
      plotname <- paste("plot_2b", i, sep = "")
      plotOutput(plotname, height = 750, width = 1200) #usually height = 280
    })
    do.call(tagList, plot_output_list)
  })
  
  
  # Dates
  dates <- reactive({
    timedData()[[1]]$date[61:nrow(timedData()[[1]])]
  })
  
  var_explained <- reactiveValues(by_model = list())
  times <- reactiveValues(time = list())
  ## IRF button
  observeEvent(input$irf_butt,{
   #start <- Sys.time() 
    withProgress(message = paste("Site:",sep = ""),value = 0,{
      
      for (i in 1:length(actual_selected())) {
        
          incProgress(1/length(actual_selected()), detail = paste(actual_selected()[i]," (",i," of ",length(actual_selected()),")",sep = ""))
#browser()      
      withProgress(message = paste("Fitting IRF: ",actual_selected()[i], sep = ""), value = 0, {
        
        incProgress(1/5, detail = "Optimizing IRF")
        
        bs <- fit.IRF(timedData()[[actual_selected()[i]]]$gwl[61:nrow(timedData()[[actual_selected()[i]]])],timedData()[[actual_selected()[i]]]$ppt)##### gwl must start at 60 past
        irfs$fitted[[actual_selected()[i]]] <- bs
        print(actual_selected()[i])
#browser()
        #incProgress(2/3, detail = "Predicting GWL")
        preGWL <- predict.GWL(timedData()[[actual_selected()[i]]]$ppt,bs)
    
        incProgress(1/5, detail = "Modelling residuals")
        res.md <- model.residuals(timedData()[[actual_selected()[i]]]$gwl[61:nrow(timedData()[[actual_selected()[i]]])],preGWL)
        
        }) #### progress indicator
#browser()
      res.md[["krige.output"]]$date <- timedData()[[actual_selected()[i]]]$date[61:nrow(timedData()[[actual_selected()[i]]])]
      
      ## IRF plotting
      local({
        my_i <- i
        plotname_a <- paste("plot_2b", (my_i), sep="")
        modelled_i <- res.md
        bs_i <- bs
        
        output[[plotname_a]] <- renderPlot({ ###output is list -  why is not not plotting?
          box('outer')
          par(bg = ifelse((my_i%%2==1),"white","gray98"))
          layout(matrix(c(1,1,1,1,
                       2,2,2,2,
                       3,3,3,4), 3, 4, byrow = TRUE), 
              widths=c(1,1), heights=c(1,1,1)
              )
          
          #### raw
          plot(timedData()[[actual_selected()[my_i]]]$gwl[61:nrow(timedData()[[actual_selected()[my_i]]])] ~ timedData()[[actual_selected()[my_i]]]$date[61:nrow(timedData()[[actual_selected()[my_i]]])],
               main = paste("Raw: ",actual_selected()[my_i], sep = ""),
               type = lines_or_points2(),
               xlab = "Date (monthly)",
               ylab = "GroundWater Level (meters)",
               ylim = c((min(modelled_i[["krige.output"]]$Predicted_GWL + modelled_i[["krige.output"]]$Sim0.05)-2),(max(modelled_i[["krige.output"]]$Predicted_GWL + modelled_i[["krige.output"]]$Sim0.95)+2)))
          
          #### predicted
          plot(modelled_i[["Complete.Predicted"]]~timedData()[[actual_selected()[my_i]]]$date[61:nrow(timedData()[[actual_selected()[my_i]]])],
               type = "n",
               main = paste("Predicted", 
                            " / Variance explained: ",
                            1 - round(mean(((timedData()[[actual_selected()[my_i]]]$gwl[61:nrow(timedData()[[actual_selected()[my_i]]])] - modelled_i[["krige.output"]]$Predicted_GWL)^2),na.rm = T)/var(timedData()[[actual_selected()[my_i]]]$gwl[61:nrow(timedData()[[actual_selected()[my_i]]])],na.rm = T),3),
                            sep = ""),
               ylab = "GroundWater Level (meters)",
               xlab = "Date (monthly)",
               ylim = c((min(modelled_i[["krige.output"]]$Predicted_GWL + modelled_i[["krige.output"]]$Sim0.05)-2),(max(modelled_i[["krige.output"]]$Predicted_GWL + modelled_i[["krige.output"]]$Sim0.95)+2))
          )
          
          #confidence Intervals
          l.ci <- modelled_i[["Complete.Predicted"]]
          l.ci[modelled_i[["krige.output"]]$Index] <- modelled_i[["krige.output"]]$Predicted_GWL + modelled_i[["krige.output"]]$Sim0.05
          
          u.ci <- modelled_i[["Complete.Predicted"]]
          u.ci[modelled_i[["krige.output"]]$Index] <- modelled_i[["krige.output"]]$Predicted_GWL + modelled_i[["krige.output"]]$Sim0.95
          
          polygon(c(timedData()[[actual_selected()[my_i]]]$date[61:nrow(timedData()[[actual_selected()[my_i]]])],rev(timedData()[[actual_selected()[my_i]]]$date[61:nrow(timedData()[[actual_selected()[my_i]]])])),
                  c(l.ci,rev(u.ci)),col = "grey85",border = NA)
          #Predicted
          ##### FIX COLOUR?
          cols <-ifelse(is.na(timedData()[[actual_selected()[my_i]]]$date[61:nrow(timedData()[[actual_selected()[my_i]]])]),"blue","black")
          points(timedData()[[actual_selected()[my_i]]]$date[61:nrow(timedData()[[actual_selected()[my_i]]])],modelled_i[["Complete.Predicted"]],
                 type = "l",
                 col = cols
          )

          #### square standard error 
          plot((modelled_i[["cross.validation"]]$std.error)^2 ~ timedData()[[actual_selected()[my_i]]]$date[61:nrow(timedData()[[actual_selected()[my_i]]])][which(!is.na(timedData()[[actual_selected()[my_i]]]$gwl[61:nrow(timedData()[[actual_selected()[my_i]]])]))],
               main = "Square Standard Errors",
               type = "p",
               col = ifelse((modelled_i[["cross.validation"]]$std.error^2) > as.numeric(input$numeric_2), "red","black"),
               xlab = "Date (monthly)",
               ylab = "Standard Error (meters^2)")
          
          #### IRF function plot
          plot(x = 1:61,
               y = bs_i[-c(1:5)],
               type = "l",
               lwd = 1.5,
               main = "IRF",
               ylab = "", xlab = "Months")
          
          
        })
        
        
      }) #### for local variable stuff 
      
      to.SGI$sgi_ready[[actual_selected()[i]]] <- res.md
      var_explained$by_model[[actual_selected()[i]]] <- 1 - round(mean(((timedData()[[actual_selected()[i]]]$gwl[61:nrow(timedData()[[actual_selected()[i]]])] - res.md[["krige.output"]]$Predicted_GWL)^2),na.rm = T)/var(timedData()[[actual_selected()[i]]]$gwl[61:nrow(timedData()[[actual_selected()[i]]])],na.rm = T),3)
      
      } #for loop
      
    }) #first progress indicator
    #end <- Sys.time()
    #isolate(times$time <- c(star,end))
  })
  # 
  # output$check_time <- renderText({
  #  unlist(times$time) 
  # })
  
  ## bh with outlier standard errors
  
  outlier_bh <- reactive({
    bn_names <- vector("character")
    if(length(to.SGI$sgi_ready) > 0 & !(input$numeric_2=="")){
      for(j in 1:length(to.SGI$sgi_ready)) {
        if(any(((to.SGI$sgi_ready[[j]]$cross.validation$std.error)^2) > as.numeric(input$numeric_2))) {
          bn_names[length(bn_names)+1] <- names(to.SGI$sgi_ready)[j]
        }
      }
    }
    bn_names
  })
  
  
  
  # ** REF-FIT SGI BUTTON ----
  
  observe({
    updateSelectInput(session, "select_refit",choices = outlier_bh(),
                      selected = if(input$check_intint) outlier_bh() else NULL)
  })
  
  ##### RE-fit Button ####re-fit IRF having dropped errors above threshold #### for all i guess
  
  observeEvent(input$outlier_butt,{
    
    
    withProgress(message = paste("Re-fit Site:",sep = ""),value = 0,{
    
    for(i in 1:length(input$select_refit)){
      incProgress(1/length(input$select_refit), detail = paste(input$select_refit[i]," (",i," of ",length(input$select_refit),")",sep = ""))
  
      ts <- timedData()[[input$select_refit[i]]]

      ts$gwl[!is.na(ts$gwl)][which(((to.SGI$sgi_ready[[input$select_refit[i]]]$cross.validation$std.error)^2) > as.numeric(input$numeric_2))] <- rep(NA,length(which(((to.SGI$sgi_ready[[input$select_refit[i]]]$cross.validation$std.error)^2) > as.numeric(input$numeric_2)))) # will change points to be missing instead of removing them all together and making the dataset smaller
      
      withProgress(message = paste("Re-Fitting IRF: ",input$select_refit[i], sep = ""), value = 0, {
        
        incProgress(1/5, detail = "Optimizing IRF")
        bs <- fit.IRF(ts$gwl[61:nrow(ts)],ts$ppt)##### gwl must start at 60 past
        irfs$fitted[[input$select_refit[i]]] <- bs
        
        incProgress(1/5, detail = "Predicting GWL")
        preGWL <- predict.GWL(ts$ppt,bs)
        
        incProgress(1/5, detail = "Modelling residuals")
        res.md <- model.residuals(ts$gwl[61:nrow(ts)],preGWL)
        
      }) #### progress indicator
      
      res.md[["krige.output"]]$date <- ts$date[61:nrow(ts)] #####??????
    
      local({
        f_i <- i
        my_i <- which(names(to.SGI$sgi_ready) == input$select_refit[f_i]) ###### replaces already existing plots
        plotname_a <- paste("plot_2b", my_i, sep="")
        modelled_i <- res.md
        ts_i <- ts
        bs_i <- bs
        
        output[[plotname_a]] <- renderPlot({ ###Plotting is weird
          par(bg = ifelse((my_i%%2==1),"white","gray98"))
          layout(matrix(c(1,1,1,1,
                          2,2,2,2,
                          3,3,3,4), 3, 4, byrow = TRUE), 
                 widths=c(1,1), heights=c(1,1,1))
          
          ###Raw
          plot(ts_i$gwl[61:nrow(ts_i)] ~ ts_i$date[61:nrow(ts_i)],
               main = paste("Raw: ",actual_selected()[my_i], sep = ""),
               type = lines_or_points2() ,
               xlab = "Date (monthly)",
               ylab = "GroundWater Level (meters)")
          

          ####predicted
          plot(modelled_i[["Complete.Predicted"]]~ts_i$date[61:nrow(ts_i)],
               type = "n",
               main = paste("Predicted", 
                            " / Variance Explained: ",
                            1 - round(mean(((timedData()[[actual_selected()[my_i]]]$gwl[61:nrow(timedData()[[actual_selected()[my_i]]])] - modelled_i[["krige.output"]]$Predicted_GWL)^2),na.rm = T)/var(timedData()[[actual_selected()[my_i]]]$gwl[61:nrow(timedData()[[actual_selected()[my_i]]])],na.rm = T),3),
                            sep = ""),
               ylab = "GroundWater Level (meters)",
               xlab = "Date (monthly)"
          )
          
          #confidence Intervals
          l.ci <- modelled_i[["Complete.Predicted"]]
          l.ci[modelled_i[["krige.output"]]$Index] <- modelled_i[["krige.output"]]$Predicted_GWL + modelled_i[["krige.output"]]$Sim0.05 ####### change
          
          u.ci <- modelled_i[["Complete.Predicted"]]
          u.ci[modelled_i[["krige.output"]]$Index] <- modelled_i[["krige.output"]]$Predicted_GWL + modelled_i[["krige.output"]]$Sim0.95 ####### change
          
          polygon(c(ts_i$date[61:nrow(ts_i)],rev(ts_i$date[61:nrow(ts_i)])),
                  c(l.ci,rev(u.ci)),col = "grey88",border = NA)
          
          ##### fix colour!
          cols <-ifelse(is.na(ts_i$date[61:nrow(ts_i)]),"blue","black") ##### browse
          points(ts_i$date[61:nrow(ts_i)],modelled_i[["Complete.Predicted"]],
                 type = "l",
                 col = cols
          )
          
          ###Errors
    
          plot((modelled_i[["cross.validation"]]$std.error^2) ~ ts_i$date[61:nrow(ts_i)][!is.na(ts_i$gwl[61:nrow(ts_i)])],
               main = "Standard Errors",
               type = "p",
               col = ifelse((modelled_i[["cross.validation"]]$std.error^2) > as.numeric(input$numeric_2), "red","black"), #### if input$ needs to be converted into numeric
               xlab = "Date (monthly)",
               ylab = "Standard Error (meters)")
          
          
          #### IRF function plot
          plot(x = 1:61,
               y = bs_i[-c(1:5)],
               type = "l",
               lwd = 1.5,
               main = "IRF",
               ylab = "", xlab = "Months")
          
        })
        
        }) #### for local variable stuff 
       to.SGI$sgi_ready[[input$select_refit[i]]] <- res.md
       var_explained$by_model[[input$select_refit[i]]] <- 1 - round(mean(((ts$gwl[61:nrow(ts)] - res.md[["krige.output"]]$Predicted_GWL)^2),na.rm = T)/var(ts$gwl[61:nrow(ts)],na.rm = T),3)
       
      } #for loop
    })
  })
  
  # SGI&Cluster tab ----
  
  #** Leaflet map ----
  output$clustermap <- renderLeaflet({
    leaflet() %>%
      addTiles() %>%
      fitBounds(-15.39,36.4,31.02,60.38)%>%
      addLegend("bottomleft", 
                colors = ugly_colours, 
                labels = c("1","2","3","4","5","6","7","8","9"),
                title = "Cluster ID")
  })
  
  #SGI function
  SGI_monthly <- function(x) {
    #Obtain dimensions of x
    #Matrix or vector to hold SGI values
    if(!is.null(ncol(x))){
      c <- ncol(x)
      r <- nrow(x)
      to.return <- matrix(NA, nrow = r, ncol = c)
    } else{
      c <- 1
      r <- length(x)
      to.return <- matrix(NA,nrow = r,ncol = c)
      x <- as.matrix(x)
    }
    
    for (i in 1:c) { #c is site
      
      for(month in 1:12) { #iterating through each month of the year
        
        #Select the same month every year
        k <- seq(from = month, to = r,by = 12)
        
        #Drop incomplete cases and subset data to specific month and site

        k <- k[complete.cases(x[k,i])]
        xm <- x[k,i]
        
        #Create a - a vector of ascending values that are normally distributed
        l <- 1/length(k)
        F <- seq(from = l/2,to = 1, by = l)
        a <- qnorm(F)
        
        #Order values of xm according to rank
        kk <- order(xm)
        #kk <- rank(xm)
        #to.return[k,i] <- a[kk] #either way works
        #Fill return matrix with ordered and normalized values
        to.return[k[kk],i] <- a
        
      }
    }
    return(to.return)
  }
  
## **SGI conversion Box ----
  #Matrix of interpolated values
  interp_matrix <- reactive({
    #sgi_matrix columns are in the same order as to.SGI$sgi_ready
    n <- length(to.SGI$sgi_ready)
    if(n==0) {
      return(NULL)
    }else if(n==1) {
      sgis <- as.matrix(to.SGI$sgi_ready[[1]][["Complete.Predicted"]])
    }else if (n==2) {
      sgis <- as.matrix(cbind(to.SGI$sgi_ready[[1]][["Complete.Predicted"]],to.SGI$sgi_ready[[2]][["Complete.Predicted"]]))
    }else {
      sgis <- cbind(to.SGI$sgi_ready[[1]][["Complete.Predicted"]],to.SGI$sgi_ready[[2]][["Complete.Predicted"]])
      for(j in 3:n) {
        sgis <- cbind(sgis,to.SGI$sgi_ready[[j]][["Complete.Predicted"]])
      }
    } 
    return(as.matrix(sgis))
  })
  
  #Create matrix
  sgi_matrix <- reactive({
    if(!is.null(interp_matrix())){
    return(SGI_monthly(interp_matrix()))
    } else {
      return(NULL)
    }
  })
  
  #** Read in SGId data ----
  file_cluster <- reactive({
    if (is.null(input$cluster_data)) {
      return(NULL)
    } else {
      input$cluster_data
    }
  })
  
  cluster_data <- reactive({
    if(is.null(file_cluster())) {
        return (NULL)
      }else {
#browser() 
      for (j in 1:nrow(file_cluster())){
        dat <- openxlsx::read.xlsx(file_cluster()$datapath[j], 
                                   sheet  = "sgis",
                                   detectDates = T,
                                   colNames = T)
        
        if(!all(complete.cases(dat))) {
          validate(
            need(all(complete.cases(dat)), "Data is incomplete")
          )
          return(NULL)
          
        } else{
          if(j == 1) {
            data_to_return <- dat
          } else{
            data_to_return <- merge(data_to_return, dat, by = "Date", all = F) 
          }
        }

      }
#browser()        
      return(data_to_return)
    }
  })
  
  cluster_coords <- reactive({
    if(is.null(file_cluster())) {
      return(NULL)
    } else {
      for(i in 1:nrow(file_cluster())){
        cs <- xlsx::read.xlsx(file_cluster()$datapath[i], 
                            sheetName  = "coords&clusters",
                            colClasses = NA,
                            stringsAsFactors = F)
        if(i == 1) {
          coords <- cs
        } else {
          coords <- rbind(coords, cs)
        }
      }
#browser()      
      return(coords) #Name, Longitude, Latitude
    } 
  })
  

  #number of plots
  output$sgi_plots <- renderUI({
    if(is.null(file_cluster())) {
      if(length(to.SGI$sgi_ready) > 0){
      plot_output_listb <- lapply(1:length(to.SGI$sgi_ready), function(i) {
        plotname <- paste("plot_sgi", i, sep="")
        fluidRow(
        column(10,
               offset = 1,
               style = "padding:0px",
                plotOutput(plotname, height = 250, width = 1600)) ###### Maybe make it weider in case comparison is needed
          )
        })
      do.call(tagList, plot_output_listb)
      }
    } else {
      #browser()
      plot_output_listb <- lapply(1:(ncol(cluster_data())-1), function(i) {
        plotname <- paste("plot_sgi", i, sep="")
        fluidRow(
          column(10,
                 offset = 1,
                 style = "padding:0px",
                 plotOutput(plotname, height = 250, width = 1600)
                 ) ###### Maybe make it weider in case comparison is needed
          )
      })
      do.call(tagList, plot_output_listb)
    }
  })

  observe({
    if(is.null(cluster_data())) {
      for (i in 1:length(to.SGI$sgi_ready)) {
        local({
          my_i <- i
          plotname <- paste("plot_sgi", my_i, sep="")
          output[[plotname]] <- renderPlot({
            plot(SGI_monthly(to.SGI$sgi_ready[[my_i]]$Complete.Predicted)~dates(),#as.Date(final.SGI[[input$select_in3[my_i]]]$date),
                 main = names(to.SGI$sgi_ready)[my_i],
                 type = "n",
                 xlab = "Date (monthly)",
                 ylab = "SGI"
            )
            
            low_ci <- apply(SGI_monthly(to.SGI$sgi_ready[[my_i]]$Simulations),1,stats:: quantile, 0.05)
            hi_ci <- apply(SGI_monthly(to.SGI$sgi_ready[[my_i]]$Simulations),1,stats:: quantile, 0.95)
            
            polygon(c(dates(),rev(dates())),
                    c(low_ci,rev(hi_ci))
                    ,col = "grey88",border = NA)
            # #browser()
            points(y = SGI_monthly(to.SGI$sgi_ready[[my_i]]$Complete.Predicted),
                   x = dates(),
                   type = "l",col = "black")

            }) #renderplot
          }) #local
        }#for loop
      } else {
        for(i in 2:ncol(cluster_data())) {
          local({
            my_i <- i
            plotname <- paste("plot_sgi", (my_i-1), sep="")
            output[[plotname]] <- renderPlot({
              plot(cluster_data()[,my_i]~cluster_data()$Date,
                   main = names(cluster_data())[my_i],
                   type = "l",
                   xlab = "Date (monthly)",
                   ylab = "SGI"
              )
            }) #renderplot
          }) #local
        }#for loop
      }
  })

    
    ## ** Clustering ----
    cluster_output <- reactive({
      if(is.null(cluster_data())){  
        if(!is.null(sgi_matrix()) & (length(to.SGI$sgi_ready) >2)) {
          km <- kmeans(t(sgi_matrix()),input$n_cluster, nstart = 1000)
        } else{
          km <- NULL
        }
      } else{
         if(ncol(cluster_data())>3) {
           km <- kmeans(t(cluster_data()[,-1]),input$n_cluster, nstart = 1000)
         } else{
           km <- NULL
         }
      }
      return(km)
    })
  
    cluster_mem <- reactive({
      if(is.null(cluster_data())){
        if((length(to.SGI$sgi_ready) >2)) {
        members <- data.frame(Name = selected_by_country()$Name[selected_by_country()$Name %in% names(to.SGI$sgi_ready)],
                              Longitude = selected_by_country()$Longitude[selected_by_country()$Name %in% names(to.SGI$sgi_ready)],
                              Latitude = selected_by_country()$Latitude[selected_by_country()$Name %in% names(to.SGI$sgi_ready)],
                              Cluster = cluster_output()$cluster,
                              Variance_Explained = as.vector(unlist(var_explained$by_model)),
                              stringsAsFactors = F)
  
        }else if((length(to.SGI$sgi_ready) <= 2) & (length(to.SGI$sgi_ready) >0)) {
          members <- data.frame(Name = selected_by_country()$Name[selected_by_country()$Name %in% names(to.SGI$sgi_ready)],
                                Longitude = selected_by_country()$Longitude[selected_by_country()$Name %in% names(to.SGI$sgi_ready)],
                                Latitude = selected_by_country()$Latitude[selected_by_country()$Name %in% names(to.SGI$sgi_ready)],
                                Cluster = rep(1,length(to.SGI$sgi_ready)),
                                Variance_Explained = as.vector(unlist(var_explained$by_model)),
                                stringsAsFactors = F)
        } else {
          return(NULL)
          }
      } else {
        if(ncol(cluster_data()) <= 3) {
          members <- data.frame(Name = names(cluster_data())[-1],
                                Longitude = cluster_coords()$Longitude,
                                Latitude = cluster_coords()$Latitude,
                                Cluster = rep(1,ncol(cluster_data())),
                                Variance_Explained = cluster_coords()$Variance_Explained,
                                stringsAsFactors = F)
        } else {
          members <- data.frame(Name = names(cluster_data())[-1],
                                Longitude = cluster_coords()$Longitude,
                                Latitude = cluster_coords()$Latitude,
                                Cluster = cluster_output()$cluster,
                                Variance_Explained = cluster_coords()$Variance_Explained,
                                stringsAsFactors = F)
        }
      }
      return(members)
    }) 
    
      #updated what clusters to show
      observe({
        updateSelectInput(session,"select_clusters", choices = 1:input$n_cluster, selected = 1:input$n_cluster)
      }) 
      
    ## ** Cluster Box ----
      ## cluster TS
      output$cluster_plots <- renderUI({
          plot_output_listb <- lapply(1:input$n_cluster, function(i) {
            plotname <- paste("plot_cluster", i, sep="")
            fluidRow(
              column(10,
                     offset = 1,
                     style = "padding:0px",
                     plotOutput(plotname, height = 250, width = 1600)) ###### Maybe make it weider in case comparison is needed
               )
            })
          do.call(tagList, plot_output_listb)
      })
      
      
      observeEvent(input$select_clusters,{
#browser()        
        for (i in 1:input$n_cluster) {
          if(is.null(cluster_data())){
            local({
              my_i <- i
          
              plotname <- paste("plot_cluster", my_i, sep="")
              output[[plotname]] <- renderPlot({
                  plot(x = dates(),
                       y = cluster_output()$centers[my_i,],
                       type = "l", 
                       main = paste("Cluster ",my_i, " Center", sep = ""),
                       xlab = "Date (monthly)",
                       ylab = "SGI")
                }) #renderplot
              }) #local
          } else {
            local({
              my_i <- i
              plotname <- paste("plot_cluster", my_i, sep="")
              output[[plotname]] <- renderPlot({
                plot(x = cluster_data()$Date,
                     y = cluster_output()$centers[my_i,],
                     type = "l", 
                     main = paste("Cluster ",my_i, " Center", sep = ""),
                     xlab = "Date (monthly)",
                     ylab = "SGI")
              }) #renderplot
            }) #local
              
            }
          } #for loop
      })
      
      
      ## cluster IRFs
      output$cluster_irfs <- renderUI({
        if(is.null(cluster_data())) {
        plot_output_listirf <- lapply(1:ceiling(input$n_cluster/3), function(i) {
          plotnames <- paste("plot_clirf", 3*(i-1)+(1:3), sep="")
          fluidRow(
            column(3,
                   offset = 1,
                   style = "padding:0px",
                   plotOutput(plotnames[1], height = 300, width = 400)) ###### Maybe make it weider in case comparison is needed
            ,column(3,
                    style = "padding:0px",
                    plotOutput(plotnames[2], height = 300, width = 400)) ###### Maybe make it weider in case comparison is needed
            ,column(3,
                    style = "padding:0px",
                    plotOutput(plotnames[3], height = 300, width = 400))
          )
          
          })
        do.call(tagList, plot_output_listirf)
        }else{
          return(NULL)
        }
      })
      
      ## prepare matrix of IRFS (irf per column)
      cl_irfmatrix <- reactive({
        if(is.null(cluster_data())){
          if(length(irfs$fitted) > 2){
            cl_irfs <- cbind(irfs$fitted[[1]],irfs$fitted[[2]])
            for(i in 3:length(irfs$fitted)) {
              cl_irfs <- cbind(cl_irfs, as.vector(irfs$fitted[[i]]))
            }
            #drop first 5
            cl_irfs <- cl_irfs[-c(1:5),]
            
            #normalize (from 0 - 1)
            norm_irfs <- matrix(NA, nrow = nrow(cl_irfs),ncol = ncol(cl_irfs))
            for(j in 1:ncol(cl_irfs)){
              norm_irfs[,j] <- sapply(cl_irfs[,j],
                                      function(x) (x- min(as.numeric(as.vector(cl_irfs[,j]))))/(sd(as.numeric(as.vector(cl_irfs[,j])))))
            }
            
            return(norm_irfs)
            }
        } else {
            return(NULL)
          }
      })
      
      #plot cluster irs
      observe({
        if(is.null(cluster_data())){    
          if(!is.null(cluster_output())) {
          
          for (i in 1:(ceiling(input$n_cluster/3)*3)) {
            local({
              my_i <- i
              
              plotname<- paste("plot_clirf", my_i, sep="")
              
              cl_irfs <- apply(as.matrix(cl_irfmatrix()[,which(cluster_output()$cluster == my_i)]),1,mean)
              
              output[[plotname]] <- renderPlot({
                if(my_i <= input$n_cluster){
                plot(x = 1:61,
                     y = cl_irfs,
                     type = "l", 
                     main = paste("IRF: Cluster ",my_i, sep = ""),
                     xlab = "Months",
                     ylab = "IRF")
                  
                    }else{
                  plot.new()
                    }
                 })#renderplot
                }) #local
            }#for loop
          } # if loop
        } #if cluster_data is null
      })
      
    
    ## ** Make awesomemarkers ----
    #clcols <- c("gold", "darkorange2","dodgerblue2","mediumpurple2" ,"yellowgreen","lightpink","tan3","darkgrey","red3") #wish I could keep these
    ugly_colours <- c("orange","red","darkblue","darkgreen","lightgreen","purple","pink","lightblue","lightgray")
    
    
    ## ** Adding Markers ----
    observe({
      if(!is.null(cluster_mem())) {
#browser()        
        icons <- awesomeIcons(icon = "whatever",
                              iconColor = "black",
                              library = "ion",
                              markerColor = ugly_colours[cluster_mem()$Cluster[cluster_mem()$Cluster %in% as.numeric(input$select_clusters)]])
        
        if(length(input$select_clusters) > 0){
          
        leafletProxy('clustermap') %>%
          clearMarkers() %>%
          addAwesomeMarkers(lng = cluster_mem()$Longitude[cluster_mem()$Cluster %in% as.numeric(input$select_clusters)],
                            lat = cluster_mem()$Latitude[cluster_mem()$Cluster %in% as.numeric(input$select_clusters)],
                            label = cluster_mem()$Name[cluster_mem()$Cluster %in% as.numeric(input$select_clusters)],
                            icon = icons) 
        } else {
          leafletProxy('clustermap') %>%
            clearMarkers()
        }
      }
    })
  
      

  ## ** Download Button ----    
  down_to_SGIs <- reactive({
    if(is.null(cluster_data())){
      to.download <- data.frame(dates(), sgi_matrix(), intervals(),stringsAsFactors = F)
      names(to.download) <- c("Date",names(to.SGI$sgi_ready),paste0("ci:",paste(rep(names(to.SGI$sgi_ready),each = 2),c("5%","95%"),sep = "/")))
      #to.download <- cbind(to.download)
      return(to.download)
    } else {
      return(cluster_data())
    }
  })
      
  intervals <- reactive({
    if(is.null(cluster_data())) {
      ints <-do.call(cbind,lapply(to.SGI$sgi_ready, function(x) 
                                                     as.matrix(t(apply(SGI_monthly(x$Simulations),1,stats:: quantile, c(0.05,0.95))))))
      ints <- as.data.frame(ints)
      names(ints) <- paste0("ci:",paste(rep(names(to.SGI$sgi_ready),each = 2),c("5%","95%"),sep = "/"))
      return(ints)
    }
  })    
      
  interpolated <- reactive({
    
    ppts <- matrix(NA, ncol = ncol(interp_matrix()), nrow = nrow(interp_matrix()))
    
    for(i in 1:length(to.SGI$sgi_ready)){
      ppts[,i] <- timedData()[[names(to.SGI$sgi_ready)[i]]]$ppt[61:nrow(timedData()[[names(to.SGI$sgi_ready)[i]]])]
    }
    
    go_die <- do.call(cbind,lapply(to.SGI$sgi_ready, function(x) 
                                                     as.matrix(t(apply(x$Simulations,1,stats:: quantile, c(0.05,0.95))))))
    
    interp <- data.frame(dates(), interp_matrix(),ppts,go_die, stringsAsFactors= F)
    names(interp) <- c("Date", 
                       names(to.SGI$sgi_ready),
                       paste("ppt:",names(to.SGI$sgi_ready),sep = ""),
                       paste0("ci:",paste(rep(names(to.SGI$sgi_ready),each = 2),c("5%","95%"),sep = "/")))
    return(interp)
  })
  
  IRFs_to_download <- reactive({
#browser()    
    to_out <- data.frame(cbind(names(to.SGI$sgi_ready),do.call(rbind,irfs$fitted)),stringsAsFactors = F)
    names(to_out) <- c("Name",paste("IRF_par",1:length(irfs$fitted[[1]])))
    return(to_out)
  })
  
  output$downloads <- downloadHandler(
    filename = paste("sgi_conv", "xlsx", sep = "."),
    content = function(file) {
#browser()      
      write.xlsx2(down_to_SGIs(), file, 
                  sheetName = "sgis",
                  row.names = FALSE, 
                  col.names = T)
      
    if(is.null(cluster_data())) {
      
        write.xlsx2(interpolated(), file, 
                    sheetName = "interpolatedTS", 
                    row.names = F, 
                    col.names = T,
                    append = T)
      
        write.xlsx2(IRFs_to_download(), file, 
                    sheetName = "IRF_parameters",
                    row.names = FALSE, 
                    col.names = T,
                    append = T)
    }
      
      write.xlsx2(cluster_mem(), file, 
                 sheetName = "coords&clusters",
                 row.names = FALSE, 
                 col.names = T,
                 append = T)

      
    }
  )
  
  observeEvent(to.SGI$sgi_ready, {
    if(length(to.SGI$sgi_ready) >3) {
    
    file <- "GUIoutput_latest.xlsx"
    
    write.xlsx2(down_to_SGIs(), file, 
                sheetName = "sgis",
                row.names = FALSE, 
                col.names = T)
    
    if(is.null(cluster_data())) {
      
      write.xlsx2(interpolated(), file, 
                  sheetName = "interpolatedTS", 
                  row.names = F, 
                  col.names = T,
                  append = T)
      
      write.xlsx2(IRFs_to_download(), file, 
                  sheetName = "IRF_parameters",
                  row.names = FALSE, 
                  col.names = T,
                  append = T)
    }
    
    write.xlsx2(cluster_mem(), file, 
                sheetName = "coords&clusters",
                row.names = FALSE, 
                col.names = T,
                append = T)
    }
  })
}
shinyApp(ui, server)
