
set (CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${PROJECT_SOURCE_DIR}/etherflow)

find_package (PCAP)

if (PCAP_FOUND)

    if (APPLE)

        find_package (DNET)

        if (DNET_FOUND)

            set (CMAKE_C_COMPILER "gcc-4.0")
            set (CMAKE_C_FLAGS "-arch x86_64")

            include_directories (${PROJECT_SOURCE_DIR}/etherflow ${PCAP_INCLUDE_DIRS} ${DNET_INCLUDE_DIRS} ${TORCH_INCLUDE_DIR})
            link_directories (${TORCH_LIBRARY_DIR})
            add_library (etherflow SHARED init.c)
            target_link_libraries (etherflow ${TORCH_LIBRARIES} ${PCAP_LIBRARIES} ${DNET_LIBRARIES})
            install_files(/lua/etherflow init.lua)
            install_targets(/lib etherflow)

        else (DNET_FOUND)

            message ("WARNING: Could not find LibDNET, etherflow [ethernet driver for neuFlow] will not be installed")

        endif (DNET_FOUND)

    else (APPLE)

         include_directories (${PROJECT_SOURCE_DIR}/etherflow ${PCAP_INCLUDE_DIRS} ${TORCH_INCLUDE_DIR})
         link_directories (${TORCH_LIBRARY_DIR})
         set (CMAKE_C_FLAGS "-D_LINUX_=1")
         add_library (etherflow SHARED init.c)
         target_link_libraries (etherflow ${TORCH_LIBRARIES} ${PCAP_LIBRARIES} ${DNET_LIBRARIES})
         install_files(/lua/etherflow init.lua)
         install_targets(/lib etherflow)

    endif (APPLE)

else (PCAP_FOUND)

    message ("WARNING: Could not find LibPCAP, etherflow [ethernet driver for neuFlow] will not be installed")

endif (PCAP_FOUND) 
