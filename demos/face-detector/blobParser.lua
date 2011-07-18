
require 'inline'

local parse = inline.load [[
      // get args
      const void* id = luaT_checktypename2id(L, "torch.DoubleTensor");
      THDoubleTensor *tensor = luaT_checkudata(L, 1, id);
      double threshold = lua_tonumber(L, 2);
      int table_blobs = 3;
      int idx = lua_objlen(L, 3) + 1;
      double scale = lua_tonumber(L, 4);

      // loop over pixels
      int x,y;
      for (y=0; y<tensor->size[0]; y++) {
         for (x=0; x<tensor->size[1]; x++) {
            double val = THDoubleTensor_get2d(tensor, y, x);
            if (val > threshold) {
               // entry = {}
               lua_newtable(L);
               int entry = lua_gettop(L);

               // entry[1] = x
               lua_pushnumber(L, x);
               lua_rawseti(L, entry, 1);

               // entry[2] = y
               lua_pushnumber(L, y);
               lua_rawseti(L, entry, 2);

               // entry[3] = scale
               lua_pushnumber(L, scale);
               lua_rawseti(L, entry, 3);

               // blobs[idx] = entry; idx = idx + 1
               lua_rawseti(L, table_blobs, idx++);
            }
         }
      }
      return 0;
]]

return parse
