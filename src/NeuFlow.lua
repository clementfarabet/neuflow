
--------------------------------------------------------------------------------
-- NeuFlow
-- a class to abstract the neuFlow processor
--

----------------------------------------------------------------------
-- register class + constructor
--
local NeuFlow = torch.class('neuflow.NeuFlow')

function NeuFlow:__init(args)
   -- parse args
   args = args or {}
   self.prog_name = args.prog_name or 'temp'
   self.use_ethernet = args.use_ethernet or false
   self.serial_device = args.serial_device or false
   self.global_msg_level = args.global_msg_level or 'none'
   self.mode = args.mode or 'runtime' -- or 'simulation' or 'rom'
   self.use_ethernet = (self.mode == 'runtime')
   if(args.network_if_name) then
      self.network_if_name = args.network_if_name
   end

   -- default offsets, for conveniency
   args.offset_code = args.offset_code or bootloader.entry_point_b
   -- in simul, bypass header
   if self.mode == 'simulation' then
      args.offset_code = 0
   end

   -- instantiate core, with all args
   args.msg_level = args.core_msg_level or self.global_msg_level
   self.core = neuflow.Core(args)

   -- instantiate the compiler, relies on the core
   self.compiler = neuflow.Compiler{optimize_across_layers = true,
                                    core = self.core,
                                    msg_level = args.compiler_msg_level or self.global_msg_level}

   -- use a profiler
   self.profiler = neuflow.Profiler()

   -- instantiate the interface
   if (self.core.platform == 'pico_m503') or (self.core.platform == 'xilinx_ml605_tbsp') then
      self.handshake = false
      self.ethernet = neuflow.DmaEthernet{msg_level = args.ethernet_msg_level or self.global_msg_level,
                                          core = self.core,
                                          nf = self}
   else
      self.handshake = true
      self.ethernet = neuflow.Ethernet{msg_level = args.ethernet_msg_level or self.global_msg_level,
                                       core = self.core,
                                       nf = self}
   end

   -- for loops: this retains a list of jump locations
   self.loopTags = {}

   -- ethernet socket (auto found for now)
   if self.use_ethernet then
      print '<neuflow.NeuFlow> loading ethernet driver'
      if self.ethernet:open(self.network_if_name) ~= 0 then
         self.use_ethernet = false
      end
   end

   -- serial dev
   if self.serial_device then
      self.tty = neuflow.Serial(self.serial_device, '57600')
   end

   -- bytecode has a constant size (oFlower bios)
   self.bytecodesize = bootloader.load_size

   -- data ack
   self.ack_tensor = torch.Tensor(1,1,32)
   self.ack_stream = self:allocHeap(self.ack_tensor)

   -- and finally initialize hardware
   self:initialize()
end

----------------------------------------------------------------------
-- ending functions: this is not clean for now, but insures that
-- the hardware stays in sync.
--
function NeuFlow:cleanup()
   if self.use_ethernet then
      self.ethernet:close()
   end
   if self.tty then
      self.tty:cleanup()
   end
end

----------------------------------------------------------------------
-- print messages / send message
--
function NeuFlow:printMessage()
   if self.tty then
      print(self.tty:read())
   end
end

function NeuFlow:sendMessage(message)
   if self.tty then
      self.tty:write(message)
   end
end

----------------------------------------------------------------------
-- initialize system
--
function NeuFlow:initialize(args)
   -- args
   if args and args.selftest then
      self.core:bootSequence{selftest=true}
   else
      self.core:bootSequence{selftest=false}
   end
end

----------------------------------------------------------------------
-- high-level memory functions
--
function NeuFlow:allocHeap(tensor)
   local alloc_list = {}
   if type(tensor) == 'table' then
      local first = true
      for i = 1,#tensor do
         if tensor[i]:nDimension() ~= 2 then
            xlua.error('only supports list of 2D tensors','NeuFlow.allocHeap')
         end
         local segment = self.core.mem:allocOnTheHeap(tensor[i]:size(1), tensor[i]:size(2), nil, first)
         table.insert(alloc_list, segment)
         first = false
      end
   else
      local dims = tensor:nDimension()
      if dims == 2 then
         local segment = self.core.mem:allocOnTheHeap(tensor:size(1), tensor:size(2), nil, true)
         table.insert(alloc_list, segment)
      elseif dims == 3 then
         local first = true
         for i = 1,tensor:size(1) do
            local segment = self.core.mem:allocOnTheHeap(tensor:size(2), tensor:size(3), nil, first)
            table.insert(alloc_list, segment)
            first = false
         end
      else
         error('tensors must have 2 or 3 dimensions')
      end
   end
   return alloc_list
end

