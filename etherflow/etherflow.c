/***********************************************************
 * A self-contained API to interface neuFlow
 **********************************************************/

#include <math.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

// self-contained (no lua)
#define _NO_LUA_

// define template macros
#define TH_CONCAT_3(x,y,z) TH_CONCAT_3_EXPAND(x,y,z)
#define TH_CONCAT_3_EXPAND(x,y,z) x ## y ## z
#define etherflow_(NAME) TH_CONCAT_3(etherflow_, Real, NAME)
#define etherflow_send_(NAME) TH_CONCAT_3(etherflow_send_, Real, NAME)
#define etherflow_receive_(NAME) TH_CONCAT_3(etherflow_receive_, Real, NAME)

// load templated code
#include "generic/etherflow.c"

// generate Float version
#define real float
#define accreal double
#define Real Float
#define TH_REAL_IS_FLOAT
#line 1 TH_GENERIC_FILE
#include TH_GENERIC_FILE
#undef accreal
#undef real
#undef Real
#undef TH_REAL_IS_FLOAT

// generate Double version
#define real double
#define accreal double
#define Real Double
#define TH_REAL_IS_DOUBLE
#line 1 TH_GENERIC_FILE
#include TH_GENERIC_FILE
#undef accreal
#undef real
#undef Real
#undef TH_REAL_IS_DOUBLE
