// Sollin FX presets 13-25 · 原生 WebGL2 版（与 preview.html 完全相同）
#version 300 es
precision highp float;
in vec2 aUv; in float aSeed; in vec3 aRnd;
uniform mat4 uView, uProj;
uniform vec3 uCamPos;
uniform float uTime, uBass, uMid, uTreble, uEnergy, uBeat;
uniform float uPreset, uK, uPoint, uBurst, uShield, uSizeK, uColorBoost, uAlpha;
uniform sampler2D uCover;
uniform vec3 uCoverA, uCoverB, uAccent;
out vec3 vColor; out float vAlpha;

const float TAU = 6.2831853;
const vec3 HOT = vec3(1.0, 0.95, 0.86);
vec3 P; vec3 C; float A; float S; vec3 cover;

// ---- 共享工具（hash / value noise 都不用三角函数）----
float h11(float p){ p = fract(p*0.1031); p *= p + 33.33; p *= p + p; return fract(p); }
float h21(vec2 p){ vec3 p3 = fract(vec3(p.xyx)*0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y)*p3.z); }
float h31(vec3 p3){ p3 = fract(p3*0.1031); p3 += dot(p3, p3.zyx + 31.32); return fract((p3.x + p3.y)*p3.z); }
vec3 hv3(float k){ return vec3(h11(k*1.17 + 0.31), h11(k*2.39 + 1.73), h11(k*3.71 + 2.97)); }
float vnoise(vec3 p){
  vec3 i = floor(p), f = fract(p); f = f*f*(3.0 - 2.0*f);
  return mix(mix(mix(h31(i),             h31(i+vec3(1,0,0)), f.x),
                 mix(h31(i+vec3(0,1,0)), h31(i+vec3(1,1,0)), f.x), f.y),
             mix(mix(h31(i+vec3(0,0,1)), h31(i+vec3(1,0,1)), f.x),
                 mix(h31(i+vec3(0,1,1)), h31(i+vec3(1,1,1)), f.x), f.y), f.z);
}
// 球面均匀方向（2 次三角函数）。不要用 normalize(aRnd-0.5)，那样会有立方体偏差，球看起来发方。
vec3 sphDir(vec2 r){ float y = r.x*2.0 - 1.0, a = r.y*TAU, q = sqrt(max(0.0, 1.0 - y*y)); return vec3(q*cos(a), y, q*sin(a)); }
vec3 rotY(vec3 p, float c, float s){ return vec3(c*p.x + s*p.z, p.y, -s*p.x + c*p.z); }
// 法线朝向相机的程度：1 正对，0 切线（轮廓），-1 背面。用来压暗球体背面，避免加色混合下前后糊在一起。
float facing(vec3 n, vec3 p){ return dot(n, normalize(uCamPos - p)); }
// uBeat 峰值后指数衰减 → 反过来就是"距上一拍的进度" 0→1，用于从中心向外推的波前
float beatFront(){ return clamp(1.0 - uBeat/0.78, 0.0, 1.0); }

// ==== PRESET 13 ==== 金缮 KINTSUGI：封面贴成的瓷球，碎成不规则碎片，裂缝里是金
void pKintsugi(){
  float t = uTime;
  float th = aUv.x*TAU;
  float y = aUv.y*2.0 - 1.0;                       // y 均匀 → 球面等面积分布
  float rxz = sqrt(max(0.0, 1.0 - y*y));
  vec3 n = vec3(rxz*cos(th), y, rxz*sin(th));      // trig 2
  // 3D 晶格 + 噪声扭曲 = 不规则碎片；晶格平面与球面的交线就是裂缝
  vec3 w = n*2.6 + (vec3(vnoise(n*2.0 + 1.7), vnoise(n*2.0 + 7.3), vnoise(n*2.0 + 4.1)) - 0.5)*0.9;
  vec3 cell = floor(w), f = fract(w);
  vec3 ed = min(f, 1.0 - f);
  float edge = min(ed.x, min(ed.y, ed.z));
  float ch = h31(cell + 17.0);
  vec3 cdir = normalize(cell + 0.5);
  float open = (uBeat*0.55 + uBass*0.22)*uK*0.6;
  float R = 2.2;
  vec3 p;
  if (edge < 0.045) {
    p = n*R*0.985;                                 // 金缝留在原球面，碎片浮起时露出金网
    float glit = pow(h11(aSeed*91.7 + floor(t*14.0)), 10.0);
    C = uAccent*(0.95 + 1.6*uBeat + 0.5*uBass) + HOT*glit*(0.15 + uTreble*2.6);
    A = 0.9; S = 1.15;
  } else {
    float breathe = sin(t*0.35 + ch*TAU)*0.025;                 // trig 3
    float wob = sin(t*0.6 + ch*9.0)*(0.03 + uMid*0.15*uK);       // trig 4
    p = n*R*(1.0 + breathe + open*(0.12 + 0.3*ch) + uBass*0.05*ch*uK) + (n - cdir)*wob*R;
    C = cover*(1.5 + 0.4*uEnergy)*(0.9 + 0.25*ch);
    A = 0.9; S = 1.05;
  }
  float sp = t*0.1, cs = cos(sp), ss = sin(sp);                  // trig 6
  P = rotY(p, cs, ss);
  A *= mix(0.22, 1.0, smoothstep(-0.25, 0.35, facing(rotY(n, cs, ss), P)));
}

