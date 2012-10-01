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
   self.disassemble = args.disassemble

   -- the bytecode array
   local sentinel_node = {}
   self.instruction_list = {
      start_node     = sentinel_node,
      end_node       = sentinel_node,
      start_sentinel = sentinel_node,
      end_sentinel   = sentinel_node
   }

   self.init_offset = (args.init_offset or 0) + 1

   -- only if we start NOT from page zero
   if (self.init_offset ~= 1) then

      -- init padding
      for aa = 0, ((self.init_offset/8)-1) do
         self:appendInstruction{bytes = {0,0,0,0,0,0,0,0}}
      end

      -- Sentinel to seperate init padding from next process
      self:appendSentinel()
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

   return ii
end

function Linker:resolveMemSegments()
   local node = self.instruction_list.start_node

   while node do
      if node.mem_offset ~= nil then
         self:rewriteARG32(node.bytes, node.mem_offset:calc())
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
   local instr_nb = self:resolveGotos()

   mem:adjustBytecodeSize(instr_nb*8)

   self:resolveMemSegments()
   local instr = self:genBytecode()

   -- optional disassemble
   if self.disassemble then
      neuflow.tools.disassemble(instr, {length = #instr})
   end

   -- parse argument
   assert(info.tensor)
   info.bigendian = info.bigendian or 0

   -- print all the instructions
   self:dump_instructions(instr, info.tensor)

   -- and embedded
   self:dump_RawData(info, info.tensor, mem)

   -- and data (images) for simulation)
   self:dump_ImageData(info, info.tensor, mem)

   -- print memory area statistics
   mem:printAreaStatistics()

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
   self.counter_bytes = mem.embedded.start.y * streamer.stride_b
                      + mem.embedded.start.x * streamer.word_b

   for i=1, #mem.embedded do
      mem_entry = mem.embedded[i]

      -- set offset in file
      if ('number' == type(mem_entry.y)) then
         self.counter_bytes = mem_entry.y * streamer.stride_b + mem_entry.x * streamer.word_b
      else
         self.counter_bytes = mem_entry.y:calc() * streamer.stride_b + mem_entry.x:calc() * streamer.word_b
      end

      if (mem_entry.bias ~= nil) then
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
         end
      end

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
         end
      end
   end
end

function Linker:dump_ImageData(info, tensor, mem)
   if (mem.persistent[1] == nil) then
      return
   end
   -- pad initial offset for raw data
   self.counter_bytes =  mem.persistent.start.y*streamer.stride_b + mem.persistent.start.x*streamer.word_b
   mem_entry = mem.persistent[1]

   for r=1,mem_entry.h do
      for i=1, #mem.persistent do
         mem_entry = mem.persistent[i]

         if ('number' == type(mem_entry.y)) then
            self.counter_bytes = (mem_entry.y + r - 1)*streamer.stride_b + mem_entry.x*streamer.word_b
         else
            self.counter_bytes = (mem_entry.y:calc() + r - 1)*streamer.stride_b + mem_entry.x:calc()*streamer.word_b
         end

         for c=1, mem_entry.w do
            dataTwos = math.floor(mem_entry.data[c][r] * num.one + 0.5)
            dataTwos = bit.band(dataTwos, num.mask)
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
      end -- entry
   end -- row
end
