
IF (APPLE)
    SET (CMAKE_C_FLAGS "-D_APPLE_=1")
ELSE (APPLE)
    SET (CMAKE_C_FLAGS "-D_LINUX_=1")
ENDIF (APPLE)

INCLUDE_DIRECTORIES (${PROJECT_SOURCE_DIR}/etherflow)
SET(src init.c)
SET(luasrc init.lua)
ADD_TORCH_PACKAGE(etherflow "${src}" "${luasrc}" "neuFlow")
TARGET_LINK_LIBRARIES(etherflow luaT TH)