// ==== PRESET 14 ==== 墨韵 INK BLOOM：4 团墨在 3D 水体里错峰扩散、翻卷、下沉
void pInk(){
  float t = uTime;
  if (aSeed > 0.86) {                              // 14%：悬浮微尘
    vec3 p = (aRnd - 0.5)*vec3(12.0, 8.0, 12.0);
    vec3 q = p*0.3 + vec3(0.0, t*0.05, 0.0);
    p += (vec3(vnoise(q), vnoise(q + 3.1), vnoise(q + 6.7)) - 0.5)*0.9;
    float tw = pow(h11(aSeed*13.1 + floor(t*6.0)), 12.0);
    P = p; C = mix(uCoverA, vec3(1.0), 0.4)*(0.4 + tw*uTreble*3.0);
    A = 0.16 + tw*uTreble*0.6; S = 0.6; return;
  }
  float d = floor(aSeed/0.86*4.0);
  float cyc = t/10.0 + d*0.25;
  float age = fract(cyc), gen = floor(cyc);
  vec3 hd = hv3(d*7.0 + gen*13.0) - 0.5;
  vec2 hz = normalize(hd.xz + 1e-3)*(1.3 + abs(hd.y)*2.4);       // 绕中心一圈分布，不挤在正中
  vec3 c = vec3(hz.x, 0.9 + hd.y*0.6, hz.y);
  vec3 dir = sphDir(aRnd.xy);
  float r0 = pow(fract(aSeed*53.7), 0.3);                        // 偏向外层 → 云团有清晰"表皮"
  vec3 q = dir*r0;
  float R = (0.35 + 1.5*sqrt(age))*(1.0 + uBass*0.3*uK)*(1.0 + uBeat*0.15);
  vec3 nq = q*2.2 + vec3(0.0, 0.0, t*0.12 + d*3.1 + gen*1.7);
  vec3 warp = vec3(vnoise(nq), vnoise(nq + 5.2), vnoise(nq + 9.7)) - 0.5;
  vec3 xyz = q*R + warp*(0.6 + uMid*1.1*uK)*r0*R;
  xyz.xz *= 1.0 + age*0.7*smoothstep(-0.2, 0.7, q.y);           // 上半部外翻 → 蘑菇状涡环
  xyz.y -= age*age*2.0 + r0*age*0.3;                             // 下沉
  float edge = smoothstep(0.6, 1.0, r0);
  float fib = pow(vnoise(q*9.0 + t*0.3 + d), 3.0)*uTreble*1.2*edge;
  xyz += dir*fib*R*0.3;
  P = c + xyz;
  float fade = pow(1.0 - age, 1.4)*smoothstep(0.0, 0.06, age);
  C = mix(cover*1.0, mix(uCoverB, uAccent, 0.35)*1.7, edge)*(1.0 + uBeat*0.7*(1.0 - age));
  A = (0.3 + 0.55*edge)*fade; S = 0.9 + edge*0.4;
}

// ==== PRESET 15 ==== 超立方 TESSERACT：32 棱 + 16 顶点，XW/YW 旋转后 4D→3D 透视
void pTess(){
  float t = uTime;
  float e = floor(aSeed*32.0);
  float ax = mod(e, 4.0);
  float b = floor(e/4.0);
  vec3 bits = vec3(mod(b, 2.0), mod(floor(b/2.0), 2.0), floor(b/4.0))*2.0 - 1.0;
  float s = aUv.x*2.0 - 1.0;
  bool isVert = aRnd.x < 0.18;
  if (isVert) s = s < 0.0 ? -1.0 : 1.0;
  vec4 v;
  if (ax < 0.5)      v = vec4(s, bits);
  else if (ax < 1.5) v = vec4(bits.x, s, bits.yz);
  else if (ax < 2.5) v = vec4(bits.xy, s, bits.z);
  else               v = vec4(bits, s);
  v += vec4(aRnd - 0.5, aRnd.x - 0.5)*(isVert ? 0.06 : 0.012)*(1.0 + uBeat*4.0);
  float a1 = t*0.21 + uMid*0.45*uK, a2 = t*0.13 + 0.6, a3 = t*0.07;
  float c1 = cos(a1), s1 = sin(a1), c2 = cos(a2), s2 = sin(a2), c3 = cos(a3), s3 = sin(a3); // trig 6
  v = vec4(c1*v.x - s1*v.w, v.y, v.z, s1*v.x + c1*v.w);
  v = vec4(v.x, c2*v.y - s2*v.w, v.z, s2*v.y + c2*v.w);
  float wd = 3.0 - uBass*0.7*uK - uBeat*0.3;
  vec3 p = v.xyz/(wd - v.w)*2.0;
  p = rotY(p, c3, s3);
  P = p*1.05 + vec3(0.0, -0.55, -0.6);
  float wn = clamp(v.w*0.5 + 0.5, 0.0, 1.0);
  C = mix(uCoverA*0.9, uAccent, wn);
  float run = pow(fract(aUv.x*1.5 - t*0.8 + h11(e)*3.0), 14.0);
  C += HOT*run*(0.25 + uTreble*2.2);
  A = 0.5 + 0.25*wn; S = 0.9;
  if (isVert) { C = mix(uAccent, vec3(1.0), 0.4)*(1.0 + uBeat*2.0); A = 0.9; S = 1.6 + uBeat*1.5; }
}

