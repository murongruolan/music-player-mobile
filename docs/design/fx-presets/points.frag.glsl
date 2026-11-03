#version 300 es
precision highp float;
in vec3 vColor; in float vAlpha; out vec4 o;
void main(){
  vec2 c = gl_PointCoord - 0.5; float d = dot(c, c)*4.0;
  if (d > 1.0) discard;
  float a = 1.0 - d; a *= a;
  o = vec4(vColor, vAlpha*a);
}
