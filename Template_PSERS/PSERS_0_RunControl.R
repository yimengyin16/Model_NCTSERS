# Run control file of the PSERS model


#********************************************************************************
#                            Packages and tools ####
#********************************************************************************

rm(list = ls())
gc()

library(knitr)
library(data.table)
library(gdata) # read.xls
library(plyr)
library(dplyr)
options(dplyr.print_min = 100) # default is 10
options(dplyr.print_max = 100) # default is 20
library(ggplot2)
library(magrittr)
library(tidyr) # gather, spread
library(foreach)
library(doParallel)
library(microbenchmark)
library(readxl)
library(stringr)
library(zoo)
library("readxl")
library("XLConnect") # slow but convenient because it reads ranges; NOTE: I had to install Java 64-bit on Windows 10 64-bit to load properly
# library(xlsx)
library("btools")
options(dplyr.print_min = 60) # default is 10


source("Functions.R")


#********************************************************************************
#                             Development Notes ####
#********************************************************************************

# Road map for model files (all with suffix "PSERS_" and extension ".R")

  # Master files:
  # Master_singleTier
  # Master_allTiers
  
  # Data_RP2000
  # Data_PlanInfo 
  # Data_ImportMemberData
  
  # Model_decrements
  # Model_InvReturns
  # Model_PrepData
  # Model_Demographics
  # Model_ContingentAnnuity
  # Model_IndivLiab
  # Model_AggLiab
  # Model_Sim



## Assumptions and simplifications
# 1. Assume all terms take a lump sum benefit equal to the present value 
# 2. Assume members are elgible for death benefit only after they are eligible for early or normal retirement. Assume the benefit


## For PSERS death benefit: 
#    1. Lump sum death benefit equal to PV of future benefit (Bx.death * ax.deathBen);
#    2. Death benefit are assumed to be claimed 1 year after death     


# For PSERS term benefit: 
#   1. Vested terms begin to receive benefit 1 year after termination. (use the same method as disability benefit.)
#   2. benefits are equal to accrued benefit up to the year of termination 
#   3. Should be reduced later. 

# PSERS: expand qxm.post.male/female with qxm.pre.male/female



#### Model Parameters ####
#********************************************************************************
folder_run <- "."
filename_RunControl <- dir(folder_run, pattern = "^RunControl")
path_RunControl <- paste0(folder_run, "/" ,filename_RunControl)

# Import global parameters
runList <- read_excel(path_RunControl, sheet="params", skip = 0) %>% filter(!is.na(runname), include == 1)
runList

# Import return scenarios
returnScenarios <- read_excel(path_RunControl, sheet="returns", skip = 0) %>% filter(!is.na(scenario))

# Import global parameters
Global_paramlist <- read_excel(path_RunControl, sheet="GlobalParams") %>% filter(!is.na(init.year)) %>% 
                 as.list


#### Run Models and Save  ####
#********************************************************************************

folder_save <- "Results/"



#####  Run Model ####
#*********************************************************************************************************


for(runName in runList$runname ){
  
  #runName <- "RS1"
  
  paramlist <- get_parmsList(runList, runName)
  
  paramlist$simTiers <- "separate"  # "joint"(defult) or "separate"

  if(paramlist$nyear.override != 0) Global_paramlist$nyear <- paramlist$nyear.override
  

  # Global_paramlist (Specified in RunControl.xlsx)
  
    # init.year = 2015,
    # nyear     = 30,
    # nsim      = 2000,
    # ncore     = 4,
    # 
    # min.ea    = 20,
    # max.ea    = 74, # Retirement rate is 100% at age 75 
    # 
    # min.age   = 20,
    # max.age   = 115 # Need to set mortality at age 115 to 1

  
  
 # Benefit provisions
  paramlist$r.min  <- 55 # this is not required age of retirement benefit. 
  paramlist$r.max  <- 74 
  paramlist$bfactor <- 0.025
  
  # paramlist$r.full <- 50 # age at which vested terms are assumed to retire(Temp, should use r.vben)
  # paramlist$r.vben <- 50 # age at which vested terms are assumed to retire.
  

 # Funding policy 
  paramlist$smooth_method <- "method1"
  #paramlist$salgrowth_amort <- 0.035   #   0.035 #0.213 # paryoll growth 5.5%, 3.5%, 2.13%
  #paramlist$amort_type <- "open"
  
  paramlist$s.lower <- -Inf # No corridor for AA
  paramlist$s.upper <- Inf
 
  paramlist$actuarial_method <- "EAN.CP" 
  
  paramlist$init_EAA <- "MA"

  
 # Economic assumption
  paramlist$infl <- 0.0275
  paramlist$prod <- 0.01
  paramlist$startingSal_growth <- paramlist$infl + paramlist$prod

  
 # Demographic
  paramlist$Grouping    <- "fillin"
  paramlist$newEnt_byTier <- c(tCD = 0, tE = 0.85, t3 = 0.15)

  paramlist$pct.ca.M <-  0.25 # proportion of males who opt for ca upon retirement
  paramlist$pct.ca.F <-  0.25
  
  
 
   
 # Investment returns
  paramlist$seed <- 1234


  # Parameters derived from the parameter list above. 
  paramlist$range_ea = with(Global_paramlist, min.ea:max.ea)
  paramlist$range_age = with(Global_paramlist, min.age:max.age)
  paramlist$range_age.r = with(paramlist, 25:r.max)
  paramlist$v     = with(paramlist, 1/(1 + i))
  
  

  if(paramlist$tier == "sumTiers"){
    source("PSERS_0_Master_allTiers.R")
    save(outputs_list, file = paste0(folder_save, "results_",  paramlist$tier, "_", runName, ".RData"))

  } else {
    Tier_select <- paramlist$tier
    source("PSERS_0_Master_singleTier.R")
    save(outputs_list, file = paste0(folder_save, "results_",  paramlist$tier, runName, ".RData"))
  }

}




