// 洛雪（LX Music）自定义源脚本的运行环境：在 QuickJS 里提供 `globalThis.lx`。
//
// 对齐桌面端 source-worker.ts 的 createLxApi（desktop 分支），接口与 lx-music-mobile 的
// 自定义源 API 一致：lx.request / lx.send / lx.on / lx.utils.{crypto,buffer,zlib} / lx.version / lx.env。
//
// 与 Dart 的桥（由 lx_runtime.dart 在执行本段之前挂到全局）：
//   __lx_native(op, arg)            同步：md5 / aes / rsa / randomBytes，参数与返回值都是字符串（base64 / hex）
//   __lx_http(id, url, optionsJson) 异步：返回 Promise<string>（响应 JSON）
//   __lx_http_cancel(id)            取消请求
//   __lx_zlib(op, base64)           异步：inflate / deflate，返回 Promise<string>（base64）
//   __lx_sleep(ms)                  异步：定时器
//   __lx_event(name, json)          inited / updateAlert
// 字节在桥上一律用 base64 传，避免不同引擎之间 ArrayBuffer 转换的差异。
const lxPrelude = r'''
(function () {
  'use strict';
  var G = globalThis;
  var native = G.__lx_native, http = G.__lx_http, httpCancel = G.__lx_http_cancel,
      zlib = G.__lx_zlib, sleep = G.__lx_sleep, emit = G.__lx_event;

  // ---------------------------------------------------------------- 编解码
  var B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  var B64R = {};
  for (var i = 0; i < 64; i++) B64R[B64.charAt(i)] = i;
  B64R['-'] = 62; B64R['_'] = 63;

  function utf8Encode(str) {
    str = String(str);
    var out = [];
    for (var i = 0; i < str.length; i++) {
      var c = str.charCodeAt(i);
      if (c >= 0xd800 && c <= 0xdbff && i + 1 < str.length) {
        var d = str.charCodeAt(i + 1);
        if (d >= 0xdc00 && d <= 0xdfff) { c = 0x10000 + ((c - 0xd800) << 10) + (d - 0xdc00); i++; }
      }
      if (c < 0x80) out.push(c);
      else if (c < 0x800) out.push(0xc0 | (c >> 6), 0x80 | (c & 63));
      else if (c < 0x10000) out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
      else out.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
    }
    return new Uint8Array(out);
  }
  function utf8Decode(bytes) {
    var out = '', i = 0;
    while (i < bytes.length) {
      var c = bytes[i++];
      if (c < 0x80) { out += String.fromCharCode(c); continue; }
      var n = c >= 0xf0 ? 3 : c >= 0xe0 ? 2 : c >= 0xc0 ? 1 : 0;
      var cp = n === 3 ? c & 7 : n === 2 ? c & 15 : c & 31;
      for (var k = 0; k < n && i < bytes.length; k++) cp = (cp << 6) | (bytes[i++] & 63);
      if (n === 0) cp = 0xfffd;
      if (cp >= 0x10000) { cp -= 0x10000; out += String.fromCharCode(0xd800 + (cp >> 10), 0xdc00 + (cp & 1023)); }
      else out += String.fromCharCode(cp);
    }
    return out;
  }
  function b64Encode(bytes) {
    var out = '', i;
    for (i = 0; i + 2 < bytes.length; i += 3) {
      var n = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
      out += B64.charAt(n >> 18) + B64.charAt((n >> 12) & 63) + B64.charAt((n >> 6) & 63) + B64.charAt(n & 63);
    }
    var rest = bytes.length - i;
    if (rest === 1) { var a = bytes[i] << 16; out += B64.charAt(a >> 18) + B64.charAt((a >> 12) & 63) + '=='; }
    else if (rest === 2) { var b = (bytes[i] << 16) | (bytes[i + 1] << 8); out += B64.charAt(b >> 18) + B64.charAt((b >> 12) & 63) + B64.charAt((b >> 6) & 63) + '='; }
    return out;
  }
  function b64Decode(str) {
    str = String(str).replace(/[^A-Za-z0-9+/\-_]/g, '');
    var out = [], buf = 0, bits = 0;
    for (var i = 0; i < str.length; i++) {
      buf = (buf << 6) | B64R[str.charAt(i)]; bits += 6;
      if (bits >= 8) { bits -= 8; out.push((buf >> bits) & 255); }
    }
    return new Uint8Array(out);
  }
  function hexEncode(bytes) {
    var out = '';
    for (var i = 0; i < bytes.length; i++) out += (bytes[i] < 16 ? '0' : '') + bytes[i].toString(16);
    return out;
  }
  function hexDecode(str) {
    str = String(str);
    var out = new Uint8Array(str.length >> 1);
    for (var i = 0; i < out.length; i++) out[i] = parseInt(str.substr(i * 2, 2), 16);
    return out;
  }

  // ---------------------------------------------------------------- Buffer（够脚本用的最小实现）
  function LxBuffer(arg) { return LxBuffer.from(arg); }
  function wrap(u8) { Object.setPrototypeOf(u8, LxBuffer.prototype); return u8; }
  LxBuffer.prototype = Object.create(Uint8Array.prototype);
  LxBuffer.prototype.constructor = LxBuffer;
  LxBuffer.prototype.toString = function (enc) {
    enc = (enc || 'utf8').toLowerCase();
    var u8 = new Uint8Array(this.buffer, this.byteOffset, this.byteLength);
    if (enc === 'hex') return hexEncode(u8);
    if (enc === 'base64') return b64Encode(u8);
    if (enc === 'binary' || enc === 'latin1' || enc === 'ascii') { var s = ''; for (var i = 0; i < u8.length; i++) s += String.fromCharCode(u8[i]); return s; }
    return utf8Decode(u8);
  };
  LxBuffer.prototype.toJSON = function () { return { type: 'Buffer', data: Array.prototype.slice.call(this) }; };
  LxBuffer.prototype.slice = LxBuffer.prototype.subarray = function (s, e) {
    return wrap(new Uint8Array(this.buffer, this.byteOffset, this.byteLength).slice(s, e));
  };
  LxBuffer.from = function (value, enc) {
    if (value instanceof ArrayBuffer) return wrap(new Uint8Array(value.slice(0)));
    if (ArrayBuffer.isView(value)) return wrap(new Uint8Array(value.buffer.slice(value.byteOffset, value.byteOffset + value.byteLength)));
    if (Array.isArray(value)) return wrap(new Uint8Array(value));
    if (value && value.type === 'Buffer' && Array.isArray(value.data)) return wrap(new Uint8Array(value.data));
    enc = (enc || 'utf8').toLowerCase();
    if (enc === 'hex') return wrap(hexDecode(value));
    if (enc === 'base64') return wrap(b64Decode(value));
    if (enc === 'binary' || enc === 'latin1' || enc === 'ascii') { var s = String(value), u = new Uint8Array(s.length); for (var i = 0; i < s.length; i++) u[i] = s.charCodeAt(i) & 255; return wrap(u); }
    return wrap(utf8Encode(value));
  };
  LxBuffer.alloc = function (n, fill) { var u = new Uint8Array(n); if (fill) u.fill(fill); return wrap(u); };
  LxBuffer.isBuffer = function (v) { return v instanceof LxBuffer; };
  LxBuffer.byteLength = function (v, enc) { return LxBuffer.from(v, enc).length; };
  LxBuffer.concat = function (list) {
    var len = 0, i;
    for (i = 0; i < list.length; i++) len += list[i].length;
    var out = new Uint8Array(len), o = 0;
    for (i = 0; i < list.length; i++) { out.set(list[i], o); o += list[i].length; }
    return wrap(out);
  };
  function toBytes(v) { return typeof v === 'string' ? utf8Encode(v) : LxBuffer.from(v); }
  function toB64(v) { return b64Encode(toBytes(v)); }

  // ---------------------------------------------------------------- 定时器
  var timerSeq = 0, timers = {};
  G.setTimeout = function (fn, ms) {
    var id = ++timerSeq, args = Array.prototype.slice.call(arguments, 2);
    timers[id] = true;
    sleep(Math.max(0, Math.min(Number(ms) || 0, 600000))).then(function () {
      if (!timers[id]) return;
      delete timers[id];
      if (typeof fn === 'function') fn.apply(null, args);
    });
    return id;
  };
  G.clearTimeout = function (id) { delete timers[id]; };
  G.setInterval = function (fn, ms) {
    var id = ++timerSeq;
    timers[id] = true;
    var tick = function () {
      sleep(Math.max(10, Number(ms) || 0)).then(function () {
        if (!timers[id]) return;
        fn();
        tick();
      });
    };
    tick();
    return id;
  };
  G.clearInterval = G.clearTimeout;

  // ---------------------------------------------------------------- 其它全局
  var noop = function () {};
  G.console = { log: noop, info: noop, warn: noop, error: noop, debug: noop, trace: noop, group: noop, groupEnd: noop, table: noop, time: noop, timeEnd: noop, assert: noop, dir: noop };
  G.TextEncoder = function () {};
  G.TextEncoder.prototype.encode = function (s) { return utf8Encode(s === undefined ? '' : s); };
  G.TextDecoder = function () {};
  G.TextDecoder.prototype.decode = function (b) { return b ? utf8Decode(new Uint8Array(b.buffer || b, b.byteOffset || 0, b.byteLength)) : ''; };
  G.btoa = function (s) { s = String(s); var u = new Uint8Array(s.length); for (var i = 0; i < s.length; i++) u[i] = s.charCodeAt(i) & 255; return b64Encode(u); };
  G.atob = function (s) { var u = b64Decode(s), out = ''; for (var i = 0; i < u.length; i++) out += String.fromCharCode(u[i]); return out; };
  G.window = G; G.self = G;

  // ---------------------------------------------------------------- lx
  var handler = null, inited = false, updateSent = false, httpSeq = 0;
  var info = G.__lx_script_info || {};

  function request(url, options, callback) {
    if (typeof options === 'function') { callback = options; options = {}; }
    options = options || {};
    callback = typeof callback === 'function' ? callback : noop;
    if (!/^https?:\/\//i.test(String(url)) || String(url).length > 2048) {
      Promise.resolve().then(function () { callback(new Error('Only HTTP(S) requests are allowed'), null, null); });
      return noop;
    }
    var id = 'h' + (++httpSeq), done = false;
    var opts = {};
    for (var k in options) {
      var v = options[k];
      if (typeof v === 'function') continue;
      opts[k] = (v instanceof Uint8Array) ? { __b64: b64Encode(v) } : v;
    }
    http(id, String(url), JSON.stringify(opts)).then(function (text) {
      if (done) return;
      done = true;
      var r = JSON.parse(text);
      if (r.error) return callback(new Error(r.error), null, null);
      var resp = r.response;
      if (resp.raw) resp.raw = LxBuffer.from(resp.raw, 'base64');
      callback(null, resp, resp.body);
    }, function (e) {
      if (done) return;
      done = true;
      callback(new Error(String(e && e.message || e)), null, null);
    });
    return function () { if (!done) { done = true; httpCancel(id); } };
  }

  var lx = {
    EVENT_NAMES: Object.freeze({ request: 'request', inited: 'inited', updateAlert: 'updateAlert' }),
    request: request,
    send: function (name, data) {
      if (name === 'inited') {
        if (inited) return Promise.reject(new Error('Script is already initialized'));
        inited = true;
        emit('inited', JSON.stringify(data === undefined ? null : data));
        return Promise.resolve();
      }
      if (name === 'updateAlert') {
        if (updateSent) return Promise.reject(new Error('Update alert can only be sent once'));
        updateSent = true;
        emit('updateAlert', JSON.stringify(data === undefined ? null : data));
        return Promise.resolve();
      }
      return Promise.reject(new Error('Unsupported event: ' + name));
    },
    on: function (name, fn) {
      if (name !== 'request' || typeof fn !== 'function') return Promise.reject(new Error('Unsupported event handler'));
      handler = fn;
      return Promise.resolve();
    },
    utils: Object.freeze({
      crypto: Object.freeze({
        aesEncrypt: function (data, mode, key, iv) {
          return LxBuffer.from(native('aes', JSON.stringify({ data: toB64(data), mode: String(mode), key: toB64(key), iv: iv == null ? '' : toB64(iv) })), 'base64');
        },
        rsaEncrypt: function (data, key) {
          return LxBuffer.from(native('rsa', JSON.stringify({ data: toB64(data), key: String(key) })), 'base64');
        },
        randomBytes: function (size) {
          return LxBuffer.from(native('random', String(Math.min(Math.max(Number(size) || 0, 0), 65536))), 'base64');
        },
        md5: function (value) { return native('md5', toB64(value)); }
      }),
      buffer: Object.freeze({
        from: function (a, b) { return LxBuffer.from(a, b); },
        bufToString: function (buf, format) { return LxBuffer.from(buf).toString(format); }
      }),
      zlib: Object.freeze({
        inflate: function (data) { return zlib('inflate', toB64(data)).then(function (r) { return LxBuffer.from(r, 'base64'); }); },
        deflate: function (data) { return zlib('deflate', toB64(data)).then(function (r) { return LxBuffer.from(r, 'base64'); }); }
      })
    }),
    currentScriptInfo: Object.freeze({
      name: info.name || '', description: info.description || '', version: info.version || '',
      author: info.author || '', homepage: info.homepage || '', rawScript: info.rawScript || ''
    }),
    version: '2.1.0',
    env: 'mobile'
  };
  G.lx = Object.freeze(lx);

  // Dart 调用：执行一次脚本的 request 处理器，返回 Promise
  G.__lx_dispatch = function (payloadJson) {
    if (!handler) return Promise.reject(new Error('Source request handler is not initialized'));
    var p = JSON.parse(payloadJson);
    var res;
    try { res = handler({ source: p.source, action: p.action, info: p.info }); }
    catch (e) { return Promise.reject(e); }
    return Promise.resolve(res).then(function (v) {
      return JSON.stringify({ value: v === undefined ? null : v });
    });
  };

  // 不让脚本拿到桥函数（lx 已经持有引用）
  ['__lx_native', '__lx_http', '__lx_http_cancel', '__lx_zlib', '__lx_sleep', '__lx_event', '__lx_script_info'].forEach(function (k) {
    try { delete G[k]; } catch (e) {}
  });
})();
''';
