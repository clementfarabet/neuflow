
----------------------------------------------------------------------
--- Class: Compiler
--
-- This class provides a set of methods to compile a neural network into
-- bytecode for the dataflow computer.
--
local Compiler = torch.class('neuflow.Compiler')

local message = {
   WARNING_IMPLEMENTED = '<neuflow.Compiler> WARNING: module not implemented > ',
   ERROR_IMPLEMENTED = '<neuflow.Compiler> ERROR: module not implemented > '
}

function Compiler:__init(args)
   -- args:
   self.opt_across_layers = args.optimize_across_layers or false
   self.logfile = args.logfile or nil
   self.core = args.core
   self.msg_level = args.msg_level or 'concise' -- can be 'none' or 'detailled'

   if (self.core == nil or self.logfile == nil) then
      error('<neuflow.Compiler> ERROR: please provide DataflowComputer + Log')
   end

   -- this param holds the number of ops required to compute the given net
   self.ops = 0
end

-- a table of all supported (compilable) modules
local layer = {
   -- Local operators
   ["nn.SpatialSubSampling"] =
      function(net_compiler, module, inputs, mapping)
         return net_compiler:SpatialSubSampling(module, inputs, mapping)
      end,

   ["nn.SpatialLPPooling"] =
      function(net_compiler, module, inputs, mapping)
         return net_compiler:SpatialLPPooling(module, inputs, mapping)
      end,

   ["nn.SpatialConvolution"] =
      function(net_compiler, module, inputs, mapping)
         return net_compiler:SpatialConvolution(module, inputs, mapping)
      end,

   ["nn.SpatialLinear"] =
      function(net_compiler, module, inputs, mapping)
         return net_compiler:SpatialLinear(module, inputs, mapping)
      end,

   ["nn.SpatialConvolutionMap"] =
      function(net_compiler, module, inputs, mapping)
         return net_compiler:SpatialConvolutionMap(module, inputs, mapping)
      end,

   ["nn.SpatialNormalization"] =
      function(net_compiler, module, inputs)
         return net_compiler:SpatialNormalization(module, inputs)
      end,

   ["nn.SpatialSubtractiveNormalization"] =
      function(net_compiler, module, inputs)
         return net_compiler:SpatialSubtractiveNormalization(module, inputs)
      end,

   -- Non Linear mappings
   ["nn.Abs"] =
      function(net_compiler, module, inputs)
         return net_compiler:Mapping(module,inputs,'Abs')
      end,

   ["nn.Sqrt"] =
      function(net_compiler, module, inputs)
         return net_compiler:Mapping(module,inputs,'Sqrt')
      end,

   ["nn.HardTanh"] =
      function(net_compiler, module, inputs)
         return net_compiler:Mapping(module,inputs,'HardTanh')
      end,

   ["nn.StdSigm"] =
      function(net_compiler, module, inputs)
         return net_compiler:Mapping(module,inputs,'StdSigm')
      end,

   ["nn.Tanh"] =
      function(net_compiler, module, inputs)
         return net_compiler:Mapping(module,inputs,'Tanh')
      end,

   ["nn.TanhAbs"] =
      function(net_compiler, module, inputs)
         return net_compiler:Mapping(module,inputs,'TanhAbs')
      end,

   -- Component-wise operators
   ["nn.CCSub"] =
      function(net_compiler, module, inputs)
         return net_compiler:CCSub(module, inputs)
      end,

   ["nn.CCAdd"] =
      function(net_compiler, module, inputs)
         return net_compiler:CCAdd(module, inputs)
      end,

   -- containers
   ["nn.Reshape"]  =
      function(net_compiler, module, inputs)
         return net_compiler:Reshape(module, inputs)
      end,

   ["nn.Sequential"] =
      function(net_compiler, module, inputs)
         return net_compiler:Sequential(module, inputs)
      end,

   ["nn.Parallel"] =
      function(net_compiler, module, inputs)
         return net_compiler:Parallel(module, inputs)
      end,
}


-- top level compiler function
function Compiler:processNetwork(network, inputs)
   if (self.print_times == 'detailled') then
      self.core:startProcess()
      self.core:message('unrolling convnet...')
      self.core:resetTime()
      self.core:getTime()
      self.core:endProcess()
   end
   local module_name = torch.typename(network)
   print('<neuflow.Compiler> processing network [type = ' .. module_name .. ']')
   local outputs = layer[module_name](self, network, inputs)
   self:printStats()
   return outputs
end

