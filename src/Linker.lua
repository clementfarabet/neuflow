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

   local init_offset = (args.init_offset or 0) + 1

   -- only if we start NOT from page zero
   if (init_offset ~= 1) then

      -- init padding
      for aa = 0, ((init_offset/8)-1) do
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

      -- if destination node is a sentinel, try linking to a node in the next
      -- direction, if cannot then in the prev direction. Throw an error if
      -- cannot find a non sentinel node.
      function checkNode(ref_node, reverse)

         if nil ~= ref_node.bytes then
            return ref_node
         else
            if ref_node.next and not reverse then
               return checkNode(ref_node.next)
            elseif ref_node.prev then
               return checkNode(ref_node.prev, true)
            else
               error('# ERROR <Linker:linkGotos> : could not link goto')
            end
         end
      end

      ref_node = checkNode(ref_node)

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

function Linker:appendSentinel(mode)
   assert('start' == mode or 'end' == mode or nil == mode)

   local new_sentinel = {mode = mode}
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

function Linker:alignSensitiveCode(walker)
   walker = walker or {
      current_node      = self.instruction_list.start_node,
      sentinel_start    = nil,
      sentinel_nesting  = 0,
      sentinel_size     = 0,
      bytecode_size     = 0,
   }

   if nil == walker.current_node.bytes then
      -- sentinel

      if 'start' == walker.current_node.mode then
         if 0 == walker.sentinel_nesting then
            walker.sentinel_start = walker.current_node
            walker.sentinel_size  = 0
         end
         walker.sentinel_nesting = walker.sentinel_nesting + 1
      end

      if 'end' == walker.current_node.mode then
         walker.sentinel_nesting = walker.sentinel_nesting - 1
         assert(0 <= walker.sentinel_nesting)
      end
   else
      -- instr
      walker.bytecode_size = walker.bytecode_size + 1

      if 0 < walker.sentinel_nesting then
         if (1 == (walker.bytecode_size % (oFlower.page_size_b/8))) then
            -- current node is first of new page

            if walker.sentinel_start ~= walker.current_node.prev then
               -- shift sensitive section into new page
               assert((oFlower.page_size_b/8) > walker.sentinel_size)

               local before_sensitive = walker.sentinel_start.next
               for i = 1, walker.sentinel_size do
                  self:insertInstruction(before_sensitive, {bytes = {0,0,0,0,0,0,0,0}})
                  before_sensitive = before_sensitive.next
                  walker.bytecode_size = walker.bytecode_size + 1
               end
            end
         end

         walker.sentinel_size = walker.sentinel_size + 1
      end
   end

   if walker.current_node.next then
      walker.current_node = walker.current_node.next
      return self:alignSensitiveCode(walker)
   end
end

function Linker:dump(info, mem)

   self:linkGotos()
   self:alignSensitiveCode()
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

   -- and embedded data
   self:dump_embedded_data(info, info.tensor, mem)

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

function Linker:dump_embedded_data(info, tensor, mem)
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
