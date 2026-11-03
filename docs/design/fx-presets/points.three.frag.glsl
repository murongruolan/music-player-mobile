// three.js 版（GLSL3）：three 会提供 gl_FragColor 的输出映射
in vec3 vColor; in float vAlpha;
void main(){
  vec2 c = gl_PointCoord - 0.5; float d = dot(c, c)*4.0;
  if (d > 1.0) discard;
  float a = 1.0 - d; a *= a;
  gl_FragColor = vec4(vColor, vAlpha*a);
}
