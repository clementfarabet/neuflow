-- -*- lua -*-

----------------------------------------------------------------------
--- Useful abbrevs
--
kB = 1024
MB = 1024*1024
GB = 1024*1024*1024
kHz = 1000
MHz = 1000*1000
GHz = 1000*1000*1000

----------------------------------------------------------------------
--- Blast Bus parameters
--
blast_bus = {
   -- Addressing :
   area_streamer       =  1,
   area_tile           =  2,
   area_memctrl        =  3,
   area_dma            =  4,
   --                  
   addr_broadcast      = 0,
   addr_conv_0         = 1,
   addr_conv_1         = 2,
   addr_comb_0         = 16,
   addr_mapp_0         = 24,
   addr_div_0          = 28,
   addr_grid_0         = 256,
   addr_mem_streamer_0 = 1,
   addr_mem_streamer_1 = 2,
   addr_mem_streamer_2 = 3,
   addr_mem_streamer_3 = 4,
   addr_mem_streamer_4 = 5,
   addr_mem_streamer_5 = 6,
   addr_mem_streamer_6 = 7,
   addr_mem_streamer_7 = 8,
   addr_dma            = 0,
   addr_memctrl        = 0,
   -- 
   subAddr_router      =  0,
   subAddr_operator    =  1,
   subAddr_cacher      =  2,
   subAddr_IO          =  3,
   subAddr_none        =  0,
   subAddr_memTimeouts =  0,
   subAddr_memGlobals  =  1,
   subAddr_memLocals   =  2,

   -- Content:
   content_nothing     = 0,
   content_command     = 1,
   content_instruc     = 2,
   content_config      = 3,
   content_valid       = 1,

   -- Instructions
   instruc_config      = 0,
   instruc_setAdd      = 1,
   instruc_activate    = 2,
   instruc_deActivate  = 3,
   instruc_reset       = 4,
   instruc_RESERVED_1  = 5,
   instruc_control_0   = 6,
   instruc_control_1   = 7,
   instruc_control_2   = 8,
   instruc_control_3   = 9,
   instruc_control_4   = 10,
   instruc_control_5   = 11,
   instruc_control_6   = 12,
   instruc_control_7   = 13,
   instruc_cacheStart  = 14,
   instruc_cacheFinish = 15,

   -- Status
   status_notAddressed = 0,
   status_idle         = 1,
   status_busy         = 2,
   status_done         = 3,
   status_primed       = 4,
   status_unconfigured = 5,
   status_misconfigured = 6
}


----------------------------------------------------------------------
--- OpenFlower Instruction Set.
--
oFlower = {
   -- Opcodes
   op_writeConfig = 0,
   op_getStatus   = 1,
   op_writeStream = 2,
   op_routeStream = 3,
   op_writeWord   = 4,
   op_readWord    = 5,
   op_setReg      = 6,
   op_goto        = 7,
   op_add         = 8,
   op_control     = 9,
   op_and         = 10,
   op_or          = 11,
   op_comp        = 12,
   op_shr         = 13,
   op_nop         = 14,
   op_term        = 15,

   -- Register map
   reg_operation  = 0,
   reg_size       = 1,
   reg_type       = 2,
   reg_state      = 3,
   reg_counter    = 4,
   reg_loops      = 5,
   reg_status     = 6,
   reg_sys_A      = 7,
   reg_sys_B      = 8,
   reg_sys_C      = 9,
   reg_A          = 10,
   reg_B          = 11,
   reg_C          = 12,
   reg_D          = 13,
   reg_E          = 14,
   reg_F          = 15,

   -- ctrl map
   ctrl_lock_config_bus = 0,

   -- I/O Map
   io_uart        = 0,
   io_uart_status = 1,
   io_dma         = 2,
   io_dma_status  = 3,
   io_ethernet    = 4,
   io_ethernet_status = 5,
   io_iic         = 6,
   io_iic_status  = 7,
   io_spi         = 8,
   io_spi_status  = 8,
   io_gpios       = 10,
   io_timer       = 11,
   io_timer_ctrl  = 12,

   -- CPU types
   type_uint8     = 8,
   type_uint16    = 4,
   type_uint32    = 2,
   type_uint64    = 1,

   -- clock
   clock_freq     = 200*MHz,
   uart_freq      = 57600,

   -- nb of dmas (this includes instruction path)
   nb_dmas = 2
}
do
   -- Cache
   oFlower.cache_size_b    = 64*kB
   oFlower.page_size_b     = oFlower.cache_size_b/2
   oFlower.bus_            = 64
   oFlower.bus_b           = oFlower.bus_/8
end


----------------------------------------------------------------------
--- Grid parameters
--
grid = {}
do
   -- nb of grids
   grid.nb_grids = 1
   -- global IOs
   grid.nb_ios = 7
   -- conv
   grid.nb_convs = 4
   grid.kernel_width = 10
   grid.kernel_height = 10
   -- mapper
   grid.nb_mappers = 4
   grid.mapper_segs = 8
   -- generic ALUs
   grid.nb_alus = 4
   -- clock:
   grid.clock_freq = 400*MHz
end


----------------------------------------------------------------------
--- General DMAs
--
dma = {}
do
   -- global DMA IOs
   dma.nb_ios = 2
end


----------------------------------------------------------------------
--- Streamer parameters
--
-- Units:
-- _: bits
-- _b: bytes
-- _w: words (1 word = word_b bytes)
-- _r: memory rows (1 row = size_b bytes)
-- _i: integers (1 int = 4 bytes)
--
streamer = {}
do
   -- physical params
   streamer.nb_ports   = oFlower.nb_dmas + dma.nb_ios + grid.nb_ios * grid.nb_grids
   -- geometry
   streamer.mem_bus_   = 256
   streamer.mem_bus_b  = 256 / 8
   streamer.stride_b   = 2048
   streamer.word_b     = 2
   streamer.align_b    = streamer.mem_bus_ / 8
   streamer.stride_w   = streamer.stride_b / streamer.word_b
   streamer.align_w    = streamer.align_b / streamer.word_b
   -- clock
   streamer.clock_freq = 400*MHz
