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
      start_node     = sentinel_node,
      end_node       = sentinel_node,
      start_sentinel = sentinel_node,
      end_sentinel   = sentinel_node
   }

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
   local instruction_output = {}
   local ii = 0

   while node do
      if node.bytes ~= nil then
         instruction_output[ii+1] = node.bytes[1]
         instruction_output[ii+2] = node.bytes[2]
         instruction_output[ii+3] = node.bytes[3]
         instruction_output[ii+4] = node.bytes[4]
         instruction_output[ii+5] = node.bytes[5]
         instruction_output[ii+6] = node.bytes[6]
         instruction_output[ii+7] = node.bytes[7]
         instruction_output[ii+8] = node.bytes[8]

         ii = ii + 8
      end

      node = node.next
   end

   return instruction_output
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
   self:alignProcessWithPages()
   self:resolveGotos()
   local instr = self:genBytecode()

   -- optional disassemble
   if self.disassemble then
      neuflow.tools.disassemble(instr, {length = #instr})
   end

   -- parse argument
   assert(info.tensor)

   -- get defaults if nil
   info.filename        = info.filename   or 'temp'
   info.offsetData      = info.offsetData or #instr + 1
   info.bigendian       = info.bigendian  or 0

   -- print all the instructions
   self:dump_instructions(instr, info.tensor)

   -- and raw_data
   self:dump_RawData(info, info.tensor, mem)

   -- and data (images) for simulation)
   self:dump_ImageData(info, info.tensor, mem)

   -- check collisions:
   self:checkCollisions(info.filename, #instr, mem)

   return self.counter_bytes
end

function Linker:dump_instructions(instr, tensor)
   -- copy instructions into tensor
   for i=1, #instr do
      tensor[self.counter_bytes+1] = instr[i]
      self.counter_bytes = self.counter_bytes + 1
   end
end

function Linker:dump_RawData(info, tensor, mem)
   -- pad initial offset for raw data
   self.logfile:write("Kernels:\n")
   self.counter_bytes = mem.start_raw_data_y * streamer.stride_b
                      + mem.start_raw_data_x * streamer.word_b

   for i=1,(mem.raw_datap-1) do
      mem_entry = mem.raw_data[i]
      self.logfile:write(
         string.format("#%d, offset_x = %d, offset_y = %d\n", i, mem_entry.x,mem_entry.y)
      )

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

   self.logfile:write(
      string.format("Writing images from offset: %d\n",
         mem.start_data_y*streamer.stride_w + mem.start_data_x)
   )

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

function Linker:checkCollisions(filename, instr_length, mem)
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
         c.none ..'[' .. filename .. "]\n")
   print(
      string.format("    bytecode segment: start = %10d, size = %10d, end = %10d",
         offset_bytes_process,
         (instr_length-offset_bytes_process),
         offset_bytes_process+(instr_length-offset_bytes_process))
   )
   if (((instr_length+1)-offset_bytes_process) + offset_bytes_process > offset_bytes_rawData) then
      print(c.Red .. 'ERROR' .. c.red .. ' segments overlap' .. c.none)
   end
   print(
      string.format("kernels data segment: start = %10d, size = %10d, end = %10d",
         offset_bytes_rawData,
         size_raw_data,
         offset_bytes_rawData+size_raw_data)
   )
   if (offset_bytes_rawData+size_raw_data > offset_bytes_data) then
      print(c.Red .. 'ERROR' .. c.red .. ' segments overlap' .. c.none)
   end
   print(
      string.format("  image data segment: start = %10d, size = %10d, end = %10d",
         offset_bytes_data,
         size_data,
         offset_bytes_data+size_data)
   )
   if (offset_bytes_data+size_data > offset_bytes_buffer) then
      print(c.Red .. 'ERROR' .. c.red .. ' segments overlap' .. c.none)
   end
   print(
      string.format("        heap segment: start = %10d, size = %10d, end = %10d",
         offset_bytes_buffer,
         size_buff, memory.size_b)
   )

   print(
      string.format("                                  the binary file size should be = %10d",
         self.counter_bytes)
   )
   print("++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++")
end
