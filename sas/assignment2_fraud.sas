/*===========================================================================
  ACCT 270 - Group Assignment 2: Predicting Accounting Fraud

  Model: Fraud = a + b1*MFLAG + b2*FFLAG + b3*Z1 + b4*Z2 + ... + e

  Sample period: 2003-2014
  Data sources:
    - mydata.compustat1990to2019  (Compustat financial variables)
    - mydata.aaer1982to2014       (SEC fraud enforcement releases)

  BEFORE RUNNING: Upload compustat1990to2019.sas7bdat and
  aaer1982to2014.sas7bdat from the local data/ folder to your ODA
  home directory under a subfolder called SASData.
===========================================================================*/

/* Amazon WorkSpaces (AWS) — use these libnames */
libname mydata "s:\sasdata";
libname home   "d:\users\mcbai\desktop\programs";

/* ODA alternative — swap in if running on SAS OnDemand instead:
libname mydata "/home/u64486450/SASData";
libname home   "/home/u64486450/";
*/

options ps=max ls=max nocenter;


/*===========================================================================
  STEP 1: CONSTRUCT M-SCORE (Beneish 1999)

  MSCORE = -4.84 + 0.92*DSR + 0.528*GMI + 0.404*AQI + 0.892*SGI
           + 0.115*DEPI - 0.172*SGAI + 4.679*ACCRUALS - 0.327*LEVI
  MFLAG = 1 if MSCORE > -1.78
===========================================================================*/

/* Examine AAER dataset */
proc contents data=mydata.aaer1982to2014; run;
proc freq data=mydata.aaer1982to2014; tables fyear; run;

/* Pull and clean Compustat variables needed for M-score and F-score */
data variables;
    set mydata.compustat1990to2019;

    /* Require non-missing, non-zero key denominators */
    if AT > 0 and SALE > 0 and PPENT > 0;
    if nmiss(cogs, dp, rect, act, lct, ib, oancf) = 0;

    /* Set missing optional items to zero */
    if dltt  = . then dltt  = 0;
    if xsga  = . then xsga  = 0;
    if am    = . then am    = 0;
    if invt  = . then invt  = 0;
    if che   = . then che   = 0;
    if dltis = . then dltis = 0;
    if sstk  = . then sstk  = 0;

    /* --- M-Score raw components (current-year values) --- */
    DS      = RECT / SALE;                      /* Days Sales in Receivables   */
    GM      = 1 - (COGS / SALE);               /* Gross Margin                */
    AQ      = 1 - ((PPENT + ACT) / AT);        /* Asset Quality               */
    SG      = SALE;                             /* Sales (for SGI ratio)       */
    DEP     = (DP - AM) / (DP - AM + PPENT);   /* Depreciation rate           */
    SGA     = XSGA / SALE;                      /* SG&A ratio                  */
    ACCRUAL = (IB - OANCF) / AT;               /* Accruals (also used in F)   */
    LEV     = (LCT + DLTT) / AT;               /* Leverage                    */

    /* Return on assets — computed but excluded from regression due to
       near-perfect collinearity with ACCRUAL (both contain IB/AT, r=0.905) */
    ROA = IB / AT;
run;

/* Add prior-year values for M-score index construction and growth rates */
proc sql;
    create table addlagyear as
    select a.*,
           b.DS      as DS_m1,
           b.GM      as GM_m1,
           b.AQ      as AQ_m1,
           b.SG      as SG_m1,
           b.DEP     as DEP_m1,
           b.SGA     as SGA_m1,
           b.ACCRUAL as ACCRUAL_m1,
           b.LEV     as LEV_m1,
           b.AT      as AT_m1,
           b.IB      as IB_m1,
           b.RECT    as RECT_m1,
           b.INVT    as INVT_m1,
           b.SALE    as SALE_m1
    from variables a
    inner join variables b
        on a.gvkey = b.gvkey and a.fyear - 1 = b.fyear;
quit;

/* Calculate M-Score indices and flag */
data Mscore;
    set addlagyear;

    /* M-Score index ratios (handle zero denominators) */
    if DS_m1  > 0 then DSR  = DS  / DS_m1;  else DSR  = 1;
    if GM     > 0 then GMI  = GM_m1 / GM;   else GMI  = 1;
    if AQ_m1  > 0 then AQI  = AQ  / AQ_m1; else AQI  = 1;
    if SG_m1  > 0 then SGI  = SG  / SG_m1; else SGI  = 1;
    if DEP    > 0 then DEPI = DEP_m1 / DEP; else DEPI = 1;
    if SGA_m1 > 0 then SGAI = SGA / SGA_m1; else SGAI = 1;
    if LEV_m1 > 0 then LEVI = LEV / LEV_m1; else LEVI = 1;

    MSCORE = -4.84 + 0.92*DSR + 0.528*GMI + 0.404*AQI + 0.892*SGI
             + 0.115*DEPI - 0.172*SGAI + 4.679*ACCRUAL - 0.327*LEVI;

    if MSCORE > -1.78 then MFLAG = 1; else MFLAG = 0;

    /* Asset growth and sales growth (now we have lags) */
    if AT_m1   > 0 then ASSET_GROWTH = (AT   - AT_m1)   / AT_m1;
    if SALE_m1 > 0 then SALES_GROWTH = (SALE - SALE_m1) / SALE_m1;