// ==== PRESET 16 ==== 事件视界 ACCRETION：吸积盘（真 3D）+ 透镜弧/光子环（实时朝向相机）
void pDisk(){
  float t = uTime;
  vec3 warm = mix(uCoverA, vec3(1.0, 0.48, 0.18), 0.55);
  vec3 O = vec3(0.0, -0.6, 0.0);
  // 观察基：V 指向相机；rt = 盘法线 × V（屏幕右）；upv = 屏幕上方向里离盘法线最近的方向
  vec3 V = normalize(uCamPos - O);
  vec3 rt = cross(vec3(0.0, 1.0, 0.0), V);
  float rlen = length(rt);
  rt = rlen > 1e-3 ? rt/rlen : vec3(1.0, 0.0, 0.0);
  vec3 upv = cross(V, rt);
  float above = V.y >= 0.0 ? 1.0 : -1.0;          // 从盘下方看时，透镜弧翻到下方
  float elev = abs(V.y);                           // 越接近俯视，透镜像越接近完整对称圆环
  float front = beatFront()*4.8;
  if (aSeed < 0.74) {
    float rin = 1.3 - uBass*0.12*uK;
    float r = mix(rin, 4.8, pow(aRnd.x, 0.75));
    float w = 0.95*pow(r, -1.5)*(1.0 + uEnergy*0.25);           // 开普勒
    float th = aRnd.y*TAU + t*w;
    float ct = cos(th), st = sin(th);                            // trig 2
    float wave = 0.5 + 0.5*cos(2.0*th - 4.0*log(r) + t*0.2);     // trig 3
    float y = (aRnd.z - 0.5)*(0.03 + 0.025*r)*(1.0 + uMid*1.4*uK)
            + (vnoise(vec3(ct*r, st*r, t*0.3)) - 0.5)*uMid*0.12*r;
    vec3 p = vec3(ct*r, y, st*r);
    float heat = 1.0 - smoothstep(rin, 3.2, r);
    C = mix(mix(uCoverA*0.55, warm, smoothstep(4.8, 2.2, r)), mix(uAccent, HOT, heat), heat);
    float dop = 1.0 + 0.6*dot(vec3(-st, 0.0, ct), V);           // 多普勒：朝相机运动的一侧更亮（任意视角）
    float hotspot = pow(h11(aSeed*57.3 + floor(t*12.0)), 14.0)*uTreble*3.0*heat;
    float ringBeat = exp(-abs(r - front)*3.0)*uBeat*1.4;
    C *= 1.5*dop*(0.55 + 0.55*wave*(0.6 + uMid*0.8))*(1.0 + uBass*0.7*heat);
    C += HOT*hotspot + uAccent*ringBeat;
    A = (0.4 + 0.55*heat)*smoothstep(4.8, 4.0, r);
    float along = dot(p, V);                                     // 被黑影挡住：在黑洞后方且投影落在阴影半径内
    if (along < 0.0 && length(p - V*along) < 1.12) A *= 0.04;
    S = 0.85 + heat*0.5;
    P = O + p;
  } else if (aSeed < 0.9) {
    // 引力透镜弧：盘背面的像被弯到黑影上方（始终在垂直于视线的平面里）
    float ph = aRnd.y*TAU;
    float rl = 1.3 + pow(aRnd.x, 2.2)*0.75*(1.0 + uBass*0.2*uK);
    float cp = cos(ph), sp = sin(ph);                            // trig 2
    P = O + (rt*cp + upv*sp*0.92)*rl - V*(0.1 + (aRnd.z - 0.5)*0.05);
    float up = mix(sp*above > 0.0 ? 1.0 : 0.38, 1.0, smoothstep(0.6, 0.95, elev));
    C = mix(uAccent, HOT, 0.4)*(0.6 + 0.5*(1.0 - aRnd.x))*(1.0 + 0.5*cp)*(1.0 + uBass*0.5);
    A = 0.85*up*(1.0 - aRnd.x*0.7); S = 0.85;
  } else {
    // 光子环：同样朝向相机
    float ph = aRnd.y*TAU;
    float rr = 1.12 + (aRnd.x - 0.5)*0.035;
    P = O + (rt*cos(ph) + upv*sin(ph))*rr;                       // trig 2
    C = HOT*(1.0 + uBeat*2.5 + uBass*0.6); A = 0.75; S = 0.9 + uBeat;
  }
}

// ==== PRESET 17 ==== 磷光示波 PHOSPHOR SCOPE：3:2:5 李萨如三维结 + 玻璃立方体框 + 水平扫描面
void pScope(){
  float t = uTime;
  vec3 O = vec3(0.0, -0.5, 0.0);
  vec3 H = vec3(2.4, 1.5, 2.0);                    // 示波"立方体"半尺寸
  float scanY = (1.0 - fract(t*0.22)*2.0)*H.y;
  if (aSeed < 0.66) {
    float tr = pow(aRnd.y, 1.7);
    float s = aRnd.x*TAU;
    float delta = t*0.45 - tr*0.9;
    float amp = 0.82 + uBass*0.3*uK + uBeat*0.12;
    float bq = 2.0 + uMid*0.3*uK;
    vec3 p = H*amp*0.92*vec3(sin(3.0*s + delta), sin(bq*s), sin(5.0*s - delta*0.7)); // trig 3
    float j = floor(t*30.0);
    p += (vec3(h11(aSeed*31.1 + j), h11(aSeed*17.3 + j), h11(aSeed*7.9 + j)) - 0.5)*uTreble*0.1*uK;
    if (aRnd.z > 0.985) p += (aRnd - 0.5)*0.7*uTreble*uK;
    float persist = mix(3.2, 1.5, uBeat);
    float scan = exp(-abs(p.y - scanY)*14.0);
    A = pow(1.0 - tr, persist)*0.85;
    C = mix(vec3(1.0, 0.97, 0.9), mix(uCoverB, uAccent, 0.3), smoothstep(0.0, 0.25, tr))*(1.0 + uBeat*1.2)
      + uAccent*scan*0.8*(1.0 - tr);
    S = mix(1.3, 0.7, tr);
    P = O + p;
  } else if (aSeed < 0.8) {
    // 12 条立方体棱
    float e = floor(aRnd.z*12.0), ax = floor(e/4.0), m = mod(e, 4.0);
    vec2 sg = vec2(mod(m, 2.0), floor(m/2.0))*2.0 - 1.0;
    float s = aRnd.x*2.0 - 1.0;
    vec3 p = ax < 0.5 ? vec3(s, sg.x, sg.y) : (ax < 1.5 ? vec3(sg.x, s, sg.y) : vec3(sg.x, sg.y, s));
    float corner = smoothstep(0.82, 1.0, abs(s));
    P = O + p*H*1.05;
    C = uCoverA*0.45 + uAccent*(0.12 + 0.5*corner);
    A = 0.28 + 0.3*corner; S = 0.7;
  } else {
    if (aRnd.z < 0.7) {
      // 底面刻度网格
      vec2 g = (aRnd.xy*2.0 - 1.0)*H.xz;
      if (aRnd.z < 0.35) g.x = floor(g.x/0.48 + 0.5)*0.48; else g.y = floor(g.y/0.5 + 0.5)*0.5;
      P = O + vec3(g.x, -H.y*1.05, g.y);
      C = uCoverA*0.4 + uAccent*0.1; A = 0.2; S = 0.6;
    } else {
      // 扫描面的矩形轮廓（随 scanY 上下移动）
      float u = aRnd.x*4.0, k = floor(u), s = fract(u)*2.0 - 1.0;
      vec2 g = k < 0.5 ? vec2(s, -1.0) : (k < 1.5 ? vec2(1.0, s) : (k < 2.5 ? vec2(-s, 1.0) : vec2(-1.0, -s)));
      P = O + vec3(g.x*H.x*1.05, scanY, g.y*H.z*1.05);
      C = uAccent*(0.7 + uEnergy + uBeat*1.5); A = 0.5; S = 0.8;
    }
  }
}

