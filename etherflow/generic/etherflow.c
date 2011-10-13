#ifndef TH_GENERIC_FILE
#define TH_GENERIC_FILE "generic/etherflow.c"
#else

#ifndef _ETHERFLOW_COMMON_
#define _ETHERFLOW_COMMON_

/***********************************************************
 * Ethernet Headers
 **********************************************************/
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <sys/errno.h>
#include <netinet/in.h>

#ifdef _LINUX_
#include <linux/if_packet.h>
#include <linux/if_ether.h>
#include <linux/if_arp.h>
#include <linux/filter.h>
#include <asm/types.h>
#else // _APPLE_
#include <net/if.h>
#include <net/if_dl.h>
#include <net/if_types.h>
#include <net/dlil.h>
#include <net/ndrv.h>
#include <net/ethernet.h>
#include <net/route.h>
#include <sys/ioctl.h>
#include <net/bpf.h>
#define ETH_ALEN        6        /* Octets in one ethernet addr     */
#define ETH_HLEN        14       /* Total octets in header.         */
#define ETH_ZLEN        60       /* Min. octets in frame sans FCS   */
//#define ETH_DATA_LEN    1500     /* Max. octets in payload          */
#define ETH_DATA_LEN    1400     /* Max. octets in payload          */
#define ETH_FRAME_LEN   1514     /* Max. octets in frame sans FCS   */
#define ETH_FCS_LEN     4        /* Octets in the FCS               */
#endif

/***********************************************************
 * Global Parameters
 **********************************************************/
static unsigned int carryover_ptr = 0;
static real carryover[ETH_FRAME_LEN];
static unsigned char dest_mac[6] = {0x01,0x02,0x03,0x04,0x05,0x06};
static unsigned char host_mac[6] = {0xff,0xff,0xff,0xff,0xff,0xff};
static unsigned char eth_type[2] = {0x10, 0x00};
static unsigned char eth_type_dma[2] = {0x88, 0xb5};
static unsigned char eth_type_rst[2] = {0x88, 0xb6};
static const int neuflow_one_encoding = 1<<8;
static int neuflow_first_call = 1;

// socket descriptors
static int sock;
static socklen_t socklen;

#ifdef _LINUX_
static struct sockaddr_ll sock_address;
static struct ifreq ifr;
static int ifindex;
#else // _APPLE_
static struct sockaddr_ndrv sock_address;
#endif

/***********************************************************
 * open_socket()
 * what: opens an ethernet socket
 * params:
 *    none
 * returns:
 *    socket - a socket descriptor
 **********************************************************/
