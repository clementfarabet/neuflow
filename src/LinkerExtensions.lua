----------------------------------------------------------------------
--- Class: Linker
--
-- This file contains extensions to the Linker class.
--

function neuflow.Linker:cacheConfigOptimization()
   -- Filter for the instruction linked list, would be used after 'linkGotos()' and before
   -- 'alignProcessWithPages()'

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
