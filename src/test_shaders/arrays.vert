#version 450

#extension GL_EXT_control_flow_attributes : enable

layout (location = 0) in vec2 a_position;

layout (location = 0) uniform int index;
layout (location = 1) uniform float u[8];

void main() {
    float z = 0.0;
    // The [[unroll]] attribute is necessary to unroll the loop
    [[unroll]] for (int i = 0; i < 8; i++) {
        z += u[i];
    }
    for (float i = 0; i < 8; i++) {
        z += u[int(i) + 2];
        z += u[int(i) - 4];
        z += u[int(i) * 8];
        z += u[int(i) / 16];
    }
    z += log2(u[index]);

    for (float i = 0.0; i < 17.0f; i += 1.0f) {
        z += i;
    }

    // Dummy position
    gl_Position = vec4(a_position, z, 1.0);
}
