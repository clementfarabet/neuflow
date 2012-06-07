
----------------------------------------------------------------------
--- Class: Camera
--
-- This class provides a set of methods to exchange data/info with the Camera.
--
local Camera = torch.class('neuflow.Camera')

function Camera:__init(args)
   -- args:
   self.nf = args.nf
   self.core = args.nf.core
   self.msg_level = args.msg_level or 'none'  -- 'detailled' or 'none' or 'concise'
   self.frames = {}

   self.nb_frames = 4 -- number of frames in running buffer
   self.w_ = 640
   self.h_ = 240
   self.mask = {
      ['counter'] = {['A'] = 0x00000003, ['B'] = 0x00030000},
      ['status']  = {['A'] = 0x00000004, ['B'] = 0x00040000},
      ['ctrl']    = {['A'] = 0x00000800, ['B'] = 0x08000000}
   }

   self.port_addrs = {
      ['A'] = dma.camera_A_port_id,
      ['B'] = dma.camera_B_port_id
   }

   -- compulsory
   if (self.core == nil) then
      error('<neuflow.Camera> ERROR: requires a Dataflow Core')
   end
end

function Camera:initCamera(cameraID, alloc_frames)

   self.frames[cameraID] = alloc_frames
   print('<neuflow.Camera> : init Camera ' ..
         cameraID .. ' : alloc_frame ' ..
         alloc_frames.w .. 'x' ..
         alloc_frames.h .. ' at ' ..
         alloc_frames.x .. ' ' ..
         alloc_frames.y)

   -- puts the cameras in standby
   local reg_ctrl = self.core.alloc_ur:get()
   self.core:setreg(reg_ctrl, 0x00000000) -- Unset bit 16 of GPIO to 0
   self.core:iowrite(oFlower.io_gpios, reg_ctrl)
   self.core.alloc_ur:free(reg_ctrl)

   self.core:message('Camera: Init done')
end

function Camera:getLastFrame(cameraID)
   local outputs = {}

   if #cameraID == 1 then
      lcameraID = {cameraID}
   else
      lcameraID = cameraID
   end

   for i = 1,#lcameraID do
      table.insert(outputs, self.frames[lcameraID[i]])

      self.core:closePortSafe(self.port_addrs[lcameraID[i]])
   end
   return outputs
end

function Camera:captureOneFrame(cameraID)

   local reg_ctrl = self.core.alloc_ur:get()
   local reg_acqst = self.core.alloc_ur:get()
   local reg_tmp = self.core.alloc_ur:get()

   local mask_ctrl = 0x00000000
   local mask_status = 0x00000000

   -- Enable camera acquisition
   if #cameraID == 1 then
      lcameraID = {cameraID}
   else
      lcameraID = cameraID
   end

   for i = 1,#lcameraID do
      mask_ctrl = bit.bor(mask_ctrl, self.mask.ctrl[lcameraID[i]])
      self.core:openPortWr(self.port_addrs[lcameraID[i]], self.frames[lcameraID[i]])

      mask_status = bit.bor(mask_status, self.mask.status[lcameraID[i]])
   end

   -- trigger acquisition
   self.core:setreg(reg_ctrl, mask_ctrl)
   self.core:iowrite(oFlower.io_gpios, reg_ctrl)

   -- loop until acquisition has started
   self.core:loopUntilStart()
   self.core:ioread(oFlower.io_gpios, reg_acqst)
   self.core:bitandi(reg_acqst, mask_status, reg_tmp)
   self.core:compi(reg_tmp, mask_status, reg_tmp)
   self.core:loopUntilEndIfNonZero(reg_tmp)

   -- Once the acquisition start. Disable the acquisition for the next frame
   self.core:setreg(reg_ctrl, 0x00000000)
   self.core:iowrite(oFlower.io_gpios, reg_ctrl)

   self.core.alloc_ur:free(reg_acqst)
   self.core.alloc_ur:free(reg_ctrl)
   self.core.alloc_ur:free(reg_tmp)
end

function Camera:enableCameras()

   print('<neuflow.Camera> Enable Camera: ' .. self.w_ .. 'x' .. self.h_)
   local idx_A = self.core.mem:allocImageData(self.h_, self.w_, nil)
   local idx_B = self.core.mem:allocImageData(self.h_, self.w_, nil)

   self:initCamera('A', self.core.mem.data[idx_A])
   self:initCamera('B', self.core.mem.data[idx_B])
end

