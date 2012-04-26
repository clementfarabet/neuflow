/***********************************************************
 * A self-contained API to interface Ethernet to neuFlow
 **********************************************************/

/***********************************************************
 * open_socket()
 * what: opens an ethernet socket
 * params:
 *    dev - network device name
 *    remote_mac - MAC addr of remote dev
 *    local_mac - MAC addr of host computer
 *
 * returns:
 *    error - 0 for succsess, -1 for error
 **********************************************************/
int ethertbsp_open_socket_C(const char *dev, unsigned char *remote_mac, unsigned char *local_mac);

/***********************************************************
 * close_socket()
 * what: closes the ethernet socket
 * params:
 *    none
 * returns:
 *    none
 **********************************************************/
int ethertbsp_close_socket_C();

/***********************************************************
 * send_tensor_byte()
 * what: sends a torch byte tensor by breaking it down into
 *       ethernet packets of maximum size
 * params:
 *    data - send tensor as array
 *    size - length of data array
 * returns:
 *    zero
 **********************************************************/
int ethertbsp_send_ByteTensor_C(unsigned char * data, int size);

/***********************************************************
 * send_tensor()
 * what: sends a torch tensor by breaking it down into
 *       ethernet packets of maximum size
 *       a tensor of reals is converted to Q8.8
 * params:
 *    data - send tensor as array
 *    size - length of data array
 * returns:
 *    zero
 **********************************************************/
int ethertbsp_send_FloatTensor_C(float * data, int size);
int ethertbsp_send_DoubleTensor_C(double * data, int size);

/***********************************************************
 * receive_tensor_TYPE()
 * what: receives a torch tensor by concatenating eth packs
 *       a tensor of TYPE is created from Q8.8
 * params:
 *    data - tensor as array to be filled
 *    size - length of data array
 * returns:
 *    zero
 **********************************************************/
int ethertbsp_receive_FloatTensor_C(float *data, int size, int height);
int ethertbsp_receive_DoubleTensor_C(double *data, int size, int height);
