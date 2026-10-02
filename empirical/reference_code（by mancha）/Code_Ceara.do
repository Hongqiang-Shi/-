*********************************************************************************
*                 REPLICATION PACKAGE - CEARA                 *
********************************************************************************


* Setting Working Directories
clear all

global data "YOUR WORKING DIRECTORY\Bases"

global outputs "YOUR WORKING DIRECTORY\Outputs"


* Install packages and scheme for plots
ssc install reghdfe, replace
ssc install ftools, replace
ssc install schemepack, replace
ssc install ppmlhdfe, replace
ssc install coefplot, replace
ssc install  did_multiplegt_dyn, replace 
set scheme white_tableau



***************************************************************************************************************************
*** Baseline Regression ***

clear

// Data manually dowloaded and organized from pdfs released by SSPDS-CE
import excel "$data\Painel.xlsx", firstrow

gen WEEKDAY = dow(DATE)
destring AGE, replace force

gen daily_homicides_men = 0
replace daily_homicides_men = HOMICIDIOS if GENDER == "M" | GENDER == "Masculino" | GENDER == "MASCULINO"

gen daily_homicides_firearms = 0
replace daily_homicides_firearms = HOMICIDIOS if WEAPON =="ARAMA DE FOGO" | WEAPON =="ARAM ADE FOGO"| ///
						WEAPON =="ARM DE FOGO" | WEAPON =="ARMA  DE FOGO"| ///
						WEAPON =="ARM D FOGO" |WEAPON =="ARMA DE FOGO"| ///
						WEAPON =="ARMA DE FOGO E ARM" |WEAPON =="ARMA DE FOGO E BRANCA"| ///
						WEAPON =="ARMA FOGO" |WEAPON =="ARMADE FOGO"| ///
						WEAPON =="Arma de Fogo" |WEAPON =="Arma de fogo"


gen daily_homicides_white_arms = 0
replace daily_homicides_white_arms = HOMICIDIOS if WEAPON =="ARAMA BRANCA" | WEAPON =="ARAMA DE BRANCA"| ///
						WEAPON =="ARMA BRANCA" | WEAPON =="Arma Branca"| ///
						WEAPON =="Arma branca"

gen daily_homicides_young = 0
replace daily_homicides_young = HOMICIDIOS if AGE < 16

gen daily_homicides_adult = 0
replace daily_homicides_adult= HOMICIDIOS if AGE > 15 & AGE < 26

gen daily_homicides_adult2 = 0
replace daily_homicides_adult2= HOMICIDIOS if AGE > 25 & AGE < 46

gen daily_homicides_old = 0
replace daily_homicides_old= HOMICIDIOS if AGE > 45

gen daily_homicides_no_id = 0
replace daily_homicides_no_id= HOMICIDIOS if AGE ==.


collapse (sum) HOMICIDIOS crime_1 crime_2 crime_3 crime_4 daily_homicides_men-daily_homicides_no_id, /// 
	by(AIS CITY YEAR MONTH DATE WEEKDAY)

gen militar = 0
replace militar = 1 if DATE > td(17feb2020)
replace militar = 0 if DATE > td(01mar2020)


***************************************************************************************************************************

*** Data Analysis and Regression ***


drop if AIS == "99" |AIS == "AIS NÃO DEFINIDA"| AIS == "Acidente de Trânsito"| AIS == "UNIDADE PRISIONAL"| AIS == "UNIDADE PRISONAL"| AIS == "Unidade Prisional"

replace AIS = "AIS 01" if AIS == "AIS 1"
replace AIS = "AIS 02" if AIS == "AIS 2"
replace AIS = "AIS 03" if AIS == "AIS 3"
replace AIS = "AIS 04" if AIS == "AIS 4"
replace AIS = "AIS 05" if AIS == "AIS 5"
replace AIS = "AIS 06" if AIS == "AIS 6"
replace AIS = "AIS 07" if AIS == "AIS 7"
replace AIS = "AIS 08" if AIS == "AIS 8"
replace AIS = "AIS 09" if AIS == "AIS 9"

replace AIS = ustrlower(ustrregexra(ustrnormalize(AIS, "nfd" ) , "\p{Mark}", "" ) )
replace CITY = ustrlower(ustrregexra(ustrnormalize(CITY, "nfd" ) , "\p{Mark}", "" ) )

replace CITY = "itapaje" if CITY == "itapage"
replace CITY = "juazeiro do norte" if CITY == "juazeiro do"
replace CITY = "lavras da mangabeira" if CITY == "lavras da mangabeira homicidio doloso"
replace CITY = "quixeramobim" if CITY == "quixeramobim  homicidio doloso"
replace CITY = "sao luis do curu" if CITY == "sao luis do curu  homicidio doloso"
replace CITY = "senador pompeu" if CITY == "senador pompeu homicidio doloso" | CITY == "senador pompeu  homicidio doloso"| CITY == "senador sa" 
replace CITY = "tabuleiro do norte" if CITY == "tabuleiro do"

