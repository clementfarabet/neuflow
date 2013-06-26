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
   prog_name           = 'loopback',
   platform            ='pico_m503',
   --global_msg_level    = 'detailled',
   --interface_msg_level = 'detailled',
}

----------------------------------------------------------------------
-- ELABORATION: describe the algorithm to be run on neuFlow, and
-- how it should interact with the host (data exchange)
-- note: any copy**Host() inserted here needs to be matched by
-- a copy**Dev() in the EXEC section.
--
activeCamera = {'B','A'}
toto = nf.camera:config(activeCamera, 'iic', 'ON')
--toto = nf.camera:config(activeCamera, 'domain', 'RGB')
--toto = nf.camera:config(activeCamera, 'definition', 'QVGA')
toto = nf.camera:config(activeCamera, 'scan', 'PROGRESSIVE')
toto = nf.camera:config(activeCamera, 'color', 'B&W')
--toto = nf.camera:config(activeCamera, 'domain', 'RGB')
--toto = nf.camera:cPROGRESSIVEonfig(activeCamera, 'grab', 'ONESHOT')
--print('<neuflow.Camera> : reg ctrl ' .. toto)

--nf.camera:stopRBCameras() -- Being sure that the Camera is stopped
nf.camera.core:sleep(1)
--nf.camera:startRBCameras() -- Start camera and send images to Running Buffer
nf.camera:enableCameras(activeCamera)

-- loop over the main code
nf:beginLoop('main') do


   -- send image from camera to memory
   nf.camera:captureOneFrame(activeCamera)
   input_dev = nf.camera:getLastFrame(activeCamera)

   -- pass image to host
   outputs = nf:copyToHost(input_dev)
   --outputs = nf.camera:copyToHostLatestFrame() -- Get the latest complete frame from both camers
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
   win = qtwidget.newwindow(2000,800,'Loopback Camera Test')
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
