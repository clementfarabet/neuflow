----------------------------------------------------------------------
--
-- Copyright (c) 2010,2011 Clement Farabet, Polina Akselrod
--
-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the
-- "Software"), to deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to
-- the following conditions:
--
-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
-- NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
-- LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
-- OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
-- WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
--
----------------------------------------------------------------------
-- description:
--     ethertbsp - a raw Ethernet packet interface over gigabit ethernet,
--                 for communication between neuFlow <-> UNIX host.
--
-- history:
--     July 16, 2011, 1:46PM - import from Torch5 - Clement Farabet
--     Wed 25 Apr 2012 22:53:06 EDT - Berin Martini
----------------------------------------------------------------------

require 'torch'
require 'libethertbsp'

function ethertbsp.open(dev, destmac, srcmac)
   return ethertbsp.double.open_socket(dev, destmac, srcmac)
end

function ethertbsp.close(dev)
   ethertbsp.double.close_socket()
end

function ethertbsp.sendreset()
   return ethertbsp.double.send_reset()
end

function ethertbsp.sendtensor(tensor)
   tensor.ethertbsp.send_tensor(tensor)
end

function ethertbsp.receivetensor(tensor)
   tensor.ethertbsp.receive_tensor(tensor)
end

function ethertbsp.loadbytecode(bytetensor)
   ethertbsp.double.send_bytetensor(bytetensor)
end
