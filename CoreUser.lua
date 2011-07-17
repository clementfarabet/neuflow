
----------------------------------------------------------------------
--- Class: CoreUser
--
-- This class provides a set of methods to abstract the Dataflow Computer 
-- hardware.
--
-- This file only includes the high-level API calls of the Core module.
--
-- IMPORTANT NOTE: these methods are inserted into the Core class, and
--                 cannot be used independently
--
CoreUser = {}

function CoreUser:registerKernel(args)
   -- parse args
   local address = args.address + blast_bus.addr_conv_0 - 1
   -- register kernel into convolver
   self:send_selectModule(blast_bus.area_tile, address, blast_bus.subAddr_operator)
   self:send_control_0()
   if (self.nb_kernels_loaded[args.address] > 0) then
      -- kernels are already there, discard the previous kernels
      local nb_discards = self.nb_kernels_loaded[args.address]
      for i=1,nb_discards do
	 self:send_control_1()
	 self.nb_kernels_loaded[args.address] = self.nb_kernels_loaded[args.address] - 1
      end
   end
   self.nb_kernels_loaded[args.address] = self.nb_kernels_loaded[args.address] + 1
end

function CoreUser:convolve(input, kernel, output, opts)
   self:startProcess()
   if (self.msg_level ~= 'none') then
      self:message('exec.convolution.with.'..input.orig_h..'x'..input.orig_w..'.image')
   end

   -- args
   local mapping = (opts and opts.mapping) or nil
   local bias = (opts and opts.bias) or 'off'

   -- mapping ?
   if mapping then
      -- config tile #1 for convolution
      self:configTile{operation = 'CONV2D',
                      address = 1,
                      config = {bias = bias},
                      inputs = {[1] = {source = 1, data = input},
                                [2] = {source = 2, data = kernel}},
                      outputs = {[1] = {dest = 'east', data = output}},
                      control = 3, -- next op signal
                      activate = true}

      -- config tile #1 for mapper
      self:configTile{operation = 'MAPPING',
                      address = 1,
                      config = {mode = {even=coefs.even, odd=coefs.odd}, 
                                segments = coefs},
                      inputs = {[1] = {source = 'north'}},
                      outputs = {[1] = {dest = 3}},
                      activate = true}
   else
      -- config tile #1 for convolution
      self:configTile{operation = 'CONV2D',
                      address = 1,
                      config = {bias = bias},
                      inputs = {[1] = {source = 1, data = input},
                                [2] = {source = 2, data = kernel}},
                      outputs = {[1] = {dest = 3, data = output}},
                      control = 3, -- next op signal
                      activate = true}
   end

   -- prefetch data input, while loading kernel
   self:configPort{index = 1, action = 'prefetch', data = input}
   self:configPort{index = 2, action = 'fetch+read+sync+close', data = kernel}
   self:registerKernel{address = 1}

   -- initialize data transfers
   self:configPort{index = 3, action = 'write', data = output}
   self:configPort{index = 1, action = 'read'}

   -- synchronize write port, and close all
   self:configPort{index = 3, action = 'sync+close'}
   self:configPort{index = 1, action = 'close'}
   
   -- deactivate tile
   self:configTile{operation = 'CONV2D', address = 1, activate = false}
   if mapping then
      self:configTile{operation = 'MAPPING', address = 1, activate = false}
   end
   self:endProcess()
end

function CoreUser:convolveWithBias(input, kernel, output)
   self:convolve(input, kernel, output, {bias='on'})
end

function CoreUser:convolveWithBiasAndMap(input, kernel, output, coefs)
   self:convolve(input, kernel, output, {bias='on', mapping=coefs})
end