gen id_code = AIS + "_" + CITY

encode AIS, gen (id_ais)
encode id_code, gen (id_code2)

rename HOMICIDIOS daily_homicides
rename YEAR year
rename MONTH month
rename WEEKDAY weekday

gen daily_homicides_women = daily_homicides - daily_homicides_men

ttest daily_homicides, by(militar)
ttest daily_homicides_firearms, by(militar)

save "$data\Daily_Homicides_CE.dta", replace


/// Histogram

preserve
	
collapse(sum) daily_homicides crime_1, by(AIS militar)

gen prop_criminals = crime_1/daily_homicides
tab prop_criminals

twoway (histogram prop_criminals if militar==0, freq bin(22) start(0) color(orange%30)) ///        
       (histogram prop_criminals if militar==1, freq bin(22) start(0)  color(blue%30)), ///   
       legend(pos(6) col(2) order(1 "Non-strike" 2 "Strike" )) xtitle("Suspected Criminals Deaths / Total Homicides")
	   
restore

	   

/// Descriptive Statistics

	tabulate AIS militar, summarize(daily_homicides)
	tabulate AIS militar, summarize(daily_homicides_men)
	tabulate AIS militar, summarize(daily_homicides_women)
	tabulate AIS militar, summarize(daily_homicides_young)
	tabulate AIS militar, summarize(daily_homicides_adult)
	tabulate AIS militar, summarize(daily_homicides_adult2)
	tabulate AIS militar, summarize(daily_homicides_old)


***************************************************************************************************************************

*** Indentifying Gang Turfs - Treatment Group ***

/// By number of Gang Turfs

preserve

clear

// Data manually organized from the Civil Police transcripts released in the mecia
import excel "$data\Gang_Turfs.xlsx", sheet("Gang_Turfs") firstrow

// Highlight Median and Top Quartile

summarize ExposureDistricts, detail

local p50 = r(p50)
local p75 = r(p75)

dis `p50'
dis `p75'


// Plot of Exposure wiht Median and Quartiles

