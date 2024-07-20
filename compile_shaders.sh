function compileShader {
    glslc --target-env=opengl -O src/test_shaders/$1.vert -o src/test_shaders/$1.spv
    #spirv-opt -O --loop-unroll src/test_shaders/$1.unoptimized.spv -o src/test_shaders/$1.spv
    spirv-dis src/test_shaders/$1.spv -o src/test_shaders/$1.spvasm
}

compileShader "simple"
compileShader "math"
compileShader "control_flow"
compileShader "arrays"
compileShader "std"
