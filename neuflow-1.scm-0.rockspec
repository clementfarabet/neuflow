package = "neuflow"
version = "1.scm-0"

source = {
   url = "git://github.com/clementfarabet/neuflow",
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
   type = "command",
   build_command = [[
cmake -E make_directory build;
cd build;
cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$(LUA_BINDIR)/.." -DCMAKE_INSTALL_PREFIX="$(PREFIX)"; 
$(MAKE)
   ]],
   install_command = "cd build && $(MAKE) install"
}
