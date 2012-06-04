
----------------------------------------------------------------------
--- Class: Camera
--
-- This class provides a set of methods to exchange data/info with the Camera.
--
local Camera = torch.class('neuflow.Camera')

function Camera:__init(args)
   -- args:
   self.core = args.core
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

   -- compulsory
   if (self.core == nil) then
      error('<neuflow.Camera> ERROR: requires a Dataflow Core')
   end
end

function Camera:initCamera(cameraID, alloc_frames)

   local buffer_size = alloc_frames.w * alloc_frames.h

   if cameraID == 'B' then
      self.frames['B'] = alloc_frames
      print('<neuflow.Camera> : init Camera B : alloc_frame ' .. alloc_frames.w .. 'x' .. alloc_frames.h .. ' at ' .. alloc_frames.x .. ' ' .. alloc_frames.y)
   else
      self.frames['A'] = alloc_frames
      print('<neuflow.Camera> : init Camera A : alloc_frame ' .. alloc_frames.w .. 'x' .. alloc_frames.h .. ' at ' .. alloc_frames.x .. ' ' .. alloc_frames.y)
   end

   local reg_ctrl = self.core.alloc_ur:get()
   self.core:setreg(reg_ctrl, 0x00000000) -- Unset bit 16 of GPIO to 0
   self.core:iowrite(oFlower.io_gpios, reg_ctrl)
   self.core.alloc_ur:free(reg_ctrl)

   self.core:message('Camera: Init done')
end

function Camera:getLastFrame(cameraID)
   local outputs = {}

   local reg_acqst = self.core.alloc_ur:get()
   local reg_tmp = self.core.alloc_ur:get()

   local mask_status = 0x00000000
   if #cameraID == 1 then
      lcameraID = {cameraID}
   else
      lcameraID = cameraID
   end
   for i = 1,#lcameraID do
      if lcameraID[i] == 'B' then
         if (mask_status == 0x00000000) or (mask_status == self.mask.status['A']) then
            mask_status = mask_status + self.mask.status['B']
            table.insert(outputs, self.frames['B'])
         end
      else
         if (mask_status == 0x00000000) or (mask_status == self.mask.status['B']) then
            mask_status = mask_status + self.mask.status['A']
            table.insert(outputs, self.frames['A'])
         end
      end
   end
   self.core:loopUntilStart()
   self.core:ioread(oFlower.io_gpios, reg_acqst)
   self.core:bitandi(reg_acqst, mask_status, reg_tmp)
   self.core:compi(reg_tmp, 0x00000000, reg_tmp)
   self.core:loopUntilEndIfNonZero(reg_tmp)

   self.core.alloc_ur:free(reg_acqst)
   self.core.alloc_ur:free(reg_tmp)

   for i = 1,#lcameraID do
      if lcameraID[i] == 'B' then
         self.core:closePort(dma.camera_B_port_id)
      else
         self.core:closePort(dma.camera_A_port_id)
      end
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
      if lcameraID[i] == 'B' then
         if (mask_ctrl == 0x00000000) or (mask_ctrl == self.mask.ctrl['A']) then
            mask_ctrl = mask_ctrl + self.mask.ctrl['B']
            self.core:openPortWr(5, self.frames['B'])
         end
         if (mask_status == 0x00000000) or (mask_status == self.mask.status['A']) then
            mask_status = mask_status + self.mask.status['B']
         end
      else
         if (mask_ctrl == 0x00000000) or (mask_ctrl == self.mask.ctrl['B']) then
            mask_ctrl = mask_ctrl + self.mask.ctrl['A']
            self.core:openPortWr(4, self.frames['A'])
         end
         if (mask_status == 0x00000000) or (mask_status == self.mask.status['B']) then
            mask_status = mask_status + self.mask.status['A']
         end
      end
   end

   self.core:setreg(reg_ctrl, mask_ctrl) -- Set bit 11 of GPIO to 1
   self.core:iowrite(oFlower.io_gpios, reg_ctrl)

   self.core:loopUntilStart()
   self.core:ioread(oFlower.io_gpios, reg_acqst)
   self.core:bitandi(reg_acqst, mask_status, reg_tmp)
   self.core:compi(reg_tmp, mask_status, reg_tmp)
   self.core:loopUntilEndIfNonZero(reg_tmp)

   -- Once the acquisition start. Disable the acquisition for the next frame
   self.core:setreg(reg_ctrl, 0x00000000) -- Unset bit 16 of GPIO to 1
   self.core:iowrite(oFlower.io_gpios, reg_ctrl)

   self.core.alloc_ur:free(reg_acqst)
   self.core.alloc_ur:free(reg_ctrl)
   self.core.alloc_ur:free(reg_tmp)

end

function Camera:enableCameras()

   local w_ = self.w_
   local h_ = self.h_

   print('<neuflow.Camera> Enable Camera: ' .. w_ .. 'x' .. h_)
   local idx = self.core.mem:allocOnTheHeap(h_, w_, nil, true)
   local idx2 = self.core.mem:allocOnTheHeap(h_, w_, nil, true)
   self.core.mem.buff[idx].id = idx
   self.core.mem.buff[idx2].id = idx2

   self:initCamera('A',self.core.mem.buff[idx])
   self:initCamera('B',self.core.mem.buff[idx2])
end
