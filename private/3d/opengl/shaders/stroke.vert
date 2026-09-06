#version 150

// SCENE-3D-O already tessellates strokes to screen-space triangles.  P's
// first shader consumes that representation rather than duplicating cap, join,
// dash, and clipping semantics in GLSL.
in vec4 position;
in vec4 color;

out vec4 vertexColor;

void main() {
  vertexColor = color;
  gl_Position = position;
}
