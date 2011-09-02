
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

   -- default offsets, for conveniency
   args.offset_code = args.offset_code or bootloader.entry_point_b
   args.offset_data_1D = args.offset_data_1D or bootloader.entry_point_b + 16*MB
   args.offset_data_2D = args.offset_data_2D or bootloader.entry_point_b + 18*MB
   args.offset_heap = args.offset_heap or bootloader.entry_point_b + 20*MB

   -- use a log file
   self.logfile = neuflow.Log('/tmp/' .. self.prog_name .. '-' .. os.date("%Y_%m_%d_%H_%M_%S") .. '.log')

   -- instantiate core, with all args
   args.msg_level = args.core_msg_level or self.global_msg_level
   args.logfile = self.logfile
   self.core = neuflow.Core(args)

   -- instantiate the compiler, relies on the core
   self.compiler = neuflow.Compiler{optimize_across_layers = true,
                                    logfile = self.logfile,
                                    core = self.core,
                                    msg_level = args.compiler_msg_level or self.global_msg_level}

   -- instantiate the interface
   if self.core.platform == 'pico_m503' then
      self.ethernet = neuflow.DmaEthernet{msg_level = args.ethernet_msg_level or self.global_msg_level,
                                          core = self.core}
   else
      self.ethernet = neuflow.Ethernet{msg_level = args.ethernet_msg_level or self.global_msg_level,
                                       core = self.core}
   end

   -- for loops: this retains a list of jump locations
   self.loopTags = {}

   -- use a profiler
   self.profiler = neuflow.Profiler()

   -- ethernet socket (auto found for now)
   if self.use_ethernet then
      print '<neuflow.NeuFlow> loading ethernet driver'
      local l = xrequire 'etherflow'
      if not l then
         self.use_ethernet = false
      else
         etherflow.open()
      end
   end

   -- serial dev
   if self.serial_device then
      self.tty = neuflow.Serial(self.serial_device, '57600')
   end

   -- bytecode has a constant size (oFlower bios)
   self.bytecodesize = bootloader.load_size

   -- stupid hack
   self.first_time = true

   -- and finally initialize hardware
   self:initialize()
end

----------------------------------------------------------------------
-- ending functions: this is not clean for now, but insures that
-- the hardware stays in sync.
--
function NeuFlow:cleanup()
   if self.use_ethernet then
      etherflow.close()
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
         local idx = self.core.mem:allocOnTheHeap(tensor[i]:size(1), tensor[i]:size(2), nil, first)
         self.core.mem.buff[idx].id = idx
         table.insert(alloc_list, self.core.mem.buff[idx])
         first = false
      end
   else
      local dims = tensor:nDimension()
      if dims == 2 then
         local idx = self.core.mem:allocOnTheHeap(tensor:size(1), tensor:size(2), nil, true)
         self.core.mem.buff[idx].id = idx
         table.insert(alloc_list, self.core.mem.buff[idx])
      elseif dims == 3 then
         local first = true
         for i = 1,tensor:size(1) do
            local idx = self.core.mem:allocOnTheHeap(tensor:size(2), tensor:size(3), nil, first)
            self.core.mem.buff[idx].id = idx
            table.insert(alloc_list, self.core.mem.buff[idx])
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
         local idx
         if bias then
            idx = self.core.mem:allocKernel(tensor[i]:size(1), tensor[i]:size(2),
                                            tensor[i], bias[i])
         else
            idx = self.core.mem:allocRawData(tensor[i]:size(1), tensor[i]:size(2), tensor[i])
         end
         self.core.mem.raw_data[idx].id = idx
         table.insert(alloc_list, self.core.mem.raw_data[idx])
      end
   else
      local dims = tensor:nDimension()
      if dims == 2 then
         local idx
         if bias then
            idx = self.core.mem:allocKernel(tensor:size(1), tensor:size(2), tensor, bias)
         else
            idx = self.core.mem:allocRawData(tensor:size(1), tensor:size(2), tensor)
         end
         self.core.mem.raw_data[idx].id = idx
         table.insert(alloc_list, self.core.mem.raw_data[idx])
      elseif dims == 3 then
         for i = 1,tensor:size(1) do
            local idx
            if bias then
               idx = self.core.mem:allocKernel(tensor:size(2), tensor:size(3),
                                               tensor[i], bias:narrow(1,i,1))
            else
               idx = self.core.mem:allocRawData(tensor:size(2), tensor:size(3),
                                                tensor[i])
            end
            self.core.mem.raw_data[idx].id = idx
            table.insert(alloc_list, self.core.mem.raw_data[idx])
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
         local idx = self.core.mem:allocImageData(tensor[i]:size(1), tensor[i]:size(2),
                                                  tensor[i])
         self.core.mem.data[idx].id = idx
         table.insert(alloc_list, self.core.mem.data[idx])
      end
   else
      local dims = tensor:nDimension()
      if dims == 2 then
         local idx = self.core.mem:allocImageData(tensor:size(1), tensor:size(2), tensor)
         self.core.mem.data[idx].id = idx
         table.insert(alloc_list, self.core.mem.data[idx])
      elseif dims == 3 then
         for i = 1,tensor:size(1) do
            local idx = self.core.mem:allocImageData(tensor:size(2), tensor:size(3),
                                                     tensor[i])
            self.core.mem.data[idx].id = idx
            table.insert(alloc_list, self.core.mem.data[idx])
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


