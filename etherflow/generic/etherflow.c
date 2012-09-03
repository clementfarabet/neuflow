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
#include <sys/types.h>
#include <sys/uio.h>
#include <fcntl.h>
#include <arpa/inet.h>
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
#define ETH_DATA_LEN    1500     /* Max. octets in payload          */
#define ETH_FRAME_LEN   1514     /* Max. octets in frame sans FCS   */
#define ETH_FCS_LEN     4        /* Octets in the FCS               */
#endif
#define ETH_PACKET_DELAY_US 12
#define ETH_ADDR_REM (0x010203040506)
#define ETH_TYPE     (0x1000)

/***********************************************************
 * Global Parameters
 **********************************************************/
static unsigned char dest_mac[6] = {ETH_ADDR_REM>>40,
                                    (ETH_ADDR_REM>>32) & 0xff,
                                    (ETH_ADDR_REM>>24) & 0xff,
                                    (ETH_ADDR_REM>>16) & 0xff,
                                    (ETH_ADDR_REM>>8)  & 0xff,
                                    (ETH_ADDR_REM)     & 0xff};
static unsigned char host_mac[6] = {0xff,0xff,0xff,0xff,0xff,0xff};
static unsigned char eth_type[2] = {ETH_TYPE>>8, ETH_TYPE & 0xff};
struct timeval last_packet = {0, 0};
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
// BPF (Berkeley Packet Filter) interface
int bpf = 0;
int bpf_buf_len = 0;
struct bpf_hdr *bpf_buf;
char* bpf_ptr;
int bpf_read_bytes;
struct bpf_program my_bpf_program;
//BPF Filter
struct bpf_insn insns[] = {
  BPF_STMT(BPF_LD+BPF_H+BPF_ABS, 12),                 // Load type at offset 12 in accumulator
  BPF_JUMP(BPF_JMP+BPF_JEQ+BPF_K, ETH_TYPE, 0, 5), // If type matches then check src addr (incr PC by 0)
  BPF_STMT(BPF_LD+BPF_W+BPF_ABS, 6),                  // Load src addr in accumulator
  BPF_JUMP(BPF_JMP+BPF_JEQ+BPF_K, ETH_ADDR_REM>>16, 0, 3),  // If src addr matches then keep the whole message
  BPF_STMT(BPF_LD+BPF_H+BPF_ABS, 10),                  // Load src addr in accumulator
  BPF_JUMP(BPF_JMP+BPF_JEQ+BPF_K, ETH_ADDR_REM & 0xffff, 0, 1),// 2nd part of src addr
  BPF_STMT(BPF_RET+BPF_K, (u_int)-1),                 // Keep the message (keep max byte)
  BPF_STMT(BPF_RET+BPF_K, 0),                         // Discard the message (keep 0 byte)
};

// Open an available bpf device
int open_dev(void)
{
  char buf[ 11 ] = { 0 };

  int i = 0;
  for(i = 0; i < 99; i++ )
  {
    sprintf( buf, "/dev/bpf%i", i );
    bpf = open( buf, O_RDWR );
    if( bpf != -1 ) {
      printf("<etherflow> Opened device /dev/bpf%i\n", i);
      break;
    }
  }
  if(bpf == -1) {
    printf("<etherflow> Cannot open any /dev/bpf* device, exiting\n");
    exit(1);
  }
  return bpf;
}

// link the device to an interface
void assoc_dev(int bpflocal, const char* interface)
{
  struct ifreq bound_if;
  strcpy(bound_if.ifr_name, interface);
  if(ioctl(bpflocal , BIOCSETIF, &bound_if ) > 0) {
    printf("<etherflow> Cannot bind bpf device to physical device %s, exiting\n", interface);
    exit(1);
  }
  printf("<etherflow> Bound bpf device to physical device %s\n", interface);
}

// Set the bpf buffer size
int set_buf_len(int bpflocal)
{
  int buf_len_local = 1;
  // activate immediate mode (therefore, buf_len is initially set to "1")
  if( ioctl( bpflocal, BIOCIMMEDIATE, &buf_len_local ) == -1 ) {
    printf("<etherflow> Cannot set IMMEDIATE mode of bpf device\n");
    exit(1);
  }
  buf_len_local = 3*1024*1024;
  // request buffer length
  if( ioctl( bpflocal, BIOCSBLEN, &buf_len_local  ) == -1 ) {
    printf("<etherflow> Cannot get bufferlength of bpf device\n");
    exit(1);
  }

  // request buffer length
  if( ioctl( bpflocal, BIOCGBLEN, &buf_len_local  ) == -1 ) {
    printf("<etherflow> Cannot get bufferlength of bpf device\n");
    exit(1);
  }
  printf("<etherflow> Buffer length of bpf device: %d\n", buf_len_local);
  return buf_len_local;
}

