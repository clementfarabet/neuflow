
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
   -- compulsory
   if (self.core == nil) then
      error('<neuflow.Camera> ERROR: requires a Dataflow Core')
   end
end

function Camera:startCom(cameraID, alloc_frames)

   local buffer_size = alloc_frames.w * alloc_frames.h

   if cameraID == 'B' then
      self.frames[2] = alloc_frames
      print('<neuflow.Camera> : init Camera B : alloc_frame ' .. alloc_frames.w .. 'x' .. alloc_frames.h .. ' at ' .. alloc_frames.x .. ' ' .. alloc_frames.y)
   else
      self.frames[1] = alloc_frames
      print('<neuflow.Camera> : init Camera A : alloc_frame ' .. alloc_frames.w .. 'x' .. alloc_frames.h .. ' at ' .. alloc_frames.x .. ' ' .. alloc_frames.y)
   end

   local reg_ctrl = self.core.alloc_ur:get()
   self.core:setreg(reg_ctrl, 0x00000000) -- Unset bit 16 of GPIO to 1
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
	 if (mask_status == 0x00000000) or (mask_status == 0x00000004) then
   	    mask_status = mask_status + 0x00040000
	    table.insert(outputs, self.frames[2])
   	 end
      else
	 if (mask_status == 0x00000000) or (mask_status == 0x00040000) then
   	    mask_status = mask_status + 0x00000004
	    table.insert(outputs, self.frames[1])
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
	 self.core:closePort(5)
      else
	 self.core:closePort(4)
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
   	 if (mask_ctrl == 0x00000000) or (mask_ctrl == 0x00000800) then
   	    mask_ctrl = mask_ctrl + 0x08000000
   	    self.core:openPortWr(5, self.frames[2])
   	 end
   	 if (mask_status == 0x00000000) or (mask_status == 0x00000004) then
   	    mask_status = mask_status + 0x00040000
   	 end
      else
   	 if (mask_ctrl == 0x00000000) or (mask_ctrl == 0x08000000) then
   	    mask_ctrl = mask_ctrl + 0x00000800
   	    self.core:openPortWr(4, self.frames[1])
   	 end
   	 if (mask_status == 0x00000000) or (mask_status == 0x00040000) then
   	    mask_status = mask_status + 0x00000004
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
