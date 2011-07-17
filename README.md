
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
interface Torch7's neural-network package natively.

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

At this stage, Luarocks should be in your path. Now
all you have to do is:

``` sh
$ luarocks install image    # an image library for Torch7
$ luarocks install nnx      # lots of extra neural-net modules
$ luarocks install camera   # a camera interface for Linux/MacOS
$ luarocks install ffmpeg   # a video decoder for most formats
$ luarocks install neuflow  # the neuFlow toolkit
```
