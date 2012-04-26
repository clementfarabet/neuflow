
#include <math.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include <luaT.h>
#include <TH/TH.h>

#define torch_(NAME) TH_CONCAT_3(torch_, Real, NAME)
#define torch_string_(NAME) TH_CONCAT_STRING_3(torch., Real, NAME)
#define ethertbsp_(NAME) TH_CONCAT_3(ethertbsp_, Real, NAME)
#define ethertbsp_send_(NAME) TH_CONCAT_3(ethertbsp_send_, Real, NAME)
#define ethertbsp_receive_(NAME) TH_CONCAT_3(ethertbsp_receive_, Real, NAME)

static const void* torch_FloatTensor_id = NULL;
static const void* torch_DoubleTensor_id = NULL;

#undef TH_GENERIC_FILE
#include "generic/ethertbsp.c"
#include "THGenerateFloatTypes.h"

DLL_EXPORT int luaopen_libethertbsp(lua_State *L)
{
  torch_FloatTensor_id = luaT_checktypename2id(L, "torch.FloatTensor");
  torch_DoubleTensor_id = luaT_checktypename2id(L, "torch.DoubleTensor");

  ethertbsp_FloatApi_init(L);
  ethertbsp_DoubleApi_init(L);

  luaL_register(L, "ethertbsp.double", ethertbsp_DoubleApi__);
  luaL_register(L, "ethertbsp.float", ethertbsp_FloatApi__);

  return 1;
}
