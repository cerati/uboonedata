# Wire-Cell Data files, required at runtime.

FILE(GLOB data *.jsonnet )

message(STATUS "Data files ${data}")

#install(FILES ${data} DESTINATION #${product}/${version}/WireCellData/pgrapher/common/sim)

install_wp(LIST ${data} SUBDIRNAME pgrapher/common/sim)