int open_socket_C(const char *dev, unsigned char *destmac, unsigned char *srcmac) {

  // dest mac ?
  if (destmac != NULL) {
    int k = 0;
    for (k=0; k<ETH_ALEN; k++) dest_mac[k] = destmac[k];
  }

  // src mac ?
  if (srcmac != NULL) {
    int k = 0;
    for (k=0; k<ETH_ALEN; k++) host_mac[k] = srcmac[k];
  }

#ifdef _LINUX_
  // open raw socket and configure it
  sock = socket(AF_PACKET, SOCK_RAW, htons(ETH_P_ALL));
  if (sock == -1) {
    perror("socket():");
    exit(1);
  }

  // retrieve ethernet interface index
  strncpy(ifr.ifr_name, dev, IFNAMSIZ);
  if (ioctl(sock, SIOCGIFINDEX, &ifr) == -1) {
    perror(dev);
    exit(1);
  }
  ifindex = ifr.ifr_ifindex;

  // retrieve corresponding MAC
  if (ioctl(sock, SIOCGIFHWADDR, &ifr) == -1) {
    perror("GET_HWADDR");
    exit(1);
  }

  // prepare sockaddr_ll
  sock_address.sll_family   = AF_PACKET;
  sock_address.sll_protocol = htons(ETH_P_ALL);
  sock_address.sll_ifindex  = ifindex;
  sock_address.sll_hatype   = 0;//ARPHRD_ETHER;
  sock_address.sll_pkttype  = 0;//PACKET_OTHERHOST;
  sock_address.sll_halen    = ETH_ALEN;
  sock_address.sll_addr[0]  = dest_mac[0];
  sock_address.sll_addr[1]  = dest_mac[1];
  sock_address.sll_addr[2]  = dest_mac[2];
  sock_address.sll_addr[3]  = dest_mac[3];
  sock_address.sll_addr[4]  = dest_mac[4];
  sock_address.sll_addr[5]  = dest_mac[5];
  sock_address.sll_addr[6]  = 0x00;
  sock_address.sll_addr[7]  = 0x00;

  // size of socket
  socklen = sizeof(sock_address);

#else // _APPLE_

  // open raw socket, on Mac OS, by default it can't receive anything
  sock = socket(PF_NDRV, SOCK_RAW, 0);
  if (sock < 0) {
    fprintf(stderr, "socket: socket() failed: %s\n", strerror(errno));
    exit(1);
  }

  // bind socket to physical device
  strlcpy((char *)sock_address.snd_name, dev, sizeof(sock_address.snd_name));
  sock_address.snd_len = sizeof(sock_address);
  sock_address.snd_family = AF_NDRV;
  if (bind(sock, (struct sockaddr *)&sock_address, sizeof(sock_address)) < 0) {
    fprintf(stderr, "socket: bind() failed: %s\n", strerror(errno));
    exit(1);
  }

  // size of socket address
  socklen = sizeof(sock_address);

  // authorize receiving raw ethernet frames by type
  const u_short ETHER_TYPES[] = {((eth_type[0]<<8)+eth_type[1]),
                                 ((eth_type_dma[0]<<8)+eth_type_dma[1])};

  const int ETHER_TYPES_COUNT = sizeof(ETHER_TYPES)/sizeof(ETHER_TYPES[0]);
  struct ndrv_demux_desc demux[ETHER_TYPES_COUNT];

  int aa;
  for (aa = 0; aa < ETHER_TYPES_COUNT; aa++) {
    demux[aa].type            = NDRV_DEMUXTYPE_ETHERTYPE;
    demux[aa].length          = sizeof(demux[aa].data.ether_type);
    demux[aa].data.ether_type = htons(ETHER_TYPES[aa]);
  }

  struct ndrv_protocol_desc proto;
  bzero(&proto, sizeof(proto));
  proto.version         = NDRV_PROTOCOL_DESC_VERS;
  proto.protocol_family = NDRV_DEMUXTYPE_ETHERTYPE;
  proto.demux_count     = ETHER_TYPES_COUNT;
  proto.demux_list      = demux;

  int result = setsockopt(sock, SOL_NDRVPROTO, NDRV_SETDMXSPEC, (caddr_t)&proto, sizeof(proto));
  if (result != 0) {
    fprintf(stderr, "error on setsockopt %d\n", result);
    exit(1);
  }
#endif

  // Message
  printf("<etherflow> started on device %s\n", dev);

  // set buffer sizes
  unsigned int size = sizeof(int);
  int realbufsize = 0;

  // receive buffer
#ifdef _LINUX_
  int sockbufsize_rcv = 64*1024*1024;
  int set_res = setsockopt(sock, SOL_SOCKET, SO_RCVBUFFORCE, (int *)&sockbufsize_rcv, sizeof(int));
#else // _APPLE_
  int sockbufsize_rcv = 3*1024*1024;
  int set_res = setsockopt(sock, SOL_SOCKET, SO_RCVBUF, (int *)&sockbufsize_rcv, sizeof(int));
#endif
  int get_res = getsockopt(sock, SOL_SOCKET, SO_RCVBUF, &realbufsize, &size);
  if ((set_res < 0)||(get_res < 0)) {
    perror("set/get sockopt");
    close(sock);
    exit(1);
  }
  printf("<etherflow> set rx buffer size to %dMB\n", realbufsize/(1024*1024));

  // send buffer
#ifdef _LINUX_
  int sockbufsize_snd = 64*1024*1024;
  set_res = setsockopt(sock, SOL_SOCKET, SO_SNDBUFFORCE, (int *)&sockbufsize_snd, sizeof(int));
#else // _APPLE_
  int sockbufsize_snd = 3*1024*1024;
  set_res = setsockopt(sock, SOL_SOCKET, SO_SNDBUF, (int *)&sockbufsize_snd, sizeof(int));
#endif
  get_res = getsockopt(sock, SOL_SOCKET, SO_SNDBUF, &realbufsize, &size);
  if ((set_res < 0)||(get_res < 0)) {
    perror("set/get sockopt");
    close(sock);
    exit(1);
  }
  printf("<etherflow> set tx buffer size to %dMB\n", realbufsize/(1024*1024));

  return 0;
}

/***********************************************************
 * close_socket()
 * what: closes an ethernet socket
 * params:
 *    socket
 * returns:
 *    none
 **********************************************************/
int close_socket_C() {
  close(sock);
  return 0;
}

