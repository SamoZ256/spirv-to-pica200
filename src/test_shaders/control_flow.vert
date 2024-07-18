#version 450

layout (location = 0) in vec2 a_position;

layout (location = 0) uniform float u_seed;

void main() {
    float z = 0.0;
    if (u_seed > 0.0) {
        z = 1.0;
    } else {
        z = -1.0;
    }

    // Dummy position
    gl_Position = vec4(a_position, z, 1.0);
}
