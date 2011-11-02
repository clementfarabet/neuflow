
// common
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <sys/errno.h>
#include <netinet/in.h>
#include <unistd.h>


#ifdef _LINUX_

#include <linux/if_packet.h>
#include <linux/if_ether.h>
#include <linux/if_arp.h>
#include <linux/filter.h>
#include <asm/types.h>

#else // not _LINUX_ but _APPLE_

// osx
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

#endif // _LINUX_


/**
 * Global Parameters
 */

static int sockfd;
static socklen_t socklen;

#ifdef _LINUX_
static struct sockaddr_ll sock_address;
static struct ifreq ifr;
static int ifindex;
#else // not _LINUX_ but _APPLE_
// socket parameters
static struct sockaddr_ndrv sock_address;
#endif // _LINUX_

// ethernet packet parameters
static uint8_t eth_addr_dest[6] = {0x00,0x80,0x10,0x64,0x00,0x00};
static uint8_t eth_addr_host[6] = {0xff,0xff,0xff,0xff,0xff,0xff};
static uint8_t eth_type_tbsp[2] = {0x88, 0xb5};
const int ethertype_length	    = (ETH_HLEN-(2*ETH_ALEN));

uint8_t send_buffer[ETH_FRAME_LEN];
const int send_buffer_length = ETH_FRAME_LEN;

uint8_t recv_buffer[ETH_FRAME_LEN];
const int recv_buffer_length = ETH_FRAME_LEN;

// tbsp parameters
const int tbsp_frame_length     = ETH_DATA_LEN;
const int tbsp_type_length      = 1;
const int tbsp_sequence_length  = 4;
const int tbsp_length_length    = 2;
const int tbsp_header_length    = 7;
const int tbsp_data_length      = ETH_DATA_LEN - 1 - 4 - 2;

enum tbsp_types_t {TBSP_ERROR=0, TBSP_RESET=1, TBSP_DATA=2, TBSP_REQ=3, TBSP_ACK=4};

struct tbsp_packet {
  uint8_t *buffer;

  uint8_t *tbsp_type;
  uint8_t *tbsp_sequence;
  uint8_t *tbsp_length;
  uint8_t *tbsp_data;
};

struct tbsp_packet send_packet;
struct tbsp_packet recv_packet;

int carryover_ptr = 0;
uint8_t carryover[ETH_FRAME_LEN];

uint32_t current_send_seq_pos = 0;
uint32_t current_recv_seq_pos = 0;


/**
 * TBSP Handler Functions
 */

void tbsp_packet_init(struct tbsp_packet *packet, uint8_t *buffer) {

  packet->buffer = buffer;

  packet->tbsp_type     = &buffer[0];
  packet->tbsp_sequence = &buffer[1];
  packet->tbsp_length   = &buffer[5];
  packet->tbsp_data     = &buffer[7];

}


void tbsp_write_type (struct tbsp_packet *packet, enum tbsp_types_t type) {
  *packet->tbsp_type = (uint8_t) type;
}


enum tbsp_types_t tbsp_read_type (struct tbsp_packet *packet) {
  int type = (int) *packet->tbsp_type;

  if (TBSP_RESET == (enum tbsp_types_t) type) return TBSP_RESET;
  if (TBSP_DATA  == (enum tbsp_types_t) type) return TBSP_DATA;
  if (TBSP_REQ   == (enum tbsp_types_t) type) return TBSP_REQ;
  if (TBSP_ACK   == (enum tbsp_types_t) type) return TBSP_ACK;

  return TBSP_ERROR;
}


void tbsp_write_seq_position(struct tbsp_packet *packet, uint32_t seq_pos) {

  packet->tbsp_sequence[0] = (uint8_t) (seq_pos >> 24);
  packet->tbsp_sequence[1] = (uint8_t) (seq_pos >> 16);
  packet->tbsp_sequence[2] = (uint8_t) (seq_pos >> 8);
  packet->tbsp_sequence[3] = (uint8_t) (seq_pos);
}


