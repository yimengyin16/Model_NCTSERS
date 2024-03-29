# This script import demographic data of NCTSERS

# Data source: Data_inputs/NCTSERS_MemberData_2015.xlsx


# Output list
  # init_actives_all
  # init_retirees_all     
  # init_beneficiaries_all
  # init_disb_all         
  # init_terms_all

  # pct.male, pct.female

# Output file
  # Data_inputs/NCTSERS_MemberData.RData



#****************************************************************************************************
#                    Global constants ####
#****************************************************************************************************

file_memberData <- "Data_inputs/NCTSERS_MemberData_AV2015.xlsx"


#****************************************************************************************************
#                                       Tools                                                   #####                  
#****************************************************************************************************

# Utility functions
getcell <- function(file, sheet, cell) {
  require(XLConnect)
  value <- readWorksheetFromFile(file, sheet=sheet, header=FALSE, region=cell, colTypes="character")
  return(as.character(value))
}


xlrange <- function(file, sheet, cell1, cell2) {
  startcell <- getcell(file, sheet, cell1)
  endcell   <- getcell(file, sheet, cell2)
  range     <- paste0(startcell, ":", endcell)
  return(range)
}


get_bound <- function(range, bound = c("l","u")){
  # range must be in the form of "XX-YY", "X" is a single digit, and "XX" <= "YY".
  switch(bound,
         l =  str_extract(range, "\\d+-") %>% gsub("\\D+", "",.) %>% as.integer,
         u =  str_extract(range, "-\\d+") %>% gsub("\\D+", "",.) %>% as.integer)
}


# Load actives
import_actives <- function(file, sheet, planname){
#   

# file <- file_memberData
# sheet <- "Actives_t3"
# planname <- "Actives_t3"
# 
# getcell("Data_inputs/LAFPP_MemberData1.xlsx", "sheet1", "B2")
# read_excel(file, sheet = "TOC")



  range <- xlrange(file, sheet, "B2", "B3")
  
  df <- readWorksheetFromFile(file, sheet=sheet, header=TRUE, region=range, colTypes="character")
  
  yoscuts <- df %>% filter(type == "yosgrp") %>%
    select(starts_with("X")) %>%
    gather(yos.cell, yosgrp) %>%
    mutate(yos.cell=as.integer(gsub("[^0-9]", "", yos.cell)),
           yoslb = get_bound(yosgrp, "l"),
           yosub = get_bound(yosgrp, "u")) %>% 
    select(-yosgrp)
  yoscuts
  
  agecuts <- df %>% filter(type != "yosgrp") %>% 
             filter(type == unique(type)[1]) %>% 
             select(age.cell, agegrp) %>% 
             mutate(agelb = get_bound(agegrp, "l"),
                    ageub = get_bound(agegrp, "u")) %>% 
             select(-agegrp)
  agecuts
  
  
  df %<>% filter(type != "yosgrp") %>% 
         select(type, age.cell, starts_with("X")) %>%
         gather(yos.cell, value, -type, -age.cell) %>%
         mutate(yos.cell = as.integer(gsub("[^0-9]", "", yos.cell)),
                age.cell = as.integer(age.cell),
                value    = as.numeric(value),
                age = age.cell,
                yos = yos.cell,
                planname = planname) %>%
         filter(!is.na(value)) %>% 
         spread(type, value) %>%
         arrange(age.cell, yos.cell)
  
  
  lactives <- list()
  lactives$agecuts <- agecuts
  lactives$yoscuts <- yoscuts
  lactives$actives.yos <- df
  
  return(lactives)
}


# Load retirees, also can be used to load initial beneficiaries and initial disabled
import_retirees_byAge <- function(file, sheet, planname){

# file <- paste0(path, fileName)
# sheet <- "Beneficiaries"
# planname <- Tier_select


range <- xlrange(file, sheet, "B2", "B3")
benperiod <- getcell(file, sheet, "B4")
benmult <- ifelse(benperiod=="month", 12, 1)
name_N  <- getcell(file, sheet, "B5")
name_V  <- getcell(file, sheet, "B6")


df <- readWorksheetFromFile(file, sheet=sheet, header=TRUE, region=range, colTypes="character")

agecuts <- df %>%  
  select(age.cell, agegrp) %>% 
  mutate(agelb = get_bound(agegrp, "l"),
         ageub = get_bound(agegrp, "u")) %>% 
  select(-agegrp)

df %<>%  
  select(-agegrp) %>%
  colwise(as.numeric)() %>% 
  mutate(age.cell = as.integer(age.cell),
         age = age.cell,
         V = V * benmult,
         planname = planname)


list_out <- list()
list_out$data <- df
list_out$agecuts <- agecuts
list_out$varNames <- c(name_N = name_N, name_V = name_V)

return(list_out)
}