end


----------------------------------------------------------------------
--- Memory parameters
--
-- the parameters are expressed in different units:
-- _: bits
-- _b: bytes
-- _w: words (1 word = word_b bytes)
-- _r: memory rows (1 row = size_b bytes)
-- _i: integers (1 int = 4 bytes)
--
memory = {}
do
   -- size:
   memory.size_b      = 16*MB
   memory.size_w      = memory.size_b / streamer.word_b
   memory.size_r      = memory.size_b / streamer.stride_b
   -- clock:
   memory.clock_freq  = 400*MHz
   -- bandwidth
   memory.bus_        = 64
   memory.is_ddr      = true
   memory.is_dual     = true
   memory.bandwidth_  = memory.bus_*memory.clock_freq*((memory.is_ddr and 2) or 1)
   memory.bandwidth_b = memory.bandwidth_ / 8
   memory.bandwidth_w = memory.bandwidth_b / streamer.word_b
end


----------------------------------------------------------------------
--- Linker parameters
--
linker = {}
do
   linker.offset_text   =  0
   linker.offset_kernel =  1*MB
   linker.offset_image  =  1*MB + linker.offset_kernel
   linker.offset_heap   =  1*MB + linker.offset_image
end


----------------------------------------------------------------------
--- Extra Streamer parameters
--
do
   -- parallel streams: this is application dependent
   streamer.max_parallel_rd_streams = grid.nb_convs + 1
   streamer.max_parallel_wr_streams = 1
   streamer.max_parallel_streams = streamer.max_parallel_wr_streams+streamer.max_parallel_rd_streams
   -- bandwidth per stream:
   streamer.stream_bandwidth_b = grid.clock_freq * streamer.word_b
   streamer.grid_max_bandwidth_b = streamer.stream_bandwidth_b * streamer.max_parallel_streams
   streamer.mem_bandwidth_b = memory.bandwidth_b * 0.85 -- 0.85 is an empirical throughput factor
   -- bandwidth first check
   if streamer.mem_bandwidth_b < streamer.grid_max_bandwidth_b then
      print('ERROR <streamer> internal bandwidth too high: '
            .. streamer.grid_max_bandwidth_b/1e9 ..'GB/s'
            .. ' > external bandwidth available: '
            ..  streamer.mem_bandwidth_b/1e9 ..'GB/s')
      os.exit()
   end
   -- continous streaming per rd port:
   -- this is based on the observation that:
   -- (timeout/(dead_cycles + timeout*max_parallel_ports))*mem_bandwidth_b > stream_bandwidth_b
   local dead_cycles_rd = streamer.nb_ports - streamer.max_parallel_rd_streams
   local dead_cycles_wr = streamer.nb_ports - streamer.max_parallel_wr_streams
   streamer.min_timeout_rd = math.ceil(dead_cycles_rd /
                                       ((streamer.mem_bandwidth_b/streamer.stream_bandwidth_b)
                                     - streamer.max_parallel_streams))
   streamer.min_timeout_wr = math.ceil(dead_cycles_wr /
                                       ((streamer.mem_bandwidth_b/streamer.stream_bandwidth_b) 
                                     - streamer.max_parallel_streams))
   --print('# streamer min timeouts: wr='.. streamer.min_timeout_wr
   --      .. ' and rd=' .. streamer.min_timeout_rd)
   -- for these timeouts, we compute necessary buffers to insure no one is starving
   streamer.min_cache_rd = (math.ceil(streamer.word_b * (dead_cycles_rd 
                                                         + streamer.min_timeout_rd
                                                         *(streamer.max_parallel_streams-1))
                                   / streamer.mem_bus_b))
   streamer.min_cache_wr = (math.ceil(streamer.word_b * (dead_cycles_wr 
                                                         + streamer.min_timeout_wr
                                                         *(streamer.max_parallel_streams-1))
                                   / streamer.mem_bus_b))
   --print('# streamer min cache sizes: wr='..streamer.min_cache_wr
   --      ..' and rd='..streamer.min_cache_rd)
end


----------------------------------------------------------------------
--- Num parameters
--
num = {}
do
   num.size_b = 2
   num.size_ = 16
   num.frac_ = 8
   num.int_ = num.size_-num.frac_
   num.max = (2^(num.size_-1)-1) / 2^num.frac_
   num.min = -(2^(num.size_-1)) / 2^num.frac_
   num.one = 2^num.frac_
   num.res = 1 / 2^num.frac_
   num.precision = num.res
   num.mask = 0xFFFF
end


----------------------------------------------------------------------
--- System Banner
--
banner =
   '------------------------------------------------------------\r\n' ..
   '--     _ _  __        neuFlow [v.1.0]                     --\r\n' .. 
   '--    ( | )/_/                                            --\r\n' ..
   '-- __( >O< )         This code runs on                    --\r\n' ..
   '-- \\_\\(_|_)       the custom openFlow CPU.                --\r\n' ..
   '--                                                        --\r\n' ..
   '--   Copyright (C) 2009/10  |  Farabet/Akselrod/Martini   --\r\n' ..
   '------------------------------------------------------------'


----------------------------------------------------------------------
--- BootLoader parameters
--
bootloader = {}
do
   bootloader.entry_point_b =  oFlower.cache_size_b
   bootloader.entry_point   =  bootloader.entry_point_b / oFlower.bus_b
   bootloader.load_size     =  32*MB
end