uint32_t tbsp_read_seq_position(struct tbsp_packet *packet) {

  uint32_t seq_pos = (((uint32_t) packet->tbsp_sequence[0]) << 24) \
                   + (((uint32_t) packet->tbsp_sequence[1]) << 16) \
                   + (((uint32_t) packet->tbsp_sequence[2]) << 8)  \
                   +  ((uint32_t) packet->tbsp_sequence[3]);

  return seq_pos;
}


void tbsp_write_data_length(struct tbsp_packet *packet, uint16_t data_length) {

  packet->tbsp_length[0] = (uint8_t) (data_length >> 8);
  packet->tbsp_length[1] = (uint8_t) (data_length);
}


uint16_t tbsp_read_data_length(struct tbsp_packet *packet) {

  return (((uint16_t) packet->tbsp_length[0]) << 8) + ((uint16_t) packet->tbsp_length[1]);
}


/**
 * Network Functions
 */

int network_recv_packet() {
  int kk = 0;
  int ii = 0;
  int bad_packet = 0;

  do {
    kk = 0;
    ii = 0;
    bad_packet = 0;

    int frame_length = recv(sockfd, recv_buffer, ETH_FRAME_LEN, 0);
    if (0 > frame_length) { return frame_length; }

    // debugging
    int xx;
    printf("<recv packet> : ");
    for (xx = 0; xx < frame_length; xx++) {
      printf("%x ", recv_buffer[xx]);
    }
    printf("\n");
    // end debugging

    // check dst MAC
    for (kk = 0; kk < ETH_ALEN; kk++) {
      if (eth_addr_host[kk] != recv_buffer[ii++]) { bad_packet = 1; }
    }

    // check src MAC
    for (kk = 0; kk < ETH_ALEN; kk++) {
      if (eth_addr_dest[kk] != recv_buffer[ii++]) { bad_packet = 1; }
    }

    // check Ethertype
    for (kk=0; kk<2; kk++) {
      if (eth_type_tbsp[kk] != recv_buffer[ii++]) { bad_packet = 1; }
    }

  } while (bad_packet);

  return 0;
}


int network_send_packet() {

  memcpy( &send_buffer[0],            eth_addr_dest, ETH_ALEN);
  memcpy( &send_buffer[ETH_ALEN],     eth_addr_host, ETH_ALEN);
  memcpy( &send_buffer[(2*ETH_ALEN)], eth_type_tbsp, ethertype_length);

  int frame_length = ETH_HLEN + tbsp_header_length + tbsp_read_data_length(&send_packet);
  if (ETH_ZLEN > frame_length) {
    frame_length = ETH_ZLEN;
  }

  // debugging
  int xx;
  printf("<send packet> : ");
  for (xx = 0; xx < frame_length; xx++) {
    printf("%x ", send_buffer[xx]);
  }
  printf("\n");
  // end debugging

  return sendto(sockfd, send_buffer, frame_length, 0, (struct sockaddr*)&sock_address, socklen);
}


int network_close_socket() {

  return close(sockfd);
}


#ifdef _LINUX_

