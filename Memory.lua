
----------------------------------------------------------------------
--- Class: Memory
--
-- This class is used to allocate memory correctly with all the constraints preserved.
-- The class contains 3 tabels with pointers to obejts stored in the memory
-- one table is for raw_data segment (kernels)
-- another is for data segment (images),
-- and another one is for garbage buffer (intermediate results, outputs).
-- The class is used only to generate offsets, the acctual data writing is done in the
-- ByteCode class.
-- Offsets are in pixels!!! when writing to file need to adjust to bytes (mult by pixel value)
-- One line has 1024 pixels = 2048 bytes = 512 integers.
--
local Memory = torch.class('Memory')

function Memory:__init(args)
   -- args
   self.logfile = args.logfile or nil

   -- the raw data segment
   self.raw_data = {}
   -- the data segment

   self.data = {}

   -- the garbage buffer (heap)
   self.buff = {}

   -- id pointers
   self.raw_datap = 1 
   self.datap = 1 
   self.buffp = 1 

   -- parse args
   linker.offset_kernel = args.kernel_offset or linker.offset_kernel
   linker.offset_image = args.image_offset or linker.offset_image
   linker.offset_heap = args.heap_offset or linker.offset_heap

   -- initial offsets
   self.start_raw_data_x = 0
   self.start_raw_data_y = linker.offset_kernel / streamer.stride_b
   
   self.start_data_x = 0
   self.start_data_y = linker.offset_image / streamer.stride_b
   
   self.start_buff_x = 0
   self.start_buff_y = linker.offset_heap / streamer.stride_b
   self.buff_prev_layer_h = 0
   
   -- x,y pointers
   self.raw_data_offset_x = self.start_raw_data_x
   self.raw_data_offset_y = self.start_raw_data_y
   
   self.data_offset_x = self.start_data_x
   self.data_offset_y = self.start_data_y
   
   self.buff_offset_x = self.start_buff_x
   self.buff_offset_y = self.start_buff_y
   self.buff_prev_layer_h = 0


   -- we want to keep this value for the
   -- final report sizes to be accurate
   self.last_align = 0

   -- segment indicators
   self.seg_raw_data = 0
   self.seg_data = 1
   self.seg_buff = 2
end

function Memory:allocKernel(h_, w_, data_, bias_)
   orig_h_ = data_:size(2)
   orig_w_ = data_:size(1)
   -- transpose kernel to go to inner dim last
   data_ = data_:t()
   if((data_:size(2) < grid.kernel_width) or (data_:size(1) < grid.kernel_height)) then
      data_ker_size = lab.zeros(grid.kernel_height, grid.kernel_width)
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
   if (self.raw_data_offset_x + w_*h_ + bias_:size(1)) > streamer.stride_w then
      self.raw_data_offset_x = 0
      self.raw_data_offset_y = self.raw_data_offset_y + 1
   end
   self.raw_data[self.raw_datap] = {x = self.raw_data_offset_x, 
				    y = self.raw_data_offset_y, 
				    w = data_:size(1)*data_:size(2) + bias_:size(1),
                                    orig_h = orig_h_,
                                    orig_w = orig_w_,
				    h = 1,
				    data = data_,
                                    bias = bias_}
   -- log the information
   self.logfile:write(string.format("kernel id = %d, x = %d, y = %d, w = %d, h = %d, data = \n", 
                                    self.raw_datap, self.raw_data_offset_x, 
                                    self.raw_data_offset_y, self.raw_data[self.raw_datap].w, 
                                    self.raw_data[self.raw_datap].h))
   for i=1,h_ do
      for j=1,w_ do 
         self.logfile:write(string.format("%.02f ",data_[i][j]))
      end
      self.logfile:write("\n")
   end
   -- update pointers 
   self.raw_datap = self.raw_datap + 1
   self.raw_data_offset_x = self.raw_data_offset_x + w_*h_ + bias_:size(1)
   -- check allignment
   if (self.raw_data_offset_x % streamer.align_w) ~= 0 then
      self.last_align = (math.floor(self.raw_data_offset_x/streamer.align_w) + 1) * streamer.align_w
                        - self.raw_data_offset_x
      self.raw_data_offset_x = (math.floor(self.raw_data_offset_x/streamer.align_w) + 1) * streamer.align_w
      -- and check if we did not step out of the line again
      if (self.raw_data_offset_x > streamer.stride_w) then
         self.raw_data_offset_y = self.raw_data_offset_y + 1
         self.raw_data_offset_x = 0
	 self.last_align = 0
      end
   end
   return self.raw_datap - 1
end

