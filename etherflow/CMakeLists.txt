
if (APPLE)
    set (CMAKE_C_FLAGS "-D_APPLE_=1")
else (APPLE)
    set (CMAKE_C_FLAGS "-D_LINUX_=1")
endif (APPLE)

include_directories (${PROJECT_SOURCE_DIR}/etherflow ${TORCH_INCLUDE_DIR})
link_directories (${TORCH_LIBRARY_DIR})
add_library (etherflow SHARED init.c)
target_link_libraries (etherflow ${TORCH_LIBRARIES} ${PCAP_LIBRARIES} ${DNET_LIBRARIES})
install_files(/lua/etherflow init.lua)
install_targets(/lib etherflow)