function CoreUser:convolBank(inputs, kernels, outputs, coefs)
   -- message
   if (self.msg_level ~= 'none') then
      self:startProcess()
      self:message('exec.convolution.bank.and.mapping.on.'..
                   #inputs..'x'..inputs[1].orig_h..'x'..inputs[1].orig_w..'.inputs.and.'..
                   #outputs..'x'..outputs[1].orig_h..'x'..outputs[1].orig_w..'.outputs')
      self:endProcess()
   end

   -- nb of convs
   local nconvs = grid.nb_convs

   -- if more than 1 input, then we do data reuse on the outputs
   if #inputs > 1 and (#inputs*#outputs) == #kernels then
      -- compute all convolutions, by groups of [nconvs]
      local nb_cycles = math.ceil(#inputs / nconvs)
      local last_cycle = nb_cycles*nconvs - #inputs
      local cur_k = 0
      for o in ipairs(outputs) do
         local bias
         local cur_i = 0
         for cyc = 1,nb_cycles do
            -- message
            self:startProcess()
            if (self.msg_level == 'detailled') then
               self:message('conv.bank.cycle.'..cyc)
            end

            -- simulatenous convs for this cycle:
            local sim_convs = nconvs
            if cyc == nb_cycles and (last_cycle ~= 0) then
               -- partially filled grid
               sim_convs = #inputs - cur_i
            end

            -- config all conv tiles to receive kernels
            for i = 1,sim_convs do
               self:configTile{operation = 'CONV2D',
                               address = i,
                               --config = {bias = bias},
                               inputs = {[2] = {source = i, data = kernels[cur_k+i]}}}
            end

            -- load all kernels
            for i = 1,sim_convs do
               self:configPort{index = i, action = 'fetch+read', data = kernels[cur_k+i]}
            end

            -- sync kernels
            for i = 1,sim_convs do
               self:configPort{index = i, action = 'sync+close'}
               self:registerKernel{address = i}
            end

            -- prefetch all inputs
            for i = 1,sim_convs do
               self:configPort{index = 2+i, action = 'prefetch', data = inputs[cur_i+i]}
            end

            -- at cycle 2 and more, reread previous result
            if cyc > 1 then
               self:configPort{index = 2, action = 'prefetch', data = outputs[o]}
            end

            -- config all conv tiles to exec convolutions
            for i = 1,sim_convs do
               -- bias is active for very first conv only
               if i == 1 and cyc == 1 then bias = 'on' 
               else bias = 'off' end

               if cyc > 1 and i == 1 then
                  -- Conv i + acc output, result goes to ADD
                  self:configTile{operation = 'CONV2D',
                                  address = i,
                                  config = {bias = 'off'},
                                  inputs = {[1] = {source = 2+i, data = inputs[cur_i+i]},
                                            [2] = {data = kernels[cur_k+i]},
                                            [3] = {source = 2, data = outputs[o]}},
                                  outputs = {[1] = {dest = 'south', data = outputs[o]}},
                                  control = 3,
                                  activate = true}
               else
                  -- Conv i, result goes to ADD
                  self:configTile{operation = 'CONV2D',
                                  address = i,
                                  config = {bias = bias},
                                  inputs = {[1] = {source = 2+i, data = inputs[cur_i+i]},
                                            [2] = {data = kernels[cur_k+i]}},
                                  outputs = {[1] = {dest = 'south', data = outputs[o]}},
                                  control = 3,
                                  activate = true}
               end

               -- ADD takes result from conv, and adds it to other stream coming from mapper
               if i == 1 then
                  self:configTile{operation = 'ADD',
                                  bypass = true,
                                  address = i,
                                  inputs = {[1] = {source = 'north'}},
                                  outputs = {[1] = {dest = 'east'}}}
               else
                  self:configTile{operation = 'ADD',
                                  activate = true,
                                  address = i,
                                  inputs = {[1] = {source = 'west'},
                                            [2] = {source = 'north'}},
                                  outputs = {[1] = {dest = 'east'}}}
               end

               if i < sim_convs then
                  -- through mapper: connects ADD[i] to ADD[i+1]
                  self:configTile{operation = 'MAPPING',
                                  address = i,
                                  bypass = true,
                                  inputs = {[1] = {source = 'west'}},
                                  outputs = {[1] = {dest = 'east'}}}
               else
                  if cyc == nb_cycles and coefs then
                     -- mapper is used for the last segment
                     self:configTile{operation = 'MAPPING',
                                     address = i,
                                     config = {mode = {even=coefs.even, 
                                                       odd=coefs.odd}, 
                                               segments = coefs},
                                     inputs = {[1] = {source = 'west'}},
                                     outputs = {[1] = {dest = 1}},
                                     activate = true}
                  else
                     -- through mapper: connects ADD[i] to output 1
                     self:configTile{operation = 'MAPPING',
                                     address = i,
                                     bypass = true,
                                     inputs = {[1] = {source = 'west'}},
                                     outputs = {[1] = {dest = 1}}}
                  end
               end
            end

            -- config outputs to write result
            self:configPort{index = 1, action = 'write', data = outputs[o]}

            -- at cycle 2 and more, reread previous result
            if cyc > 1 then
               self:configPort{index = 2, action = 'sync-prefetch'}
               self:configPort{index = 2, action = 'activate'}
            end

            -- read all inputs
            for i = 1,sim_convs do
               self:configPort{index = 2+i, action = 'sync-prefetch'}
            end

            for i = 1,sim_convs do
               -- the following logic might seem absurd, but it is just some
               -- hard-coded static scheduling:
               -- scheduling on the grid is mostly deterministic, and therefore streams
               -- have to be aligned in time, to meet at precise time/space locations.
               -- the delays don't have to be cycle accurate, as each operator is buffered
               -- with 64 word deep fifos.
               local delay = 0
               local clock_ratio = oFlower.clock_freq / grid.clock_freq
               local fifo_size = 64
               if cyc > 1 and i == 2 then 
                  delay = (fifo_size/2 + 16) * clock_ratio
               elseif i > 2 then
                  delay = 4 * clock_ratio
               end
               for j=1,delay do self:nop() end    -- we insert nops to synchronize each stream
               -- activate the reading
               self:configPort{index = 2+i, action = 'activate'}
            end

            -- synchronize write port, and close all
            self:configPort{index = 1, action = 'sync+close'}
            for i = 1,sim_convs do
               self:configPort{index = 2+i, action = 'close'}
            end
            if cyc > 1 then
               self:configPort{index = 2, action = 'close'}
            end

            -- next set of inputs/kernels
            cur_i = cur_i + sim_convs
            cur_k = cur_k + sim_convs

            -- deactivate all tiles
            for i = 1,sim_convs do
               self:configTile{operation = 'CONV2D', address = i, activate = false}
               self:configTile{operation = 'MAPPING', address = i, activate = false}
               self:configTile{operation = 'ADD', address = i, activate = false}
            end
            self:endProcess()
         end
      end

   -- only one input > data reuse is done one that 1 input
   elseif #inputs == 1 and (#inputs*#outputs) == #kernels then
      -- compute all convolutions, by groups of [nconvs]
      local nb_cycles = math.ceil(#outputs / nconvs)
      local last_cycle = nb_cycles*nconvs - #outputs
      local cur_k = 0
      local cur_o = 0
      for cyc = 1,nb_cycles do
         self:startProcess()
         -- message
         if (self.msg_level == 'detailled') then
            self:message('conv.bank.cycle.'..cyc)
         end

         -- simulatenous convs for this cycle:
         local sim_convs = nconvs
         if cyc == nb_cycles and (last_cycle ~= 0) then
            -- partially filled grid
            sim_convs = #outputs - cur_o
         end

         -- config all conv tiles to receive kernels
         for o = 1,sim_convs do
            self:configTile{operation = 'CONV2D',
                            address = o,
                            inputs = {[2] = {source = o, data = kernels[cur_k+o]}}}
            self:configPort{index = o, action = 'fetch+read+sync+close', data = kernels[cur_k+o]}
            self:registerKernel{address = o}
            self:configTile{operation = 'CONV2D', address = o, activate = false}
         end

         -- config all conv tiles to exec convolutions
         for o = 1,sim_convs do
            -- Conv o, result goes to mapper
            self:configTile{operation = 'CONV2D',
                            address = o,
                            config = {bias = 'on'},
                            inputs = {[1] = {source = 1, data = inputs[1]},
                                      [2] = {data = kernels[cur_k+o]}},
                            outputs = {[1] = {dest = 'east', data = outputs[cur_o+o]}},
                            control = 3,
                            activate = true}

            
            if coefs then
               -- mapper is used for the last segment
               self:configTile{operation = 'MAPPING',
                               address = o,
                               config = {mode = {even=coefs.even, 
                                                 odd=coefs.odd}, 
                                         segments = coefs},
                               inputs = {[1] = {source = 'north'}},
                               outputs = {[1] = {dest = 1+o}},
                               activate = true}
            else
               -- mapper is bypassed
               self:configTile{operation = 'MAPPING',
                               address = o,
                               bypass = true,
                               inputs = {[1] = {source = 'north'}},
                               outputs = {[1] = {dest = 1+o}}}
            end
         end

         -- config outputs to write results
         for o = 1,sim_convs do
            self:configPort{index = 1+o, action = 'write', data = outputs[cur_o+o]}
         end

         -- readout single input
         self:configPort{index = 1, action = 'fetch+read', data = inputs[1]}

         -- synchronize write ports
         for o = 1,sim_convs do
            self:configPort{index = 1+o, action = 'sync+close'}
         end

         -- and just close input port
         self:configPort{index = 1, action = 'close'}

         -- next set of outputs/kernels
         cur_o = cur_o + sim_convs
         cur_k = cur_k + sim_convs

         -- deactivate all tiles
         for o = 1,sim_convs do
            self:configTile{operation = 'CONV2D', address = o, activate = false}
            self:configTile{operation = 'MAPPING', address = o, activate = false}
            self:configTile{operation = 'ADD', address = o, activate = false}
         end
         self:endProcess()
      end

   -- one kernel per input, this is a 1 to 1 layer
   elseif #inputs == #outputs and #inputs == #kernels then 
      -- compute all convolutions, by groups of [nconvs]
      local nconvs = math.min(math.floor(grid.nb_ios/2),nconvs)
      local nb_cycles = math.ceil(#outputs / nconvs)
      local last_cycle = nb_cycles*nconvs - #outputs
      local cur_k = 0
      local cur_o = 0
      local cur_i = 0
      for cyc = 1,nb_cycles do
         self:startProcess()
         -- message
         if (self.msg_level == 'detailled') then
            self:message('conv.bank.cycle.'..cyc)
         end

         -- simulatenous convs for this cycle:
         local sim_convs = nconvs
         if cyc == nb_cycles and (last_cycle ~= 0) then
            -- partially filled grid
            sim_convs = #outputs - cur_o
         end

         -- config all conv tiles to receive kernels
         for o = 1,sim_convs do
            self:configTile{operation = 'CONV2D',
                            address = o,
                            inputs = {[2] = {source = o, data = kernels[cur_k+o]}}}
            self:configPort{index = o, action = 'fetch+read+sync+close', data = kernels[cur_k+o]}
            self:registerKernel{address = o}
            self:configTile{operation = 'CONV2D', address = o, activate = false}
         end

         -- config all conv tiles to exec convolutions
         for o = 1,sim_convs do
            -- for the inputs
            local i = o

            -- Conv o, result goes to mapper
            self:configTile{operation = 'CONV2D',
                            address = o,
                            config = {bias = 'on'},
                            inputs = {[1] = {source = i, data = inputs[cur_i+i]},
                                      [2] = {data = kernels[cur_k+o]}},
                            outputs = {[1] = {dest = 'east', data = outputs[cur_o+o]}},
                            control = 3,
                            activate = true}

            
            if coefs then
               -- mapper is used for the last segment
               self:configTile{operation = 'MAPPING',
                               address = o,
                               config = {mode = {even=coefs.even, 
                                                 odd=coefs.odd}, 
                                         segments = coefs},
                               inputs = {[1] = {source = 'north'}},
                               outputs = {[1] = {dest = nconvs+o}},
                               activate = true}
            else
               -- mapper is bypassed
               self:configTile{operation = 'MAPPING',
                               address = o,
                               bypass = true,
                               inputs = {[1] = {source = 'north'}},
                               outputs = {[1] = {dest = nconvs+o}}}
            end
         end

         -- config outputs to write results, inputs to read
         for o = 1,sim_convs do
            local i = o
            self:configPort{index = nconvs+o, action = 'write', data = outputs[cur_o+o]}
            self:configPort{index = i, action = 'fetch+read', data = inputs[cur_i+i]}
         end

         -- synchronize write ports
         for o = 1,sim_convs do
            self:configPort{index = nconvs+o, action = 'sync+close'}
         end

         -- and close inptut ports
         for i = 1,sim_convs do
            self:configPort{index = i, action = 'close'}
         end

         -- next set of outputs/kernels
         cur_i = cur_i + sim_convs
         cur_o = cur_o + sim_convs
         cur_k = cur_k + sim_convs

         -- deactivate all tiles
         for o = 1,sim_convs do
            self:configTile{operation = 'CONV2D', address = o, activate = false}
            self:configTile{operation = 'MAPPING', address = o, activate = false}
            self:configTile{operation = 'ADD', address = o, activate = false}
         end
         self:endProcess()

      end

   -- unknown combination of kernels/inputs/outputs
   else
      error('<CoreUser:convolveBankAndMap> the number of kernels/inputs/outputs is inconsistent')
   end
end

function CoreUser:convolveAndAcc(input, kernel, inputacc, output, opts)
   self:startProcess()
   if (self.msg_level ~= 'none') then
      self:message('exec.convolution.and.mapping.with.'..input.orig_h..'x'..input.orig_w..
		   '.image.and.acc.with.'..inputacc.orig_h..'x'..inputacc.orig_w..'.image')
   end

   -- args
   local mapping = (opts and opts.mapping) or nil
   local bias = (opts and opts.bias) or 'off'

   -- mapping ?
   if mapping then
      -- config tile #1 for convolution
      self:configTile{operation = 'CONV2D',
                      address = 1,
                      config = {bias = bias},
                      inputs = {[1] = {source = 1, data = input},
                                [2] = {source = 2, data = kernel},
                                [3] = {source = 3, data = inputacc}},
                      outputs = {[1] = {dest = 'east', data = output}},
                      control = 3, -- next op signal
                      activate = true}

      -- config tile #1 for mapper
      self:configTile{operation = 'MAPPING',
                      address = 1,
                      config = {mode = {even=mapping.even, 
                                        odd=mapping.odd}, 
                                segments = mapping},
                      inputs = {[1] = {source = 'north'}},
                      outputs = {[1] = {dest = 4}},
                      activate = true}
   else
      -- config tile #1 for convolution
      self:configTile{operation = 'CONV2D',
                      address = 1,
                      config = {bias = bias},
                      inputs = {[1] = {source = 1, data = input},
                                [2] = {source = 2, data = kernel},
                                [3] = {source = 3, data = inputacc}},
                      outputs = {[1] = {dest = 4, data = output}},
                      control = 3, -- next op signal
                      activate = true}
   end

   -- prefetch data input, while loading kernel
   self:configPort{index = 1, action = 'prefetch', data = input}
   self:configPort{index = 3, action = 'prefetch', data = inputacc}
   self:configPort{index = 2, action = 'fetch+read+sync+close', data = kernel}
   self:registerKernel{address = 1}

   -- initialize data transfers
   self:configPort{index = 4, action = 'write', data = output}
   self:configPort{index = 3, action = 'read'}
   self:configPort{index = 1, action = 'read'}

   -- synchronize write port, and close all
   self:configPort{index = 4, action = 'sync+close'}
   self:configPort{index = 3, action = 'close'}
   self:configPort{index = 1, action = 'close'}

   -- deactivate tile
   self:configTile{operation = 'CONV2D', address = 1, activate = false}
   if mapping then
      self:configTile{operation = 'MAPPING', address = 1, activate = false}
   end
   self:endProcess()
end

function CoreUser:convolveAndAccAndMap(input, kernel, inputacc, output, coefs)
   self:convolveAndAcc(input, kernel, inputacc, output, {mapping=coefs})
end

function CoreUser:subsample(input, kernel, output, opts)
   self:startProcess()
   if (self.msg_level ~= 'none') then
      self:message('exec.subsample.with.'..input.orig_h..'x'..input.orig_w..'.image')
   end

   -- args
   local mapping = (opts and opts.mapping) or nil
   local bias = (opts and opts.bias) or 'off'

   -- mapping ?
   if mapping then
      -- config tile #1 for convolution
      self:configTile{operation = 'CONV2D',
                      address = 1,
                      config = {bias = 'on'},
                      inputs = {[1] = {source = 1, data = input},
                                [2] = {source = 2, data = kernel}},
                      outputs = {[1] = {dest = 'east', data = output}},
                      control = 3, -- next op signal
                      activate = true}

      -- config tile #1 for mapper
      self:configTile{operation = 'MAPPING',
                      address = 1,
                      config = {mode = {even=mapping.even, 
                                        odd=mapping.odd}, 
                                segments = mapping},
                      inputs = {[1] = {source = 'north'}},
                      outputs = {[1] = {dest = 3}},
                      activate = true}
   else
      -- config tile #1 for convolution
      self:configTile{operation = 'CONV2D',
                      address = 1,
                      config = {bias = bias},
                      inputs = {[1] = {source = 1, data = input},
                                [2] = {source = 2, data = kernel}},
                      outputs = {[1] = {dest = 3, data = output}},
                      control = 3, -- next op signal
                      activate = true}
   end

   -- prefetch data input, while loading kernel
   self:configPort{index = 1, action = 'prefetch', data = input}
   self:configPort{index = 2, action = 'fetch+read+sync+close', data = kernel}
   self:registerKernel{address = 1}

   -- initialize data transfers
   self:configPort{index = 3, action = 'write', data = output}
   self:configPort{index = 1, action = 'read'}

   -- synchronize write port, and close all
   self:configPort{index = 3, action = 'sync+close'}
   self:configPort{index = 1, action = 'close'}

   -- deactivate tile
   self:configTile{operation = 'CONV2D', address = 1, activate = false}
   if mapping then
      self:configTile{operation = 'MAPPING', address = 1, activate = false}
   end
   self:endProcess()
end

function CoreUser:subsampleWithBias(input, kernel, output)
   self:subsample(input, kernel, output, {bias='on'})
end

function CoreUser:subsampleWithBiasAndMap(input, kernel, output, coefs)
   self:subsample(input, kernel, output, {bias='on', mapping=coefs})
end

function CoreUser:mapping(input, output, coefs)
   self:startProcess()
   if (self.msg_level ~= 'none') then
      self:message('exec.mapping.with.'..input.orig_h..'x'..input.orig_w..'.image')
   end
   
   -- config tile #1 for mapper
   self:configTile{operation = 'MAPPING',
                   address = 1,
                   config = {mode = {even=coefs.even, odd=coefs.odd}, 
                             segments = coefs},
                   inputs = {[1] = {source = 1}},
                   outputs = {[1] = {dest = 3}},
                   activate = true}

   -- initialize data transfers
   self:configPort{index = 3, action = 'write', data = output}
   self:configPort{index = 1, action = 'fetch+read', data = input}

   -- synchronize write port, and close all
   self:configPort{index = 3, action = 'sync+close'}
   self:configPort{index = 1, action = 'close'}

   -- deactivate tile
   self:configTile{operation = 'MAPPING', address = 1, activate = false}
   self:endProcess()
end

function CoreUser:copy(input, output)
   self:startProcess()
   self:message('copy.'..input.orig_h..'x'..input.orig_w..'.image')

   -- global input 0 > global output 1
   self:send_selectModule(blast_bus.area_tile, blast_bus.addr_mapp_0, blast_bus.subAddr_IO)
   self:send_route__0_through_1()

   -- then stream images in and out
   self:openPortWr(5, output)
   self:openPortRd(4, input)

   -- wait for status done
   self:send_selectModule(blast_bus.area_streamer, blast_bus.addr_mem_streamer_0+5, 0)
   self:getStatus(blast_bus.status_done)

   -- and close them all
   self:closePort(4)
   self:closePort(5)
   
   -- unconnect IO router
   self:send_selectModule(blast_bus.area_tile, blast_bus.addr_mapp_0, blast_bus.subAddr_IO)
   self:send_route__all_dummys()
   self:endProcess()
end

function CoreUser:localNormalizeMean(input, kernel, output)
   if (self.msg_level ~= 'none') then
      self:message('exec.normalization.with.'..input.orig_h..'x'..input.orig_w..'.image')
   end

   if (input.orig_w ~= output.orig_w) or (input.orig_h ~= output.orig_h) then
      error('<CoreUser:localNormalizeMean> input and output should be the same size')
   end

   if not kernel.zero_mean then
      -- (0) normalize kernel, and compute 1-ker
      local meanRemover = kernel.data
      meanRemover:div(meanRemover:sum())
      meanRemover:mul(-1)
      meanRemover:narrow(1,kernel.data:size(1)-kernel.orig_w+math.ceil(kernel.orig_w/2),1):select(2,math.ceil(kernel.orig_h/2),1):add(1)

      -- (1) make sure kernel would have perfect 0 mean after quantization
      meanRemover:mul(num.one):add(0.5):floor():div(num.one)
      meanRemover:narrow(1,kernel.data:size(1)-kernel.orig_w+math.ceil(kernel.orig_w/2),1):select(2,math.ceil(kernel.orig_h/2),1):add(-meanRemover:sum())

      -- mark kernel as being zero mean
      kernel.zero_mean = true
   end

   -- (2) remove mean == convolution
   self:convolBank({input}, {kernel}, {output})
end

function CoreUser:localNormalizeStd(input, kernel, output, threshold)
   if (self.msg_level ~= 'none') then
      self:message('exec.normalization.with.'..input.orig_h..'x'..input.orig_w..'.image')
   end

   if (input.orig_w ~= output.orig_w) or (input.orig_h ~= output.orig_h) then
      error('<CoreUser:localNormalizeMean> input and output should be the same size')
   end

   if not kernel.one_mean then
      -- (0) make sure kernel given is zero-mean and have perfect 1 mean after quantization
      local average = kernel.data
      average:div(average:sum())
      average:mul(num.one):add(0.5):floor():div(num.one)
      average:narrow(1,kernel.data:size(1)-kernel.orig_w+math.ceil(kernel.orig_w/2),1):select(2,math.ceil(kernel.orig_h/2),1):add(1-average:sum())

      -- mark kernel as being one mean
      kernel.one_mean = true
   end

   -- (1) allocate temp buffers
   local buffer = self.mem:allocOnTheHeap(input.orig_h, input.orig_w, {}, true)

   -- (2) generate coefs for sqrt
   if not self.sqrtCoefs then
      local mapping
      if threshold then
	 mapping = function (x) 
		      if x < threshold then return math.sqrt(threshold)
		      else return math.sqrt(x) end
		   end
      else
	 mapping = math.sqrt
      end
      self.sqrtCoefs = math.approx{mapping=mapping, min=0, max=num.max,
				   nbSegments=grid.mapper_segs, Q=num.frac_,
				   epsilon = 19.7/256, error_type = 0,name='Sqrt_s_th'}
   end
   
   -- (3) sqrt(sum of squares) == square > convolution > mapping
   self:square(input, self.mem.buff[buffer])
   self:convolBank({self.mem.buff[buffer]}, {kernel}, {output}, self.sqrtCoefs)

   -- (4) divide
   self:divide(input, output, output)
end

function CoreUser:normKernel(kernel, sum)
   sum = sum or 1
   kernel:div(kernel:sum()):mul(sum)
   local m = 0
   local n = 0
   local switch = false
   local inc
   while true do
      kernel:mul(num.one):add(0.5):floor():div(num.one)
      if math.abs(kernel:sum()/sum-1) < num.res then break
      elseif kernel:sum()/sum > 1 then inc = -num.res
      else inc = num.res end
      kernel:narrow(1,1+m,1):narrow(2,1+n,1):add(inc)
      if switch then
         n = (n + 1) % kernel:size(2)
      else
         m = (m + 1) % kernel:size(1)
      end
      if m == 0 then
         switch = true
      elseif n == 0 and switch then
         switch = false
      end
   end
end

function CoreUser:localNormalizeMeanBank(inputs, kernels, outputs, xN_coefs)
   if (self.msg_level ~= 'none') then
      self:message('exec.mean.norm.with.'..#inputs..'x'..inputs[1].orig_h..'x'..inputs[1].orig_w..'.image')
   end

   if (inputs[1].orig_w ~= outputs[1].orig_w) or (inputs[1].orig_h ~= outputs[1].orig_h) then
      error('<CoreUser:localNormalizeMean> inputs and outputs should be the same size')
   end

   -- (0) make sure kernels given are one-mean and have perfect 1 mean after quantization
   for k,kernel in ipairs(kernels) do
      if (not kernel.mean) or (kernel.mean ~= 1) then
         local average = kernel.data:narrow(1,kernel.data:size(1)-kernel.orig_w+1,kernel.orig_w):narrow(2,1,kernel.orig_h)
         self:normKernel(average)
         kernel.mean = 1
      end
   end
   
   
   -- (2) compute mean across inputs
   local average_id = self.mem:allocOnTheHeap(inputs[1].orig_h, inputs[1].orig_w, {}, true)
   
   self:convolBank(inputs, kernels, {self.mem.buff[average_id]}, xN_coefs)

   -- (2) remove mean == convolution
   for i = 1,#inputs do
      self:subtract(inputs[i], self.mem.buff[average_id], outputs[i])
   end
end

function CoreUser:localNormalizeStdBank(inputs, kernels, outputs, sqrtCoefs)
   if (self.msg_level ~= 'none') then
      self:message('exec.std.norm.with.'..#inputs..'x'..inputs[1].orig_h..'x'..inputs[1].orig_w..'.image')
   end

   if (inputs[1].orig_w ~= outputs[1].orig_w) or (inputs[1].orig_h ~= outputs[1].orig_h) then
      error('<CoreUser:localNormalizeMean> inputs and outputs should be the same size')
   end

   -- (0) make sure kernels given are one-mean and have perfect 1 mean after quantization
   for k,kernel in ipairs(kernels) do
      if (not kernel.mean) or (kernel.mean ~= 1) then
         local average = kernel.data:narrow(1,kernel.data:size(1)-kernel.orig_w+1,kernel.orig_w):narrow(2,1,kernel.orig_h)
         self:normKernel(average)
         kernel.mean = 1
      end
   end

   -- (2) square all maps
   local squares = {}
   local newlayer = true
   for i = 1,#kernels do
      local square_id = self.mem:allocOnTheHeap(inputs[i].orig_h, inputs[i].orig_w, {}, newlayer)
      table.insert(squares, self.mem.buff[square_id])
      newlayer = false
      self:square(inputs[i], squares[i])
   end

   -- (3) sum of squares, across features, plus sqrt
   local sumsquare_id = self.mem:allocOnTheHeap(inputs[1].orig_h, inputs[1].orig_w, {}, false)
   local sumSquares = {self.mem.buff[sumsquare_id]}
   self:convolBank(squares, kernels, sumSquares, sqrtCoefs)

   -- (4) divide
   for i = 1,#inputs do
      self:divide(inputs[i], sumSquares[1], outputs[i])
   end
end

function CoreUser:stdOperator(input1, input2, input3, output, op)
   self:startProcess()
   if (self.msg_level ~= 'none') then
      self:message('exec.alu.op.'..op..'.with.'..input1.orig_h..'x'..input1.orig_w..'.images')
   end

   -- input 3 is optional
   local input1_desc = {source = 1, data = input1}
   local input2_desc
   local input3_desc
   if input2 then
      input2_desc = {source = 2, data = input2}
   end
   if input3 then
      input3_desc = {source = 3, data = input3}
   end

   -- general purpose tile
   self:configTile{operation = op,
                   activate = true,
                   address = 1,
                   inputs = {[1] = input1_desc,
                             [2] = input2_desc,
                             [3] = input3_desc},
                   outputs = {[1] = {dest = 4, data = output}}}

   -- initialize data transfers
   self:configPort{index = 1, action = 'prefetch', data = input1}
   if input2 then
      self:configPort{index = 2, action = 'prefetch', data = input2}
   end
   if input3 then
      self:configPort{index = 3, action = 'prefetch', data = input3}
   end
   self:configPort{index = 4, action = 'write', data = output}

   -- readout
   self:configPort{index = 1, action = 'read'}
   if input2 then
      self:configPort{index = 2, action = 'read'}
   end
   if input3 then
      self:configPort{index = 3, action = 'read'}
   end

   -- synchronize write port, and close all
   self:configPort{index = 4, action = 'sync+close'}
   if input3 then
      self:configPort{index = 3, action = 'close'}
   end
   if input2 then
      self:configPort{index = 2, action = 'close'}
   end
   self:configPort{index = 1, action = 'close'}
   
   -- deactivate tile
   self:configTile{operation = op, address = 1, activate = false}
   self:endProcess()
end

function CoreUser:subtract(input1, input2, output)
   self:stdOperator(input1, input2, nil, output, 'SUB')
end

function CoreUser:add(input1, input2, output)
   self:stdOperator(input1, input2, nil, output, 'ADD')
end

function CoreUser:divide(input1, input2, output)
   self:stdOperator(input1, input2, nil, output, 'DIV')
end

function CoreUser:square(input1, output)
   self:stdOperator(input1, nil, nil, output, 'SQUARE')
end

function CoreUser:multiply(input1, input2, output)
   self:stdOperator(input1, input2, nil, output, 'MUL')
end

function CoreUser:multiplyAndAcc(input1, input2, input3, output)
   self:stdOperator(input1, input2, input3, output, 'MAC')
end

function CoreUser:multiplyScalar(input, scalar, output)
   if (self.msg_level ~= 'none') then
      self:startProcess()
      self:message('exec.scalar.multiply.with.'..input1.orig_h..'x'..input1.orig_w..'.image')
      self:endProcess()
   end

   -- for now, we use the convolver grid to do that task
   local id = self.mem:allocRawData(1, 1, torch.Tensor(1,1):fill(scalar))
   self:convolBank({input}, {self.mem.raw_data[id]}, {output})
end
