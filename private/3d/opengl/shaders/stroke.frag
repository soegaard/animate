#version 150

in vec4 vertexColor;
out vec4 fragment;

void main() {
  fragment = vec4(vertexColor.rgb * vertexColor.a, vertexColor.a);
}
