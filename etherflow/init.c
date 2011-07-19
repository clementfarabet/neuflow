
#include <math.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include <luaT.h>
#include <TH/TH.h>

#define torch_(NAME) TH_CONCAT_3(torch_, Real, NAME)
#define torch_string_(NAME) TH_CONCAT_STRING_3(torch., Real, NAME)
#define etherflow_(NAME) TH_CONCAT_3(etherflow_, Real, NAME)

static const void* torch_FloatTensor_id = NULL;
static const void* torch_DoubleTensor_id = NULL;

#include "generic/etherflow.c"
#include "THGenerateFloatTypes.h"

DLL_EXPORT int luaopen_libetherflow(lua_State *L)
{
  torch_FloatTensor_id = luaT_checktypename2id(L, "torch.FloatTensor");
  torch_DoubleTensor_id = luaT_checktypename2id(L, "torch.DoubleTensor");

  etherflow_FloatApi_init(L);
  etherflow_DoubleApi_init(L);

  luaL_register(L, "etherflow.double", etherflow_DoubleApi__); 
  luaL_register(L, "etherflow.float", etherflow_FloatApi__);

  return 1;
}