function NeuFlow:allocDataPacked(tensor,bias)
   local alloc_list = {}
   if type(tensor) == 'table' then
      for i = 1,#tensor do
         if tensor[i]:nDimension() ~= 2 then
            xlua.error('only supports list of 2D tensors','NeuFlow.allocHeap')
         end
         local segment
         if bias then
            segment = self.core.mem:allocKernel(tensor[i]:size(1), tensor[i]:size(2),
                                            tensor[i], bias[i])
         else
            segment = self.core.mem:allocRawData(tensor[i]:size(1), tensor[i]:size(2), tensor[i])
         end
         table.insert(alloc_list, segment)
      end
   else
      local dims = tensor:nDimension()
      if dims == 2 then
         local segment
         if bias then
            segment = self.core.mem:allocKernel(tensor:size(1), tensor:size(2), tensor, bias)
         else
            segment = self.core.mem:allocRawData(tensor:size(1), tensor:size(2), tensor)
         end
         table.insert(alloc_list, segment)
      elseif dims == 3 then
         for i = 1,tensor:size(1) do
            local segment
            if bias then
               segment = self.core.mem:allocKernel(tensor:size(2), tensor:size(3),
                                               tensor[i], bias:narrow(1,i,1))
            else
               segment = self.core.mem:allocRawData(tensor:size(2), tensor:size(3),
                                                tensor[i])
            end
            table.insert(alloc_list, segment)
         end
      else
         error('tensors must have 2 or 3 dimensions')
      end
   end
   return alloc_list
end

function NeuFlow:allocData(tensor)
   local alloc_list = {}
   if type(tensor) == 'table' then
      for i = 1,#tensor do
         if tensor[i]:nDimension() ~= 2 then
            xlua.error('only supports list of 2D tensors','NeuFlow.allocHeap')
         end
         local segment = self.core.mem:allocImageData(tensor[i]:size(1), tensor[i]:size(2),
                                                  tensor[i])
         table.insert(alloc_list, segment)
      end
   else
      local dims = tensor:nDimension()
      if dims == 2 then
         local segment = self.core.mem:allocImageData(tensor:size(1), tensor:size(2), tensor)
         table.insert(alloc_list, segment)
      elseif dims == 3 then
         for i = 1,tensor:size(1) do
            local segment = self.core.mem:allocImageData(tensor:size(2), tensor:size(3),
                                                     tensor[i])
            table.insert(alloc_list, segment)
         end
      else
         error('tensors must have 2 or 3 dimensions')
      end
   end
   return alloc_list
end

function NeuFlow:copy(source, dest)
   -- check if source/dest are lists of streams, or streams
   if #source == 0 then
      source = {source}
      if dest then
         dest = {dest}
      end
   end

   -- if no dest, create it
   if not dest then
      dest = self:allocHeap(source)
   end

   -- process a list of streams
   for i = 1,#source do
      self.core:copy(source[i],dest[i])
   end

   -- return result
   return dest
end