#endif

/***********************************************************
 * open_socket()
 * what: opens an ethernet socket
 * params:
 *    none
 * returns:
 *    socket - a socket descriptor
 **********************************************************/
#ifdef _LINUX_
int etherflow_open_socket_C(const char *dev, unsigned char *destmac, unsigned char *srcmac) {

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

  // Message
  printf("<etherflow> started on device %s\n", dev);

  // set buffer sizes
  unsigned int size = sizeof(int);
  int realbufsize = 0;

  // receive buffer
  int sockbufsize_rcv = 64*1024*1024;
  int set_res = setsockopt(sock, SOL_SOCKET, SO_RCVBUFFORCE, (int *)&sockbufsize_rcv, sizeof(int));
  int get_res = getsockopt(sock, SOL_SOCKET, SO_RCVBUF, &realbufsize, &size);
  if ((set_res < 0)||(get_res < 0)) {
    perror("set/get sockopt");
    close(sock);
    exit(1);
  }
  printf("<etherflow> set rx buffer size to %dMB\n", realbufsize/(1024*1024));

  // send buffer
  int sockbufsize_snd = 64*1024*1024;
  set_res = setsockopt(sock, SOL_SOCKET, SO_SNDBUFFORCE, (int *)&sockbufsize_snd, sizeof(int));
  get_res = getsockopt(sock, SOL_SOCKET, SO_SNDBUF, &realbufsize, &size);
  if ((set_res < 0)||(get_res < 0)) {
    perror("set/get sockopt");
    close(sock);
    exit(1);
  }
  printf("<etherflow> set tx buffer size to %dMB\n", realbufsize/(1024*1024));

  return 0;
}
#else
int etherflow_open_socket_C(const char *dev, unsigned char *destmac, unsigned char *srcmac) {

  // src mac can't be modified using the bpf. it's automatically replaced by the real mac address.

  bpf = open_dev();
  bpf_buf_len = set_buf_len(bpf);
  assoc_dev(bpf, dev);

  //This size must match the number of instructions in the filter program
  my_bpf_program.bf_len = 8;
  my_bpf_program.bf_insns = &insns;

  if (ioctl(bpf, BIOCSETF, &my_bpf_program) < 0)    // Setting filter
  {
    perror("ioctl BIOCSETF");
    exit(EXIT_FAILURE);
  }
  printf("<etherflow> Filter program set\n");

  // Allocate space for bpf packet
  bpf_buf = (struct bpf_hdr*) malloc(bpf_buf_len);
  if (bpf_buf == 0){
      fprintf(stderr, "bpf buffer alloc failed: %s\n", strerror(errno));
      return -1;
  }
  bpf_ptr = (char*)bpf_buf;
  bpf_read_bytes = 0;
  printf("<etherflow> bpf buffer created size : %d\n", bpf_buf_len);

  // Message
  printf("<etherflow> started on device %s\n", dev);
}

#endif

/***********************************************************
 * close_socket()
 * what: closes an ethernet socket
 * params:
 *    socket
 * returns:
 *    none
 **********************************************************/
int etherflow_close_socket_C() {
#ifdef _LINUX_
  return close(sock);
#else // not _LINUX_ but _APPLE_
  free(bpf_buf);
  return close(bpf);
#endif // _LINUX_
}

/***********************************************************
 * etherflow_send_reset_C()
 * what: send a reset Ethernet frame
 * params:
 *    none
 * returns:
 *    return sendto error code
 **********************************************************/
