
package = "neuflow"
version = "1.0-1"

source = {
   url = "neuflow-1.0-1.tgz"
}

description = {
   summary = "A compiler toolkit for the neuFlow arch.",
   detailed = [[
            A compiler toolkit for the neuFlow arch.
   ]],
   homepage = "http://www.neuflow.org",
   license = "MIT/X11"
}

dependencies = {
   "lua >= 5.1",
   "torch",
   "luabitop",
   "nnx",
   "xlua",
   "image"
}

build = {
   type = "cmake",

   cmake = [[
         cmake_minimum_required(VERSION 2.8)

         set (CMAKE_MODULE_PATH ${PROJECT_SOURCE_DIR})

         # infer path for Torch7
         string (REGEX REPLACE "(.*)lib/luarocks/rocks.*" "\\1" TORCH_PREFIX "${CMAKE_INSTALL_PREFIX}" )
         message (STATUS "Found Torch7, installed in: " ${TORCH_PREFIX})

         find_package (Torch REQUIRED)

         set (CMAKE_INSTALL_RPATH_USE_LINK_PATH TRUE)

         add_subdirectory (etherflow)

         install_files(/lua/neuflow init.lua)
         install_files(/lua/neuflow tools.lua)
         install_files(/lua/neuflow defines.lua)
         install_files(/lua/neuflow defines_ibm_asic.lua)
         install_files(/lua/neuflow defines_xilinx_ml605.lua)
         install_files(/lua/neuflow defines_pico_m503.lua)
         install_files(/lua/neuflow tools.lua)
         install_files(/lua/neuflow rom.lua)
         install_files(/lua/neuflow Log.lua)
         install_files(/lua/neuflow Memory.lua)
         install_files(/lua/neuflow Compiler.lua)
         install_files(/lua/neuflow Interface.lua)
         install_files(/lua/neuflow Core.lua)
         install_files(/lua/neuflow CoreUser.lua)
         install_files(/lua/neuflow Linker.lua)
         install_files(/lua/neuflow NeuFlow.lua)
         install_files(/lua/neuflow Serial.lua)
         install_files(/lua/neuflow init.lua)
         install_files(/lua/neuflow segments/*)
   ]],

   variables = {
      CMAKE_INSTALL_PREFIX = "$(PREFIX)"
   }
}
