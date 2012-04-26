
require 'ethertbsp'
require 'image'

ethertbsp.open()

t = torch.Tensor(512,512)

for i = 1,1000 do
   print 'waiting for tensor'
   sys.tic()
   ethertbsp.receivetensor(t)
   print 'got tensor !'
   sys.toc(true)
   w = image.display{image=t, win=w, gui=false}
end
