# SPIR-V to PICA200 assembly compiler

This project aims to support the use of modern shading languages on Nintendo 3DS by compiling SPIR-V shaders to PICA200 assembly. The PICA200 instruction set is a bit more limited than SPIR-V, so not all shaders will be supported. The compiler will try to convert as much as possible, but some shaders may need to be modified to work on the 3DS.

## Usage

Simply run `zig build run -- /path/to/input.vert -o /path/to/output.shbin`. This requires that you have [picasso](https://github.com/devkitPro/picasso/tree/master) installed and in your path. If you don't have it installed or want to output assembly instead of a shader binary, you can use the `-S` flag (`zig build run -- -S /path/to/input.vert -o /path/to/output.v.pica`).

## Mapping of inputs and outputs

The translator currently supports only the OpenGL dialect of SPIR-V. In practice, this means just that you should declare you uniforms as `layout (location = X) uniform T uniformName;` instead of Vulkan's uniform blocks `layout (set = X, binding = Y) uniform BlockName { ... } uniformName;`. The rest of the shader should be pretty much the same.

| SPIR-V | PICA200 |
|--------|---------|
| inputs | v0-v15 |
| outputs | see the table bellow |
| uniforms | uniformX, where X is the location qualifier |

### Output mapping

| Location | PICA200 name |
|----------|--------------|
| 0 | normalquat |
| 1 | color |
| 2 | texcoord0 |
| 3 | texcoord0w |
| 4 | texcoord1 |
| 5 | texcoord2 |
| 6 | texcoord |
| 7 | texcoord |

See the [picasso manual](https://github.com/devkitPro/picasso/blob/master/Manual.md) for additional clarification. `gl_Position` is mapped to `position`.

## Example

GLSL:
```glsl
#version 450

layout (location = 0) in vec2 a_position;

layout (location = 2) out vec2 v_texCoord;

layout (location = 1) uniform vec2 texCoordOffset;

void main() {
    gl_Position = vec4(a_position, 0.0, 1.0);
    v_texCoord = (a_position * 0.5 + 0.5) + texCoordOffset;
}
```

SPIR-V disassembly (`glslc --target-env=opengl -O /path/to/file.vert -o /path/to/file.spv` and `spirv-dis /path/to/file.spv`):
```c
; SPIR-V
; Version: 1.0
; Generator: Google Shaderc over Glslang; 10
; Bound: 42
; Schema: 0
               OpCapability Shader
          %1 = OpExtInstImport "GLSL.std.450"
               OpMemoryModel Logical GLSL450
               OpEntryPoint Vertex %4 "main" %13 %18 %28 %gl_VertexID %gl_InstanceID
               OpMemberDecorate %_struct_11 0 BuiltIn Position
               OpMemberDecorate %_struct_11 1 BuiltIn PointSize
               OpMemberDecorate %_struct_11 2 BuiltIn ClipDistance
               OpMemberDecorate %_struct_11 3 BuiltIn CullDistance
               OpDecorate %_struct_11 Block
               OpDecorate %18 Location 0
               OpDecorate %28 Location 2
               OpDecorate %35 Location 1
               OpDecorate %gl_VertexID BuiltIn VertexId
               OpDecorate %gl_InstanceID BuiltIn InstanceId
       %void = OpTypeVoid
          %3 = OpTypeFunction %void
      %float = OpTypeFloat 32
    %v4float = OpTypeVector %float 4
       %uint = OpTypeInt 32 0
     %uint_1 = OpConstant %uint 1
%_arr_float_uint_1 = OpTypeArray %float %uint_1
 %_struct_11 = OpTypeStruct %v4float %float %_arr_float_uint_1 %_arr_float_uint_1
%_ptr_Output__struct_11 = OpTypePointer Output %_struct_11
         %13 = OpVariable %_ptr_Output__struct_11 Output
        %int = OpTypeInt 32 1
      %int_0 = OpConstant %int 0
    %v2float = OpTypeVector %float 2
%_ptr_Input_v2float = OpTypePointer Input %v2float
         %18 = OpVariable %_ptr_Input_v2float Input
    %float_0 = OpConstant %float 0
    %float_1 = OpConstant %float 1
%_ptr_Output_v4float = OpTypePointer Output %v4float
%_ptr_Output_v2float = OpTypePointer Output %v2float
         %28 = OpVariable %_ptr_Output_v2float Output
  %float_0_5 = OpConstant %float 0.5
%_ptr_UniformConstant_v2float = OpTypePointer UniformConstant %v2float
         %35 = OpVariable %_ptr_UniformConstant_v2float UniformConstant
%_ptr_Input_int = OpTypePointer Input %int
%gl_VertexID = OpVariable %_ptr_Input_int Input
%gl_InstanceID = OpVariable %_ptr_Input_int Input
         %41 = OpConstantComposite %v2float %float_0_5 %float_0_5
          %4 = OpFunction %void None %3
          %5 = OpLabel
         %19 = OpLoad %v2float %18
         %22 = OpCompositeExtract %float %19 0
         %23 = OpCompositeExtract %float %19 1
         %24 = OpCompositeConstruct %v4float %22 %23 %float_0 %float_1
         %26 = OpAccessChain %_ptr_Output_v4float %13 %int_0
               OpStore %26 %24
         %31 = OpVectorTimesScalar %v2float %19 %float_0_5
         %33 = OpFAdd %v2float %31 %41
         %36 = OpLoad %v2float %35
         %37 = OpFAdd %v2float %33 %36
               OpStore %28 %37
               OpReturn
               OpFunctionEnd
```

PICA200 assembly:
```c
.fvec uniform1

.constf zeros(0.0, 0.0, 0.0, 0.0)
.constf ones(1.0, 1.0, 1.0, 1.0)
.constf const20(0e0, 0e0, 0e0, 0e0)
.constf const21(1e0, 1e0, 1e0, 1e0)
.constf const30(5e-1, 5e-1, 5e-1, 5e-1)
.constf const41(5e-1, 5e-1, 0e0, 0e0)

.out outpos position
.out outtexcoord0 texcoord0

.proc main
label5:
    mov r0.x, v0.x
    mov r0.y, v0.y
    mov r0.z, const20.x
    mov r0.w, const21.x
    mov outpos, r0
    mul r1.xy, const30.x, v0.xy
    add r2.xy, const41.xy, r1.xy
    add r3.xy, uniform1.xy, r2.xy
    mov outtexcoord0.xy, r3.xy
.end
```

## Unsupported features

| Feature | Reason |
|---------|--------|
| Fragment shaders | Not supported by PICA200 |
| Geometry shaders | Not implemented |
| double | Not supported by PICA200 |
| Arrays as function variables | Will be supported by "unfolding" into multiple registers. Uniform arrays are already supported |
| Textures, samplers and images | Not supported by PICA200 |
| Point size, clip distance and cull distance | Not supported by PICA200 |

### Integer limitations

PICA200 doesn't support integer arithmetic the way SPIR-V handles it. It is supported onlt when indexing into and array. While this may seem like a really big limitation, integers don't have much more use cases than that. Though one common use case are for loops, and the limitation can be worked around in 2 ways:

1. Forcing the loop to unroll

This is probably the best solution, as loop unrolling generally leads to better performance. The `[[unroll]]` attribute is used to make sure the loop gets unrolled.

```glsl
[[unroll]] for (int i = 0; i < 8; i++) {
    a += myArray[i + 1];
}
```

2. Using a float loop counter

When working with larger for loops, it may be a better idea to use a float loop counter to keep the code size smaller. The counter can then be casted to an integer when accessing the array.

```glsl
for (float i = 0.0; i < 8.0; i += 1.0) {
    a += myArray[int(i) + 1];
}
```

Notice that `1` is added to the index before accessing the array, which demonstrates integer arithmetic.

## License

Distributed under the MIT License. See `LICENSE.txt` for more information.
