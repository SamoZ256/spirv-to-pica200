#version 450

layout (location = 0) in vec2 a_position;

layout (location = 0) uniform float u_seed;

void main() {
    float a = u_seed * 3.0;
    vec3 b = vec3(a) - 70.76585;

    float z = b.x + b.y + b.z;

    // Dummy position
    gl_Position = vec4(a_position, z, 1.0);
}
