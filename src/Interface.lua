
----------------------------------------------------------------------
--- Class: Ethernet
--
-- This class provides a set of methods to exchange data/info with the host.
-- 
local Ethernet = torch.class('neuflow.Ethernet')

xrequire 'etherflow'

function Ethernet:__init(args)
   -- args:
   self.core = args.core
   self.msg_level = args.msg_level or 'none'  -- 'detailled' or 'none' or 'concise'
   self.max_packet_size = 1500 or args.max_packet_size
   self.nf = args.nf
   self.profiler = self.nf.profiler

   -- compulsory
   if (self.core == nil) then
      error('<neuflow.Ethernet> ERROR: requires a Dataflow Core')
   end
end

function Ethernet:open()
   etherflow.open()
end

function Ethernet:close()
   etherflow.close()
end

function Ethernet:sendReset()
   if (-1 == etherflow.sendreset()) then
      print('<reset> fail')
   end
end

function Ethernet:dev_copyToHost(tensor, ack)
   if ack ~= 'no-ack' then
      self.core:startProcess()
      self:printToEthernet('copy-starting')
      self.core:endProcess()
   end

   for i = 1,#tensor do
      self.core:startProcess()
      self:streamToHost(tensor[i], 'default', ack)
      self.core:endProcess()
   end
end

function Ethernet:dev_copyFromHost(tensor)
   for i = 1,#tensor do
      self.core:startProcess()
      self:streamFromHost(tensor[i], 'default')
      self.core:endProcess()
   end

   -- always print a dummy flag, useful for profiling
   self.core:startProcess()
   self:printToEthernet('copy-done')
   self.core:endProcess()
end

function Ethernet:dev_receiveBytecode()
   self:loadByteCode()
end

function Ethernet:host_copyToDev(tensor)
   self.profiler:start('copy-to-dev')
   for i = 1,tensor:size(1) do
      etherflow.sendtensor(tensor[i])
   end
   self:getFrame('copy-done')
   self.profiler:lap('copy-to-dev')
end

function Ethernet:host_copyFromDev(tensor, handshake)
   profiler_neuflow = self.profiler:start('on-board-processing')
   self.profiler:setColor('on-board-processing', 'blue')
   self:getFrame('copy-starting')
   self.profiler:lap('on-board-processing')

   self.profiler:start('copy-from-dev')
   etherflow.handshake(handshake)
   for i = 1,tensor:size(1) do
      etherflow.receivetensor(tensor[i])
   end
   self.profiler:lap('copy-from-dev')
end

function Ethernet:host_sendBytecode(bytecode)
   self.profiler:start('load-bytecode')
   etherflow.loadbytecode(bytecode)
   self.profiler:lap('load-bytecode')
end


function Ethernet:startCom()
   -- simple way of connecting to the host
   self:printToEthernet('start')
end

function Ethernet:ethernetBlockOnBusy()
   local reg = self.core.alloc_ur:get()
   local goto_tag = self.core:makeGotoTag()

   self.core:ioread(oFlower.io_ethernet_status, reg)
   self.core:bitandi(reg, 0x00000001, reg)
   self.core:gotoTagIfNonZero(goto_tag, reg)

   self.core.alloc_ur:free(reg)
end

function Ethernet:ethernetBlockOnIdle()
   local reg = self.core.alloc_ur:get()
   local goto_tag = self.core:makeGotoTag()

   self.core:ioread(oFlower.io_ethernet_status, reg)
   self.core:bitandi(reg, 0x00000001, reg)
   self.core:gotoTagIfZero(goto_tag, reg)

   self.core.alloc_ur:free(reg)
end

function Ethernet:ethernetWaitForPacket()
   local reg = self.core.alloc_ur:get()
   local goto_tag = self.core:makeGotoTag()

   self.core:ioread(oFlower.io_ethernet_status, reg)
   self.core:bitandi(reg, 0x00000002, reg)
   self.core:gotoTagIfZero(goto_tag, reg)

   self.core.alloc_ur:free(reg)