function NeuFlow:copyFromHost_ack(source, dest)
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
      for i = 1,#ldest do
         self.core:startProcess()
         self.ethernet:streamFromHost_ack(ldest[i], 'default')
         self.core:endProcess()
      end
   end
   -- always print a dummy flag, useful for profiling
   if self.mode ~= 'simulation' then
      self.core:startProcess()
      self.ethernet:printToEthernet('copy-done')
      self.core:endProcess()
   end
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
      for i = 1,#ldest do
         self.core:startProcess()
         self.ethernet:streamFromHost(ldest[i], 'default')
         self.core:endProcess()
      end
   end
   -- always print a dummy flag, useful for profiling
   if self.mode ~= 'simulation' then
      self.core:startProcess()
      self.ethernet:printToEthernet('copy-done')
      self.core:endProcess()
   end
   return dest
end



function NeuFlow:copyToHost(source, dest)
   -- no ack in simulation
   local ack
   if self.mode == 'simulation' then
      ack = 'no-ack'
   end
   -- always print a dummy flag, useful for profiling
   if self.mode ~= 'simulation' then
      self.core:startProcess()
      self.ethernet:printToEthernet('copy-starting')
      self.core:endProcess()
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
   for i = 1,#lsource do
      self.core:startProcess()
      self.ethernet:streamToHost(lsource[i], 'default', ack)
      self.core:endProcess()
   end
   -- create/resize dest
   if not dest then
      dest = torch.Tensor()
   end
   dest:resize(#lsource, orig_h, orig_w)
   return dest
end


function NeuFlow:copyToHost_ack(source, dest)
   -- no ack in simulation
   local ack
   if self.mode == 'simulation' then
      ack = 'no-ack'
   end
   -- always print a dummy flag, useful for profiling
   if self.mode ~= 'simulation' then
      self.core:startProcess()
      self.ethernet:printToEthernet('copy-starting')
      self.core:endProcess()
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
   for i = 1,#lsource do
      self.core:startProcess()
      self.ethernet:streamToHost_ack(lsource[i], 'default', ack)
      self.core:endProcess()
   end
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
function NeuFlow:compile(network, inputs)
   -- retrieve IDs
   input_ids = {}
   for i = 1,#inputs do
      input_ids[i] = inputs[i].id
   end
   local output_ids
   output_ids, self.gops = self.compiler:processNetwork(network, input_ids)
   -- return actual list of outputs
   local outputs = {}
   for i = 1,#output_ids do
      outputs[i] = self.core.mem.buff[output_ids[i]]
   end
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

   -- generate binary once
   self.tempfilebin = '/tmp/' .. filename .. '-' .. os.date("%Y_%m_%d_%H_%M_%S") .. '.bin'
   self.core.linker:dump({dumpHeader=false, file=self.tempfilebin, writeArray=false},
                         self.core.mem)

   -- generate all outputs
   for _,args in ipairs(args) do
      -- args
      local format = args.format or 'bin' -- or 'hex'
      local width = args.width or 8
      local length = args.length

      if format == 'bin' then
         -- simple copy
         os.execute('cp -v' .. self.tempfilebin .. ' ' .. filename .. '.bin')
      elseif format == 'hex' then
         local filehex = filename..'.hex'..tostring(width)
         neuflow.tools.readBinWriteHex(self.tempfilebin, filehex, width, length)
      elseif format == 'rom' then
         local filev = filename..'.v'
         neuflow.tools.readBinWriteRom(self.tempfilebin, filev, width, 'flow_rom')
      else
         error('format should be one of: bin | hex')
      end
   end
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
-- transmit bytecode
--
function NeuFlow:loadBytecode(bytecode)
   if bytecode then
      -- then transmit bytecode
      print('<neuflow.NeuFlow> transmitting bytecode')
      self.profiler:start('load-bytecode')
      etherflow.loadbytecode(bytecode)
      self.profiler:lap('load-bytecode')
      -- we are already transmitting the bytecode
      -- we can close the log file now
      -- the way it was done before in cleanup
      -- it was never closed, that is why we didn't see
      -- all of the data in log file
      self.logfile:close()
   else
      -- if no bytecode given, first dump it to file, then load it from there
      self:writeBytecode{}
      self:loadBytecodeFromFile(self.tempfilebin)
   end
end

----------------------------------------------------------------------
-- transmit bytecode (from file)
--
function NeuFlow:loadBytecodeFromFile(file)
   local file = assert(io.open(file, "r"))
   local bytes = file:read("*all")
   local tensor = torch.ByteTensor(self.bytecodesize)
   local i = 1
   for b in string.gfind(bytes, ".") do
      tensor[i] = string.byte(b)
      i = i+1
   end
   file:close()

   self:loadBytecode(tensor)
end

----------------------------------------------------------------------
-- transmit tensor
--
function NeuFlow:copyToDev(tensor)
   self.profiler:start('copy-to-dev')
   local dims = tensor:nDimension()
   if dims == 3 then
      for i = 1,tensor:size(1) do
         etherflow.sendtensor(tensor[i])
      end
   else
      etherflow.sendtensor(tensor)
   end
   self:getFrame('copy-done')
   self.profiler:lap('copy-to-dev')
end

----------------------------------------------------------------------
-- receive tensor
--
function NeuFlow:copyFromDev(tensor)
   profiler_neuflow = self.profiler:start('on-board-processing')
   self.profiler:setColor('on-board-processing', 'blue')
   self:getFrame('copy-starting')
   self.profiler:lap('on-board-processing')
   self.profiler:start('copy-from-dev')
   local dims = tensor:nDimension()
   if dims == 3 then
      for i = 1,tensor:size(1) do
         etherflow.receivetensor(tensor[i])
      end
   else
      etherflow.receivetensor(tensor)
   end
   self.profiler:lap('copy-from-dev')
end

----------------------------------------------------------------------
-- helper functions:
--   getFrame() receives a frame
--   parse_descriptor() parses the frame received
--
function NeuFlow:getFrame(tag, type)
   local data
   if not self.first_time then
      data = etherflow.receivestring()
   else
      self.first_time = false
      return true
   end
   if (data:sub(1,2) == type) then
      tag_received = parse_descriptor(data)
   end
   return (tag_received == tag)
end

function parse_descriptor(s)
   local reg_word = "%s*([-%w.+]+)%s*"
   local reg_pipe = "|"
   ni,j,type,tag,size,nb_frames = string.find(s, reg_word .. reg_pipe .. reg_word .. reg_pipe ..
                                              reg_word .. reg_pipe .. reg_word)
   return tag, type
end