int network_open_socket(const char *dev) {

  // open raw socket and configure it
  if ((sockfd = socket(AF_PACKET, SOCK_RAW, htons(ETH_P_ALL))) == -1) {
    fprintf(stderr, "socket: socket() failed: %s\n", strerror(errno));
    return -1;
  }

  // retrieve ethernet interface index
  strncpy(ifr.ifr_name, dev, IFNAMSIZ);
  if (ioctl(sockfd, SIOCGIFINDEX, &ifr) == -1) {
    perror(dev);
    return -1;
  }
  ifindex = ifr.ifr_ifindex;

  // retrieve corresponding MAC
  if (ioctl(sockfd, SIOCGIFHWADDR, &ifr) == -1) {
    perror("GET_HWADDR");
    return -1;
  }

  // prepare sockaddr_ll
  sock_address.sll_family   = AF_PACKET;
  sock_address.sll_protocol = htons(ETH_P_ALL);
  sock_address.sll_ifindex  = ifindex;
  sock_address.sll_hatype   = 0;//ARPHRD_ETHER;
  sock_address.sll_pkttype  = 0;//PACKET_OTHERHOST;
  sock_address.sll_halen    = ETH_ALEN;
  sock_address.sll_addr[0]  = eth_addr_dest[0];
  sock_address.sll_addr[1]  = eth_addr_dest[1];
  sock_address.sll_addr[2]  = eth_addr_dest[2];
  sock_address.sll_addr[3]  = eth_addr_dest[3];
  sock_address.sll_addr[4]  = eth_addr_dest[4];
  sock_address.sll_addr[5]  = eth_addr_dest[5];
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
  int set_res = setsockopt(sockfd, SOL_SOCKET, SO_RCVBUFFORCE, (int *)&sockbufsize_rcv, sizeof(int));
  int get_res = getsockopt(sockfd, SOL_SOCKET, SO_RCVBUF, &realbufsize, &size);
  if ((set_res < 0)||(get_res < 0)) {
    perror("set/get sockopt");
    close(sockfd);
    exit(1);
  }
  printf("<etherflow> set rx buffer size to %dMB\n", realbufsize/(1024*1024));

  // send buffer
  int sockbufsize_snd = 64*1024*1024;
  set_res = setsockopt(sockfd, SOL_SOCKET, SO_SNDBUFFORCE, (int *)&sockbufsize_snd, sizeof(int));
  get_res = getsockopt(sockfd, SOL_SOCKET, SO_SNDBUF, &realbufsize, &size);
  if ((set_res < 0)||(get_res < 0)) {
    perror("set/get sockopt");
    close(sockfd);
    exit(1);
  }
  printf("<etherflow> set tx buffer size to %dMB\n", realbufsize/(1024*1024));

  return 0;
}

#else // not _LINUX_ but _APPLE_

int network_open_socket(const char *dev) {

  if ((sockfd = socket(PF_NDRV, SOCK_RAW, 0)) == -1) {
    fprintf(stderr, "socket: socket() failed: %s\n", strerror(errno));
    return -1;
  }

  // bind socket to physical device
  strlcpy((char *)sock_address.snd_name, dev, sizeof(sock_address.snd_name));
  sock_address.snd_len = sizeof(sock_address);
  sock_address.snd_family = AF_NDRV;

  if (bind(sockfd, (struct sockaddr *)&sock_address, sizeof(sock_address)) < 0) {
    fprintf(stderr, "socket: bind() failed: %s\n", strerror(errno));
    return -1;
  }

  // size of socket address
  socklen = sizeof(sock_address);

  const u_short ETHER_TYPES[] = {0x88b5};
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

  int result = setsockopt(sockfd, SOL_NDRVPROTO, NDRV_SETDMXSPEC, (caddr_t)&proto, sizeof(proto));
  if (result != 0) {
    fprintf(stderr, "error on setsockopt %d\n", result);
    return -1;
  }

  return 0;
}

#endif // _LINUX_


/**
 * TBSP Communication Functions
 */

int tbsp_send_reset() {
  int xx;

  for (xx = 0; xx < 10; xx++) {
    // send reset packet
    tbsp_write_type(&send_packet, TBSP_RESET);
    network_send_packet();

    // send req packet
    tbsp_write_type(&send_packet, TBSP_REQ);
    network_send_packet();

    // recv packet
    network_recv_packet();

    if (TBSP_ACK == tbsp_read_type(&recv_packet)) {
      if (0 == tbsp_read_seq_position(&recv_packet)) {
        current_send_seq_pos = 0;
        current_recv_seq_pos = 0;
        return 0;
      }
    }
  }

  return -1;
}


