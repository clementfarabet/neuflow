# neuFlow

**neuFlow** is dataflow architecture optimized for 
large array/tensor transforms, and especially image
processing operations.
More info about the architecture, 
hardware and applications can be found 
[here](http://www.neuflow.org).

## this package

This package is a compiler toolkit for neuFlow. It is 
entirely written in [Lua](http://www.lua.org/), and
relies on [Torch7](https://github.com/andresy/torch) to 
represent N-dimensional arrays efficiently. It also
interfaces Torch7's neural-network package natively.

## how to install

The easiest route to install this package is to use
[Luarocks](http://www.luarocks.org/), Lua's package
manager. 
The following instructions show you how to get
Lua + Luarocks + Torch7 quickly installed:

``` sh
$ git clone https://github.com/clementfarabet/lua4torch
$ cd lua4torch
$ make install PREFIX=/usr/local
```

At this stage, Luarocks should be in your path. Before
installing Torch7 and the neuFlow package, you will need
to install a few dependencies.

On Linux (Ubuntu):

```sh
$ apt-get install gcc g++ git libreadline5-dev cmake wget
$ apt-get install libqt4-core libqt4-gui libqt4-dev
$ apt-get install ffmpeg gnuplot
```

On Mac OS X (> 10.5): get [Homebrew](http://mxcl.github.com/homebrew/)
and then:

```sh
$ brew install git readline cmake wget
$ brew install qt
$ brew install ffmpeg gnuplot
```

Now you're ready to install Torch7, and our other packages if
wanted:

``` sh
$ luarocks install torch    # Torch7, an efficient numeric library for Lua
$ luarocks install image    # an image library for Torch7
$ luarocks install nnx      # lots of extra neural-net modules
$ luarocks install camera   # a camera interface for Linux/MacOS
$ luarocks install ffmpeg   # a video decoder for most formats
$ luarocks install neuflow  # the neuFlow toolkit
```

Alternatively, you can retrieve the source code and install it
manually:

``` sh
$ git clone https://github.com/clementfarabet/neuflow
$ cd neuflow
$ luarocks make
```

## how to run something

Demos are located in demos/. To get started, you'll need 
a standard Xilinx dev board for the Virtex 6: [the ML605 Kit]
(http://www.xilinx.com/products/devkits/EK-V6-ML605-G.htm).
We provide a version of NeuFlow that's pre synthesized/mapped/routed 
for the Virtex6 VLX240T: 
[neuFlow-ml605.bit](http://data.clement.farabet.net/share/neuFlow-ml605.bit), 
and a little script  to program the ML605 with this bitfile: 
[load-bitfile](http://data.clement.farabet.net/share/load-bitfile).

To run any of the demos, follow these instructions:

``` sh
$ git clone https://github.com/clementfarabet/neuflow
$ cd neuflow/demos

# retrieve our pre-built bitfile and the loader script:
$ wget http://data.neuflow.org/share/load-bitfile
$ wget http://data.neuflow.org/share/neuFlow-ml605.bit

# make Xilinx tools available (that implies you have them
# installed somewhere...
$ source $XILINX_INSTALL_PATH/settings**.sh

# turn on the ML605, plug the JTAG cable then load the bitfile:
$ ./load-bitfile neuFlow-ml605.bit

# run the simplest demo, a loopback client:
$ sudo qlua loopback.lua
```
