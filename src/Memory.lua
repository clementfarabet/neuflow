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
      }
   }

   -- table of managed data segments
   self.managed = {
      ['start'] = {
         ['x'] = 0,
         ['y'] = 0
      },
      ['current'] = {
         ['x'] = 0,
         ['y'] = 0
      }
   }

   self.managed_prev_layer_h = 0

   -- we want to keep this value for the
   -- final report sizes to be accurate
   self.last_align = 0
end

function Memory:adjustBytecodeSize(size_in_bytes)

   self.embedded.start.x = 0
   self.embedded.start.y =  math.ceil((size_in_bytes + 1) / streamer.stride_b)

   self.persistent.start.x = 0
   self.persistent.start.y = self.embedded.start.y + self.embedded.current.y + 1

   self.managed.start.x = 0
   self.managed.start.y = self.persistent.start.y + self.persistent.current.y + 1
end

function Memory:allocKernel(h_, w_, data_, bias_)
   orig_h_ = data_:size(1)
   orig_w_ = data_:size(2)
   -- transpose kernel to go to inner dim last
   if((data_:size(2) < grid.kernel_width) or (data_:size(1) < grid.kernel_height)) then
      data_ker_size = torch.zeros(grid.kernel_height, grid.kernel_width)
      -- now need to save to bottom left corner!!!!!
      big_i = grid.kernel_width - h_ + 1 -- bottom
      for i=1,h_ do
         big_j = 1 -- bottom left corner
         for j=1,w_ do
            data_ker_size[big_i][big_j] = data_[i][j]
            big_j = big_j + 1
         end
         big_i = big_i + 1
      end
      data_ = data_ker_size
      h_ = data_:size(1)
      w_ = data_:size(2)
   end

   -- check if current data fits in the line
   if (self.embedded.current.x + w_*h_ + bias_:size(1)) > streamer.stride_w then
      self.embedded.current.x = 0
      self.embedded.current.y = self.embedded.current.y + 1
   end

   self.embedded[ #self.embedded+1 ] = {
      x = {
         offset = self.embedded.current.x,
         calc = function(self, mem)
            return mem.embedded.start.x + self.offset
         end
      },

      y = {
         offset = self.embedded.current.y,
         calc = function(self, mem)
            return mem.embedded.start.y + self.offset
         end
      },

      w        = data_:size(1)*data_:size(2) + bias_:size(1),
      h        = 1,
      orig_w   = orig_w_,
      orig_h   = orig_h_,
      data     = data_,
      bias     = bias_
   }

   self.embedded.current.x = self.embedded.current.x + w_*h_ + bias_:size(1)
   -- check allignment
   if (self.embedded.current.x % streamer.align_w) ~= 0 then
      self.last_align = (math.floor(self.embedded.current.x/streamer.align_w) + 1) * streamer.align_w
                        - self.embedded.current.x
      self.embedded.current.x = (math.floor(self.embedded.current.x/streamer.align_w) + 1) * streamer.align_w
      -- and check if we did not step out of the line again
      if (self.embedded.current.x > streamer.stride_w) then
         self.embedded.current.y = self.embedded.current.y + 1
         self.embedded.current.x = 0
         self.last_align = 0
      end
   end
   return self.embedded[ #self.embedded ]
end

function Memory:allocRawData(h_, w_, data_)
   orig_h_ = data_:size(1)
   orig_w_ = data_:size(2)
   -- transpose kernel to go to inner dim last
   if((data_:size(2) < grid.kernel_width) or (data_:size(1) < grid.kernel_height)) then
      data_ker_size = torch.zeros(grid.kernel_height, grid.kernel_width)
      -- now need to save to bottom left corner!!!!!
      big_i = grid.kernel_width - h_ + 1 -- bottom
      for i=1,h_ do
         big_j = 1 -- bottom left corner
         --big_j = grid.kernel_width - w_ + 1 -- bottom right corner
         for j=1,w_ do
            --print("i = ", i, "j = ", j, "big_i = ", big_i, "big_j = ", big_j)
            data_ker_size[big_i][big_j] = data_[i][j]
            big_j = big_j + 1
         end
         big_i = big_i + 1
      end
      data_ = data_ker_size
      h_ = data_:size(1)
      w_ = data_:size(2)
   end

   -- check if current data fits in the line
   if (self.embedded.current.x + w_*h_) > streamer.stride_w then
       self.embedded.current.x = 0
       self.embedded.current.y = self.embedded.current.y + 1
   end

   self.embedded[ #self.embedded+1 ] = {
      x = {
         offset = self.embedded.current.x,
         calc = function(self, mem)
            return mem.embedded.start.x + self.offset
         end
      },

      y = {
         offset = self.embedded.current.y,
         calc = function(self, mem)
            return mem.embedded.start.y + self.offset
         end
      },

      w = data_:size(1)*data_:size(2),
      h = 1,
      orig_h = orig_h_,
      orig_w = orig_w_,
      data = data_
   }

   self.embedded.current.x = self.embedded.current.x + w_*h_
   -- check allignment
   if (self.embedded.current.x % streamer.align_w) ~= 0 then
      self.last_align = (math.floor(self.embedded.current.x/streamer.align_w) + 1) * streamer.align_w
                        - self.embedded.current.x
      self.embedded.current.x = (math.floor(self.embedded.current.x/streamer.align_w) + 1) * streamer.align_w
      -- and check if we did not step out of the line again
      if (self.embedded.current.x > streamer.stride_w) then
         self.embedded.current.y = self.embedded.current.y + 1
         self.embedded.current.x = 0
         self.last_align = 0
      end
   end
   return self.embedded[ #self.embedded ]
end

function Memory:allocImageData(h_, w_, data_)
   -- we assume that all the data of the same size
   -- check if current data fits in the line
   if (self.persistent.current.x + w_) > streamer.stride_w then
      self.persistent.current.x = 0
      self.persistent.current.y = self.persistent.current.y + h_
   end

   self.persistent[ #self.persistent+1 ] = {
      x = {
         offset = self.persistent.current.x,
         calc = function(self, mem)
            return mem.persistent.start.x + self.offset
         end
      },

      y = {
         offset = self.persistent.current.y,
         calc = function(self, mem)
            return mem.persistent.start.y + self.offset
         end
      },

      w        = w_,
      h        = h_,
      orig_w   = w_,
      orig_h   = h_,
      data     = data_
   }

   self.persistent.current.x = self.persistent.current.x + w_
   -- if we also assume that the width of the data cannot exceed the line,
   -- we don't need to check if we steped out of the line here
   -- check allignment
   if (self.persistent.current.x % streamer.align_w) ~= 0 then
      self.persistent.current.x = (math.floor(self.persistent.current.x/streamer.align_w) + 1)*streamer.align_w
      -- and check if we did not step out of the line again
      if (self.persistent.current.x > streamer.stride_w) then
         self.persistent.current.y = self.persistent.current.y + h_
         self.persistent.current.x = 0
      end
   end
   return self.persistent[ #self.persistent ]
end

function Memory:allocOnTheHeap_2D(h_, w_, data_, new_layer)
   -- we assume that all the data of one layer of the same size
   if (new_layer) then
      self.managed.current.y = self.managed.current.y + self.managed_prev_layer_h
      self.managed.current.x = 0
      self.managed_prev_layer_h = h_
   end
   -- check if current data fits in the line
   if (self.managed.current.x + w_) > streamer.stride_w then
      self.managed.current.x = 0
      self.managed.current.y = self.managed.current.y + h_
   end
   -- check if there is space in the mem if not start overwriting first layers
   if (self.managed.current.y + h_) > memory.size_r then
      print("<neuflow.Memory> ERROR: Overwriting the first layers of heap!")
      self.managed.current.y = 0
      self.managed.current.x = 0
   end

   self.managed[ #self.managed+1 ] = {
      x = {
         offset = self.managed.current.x,
         calc = function(self, mem)
            return mem.managed.start.x + self.offset
         end
      },

      y = {
         offset = self.managed.current.y,
         calc = function(self, mem)
            return mem.managed.start.y + self.offset
         end
      },

      w        = w_,
      h        = h_,
      orig_w   = w_,
      orig_h   = h_,
      data     = data_
   }

   self.managed.current.x = self.managed.current.x + w_
   -- we also assume that the width of the data cannot exceed the line,
   -- we don't need to check if we steped out of the line here
   -- check allignment
   if (self.managed.current.x % streamer.align_w) ~= 0 then
      self.managed.current.x = (math.floor(self.managed.current.x/streamer.align_w) + 1)*streamer.align_w
      -- and check if we did not step out of the line again
      if (self.managed.current.x > streamer.stride_w) then
         self.managed.current.y = self.managed.current.y + h_
         self.managed.current.x = 0
      end
   end
   return self.managed[#self.managed]
end

function Memory:allocOnTheHeap(h_, w_, data_)
   -- check if there is space in the mem if not start overwriting first layers
   if (self.managed.current.y + 1) > memory.size_r then
      print("<neuflow.Memory> ERROR: Overwriting the first layers of heap!")
      self.managed.current.y = 0
      self.managed.current.x = 0
   end

   -- the pointers for this entry are ready just palce the item in the memory
   self.managed[ #self.managed+1 ] = {
      x = {
         offset = self.managed.current.x,
         calc = function(self, mem)
            return mem.managed.start.x + self.offset
         end
      },

      y = {
         offset = self.managed.current.y,
         calc = function(self, mem)
            return mem.managed.start.y + self.offset
         end
      },

      w        = w_*h_,
      h        = 1,
      orig_w   = w_,
      orig_h   = h_,
      data     = data_
   }

   local length = w_*h_
   local num_of_lines = math.floor(length / streamer.stride_w)
   local last_line = length % streamer.stride_w

   --DEBUG
   --print('streamer.stride_w = '.. streamer.stride_w)
   --print('streamer.align_w = '.. streamer.align_w)

   --DEBUG
   --print('length = '.. length..' , num_of_lines = '.. num_of_lines.. ', last_line = '.. last_line)
   --print('current offset: x = '.. self.managed.current.x.. ' y = '..self.managed.current.y)

   self.managed.current.x = self.managed.current.x + last_line
   self.managed.current.y = self.managed.current.y + num_of_lines
   --DEBUG
   --print('after update offset: x = '.. self.managed.current.x.. ' y = '..self.managed.current.y)

   --  check if we did not step out of the line
   if (self.managed.current.x > streamer.stride_w) then
      self.managed.current.y = self.managed.current.y + 1
      self.managed.current.x = self.managed.current.x - streamer.stride_w
   end
   -- check allignment
   if (self.managed.current.x % streamer.align_w) ~= 0 then
      self.managed.current.x = (math.floor(self.managed.current.x/streamer.align_w) + 1)*streamer.align_w
      -- and check if we did not step out of the line again
      if (self.managed.current.x > streamer.stride_w) then
         self.managed.current.y = self.managed.current.y + 1
         self.managed.current.x = 0
      end
   end
   --DEBUG
   --print('after alignment offset: x = '.. self.managed.current.x.. ' y = '..self.managed.current.y)
   return self.managed[#self.managed]
end

function Memory:printHeap()
   print('<neuflow.Memory> allocated on the heap:')
   for i = 1,#self.managed do
      p(self.managed[i])
   end
end
