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
--     etherflow - a raw serial interface over gigabit ethernet,
--                 for communication between neuFlow <-> UNIX host.
--
-- history: 
--     July 16, 2011, 1:46PM - import from Torch5 - Clement Farabet
----------------------------------------------------------------------

require 'torch'
require 'libetherflow'

function etherflow.open(dev, destmac, srcmac)
   return etherflow.double.open_socket(dev, destmac, srcmac)
end

function etherflow.close(dev)
   etherflow.double.close_socket()
end

function etherflow.handshake(bool)
--   etherflow.double.handshake(bool)
end

--function etherflow.sendstring(str)
--   etherflow.double.send_frame(str)
--end

--function etherflow.receivestring()
--   return etherflow.double.receive_string()
--end

--function etherflow.receiveframe()
--   return etherflow.double.receive_frame()
--end

function etherflow.sendtensor(tensor)
   tensor.etherflow.send_tensor(tensor)
end

function etherflow.sendreset()
   return etherflow.double.send_reset()
end

function etherflow.receivetensor(tensor)
   tensor.etherflow.receive_tensor(tensor)
end

function etherflow.loadbytecode(bytetensor)
   etherflow.double.send_bytetensor(bytetensor)
end

--function etherflow.setfirstcall(val)
--   etherflow.double.set_first_call(val)
--end