# Interpolation of actives
fillin.actives.spreadyos.splineage <- function(lactives) {
  # salary:
  #   first spread uniformly within age.cell-yos.cell group (same salary for all)
  #   then for every yos, estimate salary for each age using a spline - adjust endpoints first for plausibility
  #   finally, adjust resulting salary within each age.cell-yos.cell proportionately to hit total payroll values from grouped data
  #   then add ea to the data
  # nactives: spread uniformly within age.cell-yos.cell group (same nactives for all), then add ea to the data
  
  lactives
  
  adf <- lactives$actives.yos
  agecuts <- lactives$agecuts
  yoscuts <- lactives$yoscuts
  #eacuts <- lactives$eacuts
  minage <- min(agecuts$agelb)
  maxage <- max(agecuts$ageub)
  minyos <- min(yoscuts$yoslb)
  maxyos <- max(yoscuts$yosub)
  
  planname <- paste0(adf$planname[1])
  
  # adf %>% select(age, ea, salary) %>% spread(ea, salary)
  # adf %>% select(age, ea, nactives) %>% spread(ea, nactives)
  
  # create a master grouped data frame
  adf.g <- adf %>% select(-planname, -age, -yos, nactives.cell=nactives, salary.cell=salary) %>%
    mutate(pay.cell=nactives.cell * salary.cell) %>%
    mutate(ageidx = findInterval(age.cell, agecuts$agelb),
           age.lb = agecuts$agelb[ageidx],
           age.ub = agecuts$ageub[ageidx],
           yosidx = findInterval(yos.cell, yoscuts$yoslb),
           yos.lb = yoscuts$yoslb[yosidx],
           yos.ub = yoscuts$yosub[yosidx]) %>%
    select(age.cell, yos.cell, age.lb, age.ub, yos.lb, yos.ub, nactives.cell, salary.cell, pay.cell)
  
  # expand the grouped data frame to all allowable age-yos combinations ####
  xpnd <- function(df) {
    # expand to all age-yos combinations but only keep those where ea>=15 or, if there are no such records,
    # keep the recrods with max ea
    df2 <- expand.grid(age=df$age.lb:df$age.ub, yos=df$yos.lb:df$yos.ub) %>%
      mutate(ea=age - yos) %>%
      filter((ea >= 20) | (ea<20 & ea==max(ea))) %>%
      select(-ea)
    return(df2)
  }
  
  adf.x <- adf.g %>% rowwise() %>%
    do(cbind(., xpnd(.))) %>%
    ungroup %>%  # get rid of rowwise
    group_by(age.cell, yos.cell) %>%
    mutate(n.cell=n()) %>%
    select(age, yos, everything()) %>%
    arrange(age, yos)
  
  
  # work with the expanded data ####
  
  # we have to anchor the endpoints with reasonable values BEFORE computing the spline
  adjustends <- function(age, salary) {
    # the basic idea is that if an endpoint is NA, insert a plausible value
    
    # simple rule: if spline first or last value falls within +/ 50% of the nearest nonNA value, use spline estimate
    # otherwise use the capped value
    firstnonna <- salary[which.min(is.na(salary))]
    lastnonna <- rev(salary)[which.min(is.na(rev(salary)))]
    bound <- .5
    firstrange <- c(firstnonna * bound, firstnonna * (1 + bound))
    lastrange <- c(lastnonna * bound, lastnonna * (1 + bound))
    cap <- function(sal, range) {
      cappedval <- max(sal, range[1])
      cappedval <- min(cappedval, range[2])
      return(cappedval)
    }
    
    salary.est <- spline(age, salary, xout=age)$y # what does spline think naively?
    salary.adjusted <- salary
    
    if(is.na(salary[1])) salary.adjusted[1] <- cap(salary.est[1], firstrange)
    ilast <- length(salary)
    if(is.na(salary[ilast])) salary.adjusted[ilast] <- cap(salary.est[ilast], firstrange)
    
    return(salary.adjusted)
  }
  
  # test out adjustends
  # fs <- function(age, sal) return(spline(age, sal, xout=age)$y) # spline doesn't seem to work with dplyr if not in function
  # # various salaries to try out
  # salary <- seq(20, 50, length.out = 10)
  # salary <- c(20, NA, 30, NA, 40, NA, 50, NA, NA, 80)
  # salary <- c(20, NA, 30, NA, 40, NA, 50, NA, NA, 30)
  # salary <- c(NA, NA, 30, NA, 40, NA, 50, NA, NA, 30)
  # salary <- c(NA, NA, 30, NA, 40, NA, 50, NA, NA, NA)
  # salary <- c(NA, 10, 30, NA, 40, NA, 50, 80, NA, NA)
  # age <- 21:30
  # d <- data_frame(age, salary, saladj=adjustends(age, salary)) %>%
  #   mutate(sal.spline=fs(age, salary),
  #          saladj.spline=fs(age, saladj))
  # d
  # qplot(age, value, data=gather(d, variable, value, -age), colour=variable, geom=c("point", "line")) + scale_x_continuous(breaks=0:100) + geom_hline(y=0)
  
  
  spline.y2 <- function(age, salary, safesalary) {
    # safesalary is what we use if salary has no data
    if(all(is.na(salary))) {
      print("AllNA")
      salary <- safesalary
    }
    salary.adjusted <- adjustends(age, salary)
    
    sp.out <- spline(age, salary.adjusted, xout=age)
    salout <- sp.out$y
    return(salout)
  }
  
  adf.x3 <- adf.x %>% ungroup %>% # MUST be ungrouped or ifelse won't work if there is only one rec in a group
    mutate(nactives=nactives.cell / n.cell, # always spread nactives uniformly
           salary.group=ifelse(age==age.cell & yos==yos.cell, salary.cell, NA),
           salary.group=ifelse(salary.group==0, NA, salary.group),
           salary.agecell=ifelse(age==age.cell, salary.cell, NA)) %>% # Yimeng's first step
    group_by(yos) %>%
    arrange(age) %>%
    mutate(salary.spline.adjep=spline.y2(age, salary.agecell, salary.cell)) %>% # Yimeng's 2nd step with endpoint adjustment
    group_by(age.cell, yos.cell) %>%
    mutate(planname=planname,
           pay.unadj=sum(salary.spline.adjep * nactives),
           adjust=pay.cell / pay.unadj,
           salary.final=salary.spline.adjep * adjust,
           pay.adj=sum(salary.final * nactives),
           ea=age - yos
           #ea.cell=eacuts$stub[findInterval(ea, eacuts$lb)]
    )
  
  return(adf.x3)
}


