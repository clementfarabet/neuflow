
#include <math.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include <sys/socket.h>
#include <sys/ioctl.h>
#include <sys/time.h>

#include <pcap.h>

#ifdef _LINUX_
#include <linux/if_packet.h>
#include <linux/if_ether.h>
#include <linux/if_arp.h>
#include <linux/filter.h>
#include <asm/types.h>
#endif

#ifndef _LINUX_
#define ETH_ALEN        6        /* Octets in one ethernet addr     */
#define ETH_HLEN        14       /* Total octets in header.         */
#define ETH_ZLEN        60       /* Min. octets in frame sans FCS   */
#define ETH_DATA_LEN    1500     /* Max. octets in payload          */
#define ETH_FRAME_LEN   1514     /* Max. octets in frame sans FCS   */
#define ETH_FCS_LEN     4        /* Octets in the FCS               */
#include <dnet.h>
#endif

#include <netinet/in.h>

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
