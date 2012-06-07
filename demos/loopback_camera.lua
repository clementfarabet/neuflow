#!/usr/bin/env torch
----------------------------------------------------------------------
-- A simple loopback program for neuFlow: send images and receive
-- them back from neuFlow, in a loop.
--
-- If this script works, it validates:
--  (1) the ethernet interface
--  (2) the embedded openFlow CPU
--  (3) the streamer
--  (4) the DDR2/3 interface
--

require 'image'
require 'neuflow'
require 'qt'
require 'qtwidget'

----------------------------------------------------------------------
-- INIT: initialize the neuFlow context
-- a mem manager, the dataflow core, and the compiler
--
nf = neuflow.init {
   platform='pico_m503',
   global_msg_level = 'detailled',
   interface_msg_level = 'detailled',
   offset_data_1D = bootloader.entry_point_b + 6*MB,
   offset_data_2D = bootloader.entry_point_b + 7*MB
}

----------------------------------------------------------------------
-- ELABORATION: describe the algorithm to be run on neuFlow, and
-- how it should interact with the host (data exchange)
-- note: any copy**Host() inserted here needs to be matched by
-- a copy**Dev() in the EXEC section.
--


nf.camera:startRBCameras() -- Start camera and send images to Running Buffer
--nf.camera:enableCameras()

-- loop over the main code
nf:beginLoop('main') do

   outputs = nf.camera:copyToHostLatestFrame() -- Get the latest complete frame from both camers

--[[
   -- send image from camera to memory
   nf.camera:captureOneFrame({'B','A'})
   input_dev = nf.camera:getLastFrame({'B','A'})

   -- pass image to host
   outputs = nf:copyToHost(input_dev)
--]]

end nf:endLoop('main')

----------------------------------------------------------------------
-- LOAD: load the bytecode on the device, and execute it
--
nf:sendReset()
nf:loadBytecode()

----------------------------------------------------------------------
-- EXEC: this part executes the host code, and interacts with the dev
--

-- profiler
p = nf.profiler

local framecnt = 0
-- process loop
function process()
   --if framecnt % 2 == 0 then
   p:start('whole-loop','fps')
   --end
   nf:copyFromDev(outputs)

   --if framecnt % 2 == 0 then
   p:start('display')
   win:gbegin()
   win:showpage()
   image.display{image=outputs, win=win, x=0, min=0, max=1}
   p:lap('display')
   p:lap('whole-loop')
   p:displayAll{painter=win, x=10, y=300, font=12}
   win:gend()
   --end
   framecnt = framecnt + 1
end

----------------------------------------------------------------------
-- GUI: setup user interface / display
--

torch.setdefaulttensortype('torch.FloatTensor')

if not win then
   win = qtwidget.newwindow(1300,480,'Loopback Camera Test')
end

timer = qt.QTimer()
timer.interval = 10
timer.singleShot = true
qt.connect(timer,
           'timeout()',
           function()
              process()
              collectgarbage()
              timer:start()
           end)
timer:start()