// ==== PRESET 18 ==== 神经花火 NEURAL BLOOM：胞体 + 30 根全方位（斐波那契球面）树突
void pNeuron(){
  float t = uTime;
  vec3 O = vec3(0.0, -0.2, 0.0);
  if (aSeed < 0.1) {
    vec3 n = sphDir(aRnd.xy);
    float rr = 0.4*(1.0 + uBass*0.3*uK + uBeat*0.15)*(0.85 + 0.15*vnoise(n*3.0 + t*0.4));
    P = O + n*rr*(0.6 + 0.4*fract(aSeed*37.0));
    C = mix(uCoverB, uAccent, 0.4)*(0.8 + uBass*0.9 + uBeat*1.2); A = 0.55; S = 1.1; return;
  }
  float f = floor((aSeed - 0.1)/0.9*30.0);
  float s = aRnd.x;
  float yf = 1.0 - 2.0*(f + 0.5)/30.0;
  float af = f*2.39996;                            // 黄金角
  float rf = sqrt(1.0 - yf*yf);
  vec3 d0 = vec3(cos(af)*rf, yf, sin(af)*rf);      // trig 2
  vec3 bend = hv3(f*3.3) - 0.5, bend2 = hv3(f*5.9 + 4.0) - 0.5, br = hv3(f*8.1 + 2.0) - 0.5;
  float sway = sin(t*0.5 + f*1.7)*(0.08 + uMid*0.25*uK);          // trig 3
  vec3 dir = d0 + bend*s*s*1.3 + bend2*s*sway;
  if (aRnd.y > 0.55 && s > 0.45) dir += br*1.6*(s - 0.45);       // 分叉
  dir = normalize(dir);
  float hf = h11(f*1.37 + 0.5), hg = h11(f*2.71 + 1.3);
  float L = (2.0 + hf*1.8)*(1.0 + uBass*0.08*uK);
  P = O + dir*(0.36 + s*L) + (aRnd.zxy - 0.5)*0.03*(1.0 + s*2.0);
  float ph2 = fract(t*(0.18 + 0.12*hf) + hg);
  float idle = exp(-abs(s - ph2)*28.0)*0.8;
  float ap = exp(-abs(s - beatFront())*12.0)*uBeat*2.2;
  float tip = smoothstep(0.9, 1.0, s);
  float spark = pow(h11(f*9.1 + floor(t*9.0) + aRnd.y), 8.0)*uTreble*3.0*tip;
  C = uCoverA*0.85*(1.0 - 0.4*s) + uAccent*(idle + ap) + HOT*spark;
  A = 0.3 + 0.35*(1.0 - s) + (idle + ap)*0.4; S = 0.75 + tip*0.5 + ap*0.4;
}

// ==== PRESET 19 ==== 雾中光柱 VOLUMETRIC BEAMS：环形排布的 10 束光（皇冠状）+ 体积雾 + 极坐标激光地网
void pBeams(){
  float t = uTime;
  float floorY = -2.2;
  if (aSeed < 0.68) {
    float b = floor(aSeed/0.68*10.0);
    float phi = b/10.0*TAU + t*0.05;
    float cphi = cos(phi), sphi = sin(phi);                          // trig 2
    float ang = 0.32 + 0.25*h11(b*3.1) + sin(t*0.37 + b*0.9)*(0.12 + uMid*0.25*uK); // trig 3
    float sa = sin(ang), ca = cos(ang);                              // trig 5
    vec3 radial = vec3(cphi, 0.0, sphi);
    vec3 tng = vec3(-sphi, 0.0, cphi);
    vec3 dir = radial*sa + vec3(0.0, ca, 0.0);                       // 向上并向外张开
    vec3 bin = cross(dir, tng);
    float L = 8.0, l = pow(aRnd.x, 0.8)*L;
    float rad = (0.02 + l*0.022)*(1.0 + uBass*0.9*uK);
    vec2 off = (aRnd.yz - 0.5)*2.0;
    float rr = length(off); off /= max(1.0, rr); rr = min(rr, 1.0);
    vec3 p = radial*3.0 + vec3(0.0, floorY, 0.0) + dir*l + (tng*off.x + bin*off.y)*rad;
    float haze = 0.35 + 0.65*vnoise(p*0.7 + vec3(0.0, -t*0.15, t*0.05));
    float core = 1.0 - rr;
    vec3 bc = mod(b, 2.0) < 0.5 ? mix(uCoverB, vec3(1.0), 0.25) : uAccent;
    C = bc*(0.6 + 1.2*core*core)*haze*(1.0 + uBeat*2.2)*(0.8 + uBass*0.6);
    A = exp(-l*0.16)*(0.55 + 0.45*core)*haze; S = 0.8;
    P = p;
  } else if (aSeed < 0.88) {
    vec3 p = (aRnd - 0.5)*vec3(14.0, 7.0, 14.0) + vec3(0.0, 1.2, 0.0);
    vec3 q = p*0.25 + t*0.04;
    p += (vec3(vnoise(q), vnoise(q + 9.0), vnoise(q + 3.0)) - 0.5)*1.2;
    float tw = pow(h11(aSeed*77.7 + floor(t*8.0)), 9.0)*uTreble*3.0;
    C = mix(uCoverA, vec3(1.0), 0.5)*(0.25 + tw); A = 0.12 + tw*0.4; S = 0.55 + tw*0.6; P = p;
  } else {
    // 极坐标地网：同心圆向外扩散 + 16 条辐条
    float u = aRnd.y*TAU, r;
    if (aRnd.z < 0.55) r = floor(aRnd.x*7.0) + fract(t*0.15); else { u = floor(aRnd.y*16.0)/16.0*TAU; r = aRnd.x*7.5; }
    P = vec3(cos(u)*r, floorY, sin(u)*r);                            // trig 2
    float fade = smoothstep(7.5, 2.0, r);
    C = uCoverB*0.5*(1.0 + uBass*1.2 + uBeat*1.5); A = 0.4*fade; S = 0.7;
  }
}

