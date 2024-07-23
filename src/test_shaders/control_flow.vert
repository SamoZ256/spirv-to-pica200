#version 450

layout (location = 0) in vec2 a_position;

layout (location = 0) uniform float u_seed1;
layout (location = 1) uniform float u_seed2;

void main() {
    float z = 0.0;
    if (u_seed1 > 0.0) {
        z = 1.0;
    } else {
        z = -1.0;
    }

    if (u_seed2 == 70.0) {
        z = 0.0;
    } else {
        z += u_seed2 / 100.0;
        z *= 77.09;
    }

    // Dummy position
    gl_Position = vec4(a_position, z, 1.0);
}
