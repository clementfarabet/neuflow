
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
   local outputs

   outputs = {self.frames[1],self.frames[2]}

   return outputs
end

function Camera:waitForNewFrame(cameraID)
   -- Read and store the current frame_count

   local reg_frid1 = self.core.alloc_ur:get()
   local reg_frid1B = self.core.alloc_ur:get()
   local reg_frid2 = self.core.alloc_ur:get()
   local reg_temp = self.core.alloc_ur:get()

   self.core:ioread(oFlower.io_gpios, reg_frid1)
   self.core:bitandi(reg_frid1, 0x00030000, reg_frid1B)
   self.core:bitandi(reg_frid1, 0x00000003, reg_frid1)


   self.core:message('WaitA')
   self.core:loopUntilStart()
   self.core:ioread(oFlower.io_gpios, reg_frid2)
   self.core:bitandi(reg_frid2, 0x00000003, reg_frid2)
   self.core:comp(reg_frid1, reg_frid2, reg_temp)
   self.core:loopUntilEndIfZero(reg_temp)
   self.core:message('WaitB')
   self.core:loopUntilStart()
   self.core:ioread(oFlower.io_gpios, reg_frid2)
   self.core:bitandi(reg_frid2, 0x00030000, reg_frid2)
   self.core:comp(reg_frid1B, reg_frid2, reg_temp)
   self.core:loopUntilEndIfZero(reg_temp)

   self.core.alloc_ur:free(reg_frid1)
   self.core.alloc_ur:free(reg_frid1B)
   self.core.alloc_ur:free(reg_frid2)
   self.core.alloc_ur:free(reg_temp)

end


function Camera:captureOneFrame(cameraID)
   local outputs = {}
   local reg_frcntA = self.core.alloc_ur:get()
   local reg_frcntB = self.core.alloc_ur:get()
   local reg_ctrl = self.core.alloc_ur:get()
   local reg_acqst = self.core.alloc_ur:get()
   local reg_tmp = self.core.alloc_ur:get()

   -- Enable camera acquisition
   self.core:openPortWr(4, self.frames[1])
   self.core:openPortWr(5, self.frames[2])


   self.core:ioread(oFlower.io_gpios, reg_tmp)
   self.core:bitandi(reg_tmp, 0x00030000, reg_frcntB)
   self.core:bitandi(reg_tmp, 0x00000003, reg_frcntA)

   self.core:setreg(reg_ctrl, 0x08000800) -- Set bit 11 of GPIO to 1
   self.core:iowrite(oFlower.io_gpios, reg_ctrl)

   self.core:loopUntilStart()
   self.core:ioread(oFlower.io_gpios, reg_acqst)
   self.core:bitandi(reg_acqst, 0x00040004, reg_tmp)
   self.core:compi(reg_tmp, 0x00040004, reg_tmp)
   self.core:loopUntilEndIfNonZero(reg_tmp)

   -- Once the acquisition start. Disable the acquisition for the next frame
   self.core:setreg(reg_ctrl, 0x00000000) -- Unset bit 16 of GPIO to 1
   self.core:iowrite(oFlower.io_gpios, reg_ctrl)

   self.core:ioread(oFlower.io_gpios, reg_frcnt)
   self.core:message('->')
   self.core:printReg(reg_frcnt)
   self.core:message('<-')

   self.core:message('WaitA')
   self.core:loopUntilStart()
   self.core:ioread(oFlower.io_gpios, reg_tmp)
   self.core:bitandi(reg_tmp, 0x00000003, reg_tmp)
   self.core:comp(reg_tmp, reg_frcntA, reg_tmp)
   self.core:loopUntilEndIfZero(reg_tmp)
   self.core:message('WaitB')
   self.core:loopUntilStart()
   self.core:ioread(oFlower.io_gpios, reg_tmp)
   self.core:bitandi(reg_tmp, 0x00030000, reg_tmp)
   self.core:comp(reg_tmp, reg_frcntB, reg_tmp)
   self.core:loopUntilEndIfZero(reg_tmp)

   self.core.alloc_ur:free(reg_frcntA)
   self.core.alloc_ur:free(reg_frcntB)
   self.core.alloc_ur:free(reg_acqst)
   self.core.alloc_ur:free(reg_ctrl)
   self.core.alloc_ur:free(reg_tmp)

   --self:waitForNewFrame(cameraID)

   self.core:closePort(4)
   self.core:closePort(5)

   outputs = self:getLastFrame(cameraID)

   return outputs
end
