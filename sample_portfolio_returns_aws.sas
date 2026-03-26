*******************************************************;
* EXECUTE LIBNAME STATEMENTS EVERY TIME YOU START SAS *;
*******************************************************;

*These tell SAS the location of the data;

libname mydata "s:\sasdata"; 					*shared data for the course;
libname home "d:\users\mcbai\desktop\programs";	*your personal folder;
options ps=max ls=max nocenter;

*MERGE COMPUSTAT AND IBES;
*MERGE ON COMPANY-ID and FISCAL YEAR END DATE;
proc sql;
create table mergeIBES as 
select a.*, b.anndats, b.consensus, b.actual, b.ibesshrout
from mydata.compustat1990to2019 a 
inner join mydata.ibes1993to2019 b
on a.permno=b.permno and a.datadate=b.datadate;
quit;

*GET FUTURE RETURNS OVER THE 180-DAY PERIOD <AFTER> THE EARNINGS ANNOUNCEMENT;
*MERGE TO CRSP ON COMPANY-ID and EARNINGS ANNOUNCEMENT DATE;
proc sql;
create table mergeCRSP as 
select a.*, ret180, mktadjret180
from mergeIBES a 
inner join mydata.crspdaily1993to2019 b
on a.permno=b.permno and a.anndats=b.date;
quit;

*COMPUTE ANALYST FORECAST ERROR SCALED BY ASSETS & LIMIT SAMPLE TO 1993 to 2018;
data AFEdata; 
set mergeCRSP;
AFE=((actual-consensus)*ibesshrout)/at;
if nmiss(AFE)=0 and 1993<=fyear<=2018;
run;

proc means data=AFEdata mean; 
var AFE; 
quit;

*RANK BY YEAR INTO PORTFOLIOS;
proc sort data=AFEdata; 
by fyear; 
quit;

*ASSIGN STOCKS TO 5 PORTFOLIOS;
*NOTE THAT SAS (STUPIDLY) ASSIGNS VALUES 0...GROUPS-1;
*since "groups=5," the new variable PORTFOLIOS will take value 0...4;
proc rank data=AFEdata out=AFEdata2 groups=5; 
by fyear; 			*do ranking every year;
var AFE;  			*rank based on AFE;
ranks portfolios; 	*assign ranks to new variable named PORTFOLIOS;
quit;

*CREATE PORTFOLIO VARIABLES;
data AFEdata3; 
set AFEdata2;
portfolios=portfolios+1;		*now takes values 1...5;
if portfolios=5 then high=1;	*binary variable =1 for Group 5;
if portfolios=1 then high=0;	*binary variable =0 for Group 1; *missing for all other groups;
run;

*AVERAGE PORTFOLIO RETURNS;
proc means data=AFEdata3 mean t; 
class portfolios;
var ret180 mktadjret180;
quit;

proc reg data=AFEdata3; 
model ret180 = high; 
quit;

*REPEAT BY YEAR;
proc sort data=AFEdata3;
by fyear; 
quit;

proc means data=AFEdata3 mean t; 
by fyear;
class portfolios;
var ret180 mktadjret180;
quit;

proc reg data=AFEdata3; 
by fyear;
model ret180 = high; 
quit;

