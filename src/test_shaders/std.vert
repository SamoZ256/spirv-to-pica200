#version 450

layout (location = 0) in vec2 a_position;

layout (location = 0) uniform float u_seed1;
layout (location = 1) uniform float u_seed2;
layout (location = 2) uniform float u_seed3;

void main() {
    float z = 0.0;
    z += floor(u_seed1);
    z += radians(u_seed1);
    z += degrees(u_seed1);
    z += exp2(u_seed1);
    z += log2(u_seed1);
    z += sqrt(u_seed1);
    z += inversesqrt(u_seed1);
    z += min(u_seed1, u_seed2);
    z += max(u_seed1, u_seed2);
    z += clamp(u_seed1, u_seed2, u_seed3);
    z += mix(u_seed1, u_seed2, u_seed3);
    z += fma(u_seed1, u_seed2, u_seed3);

    // Dummy position
    gl_Position = vec4(a_position, z, 1.0);
}
