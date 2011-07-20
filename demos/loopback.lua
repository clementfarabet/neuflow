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
nf = neuflow.init()

----------------------------------------------------------------------
-- ELABORATION: describe the algorithm to be run on neuFlow, and 
-- how it should interact with the host (data exchange)
-- note: any copy**Host() inserted here needs to be matched by
-- a copy**Dev() in the EXEC section.
--

-- input data
inputsize = 400
input = torch.Tensor(3,inputsize,inputsize)
image.scale(image.lena(), input)

-- loop over the main code
nf:beginLoop('main') do

   -- send data to device
   input_dev = nf:copyFromHost(input)

   -- get it back
   outputs = nf:copyToHost(input_dev)

end nf:endLoop('main')

----------------------------------------------------------------------
-- LOAD: load the bytecode on the device, and execute it
--
nf:loadBytecode()

----------------------------------------------------------------------
-- EXEC: this part executes the host code, and interacts with the dev
--

-- profiler
p = nf.profiler

-- process loop
function process()
   p:start('whole-loop','fps')

   nf:copyToDev(input)
   nf:copyFromDev(outputs)

   p:start('compute-error')
   error = outputs:clone():add(-1,input):abs()
   p:lap('compute-error')
   
   win:gbegin()
   win:showpage()

   p:start('display')
   image.display{image=input, win=win, x=0, min=0, max=1}
   image.display{image=outputs, win=win, x=input:size(3), min=0, max=1}
   image.display{image=error, win=win, x=input:size(3)*2, min=0, max=1}
   p:lap('display')

   p:lap('whole-loop')
   p:displayAll{painter=win, x=10, y=input:size(2)+20, font=12}
   win:gend()
end

----------------------------------------------------------------------
-- GUI: setup user interface / display
--

if not win then
   win = qtwidget.newwindow(1200,540,'Loopback Test')
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
