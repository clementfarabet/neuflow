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
   -- args
   self.logfile = args.logfile or nil

   -- the raw data segment
   self.embedded = {}

   -- the data segment
   self.data = {}

   -- the garbage buffer (heap)
   self.buff = {}

   -- initial offsets
   self.embedded_start_x = 0
   self.embedded_start_y = 0

   self.start_data_x = 0
   self.start_data_y = 0

   self.start_buff_x = 0
   self.start_buff_y = 0

   -- x,y pointers
   self.embedded_offset_x = 0
   self.embedded_offset_y = 0

   self.data_offset_x = 0
   self.data_offset_y = 0

   self.buff_offset_x = 0
   self.buff_offset_y = 0
   self.buff_prev_layer_h = 0

   -- we want to keep this value for the
   -- final report sizes to be accurate
   self.last_align = 0
end

function Memory:adjustBytecodeSize(size_in_bytes)

   self.embedded_start_x = 0
   self.embedded_start_y =  math.ceil((size_in_bytes + 1) / streamer.stride_b)

   self.start_data_x = 0
   self.start_data_y = self.embedded_start_y + self.embedded_offset_y + 1

   self.start_buff_x = 0
   self.start_buff_y = self.start_data_y + self.data_offset_y + 1
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
   if (self.embedded_offset_x + w_*h_ + bias_:size(1)) > streamer.stride_w then
      self.embedded_offset_x = 0
      self.embedded_offset_y = self.embedded_offset_y + 1
   end

   self.embedded[ #self.embedded+1 ] = {
      x = {
         offset = self.embedded_offset_x,
         calc = function(self, mem)
            return mem.embedded_start_x + self.offset
         end
      },

      y = {
         offset = self.embedded_offset_y,
         calc = function(self, mem)
            return mem.embedded_start_y + self.offset
         end
      },

      w        = data_:size(1)*data_:size(2) + bias_:size(1),
      h        = 1,
      orig_w   = orig_w_,
      orig_h   = orig_h_,
      data     = data_,
      bias     = bias_
   }

   -- log the information
   self.logfile:write(
      string.format("kernel id = %d, x = %d, y = %d, w = %d, h = %d, data = \n",
         #self.embedded,
         self.embedded_offset_x,
         self.embedded_offset_y,
         self.embedded[ #self.embedded ].w,
         self.embedded[ #self.embedded ].h)
   )

   for i=1,h_ do
      for j=1,w_ do
         self.logfile:write(string.format("%.02f ",data_[i][j]))
      end
      self.logfile:write("\n")
   end
   self.embedded_offset_x = self.embedded_offset_x + w_*h_ + bias_:size(1)
   -- check allignment
   if (self.embedded_offset_x % streamer.align_w) ~= 0 then
      self.last_align = (math.floor(self.embedded_offset_x/streamer.align_w) + 1) * streamer.align_w
                        - self.embedded_offset_x
      self.embedded_offset_x = (math.floor(self.embedded_offset_x/streamer.align_w) + 1) * streamer.align_w
      -- and check if we did not step out of the line again
      if (self.embedded_offset_x > streamer.stride_w) then
         self.embedded_offset_y = self.embedded_offset_y + 1
         self.embedded_offset_x = 0
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
   if (self.embedded_offset_x + w_*h_) > streamer.stride_w then
       self.embedded_offset_x = 0
       self.embedded_offset_y = self.embedded_offset_y + 1
   end

   self.embedded[ #self.embedded+1 ] = {
      x = {
         offset = self.embedded_offset_x,
         calc = function(self, mem)
            return mem.embedded_start_x + self.offset
         end
      },

      y = {
         offset = self.embedded_offset_y,
         calc = function(self, mem)
            return mem.embedded_start_y + self.offset
         end
      },

      w = data_:size(1)*data_:size(2),
      h = 1,
      orig_h = orig_h_,
      orig_w = orig_w_,
      data = data_
   }

   -- log the information
   self.logfile:write(
      string.format("kernel id = %d, x = %d, y = %d, w = %d, h = %d, data = \n",
         #self.embedded,
         self.embedded_offset_x,
         self.embedded_offset_y,
         self.embedded[ #self.embedded ].w,
         self.embedded[ #self.embedded ].h)
   )

   for i=1,h_ do
      for j=1,w_ do
         self.logfile:write(string.format("%.02f ",data_[i][j]))
      end
      self.logfile:write("\n")
   end
   self.embedded_offset_x = self.embedded_offset_x + w_*h_
   -- check allignment
   if (self.embedded_offset_x % streamer.align_w) ~= 0 then
      self.last_align = (math.floor(self.embedded_offset_x/streamer.align_w) + 1) * streamer.align_w
                        - self.embedded_offset_x
      self.embedded_offset_x = (math.floor(self.embedded_offset_x/streamer.align_w) + 1) * streamer.align_w
      -- and check if we did not step out of the line again
      if (self.embedded_offset_x > streamer.stride_w) then
         self.embedded_offset_y = self.embedded_offset_y + 1
         self.embedded_offset_x = 0
         self.last_align = 0
      end
   end
   return self.embedded[ #self.embedded ]
end

function Memory:allocImageData(h_, w_, data_)
   -- we assume that all the data of the same size
   -- check if current data fits in the line
   if (self.data_offset_x + w_) > streamer.stride_w then
      self.data_offset_x = 0
      self.data_offset_y = self.data_offset_y + h_
   end

   self.data[ #self.data+1 ] = {
      x = {
         offset = self.data_offset_x,
         calc = function(self, mem)
            return mem.start_data_x + self.offset
         end
      },

      y = {
         offset = self.data_offset_y,
         calc = function(self, mem)
            return mem.start_data_y + self.offset
         end
      },

      w        = w_,
      h        = h_,
      orig_w   = w_,
      orig_h   = h_,
      data     = data_
   }

   -- log the information
   self.logfile:write(
      string.format("image id = %d, x = %d, y = %d, w = %d, h = %d, data = \n",
         #self.data,
         self.data_offset_x,
         self.data_offset_y,
         w_,
         h_)
   )

   self.data_offset_x = self.data_offset_x + w_
   -- if we also assume that the width of the data cannot exceed the line,
   -- we don't need to check if we steped out of the line here
   -- check allignment
   if (self.data_offset_x % streamer.align_w) ~= 0 then
      self.data_offset_x = (math.floor(self.data_offset_x/streamer.align_w) + 1)*streamer.align_w
      -- and check if we did not step out of the line again
      if (self.data_offset_x > streamer.stride_w) then
         self.data_offset_y = self.data_offset_y + h_
         self.data_offset_x = 0
      end
   end
   return self.data[ #self.data ]
end

function Memory:allocOnTheHeap_2D(h_, w_, data_, new_layer)
   -- we assume that all the data of one layer of the same size
   if (new_layer) then
      self.buff_offset_y = self.buff_offset_y + self.buff_prev_layer_h
      self.buff_offset_x = 0
      self.buff_prev_layer_h = h_
   end
   -- check if current data fits in the line
   if (self.buff_offset_x + w_) > streamer.stride_w then
      self.buff_offset_x = 0
      self.buff_offset_y = self.buff_offset_y + h_
   end
   -- check if there is space in the mem if not start overwriting first layers
   if (self.buff_offset_y + h_) > memory.size_r then
      print("<neuflow.Memory> ERROR: Overwriting the first layers of heap!")
      self.buff_offset_y = 0
      self.buff_offset_x = 0
   end

   self.buff[ #self.buff+1 ] = {
      x = {
         offset = self.buff_offset_x,
         calc = function(self, mem)
            return mem.start_buff_x + self.offset
         end
      },

      y = {
         offset = self.buff_offset_y,
         calc = function(self, mem)
            return mem.start_buff_y + self.offset
         end
      },

      w        = w_,
      h        = h_,
      orig_w   = w_,
      orig_h   = h_,
      data     = data_
   }

   -- log the information
   self.logfile:write(
      string.format("heap id = %d, x = %d, y = %d, w = %d, h = %d, data = \n",
         #self.buff,
         self.buff_offset_x,
         self.buff_offset_y,
         w_,
         h_)
   )

   self.buff_offset_x = self.buff_offset_x + w_
   -- we also assume that the width of the data cannot exceed the line,
   -- we don't need to check if we steped out of the line here
   -- check allignment
   if (self.buff_offset_x % streamer.align_w) ~= 0 then
      self.buff_offset_x = (math.floor(self.buff_offset_x/streamer.align_w) + 1)*streamer.align_w
      -- and check if we did not step out of the line again
      if (self.buff_offset_x > streamer.stride_w) then
         self.buff_offset_y = self.buff_offset_y + h_
         self.buff_offset_x = 0
      end
   end
   return self.buff[#self.buff]
end

function Memory:allocOnTheHeap(h_, w_, data_)
   -- check if there is space in the mem if not start overwriting first layers
   if (self.buff_offset_y + 1) > memory.size_r then
      print("<neuflow.Memory> ERROR: Overwriting the first layers of heap!")
      self.buff_offset_y = 0
      self.buff_offset_x = 0
   end

   -- the pointers for this entry are ready just palce the item in the memory
   self.buff[ #self.buff+1 ] = {
      x = {
         offset = self.buff_offset_x,
         calc = function(self, mem)
            return mem.start_buff_x + self.offset
         end
      },

      y = {
         offset = self.buff_offset_y,
         calc = function(self, mem)
            return mem.start_buff_y + self.offset
         end
      },

      w        = w_*h_,
      h        = 1,
      orig_w   = w_,
      orig_h   = h_,
      data     = data_
   }

   -- log the information
   self.logfile:write(
      string.format("heap_1D id = %d, x = %d, y = %d, w = %d, h = %d, data = \n",
         #self.buff,
         self.buff_offset_x,
         self.buff_offset_y,
         w_,
         h_)
   )

   local length = w_*h_
   local num_of_lines = math.floor(length / streamer.stride_w)
   local last_line = length % streamer.stride_w

   --DEBUG
   --print('streamer.stride_w = '.. streamer.stride_w)
   --print('streamer.align_w = '.. streamer.align_w)

   --DEBUG
   --print('length = '.. length..' , num_of_lines = '.. num_of_lines.. ', last_line = '.. last_line)
   --print('current offset: x = '.. self.buff_offset_x.. ' y = '..self.buff_offset_y)

   self.buff_offset_x = self.buff_offset_x + last_line
   self.buff_offset_y = self.buff_offset_y + num_of_lines
   --DEBUG
   --print('after update offset: x = '.. self.buff_offset_x.. ' y = '..self.buff_offset_y)

   --  check if we did not step out of the line
   if (self.buff_offset_x > streamer.stride_w) then
      self.buff_offset_y = self.buff_offset_y + 1
      self.buff_offset_x = self.buff_offset_x - streamer.stride_w
   end
   -- check allignment
   if (self.buff_offset_x % streamer.align_w) ~= 0 then
      self.buff_offset_x = (math.floor(self.buff_offset_x/streamer.align_w) + 1)*streamer.align_w
      -- and check if we did not step out of the line again
      if (self.buff_offset_x > streamer.stride_w) then
         self.buff_offset_y = self.buff_offset_y + 1
         self.buff_offset_x = 0
      end
   end
   --DEBUG
   --print('after alignment offset: x = '.. self.buff_offset_x.. ' y = '..self.buff_offset_y)
   return self.buff[#self.buff]
end

function Memory:printHeap()
   print('<neuflow.Memory> allocated on the heap:')
   for i = 1,#self.buff do
      p(self.buff[i])
   end
end