# Interpolation of retirees
fillin.retirees <- function(list_data) {
  
  rdf <- select(list_data$data, planname, age, N, V) # keep only the vars we want
  agecuts <- list_data$agecuts
  
  planname <- paste0(rdf$planname[1], "_fillin")
  name_N <- list_data$varNames["name_N"]
  name_V <- list_data$varNames["name_V"]
  
  # add group ranges to the retirees data frame
  combo <- rdf %>%
    mutate(totben=N * V) %>%
    mutate(ageidx=findInterval(age, agecuts$agelb),
           age.lb=agecuts$agelb[ageidx],
           age.ub=agecuts$ageub[ageidx]) %>%
    arrange(age)
  
  # get avg benefits by age, via spline
  avgben <- splong(select(combo, age, V), "age", min(combo$age.lb):max(combo$age.ub))
  # force benefit to be non-negative DJB added 10/30/2015
  avgben <- avgben %>% mutate(V=ifelse(V<0, 0, V))
  
  guessdf <- data.frame(age=min(combo$age.lb):max(combo$age.ub)) %>%
    mutate(ageidx=findInterval(age, agecuts$agelb),
           age.cell=combo$age[match(ageidx, combo$ageidx)],
           N.cell=combo$N[match(ageidx, combo$ageidx)],
           V.cell=combo$V[match(ageidx, combo$ageidx)]) %>%
    group_by(age.cell) %>%
    mutate(n.cell=n(),
           N=N.cell / n.cell, # spread nretirees evenly
           adjV=avgben$V[match(age, avgben$age)], # get the spline-based avg benefit
           adjtotben=N * adjV)
  
  # refine the guess by adjusting ensure that we hit the right total benefits in each group
  guessdf2 <- guessdf %>% group_by(age.cell) %>%
    mutate(adjust=mean(N.cell * V.cell) / sum(adjtotben),
           V=adjV*adjust,
           totben=N * V)
  
  rdf.fillin <- guessdf2 %>% mutate(planname=planname) %>%
    select(planname, age.cell, age, N, V) %>%
    ungroup
  #plyr::rename(c("N" = list_data$varNames["name_N"])))
  
  names(rdf.fillin)[names(rdf.fillin) == "N"] <- name_N
  names(rdf.fillin)[names(rdf.fillin) == "V"] <- name_V
  
  return(rdf.fillin)
}