end

function Ethernet:ethernetStartTransfer(size)
   local reg = self.core.alloc_ur:get()
   local status = bit.lshift(size, 16)
   status = bit.bor(status, 0x00000001)
   self.core:setreg(reg, status)
   self.core:iowrite(oFlower.io_ethernet_status, reg)

   self.core.alloc_ur:free(reg)
end

function Ethernet:printToEthernet(str)
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

   -- (1) verify that ethernet module is not busy (status bit 0)
   self:ethernetBlockOnBusy()

   -- (2) write data to buffer
   self.core:addInstruction{opcode = oFlower.op_writeStream, 
                            arg8_1 = oFlower.io_ethernet,
                            arg8_3 = oFlower.type_uint32,
                            arg32_1 = math.ceil((data_size) / 4)}
   -- (2 bis) append data (+ potential padding):
   self.core:addDataString(str)
   for i=1,(data_size-string.len(str)) do
      self.core:addDataUINT8(0)
   end
   self.core:addDataPAD()

   -- (3) initialize transfer, by specifying length
   self:ethernetStartTransfer(data_size)

   -- (4) make sure it's started
   self:ethernetBlockOnIdle()
end

function Ethernet:streamToHost(stream, tag, mode)
   -- verif data size >= 64
   local data_size = stream.w * stream.h * 2
   if (data_size < 64) then
      error('<neuflow.Ethernet> ERROR: cant stream data packets smaller than 64 bytes')
   end

   -- estimate number of eth packets
   local nb_packets = math.ceil(data_size / self.max_packet_size)
   
   -- debug
   if (self.msg_level ~= 'none') then
      self.core:message(string.format('eth: sending %0d packets [tag = %s]', nb_packets, tag))
   end

   if mode ~= 'no-ack' then
      -- (1) specify: name | size | nb_packets
      self:printToEthernet(string.format('TX | %s | %0d | %0d', tag, data_size, nb_packets))
   end
   
   -- (1) a sleep ?
   if data_size < 30*30*2 then
      self.core:sleep(50e-6)
   end
 
   local last_packet = 0
   if (data_size % self.max_packet_size ~= 0) then
      nb_packets = nb_packets - 1
      last_packet = data_size % self.max_packet_size
   end
   
   if (last_packet%4 ~= 0) then
      stream.w = stream.w + stream.orig_w
      stream.orig_h = stream.orig_h + 1
      data_size = stream.w * stream.h * 2
      nb_packets = math.ceil(data_size / self.max_packet_size)
      last_packet = 0
      if (data_size % self.max_packet_size ~= 0) then
         nb_packets = nb_packets - 1
         last_packet = data_size % self.max_packet_size
      end
   end 
   
   -- (2) open the streamer port for readout
   self.core:openPortRd(1, stream)
   -- (3) stream packets of self.max_packet_size bytes max
   if (nb_packets > 0) then
      local reg = self.core.alloc_ur:get()
      self.core:setreg(reg, nb_packets)
      local goto_tag = self.core:makeGotoTag()
      
      local packet_size = self.max_packet_size
      
      -- (b) 
      self.core:addInstruction{opcode = oFlower.op_routeStream,
                               arg8_1 = oFlower.io_dma,
                               arg8_2 = oFlower.io_ethernet,
                               arg8_3 = oFlower.type_uint32,
                               arg32_1 = math.ceil(packet_size / 4)}
      -- (a) verify that ethernet module is not busy (status bit 0)
      self:ethernetBlockOnBusy()
      -- (c) initialize transfer, by specifying length
      self:ethernetStartTransfer(packet_size)
      -- (d) wait for transfer started
      self:ethernetBlockOnIdle()
      self.core:addi(reg, -1, reg)
      self.core:gotoTagIfNonZero(goto_tag, reg)

      self.core.alloc_ur:free(reg)
   end
   
   if(last_packet ~= 0) then
      packet_size = last_packet
      
      if (math.floor(packet_size/4)*4 ~= packet_size) then
         error('<neuflow.Ethernet> ERROR: eth frame not fit for the DMA [this needs to be fixed]')
      end 
      
      -- (b) 
      self.core:addInstruction{opcode = oFlower.op_routeStream,
                               arg8_1 = oFlower.io_dma,
                               arg8_2 = oFlower.io_ethernet,
                               arg8_3 = oFlower.type_uint32,
                               arg32_1 = math.ceil(packet_size / 4)}
      
      -- ()
      if (packet_size < 64) then 
         local to_pad = 64 - packet_size
         -- (2) write data to buffer
         self.core:addInstruction{opcode = oFlower.op_writeStream, 
                                  arg8_1 = oFlower.io_ethernet,
                                  arg8_3 = oFlower.type_uint32,
                                  arg32_1 = math.ceil((to_pad) / 4)}
         -- (2 bis) append padding:
         for i=1,to_pad do
            self.core:addDataUINT8(0)
         end
         if (math.ceil((to_pad) / 4) == 1) then 
            self.core:addDataUINT8(0)
         end
         self.core:addDataPAD()
	 --print('added', math.ceil((to_pad) / 4))
         packet_size = 64
      end
      
      -- (a) verify that ethernet module is not busy (status bit 0)
      self:ethernetBlockOnBusy()
      
      -- (c) initialize transfer, by specifying length
      self:ethernetStartTransfer(packet_size)
      -- (d) wait for transfer started
      self:ethernetBlockOnIdle()
      
   end
   
   -- () wait for transfer complete
   self:ethernetBlockOnBusy()
   
   -- (4) close port
   self.core:closePort(1)
   
   if (not mode) or (mode and mode == 'with-ack') then
      -- (5) get ack
      -- (b) wait for a packet
      self:ethernetWaitForPacket()
      self.core:addInstruction{opcode = oFlower.op_routeStream,
                               arg8_1 = oFlower.io_ethernet,
                               arg8_2 = oFlower.io_uart_status, -- /dev/null
                               arg8_3 = oFlower.type_uint32,
                               arg32_1 = 16}
   elseif mode ~= 'no-ack' then
      error('ERROR <Ethernet> : mode can be one of: with-ack | no-ack')
   end
