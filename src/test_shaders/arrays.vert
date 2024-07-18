#version 450

#extension GL_EXT_control_flow_attributes : enable

layout (location = 0) in vec2 a_position;

const int N = 8;

layout (location = 0) uniform float u[N];

void main() {
    float z = 0.0;
    // The [[unroll]] attribute is necessary to unroll the loop
    [[unroll]] for (int i = 0; i < N; i++) {
        z += u[i];
    }

    // Dummy position
    gl_Position = vec4(a_position, z, 1.0);
}