// ==== PRESET 20 ==== 戴森云 DYSON SWARM：恒星 + 9 条倾斜卫星轨道 + 建造中的面板壳层
void pDyson(){
  float t = uTime;
  if (aSeed < 0.16) {
    vec3 n = sphDir(aRnd.xy);
    float conv = vnoise(n*4.0 + t*0.25);                            // 米粒组织/对流
    P = n*0.9*(1.0 + uBass*0.18*uK + uBeat*0.08)*(0.94 + 0.08*conv)*(0.75 + 0.25*fract(aSeed*61.0));
    C = mix(uAccent, HOT, conv)*(1.2 + uBass*0.8 + uBeat*1.0); A = 0.6; S = 1.1;
    if (fract(aSeed*97.0) < 0.22) {                                  // 日冕：被高频吹出
      P = n*(0.95 + pow(h11(aSeed*5.3 + floor(t*6.0)), 3.0)*(0.4 + uTreble*1.2));
      A = 0.3; C *= 0.7;
    }
    return;
  }
  if (aSeed < 0.64) {
    float k = floor((aSeed - 0.16)/0.48*9.0);
    float hk = h11(k*3.1 + 0.7), hk2 = h11(k*5.7 + 2.1);
    float rad = 1.5 + k*0.2 + hk*0.1;
    float inc = (hk - 0.5)*2.4;
    float node = hk2*TAU + t*0.03 + uMid*0.4*uK;                     // 中频推动轨道进动
    float dirS = mod(k, 2.0) < 0.5 ? 1.0 : -1.0;
    float u = aRnd.x*TAU + t*0.9*pow(rad, -1.5)*(1.0 + uEnergy*0.3)*dirS;
    float cu = cos(u), su = sin(u), ci = cos(inc), si = sin(inc), cn = cos(node), sn = sin(node); // trig 6
    vec3 p = vec3(cu*rad, -su*rad*si, su*rad*ci);
    p = rotY(p, cn, sn) + (aRnd - 0.5)*0.035;
    float train = step(0.5, fract(aRnd.x*36.0 + k*0.3));             // 卫星成列分布
    float glint = pow(h11(aSeed*41.3 + floor(t*10.0)), 12.0)*uTreble*3.0;
    C = mix(uCoverA, uCoverB, hk)*0.9 + HOT*glint;
    A = 0.12 + 0.5*train + glint*0.3; S = 0.8 + glint*0.6;
    P = p; return;
  }
  // 壳层：3D 晶格切分成面板，约一半已建成
  vec3 n = sphDir(aRnd.xy);
  float g = t*0.05, cg = cos(g), sg = sin(g);                       // trig 2
  vec3 cell = floor(n*5.0), f = fract(n*5.0);
  vec3 ed = min(f, 1.0 - f);
  float frame = step(min(ed.x, min(ed.y, ed.z)), 0.06);
  float ch = h31(cell + 3.0);
  float built = step(ch, 0.5 + 0.15*uEnergy);
  float R = 3.3 + uBeat*0.3*ch + uBass*0.06*uK;
  P = rotY(n*R, cg, sg);
  float wave = exp(-abs(n.y - (beatFront()*2.0 - 1.0))*6.0)*uBeat*1.6;  // 主拍：一道光自下而上扫过壳层
  float glint = pow(h31(cell + floor(t*5.0)), 14.0)*uTreble*3.0;
  C = frame > 0.5 ? uAccent*(0.8 + wave) : uCoverA*0.6*(1.0 + glint*4.0) + uAccent*wave*0.5;
  A = built > 0.5 ? (frame > 0.5 ? 0.8 : 0.4) : (frame > 0.5 ? 0.25 : 0.0);
  A *= mix(0.35, 1.0, smoothstep(-0.2, 0.3, facing(rotY(n, cg, sg), P)));
  S = 0.85;
}

