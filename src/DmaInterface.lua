----------------------------------------------------------------------
--- Class: DmaEthernet
--
-- This class provides a set of methods to exchange data/info with the host.
--
local DmaEthernet = torch.class('neuflow.DmaEthernet')

xrequire 'ethertbsp'

function DmaEthernet:__init(args)
   -- args:
   self.nf = args.nf
   self.core = args.core
   self.profiler = self.nf.profiler

   self.msg_level = args.msg_level or 'none'  -- 'detailled' or 'none' or 'concise'
   self.max_packet_size = 1500 or args.max_packet_size

   -- compulsory
   if (self.core == nil) then
      error('<neuflow.DmaEthernet> ERROR: requires a Dataflow Core')
   end

   -- data ack
   self.ack_tensor = torch.Tensor(1,1,32)
   self.ack_stream = self.nf:allocHeap(self.ack_tensor)
end

function DmaEthernet:open(network_if_name)
   if(network_if_name) then
      ethertbsp.open(network_if_name)
   else
      ethertbsp.open()
   end
end

function DmaEthernet:close()
   ethertbsp.close()
end

function DmaEthernet:sendReset()
   if (-1 == ethertbsp.sendreset()) then
      print('<reset> fail')
   end
end

function DmaEthernet:dev_copyToHost(tensor)
   for i = 1, (#tensor-1) do
      self.nf.core:executionTimeSensitive(function()
         self:streamToHost(tensor[i], 'default')
         --self:streamFromHost(self.ack_stream[1], 'ack_stream')
      end)
   end

   self.nf.core:executionTimeSensitive(function()
      self:streamToHost(tensor[#tensor], 'default')
   end)
end

function DmaEthernet:dev_copyFromHost(tensor)
   for i = 1,#tensor do
      self.nf.core:executionTimeSensitive(function()
         self:streamFromHost(tensor[i], 'default')
      end)
   end
end

function DmaEthernet:dev_receiveBytecode()
   self:loadByteCode()
end

function DmaEthernet:host_copyToDev(tensor)
   self.profiler:start('copy-to-dev')
   for i = 1,tensor:size(1) do
      ethertbsp.sendtensor(tensor[i])
   end
   self.profiler:lap('copy-to-dev')
end

function DmaEthernet:host_copyFromDev(tensor)
   self.profiler:start('copy-from-dev')
   ethertbsp.receivetensor(tensor[1])
   for i = 2,tensor:size(1) do
      --ethertbsp.sendtensor(self.ack_tensor)
      ethertbsp.receivetensor(tensor[i])
   end
   self.profiler:lap('copy-from-dev')
end

function DmaEthernet:host_sendBytecode(bytecode)
   self.profiler:start('load-bytecode')
   ethertbsp.loadbytecode(bytecode)
   self.profiler:lap('load-bytecode')
end

function DmaEthernet:printToEthernet(str)
   print("DEPRECATED")

   -- Printing to ethernet involves initializing a transfer with the driver,
   -- then writing the data (frame), then triggering the transfer.

   if (self.msg_level == 'detailled') then
      self.core:print(string.format('[ETHERNET TX : %s]',str))
   end

   -- verif data size >= 64
   str = str .. '\n'
   local data_size = string.len(str)
   if (data_size < 64) then
      data_size = 64
   end

   -- allocate string in memory (TODO: this call is wrong, it allocates the right size,
   -- but the data will be corrupted, need to implement a allocString function)
   local fake_string = {x = 0, y = 0, w = math.ceil(data_size/2), h = 1}

   -- stream data to DMA ethernet interface
   self.core:configPort{index = 0, action = 'fetch+read+sync+close', data = fake_string}
end

function DmaEthernet:streamToHost(stream, tag, mode)
   local data_size = stream.w * stream.h * 2

   -- estimate number of eth packets
   local nb_packets = math.ceil(data_size / self.max_packet_size)

   -- debug
   if (self.msg_level ~= 'none') then
      self.core:message(string.format('eth: sending %0d packets [tag = %s]', nb_packets, tag))
   end

   -- stream data (tensor) out with a write ack
--   self.core:configPort{index = -1, action = 'write', data = {x=0, y=0, w=32, h=1}}
   self.core:configPort{index = 0, action = 'fetch+read+sync+close', data = stream}
--   self.core:configPort{index = -1, action = 'sync+close'}

end

function DmaEthernet:streamFromHost(stream, tag)
   -- verif data size >= 64
   local data_size = stream.w * stream.h * 2
   if (data_size < 64) then
      error('<neuflow.DmaEthernet> ERROR: cant stream data packets smaller than 64 bytes')
   end

   -- estimate number of eth packets
   local nb_packets = math.ceil(data_size / self.max_packet_size)

   -- debug
   if (self.msg_level ~= 'none') then
      self.core:message(string.format('eth: requesting %0d packets [tag = %s]', nb_packets, tag))
   end

   -- stream data in
   self.core:configPort{index = -1, action = 'write', data = stream}
   self.core:configPort{index = -1, action = 'sync+close'}
end

function DmaEthernet:loadByteCode()
   -- Creating a stream
   local bytecode_stream = {x = 0, y = 0, w = 1024, h = 16*1024}

   -- Regular streamFromHost
   self:streamFromHost(bytecode_stream, 'bytecode')

   -- ACK to indicate that bytecode has been received
   --self.core:configPort{index = 0, action = 'fetch+read+sync+close', data = {x = 0, y = 0, w = 64, h = 1}}

   -- Jump to address 0 and execute
   self.core:gotoGlobal(bootloader.entry_point)
end
