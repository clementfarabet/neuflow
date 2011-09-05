----------------------------------------------------------------------
--- Class: DmaEthernet
--
-- This class provides a set of methods to exchange data/info with the host.
--
local DmaEthernet = torch.class('neuflow.DmaEthernet')

function DmaEthernet:__init(args)
   -- args:
   self.core = args.core
   self.msg_level = args.msg_level or 'none'  -- 'detailled' or 'none' or 'concise'
   self.max_packet_size = 1500 or args.max_packet_size

   -- compulsory
   if (self.core == nil) then
      error('<neuflow.DmaEthernet> ERROR: requires a Dataflow Core')
   end
end

function DmaEthernet:printToEthernet(str)
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
   -- verif data size >= 64
   local data_size = stream.w * stream.h * 2
   if (data_size < 64) then
      error('<neuflow.DmaEthernet> ERROR: cant stream data packets smaller than 64 bytes')
   end

   -- estimate number of eth packets
   local nb_packets = math.ceil(data_size / self.max_packet_size)

   -- debug
   if (self.msg_level ~= 'none') then
      self.core:message(string.format('eth: sending %0d packets [tag = %s]', nb_packets, tag))
   end

   -- (1) specify: name | size | nb_packets
   self:printToEthernet(string.format('TX | %s | %0d | %0d', tag, data_size, nb_packets))

   -- (2) stream data out
   self.core:configPort{index = 0, action = 'fetch+read+sync+close', data = stream}
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

   -- (1) specify: name | size | nb_packets
   self:printToEthernet(string.format('RX | %s | %0d | %0d', tag, data_size, nb_packets))

   -- (2) stream data in
   self.core:configPort{index = -1, action = 'write', data = stream}
   self.core:configPort{index = -1, action = 'sync+close'}
end

function DmaEthernet:loadByteCode()
   -- Creating a stream
   local bytecode_stream = {x = 0, y = 0, w = 1024, y = 1024}

   -- Regular streamFromHost
   self.core:streamFromHost(bytecode_stream, 'bytecode')

   -- Jump to address 0 and execute
   self.core:gotoGlobal(bootloader.entry_point)
end
