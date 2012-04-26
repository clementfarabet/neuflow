/***********************************************************
 * A self-contained example
 * Compile:
 *   gcc -fpic -shared ethertbsp.c -o libeth.so
 *   gcc example.c libeth.so -o example
 **********************************************************/

#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include "ethertbsp.h"

#define BINARY_SIZE 32*1024*1024

#ifdef _LINUX_
#define ETH_DEV "eth0"
#else // _APPLE_
#define ETH_DEV "en0"
#endif

#define abs(a) (a)>0 ? (a) : -(a)

int main() {
  // init device
  ethertbsp_open_socket_C(ETH_DEV, NULL, NULL);

  // load code (binary) from file
  unsigned char *neuflow_bin = (unsigned char *)malloc(BINARY_SIZE);
  memset(neuflow_bin, BINARY_SIZE, 0);
  FILE *f = fopen("neuflow.bin", "rb");
  int nread;
  if (f) nread = fread(neuflow_bin, 1, BINARY_SIZE, f);
  else {
    printf("error: could not find neuflow code (neuflow.bin)\n");
    return 1;
  }
  printf("loaded bytecode [size = %d]\n", nread);

  // load (and exec) code on neuFlow
  printf("transmitting bytecode\n");
  ethertbsp_send_ByteTensor_C(neuflow_bin, BINARY_SIZE);
  sleep(1);
  printf("transmitted.\n");

  // data structures
  double *input_data = malloc(sizeof(double) * 3 * 400 * 400);
  double *output_data = malloc(sizeof(double) * 3 * 400 * 400);

  // initialize data
  int i,k;
  for (k = 0; k < 3; k++) {
    for (i = 0; i < 400*400; i++) {
      input_data[k*400*400+i] = k;
      output_data[k*400*400+i] = 0;
    }
  }

  // code is now executing, send data and receive answer in a loop
  while (1) {
    // send input data (a 3x400x400 image)
    double *input_p = input_data;
    for (i = 0; i < 3; i++) {
      ethertbsp_send_DoubleTensor_C(input_p, 400*400);
      input_p += 400*400;
    }

    // receive data, processed by neuFlow (a 3x400x400 image, loopbacked)
    double *output_p = output_data;
    for (i = 0; i < 3; i++) {
      ethertbsp_receive_DoubleTensor_C(output_p, 400*400, 400);
      output_p += 400*400;
    }

    // measure loopback error
    double error = 0;
    double maxerr = 0;
    for (i = 0; i < 3*400*400; i++) {
      double err = abs(input_data[i] - output_data[i]);
      if (err > maxerr) maxerr = err;
      error += err;
    }
    error /= 3*400*400;
    printf("average error = %f, max error = %f\n", error, maxerr);
  }

  // cleanup
  free(input_data);
  free(output_data);
  free(neuflow_bin);
  return 0;
}