end

function Ethernet:streamToHost_ack(stream, tag, mode)
   -- verif data size >= 64
   local data_size = stream.w * stream.h * 2
   if (data_size < 64) then
      error('<neuflow.Ethernet> ERROR: cant stream data packets smaller than 64 bytes')
   end

   -- estimate number of eth packets
   local nb_packets = math.ceil(data_size / self.max_packet_size)
   
   -- debug
   if (self.msg_level ~= 'none') then
      self.core:message(string.format('eth: sending %0d packets [tag = %s]', nb_packets, tag))
   end

   -- (1) specify: name | size | nb_packets
   self:printToEthernet(string.format('TX | %s | %0d | %0d', tag, data_size, nb_packets))
   
   -- (1) a sleep ?
   if data_size < 30*30*2 then
      self.core:sleep(50e-6)
   end
 
   local last_packet = 0
   if (data_size % self.max_packet_size ~= 0) then
      nb_packets = nb_packets - 1
      last_packet = data_size % self.max_packet_size
   end
   
   if (last_packet%4 ~= 0) then
      stream.w = stream.w + stream.orig_w
      stream.orig_h = stream.orig_h + 1
      data_size = stream.w * stream.h * 2
      nb_packets = math.ceil(data_size / self.max_packet_size)
      last_packet = 0
      if (data_size % self.max_packet_size ~= 0) then
         nb_packets = nb_packets - 1
         last_packet = data_size % self.max_packet_size
      end
   end 
   
   -- (2) open the streamer port for readout
   self.core:openPortRd(1, stream)
   local count = 1
   -- (3) stream packets of self.max_packet_size bytes max
   if (nb_packets > 0) then
      local reg = self.core.alloc_ur:get()
      self.core:setreg(reg, nb_packets)
      local goto_tag = self.core:makeGotoTag()
      
      local packet_size = self.max_packet_size
      
      -- (b) 
      self.core:addInstruction{opcode = oFlower.op_routeStream,
                               arg8_1 = oFlower.io_dma,
                               arg8_2 = oFlower.io_ethernet,
                               arg8_3 = oFlower.type_uint32,
                               arg32_1 = math.ceil(packet_size / 4)}
      -- (a) verify that ethernet module is not busy (status bit 0)
      self:ethernetBlockOnBusy()
      -- (c) initialize transfer, by specifying length
      self:ethernetStartTransfer(packet_size)
      -- (d) wait for transfer started
      self:ethernetBlockOnIdle()

      
      if (not mode) or (mode and mode == 'with-ack') then
	 -- (5) get ack
	 -- (b) wait for a packet
	 self:ethernetBlockOnBusy()
	 self:ethernetWaitForPacket()
	 self.core:addInstruction{opcode = oFlower.op_routeStream,
				  arg8_1 = oFlower.io_ethernet,
				  arg8_2 = oFlower.io_uart_status, -- /dev/null
				  arg8_3 = oFlower.type_uint32,
				  arg32_1 = 16}
	 --self:ethernetBlockOnIdle()
      elseif mode ~= 'no-ack' then
	 error('ERROR <Ethernet> : mode can be one of: with-ack | no-ack')
      end 
      
      self.core:addi(reg, -1, reg)
      self.core:gotoTagIfNonZero(goto_tag, reg)
      count = count + 1

      self.core.alloc_ur:free(reg)
   end
   
   if(last_packet ~= 0) then
      packet_size = last_packet
      
      if (math.floor(packet_size/4)*4 ~= packet_size) then
         error('<neuflow.Ethernet> ERROR: eth frame not fit for the DMA [this needs to be fixed]')
      end 
      
      -- (b) 
      self.core:addInstruction{opcode = oFlower.op_routeStream,
                               arg8_1 = oFlower.io_dma,
                               arg8_2 = oFlower.io_ethernet,
                               arg8_3 = oFlower.type_uint32,
                               arg32_1 = math.ceil(packet_size / 4)}
      
      -- ()
      if (packet_size < 64) then 
         local to_pad = 64 - packet_size
         -- (2) write data to buffer
         self.core:addInstruction{opcode = oFlower.op_writeStream, 
                                  arg8_1 = oFlower.io_ethernet,
                                  arg8_3 = oFlower.type_uint32,
                                  arg32_1 = math.ceil((to_pad) / 4)}
         -- (2 bis) append padding:
         for i=1,to_pad do
            self.core:addDataUINT8(0)
         end
         if (math.ceil((to_pad) / 4) == 1) then 
            self.core:addDataUINT8(0)
         end
         self.core:addDataPAD()
	 --print('added', math.ceil((to_pad) / 4))
         packet_size = 64
      end
      
      -- (a) verify that ethernet module is not busy (status bit 0)
      self:ethernetBlockOnBusy()
      
      -- (c) initialize transfer, by specifying length
      self:ethernetStartTransfer(packet_size)
      -- (d) wait for transfer started
      self:ethernetBlockOnIdle()


      if (not mode) or (mode and mode == 'with-ack') then
	 -- (5) get ack
	 -- (b) wait for a packet
	 self:ethernetBlockOnBusy()
	 self:ethernetWaitForPacket()
	 self.core:addInstruction{opcode = oFlower.op_routeStream,
				  arg8_1 = oFlower.io_ethernet,
				  arg8_2 = oFlower.io_uart_status, -- /dev/null
				  arg8_3 = oFlower.type_uint32,
				  arg32_1 = 16}
	 --self:ethernetBlockOnIdle()
      elseif mode ~= 'no-ack' then
	 error('ERROR <Ethernet> : mode can be one of: with-ack | no-ack')
      end 

      
   end
   
   -- () wait for transfer complete
   --self:ethernetBlockOnBusy()
   
   -- (4) close port
   self.core:closePort(1)
   
   -- if (not mode) or (mode and mode == 'with-ack') then
