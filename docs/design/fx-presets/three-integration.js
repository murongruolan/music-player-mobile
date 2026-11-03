// Sollin FX presets 13–25 · three.js 接入示例（r150+，ES module）
// 用法：把 presets.three.vert.glsl / points.three.frag.glsl 作为字符串导入（Vite: `?raw`），
//       然后 createSollinPoints() 得到一个 THREE.Points，每帧调用 update()。
// 这只是最小示例；你们引擎里已有的 geometry / 音频 / bloom 直接替换对应部分即可。

import * as THREE from 'three';
import vertexShader from './presets.three.vert.glsl?raw';
import fragmentShader from './points.three.frag.glsl?raw';

const N = 183, COUNT = N * N;              // 与现有点云一致：33,489 点

// 每个预设的歌词避让强度（与 preview.html 的 PRESETS[].shield 相同）
export const PRESET_SHIELD = { 13:0.35, 14:0.35, 15:0.55, 16:0.45, 17:0.5, 18:0.5, 19:0.55,
  20:0.45, 21:0.45, 22:0.45, 23:0.4, 24:0.45, 25:0.5 };

// 相机基线（球坐标，绕 look 点）。presetOrbit() 里直接用：
// position = look + r * (cos(pitch)·sin(yaw), sin(pitch), cos(pitch)·cos(yaw))
export const PRESET_ORBIT = {
  13:{ r:8.5,  pitch:0.18, look:[0,-0.2,0],   orbit:0,     sway:0.15 },
  14:{ r:9,    pitch:0.12, look:[0,-0.2,0],   orbit:0.02,  sway:0.1  },
  15:{ r:9,    pitch:0.1,  look:[0,-0.4,-0.6],orbit:0.03,  sway:0    },
  16:{ r:9.6,  pitch:0.24, look:[0,-0.6,0],   orbit:0.015, sway:0.12 },
  17:{ r:8.8,  pitch:0.28, look:[0,-0.5,0],   orbit:0.04,  sway:0    },
  18:{ r:8.2,  pitch:0.3,  look:[0,-0.2,0],   orbit:0.04,  sway:0    },
  19:{ r:10.5, pitch:0.16, look:[0,0.3,0],    orbit:0.02,  sway:0    },
  20:{ r:10.5, pitch:0.28, look:[0,0,0],      orbit:0.03,  sway:0    },
  21:{ r:8,    pitch:0.22, look:[0,-0.1,0],   orbit:0,     sway:0.2  },
  22:{ r:9,    pitch:0.5,  look:[0,-0.2,0],   orbit:0.03,  sway:0    },
  23:{ r:10,   pitch:0.6,  look:[0,-0.5,0],   orbit:0.02,  sway:0    },
  24:{ r:10,   pitch:0.38, look:[0,0,0],      orbit:0.03,  sway:0    },
  25:{ r:8,    pitch:0.2,  look:[0,-0.1,0],   orbit:0.02,  sway:0    },
};

export function createSollinPoints(coverTexture) {
  const g = new THREE.BufferGeometry();
  const uv = new Float32Array(COUNT * 2), seed = new Float32Array(COUNT), rnd = new Float32Array(COUNT * 3);
  for (let j = 0; j < N; j++) for (let i = 0; i < N; i++) {
    const k = j * N + i;
    uv[k*2] = (i + 0.5) / N; uv[k*2+1] = (j + 0.5) / N;
    seed[k] = Math.random(); rnd[k*3] = Math.random(); rnd[k*3+1] = Math.random(); rnd[k*3+2] = Math.random();
  }
  g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(COUNT * 3), 3)); // three 要求存在，shader 不用
  g.setAttribute('aUv', new THREE.BufferAttribute(uv, 2));
  g.setAttribute('aSeed', new THREE.BufferAttribute(seed, 1));
  g.setAttribute('aRnd', new THREE.BufferAttribute(rnd, 3));

  const material = new THREE.ShaderMaterial({
    glslVersion: THREE.GLSL3,
    vertexShader, fragmentShader,
    transparent: true, depthWrite: false, depthTest: false,
    blending: THREE.AdditiveBlending,
    uniforms: {
      uTime:{ value:0 }, uBass:{ value:0 }, uMid:{ value:0 }, uTreble:{ value:0 }, uEnergy:{ value:0 }, uBeat:{ value:0 },
      uPreset:{ value:16 }, uK:{ value:0.85 * 1.6 }, uPoint:{ value:1 }, uBurst:{ value:0 },
      uShield:{ value:0.45 }, uSizeK:{ value:1 }, uColorBoost:{ value:1.1 }, uAlpha:{ value:0.9 },
      uCover:{ value:coverTexture },
      uCoverA:{ value:new THREE.Color(0.4, 0.4, 0.6) },   // 每首歌算一次：封面平均色，提亮到亮度≈0.38
      uCoverB:{ value:new THREE.Color(0.7, 0.7, 0.9) },   // 封面最亮 15% 像素均值，提亮到≈0.7
      uAccent:{ value:new THREE.Color(0xf4d28a) },
      uCamPos:{ value:new THREE.Vector3() },              // 相机位置（点云局部坐标）—— 修复"侧面看是平面"的关键
    },
  });
  const points = new THREE.Points(g, material);
  points.frustumCulled = false;                           // 顶点在 shader 里才确定位置，不能按包围盒裁剪

  const tmp = new THREE.Vector3();
  function update({ time, bass, mid, treble, energy, beat, preset, burst, camera, renderer }) {
    const u = material.uniforms;
    u.uTime.value = time; u.uBass.value = bass; u.uMid.value = mid; u.uTreble.value = treble;
    u.uEnergy.value = energy; u.uBeat.value = beat; u.uPreset.value = preset; u.uBurst.value = burst;
    u.uShield.value = PRESET_SHIELD[preset] ?? 0.4;
    // uSizeK：与 preview.html 一致 = 画布像素高度 × 0.03
    u.uSizeK.value = renderer.domElement.height * 0.03;
    // 点云若有平移/旋转/缩放，必须换到局部坐标；没有变换时等于 camera.position
    u.uCamPos.value.copy(points.worldToLocal(tmp.copy(camera.getWorldPosition(tmp))));
  }
  return { points, material, update };
}

// 封面主色（与 preview.html 的 computePalette 相同）
export function computeCoverPalette(image) {
  const c = document.createElement('canvas'); c.width = c.height = 32;
  const g = c.getContext('2d'); g.drawImage(image, 0, 0, 32, 32);
  const d = g.getImageData(0, 0, 32, 32).data, px = [], sum = [0, 0, 0];
  for (let i = 0; i < d.length; i += 4) { const v = [d[i]/255, d[i+1]/255, d[i+2]/255];
    px.push([v, 0.2126*v[0] + 0.7152*v[1] + 0.0722*v[2]]); for (let k = 0; k < 3; k++) sum[k] += v[k]; }
  px.sort((a, b) => b[1] - a[1]);
  const n = Math.max(1, Math.floor(px.length * 0.15)), top = [0, 0, 0];
  for (let i = 0; i < n; i++) for (let k = 0; k < 3; k++) top[k] += px[i][0][k] / n;
  const lift = (v, target) => { const l = 0.2126*v[0] + 0.7152*v[1] + 0.0722*v[2];
    const m = l < target ? target / Math.max(l, 0.02) : 1; return new THREE.Color(...v.map(x => Math.min(1, x * m))); };
  return { coverA: lift(sum.map(v => v / px.length), 0.38), coverB: lift(top, 0.7) };
}
