--[[ Class: Memory

This class is used to allocate areas of memory in a controlled manner. It
generate offsets and areas. If data needs to be written to the bytecode start
up stream, that is done in the Linker class.

The offsets and memory areas are represented in pixels. Conceptually the memory
is considered to be a large rectangular matrix.

The requirements for the memory that gets allocation vary but for our purposes
they can be grouped into three broad types. As such when requesting a memory
allocation the way that memory will be used needs to be considered and the
correct alloc function selected. The definition of these 3 type are as follows:

1) Embedded data (e.g., kernels) whose value is know at compile time and thus
   would benefit by being written to memory when the bytecode is sent at start
   up.

2) Persistent data (e.g., circular image buffers). The contents of this memory
   may be updated or change in time but the area addressing it does not. This
   allocation is used when data needs to be preserved between multiples layers
   in a conv net or between multiple runs of the program.

3) Managed data (e.g., intermediate results). The contents of which only need
   to exist to pass data between operations or layers in a program. Area
   allocations of this type can be freed and reused in a managed fashion as the
   need arises.

--]]

local Memory = torch.class('neuflow.Memory')

function Memory:__init(args)

   self.prog_name = args.prog_name
   self.init_offset = (args.init_offset or 0) + 1
   self.bytecode_size_b = 0

   -- table of embedded data segments
   self.embedded = {
      ['start'] = {
         ['x'] = 0,
         ['y'] = 0
      },
      ['current'] = {
         ['x'] = 0,
         ['y'] = 0
      }
   }

   -- table of persistent data segments
   self.persistent = {
      ['start'] = {
         ['x'] = 0,
         ['y'] = 0
      },
      ['current'] = {
         ['x'] = 0,
         ['y'] = 0
      },
      ['layer'] = {
         ['h'] = 0
      }
   }

   -- table of managed data segments
   self.managed = {
      ['start'] = {
         ['x'] = 0,
         ['y'] = 0,
      },
      ['current'] = {
         ['x'] = 0,
         ['y'] = 0,
      },
      ['layer'] = {
         ['h'] = 0,
         ['packing'] = '1D'
      },
   }

   self.managed_prev_layer_h = 0

   -- we want to keep this value for the
   -- final report sizes to be accurate
   self.last_align = 0
end

function Memory:adjustBytecodeSize(size_in_bytes)

   self.bytecode_size_b = size_in_bytes

   self.embedded.start.x = 0
   self.embedded.start.y =  math.ceil((size_in_bytes + 1) / streamer.stride_b)

   self.persistent.start.x = 0
   self.persistent.start.y = self.embedded.start.y + self.embedded.current.y + 1

   self.managed.start.x = 0
   self.managed.start.y = self.persistent.start.y + self.persistent.current.y + 1
end

function Memory:constructCoordinate(area, coor)
   return {
      coor = coor,
      start = self[area].start,
      offset = self[area].current[coor],
      calc = function(self)
         return self.start[self.coor] + self.offset
      end
   }
end