function Compiler:SpatialConvolution(conv_module, inputs, mapping)
   local outputs = {}
   local new_layer = true

   if (self.msg_level ~= 'none') then
      self.core:startProcess()
      if mapping then
         self.core:message(string.format('SC+M'))
      else
         self.core:message(string.format('SC'))
      end
      self.core:endProcess()
   end

   -- timing info
   if (self.msg_level == 'timing') then
      self.core:startProcess()
      self.core:resetTime()
      self.core:endProcess()
   end

   local coefs
   if mapping then
      -- generate coefs for this non-linear mapping
      coefs = self:getCoefs(mapping)
   end

   -- lists of connections
   local input_list = {}
   local kernel_list = {}
   local output_list = {}

   -- store inputs
   for i = 1,conv_module.nInputPlane do
      table.insert(input_list, self.core.mem.buff[inputs[i]])
   end

   -- parse connections
   for o = 1,conv_module.nOutputPlane do
      -- allocate output
      local item = self.core.mem.buff[inputs[1]]
      local output_width = math.floor( (item.orig_w - conv_module.kW)/conv_module.dW + 1 )
      local output_height = (item.orig_h - conv_module.kH)/conv_module.dH + 1
      if output_height ~= math.floor(output_height) then
         error('<neuflow.Compiler> ERROR: inconsistent subsampling ratios in_h='
               .. item.orig_h .. ', sub_h=' ..
               conv_module.kH .. ', out_h=' .. output_height)
      end
      local id_output = self.core.mem:allocOnTheHeap(output_height, output_width, {}, new_layer)
      outputs[o] = id_output
      new_layer = false

      -- store output
      table.insert(output_list, self.core.mem.buff[outputs[o]])

      -- store kernels
      for i = 1,conv_module.nInputPlane do
         -- allocate kernel
         local kernel = conv_module.weight[o][i]
         local bias = conv_module.bias:narrow(1,o,1)
         local id_kernel = self.core.mem:allocKernel(conv_module.kH, conv_module.kW, kernel, bias)

         -- collect connections
         table.insert(kernel_list, self.core.mem.raw_data[id_kernel])

         -- for info, update the number of ops
         self.ops = self.ops + output_width*output_height*conv_module.kW*conv_module.kH*2
      end
   end

   -- compute whole convol bank
   self.core:convolBank(input_list, kernel_list, output_list, coefs)

   -- timing info
   if (self.msg_level == 'timing') then
      self.core:startProcess()
      self.core:getTime()
      self.core:endProcess()
   end

   return outputs
end