--       print('here')
--       -- (5) get ack
--       -- (b) wait for a packet
--       self:ethernetWaitForPacket()
--       self.core:addInstruction{opcode = oFlower.op_routeStream,
--                                arg8_1 = oFlower.io_ethernet,
--                                arg8_2 = oFlower.io_uart_status, -- /dev/null
--                                arg8_3 = oFlower.type_uint32,
--                                arg32_1 = 16}
--    elseif mode ~= 'no-ack' then
--       error('ERROR <Ethernet> : mode can be one of: with-ack | no-ack')
--    end
end

function Ethernet:streamFromHost_legacy(stream, tag)
   -- verif data size >= 64
   local data_size = stream.w * stream.h * 2
   if (data_size < 64) then
      error('<neuflow.Ethernet> ERROR: cant stream data packets smaller than 64 bytes')
   end
   
   -- for compilation
   print('# ethernet RX: '..stream.w..'x'..stream.h..' stream')
   
   -- estimate number of eth packets
   local nb_packets = math.ceil(data_size / self.max_packet_size)
   
   -- debug
   if (self.msg_level ~= 'none') then
      self.core:message(string.format('eth: requesting %0d packets [tag = %s]', nb_packets, tag))
   end
   
   -- (1) specify: name | size | nb_packets
   self:printToEthernet(string.format('RX | %s | %0d | %0d', tag, data_size, nb_packets))

   local last_packet = 0
   if (data_size % self.max_packet_size ~= 0) then
      nb_packets = nb_packets - 1
 last_packet = data_size % self.max_packet_size
   end
   
   -- (2) open the streamer port for readout
   self.core:openPortWr(1, stream)
   
   
   -- (3) request packets of self.max_packet_size bytes max
   if (nb_packets > 0) then
      local reg = self.core.alloc_ur:get()
      self.core:setreg(reg, nb_packets)
      local goto_tag = self.core:makeGotoTag()
      local packet_size = self.max_packet_size
      
      -- (a) request a particular nb of bytes from the host
      self:printToEthernet(string.format('REQ | %0d', packet_size))
      -- (b) wait for a packet
      self:ethernetWaitForPacket()
      -- (c) receive data
      self.core:addInstruction{opcode = oFlower.op_routeStream,
                               arg8_1 = oFlower.io_ethernet,
                               arg8_2 = oFlower.io_dma,
                               arg8_3 = oFlower.type_uint32,
                               arg32_1 = math.ceil(packet_size / 4)}
      if (self.msg_level == 'concise') then
	 self.core:messagebody('.')
      end
      -- (d) loopback
      self.core:addi(reg, -1, reg)
      self.core:gotoTagIfNonZero(goto_tag, reg)

      self.core.alloc_ur:free(reg)
   end
   
   if(last_packet ~= 0) then
      packet_size = last_packet
      
      -- (a) request a particular nb of bytes from the host
      self:printToEthernet(string.format('REQ | %0d', packet_size))
      -- (b) wait for a packet
      self:ethernetWaitForPacket()
      -- (c) receive data
      self.core:addInstruction{opcode = oFlower.op_routeStream,
                               arg8_1 = oFlower.io_ethernet,
                               arg8_2 = oFlower.io_dma,
                               arg8_3 = oFlower.type_uint32,
                               arg32_1 = math.ceil(packet_size / 4)}
      -- (d) leftovers
      if packet_size < 64 then
	 self.core:addInstruction{opcode = oFlower.op_routeStream,
                                  arg8_1 = oFlower.io_ethernet,
                                  arg8_2 = oFlower.io_uart_status,
                                  arg8_3 = oFlower.type_uint32,
                                  arg32_1 = 16-math.ceil(packet_size / 4)}
      end
   end
   
   -- (4) close port
   self.core:closePort(1)