scatter GangDistricts ExposureDistricts, ///
    mcolor(blue) ///
    mlab(AIS) ///
	xline(`p50', lcolor(orange)) ///
	xline(`p75', lp(shortdash_dot) lcolor(red)) ///
    ytitle("Gang Districts") ///
    xtitle("Exposure (%)") ///
    legend(off)

graph export "$outputs\gang_districts.png", as(png) name("Graph")  replace
	

restore

/// By Population living in Gang Turfs

preserve

clear

// Data manually organized from the Civil Police transcripts released in the mecia
import excel "$data\Gang_Turfs.xlsx", sheet("Gang_Turfs") firstrow

// Highlight Median and Top Quartile

summarize ExposurePop, detail

local p50 = r(p50)
local p75 = r(p75)

dis `p50'
dis `p75'


// Plot of Exposure wiht Median and Quartiles

scatter GangDistricts ExposurePop, ///
    mcolor(blue) ///
    mlab(AIS) ///
	xline(`p50', lcolor(orange)) ///
	xline(`p75', lp(shortdash_dot) lcolor(red)) ///
    ytitle("Gang Districts") ///
    xtitle("Exposure (%)") ///
    legend(off)

graph export "$outputs\gang_districts_pop.png", as(png) name("Graph")  replace
	

restore



*** Districts of the Treatment Group - First Specification: Top Quartile ***

preserve

gen d_treat = 0
replace d_treat = 1 if AIS == "ais 02" |AIS == "ais 06" | AIS == "ais 11" |AIS == "ais 12" | AIS == "AIS 13"

gen militar_treat = militar*d_treat

* Descriptive Statistics *
tabulate d_treat militar, summarize(daily_homicides)

* Balancing the Panel *
duplicates drop id_code2 DATE, force
tsset id_code2 DATE
tsfill, full

xtset id_code2 DATE

foreach v of varlist daily_homicides_women daily_homicides daily_homicides_adult daily_homicides_adult2 daily_homicides_men daily_homicides_firearms daily_homicides_old daily_homicides_young {

replace `v'=0 if `v'==.	

}

replace year = year(DATE) if year ==.
replace month = month(DATE) if month ==.
replace weekday = dow(DATE) if weekday ==.

gen ais_year = id_ais*year


* Total Homicides *
qui bootstrap, rep(999) cl(id_ais) idcl(new_id_ais) group(id_code2): reghdfe daily_homicides  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara.xls", replace ctitle(Total Homicides) label 
estimates store ceara_total

qui bootstrap, rep(999) cl(id_ais) idcl(new_id_ais) group(id_code2): reghdfe daily_homicides_men  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara.xls", append ctitle(Homicides (Men)) label 
estimates store ceara_men

qui bootstrap, rep(999) cl(id_ais) idcl(new_id_ais) group(id_code2): reghdfe daily_homicides_women  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara.xls", append ctitle(Homicides (Women)) label 
estimates store ceara_women

qui bootstrap, rep(999) cl(id_ais) idcl(new_id_ais) group(id_code2): reghdfe daily_homicides_firearms  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara.xls", append ctitle(Homicides (Firearms)) label 


qui bootstrap, rep(999) cl(id_ais) idcl(new_id_ais) group(id_code2): reghdfe daily_homicides_young  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara.xls", append ctitle(Homicides (0-15)) label 

qui bootstrap, rep(999) cl(id_ais) idcl(new_id_ais) group(id_code2): reghdfe daily_homicides_adult  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara.xls", append ctitle(Homicides (15-25)) label

qui bootstrap, rep(999) cl(id_ais) idcl(new_id_ais) group(id_code2): reghdfe daily_homicides_adult2  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara.xls", append ctitle(Homicides (25-45)) label 

qui bootstrap, rep(999) cl(id_ais) idcl(new_id_ais) group(id_code2): reghdfe daily_homicides_old  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara.xls", append ctitle(Homicides (> 45)) label 


qui bootstrap, rep(999) cl(id_ais) idcl(new_id_ais) group(id_code2): reghdfe crime_1  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara.xls", append ctitle(Suspected I) label 

qui bootstrap, rep(999) cl(id_ais) idcl(new_id_ais) group(id_code2): reghdfe crime_2 militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara.xls", append ctitle(Suspected II) label 

qui bootstrap, rep(999) cl(id_ais) idcl(new_id_ais) group(id_code2): reghdfe crime_3  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara.xls", append ctitle(Suspected III) label 

qui bootstrap, rep(999) cl(id_ais) idcl(new_id_ais) group(id_code2): reghdfe crime_4  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara.xls", append ctitle(Suspected IV) label 

qui bootstrap, rep(999) cl(id_ais) idcl(new_id_ais) group(id_code2): reghdfe crime_5  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara.xls", append ctitle(Suspected V) label 



* Baseline Coefplot *
label variable militar "PM_strike"
label variable militar_treat "PM_strike*Gang_Turfs"

coefplot ceara_total, bylabel(Total) || ceara_men, bylabel(Homicides - Men) || ceara_women, bylabel(Homicides - Women) ||, keep(militar militar_treat) xline(0) ciopts(recast(rcap)) byopts(row(1) xrescale)
graph export "$outputs\coefplot_top_quartile.png", as(png) name("Graph")  replace	


* Graph Parallel Trend *
gen date2 = qofd(DATE)
format date2 %tq

separate daily_homicides, by(d_treat)
collapse(mean) daily_homicides?, by(d_treat date2)

graph twoway connect daily_homicides? date2, ///
	sort legend(pos(6) col(2) label(1 "Control Districts") label(2 "Gang Districts")) ///
	ytitle("Homicides") ///
	xtitle("Quarter") ///
	tline(2016q1, lpattern(dash)) ///
	tline(2019q4, lpattern(dash))

graph export "$outputs\trends_top_quartile.png", as(png) name("Graph")  replace	
	
restore


*** Districts of the Treatment Group - Second Specification: Above Median ***

preserve

gen d_treat = 0
replace d_treat = 1 if AIS == "ais 02" |AIS == "ais 05" |AIS == "ais 06" | AIS == "ais 07" |AIS == "ais 08" |AIS == "ais 11" |AIS == "ais 12" | AIS == "AIS 13"| AIS == "ais 14" | AIS == "ais 17"

gen militar_treat = militar*d_treat

* Descriptive Statistics *
tabulate d_treat militar, summarize(daily_homicides)

* Balancing the Panel *
duplicates drop id_code2 DATE, force
tsset id_code2 DATE
tsfill, full

xtset id_code2 DATE

foreach v of varlist daily_homicides_women daily_homicides daily_homicides_adult daily_homicides_adult2 daily_homicides_men daily_homicides_firearms daily_homicides_old daily_homicides_young {

replace `v'=0 if `v'==.	

}

replace year = year(DATE) if year ==.
replace month = month(DATE) if month ==.
replace weekday = dow(DATE) if weekday ==.

gen ais_year = id_ais*year

reghdfe daily_homicides  militar militar_treat, a(id_code2 id_ais year month weekday) vce(cl id_ais)

reghdfe daily_homicides  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)


* Total Homicides *
qui bootstrap, rep(999) cl(id_ais) idcl(new_id_ais) group(id_code2): reghdfe daily_homicides  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara2.xls", replace ctitle(Total Homicides) label 
estimates store ceara_total

qui bootstrap, rep(999) cl(id_ais) idcl(new_id_ais) group(id_code2): reghdfe daily_homicides_men  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara2.xls", append ctitle(Homicides (Men)) label 
estimates store ceara_men

qui bootstrap, rep(999) cl(id_ais) idcl(new_id_ais) group(id_code2): reghdfe daily_homicides_women  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara2.xls", append ctitle(Homicides (Women)) label 

qui bootstrap, rep(999) cl(id_ais) idcl(new_id_ais) group(id_code2): reghdfe daily_homicides_firearms  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara2.xls", append ctitle(Homicides (Firearms)) label 
estimates store ceara_women

qui bootstrap, rep(999) cl(id_ais) idcl(new_id_ais) group(id_code2): reghdfe daily_homicides_young  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara2.xls", append ctitle(Homicides (0-15)) label 

qui bootstrap, rep(999) cl(id_ais) idcl(new_id_ais) group(id_code2): reghdfe daily_homicides_adult  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara2.xls", append ctitle(Homicides (15-25)) label

qui bootstrap, rep(999) cl(id_ais) idcl(new_id_ais) group(id_code2): reghdfe daily_homicides_adult2  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara2.xls", append ctitle(Homicides (25-45)) label 

qui bootstrap, rep(999) cl(id_ais) idcl(new_id_ais) group(id_code2): reghdfe daily_homicides_old  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara2.xls", append ctitle(Homicides (> 45)) label 


qui bootstrap, rep(999) cl(id_ais) idcl(new_id_ais) group(id_code2): reghdfe crime_1  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara2.xls", append ctitle(Suspected I) label 

qui bootstrap, rep(999) cl(id_ais) idcl(new_id_ais) group(id_code2): reghdfe crime_2 militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara2.xls", append ctitle(Suspected II) label 

qui bootstrap, rep(999) cl(id_ais) idcl(new_id_ais) group(id_code2): reghdfe crime_3  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara2.xls", append ctitle(Suspected III) label 

qui bootstrap, rep(999) cl(id_ais) idcl(new_id_ais) group(id_code2): reghdfe crime_4  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara2.xls", append ctitle(Suspected IV) label 

qui bootstrap, rep(999) cl(id_ais) idcl(new_id_ais) group(id_code2): reghdfe crime_5 militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara2.xls", append ctitle(Suspected V) label 


* Baseline Coefplot *
coefplot ceara_total, bylabel(Total) || ceara_men, bylabel(Homicides - Men) || ceara_women, bylabel(Homicides - Women) ||, keep(militar militar_treat) xline(0) ciopts(recast(rcap)) byopts(row(1) xrescale)
graph export "$outputs\coefplot_median.png", as(png) name("Graph")  replace	


* Graph Parallel Trend *
gen date2 = qofd(DATE)
format date2 %tq

separate daily_homicides, by(d_treat)
collapse(mean) daily_homicides?, by(d_treat date2)

graph twoway connect daily_homicides? date2, ///
	sort legend(position(6) col(2) label(1 "Control Districts") label(2 "Gang Districts")) ///
	ytitle("Homicides") ///
	xtitle("Quarter") ///
	tline(2016q1, lpattern(dash)) ///
	tline(2019q4, lpattern(dash))

graph export "$outputs\trends_median.png", as(png) name("Graph")  replace	
	
restore



*** Districts of the Treatment Group - Third Specification: Top Quartile Population ***

preserve

gen d_treat = 0
replace d_treat = 1 if AIS == "ais 02" |AIS == "ais 06" | AIS == "ais 11" | AIS == "AIS 13"

gen militar_treat = militar*d_treat

* Descriptive Statistics *
tabulate d_treat militar, summarize(daily_homicides)

* Balancing the Panel *
duplicates drop id_code2 DATE, force
tsset id_code2 DATE
tsfill, full

xtset id_code2 DATE

foreach v of varlist daily_homicides_women daily_homicides daily_homicides_adult daily_homicides_adult2 daily_homicides_men daily_homicides_firearms daily_homicides_old daily_homicides_young {

replace `v'=0 if `v'==.	

}

replace year = year(DATE) if year ==.
replace month = month(DATE) if month ==.
replace weekday = dow(DATE) if weekday ==.

gen ais_year = id_ais*year


* Total Homicides *
reghdfe daily_homicides  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara4.xls", replace ctitle(Total Homicides) label 
estimates store ceara_total

reghdfe daily_homicides_men  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara4.xls", append ctitle(Homicides (Men)) label 
estimates store ceara_men

reghdfe daily_homicides_women  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara4.xls", append ctitle(Homicides (Women)) label 
estimates store ceara_women

reghdfe daily_homicides_firearms  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara4.xls", append ctitle(Homicides (Firearms)) label 


reghdfe daily_homicides_young  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara4.xls", append ctitle(Homicides (0-15)) label 

reghdfe daily_homicides_adult  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara4.xls", append ctitle(Homicides (15-25)) label

reghdfe daily_homicides_adult2  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara4.xls", append ctitle(Homicides (25-45)) label 

reghdfe daily_homicides_old  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara4.xls", append ctitle(Homicides (> 45)) label 


reghdfe crime_1  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara4.xls", append ctitle(Suspected I) label 

reghdfe crime_2 militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara4.xls", append ctitle(Suspected II) label 

reghdfe crime_3  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara4.xls", append ctitle(Suspected III) label 

reghdfe crime_4  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara4.xls", append ctitle(Suspected IV) label 



* Baseline Coefplot *
label variable militar "PM_strike"
label variable militar_treat "PM_strike*Gang_Turfs"

coefplot ceara_total, bylabel(Total) || ceara_men, bylabel(Homicides - Men) || ceara_women, bylabel(Homicides - Women) ||, keep(militar militar_treat) xline(0) ciopts(recast(rcap)) byopts(row(1) xrescale)
graph export "$outputs\coefplot_top_quartile2.png", as(png) name("Graph")  replace	


* Graph Parallel Trend *
gen date2 = qofd(DATE)
format date2 %tq

separate daily_homicides, by(d_treat)
collapse(mean) daily_homicides?, by(d_treat date2)

graph twoway connect daily_homicides? date2, ///
	sort legend(pos(6) col(2) label(1 "Control Districts") label(2 "Gang Districts")) ///
	ytitle("Homicides") ///
	xtitle("Quarter") ///
	tline(2016q1, lpattern(dash)) ///
	tline(2019q4, lpattern(dash))

graph export "$outputs\trends_top_quartile2.png", as(png) name("Graph")  replace	
	
restore


*** Districts of the Treatment Group - Fourth Specification: Above Median ***

preserve

gen d_treat = 0
replace d_treat = 1 if AIS == "ais 02" |AIS == "ais 06" | AIS == "ais 07" |AIS == "ais 08" |AIS == "ais 11" |AIS == "ais 12" | AIS == "AIS 13"| AIS == "ais 14" | AIS == "ais 17"

gen militar_treat = militar*d_treat

* Descriptive Statistics *
tabulate d_treat militar, summarize(daily_homicides)

* Balancing the Panel *
duplicates drop id_code2 DATE, force
tsset id_code2 DATE
tsfill, full

xtset id_code2 DATE

foreach v of varlist daily_homicides_women daily_homicides daily_homicides_adult daily_homicides_adult2 daily_homicides_men daily_homicides_firearms daily_homicides_old daily_homicides_young {

replace `v'=0 if `v'==.	

}

replace year = year(DATE) if year ==.
replace month = month(DATE) if month ==.
replace weekday = dow(DATE) if weekday ==.

gen ais_year = id_ais*year

reghdfe daily_homicides  militar militar_treat, a(id_code2 id_ais year month weekday) vce(cl id_ais)

reghdfe daily_homicides  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)