function Compiler:SpatialConvolutionMap(conv_module, inputs, mapping)
   local outputs = {}
   local new_layer = true
   local new_output = true
   local current_op = 1

   if (self.msg_level ~= 'none') then
      self.core:startProcess()
      if mapping then
         self.core:message(string.format('SCT+M'))
      else
         self.core:message(string.format('SCT'))
      end
      self.core:endProcess()
   end

   -- timing info
   if (self.msg_level == 'timing') then
      self.core:startProcess()
      self.core:resetTime()
      self.core:endProcess()
   end

   local coefs
   if mapping then
      -- generate coefs for this non-linear mapping
      coefs = self:getCoefs(mapping)
   end

   -- parse connex table, and identidy output reuse / one2one connex
   -- if outputs are used more than once, then they'll be reused
   local output_reuse = false
   local one_to_one = false
   local diff = (conv_module.connTable:select(2,1)-conv_module.connTable:select(2,2)):abs():max()
   if diff == 0 then
      one_to_one = true
   else
      for i = 1,conv_module.connTable:size(1) do
         local current = conv_module.connTable[i][2]
         for j = 1,conv_module.connTable:size(1) do
            if j ~= i and current == conv_module.connTable[j][2] then
               output_reuse = true
               break
            end
         end
         if output_reuse then break end
      end
   end

   -- depending on output/input reuse and one2one connex:
   if one_to_one then
      local input_list = {}
      local kernel_list = {}
      local output_list = {}

      for o = 1,conv_module.nOutputPlane do
         -- allocate output
         local item = self.core.mem.buff[inputs[1]]
         local output_width = math.floor( (item.orig_w - conv_module.kW)/conv_module.dW + 1 )
         local output_height = (item.orig_h - conv_module.kH)/conv_module.dH + 1
         if output_height ~= math.floor(output_height) then
            error('<neuflow.Compiler> ERROR: inconsistent subsampling ratios in_h=' .. item.orig_h .. ', sub_h=' ..
                  conv_module.kH .. ', out_h=' .. output_height)
         end
         local id_output = self.core.mem:allocOnTheHeap(output_height, output_width, {}, new_layer)
         outputs[o] = id_output

         -- allocate kernel + bias
         local kernel = conv_module.weight[current_op]
         local bias = conv_module.bias:narrow(1,o,1)
         local id_kernel = self.core.mem:allocKernel(conv_module.kH, conv_module.kW,
                                                     kernel, bias)

         -- collect connections
         table.insert(input_list, self.core.mem.buff[inputs[o]])
         table.insert(output_list, self.core.mem.buff[outputs[o]])
         table.insert(kernel_list, self.core.mem.raw_data[id_kernel])

         -- for info, update the number of ops
         self.ops = self.ops + output_width*output_height*conv_module.kW*conv_module.kH*2

         -- next connex
         current_op = current_op + 1
         new_layer = false
      end

      -- compute output
      self.core:convolBank(input_list, kernel_list, output_list, coefs)

   elseif output_reuse then
      for o = 1,conv_module.nOutputPlane do
         -- allocate output
         local item = self.core.mem.buff[inputs[1]]
         local output_width = math.floor( (item.orig_w - conv_module.kW)/conv_module.dW + 1 )
         local output_height = (item.orig_h - conv_module.kH)/conv_module.dH + 1
         if output_height ~= math.floor(output_height) then
            error('<neuflow.Compiler> ERROR: inconsistent subsampling ratios in_h=' .. item.orig_h .. ', sub_h=' ..
                  conv_module.kH .. ', out_h=' .. output_height)
         end
         local id_output = self.core.mem:allocOnTheHeap(output_height, output_width, {}, new_layer)
         outputs[o] = id_output
         new_layer = false
         new_output = true

         local input_list = {}
         local kernel_list = {}
         local output_list = {self.core.mem.buff[id_output]}

         -- find all inputs
         for i = 1,conv_module.connTable:size(1) do
            if (o == conv_module.connTable[i][2]) then
               -- get input from table
               local input_p = conv_module.connTable[i][1]

               -- allocate kernel + bias
               local kernel = conv_module.weight[current_op]
               local bias = conv_module.bias:narrow(1,o,1)
               local id_kernel = self.core.mem:allocKernel(conv_module.kH, conv_module.kW,
                                                           kernel, bias)

               -- collect connections
               table.insert(input_list, self.core.mem.buff[inputs[input_p]])
               table.insert(kernel_list, self.core.mem.raw_data[id_kernel])

               -- for info, update the number of ops
               self.ops = self.ops + output_width*output_height*conv_module.kW*conv_module.kH*2

               -- next connex
               new_output = false
               current_op = current_op + 1
            end
         end

         -- compute output
         self.core:convolBank(input_list, kernel_list, output_list, coefs)
      end

   else -- input reuse
      for i = 1,conv_module.nInputPlane do
         -- lists of outputs/kernels
         local input_list = {self.core.mem.buff[inputs[i]]}
         local kernel_list = {}
         local output_list = {}

         -- find all outputs
         for oidx = 1,conv_module.connTable:size(1) do
            local o = conv_module.connTable[oidx][2]
            if (i == conv_module.connTable[o][1]) then
               -- allocate output
               local item = self.core.mem.buff[inputs[1]]
               local output_width = math.floor( (item.orig_w - conv_module.kW)/conv_module.dW + 1 )
               local output_height = (item.orig_h - conv_module.kH)/conv_module.dH + 1
               if output_height ~= math.floor(output_height) then
                  error('<neuflow.Compiler> ERROR: inconsistent subsampling ratios in_h=' .. item.orig_h .. ', sub_h=' ..
                        conv_module.kH .. ', out_h=' .. output_height)
               end
               local id_output = self.core.mem:allocOnTheHeap(output_height, output_width, {},
                                                              new_layer)
               outputs[o] = id_output

               -- allocate kernel + bias
               local kernel = conv_module.weight[o]
               local bias = conv_module.bias:narrow(1,o,1)
               local id_kernel = self.core.mem:allocKernel(conv_module.kH, conv_module.kW,
                                                           kernel, bias)

               -- collect connections
               table.insert(output_list, self.core.mem.buff[id_output])
               table.insert(kernel_list, self.core.mem.raw_data[id_kernel])

               -- for info, update the number of ops
               self.ops = self.ops + output_width*output_height*conv_module.kW*conv_module.kH*2

               -- next connex
               current_op = current_op + 1
               new_layer = false
            end
         end

         -- compute all outputs for given input
         self.core:convolBank(input_list, kernel_list, output_list, coefs)
      end
   end

   -- timing info
   if (self.msg_level == 'timing') then
      self.core:startProcess()
      self.core:getTime()
      self.core:endProcess()
   end

   return outputs
end

