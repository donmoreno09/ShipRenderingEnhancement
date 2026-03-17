cmake_minimum_required(VERSION 3.16)

project(MOC_ShipRenderingEnhancement VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.8 REQUIRED COMPONENTS Quick Network Location Positioning)

qt_standard_project_setup(REQUIRES 6.8)

set(cpp_sources
    # Entities
    entities/IPersistable.h
    entities/Vessel.h

    # Networking
    networking/ApiTypes.h
    networking/HttpClient.h
    networking/HttpClient.cpp
    networking/BaseApi.h
    networking/ApiEndpoints.h
    networking/ApiEndpoints.cpp
    networking/VesselApi.h
    networking/VesselApi.cpp

    # Models
    models/VesselModel.h
    models/VesselModel.cpp
)

set(qml_files
    qml/Main.qml
    qml/MapPage.qml
)

set(asset_files
    assets/Map_pin.svg
    assets/circle-selection.svg
    assets/level-02.svg
)

qt_add_executable(MOC_ShipRenderingEnhancement main.cpp)

qt_add_qml_module(MOC_ShipRenderingEnhancement
    URI MOC_ShipRenderingEnhancement
    VERSION 1.0
    QML_FILES  ${qml_files}
    SOURCES    ${cpp_sources}
    RESOURCES  ${asset_files}
    RESOURCE_PREFIX "/"
)

target_include_directories(MOC_ShipRenderingEnhancement
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/networking
        ${CMAKE_CURRENT_SOURCE_DIR}/models
)

target_link_libraries(MOC_ShipRenderingEnhancement
    PRIVATE
        Qt6::Quick
        Qt6::Network
        Qt6::Location
        Qt6::Positioning
)

set_target_properties(MOC_ShipRenderingEnhancement PROPERTIES
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)
