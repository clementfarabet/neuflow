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
nf = neuflow.init{platform='pico_m503',
   global_msg_level = 'detailled',
   interface_msg_level = 'detailled'}
----------------------------------------------------------------------
-- ELABORATION: describe the algorithm to be run on neuFlow, and
-- how it should interact with the host (data exchange)
-- note: any copy**Host() inserted here needs to be matched by
-- a copy**Dev() in the EXEC section.
--


nf:enableCameras()
-- loop over the main code
nf:beginLoop('main') do


   -- send data to device
   nf:captureOneFrame({'B','A'})

   -- slow down for slow host computer
   --nf:wait(50)
   input_dev = nf:getLastFrame({'B','A'})

   -- get it back
   outputs = nf:copyToHost(input_dev)

   -- nf:wait(4000)

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
