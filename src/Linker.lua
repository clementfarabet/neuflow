----------------------------------------------------------------------
--- Class: Linker
--
-- This class is used to manage and link the bytecode.
-- The bytecode contains processes and data:
-- (1) a process is an action recognized by the virtual machine
--     running on the dataflow computer
-- (2) data is used by processes
--
local Linker = torch.class('neuflow.Linker')

function Linker:__init(args)
   -- args
   self.logfile = args.logfile
   self.disassemble = args.disassemble

   -- the bytecode array
   local sentinel_node = {}
   self.instruction_list = {
      start_node    = sentinel_node,
      end_node       = sentinel_node,
      start_sentinel = sentinel_node,
      end_sentinel   = sentinel_node
   }

   self.instruction_output = {}
   self.process = {}
   self.processp = 1
   self.datap = 1 -- unused

   -- initial offsets
   self.start_process_x = 0 -- initial offset here!!!
   self.start_process_y = 0 -- initial offset here!!!

   self.start_text = (args.start_text or linker.offset_text) + 1

   -- only if we start NOT from page zero
   if(self.start_text ~= 1) then
      -- init with default code

      local ii = 0
      while ii < (#bootloader.content-1) do
         local instruction = {
            bytes = {
               bootloader.content[ii+1],
               bootloader.content[ii+2],
               bootloader.content[ii+3],
               bootloader.content[ii+4],
               bootloader.content[ii+5],
               bootloader.content[ii+6],
               bootloader.content[ii+7],
               bootloader.content[ii+8]
            }
         }

         self:appendInstruction(instruction)
         ii = ii + 8
      end

      for aa = (ii/8), ((self.start_text/8)-1) do
         self:appendInstruction{bytes = {0,0,0,0,0,0,0,0}}
      end

      -- Sentinel to seperate bootloader content from next process
      self:appendSentinel()

      -- calculate start_x and start_y for collision check
      self.start_process_x = 0
      self.start_process_y = self.start_text / streamer.stride_b
   end

   self.counter_bytes = 0
end

function Linker:getLastReference()
   return self.instruction_list.end_node
end

function Linker:getReference()
   error('# ERROR <Linker:getReference> : Deprecated')
end

function Linker:linkGotos()

   local goto_table = {}
   local node = self.instruction_list.start_node
   while node do
      if node.goto_tag then
         goto_table[node] = node.goto_tag
      end

      node = node.next
   end

   for node in pairs(goto_table) do
      local ref_node = goto_table[node].ref
      local offset = goto_table[node].offset

      if offset <= 0 then
         local ii = 0
         while ii > offset do

            ref_node = ref_node.prev
            ii = ii - 1
         end
      else
         local ii = 0
         while ii < offset do

            ref_node = ref_node.next
            ii = ii + 1
         end
      end

      -- if destination node is a sentinel, try linking to node
      -- on ether side and throw an error if cannot
      if ref_node.bytes == nil then

         if ref_node.next then
            ref_node = ref_node.next
         elseif ref_node.prev then
            ref_node = ref_node.prev
         end

         if ref_node.bytes == nil then
            error('# ERROR <Linker:linkGotos> : could not link goto')
         end
      end

      -- remove just processed goto tab from table
      goto_table[node] = nil

      -- ref_node is destination instr
      node.goto_instr = ref_node
   end
end

function Linker:resolveGotos()
   local addr_index = {}
   local ii = 0

   local node = self.instruction_list.start_node
   while node do
      if node.bytes ~= nil then
         addr_index[node] = ii
         ii = ii + 1
      end

      node = node.next
   end

   local node = self.instruction_list.start_node
   while node do
      if node.goto_instr ~= nil then
         self:rewriteARG32(node.bytes, addr_index[node.goto_instr])
      end

      node = node.next
   end
end

function Linker:genBytecode()
   local node = self.instruction_list.start_node
   local ii = 0

   while node do
      if node.bytes ~= nil then
         self.instruction_output[ii+1] = node.bytes[1]
         self.instruction_output[ii+2] = node.bytes[2]
         self.instruction_output[ii+3] = node.bytes[3]
         self.instruction_output[ii+4] = node.bytes[4]
         self.instruction_output[ii+5] = node.bytes[5]
         self.instruction_output[ii+6] = node.bytes[6]
         self.instruction_output[ii+7] = node.bytes[7]
         self.instruction_output[ii+8] = node.bytes[8]

         ii = ii + 8
      end

      node = node.next
   end
end

function Linker:addProcess()
   self:appendSentinel()
end

function Linker:appendSentinel()
   local new_sentinel = {}
   local last_sentinel = self.instruction_list.end_sentinel
   local last_node = self.instruction_list.end_node

   last_sentinel.next_sentinel = new_sentinel
   new_sentinel.prev_sentinel = last_sentinel
   self.instruction_list.end_sentinel = new_sentinel

   last_node.next = new_sentinel
   new_sentinel.prev = last_node
   self.instruction_list.end_node = new_sentinel
end

function Linker:appendInstruction(instruction)

   if not instruction.bytes then
      instruction.bytes = self:newInstructionBytes(instruction)
   end

   local node = self.instruction_list.end_node

   node.next = instruction
   instruction.prev = node
   self.instruction_list.end_node = instruction
end

function Linker:newInstructionBytes(args)
   if args.binary then
      return args.binary
   end

   -- parse args
   local opcode = args.opcode or oFlower.op_nop
   local arg8_1 = args.arg8_1 or 0
   local arg8_2 = args.arg8_2 or 0
   local arg8_3 = args.arg8_3 or 0
   local arg32_1 = args.arg32_1 or 0
   local bytes = {}

   -- serialize opcode + args
   bytes[1] = math.floor(arg32_1/256^0) % 256
   bytes[2] = math.floor(arg32_1/256^1) % 256
   bytes[3] = math.floor(arg32_1/256^2) % 256
   bytes[4] = math.floor(arg32_1/256^3) % 256
   bytes[5] = arg8_3
   bytes[6] = arg8_2
   bytes[7] = arg8_1
   bytes[8] = opcode

   return bytes
end

function Linker:rewriteARG32(instr_bytes, uint32)
   instr_bytes[1] = math.floor(uint32/256^0) % 256
   instr_bytes[2] = math.floor(uint32/256^1) % 256
   instr_bytes[3] = math.floor(uint32/256^2) % 256
   instr_bytes[4] = math.floor(uint32/256^3) % 256
end

function Linker:insertInstruction(node, instruction)

   instruction.next = node.next
   instruction.prev = node

   instruction.next.prev = instruction
   instruction.prev.next = instruction
end

function Linker:insertSegment(earlier_node, seg_start, seg_end)
   local later_node = earlier_node.next

   earlier_node.next = seg_start
   seg_start.prev = earlier_node

   later_node.prev = seg_end
   seg_end.next = later_node
end

function Linker:removeSegment(seg_start, seg_end)
   local earlier_node = seg_start.prev
   local later_node = seg_end.next

   earlier_node.next = later_node
   later_node.prev = earlier_node
end

function Linker:alignProcessWithPages()
   local function countNextProcess(node, cnt)
      cnt = cnt or 0

      if node == nil or node.bytes == nil then
         return cnt
      else
         cnt = cnt+1
         return countNextProcess(node.next, cnt)
      end
   end

   local node = self.instruction_list.start_sentinel.next_sentinel
   local cur_page = countNextProcess(self.instruction_list.start_sentinel.next)

   while node.next do
      local next_process = countNextProcess(node.next)
      local new_page = cur_page + next_process

      if new_page > (oFlower.page_size_b/8) then
         local old_page = node.prev
         local diff = 0
         if (cur_page%(oFlower.page_size_b/8) ~= 0) then
            diff = (oFlower.page_size_b/8) - (cur_page%(oFlower.page_size_b/8))
         end

         if (diff > 0) then
            local instr_bytes = self:newInstructionBytes{opcode = oFlower.op_goto}
            local new_instr = {bytes = instr_bytes, goto_instr = node.next}

            self:insertInstruction(old_page, new_instr)
            old_page = old_page.next
         end

         for i = 1, (diff-1) do
            self:insertInstruction(old_page, {bytes = {0,0,0,0,0,0,0,0}})
            old_page = old_page.next
         end

         cur_page = next_process
      else
         cur_page = new_page
      end

      node = node.next_sentinel
   end
end

function Linker:dump(info, mem)

   self:linkGotos()
   --self:cacheConfigOptimization()
   self:alignProcessWithPages()
   self:resolveGotos()
   self:genBytecode()

   self.process = self.instruction_output
   self.processp = #self.instruction_output + 1

   -- parse argument
   assert(info.tensor)

   -- get defaults if nil
   info.filename        = info.filename      or 'temp'
   info.offsetData      = info.offsetData    or self.processp
   info.offsetProcess   = info.offsetProcess or 0
   info.bigendian       = info.bigendian     or 0
   info.dumpHeader      = info.dumpHeader    or false
   info.writeArray      = info.writeArray    or false

   if(info.writeArray) then  -- we are writing arrays for C
      for b in string.gfind('const uint8 bytecode_exampleInstructions[] = {', ".") do
         info.tensor[self.counter_bytes+1] = string.byte(b)
         self.counter_bytes = self.counter_bytes + 1
      end
   else -- writing bytecode to file or stdout
      -- print optional header
      if (info.dumpHeader) then
         local str = tostring(info.offsetProcess) .. '\n' ..
                     tostring(info.offsetData - info.offsetProcess + (self.datap - 1)*4) .. '\n' ..
                     tostring((self.datap-1)*4) .. '\n'

         for b in string.gfind(str, ".") do
            info.tensor[self.counter_bytes+1] = string.byte(b)
            self.counter_bytes = self.counter_bytes + 1
         end
      end
   end

   -- print all the instructions
   self:dump_instructions(info, info.tensor)

   if(info.writeArray == false)then
      -- and raw_data
      self:dump_RawData(info, info.tensor, mem)

      -- and data (images) for simulation)
      self:dump_ImageData(info, info.tensor, mem)
   end

   -- and close the file
   if(info.writeArray) then  -- we are writing arrays for C
      for b in string.gfind('0};\n\n', ".") do
         info.tensor[self.counter_bytes+1] = string.byte(b)
         self.counter_bytes = self.counter_bytes + 1
      end
   end

   -- check collisions:
   self:checkCollisions(info, mem)