// ==== PRESET 21 ==== 全息地球 HOLO GLOBE：点阵大陆 + 经纬网 + 大气辉光 + 数据弧 + 卫星环 + 扫描环
void pGlobe(){
  float t = uTime;
  float R = 2.1*(1.0 + uBass*0.05*uK);
  float sp = t*0.08, cs = cos(sp), ss = sin(sp);                    // trig 2
  if (aSeed < 0.6) {
    float y = aRnd.x*2.0 - 1.0, th = aRnd.y*TAU, rxz = sqrt(max(0.0, 1.0 - y*y));
    vec3 n = vec3(rxz*cos(th), y, rxz*sin(th));                     // trig 4
    float land = vnoise(n*2.3 + 3.0)*0.65 + vnoise(n*5.1 + 1.0)*0.35;
    float lat = step(abs(fract(y*6.0 + 0.5) - 0.5), 0.018);
    float lon = step(abs(fract(aRnd.y*24.0 + 0.5) - 0.5), 0.02);
    vec3 nr = rotY(n, cs, ss);
    float fc;
    if (land > 0.53) {
      P = nr*R; fc = facing(nr, P);
      float city = pow(h11(aSeed*33.1 + floor(t*7.0)), 10.0)*uTreble*3.0;
      C = mix(uCoverA, uCoverB, smoothstep(0.53, 0.7, land))*1.5 + HOT*city;
      A = 0.9*mix(0.15, 1.0, smoothstep(-0.2, 0.35, fc)); S = 0.85 + city*0.4;
    } else if (lat + lon > 0.5) {
      P = nr*R*1.003; fc = facing(nr, P);
      C = uCoverA*0.8 + uAccent*0.2;
      A = 0.6*mix(0.15, 1.0, smoothstep(-0.2, 0.35, fc)); S = 0.7;
    } else {
      // 海洋区域的点抬成大气层，边缘（轮廓）最亮 → 任意角度都有球形辉光
      float h = pow(fract(aSeed*91.3), 2.0);
      P = nr*R*(1.03 + h*0.16*(1.0 + uBass*0.6*uK)); fc = facing(nr, P);
      C = mix(uCoverB, vec3(1.0), 0.3)*(0.5 + uBass*0.6);
      A = 0.12*(1.0 - h)*(0.6 + 2.4*(1.0 - abs(fc))); S = 0.8;
    }
    return;
  }
  if (aSeed < 0.86) {
    // 36 条数据弧：两端点在球面上，中间拱起
    float k = floor((aSeed - 0.6)/0.26*36.0);
    vec3 a = normalize(hv3(k*1.3) - 0.5 + 1e-3), b = normalize(hv3(k*7.7 + 3.0) - 0.5 + 1e-3);
    float s = aRnd.x;
    vec3 dir = normalize(mix(a, b, s) + 1e-3);
    float hgt = 4.0*s*(1.0 - s)*(0.18 + 0.3*h11(k*9.1))*(1.0 + uMid*0.9*uK);
    P = rotY(dir, cs, ss)*R*(1.0 + hgt) + (aRnd - 0.5)*0.015;
    float idle = exp(-abs(s - fract(t*0.25 + h11(k*2.2)))*30.0);
    float ap = exp(-abs(s - beatFront())*14.0)*uBeat*2.5;
    float endp = 1.0 - smoothstep(0.0, 0.03, min(s, 1.0 - s));
    C = uCoverB*0.7 + uAccent*(idle + ap) + HOT*endp*0.6;
    A = 0.35 + 0.5*(idle + ap) + endp*0.4; S = 0.7 + ap*0.5 + endp*0.5;
    return;
  }
  if (aSeed < 0.94) {
    // 倾斜卫星环（虚线）+ 3 颗卫星
    float u = aRnd.x*TAU + t*0.3;
    vec3 p = vec3(cos(u), 0.0, sin(u))*R*1.45;                      // trig 4
    const float ci = 0.9004, si = 0.4350;                          // cos/sin(0.45)
    P = vec3(p.x, -p.z*si, p.z*ci) + (aRnd - 0.5)*0.02;
    float dash = step(0.35, fract(aRnd.x*48.0));
    float sat = step(fract(aRnd.x*3.0), 0.015);
    C = uCoverA*0.6*dash + HOT*sat*(1.0 + uBeat*2.0);
    A = 0.3*dash + 0.8*sat; S = 0.75 + sat*1.2;
    return;
  }
  // 纬度扫描环：上下往复
  float ys = sin(t*0.4)*0.92;                                       // trig 3
  float rr = sqrt(max(0.0, 1.0 - ys*ys))*R*1.02;
  float u = aRnd.x*TAU;
  P = vec3(cos(u)*rr, ys*R*1.02, sin(u)*rr);                        // trig 5
  C = uAccent*(0.6 + uBeat*2.0 + uEnergy); A = 0.35; S = 0.85;
}

// ==== PRESET 22 ==== 托卡马克 TOKAMAK：螺旋磁力线上流动的等离子体环 + 16 个 D 形线圈 + 中心螺线管
void pTokamak(){
  float t = uTime;
  float R0 = 2.3;
  if (aSeed < 0.6) {
    float line = floor(aRnd.y*28.0);
    float hl = h11(line*3.7 + 0.4);
    float a = 0.62*(1.0 + uBass*0.3*uK);
    float u = aRnd.x*TAU;
    float rr = (0.25 + 0.75*hl)*a;
    rr *= 1.0 + 0.25*uMid*uK*sin(3.0*u + t);                         // trig 1：m=3 扭曲模
    if (aRnd.z > 0.97) rr += pow(h11(aSeed*19.3 + floor(t*12.0)), 3.0)*uTreble*0.9*uK;
    float v = line/28.0*TAU + u*2.0 + t*(0.5 + 0.3*hl);             // 磁力线缠绕 + 沿线流动
    float uu = u + t*0.12;
    float cu = cos(uu), su = sin(uu), cv = cos(v), sv = sin(v);     // trig 5
    float Rr = R0 + rr*cv;
    P = vec3(Rr*cu, rr*sv*1.35, Rr*su) + (aRnd.zxy - 0.5)*0.015;
    float core = clamp(1.0 - rr/(a*1.05), 0.0, 1.0);
    float dash = pow(fract(u/TAU*12.0 - t*0.8*(0.6 + hl)), 5.0);
    float ap = exp(-abs(fract(u/TAU) - beatFront())*18.0)*uBeat*2.5;   // 主拍：一团亮脉冲绕环跑一圈
    C = mix(uCoverB, HOT, core*core)*(0.7 + 1.1*dash)*(1.0 + uBass*0.8) + uAccent*ap;
    A = 0.45 + 0.45*core + ap*0.3; S = 0.8 + core*0.4;
  } else if (aSeed < 0.88) {
    float k = floor((aSeed - 0.6)/0.28*16.0);
    float u = k/16.0*TAU + t*0.12;
    float v = aRnd.x*TAU;
    float cu = cos(u), su = sin(u), cv = cos(v), sv = sin(v);        // trig 4
    vec2 dl = vec2(max(R0 + 0.15 + 1.05*cv, R0 - 0.7), 1.45*sv);     // max() 截出 D 形的直边
    dl += (aRnd.yz - 0.5)*0.09;
    P = vec3(dl.x*cu, dl.y, dl.x*su);
    float chase = pow(fract(k/16.0 + t*0.4), 6.0);
    C = uCoverA*0.6 + uAccent*(0.2 + chase*0.7 + uBeat*0.8); A = 0.45; S = 0.8;
  } else {
    float u = aRnd.x*TAU, y = (aRnd.y - 0.5)*3.0;
    P = vec3(cos(u)*0.55, y, sin(u)*0.55) + (aRnd.z - 0.5)*0.03;    // trig 2
    float wind = pow(fract(y*5.0 + u/TAU + t*0.5), 6.0);
    C = mix(uCoverA*0.5, uAccent, wind)*(1.0 + uBass*1.2 + uBeat*1.5); A = 0.35; S = 0.8;
  }
}

