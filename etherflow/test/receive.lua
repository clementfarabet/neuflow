
require 'etherflow'
require 'image'

etherflow.open()

t = torch.Tensor(512,512)

for i = 1,1000 do
   print 'waiting for tensor'
   sys.tic()
   etherflow.setfirstcall(1)
   etherflow.receivetensor(t)
   print 'got tensor !'
   sys.toc(true)
   w = image.display{image=t, win=w, gui=false}
end
