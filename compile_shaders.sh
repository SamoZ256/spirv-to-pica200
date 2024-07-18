function compileShader {
    glslang -G -Os src/test_shaders/$1.vert -o src/test_shaders/$1.spv
    spirv-dis src/test_shaders/$1.spv -o src/test_shaders/$1.spvasm
}

compileShader "simple"
compileShader "math"
compileShader "control_flow"