run;


/*===========================================================================
  STEP 2: CONSTRUCT F-SCORE (Dechow et al. 2011)

  Requires 2-year lagged receivables for CH_CS calculation
  FFLAG = 1 if FSCORE > 1.0
===========================================================================*/

/* Get 2-year lagged receivables */
proc sql;
    create table addlagyear2 as
    select a.*,
           b.rect as rect_m2
    from Mscore a
    inner join mydata.compustat1990to2019 b
        on a.gvkey = b.gvkey and a.fyear - 2 = b.fyear;
quit;

/* Calculate F-Score components and flag */
data Fscore;
    set addlagyear2;

    if nmiss(rect, rect_m1, rect_m2, ib, ib_m1, invt, invt_m1, che, at, at_m1) = 0;

    /* --- 7 F-Score components --- */
    RSST    = ACCRUAL;
    CH_REC  = (RECT - RECT_m1) / AT;
    CH_INV  = (INVT - INVT_m1) / AT;
    SOFT    = (AT - PPENT - CHE) / AT;
    CH_ROA  = (IB / AT) - (IB_m1 / AT_m1);

    if SALE_m1 - (RECT_m1 - RECT_m2) > 0
        then CH_CS = ((SALE - (RECT - RECT_m1)) / (SALE_m1 - (RECT_m1 - RECT_m2))) - 1;
        else CH_CS = 1;

    if DLTIS + SSTK > 0 then ISSUE = 1; else ISSUE = 0;

    /* F-Score predicted value and probability */
    PredictedValue = -7.893 + 0.790*RSST + 2.518*CH_REC + 1.191*CH_INV
                     + 1.979*SOFT + 0.171*CH_CS - 0.932*CH_ROA + 1.029*ISSUE;

    if PredictedValue > 709 then PredictedValue = 709;  /* prevent overflow */

    Probability = exp(PredictedValue) / (1 + exp(PredictedValue));
    Fscore      = Probability / 0.0037;

    if FSCORE > 1 then FFLAG = 1; else FFLAG = 0;
run;


/*===========================================================================
  STEP 3: MERGE WITH AAER AND CODE FRAUD INDICATOR
===========================================================================*/

/* Left join: keep all firm-years, mark those with AAER as fraud */
proc sql;
    create table addAAER as
    select a.*, b.P_aaer
    from FSCORE a
    left join mydata.aaer1982to2014 b
        on a.gvkey = b.gvkey and a.fyear = b.fyear;
quit;

/* Restrict to 2003-2014, require flags non-missing, code FRAUD */
data Fraud;
    set addAAER;
    if 2003 <= fyear <= 2014;
    if nmiss(mflag, fflag) = 0;
    if nmiss(accrual, asset_growth, lev) = 0;
    if not missing(P_aaer) then FRAUD = 1; else FRAUD = 0;
run;


/*===========================================================================
  STEP 4: DESCRIPTIVE STATISTICS
===========================================================================*/

/* Overall means for all model variables */
proc means data=fraud n mean std p25 p50 p75 maxdec=3;
    var fraud mflag fflag accrual asset_growth lev;
quit;

/* Observations per year */
proc freq data=fraud;
    tables fyear;
run;

/* Fraud rate by year */
proc means data=fraud mean maxdec=4;
    var fraud;
    class fyear;
run;

/* Correlations among predictors */
proc corr data=fraud;
    var mflag fflag accrual asset_growth lev;
quit;


/*===========================================================================
  STEP 5: PART I - ALL-YEARS REGRESSION (2003-2014 pooled)

  Model: FRAUD = a + b1*MFLAG + b2*FFLAG + b3*ACCRUAL
                   + b4*ASSET_GROWTH + b5*LEV + e

  Variable predictions:
    MFLAG        (+): M-score flags firms with distorted financials
    FFLAG        (+): F-score flags firms with high fraud probability
    ACCRUAL      (+): High accruals signal earnings manipulation
    ASSET_GROWTH (+): Aggressive expansion may be funded by manipulation
    LEV          (+): Debt pressure creates incentive to appear healthier

  Note: ROA dropped due to near-perfect collinearity with ACCRUAL (r=0.905)
  Note: SALES_GROWTH dropped due to extreme outliers (max=11,880, std=61)
===========================================================================*/

proc reg data=fraud;
    model fraud = mflag fflag accrual asset_growth lev;
    title 'Assignment 2 Part I: Pooled Fraud Regression (2003-2014)';
quit;


/*===========================================================================
  STEP 6: PART II - YEAR-BY-YEAR REGRESSIONS (2003-2014)

  Run same model separately for each fiscal year to assess
  consistency of coefficients across time
===========================================================================*/

proc sort data=fraud;
    by fyear;
run;

proc reg data=fraud;
    by fyear;
    model fraud = mflag fflag accrual asset_growth lev;
    title 'Assignment 2 Part II: Year-by-Year Fraud Regressions';
quit;