end

function Linker:checkCollisions(info, mem)
   -- processes are 1 byte long, numbers are 2 (streamer.word_b) bytes long

   offset_bytes_process = self.start_process_y * streamer.stride_b
                        + self.start_process_x
   --+ self.start_process_x * streamer.word_b

   offset_bytes_rawData = mem.start_raw_data_y * streamer.stride_b
                          + mem.start_raw_data_x * streamer.word_b

   offset_bytes_data = mem.start_data_y * streamer.stride_b
                       + mem.start_data_x * streamer.word_b

   offset_bytes_buffer = mem.start_buff_y * streamer.stride_b
                         + mem.start_buff_x * streamer.word_b

   size_raw_data = (mem.raw_data_offset_y - mem.start_raw_data_y) * streamer.stride_b
                 + (mem.raw_data_offset_x - mem.start_raw_data_x - mem.last_align) * streamer.word_b

   size_data = (mem.data_offset_y - mem.start_data_y) * streamer.stride_b

   if (mem.data_offset_x ~= 0) then -- if we did not just step a new line
      -- take into account all the lines we wrote (the last entry's hight is enough)
      -- if not all the lines are filled till the end we are counting more than we should here,
      -- but for checking collision it's OK
      size_data = size_data + mem.data[mem.datap - 1].h * streamer.stride_b
   end

   size_buff =  (mem.buff_offset_y - mem.start_buff_y) * streamer.stride_b

   if (mem.buff_offset_x ~= 0) then -- if we did not just step a new line
      -- take into account all the lines we wrote (the last entry's hight is enough)
      -- if not all the lines are filled till the end we are counting more than we should here,
      -- but for checking collision it's OK
      size_buff = size_buff + mem.buff[mem.buffp - 1].h * streamer.stride_b
   end

   local c = sys.COLORS
   print("++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++")
   print(c.Cyan .. '-openFlow-' .. c.Magenta .. ' ConvNet Name ' ..
         c.none ..'[' .. info.filename .. "]\n")
   print(string.format("    bytecode segment: start = %10d, size = %10d, end = %10d",
                       offset_bytes_process,
                       (self.processp-offset_bytes_process-1),
                       offset_bytes_process+(self.processp-offset_bytes_process)-1))
   if ((self.processp-offset_bytes_process) + offset_bytes_process > offset_bytes_rawData) then
      print(c.Red .. 'ERROR' .. c.red .. ' segments overlap' .. c.none)
   end
   print(string.format("kernels data segment: start = %10d, size = %10d, end = %10d",
                       offset_bytes_rawData,
                       size_raw_data,
                       offset_bytes_rawData+size_raw_data))
   if (offset_bytes_rawData+size_raw_data > offset_bytes_data) then
      print(c.Red .. 'ERROR' .. c.red .. ' segments overlap' .. c.none)
   end
   print(string.format("  image data segment: start = %10d, size = %10d, end = %10d",
                       offset_bytes_data,
                       size_data,
                       offset_bytes_data+size_data))
   if (offset_bytes_data+size_data > offset_bytes_buffer) then
      print(c.Red .. 'ERROR' .. c.red .. ' segments overlap' .. c.none)
   end
   print(string.format("        heap segment: start = %10d, size = %10d, end = %10d",
                       offset_bytes_buffer, size_buff, memory.size_b))

   print(string.format("                                  the binary file size should be = %10d",
                       self.counter_bytes))
   print("++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++")
end

function Linker:dump_instructions(info, tensor)
   -- optional disassemble
   if self.disassemble then
      neuflow.tools.disassemble(self.process, {length=self.processp-1})
   end

   -- dump
   for i=1,(self.processp-1) do
      if (info.writeArray) then
         tensor[self.counter_bytes+1] = string.byte(string.format('0x%02X, ', self.process[i]))
      else
         tensor[self.counter_bytes+1] = self.process[i]
         self.counter_bytes = self.counter_bytes + 1
      end
   end
end

function Linker:dump_RawData(info, tensor, mem)

   -- pad initial offset for raw data
   self.logfile:write("Kernels:\n")
   self.counter_bytes =  mem.start_raw_data_y * streamer.stride_b
                 + mem.start_raw_data_x * streamer.word_b

   for i=1,(mem.raw_datap-1) do
      mem_entry = mem.raw_data[i]
      self.logfile:write(string.format("#%d, offset_x = %d, offset_y = %d\n",
                                       i,mem_entry.x,mem_entry.y))
      -- set offset in file
      self.counter_bytes = mem_entry.y * streamer.stride_b + mem_entry.x * streamer.word_b

      if (mem_entry.bias ~= nil) then
         self.logfile:write("Bias:\n")
         for b = 1,mem_entry.bias:size(1) do
            dataTwos = math.floor(mem_entry.bias[b] * num.one + 0.5)
            dataTwos = bit.band(dataTwos, num.mask)
            for j=0,(num.size_b - 1) do
               -- get char from short
               if (info.bigendian == 1) then
                  tempchar = math.floor(dataTwos / (256^((num.size_b - 1)-j))) % 256
               else
                  tempchar = math.floor(dataTwos / (256^j)) % 256
               end
               tensor[self.counter_bytes+1] = tempchar
               self.counter_bytes = self.counter_bytes + 1
            end
            -- print the kernel to logFile:
            self.logfile:write(string.format("%d ", mem_entry.bias[b]))
         end
         self.logfile:write(string.format("\n"))
      end

      self.logfile:write("Kernel:\n")
      for r=1,mem_entry.data:size(1) do
         for c=1,mem_entry.data:size(2) do
            dataTwos = math.floor(mem_entry.data[r][c] * num.one + 0.5)
            dataTwos = bit.band(dataTwos, num.mask)
            for j=0,(num.size_b - 1) do
               -- get char from short
               if (info.bigendian == 1) then
                  tempchar = math.floor(dataTwos / (256^((num.size_b - 1)-j))) % 256
               else
                  tempchar = math.floor(dataTwos / (256^j)) % 256
               end
               tensor[self.counter_bytes+1] = tempchar
               self.counter_bytes = self.counter_bytes + 1
            end
            -- print the kernel to logFile:
            self.logfile:write(string.format("%d ", mem_entry.data[r][c]))
         end
         self.logfile:write(string.format("\n"))
      end
   end
end

function Linker:dump_ImageData(info, tensor, mem)
   if (mem.data[1] == nil) then
      return
   end
   -- pad initial offset for raw data
   self.counter_bytes =  mem.start_data_y*streamer.stride_b + mem.start_data_x*streamer.word_b
   mem_entry = mem.data[1]
   self.logfile:write(string.format("Writing images from offset: %d\n",
                                    mem.start_data_y*streamer.stride_w
                                       + mem.start_data_x))
   for r=1,mem_entry.h do
      for i=1,(mem.datap-1) do
         mem_entry = mem.data[i]
         self.counter_bytes = (mem_entry.y + r - 1)*streamer.stride_b + mem_entry.x*streamer.word_b
         for c=1, mem_entry.w do
            dataTwos = math.floor(mem_entry.data[c][r] * num.one + 0.5)
            dataTwos = bit.band(dataTwos, num.mask)
            self.logfile:write(string.format("%d ",dataTwos))--mem_entry.data[r][c]))
            for j=0,(num.size_b - 1) do
               -- get char from short
               if (info.bigendian == 1) then
                  tempchar = math.floor(dataTwos / (256^((num.size_b - 1)-j))) % 256
               else
                  tempchar = math.floor(dataTwos / (256^j)) % 256
               end
               tensor[self.counter_bytes+1] = tempchar
               self.counter_bytes = self.counter_bytes+1
            end
         end -- column
         self.logfile:write(string.format("\t"))
      end -- entry
      self.logfile:write(string.format("\n"))
   end -- row