* Total Homicides *
 reghdfe daily_homicides  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara3.xls", replace ctitle(Total Homicides) label 
estimates store ceara_total

 reghdfe daily_homicides_men  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara3.xls", append ctitle(Homicides (Men)) label 
estimates store ceara_men

 reghdfe daily_homicides_women  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara3.xls", append ctitle(Homicides (Women)) label 

 reghdfe daily_homicides_firearms  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara3.xls", append ctitle(Homicides (Firearms)) label 
estimates store ceara_women

 reghdfe daily_homicides_young  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara3.xls", append ctitle(Homicides (0-15)) label 

 reghdfe daily_homicides_adult  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara3.xls", append ctitle(Homicides (15-25)) label

 reghdfe daily_homicides_adult2  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara3.xls", append ctitle(Homicides (25-45)) label 

 reghdfe daily_homicides_old  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara3.xls", append ctitle(Homicides (> 45)) label 


 reghdfe crime_1  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara3.xls", append ctitle(Suspected I) label 

 reghdfe crime_2 militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara3.xls", append ctitle(Suspected II) label 

 reghdfe crime_3  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara3.xls", append ctitle(Suspected III) label 

 reghdfe crime_4  militar militar_treat, a(id_code2 ais_year month weekday) vce(cl id_ais)
