/***********************************************************
 * A self-contained example
 **********************************************************/

#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include "etherflow.h"

#define BINARY_SIZE 32*1024*1024

#ifdef _LINUX_
#define ETH_DEV "eth0"
#else // _APPLE_
#define ETH_DEV "en0"
#endif

int main() {
  // init device
  open_socket_C(ETH_DEV, NULL, NULL);

  // load code (binary) from file
  unsigned char *neuflow_bin = (unsigned char *)malloc(BINARY_SIZE);
  memset(neuflow_bin, BINARY_SIZE, 0);
  FILE *f = fopen("neuflow.bin", "rb");
  if (f) fread(neuflow_bin, BINARY_SIZE, 1, f);
  else {
    printf("error: could not load binary\n");
    return 1;
  }

  // load (and exec) code on neuFlow
  etherflow_send_ByteTensor_C(neuflow_bin, BINARY_SIZE);

  // data structures
  float *input_data = malloc(sizeof(float) * 100 * 100);
  float *output_data = malloc(sizeof(float) * 16 * 20 * 20);

  // code is now executing, send data and receive answer in a loop
  while (1) {
    // send input data (a 100x100 image)
    etherflow_send_FloatTensor_C(input_data, 100*100);

    // receive data, processed by neuFlow (say a 16 20x20 images/maps)
    int i;
    float *output_p = output_data;
    for (i = 0; i < 16; i++) {
      // receive each map
      etherflow_receive_FloatTensor_C(output_p, 20*20, 20);
      output_p += 20*20;
    }

    // at this stage, output_data contains a valid 16x20x20 signal
  }

  // cleanup
  free(input_data);
  free(output_data);
  free(neuflow_bin);
  return 0;
}