end

function Ethernet:streamFromHost(stream, tag)
   -- verif data size >= 64
   local data_size = stream.w * stream.h * 2
   if (data_size < 64) then
      error('<neuflow.Ethernet> ERROR: cant stream data packets smaller than 64 bytes')
   end
   
   -- estimate number of eth packets
   local nb_packets = math.ceil(data_size / self.max_packet_size)
   
   -- debug
   if (self.msg_level ~= 'none') then
      self.core:message(string.format('eth: requesting %0d packets [tag = %s]', nb_packets, tag))
   end
   
   -- (1) specify: name | size | nb_packets
   self:printToEthernet(string.format('RX | %s | %0d | %0d', tag, data_size, nb_packets))
   
   local last_packet = 0
   if (data_size % self.max_packet_size ~= 0) then
      nb_packets = nb_packets - 1
      last_packet = data_size % self.max_packet_size
   end
   
   -- (2) open the streamer port for readout
   self.core:openPortWr(1, stream)
   
   -- (3) receive data
   self.core:addInstruction{opcode = oFlower.op_routeStream,
                            arg8_1 = oFlower.io_ethernet,
                            arg8_2 = oFlower.io_dma,
                            arg8_3 = oFlower.type_uint32,
                            arg32_1 = nb_packets*math.ceil(self.max_packet_size / 4)}
   if (self.msg_level == 'concise') then
      self.core:messagebody('.')
   end
   
   -- (3bis) last packet ?
   if(last_packet ~= 0) then
      -- (a) receive data
      self.core:addInstruction{opcode = oFlower.op_routeStream,
                               arg8_1 = oFlower.io_ethernet,
                               arg8_2 = oFlower.io_dma,
                               arg8_3 = oFlower.type_uint32,
                               arg32_1 = math.ceil(last_packet / 4)}
      -- (b) clean leftovers
      if last_packet < 64 then
	 self.core:addInstruction{opcode = oFlower.op_routeStream,
                                  arg8_1 = oFlower.io_ethernet,
                                  arg8_2 = oFlower.io_uart_status,
                                  arg8_3 = oFlower.type_uint32,
                                  arg32_1 = 16-math.ceil(last_packet / 4)}
      end	      
   end
   
   -- (4) close port
   self.core:closePort(1)
