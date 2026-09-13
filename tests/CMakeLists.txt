cmake_minimum_required(VERSION 3.20)
project(SemanticTests LANGUAGES CXX)
enable_testing()

add_executable(semantic_heatmap_colors_test semantic_heatmap_colors_test.cpp)
target_compile_features(semantic_heatmap_colors_test PRIVATE cxx_std_17)
target_include_directories(semantic_heatmap_colors_test PRIVATE ../src/semantic)
add_test(NAME semantic_heatmap_colors COMMAND semantic_heatmap_colors_test)

if(APPLE)
    enable_language(OBJCXX)
    add_executable(semantic_index_test semantic_index_test.mm
        ../src/semantic/SpillableVectorIndex.mm)
    set_target_properties(semantic_index_test PROPERTIES OBJCXX_STANDARD 17)
    target_compile_options(semantic_index_test PRIVATE -fobjc-arc)
    target_include_directories(semantic_index_test PRIVATE ../src/semantic)
    target_link_libraries(semantic_index_test PRIVATE "-framework Foundation")
    add_test(NAME semantic_index COMMAND semantic_index_test)
endif()