void tbsp_send_stream(uint8_t *data, int length) {
  int current_ptr = 0;
  int data_length = 0;
  int start_pos   = current_send_seq_pos;

  // optimistic sending
  while (current_ptr < length) {

    if ((length - current_ptr) >= tbsp_data_length) {
      data_length = tbsp_data_length;
    } else {
      data_length = (length - current_ptr);
    }

    tbsp_write_type(&send_packet, TBSP_DATA);
    tbsp_write_seq_position(&send_packet, current_send_seq_pos);
    tbsp_write_data_length(&send_packet, data_length);
    memcpy(send_packet.tbsp_data, &data[current_ptr], data_length);
    // send data packet
    network_send_packet();

    current_send_seq_pos += data_length;
    current_ptr += data_length;

    if (current_ptr >= length) {
      tbsp_write_type(&send_packet, TBSP_REQ);
      network_send_packet();

      do {
        network_recv_packet();
      } while (TBSP_ACK != tbsp_read_type(&recv_packet));

      current_send_seq_pos = tbsp_read_seq_position(&recv_packet);
      current_ptr = (current_send_seq_pos - start_pos);
    }
  }
}


void tbsp_recv_stream(uint8_t *data, int length) {
  int start_stream   = 0;
  int num_acks       = 0;

  // if carryover from last stream, add to data array
  if (0 < carryover_ptr) {
    memcpy(&data[0], &carryover[0], carryover_ptr);
    carryover_ptr = 0;
    start_stream  = 1;
  }

  while (1) {
    network_recv_packet();

    if (TBSP_ACK == tbsp_read_type(&recv_packet)) {
      if (1 == start_stream) { num_acks++; }

      current_send_seq_pos = tbsp_read_seq_position(&recv_packet);

      // Once stream has started 2 acks in a row means there is no more data
      if (2 == num_acks) { break; }
    }

    if (TBSP_DATA == tbsp_read_type(&recv_packet)) {
      start_stream    = 1;
      num_acks        = 0;
      int seq_pos     = tbsp_read_seq_position(&recv_packet);
      int data_length = tbsp_read_data_length(&recv_packet);
      int current_ptr = (seq_pos - current_recv_seq_pos);

      if (0 <= current_ptr) {
        if ((current_ptr + data_length) < length) {

          memcpy(&data[current_ptr], recv_packet.tbsp_data, data_length);
        } else {
          carryover_ptr = (current_ptr + data_length) - length;
          data_length   = data_length - carryover_ptr;

          // debugging
          printf("<recv stream> seq_pos %i, current_recv_seq_pos %i\n", seq_pos, current_recv_seq_pos );
          printf("<recv stream> data_length %i, current_ptr %i\n", data_length, current_ptr);
          // end debugging

          memcpy(&carryover[0], &recv_packet.tbsp_data[data_length], carryover_ptr);
          memcpy(&data[current_ptr], recv_packet.tbsp_data, data_length);
          break;
        }
      }
    }
  }

  current_recv_seq_pos = current_recv_seq_pos + ((uint32_t) length);
}


/**
 * Etherflow Functions
 */


int main(void) {
  // open socket
#ifdef _LINUX_
  char *dev = "eth0";
#else // not _LINUX_ but _APPLE_
  char *dev = "en0";
#endif
  network_open_socket(dev);
  if (sockfd < 0) {
    return -1;
  }

  // init send packet
  bzero(send_buffer, send_buffer_length);
  tbsp_packet_init(&send_packet, &send_buffer[ETH_HLEN]);

  // init recv packet
  bzero(recv_buffer, recv_buffer_length);
  tbsp_packet_init(&recv_packet, &recv_buffer[ETH_HLEN]);

  // reset NewFlow hardware
  if (0 > tbsp_send_reset()) {
    printf("RESET FAIL\n");
    return -1;
  }
  printf("RESET SUCCESS\n");


  int xx;
  int length = 100;
  uint8_t data[length];;
  for (xx = 0; xx < length; xx++) {
    data[xx] = (uint8_t) xx;
  }



  printf("Send Data Stream: ");
  for (xx = 0; xx < length; xx++) {
    printf("%c ", data[xx]);
  }
  printf("\n");
  tbsp_send_stream( &data[0], length);



  printf("Recv Data Stream: ");
  tbsp_recv_stream( &data[0], length);
  for (xx = 0; xx < length; xx++) {
    printf("%c ", data[xx]);
  }
  printf("\n");


  return 0;
}