outreg2 using "$outputs\table_ceara3.xls", append ctitle(Suspected IV) label 



* Baseline Coefplot *
coefplot ceara_total, bylabel(Total) || ceara_men, bylabel(Homicides - Men) || ceara_women, bylabel(Homicides - Women) ||, keep(militar militar_treat) xline(0) ciopts(recast(rcap)) byopts(row(1) xrescale)
graph export "$outputs\coefplot_median2.png", as(png) name("Graph")  replace	


* Graph Parallel Trend *
gen date2 = qofd(DATE)
format date2 %tq

separate daily_homicides, by(d_treat)
collapse(mean) daily_homicides?, by(d_treat date2)

graph twoway connect daily_homicides? date2, ///
	sort legend(position(6) col(2) label(1 "Control Districts") label(2 "Gang Districts")) ///
	ytitle("Homicides") ///
	xtitle("Quarter") ///
	tline(2016q1, lpattern(dash)) ///
	tline(2019q4, lpattern(dash))

graph export "$outputs\trends_median2.png", as(png) name("Graph")  replace	
	
restore




****** (Robustness) Districts of the Treatment Group - Random Assignment ******

* Example of Random assignment *

preserve

set seed 123456			// Random treated units
gen random= uniform()
gen byte treat = 0

sort DATE random
by DATE: replace treat = (_n <=4) if (DATE == date("01012014","DMY"))