/***********************************************************
 * receive_frame_C()
 * what: receives an ethernet frame
 * params:
 *    socket - socket descriptor.
 *    buffer - to receive the data
 * returns:
 *    length - nb of bytes read/received
 **********************************************************/
unsigned char recbuffer[ETH_FRAME_LEN+1];
unsigned char * receive_frame_C(int *lengthp) {
  int len;
  while (1) {
    // receive a frame
    len = recv(sock, recbuffer, ETH_FRAME_LEN, 0);

    // check its destination/source/protocol
    int accept = 1;
    int k; int i = 0;
    for (k=0; k<ETH_ALEN; k++) {
      if (host_mac[k] != recbuffer[i++]) accept = 0;
    }
    for (k=0; k<ETH_ALEN; k++) {
      if (dest_mac[k] != recbuffer[i++]) accept = 0;
    }
    /* for (k=0; k<2; k++) { */
    /*   if (eth_type[k] != recbuffer[i++]) accept = 0; */
    /* } */
    if (accept) break;
  }

  int payload_start = ETH_HLEN;

  if (lengthp != NULL) {
    (*lengthp) = len-ETH_HLEN;

    // If Ethernet packet from DMA port
    if (eth_type_dma[0] == recbuffer[2*ETH_ALEN] && eth_type_dma[1] == recbuffer[2*ETH_ALEN+1]) {

      payload_start = ETH_HLEN+2;
      (*lengthp)    = (recbuffer[ETH_HLEN] << 8) + recbuffer[ETH_HLEN+1];

      if (0 == *lengthp) {
        payload_start = ETH_HLEN;
        (*lengthp)    = len-ETH_HLEN;
      }
    }
  }

  return &recbuffer[payload_start];
}

/***********************************************************
 * send_frame_C()
 * what: sends an ethernet frame
 * params:
 *    socket - socket descriptor.
 *    length - length of data to send
 *    data_p - data pointer
 * returns:
 *    error code
 **********************************************************/
int send_type_frame_C(short int length, const unsigned char *data_p, int ethertype) {

  int pos_payload_length;
  int pos_payload_data;
  int frame_length;

  // buffer to send:
  unsigned char send_buffer[ETH_FRAME_LEN];
  bzero(&send_buffer, ETH_FRAME_LEN);

  // prepare send_buffer with DEST and SRC addresses
  memcpy((void*)send_buffer, (void*)dest_mac, ETH_ALEN);
  memcpy((void*)(send_buffer+ETH_ALEN), (void*)host_mac, ETH_ALEN);

  if (1 == ethertype) {

    // copy ethertype to send_buffer
    send_buffer[ETH_ALEN*2+0] = eth_type_dma[0];
    send_buffer[ETH_ALEN*2+1] = eth_type_dma[1];

    pos_payload_length = ETH_ALEN*2+2;
    pos_payload_data   = ETH_HLEN+2;
    frame_length       = length+ETH_HLEN+2;
  } else if (2 == ethertype) {

    // copy ethertype to send_buffer
    send_buffer[ETH_ALEN*2+0] = eth_type_rst[0];
    send_buffer[ETH_ALEN*2+1] = eth_type_rst[1];

    pos_payload_length = ETH_ALEN*2+2;
    pos_payload_data   = ETH_HLEN+2;
    frame_length       = length+ETH_HLEN+2;
  } else {

    pos_payload_length = ETH_ALEN*2;
    pos_payload_data   = ETH_HLEN;
    frame_length       = length+ETH_HLEN;
  }

  // if smaller than min packet size - pad
  if (ETH_ZLEN > frame_length) {
    frame_length = ETH_ZLEN;
  }

  // copy length to send_buffer
  unsigned char* length_str_reversed = (unsigned char*)&length;
  send_buffer[pos_payload_length+0] = length_str_reversed[1];
  send_buffer[pos_payload_length+1] = length_str_reversed[0];

  // copy user data to send_buffer
  memcpy((void*)(send_buffer+pos_payload_data), (void*)data_p, length);

  // send packet
  sendto(sock, send_buffer, frame_length, 0, (struct sockaddr*)&sock_address, socklen);

  return 0;
}

int send_frame_C(short int length, const unsigned char *data_p) {
  //return send_type_frame_C(length, data_p, 1); // Use Ethertype
  return send_type_frame_C(length, data_p, 0); // Don't use Ethertype
}


/***********************************************************
 * send_tensor_byte()
 * what: sends a torch byte tensor by breaking it down into
 *       ethernet packets of maximum size
 * params:
 *    socket - socket descriptor.
 *    tensor - tensor to send
 * returns:
 *    void
 **********************************************************/