int etherflow_send_reset_C() {
  // reset mac addr
  unsigned char rst_mac[6] = {0x00,0x00,0x36,0x26,0x00,0x01};
  // buffer to send:
  unsigned char send_buffer[ETH_FRAME_LEN];

  // zero frame
  bzero(send_buffer, ETH_FRAME_LEN);

  // prepare send_buffer with DEST and SRC addresses
  memcpy((void*)send_buffer, (void*)rst_mac, ETH_ALEN);
  memcpy((void*)(send_buffer+ETH_ALEN), (void*)host_mac, ETH_ALEN);

  // send packet return error sendto error code
#ifdef _LINUX_
  return sendto(sock, send_buffer, ETH_FRAME_LEN, 0, (struct sockaddr*)&sock_address, socklen);
#else // not _LINUX_ but _APPLE_
  return write(bpf, send_buffer, ETH_FRAME_LEN);
#endif // _LINUX_
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
unsigned char recbuffer[ETH_FRAME_LEN];
#ifdef _LINUX_
unsigned char * etherflow_receive_frame_C(int *lengthp) {
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
  if (lengthp != NULL) (*lengthp) = len;
  return recbuffer;
}
#else // not _LINUX_ but _APPLE_
unsigned char * etherflow_receive_frame_C(int *lengthp) {
  struct frame_t *frame;
  struct bpf_hdr *bpf_packet;
  // Check if a new read is needed (a read from a bpf device can contains several bpf packets)
  if(bpf_ptr >= ((char*)(bpf_buf) + bpf_read_bytes))
  {
    //New read
    memset(bpf_buf, 0, bpf_buf_len);
    bpf_read_bytes = read(bpf, bpf_buf, bpf_buf_len);
    if(bpf_read_bytes < 0)
    {
        (*lengthp) = 0;
      return recbuffer;
    }
    if(bpf_read_bytes == 0)
    {
        (*lengthp) = 0;
      return recbuffer;
    }
    bpf_ptr = (char*)bpf_buf;
  }
  bpf_packet = (struct bpf_hdr*)bpf_ptr;
  memcpy(recbuffer, (char*)bpf_packet + bpf_packet->bh_hdrlen, bpf_packet->bh_caplen);
  // Increment thr ptr message for the next read
  bpf_ptr += BPF_WORDALIGN(bpf_packet->bh_hdrlen + bpf_packet->bh_caplen);
  if (lengthp != NULL) (*lengthp) = bpf_packet->bh_caplen;
  return recbuffer;
}
#endif // _LINUX_
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
int etherflow_send_frame_C(short int length, const unsigned char * data_p) {
  struct timeval current;
  // buffer to send:
  unsigned char send_buffer[ETH_FRAME_LEN];
  // A delay to give the OS time to complete sending the last packet
  int error;
  long int diff_usec;

  // prepare send_buffer with DEST and SRC addresses
  memcpy((void*)send_buffer, (void*)dest_mac, ETH_ALEN);
  memcpy((void*)(send_buffer+ETH_ALEN), (void*)host_mac, ETH_ALEN);

  // copy length to send_buffer
  unsigned char* length_str_reversed = (unsigned char*)&length;
  send_buffer[ETH_ALEN*2] = length_str_reversed[1];
  send_buffer[ETH_ALEN*2+1] = length_str_reversed[0];

  // copy user data to send_buffer
  memcpy((void*)(send_buffer+ETH_HLEN), (void*)data_p, length);

  error = gettimeofday(&current, NULL);
  diff_usec = current.tv_usec - last_packet.tv_usec + (current.tv_sec - last_packet.tv_sec) * 1000000;
  if(diff_usec < ETH_PACKET_DELAY_US){
      usleep(ETH_PACKET_DELAY_US - diff_usec);
  }
  error = gettimeofday(&last_packet, NULL);

  // send packet
#ifdef _LINUX_
  sendto(sock, send_buffer, length+ETH_HLEN, 0, (struct sockaddr*)&sock_address, socklen);
#else // not _LINUX_ but _APPLE_
  write(bpf, send_buffer, length+ETH_HLEN);
#endif // _LINUX_
  return 0;
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
int etherflow_send_ByteTensor_C(unsigned char * data, int size) {
  short int packet_size;
  unsigned char packet[ETH_FRAME_LEN];
  int elements_pointer = 0;
  int i;

  // this is the tensor descriptor header
  if (!neuflow_first_call) etherflow_receive_frame_C(NULL);
  neuflow_first_call = 0;

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

    // only the last packet could be not dividable by 4
    while(packet_size%4 != 0){
      packet[packet_size] = 0;
      packet_size++;
    }

    // smaller than min packet size - pad
    if (packet_size < ETH_ZLEN+4){ // smaller than min packet size - pad
      for(i = packet_size; i < ETH_ZLEN+4; i++){packet[i] = 0;}
      packet_size = ETH_ZLEN+4;
    }

    // send
    etherflow_send_frame_C(packet_size, packet);

    // why do we have to do that? buffer size?
    //usleep(100);
  }

  // return the number of results
  return 0;
}

/***********************************************************
 * enable_handshake()
 * disable_handshake()
 * what: enables, or disables handshake
 *       for neuflow->PC transfers
 * params:
 *    void
 * returns:
 *    void
 **********************************************************/
static int receive_ack = 1;
void etherflow_enable_handshake(void) {
  receive_ack = 1;
}
void etherflow_disable_handshake(void) {
  receive_ack = 0;
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
int etherflow_send_(Tensor_C)(real * data, int size) {
  // get the arguments
  short int packet_size;
  int elements_pointer = 0;
  unsigned char packet[ETH_FRAME_LEN];
  int i;

  // this is the tensor descriptor header
  if (!neuflow_first_call) etherflow_receive_frame_C(NULL);
  neuflow_first_call = 0;

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

    // only the last packet could be not dividable by 4
    while(packet_size%4 != 0){
      packet[packet_size] = 0;
      packet_size++;
    }

    // smaller than min packet size - pad
    if (packet_size < ETH_ZLEN+4) {
      for(i = packet_size; i < ETH_ZLEN+4; i++) {packet[i] = 0;}
      packet_size = ETH_ZLEN+4;
    }

    // send
    etherflow_send_frame_C(packet_size, packet);
  }

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
int etherflow_receive_(Tensor_C)(real *data, int size, int height) {
  int length = 0;
  int currentlength = 0;
  unsigned char *buffer;
  int num_of_bytes = size*2; // each value is 2 bytes
  int tensor_pointer = 0;
  int i;
  int num_of_frames = 0;

  // this is the tensor descriptor header
  if (!neuflow_first_call) etherflow_receive_frame_C(NULL);
  neuflow_first_call = 0;

  // if not a multiple of 4 the streamToHost function
  // will add an extra line to the stream
  // we want to make sure to receive it here
  if(num_of_bytes%4 != 0){
    num_of_bytes += (size/height)*2;
  }

  // receive tensor
  while (length < num_of_bytes){
    // Grab a packet
    buffer = etherflow_receive_frame_C(&currentlength);
    length += currentlength-ETH_HLEN;
    num_of_frames++;

    // Save data to tensor
    for (i = ETH_HLEN; tensor_pointer < size && i < currentlength; i+=2){
      short* val_short = (short*)&buffer[i];
      real val = (real)*val_short;
      val /= neuflow_one_encoding;
      data[tensor_pointer] = val;
      tensor_pointer++;
    }
  }

  // send ack after each tensor
  if (receive_ack)
    etherflow_send_frame_C(64, (unsigned char *)"1234567812345678123456781234567812345678123456781234567812345678");

  return 0;
}

#ifndef _NO_LUA_
/***********************************************************
 * Lua wrappers
 **********************************************************/
static int etherflow_(Api_handshake_lua)(lua_State *L){
  int handshake = lua_toboolean(L, 1);
  if (handshake)
    etherflow_enable_handshake();
  else
    etherflow_disable_handshake();
}

static int etherflow_(Api_receive_tensor_lua)(lua_State *L){
  /* get the arguments */
  THTensor *tensor = luaT_toudata(L, 1, torch_(Tensor_id));
  real *data = THTensor_(data)(tensor);
  int size = THTensor_(nElement)(tensor);
  etherflow_receive_(Tensor_C)(data, size, tensor->size[0]);
  return 0;
}

static int etherflow_(Api_send_tensor_lua)(lua_State *L) {
  /* get the arguments */
  THTensor *tensor = luaT_toudata(L, 1, torch_(Tensor_id));
  int size = THTensor_(nElement)(tensor);
  real *data = THTensor_(data)(tensor);
  etherflow_send_(Tensor_C)(data, size);
  return 0;
}

static int etherflow_(Api_send_tensor_byte_lua)(lua_State *L) {
  // get params
  THByteTensor *tensor = luaT_toudata(L, 1, luaT_checktypename2id(L, "torch.ByteTensor"));
  int size = THByteTensor_nElement(tensor);
  unsigned char *data = THByteTensor_data(tensor);
  etherflow_send_ByteTensor_C(data, size);
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
  int error = etherflow_open_socket_C(dev, destmac, srcmac);

  lua_pushnumber(L, error);  /* push result */
  return 1;
}

static int etherflow_(Api_send_reset_lua)(lua_State *L) {
  lua_pushnumber(L, etherflow_send_reset_C());
  return 1;
}


static int etherflow_(Api_close_socket_lua)(lua_State *L) {
  etherflow_close_socket_C();
  return 0;
}

static int etherflow_(Api_send_frame_lua)(lua_State *L) {
  /* get the arguments */
  const char * data_p = lua_tostring(L, 1);
  int length = strlen(data_p);
  return etherflow_send_frame_C(length, (unsigned char *)data_p);
}

static int etherflow_(Api_receive_string_lua)(lua_State *L) {
  // receive frame
  int length;
  unsigned char *buffer = etherflow_receive_frame_C(&length);

  // Protection: insert a 0 in case
  buffer[length] = 0;

  // Push string
  lua_pushstring(L, (char *)(buffer+ETH_HLEN));
  return 1;
}

static int etherflow_(Api_receive_frame_lua)(lua_State *L) {
  /* get the arguments */
  int length;
  unsigned char *buffer = etherflow_receive_frame_C(&length);

  lua_pushnumber(L, length-ETH_HLEN);
  lua_newtable(L);

  int i;
  for(i=ETH_HLEN; i<length; i++){
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
  {"send_reset",      etherflow_(Api_send_reset_lua)},
  {"handshake", etherflow_(Api_handshake_lua)},
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
#endif
