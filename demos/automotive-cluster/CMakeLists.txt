qt_add_executable(automotive-cluster
  main.cpp
)

target_link_libraries(automotive-cluster PRIVATE Qt6::Widgets)

install(TARGETS automotive-cluster
  RUNTIME DESTINATION /opt/var-scope-demos/bin
)

install(FILES manifest.json
  DESTINATION /opt/var-scope-demos/manifests
)
