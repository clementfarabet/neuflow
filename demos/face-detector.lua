#!/usr/bin/env torch
----------------------------------------------------------------------
-- This program demonstrates the computation of a bank of filters
-- over a grayscale image. The image is grabbed from a webcam,
-- if available (and if the package 'camera' is installed as well),
-- otherwise, a fixed image (lena) is used as an input.
--
-- This script demonstrates how to describe a simple algorithm
-- using Torch7's 'nn' package, and how to compile it for neuFlow.
--

require 'neuflow'
require 'qt'
require 'qtwidget'
require 'xlua'
xrequire('inline',true)
xrequire('nnx',true)
xrequire('camera',true)
xrequire('image',true)

----------------------------------------------------------------------
-- ARGS: parse user arguments
--
op = xlua.OptionParser('%prog [options]')
op:option{'-c', '--camera', action='store', dest='camidx',
          help='if source=camera, you can specify the camera index: /dev/videoIDX', 
          default=0}
op:option{'-n', '--network', action='store', dest='network', 
          help='path to existing [trained] network',
          default='face-detector/face.net'}
opt,args = op:parse()

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

-- load pre-trained network from disk
network = torch.load(opt.network)
network_fov = 32
network_sub = 4
softnorm = network.modules[1]
hardnet = nn.Sequential()
for i = 2,#network.modules do
   hardnet:add(network.modules[i])
end
network = hardnet

-- process input at multiple scales
scales = {0.3, 0.24, 0.192, 0.15, 0.12, 0.1}

-- use a pyramid packer/unpacker
require 'face-detector/PyramidPacker'
require 'face-detector/PyramidUnPacker'
packer = nn.PyramidPacker(network, scales)
unpacker = nn.PyramidUnPacker(network)

-- blob parser
parse = require 'face-detector/blobParser'

-- a gaussian for smoothing the distributions
gaussian = image.gaussian(3,0.15)

-- generate input data for compiler
frameRGB = torch.Tensor(3,480,640)
frameY = image.rgb2y(frameRGB)
input = packer:forward(frameY)

-- loop over the main code
nf:beginLoop('main') do

   -- send data to device
   input_dev = nf:copyFromHost(input)

   -- compile network
   output_dev = nf:compile(network, input_dev)

   -- send result back to host
   outputs = nf:copyToHost(output_dev)

end nf:endLoop('main')

-- package hardware network
nf.forward = function(nf,input)
                local normed = softnorm:forward(input)
                nf:copyToDev(normed)
                nf:copyFromDev(outputs)
                return outputs
             end

----------------------------------------------------------------------
-- LOAD: load the bytecode on the device, and execute it
--
nf:sendReset()
nf:loadBytecode()

----------------------------------------------------------------------
-- EXEC: this part executes the host code, and interacts with the dev
--

-- camera
camera = image.Camera{}

-- profiler
p = nf.profiler

-- zoom
zoom = 0.5

-- process loop
function process()
   p:start('whole-loop','fps')

   -- (1) grab frame
   p:start('get-camera-frame')
   frameRGB = camera:forward()
   frameRGB = image.scale(frameRGB, 640, 480)
   p:lap('get-camera-frame')

   -- (2) transform it into Y space
   p:start('RGB->Y')
   frameY = image.rgb2y(frameRGB)
   p:lap('RGB->Y')

   -- (3) create multiscale pyramid
   p:start('pack-pyramid')
   pyramid, coordinates = packer:forward(frameY)
   p:lap('pack-pyramid')

   -- (4) run pre-trained network on it
   p:start('network-inference')
   result = nf:forward(pyramid)
   p:lap('network-inference')

   -- (5) unpack pyramid
   p:start('unpack-pyramid')
   distributions = unpacker:forward(result, coordinates)
   p:lap('unpack-pyramid')

   -- (6) parse distributions to extract blob centroids
   p:start('parse-distributions')
   threshold = 0.9
   rawresults = {}
   for i,distribution in ipairs(distributions) do
      local smoothed = image.convolve(distribution[1]:add(1):mul(0.5), gaussian)
      parse(smoothed, threshold, rawresults, scales[i])
   end
   p:lap('parse-distributions')

   -- (7) clean up results
   p:start('clean-up')
   detections = {}
   for i,res in ipairs(rawresults) do
      local scale = res[3]
      local x = res[1]*network_sub/scale
      local y = res[2]*network_sub/scale
      local w = network_fov/scale
      local h = network_fov/scale
      detections[i] = {x=x, y=y, w=w, h=h}
   end
   p:lap('clean-up')
end

-- display loop
function display()
   win:gbegin()
   win:showpage()
   -- (1) display input image + pyramid
   image.display{image=frameRGB, win=win}

   -- (2) overlay bounding boxes for each detection
   for i,detect in ipairs(detections) do
      win:setcolor(1,0,0)
      win:rectangle(detect.x, detect.y, detect.w, detect.h)
      win:stroke()
      win:setfont(qt.QFont{serif=false,italic=false,size=16})
      win:moveto(detect.x, detect.y-1)
      win:show('face')
   end

   -- (3) display distributions
   local prevx = 0
   for i,distribution in ipairs(distributions) do
      local prev = distributions[i-1]
      if prev then prevx = prevx + prev:size(3) end
      image.display{image=distribution[1], win=win, x=prevx, min=0, max=1}
   end

   p:lap('whole-loop')
   p:displayAll{painter=win, x=5, y=distributions[1]:size(2)+20, font=12}
   win:gend()
end

----------------------------------------------------------------------
-- GUI: setup user interface / display
--

if not win then
   win = qtwidget.newwindow(frameRGB:size(3), frameRGB:size(2), 'Face Detection')
end

timer = qt.QTimer()
timer.interval = 10
timer.singleShot = true
qt.connect(timer,
           'timeout()',
           function()
              process()
              display()
              collectgarbage()
              timer:start()
           end)
timer:start()