end


function Ethernet:loopBack(size)
   -- debug
   if (self.msg_level == 'detailled') then
      self.core:message(string.format('looping back one %d-long packet', size))
   end
   
   -- (a) wait for a packet to be there, and TX to be ready
   self:ethernetWaitForPacket()
   self:ethernetBlockOnBusy()
   
   -- (b) receive data
   self.core:addInstruction{opcode = oFlower.op_routeStream,
                            arg8_1 = oFlower.io_ethernet,
                            arg8_2 = oFlower.io_ethernet,
                            arg8_3 = oFlower.type_uint32,
                            arg32_1 = math.ceil(size / 4)}
   
   -- (c) trigger the sending
   self:ethernetStartTransfer(size)
end

function Ethernet:streamFromHost_ack(stream, tag)
   -- verif data size >= 64
   local data_size = stream.w * stream.h * 2
   if (data_size < 64) then
      error('<neuflow.Ethernet> ERROR: cant stream data packets smaller than 64 bytes')
   end
   
   -- estimate number of eth packets
   local nb_packets = math.ceil(data_size / self.max_packet_size)
   
   -- debug
   if (self.msg_level ~= 'none') then
      self.core:message(string.format('eth: requesting %0d packets [tag = %s]', nb_packets, tag))
   end
   
   -- (1) specify: name | size | nb_packets
   self:printToEthernet(string.format('RX | %s | %0d | %0d', tag, data_size, nb_packets))
   
   local last_packet = 0
   if (data_size % self.max_packet_size ~= 0) then
      nb_packets = nb_packets - 1
      last_packet = data_size % self.max_packet_size
   end
   
   -- (2) open the streamer port for readout
   self.core:openPortWr(1, stream)
   

    -- (3) request packets of self.max_packet_size bytes max
   if (nb_packets > 0) then
      local reg = self.core.alloc_ur:get()
      self.core:setreg(reg, nb_packets)
      local goto_tag = self.core:makeGotoTag()
      local packet_size = self.max_packet_size
      
      -- (a) request a particular nb of bytes from the host
      self:printToEthernet(string.format('REQ | %0d', packet_size))
      
      
      -- (c) receive data
      self.core:addInstruction{opcode = oFlower.op_routeStream,
                               arg8_1 = oFlower.io_ethernet,
                               arg8_2 = oFlower.io_dma,
                               arg8_3 = oFlower.type_uint32,
                               arg32_1 = math.ceil(packet_size / 4)}
      if (self.msg_level == 'concise') then
	 self.core:messagebody('.')
      end
      -- (d) loopback
      self.core:addi(reg, -1, reg)
      self.core:gotoTagIfNonZero(goto_tag, reg)

      self.core.alloc_ur:free(reg)
   end



   -- (3) receive data
   -- self.core:addInstruction{opcode = oFlower.op_routeStream,
--                             arg8_1 = oFlower.io_ethernet,
--                             arg8_2 = oFlower.io_dma,
--                             arg8_3 = oFlower.type_uint32,
--                             arg32_1 = nb_packets*math.ceil(self.max_packet_size / 4)}
   if (self.msg_level == 'concise') then
      self.core:messagebody('.')
   end
   
   -- (3bis) last packet ?
   if(last_packet ~= 0) then

      self:printToEthernet(string.format('REQ | %0d', last_packet))

      -- (a) receive data
      self.core:addInstruction{opcode = oFlower.op_routeStream,
                               arg8_1 = oFlower.io_ethernet,
                               arg8_2 = oFlower.io_dma,
                               arg8_3 = oFlower.type_uint32,
                               arg32_1 = math.ceil(last_packet / 4)}
      -- (b) clean leftovers
      if last_packet < 64 then
	 self.core:addInstruction{opcode = oFlower.op_routeStream,
                                  arg8_1 = oFlower.io_ethernet,
                                  arg8_2 = oFlower.io_uart_status,
                                  arg8_3 = oFlower.type_uint32,
                                  arg32_1 = 16-math.ceil(last_packet / 4)}
      end	      
   end
   
   -- (4) close port
   self.core:closePort(1)
  
end

function Ethernet:loadByteCode()
   -- Creating a stream
   local bytecode_stream = {x = 0, y = 0, w = 1024, h = 16*1024}

   -- Regular streamFromHost
   self:streamFromHost(bytecode_stream, 'bytecode')

   -- Jump to address 0 and execute 
   self.core:gotoGlobal(bootloader.entry_point)
end

----------------------------------------------------------------------
-- helper functions:
--   getFrame() receives a frame
--   parse_descriptor() parses the frame received
--
function Ethernet:getFrame(tag, type)
   local data
   data = etherflow.receivestring()
   if (data:sub(1,2) == type) then
      tag_received = self:parse_descriptor(data)
   end
   return (tag_received == tag)
end

function Ethernet:parse_descriptor(s)
   local reg_word = "%s*([-%w.+]+)%s*"
   local reg_pipe = "|"
   ni,j,type,tag,size,nb_frames = string.find(s, reg_word .. reg_pipe .. reg_word .. reg_pipe ..
                                              reg_word .. reg_pipe .. reg_word)
   return tag, type
end