#*************************************************************************************************************
#                                       Importing Data for initial actives                               #####                  
#*************************************************************************************************************

fn_actives <- function(sheet, file_ = file_memberData){
  
  # path_ = path
  # fileName_ = fileName
  # Tier_select = "t76"
  
  lactives <- import_actives(file_, sheet, sheet)
  lactives$actives.yos %<>% filter(age - yos >= 20) # Will drop a small number of members, need to figure out how to add memebers with ea<20 back   
  
  actives_grouped <- lactives$actives.yos %>% select(planname, age, yos, nactives, salary) %>% 
    mutate(planname = paste0(planname, "_grouped"),
           ea = age - yos)
  
  actives_fillin  <- fillin.actives.spreadyos.splineage(lactives) %>% ungroup %>% 
    select(planname, age, yos, ea,
           #age.cell, yos.cell, 
           nactives, salary=salary.final) %>% 
    mutate(planname = paste0(planname, "_fillin"))
  
  actives_out <- bind_rows(actives_fillin, actives_grouped)
} 

# Import all actives 
init_actives_all <- fn_actives("Actives") %>% arrange(planname, ea, age) %>% 
  filter(planname == "Actives_fillin") %>% 
  mutate(planname = "Actives_t1_fillin")



# df_allTiers %>% filter(planname == "Actives_fillin") %>% 
#   summarise(sum(nactives),
#             sum(nactives*salary)/sum(nactives) )

# Note:
  # Range of age: 20 - 74




#*************************************************************************************************************
#                             Importing initial retirees                                         #####                  
#*************************************************************************************************************

fn_ret.ben <- function(sheet, fileName_){


  # fileName_ = fileName
  # Tier_select = "t76"

  ldata <- import_retirees_byAge(fileName_, sheet, sheet)

  df_grouped <- ldata$data %>% select(planname, age, N, V) %>% mutate(planname = paste0(planname, "_grouped"))
  names(df_grouped)[names(df_grouped) == "N"] <- ldata$varNames["name_N"]
  names(df_grouped)[names(df_grouped) == "V"] <- ldata$varNames["name_V"]

  df_fillin  <- fillin.retirees(ldata) %>% ungroup %>% select(-age.cell)

  df_out <- bind_rows(df_fillin, df_grouped)
}

# init_retirees_all      <- fn_ret.ben("Retirees_allTiers", file_memberData)
# init_beneficiaries_all <- fn_ret.ben("Beneficiaries_allTiers", file_memberData)
# init_disb_all          <- fn_ret.ben("Disb_allTiers", file_memberData)
#  
# init_retirees_all
# init_beneficiaries_all
# init_disb_all

init_retirees_all      <- read_ExcelRange(file_memberData, sheet = "Retirees",      "B2", "B3", colTypes="numeric") %>% select(-benefit.tot) %>% mutate(planname = "Retirees_t1_fillin")
init_beneficiaries_all <- read_ExcelRange(file_memberData, sheet = "Beneficiaries", "B2", "B3", colTypes="numeric") %>% select(-benefit.tot) %>% mutate(planname = "Beneficiaries_t1_fillin")
init_disb_all          <- read_ExcelRange(file_memberData, sheet = "Disabled",      "B2", "B3", colTypes="numeric") %>% select(-benefit.tot) %>% mutate(planname = "disb_t1_fillin")