function Compiler:SpatialSubSampling(sub_module, inputs, mapping)
   local outputs = {}
   local new_layer = true

   if (self.msg_level ~= 'none') then
      self.core:startProcess()
      if mapping then
         self.core:message(string.format('SS+M'))
      else
         self.core:message(string.format('SS'))
      end
      self.core:endProcess()
   end

   -- timing info
   if (self.msg_level == 'timing') then
      self.core:startProcess()
      self.core:resetTime()
      self.core:endProcess()
   end

   local coefs
   if mapping then
      -- generate coefs for this non-linear mapping
      coefs = self:getCoefs(mapping)
   end

   -- NEW
   do
      local input_list = {}
      local kernel_list = {}
      local output_list = {}

      for o = 1,sub_module.nInputPlane do
         -- allocate output
         local input = self.core.mem.buff[inputs[o]]
         local output_width = math.floor( (input.orig_w-sub_module.kW)/sub_module.dW + 1)
         local output_height = (input.orig_h-sub_module.kH)/sub_module.dH + 1
         if output_height ~= math.floor(output_height) then
            output_height = math.floor(output_height)
            local newinput = {y = input.y,
                              x = input.x,
                              data = input.data,
                              orig_h = (output_height - 1)*sub_module.dH + sub_module.kH,
                              orig_w = input.orig_w,
                              w = 1,
                              h = 1}
            newinput.w = newinput.orig_w * newinput.orig_h
            input = newinput
         end
         local id_output = self.core.mem:allocOnTheHeap(output_height, output_width, {}, new_layer)
         outputs[o] = id_output

         -- allocate kernel + bias
         local kernel = torch.Tensor(sub_module.kW, sub_module.kH):fill(sub_module.weight[o])
         local bias = sub_module.bias:narrow(1,o,1)
         local id_kernel = self.core.mem:allocKernel(sub_module.kH, sub_module.kW,
                                                     kernel, bias)

         -- collect connections
         table.insert(input_list, input)
         table.insert(output_list, self.core.mem.buff[outputs[o]])
         table.insert(kernel_list, self.core.mem.raw_data[id_kernel])

         -- for info, update the number of ops
         self.ops = self.ops + output_width*output_height*sub_module.kW*sub_module.kH*2

         -- next connex
         new_layer = false
      end

      -- compute output
      self.core:convolBank(input_list, kernel_list, output_list, coefs)
   end

   -- timing info
   if (self.msg_level == 'timing') then
      self.core:startProcess()
      self.core:getTime()
      self.core:endProcess()
   end

   return outputs
end

function Compiler:SpatialLPPooling(sub_module, inputs, mapping)
   local outputs = {}
   local new_layer = true

   if torch.typename(sub_module.modules[1]) ~= 'nn.Square' then
      error('<neuflow.Compiler> ERROR: LP Pooling only supported with L2 norm')
   end

   if (self.msg_level ~= 'none') then
      self.core:startProcess()
      if mapping then
         self.core:message(string.format('SLP+M'))
         error('<neuflow.Compiler> ERROR: unsupported spatial LP pooling + mapping')
      else
         self.core:message(string.format('SLP'))
      end
      self.core:endProcess()
   end

   -- timing info
   if (self.msg_level == 'timing') then
      self.core:startProcess()
      self.core:resetTime()
      self.core:endProcess()
   end

   -- generate coefs for sqrt
   coefs = self:getCoefs('Sqrt')

   -- generate code for pooling
   do
      local input_list = {}
      local kernel_list = {}
      local output_list = {}

      for o = 1,sub_module.nInputPlane do
         -- allocate output
         local input = self.core.mem.buff[inputs[o]]
         local output_width = math.floor( (input.orig_w-sub_module.modules[2].kW)/sub_module.modules[2].dW + 1)
         local output_height = (input.orig_h-sub_module.modules[2].kH)/sub_module.modules[2].dH + 1
         if output_height ~= math.floor(output_height) then
            output_height = math.floor(output_height)
            local newinput = {y = input.y,
                              x = input.x,
                              data = input.data,
                              orig_h = (output_height - 1)*sub_module.modules[2].dH + sub_module.modules[2].kH,
                              orig_w = input.orig_w,
                              w = 1,
                              h = 1}
            newinput.w = newinput.orig_w * newinput.orig_h
            input = newinput
         end
         local id_output = self.core.mem:allocOnTheHeap(output_height, output_width, {}, new_layer)
         outputs[o] = id_output

         -- allocate kernel + bias
         local kernel = sub_module.modules[2].weight[o]
         local bias = sub_module.modules[2].bias:narrow(1,o,1)
         local id_kernel = self.core.mem:allocKernel(sub_module.modules[2].kH, 
                                                     sub_module.modules[2].kW,
                                                     kernel, bias)

         -- collect connections
         table.insert(input_list, input)
         table.insert(output_list, self.core.mem.buff[outputs[o]])
         table.insert(kernel_list, self.core.mem.raw_data[id_kernel])

         -- for info, update the number of ops
         self.ops = self.ops + output_width*output_height*sub_module.modules[2].kW*sub_module.modules[2].kH*2

         -- next connex
         new_layer = false
      end

      -- compute output
      self.core:l2pooling(input_list, kernel_list, output_list, coefs)
   end

   -- timing info
   if (self.msg_level == 'timing') then
      self.core:startProcess()
      self.core:getTime()
      self.core:endProcess()
   end

   return outputs
end