sort id_ais DATE
by id_ais: replace treat=treat[_n-1] if (DATE > date("01012014","DMY"))

*replace daily_homicides_adult = daily_homicides_adult + daily_homicides_adult2

// Auxiliary Dummies
gen militar_treat = militar*treat
gen ais_year = id_ais*year


* Descriptive Statistics *
tabulate treat militar, summarize(daily_homicides)

* Total Homicides *
qui reghdfe daily_homicides militar militar_treat , ///
	absorb(id_code2 ais_year month weekday) /* All FE */
outreg2 using "$outputs\random_treat_ceara.xls", replace ctitle(Total Homicides) label 

qui reghdfe daily_homicides_men  militar militar_treat , ///
	absorb(id_code2 ais_year month weekday) /* All FE */
outreg2 using "$outputs\random_treat_ceara.xls", append ctitle(Homicides (Men)) label 

qui reghdfe daily_homicides_women  militar militar_treat , ///
	absorb(id_code2 ais_year month weekday) /* All FE */
outreg2 using "$outputs\random_treat_ceara.xls", append ctitle(Homicides (Women)) label 

qui reghdfe daily_homicides_firearms  militar militar_treat , ///
	absorb(id_code2 ais_year month weekday) /* All FE */
outreg2 using "$outputs\random_treat_ceara.xls", append ctitle(Homicides (Firearms)) label 


qui reghdfe daily_homicides_young  militar militar_treat , ///
	absorb(id_code2 ais_year month weekday) /* All FE */
outreg2 using "$outputs\random_treat_ceara.xls", append ctitle(Homicides (0-15)) label 

qui reghdfe daily_homicides_adult  militar militar_treat , ///
	absorb(id_code2 ais_year month weekday) /* All FE */
outreg2 using "$outputs\random_treat_ceara.xls", append ctitle(Homicides (15-25)) label 

qui reghdfe daily_homicides_adult  militar militar_treat , ///
	absorb(id_code2 ais_year month weekday) /* All FE */
outreg2 using "$outputs\random_treat_ceara.xls", append ctitle(Homicides (25-45)) label 

qui reghdfe daily_homicides_old  militar militar_treat , ///
	absorb(id_code2 ais_year month weekday) /* All FE */
outreg2 using "$outputs\random_treat_ceara.xls", append ctitle(Homicides (> 45)) label 

* Graph Parallel Trend *
gen date2 = qofd(DATE)
format date2 %tq

separate daily_homicides, by(treat)
collapse(mean) daily_homicides?, by(treat date2)

graph twoway connect daily_homicides? date2, ///
	sort legend(pos(6) col(2) label(1 "Control Districts") label(2 "Gang Districts")) ///
	ytitle("Homicides") ///
	xtitle("Quarter") ///
	tline(2016q1, lpattern(dash))

graph export "$outputs\trends_placebo.png", as(png) name("Graph")  replace	
	
* Randomization of all possible units *	

