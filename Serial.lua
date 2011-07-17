--------------------------------------------------------------------------------
-- Serial
-- a class to read/write through serial port
--------------------------------------------------------------------------------

require 'torch'

do
   ----------------------------------------------------------------------
   -- register class + constructor
   --
   local Serial = torch.class('Serial')

   function Serial:__init(dev,baud)
      -- error messages
      self.WARNING_NOTFOUND = '# serial: warning, device ' .. dev .. ' not found'

      -- device + speed
      self.dev = dev or '/dev/tty'
      self.baud = baud or 57600

      -- dev exists ?
      if not paths.filep(self.dev) then
         print(self.WARNING_NOTFOUND)
         return
      end

      -- this is linux dependent ?
      local ret = sys.execute('stty -F ' .. self.dev .. ' ' .. self.baud .. ' min 0 time 1')

      -- dev exists ?
      if ret ~= '' then
         print(self.WARNING_NOTFOUND)
         return
      end

      -- file descriptors
      self.devr = io.open(dev, 'r')
      self.devw = io.open(dev, 'w')

      -- background reader
      require 'thread'
      local function dumpTTY ()
         local c = sys.COLORS
         local highlight = c._cyan
         local none = c.none
         while true do
            local fromTTY = self:read()
            if fromTTY then print(fromTTY) end
         end
      end
      thread.newthread(dumpTTY, {})
   end

   function Serial:cleanup()
      self.dev:close()
   end

   function Serial:read()
      return self.devr:read('*l')
   end

   function Serial:write(line)
      return self.devw:write(line)
   end
end
