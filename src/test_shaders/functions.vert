#version 450

layout (location = 0) in vec3 a_position;

layout (location = 0) uniform float u_seed1;
layout (location = 1) uniform float u_seedArray[8];

vec3 getPosition() {
    vec3 tmp = vec3(u_seed1 * 58475.908 + a_position.x);
    tmp /= a_position.y;
    tmp += a_position.z;

    return tmp - a_position;
}

void main() {
    vec3 pos = vec3(0.0);
    for (float i = 0.0; i < 8.0; i += 1.0) {
        pos += getPosition() * u_seedArray[int(i)];
    }

    // Dummy position
    gl_Position = vec4(pos, 1.0);
}
