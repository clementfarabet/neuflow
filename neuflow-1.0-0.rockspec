package = "neuflow"
version = "1.0-0"

source = {
   url = "git://github.com/clementfarabet/neuflow",
   tag = "1.0-0"
}

description = {
   summary = "A compiler toolkit for the neuFlow v1 arch",
   detailed = [[
A package to generate the bytecode for and to setup a communication channel with the neuFlow v1 processor.
   ]],
   homepage = "https://github.com/clementfarabet/neuflow",
   license = "MIT/X11"
}

dependencies = {
   "torch >= 7.0",
   "xlua >= 1.0",
   "nnx >= 0.1",
   "luabitop >= 1.0.1",
}

build = {
   type = "cmake",
   variables = {
      LUAROCKS_PREFIX = "$(PREFIX)"
   }
}
