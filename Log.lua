
----------------------------------------------------------------------
--- Class: Log
--
-- logs info during compilation.
--
local Log = torch.class('Log')

function Log:__init(file)
   self.logFile = assert(io.open(file, "w"))
end

function Log:write(msg)
   self.logFile:write(msg)
end

function Log:close()
   self.logFile:close()
end

