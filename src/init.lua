----------------------------------------------------------------------
--
-- Copyright (c) 2010,2011 Clement Farabet, Polina Akselrod, Berin Martini
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
--     neuflow - a compiler toolkit + communication for neuFlow.
--
-- history:
--     July 16, 2011, 1:51PM - import from Torch5 - Clement Farabet
----------------------------------------------------------------------

-- dependencies
require 'xlua'
require 'os'
require 'torch'
require 'nnx'
require 'bit'

-- main table
neuflow = {}

-- load all submodules
torch.include('neuflow', 'defines.lua')
torch.include('neuflow', 'tools.lua')
torch.include('neuflow', 'rom.lua')
torch.include('neuflow', 'Profiler.lua')
torch.include('neuflow', 'Log.lua')
torch.include('neuflow', 'Memory.lua')
torch.include('neuflow', 'Compiler.lua')
torch.include('neuflow', 'Interface.lua')
torch.include('neuflow', 'DmaInterface.lua')
torch.include('neuflow', 'Core.lua')
torch.include('neuflow', 'CoreUser.lua')
torch.include('neuflow', 'Linker.lua')
torch.include('neuflow', 'LinkerExtensions.lua')
torch.include('neuflow', 'Serial.lua')
torch.include('neuflow', 'NeuFlow.lua')

-- shortcut for user interface:
neuflow.init = neuflow.NeuFlow

-- create a path in home dir to store things
-- like coefficients for example
neuflow.coefpath = os.getenv('HOME')..'/.neuflow/coefs'
os.execute('mkdir -p ' .. neuflow.coefpath)
os.execute('chmod a+rw ' .. neuflow.coefpath)

-- migrate all the coefficients
os.execute('cp ' ..  sys.concat(sys.fpath(), 'coef_*') .. ' ' .. neuflow.coefpath)
os.execute('chmod a+rw ' .. neuflow.coefpath .. '/*')

-- return table
return neuflow
