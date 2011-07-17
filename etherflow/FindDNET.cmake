###################################################################
#  $Id$
#
#  Copyright (c) 2009 Aaron Turner, <aturner at synfin dot net>
#  All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# * Redistributions of source code must retain the above copyright
#   notice, this list of conditions and the following disclaimer.
#
# * Redistributions in binary form must reproduce the above copyright
#   notice, this list of conditions and the following disclaimer in
#   the documentation and/or other materials provided with the
#   distribution.
#
# * Neither the name of the Aaron Turner nor the names of its
#   contributors may be used to endorse or promote products derived
#   from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
# FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
# COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
# BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
# ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#
###################################################################
# - Find libdnet
# Find the libdnet includes and library
# http://libdnet.sourceforge.net/
#
# The environment variable DNETDIR allows to specify where to find
# libdnet in non standard location.
# 
#  DNET_INCLUDE_DIRS - where to find dnet.h, etc.
#  DNET_LIBRARIES   - List of libraries when using libdnet.
#  DNET_FOUND       - True if libdnet found.
	
IF(EXISTS $ENV{DNETDIR})
  FIND_PATH(DNET_INCLUDE_DIR
    NAMES
    dnet/dnet.h
    dnet.h
    /usr/local/include/dnet.h
    PATHS
    $ENV{DNETDIR}
    NO_DEFAULT_PATH
    )
  
  FIND_LIBRARY(DNET_LIBRARY
    NAMES
    /usr/local/lib/
    dnet
    PATHS
    $ENV{DNETDIR}
    NO_DEFAULT_PATH
    )
  
  
ELSE(EXISTS $ENV{DNETDIR})
  FIND_PATH(DNET_INCLUDE_DIR
    NAMES
    dnet/dnet.h
    dnet.h
    /usr/local/include/dnet.h
    )
  
  FIND_LIBRARY(DNET_LIBRARY
    NAMES
    /usr/local/lib/
    dnet
    )
	 
ENDIF(EXISTS $ENV{DNETDIR})
	
SET(DNET_INCLUDE_DIRS ${DNET_INCLUDE_DIR})
SET(DNET_LIBRARIES ${DNET_LIBRARY})


IF(DNET_INCLUDE_DIRS)
  MESSAGE(STATUS "Dnet include dirs set to ${DNET_INCLUDE_DIRS}")
ELSE(DNET_INCLUDE_DIRS)
  MESSAGE(STATUS "Dnet include dirs cannot be found")
ENDIF(DNET_INCLUDE_DIRS)

IF(DNET_LIBRARIES)
  MESSAGE(STATUS "Dnet library set to ${DNET_LIBRARIES}")
ELSE(DNET_LIBRARIES)
  MESSAGE(STATUS "Dnet library cannot be found")
ENDIF(DNET_LIBRARIES)

#Is dnet found ?
IF(DNET_INCLUDE_DIRS AND DNET_LIBRARIES)
  SET( DNET_FOUND "YES" )
ENDIF(DNET_INCLUDE_DIRS AND DNET_LIBRARIES)
	
	
MARK_AS_ADVANCED(
  DNET_LIBRARIES
  DNET_INCLUDE_DIRS
  )