function Camera:startRBCameras() -- Start camera and send images to Running Buffer

   local buff_h_ = self.h_ * self.nb_frames

   print('<neuflow.Camera> Enable Camera: ' .. self.w_ .. 'x' .. self.h_)
   local idx_A = self.core.mem:allocImageData(buff_h_, self.w_, nil)
   local idx_B = self.core.mem:allocImageData(buff_h_, self.w_, nil)

   self:initCamera('A', self.core.mem.data[idx_A])
   self:initCamera('B', self.core.mem.data[idx_B])

   -- Global setup for DMA port (camera A and B) to make continuous
   local stride_bit_shift = math.log(1024) / math.log(2)

   self.core:send_selectModule(blast_bus.area_streamer, blast_bus.addr_mem_streamer_0+dma.camera_A_port_id, 1)
   self.core:send_setup(0, 16*1024*1024, stride_bit_shift, 1)

   self.core:send_selectModule(blast_bus.area_streamer, blast_bus.addr_mem_streamer_0+dma.camera_B_port_id, 1)
   self.core:send_setup(0, 16*1024*1024, stride_bit_shift, 1)

   -- Open the streamer ports for writing
   self.core:openPortWr(dma.camera_A_port_id, self.frames['A'])
   self.core:openPortWr(dma.camera_B_port_id, self.frames['B'])

   -- Start cameras sending images
   local reg_ctrl = self.core.alloc_ur:get()
   local mask_ctrl = bit.bor(self.mask.ctrl['A'], self.mask.ctrl['B'])

   -- trigger acquisition
   self.core:setreg(reg_ctrl, mask_ctrl)
   self.core:iowrite(oFlower.io_gpios, reg_ctrl)

   self.core.alloc_ur:free(reg_ctrl)
end

function Camera:stopRBCameras() -- Stop camera sending to Running Buffer

   local reg_acqst = self.core.alloc_ur:get()
   local mask_status = bit.bor(self.mask.status['A'], self.mask.status['B'])

   -- Once the acquisition start. Disable the acquisition for the next frame
   self.core:setreg(reg_acqst, 0x00000000) -- Unset bit 16 of GPIO to 1
   self.core:iowrite(oFlower.io_gpios, reg_acqst)
   self.core:nop(100) -- small delay

   -- wait for the frame to finish being sent
   self.core:loopUntilStart()
   self.core:ioread(oFlower.io_gpios, reg_acqst)
   self.core:bitandi(reg_acqst, mask_status, reg_acqst)
   self.core:compi(reg_acqst, 0x00000000, reg_acqst)
   self.core:loopUntilEndIfNonZero(reg_acqst)

   self.core.alloc_ur:free(reg_acqst)

   -- reset ports setup
   self.core:configureStreamer(0, 16*1024*1024, 1024, {dma.camera_A_port_id, dma.camera_B_port_id})
end

function Camera:getLatestFrame() -- Get the latest complete frame

   local reg_acqst = self.core.alloc_ur:get()
   self.core:ioread(oFlower.io_gpios, reg_acqst)

   self:streamLatestFrameFromPort('A', reg_acqst, dma.ethernet_read_port_id, 'full')
   self.nf.ethernet:streamFromHost(self.nf.ethernet.ack_stream[1], 'ack_stream')
   self:streamLatestFrameFromPort('B', reg_acqst, dma.ethernet_read_port_id, 'full')

   self.core.alloc_ur:free(reg_acqst)

   return torch.Tensor(2, self.h_, self.w_)
end

function Camera:streamLatestFrameFromPort(cameraID, reg_acqst, port_addr, port_addr_range)

   local goto_ends = {}
   local reg_count = self.core.alloc_ur:get()

   for ii = (self.nb_frames-1), 1, -1 do
      -- copy camera status into reg but masked for frame count
      self.core:bitandi(reg_acqst, self.mask.counter[cameraID], reg_count)
      self.core:compi(reg_count, ii, reg_count) -- test if current frame is 'ii'

      -- if current frame not eq to 'ii' (reg_count == 0) goto next possible option
      self.core:gotoTagIfZero(nil, reg_count) -- goto next pos
      local goto_next = self.core.linker:getLastReference()

      -- read the last frame in running buffer
      self.core:configPort{
         index  = port_addr,
         action = 'fetch+read+sync+close',
         data   = {
            x = self.frames[cameraID].x,
            y = self.frames[cameraID].y + ((ii-1)*self.h_),
            w = self.w_,
            h = self.h_
         },

         range  = port_addr_range
      }

      self.core:gotoTag(nil) -- finish so goto end
      goto_ends[ii] = self.core.linker:getLastReference()

      -- next pos
      goto_next.goto_tag = self.core:makeGotoTag()
      self.core:nop()
   end

   -- if got here only option left is to read the following frame
   self.core:configPort {
      index  = port_addr,
      action = 'fetch+read+sync+close',
      data   = {
         x = self.frames[cameraID].x,
         y = self.frames[cameraID].y + ((self.nb_frames-1)*self.h_),
         w = self.w_,
         h = self.h_
      },

      range  = port_addr_range
   }

   -- end point
   local goto_end_tag = self.core:makeGotoTag()
   self.core:nop()

   for i, goto_end in pairs(goto_ends) do
      goto_end.goto_tag = goto_end_tag
   end

   self.core.alloc_ur:free(reg_count)
end