--[[ Allocate Embedded Data

   Current assumption is that all data being written is a kernel.
--]]
function Memory:allocEmbeddedData(data_, bias_)
   local orig_w_  = data_:size(2)
   local orig_h_  = data_:size(1)

   local dh = grid.kernel_height - data_:size(1)
   local kernel = torch.zeros(grid.kernel_height, grid.kernel_width)

   -- copy incoming data to the bottom left corner of kernel
   for r = 1, orig_h_ do
      for c = 1, orig_w_ do
         kernel[r+dh][c] = data_[r][c]
      end
   end

   -- overwrite with new transformed values
   data_ = kernel
   h_ = 1

   if bias_ then
      w_ = kernel:size(1)*kernel:size(2) + bias_:size(1)
   else
      w_ = data_:size(1) * data_:size(2)
   end

   -- check if current data fits in the line
   if (self.embedded.current.x + w_) > streamer.stride_w then
      self.embedded.current.x = 0
      self.embedded.current.y = self.embedded.current.y + 1
   end

   self.embedded[ #self.embedded+1 ] = {
      x        = self:constructCoordinate('embedded', 'x'),
      y        = self:constructCoordinate('embedded', 'y'),
      w        = w_,
      h        = h_,
      orig_w   = orig_w_,
      orig_h   = orig_h_,
      data     = data_,
      bias     = bias_
   }

   self.embedded.current.x = self.embedded.current.x + w_

   -- alignment of addresses to physical memory pages
   if (self.embedded.current.x % streamer.align_w) ~= 0 then
      self.embedded.current.x = (math.floor(self.embedded.current.x/streamer.align_w) + 1) * streamer.align_w
      -- and check if we did not step out of the line again
      if (self.embedded.current.x > streamer.stride_w) then
         self.embedded.current.y = self.embedded.current.y + 1
         self.embedded.current.x = 0
      end
   end

   return self.embedded[ #self.embedded ]
end

--[[ Allocate Persistent Data

   Current assumption is that data is no wider then the streamer (memory)
   stride width.
--]]
function Memory:allocPersistentData(data_)
   local w_  = data_:size(2)
   local h_  = data_:size(1)

   -- the layer height is the height of the maximum data area in the layer
   if self.persistent.layer.h < h_ then
      self.persistent.layer.h = h_
   end

   -- check if current data fits in the line
   if (self.persistent.current.x + w_) > streamer.stride_w then
      self.persistent.current.x = 0
      self.persistent.current.y = self.persistent.current.y + self.persistent.layer.h
      self.persistent.layer.h = 0
   end

   self.persistent[ #self.persistent+1 ] = {
      x        = self:constructCoordinate('persistent', 'x'),
      y        = self:constructCoordinate('persistent', 'y'),
      w        = w_,
      h        = h_,
      orig_w   = w_,
      orig_h   = h_,
      data     = data_
   }

   -- assume that the width of the data cannot exceed the line,
   self.persistent.current.x = self.persistent.current.x + w_

   -- alignment of addresses to physical memory pages
   if (self.persistent.current.x % streamer.align_w) ~= 0 then
      self.persistent.current.x = (math.floor(self.persistent.current.x/streamer.align_w) + 1)*streamer.align_w
      -- and check if we did not step out of the line again
      if (self.persistent.current.x > streamer.stride_w) then
         self.persistent.current.x = 0
         self.persistent.current.y = self.persistent.current.y + self.persistent.layer.h
         self.persistent.layer.h = 0
      end
   end

   return self.persistent[ #self.persistent ]
end

--[[ Allocate Managed Data

   Data can be transformed to use 1D or 2D packing depending on packing
   argument. If 2D is selected but the width of the data is larger then the
   streamer (memory) stride, packing is reverted to 1D.

   If the end of physical memory is reached, function will start overwriting
   from the start of the Managed memory space.
--]]
function Memory:allocManagedData(data_, packing)
   packing = packing or '1D'
   assert(packing == '1D' or packing == '2D')

   local orig_w_ = data_:size(2)
   local orig_h_ = data_:size(1)
   local w_
   local h_
   local offset_width
   local offset_height

   if (('2D' == packing) and (orig_w_ > streamer.stride_w)) then
      print("<neuflow.Memory> WARNING: Current Managed Data tensor cannot be written with 2D packing, switching to 1D.")
      packing = '1D'
   end

   if '1D' == packing then
      w_ = orig_w_ * orig_h_
      h_ = 1

      offset_width = w_ % streamer.stride_w
      offset_height = math.floor(w_ / streamer.stride_w)

      if '1D' ~= self.managed.layer.packing then
         self.managed.current.x = 0
         self.managed.current.y = self.managed.current.y + self.managed.layer.h
         self.managed.layer.h = 0
      end
   else
      w_ = orig_w_
      h_ = orig_h_

      offset_width = w_
      offset_height = h_

      -- check if current data fits in the line
      if (self.managed.current.x + w_) > streamer.stride_w then
         self.managed.current.x = 0
         self.managed.current.y = self.managed.current.y + self.managed.layer.h
         self.managed.layer.h = 0
      end
   end

   -- check if there is space in the mem if not start overwriting first layers
   if (self.managed.current.y + offset_height) > memory.size_r then
      print("<neuflow.Memory> WARNING: Overwriting the first layers of heap!")
      self.managed.current.x = 0
      self.managed.current.y = 0
      self.managed.layer.h = 0
   end

   -- the layer height is the height of the maximum data area in the layer
   if self.managed.layer.h < h_ then
      self.managed.layer.h = h_
   end

   self.managed[ #self.managed+1 ] = {
      x        = self:constructCoordinate('managed', 'x'),
      y        = self:constructCoordinate('managed', 'y'),
      w        = w_,
      h        = h_,
      orig_w   = orig_w_,
      orig_h   = orig_h_,
      data     = data_
   }

   self.managed.current.x = self.managed.current.x + offset_width

   if '1D' == packing then
      self.managed.current.y = self.managed.current.y + offset_height

      --  check if we did not step out of the line
      if (self.managed.current.x > streamer.stride_w) then
         self.managed.current.y = self.managed.current.y + 1
         self.managed.current.x = self.managed.current.x - streamer.stride_w
      end
   end

   -- alignment of addresses to physical memory pages
   if (self.managed.current.x % streamer.align_w) ~= 0 then
      self.managed.current.x = (math.floor(self.managed.current.x/streamer.align_w) + 1)*streamer.align_w
      -- and check if we did not step out of the line again
      if (self.managed.current.x > streamer.stride_w) then
         self.managed.current.x = 0
         self.managed.current.y = self.managed.current.y + self.managed.layer.h
         self.managed.layer.h = 0
      end
   end

   self.managed.layer.packing = packing

   return self.managed[#self.managed]
end

function Memory:printAreaStatistics()

   embedded_start_b = self.embedded.start.y * streamer.stride_b
                    + self.embedded.start.x * streamer.word_b

   embedded_size_b = self.embedded.current.y * streamer.stride_b
                   + self.embedded.current.x * streamer.word_b

   persistent_start_b = self.persistent.start.y * streamer.stride_b
                      + self.persistent.start.x * streamer.word_b

   persistent_size_b = self.persistent.current.y * streamer.stride_b
   if (self.persistent.current.x ~= 0) then
      -- if we did not just step a new line
      -- take into account all the lines we wrote (the last entry's height is enough)
      -- if not all the lines are filled till the end we are counting more than we should here,
      -- but for checking collision it's OK
      persistent_size_b = persistent_size_b + self.persistent[#self.persistent].h * streamer.stride_b
   end

   managed_start_b = self.managed.start.y * streamer.stride_b
                   + self.managed.start.x * streamer.word_b

   managed_size_b = self.managed.current.y * streamer.stride_b
   if (self.managed.current.x ~= 0) then
      -- if we did not just step a new line
      -- take into account all the lines we wrote (the last entry's height is enough)
      -- if not all the lines are filled till the end we are counting more than we should here,
      -- but for checking collision it's OK
      managed_size_b = managed_size_b + (self.managed[#self.managed].h * streamer.stride_b)
   end

   local binary_size
   if #self.persistent == 0 then
      binary_size = embedded_start_b+embedded_size_b
   else
      binary_size = persistent_start_b+persistent_size_b
   end

   print("++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++")
   print(c.Cyan .. '-openFlow-' .. c.Magenta .. ' ConvNet Name ' ..
         c.none ..'[ ' .. self.prog_name .. ' ]\n')
   print(
      string.format("       bytecode segment: start = %10d, size = %10d, end = %10d",
         self.init_offset,
         self.bytecode_size_b-self.init_offset,
         self.bytecode_size_b)
   )
   print(
      string.format("  embedded data segment: start = %10d, size = %10d, end = %10d",
         embedded_start_b,
         embedded_size_b,
         embedded_start_b+embedded_size_b)
   )
   print(
      string.format("persistent data segment: start = %10d, size = %10d, end = %10d",
         persistent_start_b,
         persistent_size_b,
         persistent_start_b+persistent_size_b)
   )
   print(
      string.format("   managed data segment: start = %10d, size = %10d, end = %10d",
         managed_start_b,
         managed_size_b,
         memory.size_b)
   )
   print(
      string.format("\n  the binary file size should be = %10d, total memory used = %10d",
         binary_size,
         managed_start_b+managed_size_b)
   )
   print("++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++")

end