int send_tensor_byte_C(unsigned char * data, int size) {
  short int packet_size;
  unsigned char packet[ETH_FRAME_LEN];
  int elements_pointer = 0;
  int i;

  // sending data
  while(elements_pointer != size) {
    // send raw bytes
    packet_size = 0;
    for (i = 0; i < ETH_DATA_LEN; i++){
      if (elements_pointer < size){
        unsigned char val = data[elements_pointer];
        packet[i] = val;
        elements_pointer++;
        packet_size++;
      }
      else break;
    }

    // send
    send_frame_C(packet_size, packet);
  }

  // A delay to give the data time to clear the transfer and for the streamer port to close before
  // the next transfer.
  usleep(100);

  // return the number of results
  return 0;
}

#endif // _ETHERFLOW_COMMON_

/***********************************************************
 * send_tensor()
 * what: sends a torch tensor by breaking it down into
 *       ethernet packets of maximum size
 *       a tensor of reals is converted to Q8.8
 * params:
 *    socket - socket descriptor.
 *    tensor - tensor to send
 * returns:
 *    void
 **********************************************************/
int etherflow_(send_tensor_C)(real * data, int size) {
  // get the arguments
  short int packet_size;
  int elements_pointer = 0;
  unsigned char packet[ETH_FRAME_LEN];
  int i;

  // send
  while(elements_pointer != size){
    // convert real -> Q8.8
    packet_size = 0;
    for (i = 0; i < ETH_DATA_LEN; i+=2){
      if (elements_pointer < size){
        real val = data[elements_pointer];
        short fixed_point = (short)(val * neuflow_one_encoding + 0.5);
        unsigned char* point_to_short = (unsigned char*)&fixed_point;
        packet[i] = point_to_short[0];
        packet[i+1] = point_to_short[1];

        elements_pointer++;
        packet_size+=2;
      }
      else break;
    }

    // send
    send_frame_C(packet_size, packet);
  }

  // A delay to give the data time to clear the transfer and for the streamer port to close before
  // the next transfer.
  usleep(100);

  return 0;
}

/***********************************************************
 * receive_tensor_TYPE()
 * what: receives a torch tensor by concatenating eth packs
 *       a tensor of TYPE is created from Q8.8
 * params:
 *    socket - socket descriptor.
 *    tensor - tensor to fill
 * returns:
 *    void
 **********************************************************/
int etherflow_(receive_tensor_C)(real *data, int size, int height) {
  int length = 0;
  int currentlength = 0;
  unsigned char *buffer;
  int num_of_bytes = size*2; // each value is 2 bytes
  int tensor_pointer = 0;
  int ii = 0;

  // if carryover pointer != 0 it means that there is left over (carryover)
  // data from the last call, add this carryover data to "data"
//  if (0 < carryover_ptr) {
//    memcpy((void*) data, (void*) carryover, carryover_ptr);
//    length         = 2*carryover_ptr;
//    tensor_pointer = carryover_ptr;
//    carryover_ptr  = 0;
//  }

  // receive tensor
  while (length < num_of_bytes){
    // grab packet
    buffer = receive_frame_C(&currentlength);
    length += currentlength;

    // unpack Ethernet payload to tensor data array
    for (ii = 0; tensor_pointer < size && ii < currentlength; ii+=2){
      short* val_short = (short*)&buffer[ii];
      real val = (real)*val_short;
      val /= neuflow_one_encoding;
      data[tensor_pointer] = val;
      tensor_pointer++;
    }
  }

  // if not all data from the Ethernet packet has been read out, carry it over
  // to the next tensor
//  while (ii < currentlength) {
//    short* val_short = (short*)&buffer[ii];
//    real val = (real)*val_short;
//    val /= neuflow_one_encoding;
//    carryover[carryover_ptr] = val;
//    carryover_ptr++;
//    ii+=2;
//  }

  // send ack after each tensor
  send_frame_C(64, (unsigned char *)"1234567812345678123456781234567812345678123456781234567812345678");
  usleep(100);

  return 0;
}

/***********************************************************
 * Lua wrappers
 **********************************************************/
static int etherflow_(Api_receive_tensor_lua)(lua_State *L){
  /* get the arguments */
  THTensor *tensor = luaT_toudata(L, 1, torch_(Tensor_id));
  real *data = THTensor_(data)(tensor);
  int size = THTensor_(nElement)(tensor);
  etherflow_(receive_tensor_C)(data, size, tensor->size[0]);
  return 0;
}