// ==== PRESET 23 ==== 旋涡星系 SPIRAL GALAXY：核球 + 双臂对数螺旋 + 暗尘带 + HII 区 + 晕
void pGalaxy(){
  float t = uTime;
  float front = beatFront()*6.0;
  if (aSeed < 0.12) {
    vec3 n = sphDir(aRnd.xy);
    float r = pow(fract(aSeed*71.3), 1.8)*1.15*(1.0 + uBass*0.15*uK);
    P = n*r*vec3(1.0, 0.62, 1.0);
    C = mix(HOT, uAccent, r)*(1.0 + uBass*0.8 + uBeat*0.8); A = 0.45; S = 1.0; return;
  }
  if (aSeed < 0.9) {
    float r = 0.5 + pow(aRnd.x, 0.85)*4.8;
    bool inArm = fract(aSeed*29.3) > 0.3;
    float arm = floor(aRnd.z*2.0);
    float sp = aRnd.y + fract(aSeed*7.31) - 1.0;                    // 三角分布：集中在旋臂中线附近，范围 ±1
    float wind = 2.3 + uMid*0.35*uK;                                // 中频让旋臂收紧
    float th = inArm ? arm*3.14159 + log(r)*wind + sp*(0.7 + 0.1*r) : aRnd.y*TAU;
    th += t*0.32/(0.5 + r*0.45);                                    // 差速转动
    float ct = cos(th), st = sin(th);                               // trig 2
    float y = (h11(aSeed*17.1) - 0.5)*0.22*exp(-r*0.18)*(1.0 + uMid*0.8*uK) + 0.025*r*st; // 盘厚 + 轻微翘曲
    P = vec3(ct*r, y, st*r);
    float dust = (inArm && sp < -0.05) ? 0.3 : 1.0;                 // 旋臂内侧暗尘带
    vec3 young = mix(uCoverB, vec3(0.85, 0.92, 1.0), 0.4);
    vec3 old = mix(uAccent, uCoverA, 0.5)*0.8;
    C = (inArm ? mix(young, old, smoothstep(0.0, 0.6, abs(sp))) : old*0.7)*dust;
    float hii = inArm ? pow(h21(vec2(floor(r*3.0), arm + floor((sp + 1.0)*3.0))), 12.0) : 0.0;
    float tw = pow(h11(aSeed*61.7 + floor(t*8.0)), 12.0)*uTreble*3.0;
    float ring = exp(-abs(r - front*0.85)*2.0)*uBeat*1.3;
    C = C*(0.8 + uMid*0.5) + HOT*tw + mix(uCoverA, HOT, 0.5)*hii*1.5 + uAccent*ring;
    A = (0.4 + 0.4*exp(-r*0.25))*dust + hii*0.3; S = 0.8 + tw*0.6;
    return;
  }
  vec3 n = sphDir(aRnd.xy);
  P = n*(2.5 + fract(aSeed*43.7)*5.5);
  float tw = pow(h11(aSeed*23.9 + floor(t*5.0)), 10.0)*uTreble*3.0;
  C = mix(uCoverA, vec3(1.0), 0.5)*(0.35 + tw); A = 0.1 + tw*0.3; S = 0.6;
}

// ==== PRESET 24 ==== 虫洞 WORMHOLE：Flamm/悬链面嵌入图的时空网格 + 螺旋穿过喉部的物质 + 背景星
void pWormhole(){
  float t = uTime;
  float b = 0.75*(1.0 + uBass*0.35*uK + uBeat*0.1);                 // 喉部半径
  float Rm = 5.0;
  float front = beatFront();
  if (aSeed < 0.58) {
    float side = aRnd.z < 0.5 ? 1.0 : -1.0;
    float rs, phi;
    if (fract(aSeed*37.1) < 0.5) { rs = (floor(aRnd.x*14.0) + 1.0 - fract(t*0.25))/14.0; phi = aRnd.y*TAU; } // 同心环向喉部流入
    else { rs = aRnd.x; phi = floor(aRnd.y*24.0)/24.0*TAU; }                                                  // 24 条经线
    phi += side*(t*0.05 + uMid*0.8*uK*(1.0 - rs));                    // 中频扭转时空网格
    float r = b + (Rm - b)*rs*rs;
    float y = side*b*acosh(max(r/b, 1.0))*1.0;                        // 悬链面 r = b·cosh(y/b)
    P = vec3(cos(phi)*r, y, sin(phi)*r);                              // trig 2
    float wave = exp(-abs(rs - front)*12.0)*uBeat*2.0;                // 主拍：引力波环从喉部外扩
    C = (side > 0.0 ? uCoverA : uCoverB)*1.3 + uAccent*wave;
    A = 0.6*(1.0 - rs*0.6) + wave*0.3; S = 0.75;
  } else if (aSeed < 0.88) {
    float s = fract(aRnd.x + t*0.07*(0.7 + 0.6*aRnd.y));             // 0→1：从上方入口穿过喉部到下方出口
    float side = s < 0.5 ? 1.0 : -1.0;
    float rs = abs(1.0 - 2.0*s);
    float r = b + (Rm - b)*rs*rs;
    float y = side*b*acosh(max(r/b, 1.0));
    float phi = aRnd.y*TAU + s*9.0 + 2.5/r;                           // 越靠近喉部转得越快
    P = vec3(cos(phi)*r, y, sin(phi)*r) + (aRnd.zxy - 0.5)*0.12;     // trig 2
    float heat = 1.0 - rs;
    float tw = pow(h11(aSeed*29.1 + floor(t*10.0)), 10.0)*uTreble*3.0;
    C = mix(uCoverB, HOT, heat*heat)*(0.6 + heat) + HOT*tw;
    A = 0.22 + 0.5*heat; S = 0.7 + heat*0.6 + tw*0.4;
  } else if (aSeed < 0.94) {
    float phi = aRnd.y*TAU;
    float r = b*(1.0 + (aRnd.x - 0.5)*0.04);
    P = vec3(cos(phi)*r, (aRnd.z - 0.5)*0.08, sin(phi)*r);            // trig 2
    C = mix(uAccent, HOT, 0.5)*(1.2 + uBass + uBeat*2.0); A = 0.7; S = 1.0;
  } else {
    vec3 n = sphDir(aRnd.xy);
    P = n*(13.0 + fract(aSeed*53.1)*8.0);
    float tw = pow(h11(aSeed*11.3 + floor(t*4.0)), 8.0);
    C = mix(uCoverA, vec3(1.0), 0.6)*(0.5 + tw*(1.0 + uTreble*2.0)); A = 0.35; S = 0.9;
  }
}

