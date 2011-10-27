
// common
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <sys/errno.h>
#include <netinet/in.h>
//#include <arpa/inet.h>


//// linux
//#include <linux/if_packet.h>
//#include <linux/if_ether.h>
//#include <linux/if_arp.h>
//#include <linux/filter.h>
//#include <asm/types.h>

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


/**
 * Global Parameters
 */

// socket parameters
static int sockfd;
static socklen_t socklen;
static struct sockaddr_ndrv sock_address;

// ethernet packet parameters
static uint8_t eth_addr_dest[6] = {0x00,0x80,0x10,0x64,0x00,0x00};
static uint8_t eth_addr_host[6] = {0xff,0xff,0xff,0xff,0xff,0xff};
static uint8_t eth_type_tbsp[2] = {0x88, 0xb5};
const int ethertype_length	      = (ETH_HLEN-(2*ETH_ALEN));

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

  uint8_t *eth_dest;
  uint8_t *eth_host;
  uint8_t *eth_type;
  uint8_t *eth_payload;
  uint8_t *tbsp_type;
  uint8_t *tbsp_sequence;
  uint8_t *tbsp_length;
  uint8_t *tbsp_data;
};

struct tbsp_packet send_packet;
struct tbsp_packet recv_packet;


/**
 * Network Functions
 */

int network_recv_packet() {
  int kk = 0;
  int ii = 0;
  int bad_packet = 0;

  // debugging
  int frame_length;

  do {
    kk = 0;
    ii = 0;
    bad_packet = 0;

    // frame_length pre-set offline debugging
    frame_length = ETH_HLEN + tbsp_header_length + tbsp_read_data_length(&recv_packet);

    //int frame_length = recv(sockfd, recv_packet.buffer, ETH_FRAME_LEN, 0);
    if (0 > frame_length) { return frame_length; }

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


  // debugging
  int xx;
  for (xx = 0; xx < frame_length ; xx++) {
    printf("%x ", recv_buffer[xx]);
  }

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

  // print values instead of sending them for debug
  int xx;
  for (xx = 0; xx < frame_length ; xx++) {
    printf("%x ", send_buffer[xx]);
  }
  return 0;

  //return sendto(sockfd, send_packet.buffer, frame_length, 0, (struct sockaddr*)&sock_address, socklen);
}


//int network_close_socket() {
//
//  return close(sockfd);
//}


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


/**
 * TBSP Functions
 */

void tbsp_packet_init(struct tbsp_packet *packet, uint8_t *buffer) {

  packet->buffer = buffer;

  packet->eth_dest      = &buffer[0];
  packet->eth_host      = &buffer[6];
  packet->eth_type      = &buffer[12];
  packet->eth_payload   = &buffer[14];

  packet->tbsp_type     = &buffer[14];
  packet->tbsp_sequence = &buffer[15];
  packet->tbsp_length   = &buffer[19];
  packet->tbsp_data     = &buffer[21];

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


int tbsp_read_data_length(struct tbsp_packet *packet) {

  return (((uint16_t) packet->tbsp_length[0]) << 8) + ((uint16_t) packet->tbsp_length[1]);
}


int tbsp_send_reset() {

  tbsp_write_type(&send_packet, TBSP_RESET);

  // send reset packet
  network_send_packet();

  // send req packet

  // recv packet

  // if recv packet not ack, return -1
  
  // if recv packet ack seq # not 0, return -1

  return 0;
}


int tbsp_send_stream(uint8_t *data, int length) {

  // optimistic sending

  // do {
  // set seq pos, data length
  // copy data from "data" to send packet
  // network_send_packet()

  // if sent all data send req packet
  // network_recv_packet() loop until ack
  // reset send seq pos 

  // } while (); // if send seq pos not end of "data", loop

  return 0;
}


int tbsp_recv_stream(uint8_t *data, int length) {

  // check carryover from last stream
  // if carryover, add to data array

  // while data not full
  // network_recv_packet 
  // check type, data or ack
  // if ack type, set send seq pos
  // if data type, get seq num and data length
  //   copy the length of packet data to seq pos in data

/*
  memcpy(send_packet->tbsp_data, data[send_seq_pos], sizeof(tbsp_d)/sizeof(tbsp_d[0]));
*/

  // if carryover, copy carry to carryover buffer

  return 0;
}


/**
 * Etherflow Functions
 */


int main(void) {
  // open socket
//  char *dev = "en0";
//  network_open_socket(dev);
//  if (sockfd < 0) {
//    return -1;
//  }

  // should I just of one packet?

  // init send packet
  bzero(send_buffer, send_buffer_length);
  tbsp_packet_init(&send_packet, &send_buffer[0]);

  // init recv packet
  bzero(recv_buffer, recv_buffer_length);
  tbsp_packet_init(&recv_packet, &recv_buffer[0]);



  // Test TBSP handler functions

  tbsp_write_type(&send_packet, TBSP_RESET);
  printf("type %i\n", tbsp_read_type(&send_packet));

  tbsp_write_seq_position(&send_packet, 16909320);
  printf("seq pos %i\n", tbsp_read_seq_position(&send_packet));

  tbsp_write_data_length(&send_packet, 258);
  printf("data length %i\n", tbsp_read_data_length(&send_packet));


  printf("send buffer: ");
  network_send_packet();
  printf("\n");


  // Test network_recv_packet()
  memcpy( &recv_buffer[0],            eth_addr_host, ETH_ALEN);
  memcpy( &recv_buffer[ETH_ALEN],     eth_addr_dest, ETH_ALEN);
  memcpy( &recv_buffer[(2*ETH_ALEN)], eth_type_tbsp, ethertype_length);

  tbsp_write_data_length(&recv_packet, 258);

  printf("recv buffer: ");
  network_recv_packet();
  printf("\n");


  return 0;
}
