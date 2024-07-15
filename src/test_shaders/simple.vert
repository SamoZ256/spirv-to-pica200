#version 450

layout (location = 0) in vec2 a_position;

layout (location = 0) out vec2 v_texCoord;

layout (location = 0) uniform vec2 texCoordOffset;

void main() {
    gl_Position = vec4(a_position, 0.0, 1.0);
    v_texCoord = (a_position * 0.5 + 0.5) + texCoordOffset;
}
