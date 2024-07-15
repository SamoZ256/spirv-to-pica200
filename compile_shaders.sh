# TODO: abstract this
glslang -G src/test_shaders/simple.vert -o src/test_shaders/simple.spv
spirv-dis src/test_shaders/simple.spv -o src/test_shaders/simple.spvasm