ritest d_treat _b[c.d_treat#c.militar], cluster(id_ais) kdensityplot reps(1000): reghdfe daily_homicides c.d_treat##c.militar, abs(id_code2 ais_year month weekday)


restore



***************************************************************************************************************************

***** Event Study Militar Police Strike ******

preserve

gen d_treat = 0
replace d_treat = 1 if AIS == "ais 02" |AIS == "ais 06" | AIS == "ais 11" |AIS == "ais 12" | AIS == "AIS 13"

gen militar_treat = militar*d_treat

* Descriptive Statistics *
tabulate d_treat militar, summarize(daily_homicides)

* Balancing the Panel *
duplicates drop id_code2 DATE, force
tsset id_code2 DATE
tsfill, full

xtset id_code2 DATE

gen daily_homicides_others = daily_homicides - crime_1

foreach v of varlist daily_homicides_women daily_homicides daily_homicides_adult daily_homicides_adult2 daily_homicides_men daily_homicides_firearms daily_homicides_old daily_homicides_young daily_homicides_others {

replace `v'=0 if `v'==.

}

replace year = year(DATE) if year ==.
replace month = month(DATE) if month ==.
replace weekday = dow(DATE) if weekday ==.

gen ais_year = id_ais*year


gen timeToTreat = .
replace timeToTreat= -9 if DATE == date("07022020","DMY") & d_treat == 1
replace timeToTreat= -8 if DATE == date("08022020","DMY") & d_treat == 1
replace timeToTreat= -7 if DATE == date("09022020","DMY") & d_treat == 1
replace timeToTreat= -6 if DATE == date("10022020","DMY") & d_treat == 1
replace timeToTreat= -5 if DATE == date("11022020","DMY") & d_treat == 1
replace timeToTreat= -4 if DATE == date("13022020","DMY") & d_treat == 1
*replace timeToTreat= -4 if DATE == date("14022020","DMY") & d_treat ==  (no variation for this lag)
replace timeToTreat= -3 if DATE == date("15022020","DMY") & d_treat == 1
replace timeToTreat= -2 if DATE == date("16022020","DMY") & d_treat == 1
replace timeToTreat= -1 if DATE == date("17022020","DMY") & d_treat == 1
replace timeToTreat= 0 if DATE == date("18022020","DMY") & d_treat == 1
replace timeToTreat= 1 if DATE == date("19022020","DMY") & d_treat == 1
replace timeToTreat= 2 if DATE == date("20022020","DMY") & d_treat == 1
replace timeToTreat= 3 if DATE == date("21022020","DMY") & d_treat == 1
replace timeToTreat= 4 if DATE == date("22022020","DMY") & d_treat == 1
replace timeToTreat= 5 if DATE == date("23022020","DMY") & d_treat == 1
replace timeToTreat= 6 if DATE == date("24022020","DMY") & d_treat == 1
replace timeToTreat= 7 if DATE == date("25022020","DMY") & d_treat == 1
replace timeToTreat= 8 if DATE == date("26022020","DMY") & d_treat == 1
replace timeToTreat= 9 if DATE == date("27022020","DMY") & d_treat == 1
replace timeToTreat= 10 if DATE == date("28022020","DMY") & d_treat == 1
			
eventdd daily_homicides, hdfe timevar(timeToTreat) ci(rcap) absorb(i.id_code2 i.ais_year i.month i.weekday) inrange lags(9) leads(9) noline graph_op(ytitle("Daily Homicides") xlabel(-12(2)12) leg(off))
graph export "$outputs\event_study_AIS.png", as(png) name("Graph") replace
estimates store strike_uf

qui eventdd crime_1, hdfe timevar(timeToTreat) ci(rcap) absorb(i.id_code2 i.ais_year i.month i.weekday) inrange lags(9) leads(9) noline graph_op(ytitle("Daily Homicides") xlabel(-12(2)12))
estimates store strike_uf2

qui eventdd daily_homicides_others, hdfe timevar(timeToTreat) ci(rcap) absorb(i.id_code2 i.ais_year i.month i.weekday) inrange lags(9) leads(9) noline graph_op(ytitle("Daily Homicides") xlabel(-12(2)12))
estimates store strike_uf3
		
coefplot (strike_uf2, offset(0.50)) (strike_uf3, offset(0.005)), vertical keep(lead10 lead9 lead8 lead7 lead6 lead5 lead4 lead3 lead2 lead1 lag0 lag1 lag2 lag3 lag4 lag5 lag6 lag7 lag8 lag9 lag10) yline(0, lpattern(dash)) xline(10, lpattern(dash))
	
restore



****** (Robustness) Testing the French Estimator ******

preserve

gen d_treat = 0
replace d_treat = 1 if AIS == "ais 02" |AIS == "ais 06" | AIS == "ais 11" |AIS == "ais 12" | AIS == "AIS 13"

gen militar_treat = militar*d_treat

* Balancing the Panel *
duplicates drop id_code2 DATE, force
tsset id_code2 DATE
tsfill, full

xtset id_code2 DATE

replace year = year(DATE) if year ==.
replace month = month(DATE) if month ==.
replace weekday = dow(DATE) if weekday ==.

gen ais_year = id_ais*year

/// Estimates
drop if DATE < td(01feb2020)
drop if DATE > td(01apr2020)
replace militar_treat = 0 if militar_treat ==.

did_multiplegt_dyn daily_homicides id_code2 DATE militar_treat, effects(7) placebo(7) cluster(id_code2)

graph export "$outputs\did_multiplegt_dyn_ceara.png", as(png) name("Graph")  replace	

restore




***************************************************************************************************************************

***** Property Violent Crime (Robbery) *****

clear

// Data manually dowloaded and organized from pdfs released by SSPDS-CE
import excel "$data\CVP.xlsx", sheet("Planilha1") firstrow

drop date O-S

gen date=ym(year, month)
format date %tm

* Balancing the Panel *
duplicates drop ais date, force
encode ais, gen (id_ais)
tsset id_ais date
tsfill, full

replace year = year(date) if year ==.
replace month = month(date) if month ==.

foreach v of varlist CVP1 CVP2 CVP CVLI drogas crimes_sexuais furto armas {

replace `v'=0 if `v'==.

}

ttest CVP, by(militar)
ttest CVP, by(pandemic)

xtset id_ais date

* Support Variables and Adjustments *
replace ais = "AIS 01" if ais == "AIS 1"
replace ais = "AIS 02" if ais == "AIS 2"
replace ais = "AIS 03" if ais == "AIS 3"
replace ais = "AIS 04" if ais == "AIS 4"
replace ais = "AIS 05" if ais == "AIS 5"
replace ais = "AIS 06" if ais == "AIS 6"
replace ais = "AIS 07" if ais == "AIS 7"
replace ais = "AIS 08" if ais == "AIS 8"
replace ais = "AIS 09" if ais == "AIS 9"

tab ais, gen(d_AIS)


*** Regressions ***

preserve

gen d_treat = 0
replace d_treat = 1 if ais == "AIS 02" |ais == "AIS 06" | ais == "AIS 11" |ais == "AIS 12" | ais == "AIS 13"

drop militar pandemic
gen militar = 0
replace militar = 1 if date > tm(2020m1)
replace militar = 0 if date > tm(2020m2)


gen militar_treat = militar*d_treat

* Descriptive Statistics *
tabulate d_treat militar, summarize(CVLI)
tabulate d_treat militar, summarize(CVP)
tabulate d_treat militar, summarize(furto)
tabulate d_treat militar, summarize(crimes_sexuais)
tabulate d_treat militar, summarize(drogas)
tabulate d_treat militar, summarize(armas)

* Effect by type of crime*
reghdfe CVP militar militar_treat, ///
	absorb(id_ais year month) /* All FE */

qui bootstrap, rep(999) cl(id_ais) idcl(new_id_ais) group(id_ais): reghdfe CVP  militar militar_treat, a(id_ais year month) vce(cl id_ais)
outreg2 using "$outputs\cvp.xls", replace ctitle(CVP) label 

qui bootstrap, rep(999) cl(id_ais) idcl(new_id_ais) group(id_ais): reghdfe furto  militar militar_treat, a(id_ais year month) vce(cl id_ais)
outreg2 using "$outputs\cvp.xls", append ctitle(Furto) label 

qui bootstrap, rep(999) cl(id_ais) idcl(new_id_ais) group(id_ais): reghdfe drogas  militar militar_treat, a(id_ais year month) vce(cl id_ais)
outreg2 using "$outputs\cvp.xls", append ctitle(Drogas) label  

qui bootstrap, rep(999) cl(id_ais) idcl(new_id_ais) group(id_ais): reghdfe armas  militar militar_treat, a(id_ais year month) vce(cl id_ais)
outreg2 using "$outputs\cvp.xls", append ctitle(Armas) label 

qui bootstrap, rep(999) cl(id_ais) idcl(new_id_ais) group(id_ais): reghdfe crimes_sexuais  militar militar_treat, a(id_ais year month) vce(cl id_ais)
outreg2 using "$outputs\cvp.xls", append ctitle(Crimes Sexuais) label 

restore


****** Comparative Strike 2011 x 2020 *******

// Data Dowloaded from SIM-DataSUS
import excel "$data\DataSUS_Ceara.xlsx", sheet("Painel_Ceara") firstrow

drop mês gcm
destring daily_homicides_nw daily_homicides_young daily_homicides_street d_500k d_100_500k d_capital population, replace force

encode city_code, gen (id_city)
encode ais, gen (id_ais)

drop if id_ais ==.

gen weekday = dow(data_obito)
gen month = month(data_obito)

gen greve_1 = 0
replace greve_1 = 1 if ano==2011 | ano == 2012 & militar==1
label variable greve_1 "2011 Strike"

gen greve_2 = 0
replace greve_2 = 1 if ano==2020 & militar==1
label variable greve_2 "2020 Strike"

gen rmce = 0
replace rmce = 1 if city_code =="230440" | city_code == "230370"| city_code =="230765" | city_code =="230100" | city_code =="230350" | city_code =="230428" | city_code =="231085"| city_code =="230970"| city_code =="230495"| city_code =="230770"| city_code =="230625"| city_code =="230523"| city_code =="230395"|city_code =="230960"

gen greve_1rm = greve_1*rmce
label variable greve_1rm "2011 Strike (Urban Area)"

gen greve_2rm = greve_2*rmce
label variable greve_2rm "2020 Strike (Urban Area)"


reghdfe daily_homicides greve_1 greve_1rm greve_2 greve_2rm, a(id_city ano month weekday) vce(rob)
estimates store comparative

reghdfe daily_homicides_firearms greve_1 greve_1rm greve_2 greve_2rm, a(id_city ano month weekday) vce(rob)
estimates store comparative2

coefplot comparative comparative2, drop(_cons) xline(0, lpattern(dash)) plotlabels("Homicides (Total)" "Homicides (Firearms)") legend(position(6) col(2)) ciopts(recast(rcap)) 

graph export "$outputs\Comparative_Strikes.png", as(png) name("Graph")  replace

