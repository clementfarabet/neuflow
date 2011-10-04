/***********************************************************
 * A self-contained API to interface neuFlow
 **********************************************************/

/***********************************************************
 * open_socket()
 * what: opens an ethernet socket
 * params:
 *    none
 * returns:
 *    socket - a socket descriptor
 **********************************************************/
int open_socket_C(const char *dev, unsigned char *destmac, unsigned char *srcmac);

/***********************************************************
 * close_socket()
 * what: closes an ethernet socket
 * params:
 *    socket
 * returns:
 *    none
 **********************************************************/
int close_socket_C();

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
int etherflow_send_ByteTensor_C(unsigned char * data, int size);

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
int etherflow_send_FloatTensor_C(float * data, int size);
int etherflow_send_DoubleTensor_C(double * data, int size);

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
int etherflow_receive_FloatTensor_C(float *data, int size, int height);
int etherflow_receive_DoubleTensor_C(double *data, int size, int height);
