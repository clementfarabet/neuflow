#!/usr/bin/env torch
----------------------------------------------------------------------
-- A simple program for neuFlow: receive images from embedded camera
-- of m503 board
-- them back from neuFlow, in a loop.
--
-- If this script works, it validates:
--  (1) the ethernet interface
--  (2) the embedded openFlow CPU
--  (3) the streamer
--  (4) the DDR2/3 interface
--  (5) the cameras capture and configuration

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
activeCamera = {'A','B'}
nf.camera:config(activeCamera, 'iic', 'ON')
nf.camera:config(activeCamera, 'scan', 'PROGRESSIVE')

--nf.camera:startRBCameras() -- Start camera and send images to Running Buffer
nf.camera:enableCameras(activeCamera)

-- loop over the main code
nf:beginLoop('main') do

   --outputs = nf.camera:copyToHostLatestFrame() -- Get the latest complete frame from both camers

   -- send image from camera to memory
   nf.camera:captureOneFrame(activeCamera)
   --nf.camera:captureOneFrame('B')
   input_dev = nf.camera:getLastFrame(activeCamera)
   --input_dev = nf.camera:getLastFrame('B')

   -- pass image to host
   outputs = nf:copyToHost(input_dev)
   --nf.camera.core:sleep(0.15)

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
   p:start('whole-loop','fps')
   --end

   nf:copyFromDev(outputs)

   p:start('display')
   win:gbegin()
   win:showpage()
   image.display{image=outputs, win=win, x=0, min=0, max=1}
   p:lap('display')
   p:lap('whole-loop')
   p:displayAll{painter=win, x=10, y=500, font=12}
   win:gend()
   --end
   framecnt = framecnt + 1
end

----------------------------------------------------------------------
-- GUI: setup user interface / display
--

torch.setdefaulttensortype('torch.FloatTensor')

if not win then
   win = qtwidget.newwindow(1280,530,'Loopback Camera Test')
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