// ==== PRESET 25 ==== 陀螺核心 GYRO CORE：能量核 + 4 层嵌套万向环（刻度、分段、追光）
void pGyro(){
  float t = uTime;
  if (aSeed < 0.12) {
    vec3 n = sphDir(aRnd.xy);
    float r = 0.55*(1.0 + uBass*0.3*uK + uBeat*0.15)*(0.92 + 0.08*vnoise(n*5.0 + t))*mix(0.7, 1.0, fract(aSeed*41.0));
    P = n*r; C = mix(uAccent, HOT, 0.5)*(1.0 + uBass + uBeat*1.5); A = 0.55; S = 1.0; return;
  }
  float k = floor((aSeed - 0.12)/0.88*4.0);
  float rad = (1.25 + k*0.5)*(1.0 + uBass*0.04*uK);
  vec3 e1 = normalize(hv3(k*3.3 + 1.0) - 0.5 + 1e-3);              // 环的翻转轴（环的一条直径）
  vec3 e2 = normalize(cross(e1, normalize(hv3(k*5.1 + 7.0) - 0.5 + 1e-3)));  // 环平面法线
  vec3 e3 = cross(e2, e1);
  float dirS = mod(k, 2.0) < 0.5 ? 1.0 : -1.0;
  float u = aRnd.x*TAU + t*(0.25 + 0.1*k)*dirS;
  float cu = cos(u), su = sin(u);                                   // trig 2
  vec3 p = (e1*cu + e3*su)*(rad + (aRnd.z - 0.5)*0.06) + e2*(aRnd.y - 0.5)*0.16;
  float ang = (t*(0.3 + 0.13*k) + uMid*0.6*uK + uBeat*0.5)*dirS;    // beat 让环"咔"地多拧一下再回弹
  float ca = cos(ang), sa = sin(ang);                               // trig 4
  p = p*ca + cross(e1, p)*sa + e1*dot(e1, p)*(1.0 - ca);            // Rodrigues 绕 e1 旋转
  float g = t*0.05, cg = cos(g), sg = sin(g);                       // trig 6
  P = rotY(p, cg, sg);
  float seg = step(0.08, fract(aRnd.x*6.0 + k*0.37));               // 6 段，留缺口
  float tick = step(0.75, fract(aRnd.x*90.0))*step(0.3, abs(aRnd.y - 0.5));
  float chase = pow(fract(aRnd.x*2.0 - t*(0.5 + 0.2*k)), 20.0)*(0.3 + uTreble*3.0);
  C = mix(uCoverA*0.7, uCoverB, k/3.0)*(0.6 + 0.6*tick) + HOT*chase + uAccent*uBeat*0.8;
  A = ((0.3 + 0.3*tick) + chase*0.4)*seg; S = 0.8 + chase*0.5;
}

void main(){
  cover = texture(uCover, aUv).rgb;
  P = vec3(0.0); C = vec3(1.0); A = 1.0; S = 1.0;
  if      (uPreset < 13.5) pKintsugi();
  else if (uPreset < 14.5) pInk();
  else if (uPreset < 15.5) pTess();
  else if (uPreset < 16.5) pDisk();
  else if (uPreset < 17.5) pScope();
  else if (uPreset < 18.5) pNeuron();
  else if (uPreset < 19.5) pBeams();
  else if (uPreset < 20.5) pDyson();
  else if (uPreset < 21.5) pGlobe();
  else if (uPreset < 22.5) pTokamak();
  else if (uPreset < 23.5) pGalaxy();
  else if (uPreset < 24.5) pWormhole();
  else                     pGyro();

  vec3 burstPos = P*1.6 + (aRnd - 0.5)*vec3(9.0, 6.0, 6.0);
  P = mix(P, burstPos, uBurst*uBurst);
  A *= 1.0 - 0.5*uBurst;

  vec4 mv = uView*vec4(P, 1.0);
  vec4 clip = uProj*mv;
  vec2 ndc = clip.xy/clip.w;
  float lyr = (1.0 - smoothstep(0.55, 0.8, abs(ndc.x)))
            * smoothstep(-0.42, -0.25, ndc.y) * (1.0 - smoothstep(0.55, 0.72, ndc.y));
  A *= 1.0 - uShield*lyr;

  vColor = C*uColorBoost;
  vAlpha = clamp(A*uAlpha, 0.0, 1.0);
  gl_Position = clip;
  gl_PointSize = clamp(uPoint*S*uSizeK/max(-mv.z, 0.1), 1.0, 28.0);
}