function NeuFlow:copyFromHost(source, dest)
   -- if no dest, create it
   if not dest then
      dest = self:allocHeap(source)
   end
   -- check if dest is a list of streams, or a stream
   local ldest
   if #dest == 0 then
      ldest = {dest}
   else
      ldest = dest
   end
   -- if simulation, we replace this transfer by a plain copy
   if self.mode == 'simulation' then
      -- alloc in constant data:
      source = self:allocData(source)
      print('<neuflow.NeuFlow> copy host->dev [simul]: ' .. #ldest .. 'x' .. ldest[1].orig_h .. 'x' .. ldest[1].orig_w)
      self:copy(source,ldest)
   else
      -- process list of streams
      print('<neuflow.NeuFlow> copy host->dev: ' .. #ldest .. 'x' .. ldest[1].orig_h .. 'x' .. ldest[1].orig_w)

      self.ethernet:dev_copyFromHost(ldest)
   end

   return dest
end

function NeuFlow:copyToHost(source, dest)
   -- no ack in simulation
   local ack
   if self.mode == 'simulation' or (not self.handshake) then
      ack = 'no-ack'
   end

   -- check if source is a list of streams, or a stream
   local lsource
   if #source == 0 then
      lsource = {source}
   else
      lsource = source
   end

   -- record original sizes
   local orig_h = lsource[1].orig_h
   local orig_w = lsource[1].orig_w

   -- process list of streams
   print('<neuflow.NeuFlow> copy dev->host: ' .. #lsource .. 'x' .. lsource[1].orig_h .. 'x' .. lsource[1].orig_w)

   self.ethernet:dev_copyToHost(lsource, ack)

   -- create/resize dest
   if not dest then
      dest = torch.Tensor()
   end
   dest:resize(#lsource, orig_h, orig_w)
   return dest
end

----------------------------------------------------------------------
-- wrappers for compilers
--
function NeuFlow:compile(network, input)
   -- retrieve IDs
   local inputs
   if #input == 0 then
      inputs = { input }
   else
      inputs = input
   end

   local outputs
   outputs, self.gops = self.compiler:processNetwork(network, inputs)

   return outputs
end

----------------------------------------------------------------------
-- high-level GOTO functions
--
function NeuFlow:beginLoop(tag)
   self.loopTags.tag = self.core:makeGotoTag()
   self.loopTags.tag.offset = 1
   self.core:startProcess()
   self.core:endProcess()
end

function NeuFlow:endLoop(tag)
   self.core:startProcess()
   self.core:defaults()
   self.core:gotoTag(self.loopTags.tag)
   self.core:endProcess()
end

function NeuFlow:term()
   self.core:startProcess()
   self.core:terminate()
   self.core:endProcess()
end

----------------------------------------------------------------------
-- write bytecode in binary/hex mode
--
function NeuFlow:writeBytecode(args)
   -- parse args
   local filename = args.filename or self.prog_name
   local filepath
   local tensor = torch.ByteTensor(self.bytecodesize):zero()

   -- generate binary once
   local tensor_size = self.core.linker:dump(
      {
         tensor   = tensor,
         filename = filename,
      },
      self.core.mem
   )

   if next(args) ~= nil then -- called with arguments pasted in
      filepath = '/tmp/' .. filename .. '-' .. os.date("%Y_%m_%d_%H_%M_%S") .. '.bin'
      local file = assert(torch.DiskFile(filepath,'w'):binary())
      file:writeString(tensor:storage():string():sub(1, tensor_size))
      assert(file:close())
   end

   -- generate all outputs
   for _,args in ipairs(args) do
      -- args
      local format = args.format or 'bin' -- or 'hex'
      local width = args.width or 8
      local length = args.length

      if format == 'bin' then
         -- simple copy
         os.execute('cp -v' .. filepath .. ' ' .. filename .. '.bin')
      elseif format == 'hex' then
         local filehex = filename..'.hex'..tostring(width)
         neuflow.tools.readBinWriteHex(filepath, filehex, width, length)
      elseif format == 'rom' then
         local filev = filename..'.v'
         neuflow.tools.readBinWriteRom(filepath, filev, width, 'flow_rom')
      else
         error('format should be one of: bin | hex')
      end
   end

   return tensor
end

----------------------------------------------------------------------
-- execute simulation (testbench)
--
function NeuFlow:execSimulation(args)
   local testbench = args.testbench or error('please provide a testbench script')
   local cache_hex = args.cache_hex or error('please provide path for cache hex mask')
   local mem_hex = args.mem_hex or error('please provide path for mem hex mask')

   print('<neuflow.NeuFlow> exporting compiled code [hex]')
   self:writeBytecode{{format='hex', width=oFlower.bus_, length=oFlower.cache_size_b},
                      {format='hex', width=streamer.mem_bus_}}

   -- platform-dependent memories:
   if self.core.platform == 'ibm_asic' then
      os.execute('mv '..self.prog_name..'.hex64 '..cache_hex)
      for subidx = 0,7 do
         os.execute('cut -c'..(subidx*8+1)..'-'..(subidx*8+8)..' '
              ..self.prog_name..'.hex256 > '..mem_hex..'.'..(subidx+1))
      end
      os.execute('rm '..self.prog_name..'.hex256 ')
   else
      os.execute('mv '..self.prog_name..'.hex64 '..cache_hex)
      os.execute('mv '..self.prog_name..'.hex256 '..mem_hex)
   end

   local c = sys.COLORS
   print(c._cyan)
   print('<neuflow.NeuFlow> running compiled bytecode in simulation')
   local path = paths.dirname(testbench)
   local script = paths.basename(testbench)
   os.execute('cd ' .. path .. '; ./' .. script .. ' ' .. options.tb_args)
   print(c.none)
end

----------------------------------------------------------------------
-- transmit reset
--
function NeuFlow:sendReset()
   self.ethernet:sendReset()
end

----------------------------------------------------------------------
-- tell device to wait for the bytecode to be sent from the host
--
function NeuFlow:receiveBytecode()
   self.ethernet:dev_receiveBytecode()
end

----------------------------------------------------------------------
-- send bytecode to device
--
function NeuFlow:sendBytecode(bytecode)
   self:loadBytecode(bytecode)
end

----------------------------------------------------------------------
-- transmit bytecode
--
function NeuFlow:loadBytecode(bytecode)
   if bytecode then
      -- then transmit bytecode
      print('<neuflow.NeuFlow> transmitting bytecode')
      self.ethernet:host_sendBytecode(bytecode)
   else
      -- if no bytecode given, first dump it to file, then load it from there
      self:loadBytecode(self:writeBytecode{})
   end
end

----------------------------------------------------------------------
-- transmit bytecode (from file)
--
function NeuFlow:loadBytecodeFromFile(filename)
   local file = assert(io.open(filename, "r"))
   local tensor = self:convertBytecodeString(file:read("*all"))
   file:close()

   self:loadBytecode(tensor)
end

function NeuFlow:convertBytecodeString(bytes)
   local tensor = torch.ByteTensor(self.bytecodesize)
   local i = 1
   for b in string.gfind(bytes, ".") do
      tensor[i] = string.byte(b)
      i = i+1
   end

   return tensor
end

----------------------------------------------------------------------
-- transmit tensor
--
function NeuFlow:copyToDev(tensor)
   self.ethernet:host_copyToDev(tensor)
end

----------------------------------------------------------------------
-- receive tensor
--
function NeuFlow:copyFromDev(tensor)
   self.ethernet:host_copyFromDev(tensor, self.handshake)
end