function Memory:allocRawData(h_, w_, data_)
   orig_h_ = data_:size(2)
   orig_w_ = data_:size(1)
   -- transpose kernel to go to inner dim last
   data_ = data_:t()
   if((data_:size(2) < grid.kernel_width) or (data_:size(1) < grid.kernel_height)) then
      data_ker_size = lab.zeros(grid.kernel_height, grid.kernel_width)
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
   if (self.raw_data_offset_x + w_*h_) > streamer.stride_w then
   	 self.raw_data_offset_x = 0
   	 self.raw_data_offset_y = self.raw_data_offset_y + 1
   end
   self.raw_data[self.raw_datap] = {x = self.raw_data_offset_x, 
				    y = self.raw_data_offset_y, 
				    w = data_:size(1)*data_:size(2),
                                    orig_h = orig_h_,
                                    orig_w = orig_w_,
				    h = 1,
				    data = data_}
   -- log the information
   self.logfile:write(string.format("kernel id = %d, x = %d, y = %d, w = %d, h = %d, data = \n", 
                                    self.raw_datap, self.raw_data_offset_x, 
                                    self.raw_data_offset_y, self.raw_data[self.raw_datap].w, 
                                    self.raw_data[self.raw_datap].h))
   for i=1,h_ do
      for j=1,w_ do 
         self.logfile:write(string.format("%.02f ",data_[i][j]))
      end
      self.logfile:write("\n")
   end
   -- update pointers 
   self.raw_datap = self.raw_datap + 1
   self.raw_data_offset_x = self.raw_data_offset_x + w_*h_
   -- check allignment
   if (self.raw_data_offset_x % streamer.align_w) ~= 0 then
      self.last_align = (math.floor(self.raw_data_offset_x/streamer.align_w) + 1) * streamer.align_w
                        - self.raw_data_offset_x  
      self.raw_data_offset_x = (math.floor(self.raw_data_offset_x/streamer.align_w) + 1) * streamer.align_w
      -- and check if we did not step out of the line again
      if (self.raw_data_offset_x > streamer.stride_w) then
          self.raw_data_offset_y = self.raw_data_offset_y + 1
          self.raw_data_offset_x = 0
	 self.last_align = 0
      end
   end
   return self.raw_datap - 1
end

function Memory:allocImageData(h_, w_, data_)
   -- we assume that all the data of the same size
   -- check if current data fits in the line
   if (self.data_offset_x + w_) > streamer.stride_w then
      self.data_offset_x = 0
      self.data_offset_y = self.data_offset_y + h_
   end
   self.data[self.datap] = {x = self.data_offset_x, y = self.data_offset_y, 
                            w = w_, h = h_, 
                            orig_w = w_, orig_h = h_, 
			    data = data_}
   -- log the information
   self.logfile:write(string.format("image id = %d, x = %d, y = %d, w = %d, h = %d, data = \n",
                                    self.datap, self.data_offset_x, self.data_offset_y, w_, h_))
   -- update pointers 
   self.datap = self.datap + 1
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
   return self.datap - 1
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
      print("##########WARNING: Overwriting the first layers of heap!")
      self.buff_offset_y = self.start_buff_y
      self.buff_offset_x = self.start_buff_x
   end
   self.buff[self.buffp] = {x = self.buff_offset_x, 
			    y = self.buff_offset_y, 
			    w = w_, 
			    h = h_, 
			    orig_w = w_,
			    orig_h = h_,
			    data = data_}
   -- log the information
   self.logfile:write(string.format("heap id = %d, x = %d, y = %d, w = %d, h = %d, data = \n", 
                                    self.buffp, self.buff_offset_x, self.buff_offset_y, w_, h_))
   -- update pointers 
   self.buffp = self.buffp + 1
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
   return self.buffp - 1
end


function Memory:allocOnTheHeap(h_, w_, data_)
   -- check if there is space in the mem if not start overwriting first layers
   if (self.buff_offset_y + 1) > memory.size_r then
      print("##########WARNING: Overwriting the first layers of heap!")
      self.buff_offset_y = self.start_buff_y
      self.buff_offset_x = self.start_buff_x
   end

   -- the pointers for this entry are ready just palce the item in the memory
   self.buff[self.buffp] = {x = self.buff_offset_x,
			    y = self.buff_offset_y,
			    w = w_*h_, 
			    h = 1,
			    orig_w = w_,
			    orig_h = h_,
			    data = data_}
   -- log the information
   self.logfile:write(string.format("heap_1D id = %d, x = %d, y = %d, w = %d, h = %d, data = \n", 
                                    self.buffp, self.buff_offset_x, self.buff_offset_y, w_, h_))
   
   -- update pointers (for the next entry) 
   self.buffp = self.buffp + 1

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
   return self.buffp - 1
end

function Memory:printHeap()
   print('# allocated on the heap:')
   for i = 1,#self.buff do
      p(self.buff[i])
   end
end