function Compiler:SpatialNormalization(sub_module, inputs)
   -- verbose
   if (self.msg_level ~= 'none') then
      self.core:startProcess()
      self.core:message(string.format('NZ'))
      self.core:endProcess()
   end

   -- timing info
   if (self.msg_level == 'timing') then
      self.core:startProcess()
      self.core:resetTime()
      self.core:endProcess()
   end

   -- alloc one kernel for the whole layer
   local kernel = sub_module.kernel
   local kernel_w = kernel:size(1)
   local kernel_h = kernel:size(2)
   local id_kernel_mean = self.core.mem:allocRawData(kernel_h, kernel_w, kernel)
   local id_kernel_std = self.core.mem:allocRawData(kernel_h, kernel_w, kernel)

   -- alloc one intermediate map (to hold zero-mean feature map)
   local zerom_w = self.core.mem.buff[inputs[1]].orig_w
   local zerom_h = self.core.mem.buff[inputs[1]].orig_h
   local zeros = {}
   local new_layer = true
   for i = 1,sub_module.nfeatures do
      zeros[i] = self.core.mem:allocOnTheHeap(zerom_h, zerom_w, {}, new_layer)
      new_layer = false
   end

   -- alloc all output maps
   local outputs = {}
   local new_layer = true
   local output_w = self.core.mem.buff[inputs[1]].orig_w
   local output_h = self.core.mem.buff[inputs[1]].orig_h
   for i = 1,sub_module.nfeatures do
      outputs[i] = self.core.mem:allocOnTheHeap(output_h, output_w, {}, new_layer)
   end

   -- collect inputs/outputs/kernels
   local input_maps = {}
   local zero_maps = {}
   local output_maps = {}
   local mean_kernels = {}
   local std_kernels = {}
   for i = 1,sub_module.nfeatures do
      table.insert(input_maps, self.core.mem.buff[inputs[i]])
      table.insert(zero_maps, self.core.mem.buff[zeros[i]])
      table.insert(output_maps, self.core.mem.buff[outputs[i]])
      table.insert(mean_kernels, self.core.mem.raw_data[id_kernel_mean])
      table.insert(std_kernels, self.core.mem.raw_data[id_kernel_std])
   end

   -- get threshold
   local threshold = sub_module.fixedThres

   -- get coefs for mapping
   local xN_coefs = {}
   local sqrtCoefs = {}
   if (sub_module.__typename == "nn.SpatialNormalization_hardware") then
      xN_coefs = sub_module.xN_coefs
      sqrtCoefs = sub_module.sqrtCoefs_no_pad
   else
      -- coefs for div by num of features
      local xN = function (x)
                    return x / #mean_kernels
                 end
      xN_coefs = math.approx_line{mapping=xN, min=num.min, max=num.max, odd = true,
                                  nbSegments=grid.mapper_segs, Q=num.frac_,
                                  verbose=true, a = 1/#mean_kernels, b = 0}

      -- generate coefs for sqrt
      local mapping
      threshold = threshold or 1/256
      if (threshold == 0) then threshold = 1/256 end
      mapping = function (x)
                   x = x / #std_kernels
                   if x < threshold then return math.sqrt(threshold)
                   else return math.sqrt(x) end
                end
      sqrtCoefs = math.approx{mapping=mapping, min=0, max=num.max,
                              nbSegments=grid.mapper_segs, Q=num.frac_,
                              verbose=true, epsilon=25/256,error_type = 0,
                              name = 'Sqrt_th_div_'..#std_kernels..'_s_'..threshold}

   end

   -- local norm mean
   self.core:localNormalizeMeanBank(input_maps, mean_kernels, zero_maps, xN_coefs)

   -- local norm std
   self.core:localNormalizeStdBank(zero_maps, std_kernels, output_maps, sqrtCoefs)

   -- for info, update the number of ops
   self.ops = self.ops + (output_w*output_h*kernel_w*kernel_h*2
                          + zerom_w*zerom_h*(kernel_w*kernel_h*2 + 16)) * sub_module.nfeatures

   -- timing info
   if (self.msg_level == 'timing') then
      self.core:startProcess()
      self.core:getTime()
      self.core:endProcess()
   end

   -- return output maps
   return outputs
end

function Compiler:SpatialSubtractiveNormalization(sub_module, inputs)
   -- verbose
   if (self.msg_level ~= 'none') then
      self.core:startProcess()
      self.core:message(string.format('SNZ'))
      self.core:endProcess()
   end

   -- timing info
   if (self.msg_level == 'timing') then
      self.core:startProcess()
      self.core:resetTime()
      self.core:endProcess()
   end

   -- alloc one kernel for the whole layer
   local kernel = sub_module.kernel
   local kernel_h = kernel:size(1)
   local kernel_w = kernel:size(2)
   local id_kernel_mean = self.core.mem:allocRawData(kernel_h, kernel_w, kernel)

   -- alloc output maps
   local output_w = self.core.mem.buff[inputs[1]].orig_w
   local output_h = self.core.mem.buff[inputs[1]].orig_h
   local outputs = {}
   local new_layer = true
   for i = 1,sub_module.nInputPlane do
      outputs[i] = self.core.mem:allocOnTheHeap(output_h, output_w, {}, new_layer)
      new_layer = false
   end

   -- collect inputs/outputs/kernels
   local input_maps = {}
   local output_maps = {}
   local mean_kernels = {}
   for i = 1,sub_module.nInputPlane do
      table.insert(input_maps, self.core.mem.buff[inputs[i]])
      table.insert(output_maps, self.core.mem.buff[outputs[i]])
      table.insert(mean_kernels, self.core.mem.raw_data[id_kernel_mean])
   end

   -- get coefs for mapping
   local xN = function (x)
      return x / #mean_kernels
   end
   local xN_coefs = math.approx_line{mapping=xN, min=num.min, max=num.max, odd = true,
                                     nbSegments=grid.mapper_segs, Q=num.frac_,
                                     verbose=true, a = 1/#mean_kernels, b = 0}

   -- local norm mean
   self.core:localNormalizeMeanBank(input_maps, mean_kernels, output_maps, xN_coefs)

   -- for info, update the number of ops
   self.ops = self.ops + (output_w*output_h*kernel_w*kernel_h*2) * sub_module.nInputPlane

   -- timing info
   if (self.msg_level == 'timing') then
      self.core:startProcess()
      self.core:getTime()
      self.core:endProcess()
   end

   -- return output maps
   return outputs
end

function Compiler:Parallel(par_module, inputs)
   -- verbose
   if (self.msg_level ~= 'none') then
      self.core:startProcess()
      self.core:message(string.format('PA'))
      self.core:endProcess()
   end

   -- timing info
   if (self.msg_level == 'timing') then
      self.core:startProcess()
      self.core:resetTime()
      self.core:endProcess()
   end

   -- not done yet
   xlua.error('Parallel not implemented yet', 'neuflow.Compiler')

   -- timing info
   if (self.msg_level == 'timing') then
      self.core:startProcess()
      self.core:getTime()
      self.core:endProcess()
   end

   -- return output maps
   return outputs
end

function Compiler:Sequential(network, inputs)
   -- verbose
   if (self.msg_level ~= 'none') then
      self.core:startProcess()
      self.core:message(string.format('SEQ'))
      self.core:endProcess()
   end

   -- process Sequential
   local doneAdvance = 0
   local outputs
   for i=1,#network.modules do
      if doneAdvance > 0 then
         doneAdvance = doneAdvance - 1
      else
         local module_0, module_1, module_2, module_3, module_name
         module_0 = network.modules[i+0].__typename
         if module_0 == 'nn.SpatialConvolutionSparse' then
            module_0 = 'nn.SpatialConvolutionMap'
         end
         module_name = module_0
         if i+1 <= #network.modules then
            module_1 = network.modules[i+1].__typename
         end
         if i+2 <= #network.modules then
            module_2 = network.modules[i+2].__typename
         end
         if i+3 <= #network.modules then
            module_3 = network.modules[i+3].__typename
         end
         io.write(sys.COLORS.cyan)
         io.write('<neuflow.Compiler> processing layer of type > '..module_0)
         mapping = nil
         if self.opt_across_layers then
            if module_0 == 'nn.Tanh' and module_1 == 'nn.Abs' then
               module_name = 'nn.TanhAbs'
               io.write(' merged with next layer > '..module_1..' >>> '..module_name)
               doneAdvance = 1
            elseif module_0 == 'nn.Mult' and module_1 == 'nn.Tanh' and module_2 == 'nn.Mult' then
               module_name = 'nn.StdSigm'
               io.write(' merged with next layers > '..module_1..' & '..module_2..
                        ' >>> '..module_name)
               doneAdvance = 2
            elseif module_0 == 'nn.SpatialConvolution'
               and module_1 == 'nn.Tanh' and module_2 == 'nn.Abs' then
               mapping = 'TanhAbs'
               io.write(' merged with next layers > '..module_1..' & '..module_2..
                        ' >>> '..module_name)
               doneAdvance = 2
            elseif module_0 == 'nn.SpatialConvolution' and module_1 == 'nn.Tanh' then
               mapping = 'Tanh'
               io.write(' merged with next layers > '..module_1..' >>> '..module_name)
               doneAdvance = 1
            elseif module_0 == 'nn.SpatialConvolution' and module_1 == 'nn.HardTanh' then
               mapping = 'HardTanh'
               io.write(' merged with next layers > '..module_1..' >>> '..module_name)
               doneAdvance = 1
            elseif module_0 == 'nn.SpatialSubSampling' and module_1 == 'nn.Tanh' then
               mapping = 'Tanh'
               io.write(' merged with next layers > '..module_1..' >>> '..module_name)
               doneAdvance = 1
            elseif module_0 == 'nn.SpatialSubSampling' and module_1 == 'nn.Mult'
               and module_2 == 'nn.Tanh' and module_3 == 'nn.Mult' then
               mapping = 'StdSigm'
               io.write(' merged with next layers > '..module_1..' & '..module_2..' & '..module_3
                        ..' >>> '..module_name)
               doneAdvance = 3
            elseif module_0 == 'nn.SpatialConvolutionMap'
               and module_1 == 'nn.Tanh' and module_2 == 'nn.Abs' then
               mapping = 'TanhAbs'
               io.write(' merged with next layers > '..module_1..' & '..module_2
                        ..' >>> '..module_name)
               doneAdvance = 2
            elseif module_0 == 'nn.SpatialConvolutionMap' and module_1 == 'nn.Tanh' then
               mapping = 'Tanh'
               io.write(' merged with next layers > '..module_1..' >>> '..module_name)
               doneAdvance = 1
            elseif module_0 == 'nn.SpatialConvolutionMap' and module_1 == 'nn.HardTanh' then
               mapping = 'HardTanh'
               io.write(' merged with next layers > '..module_1..' >>> '..module_name)
               doneAdvance = 1
            elseif module_0 == 'nn.SpatialConvolutionMap' and module_1 == 'nn.Mult'
               and module_2 == 'nn.Tanh' and module_3 == 'nn.Mult' then
               mapping = 'StdSigm'
               io.write(' merged with next layers > '..module_1..' & '..module_2..' & '..module_3
                        ..' >>> '..module_name)
               doneAdvance = 3
            end
         end
         print(sys.COLORS.none)
         if layer[module_name] then
            outputs = layer[module_name](self, network.modules[i], inputs, mapping)
         else
            xlua.error(message.ERROR_IMPLEMENTED .. module_name)
            outputs = inputs
         end
         inputs = outputs
         if (self.msg_level == 'detailled') then
            self.core:startProcess()
            self.core:getTime()
            self.core:resetTime()
            self.core:endProcess()
         end
      end
   end

   -- return output maps
   return outputs
end

function Compiler:SpatialLinear(linear_module, inputs)
   local outputs = {}
   local new_layer = true

   if (self.msg_level ~= 'none') then
      self.core:startProcess()
      self.core:message(string.format('SL'))
      self.core:endProcess()
   end

   for o = 1,linear_module.fanout do
      -- allocate output
      local item = self.core.mem.buff[inputs[1]]
      local output_width = item.orig_w
      local output_height = item.orig_h
      local id_output = self.core.mem:allocOnTheHeap(output_height, output_width, {}, new_layer)
      outputs[o] = id_output
      new_layer = false

      for i = 1,linear_module.fanin do
         -- allocate kernel
         local kernel = torch.Tensor(1, 1):fill(linear_module.weight[o][i])
         local bias = linear_module.bias:narrow(1,o,1)
         local id_kernel = self.core.mem:allocKernel(1, 1, kernel, bias)

         -- for info, update the number of ops
         self.ops = self.ops + output_width*output_height*3

         -- generate code for convolution
         if (i == 1) then
            self.core:convolve(self.core.mem.buff[inputs[i]],
                               self.core.mem.raw_data[id_kernel],
                               self.core.mem.buff[id_output],
                               {bias = 'on'})
         else
            self.core:convolveAndAcc(self.core.mem.buff[inputs[i]],
                                     self.core.mem.raw_data[id_kernel],
                                     self.core.mem.buff[outputs[o]],
                                     self.core.mem.buff[outputs[o]])
            -- nb of ops
            self.ops = self.ops + output_width*output_height
         end

         -- optional time
         if (self.msg_level == 'detailled') then
            self.core:startProcess()
            self.core:messagebody('.')
            self.core:endProcess()
         end
      end
   end
   return outputs
end

function Compiler:getCoefs(mapping)
   local type = mapping

   -- generate coefs for this non-linear mapping
   if type == 'Tanh' then
      coefs=math.approx{mapping=math.tanh, min=-5, max=5, odd=true,
                        nbSegments=grid.mapper_segs, Q=num.frac_,
                        verbose=true, epsilon = 11.7/256, error_type = 0,
                        name = type}

   elseif type == 'Abs' then
      coefs=math.approx{mapping=math.abs, min=num.min, max=num.max, even=true,
                        nbSegments=grid.mapper_segs, Q=num.frac_,
                        verbose=true, error_type = 0,
                        name = type}
   elseif type == 'TanhAbs' then
      function tanhabs (x) return math.abs(math.tanh(x)) end
      coefs=math.approx{mapping=tanhabs, min=-5, max=5, even=true,
                        nbSegments=grid.mapper_segs, Q=num.frac_,
                        verbose=true, epsilon = 11.7/256, error_type = 0,
                        name = type}
   elseif type == 'StdSigm' then
      function stdsigm (x) return 1.71593428 * math.tanh(0.66666666*x) end
      coefs=math.approx{mapping=stdsigm, min=num.min, max=num.max, odd=true,
                        nbSegments=grid.mapper_segs, Q=num.frac_,
                        verbose=true,epsilon = 4/256, error_type = 1,
                        name = 'StdSigm_abs_err_all_range'}--type}
   elseif type == 'StdSigmAbs' then
      function stdsigm (x) return 1.71593428 * math.tanh(0.66666666*x) end
      coefs=math.approx{mapping=stdsigm, min=-5.5, max=5.5, even=true,
                        nbSegments=grid.mapper_segs, Q=num.frac_,
                        verbose=true, epsilon = 32.21/256, error_type = 0,
                        name = type}
   elseif type == 'Sqrt' then
      coefs=math.approx{mapping=math.sqrt, min=0, max=num.max,
                        nbSegments=grid.mapper_segs, Q=num.frac_,
                        verbose=true, epsilon = 19.7/256, error_type = 0,
                        name = type}
   elseif type == 'HardTanh' then
      coefs=math.approx_HardTanh{nbSegments=grid.mapper_segs}
   else
      error('<neuflow.Compiler> ERROR: unknown mapping')
   end

   return coefs
end

function Compiler:Mapping(module, inputs, type)
   local outputs = {}

   if (self.msg_level ~= 'none') then
      self.core:startProcess()
      self.core:message(string.format('doing Tanh [%0d maps]', #inputs))
      self.core:endProcess()
   end

   -- generate coefs for this non-linear mapping
   coefs = self:getCoefs(type)

   -- generate code
   for i = 1,#inputs do
      local id_output = self.core.mem:allocOnTheHeap(self.core.mem.buff[inputs[i]].orig_h,
                                                     self.core.mem.buff[inputs[i]].orig_w , {}, false)
      self.core:mapping(self.core.mem.buff[inputs[i]], self.core.mem.buff[id_output], coefs)

      -- optional time
      if (self.msg_level == 'detailled') then
         self.core:startProcess()
         self.core:messagebody('.')
         self.core:endProcess()
      end
      outputs[i] = id_output

      -- for info (16 is approx here, it's hard to say what a mapping takes)
      self.ops = self.ops + self.core.mem.buff[inputs[i]].orig_h*self.core.mem.buff[inputs[i]].orig_w*16
   end
   return outputs
end

function Compiler:CCSub(module, inputs)
   local outputs = {}

   if (self.msg_level ~= 'none') then
      self.core:startProcess()
      self.core:message(string.format('doing CCSub [%0d maps]', #inputs))
      self.core:endProcess()
   end

   -- 2 inputs required
   if #inputs ~= 2 then
      error('<Compiler:CCSub> 2 inputs required')
   end

   -- alloc output
   outputs[1] = self.core.mem:allocOnTheHeap(self.core.mem.buff[inputs[1]].orig_h,
                                             self.core.mem.buff[inputs[1]].orig_w , {}, false)

   -- generate code
   self.core:subtract(self.core.mem.buff[inputs[1]],
                      self.core.mem.buff[inputs[2]],
                      self.core.mem.buff[outputs[1]])

   -- optional time
   if (self.msg_level == 'detailled') then
      self.core:startProcess()
      self.core:messagebody('.')
      self.core:endProcess()
   end

   -- for info
   self.ops = self.ops + self.core.mem.buff[inputs[1]].orig_h*self.core.mem.buff[inputs[1]].orig_w
   return outputs
end

function Compiler:CCAdd(module, inputs)
   local outputs = {}

   if (self.msg_level ~= 'none') then
      self.core:startProcess()
      self.core:message(string.format('doing CCSub [%0d maps]', #inputs))
      self.core:endProcess()
   end

   -- 2 inputs required
   if #inputs ~= 2 then
      error('<Compiler:CCSub> 2 inputs required')
   end

   -- alloc output
   outputs[1] = self.core.mem:allocOnTheHeap(self.core.mem.buff[inputs[1]].orig_h,
                                             self.core.mem.buff[inputs[1]].orig_w , {}, false)

   -- generate code
   self.core:add(self.core.mem.buff[inputs[1]],
                 self.core.mem.buff[inputs[2]],
                 self.core.mem.buff[outputs[1]])

   -- optional time
   if (self.msg_level == 'detailled') then
      self.core:startProcess()
      self.core:messagebody('.')
      self.core:endProcess()
   end

   -- for info
   self.ops = self.ops + self.core.mem.buff[inputs[1]].orig_h*self.core.mem.buff[inputs[1]].orig_w
   return outputs
end

function Compiler:Reshape(reshape_module, inputs)
   -- warning: only handle dim reshape
   local outputs = {}
   outputs[1] = self.core.mem:allocOnTheHeap(reshape_module.output:size(1),
                                             reshape_module.output:size(2),
                                             reshape_module.output, true)
   return outputs
end

function Compiler:printStats()
   str = string.format('network computed requires %f MOPs', self.ops/1000000.)
   print('<neuflow.Compiler> '..str)
   return str
end