end

function Linker:cacheConfigOptimization()

   -- Beginning from the start of list, move along list until dead time is found.
   -- From that point, descend list looking for configs that can be moved.
   -- If config that can be moved is found, remove segment and then insert the segment in dead time.
   -- Repeat until the end of list is reached


   local function bytesDecode(bytes)
      -- instr bit packing is hard code, any change in the blast_bus.vh will make errors here

      local instr = {}
      instr.config8_1 = bytes[1]
      instr.config8_2 = bytes[2]
      instr.config8_3 = bytes[3]
      instr.config8_4 = bytes[4]
      instr.config16_1 = (256^1)*bytes[4]+(256^0)*bytes[3]
      instr.config32_1 = (256^3)*bytes[4]+(256^2)*bytes[3]+(256^1)*bytes[2]+(256*0)*bytes[1]

      instr.arg8_3 = bytes[5]
      instr.arg8_2 = bytes[6]
      instr.arg8_1 = bytes[7] -- config_content
      instr.of_opcode = bytes[8] -- openflower opcode

      return instr
   end

   -- makes a table that holds the current state of all the ports, argument 'state' is an old port
   -- state table to be cloned
   local function makePorts(state)
      if not state then state = {} end
      local ports = {}
      ports.addr = state.addr or nil -- if nil no port is being addressed
      ports.submod = state.addr or nil -- if nil no port sub module is being addressed

      for aa = 1, (streamer.nb_ports-1) do
         if not state[aa] then state[aa] = {} end
         ports[aa] = {}
         ports[aa].valid = state[aa].valid or 1 -- if 0, no longer in considerion for reordering
         ports[aa].idle = state[aa].idle or 1 -- if 1, is idle & does not need to be cached set
         ports[aa].active = state[aa].active or 0
         ports[aa].cached = state[aa].cached or 0
         ports[aa].reset = state[aa].reset or 0
         ports[aa].prefetch = state[aa].prefetch or 0
      end

      function ports:reset_valid()
         for aa = 1, (streamer.nb_ports-1) do
            ports[aa].valid = 1
         end
      end

      return ports
   end

   -- determines how the current instruction affects which end point the config bus
   -- is interacting with
   local function addressState(of_opcode, config_content, config_addr, config_submod, ports)

      if of_opcode == oFlower.op_writeConfig then
         if config_content == blast_bus.content_command then
            -- last 4 bits of config_addr is the area address
            local area = (config_addr - (config_addr%(2^12)))/(2^12)

            -- group addr and broadcast addr means more then one port can be active, these will
            -- be ignored as this version of config optimizer only can deal with a single port
            -- being addressed
            if area == blast_bus.area_streamer then
               -- first 12 bits of config_addr is the port address
               ports.addr = config_addr%(2^12)
               ports.submod = config_submod

               if ((ports.addr < 1) or (ports.addr > (streamer.nb_ports-1))) then
                  -- addr zero is broadcast to all ports while any address above the
                  -- number of ports is a group addr, both are ignored
                  ports.addr = nil
                  ports.submod = nil
               end
            else
               ports.addr = nil
               ports.submod = nil
            end
         end
      end
   end

   -- determines if the current instruction has a command that will affect the addressed port
   -- should be called after addressState in case the addring command also had an config_instr
   local function portCommand(of_opcode, config_content, config_instr, ports)
      for aa = 1, (streamer.nb_ports-1) do
         ports[aa].reset = 0
         ports[aa].prefetch = 0
      end

      local command = false

      if of_opcode == oFlower.op_writeConfig then
         if ports.addr and (config_content == blast_bus.content_command or
                           config_content == blast_bus.content_instruc) then

            command = true

            if config_instr == blast_bus.instruc_config then
               -- place holder for addressing without an opcode
            elseif config_instr == blast_bus.instruc_setAdd then
               -- set group address, defualt is broadcast address
               -- addr could be set to a different area code which
               -- would mean the addressState would need to be changed
            elseif config_instr == blast_bus.instruc_reset then
               ports[ports.addr].valid = 0
               ports[ports.addr].reset = 1
            elseif config_instr == blast_bus.instruc_cacheStart then
               ports[ports.addr].valid = 0
               ports[ports.addr].cached = 1
            elseif config_instr == blast_bus.instruc_cacheFinish then
               ports[ports.addr].valid = 0
               ports[ports.addr].cached = 0
            elseif config_instr == blast_bus.instruc_activate then
               ports[ports.addr].valid = 0
               ports[ports.addr].idle = 0
               ports[ports.addr].active = 1
            elseif config_instr == blast_bus.instruc_deActivate then
               ports[ports.addr].active = 0
            elseif config_instr == blast_bus.instruc_control_1 then
               -- prefetch
               ports[ports.addr].valid = 0
               ports[ports.addr].idle = 0
               ports[ports.addr].prefetch = 1
            else
               print("WARNING: Unknown comand sent to streamer")
               command = false
            end
         end
      end
      return command
   end

   local function portConfig(of_opcode, config_content, ports)
      local config = false

      if of_opcode == oFlower.op_writeConfig then
         if ports.addr and config_content == blast_bus.content_config then
            -- sending config words to sub module, currently only can move sub mod 2
            -- global and timeout config is ignored

            config = true
         end
      end

      return config
   end

   local function portWaitStatus(of_opcode, config_content, ports)
      local wait = false

      -- TODO: have estimate of time spent in wait and if there is enough time for
      -- a config reorder set wait to true

      if ports.addr and (of_opcode == oFlower.op_getStatus) then
         if config_content == blast_bus.status_primed then
            wait = true
         elseif config_content == blast_bus.status_done then
            wait = true
         end
      end

      return wait
   end

   local function makeCacheSetInstr()
      local instr_bytes = self:newInstructionBytes {
         opcode = oFlower.op_writeConfig,
         arg8_1 = blast_bus.content_instruc,
         arg32_1 = blast_bus.instruc_cacheStart
      }

      return {bytes = instr_bytes}
   end

   local function makeCacheUnsetInstr()
      local instr_bytes = self:newInstructionBytes {
         opcode = oFlower.op_writeConfig,
         arg8_1 = blast_bus.content_instruc,
         arg32_1 = blast_bus.instruc_cacheFinish
      }

      return {bytes = instr_bytes}
   end

   local function makeAddrInstr(addr, submod)
      submod = submod or 0
      local configWord = blast_bus.area_streamer*(2^28) + addr*(2^16) + submod*(2^8)

      local instr_bytes = self:newInstructionBytes {
         opcode = oFlower.op_writeConfig,
         arg8_1 = blast_bus.content_command,
         arg32_1 = configWord
      }

      return {bytes = instr_bytes}
   end

   local function findConfigSegment(node, ports)
      -- start_node is an instruction that addressess a port and the 2nd sub mod
      -- end_node is the last config instruction
      local start_node = nil
      local end_node = nil
      local search = true

      while (search and node) do
         if node.bytes ~= nil then
            local instr = bytesDecode(node.bytes)

            addressState(instr.of_opcode, instr.arg8_1, instr.config16_1, instr.config8_2, ports)
            portCommand(instr.of_opcode, instr.arg8_1, instr.config8_1, ports)

            if (ports.submod == 2 and ports[ports.addr].valid == 1) then
               start_node = node

               node = node.next
               local nb_config = 0
               while (search and node) do

                  if node.bytes == nil then
                     search = false
                     break
                  end

                  local instr = bytesDecode(node.bytes)

                  if portCommand(instr.of_opcode, instr.arg8_1, instr.config8_1, ports) then
                     search = false
                     break
                  end

                  if portConfig(instr.of_opcode, instr.arg8_1, ports) then
                     nb_config = nb_config + 1
                  end

                  if nb_config == 5 then
                     search = false
                     end_node = node
                  end

                  node = node.next
               end
            end
         end
         if node then node = node.next end
      end

      return start_node, end_node
   end

   local function findWaitAddrNode(node, target_addr)
      -- NOTE: if there is any other instr b/w addr instr and wait instr, make a addr
      --       instr node and insert it before wait instr
      local ports = makePorts()

      while not ports.addr do
         node = node.prev

         local instr = bytesDecode(node.bytes)
         addressState(instr.of_opcode, instr.arg8_1, instr.config16_1, instr.config8_2, ports)

         if ports.addr == target_addr then
            break
         else
            local tmp_ports = makePorts(ports)
            tmp_ports.addr = target_addr

            local command = portCommand(instr.of_opcode, instr.arg8_1, instr.config8_1, tmp_ports)
            local config = portConfig(instr.of_opcode, instr.arg8_1, tmp_ports)

            if config or command then
               local addr_node = makeAddrInstr(target_addr)
               self:insertInstruction(node, addr_node)
               node = addr_node

               break
            end
         end
      end

      return node
   end

   local node = self.instruction_list.start_sentinel
   local ports = makePorts()

   while node do
      if node.bytes ~= nil then
         local instr = bytesDecode(node.bytes)

         addressState(instr.of_opcode, instr.arg8_1, instr.config16_1, instr.config8_2, ports)
         portCommand(instr.of_opcode, instr.arg8_1, instr.config8_1, ports)

         --while portWaitStatus(instr.of_opcode, instr.arg8_1, ports) do -- only with time estimate
         if portWaitStatus(instr.of_opcode, instr.arg8_1, ports) then
            ports:reset_valid()
            local descent_ports = makePorts(ports)
            local descent_node = node.next
            local start_node = nil
            local end_node = nil

            start_node, end_node = findConfigSegment(descent_node, descent_ports)

            if start_node and end_node then
               -- find the addr instr node used to addr port for the wait for status instr node
               local wait_addr_node = findWaitAddrNode(node, ports.addr)

               -- insert instruction to re-addr port after first making it
               local new_addr = makeAddrInstr(descent_ports.addr, 2)
               self:insertInstruction(end_node, new_addr)

               -- NOTE: idle/not idle might not be correct, probable sould not use until sure
               --       and just use the cache every time
               --if ports[descent_ports.addr].idle then
                  local cache_set = makeCacheSetInstr()
                  local cache_unset = makeCacheUnsetInstr()

                  -- insert cache set instr in segment if using caching
                  self:insertInstruction(start_node, cache_set)

                  -- insert instr to unset cache if using caching
                  -- (if port is not idle at dead time)
                  self:insertInstruction(new_addr, cache_unset)
               --end

               -- remove (cut) the config segment
               self:removeSegment(start_node, end_node)

               -- re-insert segment in its new place
               self:insertSegment(wait_addr_node.prev, start_node, end_node)
            end
         end
      end

      node = node.next
   end
end
