#version 450

layout (location = 0) in vec3 a_position;

layout (location = 0) uniform float u_seed1;
layout (location = 1) uniform mat4 u_mat;

void main() {
    vec4 pos = u_mat * vec4(a_position, 1.0);

    // Dummy position
    gl_Position = vec4(pos.xyz, 1.0);
}
