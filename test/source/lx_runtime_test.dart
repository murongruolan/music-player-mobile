// 在真实的 QuickJS（flutter_qjs，构建时编出宿主机的动态库）里跑洛雪格式的脚本。
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyra/source/lx_runtime.dart';

/// 一个覆盖常用 API 的洛雪自定义源：lx.request、定时器、buffer、crypto、zlib、inited / request 事件。
const _script = r'''
/**
 * @name 测试源
 * @version 1.2.0
 * @author lyra
 */
const { EVENT_NAMES, request, on, send, utils, env, version, currentScriptInfo } = globalThis.lx;
const httpGet = (url, opts) => new Promise((resolve, reject) => {
  request(url, opts || {}, (err, resp, body) => err ? reject(err) : resolve({ resp, body }));
});
on(EVENT_NAMES.request, ({ source, action, info }) => {
  if (action !== 'musicUrl') return Promise.reject(new Error('action not support'));
  const id = info.musicInfo.songmid;
  if (id === 'boom') throw new Error('炸了');
  if (id === 'bad') return Promise.resolve('ftp://nope');
  return new Promise(r => setTimeout(r, 5)).then(() => httpGet('https://api.test/url?src=' + source + '&id=' + id + '&q=' + info.type, {
    method: 'POST',
    headers: { 'X-Sign': utils.crypto.md5(id + 'salt') },
    body: { buf: utils.buffer.bufToString(utils.buffer.from('hi'), 'hex') },
  })).then(({ resp, body }) => {
    if (resp.statusCode !== 200 || body.code !== 0) throw new Error('接口失败');
    return utils.zlib.deflate(utils.buffer.from(body.url)).then(z => utils.zlib.inflate(z)).then(b => b.toString());
  });
});
send(EVENT_NAMES.inited, {
  openDevTools: false,
  sources: {
    kw: { name: '酷我', type: 'music', actions: ['musicUrl'], qualitys: ['128k', '320k', 'flac'] },
    tx: { name: 'QQ', type: 'music', actions: ['musicUrl', 'lyric'], qualitys: ['128k', 'bogus'] },
    xx: { name: '未知', type: 'music', actions: ['musicUrl'], qualitys: ['128k'] },
    wy: { name: '不是音乐', type: 'video', actions: ['musicUrl'], qualitys: ['128k'] },
  },
  info: [env, version, currentScriptInfo.name, typeof utils.crypto.aesEncrypt(utils.buffer.from('a'), 'aes-128-ecb', utils.buffer.from('0123456789abcdef'), '').toString('base64')],
});
''';

MockClient _api(List<http.Request> seen) => MockClient((r) async {
      seen.add(r);
      final id = r.url.queryParameters['id'];
      return http.Response(jsonEncode({'code': 0, 'url': 'https://cdn.test/${r.url.queryParameters['src']}/$id.${r.url.queryParameters['q']}.mp3'}), 200, headers: {'content-type': 'application/json'});
    });

void main() {
  test('初始化：只保留支持的平台、动作和音质', () async {
    final rt = await LxRuntime.start(_script, info: const LxScriptInfo(name: '测试源'), client: _api([]));
    addTearDown(rt.dispose);
    expect(rt.capabilities.keys, unorderedEquals(['kw', 'tx']));
    expect(rt.capabilities['kw']!.qualities, ['128k', '320k', 'flac']);
    expect(rt.capabilities['tx']!.actions, ['musicUrl']); // lyric 只允许本地平台
    expect(rt.capabilities['tx']!.qualities, ['128k']);
  });

  test('解析播放地址：请求、签名、定时器、zlib 都在沙箱里跑通', () async {
    final seen = <http.Request>[];
    final rt = await LxRuntime.start(_script, client: _api(seen));
    addTearDown(rt.dispose);
    final url = await rt.request('musicUrl', 'kw', {'songmid': '123'}, quality: '320k');
    expect(url, 'https://cdn.test/kw/123.320k.mp3');
    expect(seen.single.method, 'POST');
    expect(seen.single.headers['X-Sign'], '0dde5185db7da5c81f0fa71696506e4f');
    expect(jsonDecode(seen.single.body), {'buf': '6869'});
    // 并发两个请求互不干扰
    final both = await Future.wait([rt.request('musicUrl', 'kw', {'songmid': 'a'}, quality: '128k'), rt.request('musicUrl', 'tx', {'songmid': 'b'}, quality: '128k')]);
    expect(both, ['https://cdn.test/kw/a.128k.mp3', 'https://cdn.test/tx/b.128k.mp3']);
  });

  test('脚本报错 / 返回非法地址都变成 LxException', () async {
    final rt = await LxRuntime.start(_script, client: _api([]));
    addTearDown(rt.dispose);
    await expectLater(rt.request('musicUrl', 'kw', {'songmid': 'boom'}, quality: '128k'), throwsA(isA<LxException>().having((e) => e.message, 'message', contains('炸了'))));
    await expectLater(rt.request('musicUrl', 'kw', {'songmid': 'bad'}, quality: '128k'), throwsA(isA<LxException>().having((e) => e.message, 'message', contains('播放地址无效'))));
    await expectLater(rt.request('lyric', 'kw', {'songmid': '1'}), throwsA(isA<LxException>()));
  });

  test('语法错误、不初始化、死循环都会被拦下', () async {
    await expectLater(LxRuntime.start('const = ;', client: _api([])), throwsA(isA<LxException>().having((e) => e.message, 'message', contains('脚本执行出错'))));
    await expectLater(LxRuntime.start('globalThis.lx.on("request", () => 1);', client: _api([]), initTimeout: const Duration(milliseconds: 300)), throwsA(isA<LxException>().having((e) => e.message, 'message', contains('超时'))));
    await expectLater(LxRuntime.start('globalThis.lx.send("inited", {sources: {}});', client: _api([])), throwsA(isA<LxException>().having((e) => e.message, 'message', contains('平台'))));
    await expectLater(LxRuntime.start('while (true) {}', client: _api([])), throwsA(isA<LxException>()));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('MD5 签名与 Dart 侧一致（脚本里算的值经 header 传出来）', () async {
    final seen = <http.Request>[];
    final rt = await LxRuntime.start(_script, client: _api(seen));
    addTearDown(rt.dispose);
    await rt.request('musicUrl', 'kw', {'songmid': '777'}, quality: '128k');
    // md5('777salt')
    expect(seen.single.headers['X-Sign'], '28a7ae3437326f5f928f5c0bce7bbe7e');
  });
}