#*************************************************************************************************************
#                             Importing initial vested terms                                             #####                  
#*************************************************************************************************************
 
get_init.terms.temp <- function(file, sheet, planname, cellStart = "B2", cellEnd = "B3"){

  # file <- file_memberData
  # sheet <-   "Other_t2"
  # planname <- "t2"
  # cellStart <- "B2"
  # cellEnd <- "B3"

  range <- xlrange(file, sheet, cellStart, cellEnd)

  df <- readWorksheetFromFile(file, sheet = sheet, header=TRUE, region= range, colTypes="character") %>%
    mutate(value = suppressWarnings(as.numeric(value)))
  df
  init_retirees <- data.frame(age = 30:49) %>%
    mutate(nterms = df[df$variable == "terms.n.tot", "value"]/n(),
           benefit.50   = 12 * df[df$variable == "terms.ben50.mon", "value"],
           planname = planname) %>%
    mutate_each(funs(na2zero), -planname, -age) %>%
    select(planname, everything())

}


init_terms_all <- read_ExcelRange(file_memberData, sheet = "Terms", "B2", "B3", colTypes="numeric") %>% select(-termCon.tot) %>% mutate(planname = "terms_t1_fillin")
init_terms_all


#*************************************************************************************************************
#                           Post processing to make data usable to the model                             #####                  
#*************************************************************************************************************
# Assume all terms have the same entry age of 20
init_terms_all %<>% mutate(ea = 20) 



#*************************************************************************************************************
#     Gender and occupation(general, teacher, other edu, law enforcement) distribuitons                 #####                  
#*************************************************************************************************************
# Gender distribution is required to calculate weighted average mortality
# occupation distribution is required to calculate weighted average retirement rates, term rates, and disability rates.  

# occupation distribution 
# pct.male   <- 71145/259868
# pct.female <-  1 - pct.male
# 
occupGender <- read_ExcelRange(file_memberData, sheet = "prop.occupation", "B2", "B3")
#occupGender


## Assumptions on gender ratio for each occupation

 # 1. Assume overall gender ratio for all member types is M:F = 0.31:0.69
 # 2. Predetermined gender ratio for tch, edu, and law:
   # tch/edu: M:0.25   (Ref: UCRP actives M:0.396; TPAF actives M:0.234) 
   # law:     M:0.95   (Ref: LAFPP M:0.95)
   # gen: calculated: 

occupGender %<>% 
  mutate(ntot = tch + edu + gen + law,
         
         pct.tch = tch / ntot,
         pct.edu = edu / ntot,
         pct.law = law / ntot,
         pct.gen = gen / ntot,
    
         pct.male.all = 0.31,
         pct.male.tch = 0.25,
         pct.male.edu = 0.25,
         pct.male.law = 0.95,
         pct.male.gen = ((tch + edu + gen + law) * pct.male.all - tch * pct.male.tch - edu * pct.male.edu - law * pct.male.law)/gen,
         
         pct.female.all = 1 - pct.male.all,
         pct.female.tch = 1 - pct.male.tch,
         pct.female.edu = 1 - pct.male.edu,
         pct.female.law = 1 - pct.male.law,
         pct.female.gen = 1 - pct.male.gen,
         
         share.tch.male   = pct.tch * pct.male.tch,
         share.tch.female = pct.tch * pct.female.tch,
         share.edu.male   = pct.edu * pct.male.edu,
         share.edu.female = pct.edu * pct.female.edu,
         share.law.male   = pct.law * pct.male.law,
         share.law.female = pct.law * pct.female.law,
         share.gen.male   = pct.gen * pct.male.gen,
         share.gen.female = pct.gen * pct.female.gen
         )

rownames(occupGender) <- occupGender$type



save(init_actives_all, 
     init_retirees_all, 
     init_beneficiaries_all, 
     init_disb_all, 
     init_terms_all,
     occupGender,
     file = "Data_inputs/NCTSERS_MemberData_AV2015.RData")






