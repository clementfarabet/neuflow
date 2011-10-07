----------------------------------------------------------------------
-- This program demonstrates the computation of a bank of filters
-- over a grayscale image. The image is grabbed from a webcam,
-- if available (and if the package 'camera' is installed as well),
-- otherwise, a fixed image (lena) is used as an input.
--
-- This script demonstrates how to describe a simple algorithm
-- using Torch7's 'nn' package, and how to compile it for neuFlow.
--

require 'image'
require 'neuflow'
require 'qt'
require 'qtwidget'

----------------------------------------------------------------------
-- INIT: initialize the neuFlow context
-- a mem manager, the dataflow core, and the compiler
--
-- platform='xilinx_ml605' or platform='pico_m503'
nf = neuflow.init{platform='pico_m503'}

----------------------------------------------------------------------
-- ELABORATION: describe the algorithm to be run on neuFlow, and 
-- how it should interact with the host (data exchange)
-- note: any copy**Host() inserted here needs to be matched by
-- a copy**Dev() in the EXEC section.
--

-- input data
inputsize = 400
input = torch.Tensor(1,inputsize,inputsize)
image.scale(image.lena()[1], input[1])

-- compute 16 9x9 random filters on the input,
-- followed by a non-linear activation unit
network = nn.Sequential()
network:add(nn.SpatialConvolution(1,16,9,9))
network:add(nn.Tanh())

-- loop over the main code
nf:beginLoop('main') do

   -- send data to device
   input_dev = nf:copyFromHost(input)

   -- compile network
   output_dev = nf:compile(network, input_dev)

   -- send result back to host
   outputs = nf:copyToHost(output_dev)

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

-- zoom
zoom = 0.5

-- try to initialize camera, or default to Lena
if xlua.require 'camera' then
   camera = image.Camera{}
end

-- process loop
function process()
   p:start('whole-loop','fps')

   if camera then
      p:start('get-camera-frame')
      local frame = camera:forward()
      image.scale(frame:narrow(1,2,1),input)
      p:lap('get-camera-frame')
   end

   nf:copyToDev(input)
   nf:copyFromDev(outputs)

   win:gbegin()
   win:showpage()

   p:start('display')
   image.display{image=outputs, win=win, min=-1, max=1, zoom=zoom}
   p:lap('display')

   p:lap('whole-loop')
   p:displayAll{painter=win, x=outputs:size(3)*4*zoom+10, y=outputs:size(2)*2*zoom+40, font=12}
   win:gend()
end

----------------------------------------------------------------------
-- GUI: setup user interface / display
--

if not win then
   win = qtwidget.newwindow(outputs:size(3)*6*zoom, outputs:size(2)*3*zoom, 'Filter Bank')
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