static int etherflow_(Api_send_tensor_lua)(lua_State *L) {
  /* get the arguments */
  THTensor *tensor = luaT_toudata(L, 1, torch_(Tensor_id));
  int size = THTensor_(nElement)(tensor);
  real *data = THTensor_(data)(tensor);
  etherflow_(send_tensor_C)(data, size);
  return 0;
}

static int etherflow_(Api_send_tensor_byte_lua)(lua_State *L) {
  // resest packet
  //send_type_frame_C(64, (unsigned char *)"1234567812345678123456781234567812345678123456781234567812345678", 2);
  //usleep(100);

  // get params
  THByteTensor *tensor = luaT_toudata(L, 1, luaT_checktypename2id(L, "torch.ByteTensor"));
  int size = THByteTensor_nElement(tensor);
  unsigned char *data = THByteTensor_data(tensor);
  send_tensor_byte_C(data, size);
  return 0;
}

static int etherflow_(Api_open_socket_lua)(lua_State *L) {
  // get dev name
#ifdef _LINUX_
  char default_dev[] = "eth0";
#else // _APPLE_
  char default_dev[] = "en0";
#endif
  const char *dev;
  if (lua_isstring(L, 1)) dev = lua_tostring(L,1);
  else dev = default_dev;

  // get dest mac address
  unsigned char *destmac = NULL;
  if (lua_istable(L, 2)) {
    destmac = (unsigned char *)malloc(ETH_ALEN);
    int k;
    for (k=1; k<=ETH_ALEN; k++) {
      lua_rawgeti(L, 2, k);
      destmac[k-1] = (unsigned char)lua_tonumber(L, -1); lua_pop(L, 1);
    }
  }

  // get src mac address
  unsigned char *srcmac = NULL;
  if (lua_istable(L, 3)) {
    srcmac = (unsigned char *)malloc(ETH_ALEN);
    int k;
    for (k=1; k<=ETH_ALEN; k++) {
      lua_rawgeti(L, 3, k);
      srcmac[k-1] = (unsigned char)lua_tonumber(L, -1); lua_pop(L, 1);
    }
  }

  // open socket
  open_socket_C(dev, destmac, srcmac);
  return 0;
}

static int etherflow_(Api_close_socket_lua)(lua_State *L) {
  close_socket_C();
  return 0;
}

static int etherflow_(Api_send_frame_lua)(lua_State *L) {
  /* get the arguments */
  const char * data_p = lua_tostring(L, 1);
  int length = strlen(data_p);
  return send_frame_C(length, (unsigned char *)data_p);
}

static int etherflow_(Api_receive_string_lua)(lua_State *L) {
  // receive frame
  int length;
  unsigned char *buffer = receive_frame_C(&length);

  // Protection: Checks if null-terminated and if not, inserts a null
  if ('\0' != buffer[length-1]) {
    buffer[length] = '\0';
  }

  // Push string
  lua_pushstring(L, (char *)(buffer));
  return 1;
}

static int etherflow_(Api_receive_frame_lua)(lua_State *L) {
  /* get the arguments */
  int length;
  unsigned char *buffer = receive_frame_C(&length);

  lua_pushnumber(L, length);
  lua_newtable(L);

  int i;
  for(i=0; i<length; i++){
    lua_pushnumber(L, i);
    lua_pushnumber(L, buffer[i]);
    lua_settable(L, -3);
  }
  return 2;
}

static int etherflow_(Api_set_first_call)(lua_State *L) {
  /* get the arguments */
  int val = lua_tointeger(L, 1);
  neuflow_first_call = val;
  return 0;
}

/***********************************************************
 * register functions for Lua
 **********************************************************/
static const struct luaL_Reg etherflow_(Api__) [] = {
  {"open_socket", etherflow_(Api_open_socket_lua)},
  {"receive_frame", etherflow_(Api_receive_frame_lua)},
  {"receive_string", etherflow_(Api_receive_string_lua)},
  {"send_frame", etherflow_(Api_send_frame_lua)},
  {"send_tensor", etherflow_(Api_send_tensor_lua)},
  {"send_bytetensor", etherflow_(Api_send_tensor_byte_lua)},
  {"receive_tensor", etherflow_(Api_receive_tensor_lua)},
  {"close_socket", etherflow_(Api_close_socket_lua)},
  {"set_first_call", etherflow_(Api_set_first_call)},
  {NULL, NULL}
};

void etherflow_(Api_init)(lua_State *L)
{
  luaT_pushmetaclass(L, torch_(Tensor_id));
  luaT_registeratname(L, etherflow_(Api__), "etherflow");
}

#endif
