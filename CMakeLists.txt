cmake_minimum_required(VERSION 3.16)

option(TARGET_ARM64 "Compilation croisée Linux ARM64 (clang + sysroot)" OFF)

if (TARGET_ARM64)
    set(CMAKE_SYSTEM_NAME Linux)
    set(CMAKE_SYSTEM_PROCESSOR aarch64)

    set(SYSROOT $ENV{HOME}/sysroot-aarch64)
    set(GCC_DIR ${SYSROOT}/usr/lib/gcc/aarch64-redhat-linux/11)

    set(CMAKE_SYSROOT ${SYSROOT})
    set(CMAKE_C_COMPILER clang)
    set(CMAKE_CXX_COMPILER clang++)
    set(CMAKE_C_COMPILER_TARGET aarch64-linux-gnu)
    set(CMAKE_CXX_COMPILER_TARGET aarch64-linux-gnu)

    set(CMAKE_C_FLAGS_INIT   "--gcc-install-dir=${GCC_DIR}")
    set(CMAKE_CXX_FLAGS_INIT "--gcc-install-dir=${GCC_DIR}")
    set(CMAKE_EXE_LINKER_FLAGS_INIT    "-fuse-ld=lld")
    set(CMAKE_SHARED_LINKER_FLAGS_INIT "-fuse-ld=lld")

    set(CMAKE_FIND_ROOT_PATH ${SYSROOT})
    set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
    set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
    set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
    set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
endif()

project(StuAuth
    VERSION 4.1.1
    LANGUAGES CXX
)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTOUIC ON)
set(CMAKE_AUTORCC ON)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# -------------------------
# Version appli (unique)
# -------------------------
set(APP_VERSION "4.1.1")
set(APP_AUTHOR "Rona")
set(APP_SUMMARY "A Local TOTP/HOTP authenticator. No cloud, no sync, no tracking.")
string(REPLACE "." "," APP_VERSION_COMMA "${APP_VERSION}")
add_definitions(-DAPP_VERSION="${APP_VERSION}")

# ------------------------- 
# Génération du fichier RC 
# ------------------------- 
if (WIN32) 
    string(REPLACE "\\" "/" CMAKE_SOURCE_DIR_FIXED "${CMAKE_SOURCE_DIR}")
    configure_file( 
        ${CMAKE_SOURCE_DIR}/app.rc.in 
        ${CMAKE_BINARY_DIR}/app.rc 
        @ONLY 
    ) 
    # Copie l'icône dans le build dir pour que le .rc la trouve
    configure_file(
        ${CMAKE_SOURCE_DIR}/resources/Icone.ico
        ${CMAKE_BINARY_DIR}/resources/Icone.ico
        COPYONLY
    )
endif()

# -------------------------
# OpenSSL
# -------------------------
if(WIN32)
    set(OPENSSL_USE_STATIC_LIBS TRUE)
endif()
find_package(OpenSSL REQUIRED)
if (WIN32)
    add_definitions(-DOPENSSL_USE_STATIC_LIBS)
endif()

# -------------------------
# Qt Widgets (statique)
# -------------------------
find_package(Qt6 REQUIRED COMPONENTS Widgets Network)

# -------------------------
# ZXing local
# -------------------------
set(ZXING_READERS ON CACHE BOOL "" FORCE)
set(ZXING_WRITERS ON CACHE BOOL "" FORCE)
set(ZXING_EXAMPLES OFF CACHE BOOL "" FORCE)
set(ZXING_TESTS OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(BUILD_BLACKBOX_TESTS OFF CACHE BOOL "" FORCE)
set(BUILD_UNIT_TESTS OFF CACHE BOOL "" FORCE)

add_subdirectory(src/thirdparty/zxing)

# -------------------------
# Sources / Headers
# -------------------------
file(GLOB_RECURSE SOURCES
    "${CMAKE_SOURCE_DIR}/src/commun/*.cpp"
    "${CMAKE_SOURCE_DIR}/src/commun/security/*.cpp"
    "${CMAKE_SOURCE_DIR}/src/ui/*.cpp"
    "${CMAKE_SOURCE_DIR}/src/core/*.cpp"
    "${CMAKE_SOURCE_DIR}/src/network/*.cpp"
)

file(GLOB_RECURSE HEADERS
    "${CMAKE_SOURCE_DIR}/src/commun/*.h"
    "${CMAKE_SOURCE_DIR}/src/commun/security/*.h"
    "${CMAKE_SOURCE_DIR}/src/ui/*.h"
    "${CMAKE_SOURCE_DIR}/src/core/*.h"
    "${CMAKE_SOURCE_DIR}/src/network/*.h"
)

# -------------------------
# Exécutable
# -------------------------
qt_add_executable(${PROJECT_NAME}
    src/main.cpp
    ${SOURCES}
    ${HEADERS}
)

# -------------------------
# Copie Asset
# -------------------------
add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        ${CMAKE_SOURCE_DIR}/resources
        $<TARGET_FILE_DIR:${PROJECT_NAME}>/resources
)

# -------------------------
# Ressources Qt (Windows + Linux)
# -------------------------
qt_add_resources(${PROJECT_NAME} "app_resources"
    PREFIX "/"
    FILES
        resources/Icone.png
        resources/translations/stuauth_fr.qm
        resources/translations/stuauth_en.qm
        resources/translations/stuauth_bz.qm
        resources/translations/stuauth_ja.qm
)

# -------------------------
# Ressources Windows (.rc)
# -------------------------
if (WIN32)
    # Force le compilateur de ressources
    set_source_files_properties(${CMAKE_BINARY_DIR}/app.rc
        PROPERTIES
            LANGUAGE RC
    )
    target_sources(${PROJECT_NAME} PRIVATE app.rc "src/commun/security/LockManager.cpp" "src/commun/security/LockManager.h")
    set_target_properties(${PROJECT_NAME}
        PROPERTIES
            WIN32_EXECUTABLE TRUE
    )
endif()

# -------------------------
# Includes
# -------------------------
target_include_directories(${PROJECT_NAME}
    PRIVATE
        
)

# -------------------------
# Link
# -------------------------
target_link_libraries(${PROJECT_NAME}
    PRIVATE
        Qt6::Widgets
        Qt6::Network
        OpenSSL::SSL
        OpenSSL::Crypto
        ZXing::ZXing
        
)

# -------------------------
# Link Windows
# -------------------------
if (WIN32)
    target_link_libraries(${PROJECT_NAME}
        PRIVATE
            ws2_32
            advapi32
            crypt32
    )
endif()

# -------------------------
# Link Linux
# -------------------------
if (UNIX AND NOT APPLE)
    target_link_libraries(${PROJECT_NAME} 
        PRIVATE 
        
    )
endif()