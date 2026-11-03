/* 设置相关二级页。字段名与调研文档的设置项一一对应（见 DESIGN.md 第 7 节映射表）。 */
const barPv = k => {
  const items = n => Array.from({ length:n }, (_, i) => `<i style="flex:1;height:6px;margin:auto 3px;border-radius:3px;background:${i === 0 ? 'var(--accent)' : 'var(--t4)'}"></i>`).join('');
  const P = {
    liquid:`<div class="bpv liquid"><b class="drop"></b>${items(5)}</div>`,
    island:`<div class="bpv island"><b class="pill"></b>${items(5)}</div>`,
    capsule:`<div class="bpv capsule"><b class="pill solid"></b>${items(4)}</div><div class="bpv-fab"></div>`,
    frosted:`<div class="bpv frosted"><div class="bpv-mini"></div><div style="display:flex;height:14px">${items(5)}</div></div>`,
    classic:`<div class="bpv classic"><b class="line"></b>${items(5)}</div>`,
  };
  const mini = k === 'frosted' ? '' : `<div style="position:absolute;left:8px;right:8px;bottom:${k === 'classic' ? 26 : 30}px;height:11px;border-radius:5px;background:var(--s3)"></div>`;
  return `<div class="pv">${mini}${P[k]}</div>`;
};

PAGES.appearance = { render:() => `${appBar('外观与界面')}
  ${group('主题', [`<div style="padding:12px 14px 4px">${seg(['深色', '浅色', '跟随系统'], S.theme === 'dark' ? '深色' : '浅色', 'themeCN')}</div>`,
    `<div class="it noic" style="min-height:40px"><div class="lb"><b>主题色</b><small>按钮、进度条、选中态与歌词高亮，实时生效</small></div></div>`,
    `<div class="swatches">${ACCENTS.map((a, i) => `<button class="${S.accent === i ? 'on' : ''}" style="background:${a.c}" data-act="accent" data-v="${i}" title="${a.n}"></button>`).join('')}</div>`])}
  ${group('底部导航样式', [barRow(),
    item({ icon:'down', color:'blue', label:'滚动时自动收起', sub:'向下滚动时底栏收成小圆钮，迷你播放条并入同一行', sw:'navAutoMin' })],
    BAR_DESC[S.bar])}
  ${group('播放器', [
    item({ icon:'vinyl', color:'violet', label:'播放器皮肤', sub:SKINS.find(s => s.id === S.skin).d, val:SKINS.find(s => s.id === S.skin).n, act:'sheet', args:{ v:'skin' } }),
    item({ icon:'layers', color:'blue', label:'播放器背景', sub:SKINS.find(s => s.id === S.skin).bg ? '律动、声波、唱片、舞台使用' : `当前皮肤「${SKINS.find(s => s.id === S.skin).n}」自带背景，不受此项影响`, val:{ blur:'模糊封面', static:'静态流光', flow:'动态流光' }[S.bg], act:'sheet', args:{ v:'bg' } }),
    item({ icon:'phone', color:'gold', label:'横屏充电时进入待机', sub:'手机横放并充电时，自动切到「待机」皮肤', sw:'autoOpen' }),
    item({ icon:'sun', color:'orange', label:'播放页屏幕常亮', sw:'keepAwake' }),
  ])}
  ${group('界面', [
    item({ icon:'font', color:'teal', label:'界面字体', val:FONTS.find(f => f.id === S.font).n, act:'sheet', args:{ v:'fonts' } }),
    `<div class="it" data-act="sheet" data-v="appIcon">${appIconSvg(S.appIcon, 30)}<div class="lb"><b>App 图标</b></div><div class="val">${APP_ICONS.find(a => a.id === S.appIcon).n}${ic('right')}</div></div>`,
    item({ icon:'compass', color:'cyan', label:'首页内容与顺序', val:`${S.homeMods.filter(m => m.on).length} 个模块`, act:'sheet', args:{ v:'homeOrder' } }),
    item({ icon:'zap', color:'green', label:'触感反馈', sw:'haptics' }),
    item({ icon:'eye', color:'gray', label:'减少动态效果', sub:'关闭形变、弹簧、流光等动画', sw:'reduceMotion' }),
  ])}` };
ACT.themeCN = d => { S.theme = d.v === '浅色' ? 'light' : 'dark'; render(); };

PAGES.lyrics = { render:() => `${appBar('歌词')}
  <div class="m lpv" style="height:170px;border-radius:22px;overflow:hidden;position:relative;margin-bottom:14px;background:#0B0C12;--lfs:${S.set.lfs}px;--ltfs:${S.set.ltfs}px">
    <div class="pbg"><div class="flow">${flowBlobs(song())}</div><div class="shade" style="--shade:.4"></div></div>
    <div style="position:absolute;inset:0;display:flex;flex-direction:column;justify-content:center;padding:0 20px" class="${S.set.glow ? 'glowOn' : ''}">
      <div class="ll" style="padding:4px 0;${S.set.blur ? 'filter:blur(1.2px)' : ''}">${LYRICS[5].o}</div>
      <div class="ll on" style="padding:4px 0">${S.set.roma ? '<span class="ro">ye hang de xing tu</span>' : ''}<span class="w" style="--p:.55">${LYRICS[6].o}</span>${S.set.trans ? `<span class="tr">${LYRICS[6].tr}</span>` : ''}</div>
      <div class="ll" style="padding:4px 0;${S.set.blur ? 'filter:blur(1.2px)' : ''}">${LYRICS[7].o}</div></div></div>
  ${group('显示', [
    item({ icon:'globe', color:'blue', label:'显示翻译', sw:'trans' }),
    item({ icon:'font', color:'violet', label:'显示罗马音', sw:'roma' }),
    item({ icon:'refresh', color:'teal', label:'简繁转换', sub:'按系统语言自动转换', sw:'conv' }),
    item({ icon:'eye', color:'gray', label:'非当前行模糊', sw:'blur' }),
    item({ icon:'sparkle', color:'gold', label:'逐字辉光', sub:'有逐字时间轴时按字填充，否则按行均匀插值', sw:'glow' }),
  ])}
  ${group('字号与间距', [slider('正文', 'lfs', 16, 40, 1, 'px'), slider('翻译', 'ltfs', 11, 22, 1, 'px'), slider('行距', 'lgap', 4, 24, 1, 'px')])}
  ${group('时间', [slider('整体偏移', 'loff', -3, 3, .1, 's', v => (v > 0 ? '+' : '') + (+v).toFixed(1) + 's')], '正值 = 歌词提前出现。也可在播放页「歌词快调」里按 0.5 秒微调')}
  ${group('来源', [
    item({ icon:'layers', color:'orange', label:'歌词来源优先级', val:'内置 → 平台 → 本地', act:'toast', args:{ msg:'长按拖动调整顺序', icon:'drag' } }),
    item({ icon:'folder', color:'green', label:'读取同名 .lrc 文件', sub:'本地音乐优先使用同目录歌词', sw:'cache' }),
  ])}` };

PAGES.syslyrics = { render:() => `${appBar('系统歌词')}
  <div class="m" style="height:120px;border-radius:22px;position:relative;overflow:hidden;margin-bottom:14px;background:linear-gradient(160deg,#2d3a5c,#141826)">
    <div style="position:absolute;left:14px;right:14px;top:34px;padding:10px 14px;border-radius:14px;background:rgba(0,0,0,.45);backdrop-filter:blur(12px);display:flex;align-items:center;gap:10px;color:#fff">
      ${appIcon(26)}<div style="flex:1;font-weight:700;font-size:15px">${LYRICS[6].o}</div>${ic(S.set.floatLock ? 'lock' : 'drag')}</div>
    <div style="position:absolute;left:16px;bottom:10px;font-size:11px;color:rgba(255,255,255,.55)">桌面悬浮歌词预览</div></div>
  ${group('悬浮歌词（Android）', [
    item({ icon:'layers', color:'violet', label:'桌面悬浮歌词', sub:'需要「显示在其他应用上层」权限', sw:'floatLyric' }),
    item({ icon:'lock', color:'gray', label:'锁定位置', sub:'锁定后点击穿透，不影响其他应用', sw:'floatLock' }),
    item({ icon:'palette', color:'pink', label:'样式', val:'圆角卡片 · 18px', act:'toast', args:{ msg:'可调整字号、颜色和背景透明度', icon:'palette' } }),
  ])}
  ${group('车机与蓝牙', [
    item({ icon:'bluetooth', color:'blue', label:'蓝牙歌词推送', sub:'把当前行写入蓝牙媒体信息，车机屏幕可见', sw:'btLyric' }),
    item({ icon:'car', color:'teal', label:'推送顺序', val:'歌词 · 歌名', act:'toast', args:{ msg:'可选：仅歌词 / 歌词·歌名 / 歌名·歌词', icon:'car' } }),
  ])}
  ${group('状态栏', [item({ icon:'phone', color:'orange', label:'状态栏歌词', sub:'仅部分 Android 定制系统支持', sw:'sbLyric' })])}` };

PAGES.playback = { render:() => `${appBar('播放与音质')}
  ${group('音质', [
    item({ icon:'hd', color:'orange', label:'在线播放音质', val:S.quality, act:'sheet', args:{ v:'quality' } }),
    item({ icon:'download', color:'blue', label:'下载音质', val:'Hi-Res', act:'sheet', args:{ v:'quality' } }),
    item({ icon:'wifi', color:'cyan', label:'移动网络使用较低音质', sub:'非 Wi-Fi 时自动使用 HQ', sw:'wifiOnly' }),
    item({ icon:'down', color:'gray', label:'不可用时自动降级', sw:'allowDown' }),
  ])}
  ${group('播放行为', [
    item({ icon:'repeat', color:'violet', label:'默认播放模式', val:{ loop:'列表循环', one:'单曲循环', shuffle:'随机', order:'顺序' }[S.mode], act:'mode' }),
    item({ icon:'speed', color:'teal', label:'播放速度', val:S.speed.toFixed(2) + '×', act:'sheet', args:{ v:'speed' } }),
    item({ icon:'wave', color:'green', label:'淡入淡出', sub:'切歌与暂停时 400ms 交叉淡化', sw:'fade' }),
    item({ icon:'play', color:'orange', label:'启动时自动播放', sw:'autoplay' }),
    item({ icon:'up', color:'pink', label:'启动时打开播放页', sw:'autoOpen' }),
    item({ icon:'cloud', color:'blue', label:'边听边缓存', sub:'已缓存 1.8 GB · 上限 4 GB', sw:'cache' }),
  ])}
  ${group('高级', [
    item({ icon:'zap', color:'gold', label:'智能换源', val:S.set.smart ? '已开启' : '已关闭', act:'push', args:{ v:'smart' } }),
    item({ icon:'sliders', color:'teal', label:'均衡器', val:S.eqOn ? S.eqPreset : '关闭', act:'sheet', args:{ v:'eq' } }),
    item({ icon:'moon', color:'violet', label:'睡眠定时', val:S.timer ? S.timer + ' 分钟' : '关闭', act:'sheet', args:{ v:'timer' } }),
    item({ icon:'code', color:'gray', label:'播放链路', sub:'查看当前歌曲的取流与换源记录', act:'sheet', args:{ v:'trace' } }),
  ])}` };

PAGES.smart = { render:() => `${appBar('智能换源')}
  <div class="note">${ic('zap')}<span>当前音源无法播放时，按下面的顺序自动尝试，尽量不打断聆听。每次换源都会在播放页顶部提示。</span></div>
  ${group('', [item({ icon:'zap', color:'gold', label:'启用智能换源', sw:'smart' })])}
  ${S.set.smart ? `
  ${group('策略（按顺序执行）', [
    item({ icon:'down', color:'orange', label:'① 逐级降低音质', sub:'Hi-Res → SQ → HQ → 128k', sw:'gradual' }),
    item({ icon:'code', color:'violet', label:'② 换用其他脚本源', sub:'按下方脚本顺序依次尝试', sw:'crossScript' }),
    item({ icon:'globe', color:'blue', label:'③ 跨平台搜索同名歌曲', sub:'按下方平台顺序匹配歌名 + 歌手 + 时长', sw:'crossPlat' }),
    item({ icon:'next', color:'red', label:'④ 全部失败时播放下一首', sw:'autoNext' }),
  ])}
  ${group('解析脚本顺序（' + plat().n + '）', scriptsOf(S.plat).map((sc, i) => `<div class="it"><div class="tile" style="background:var(--s3);color:var(--t2)">${ic('drag')}</div><div class="lb"><b>${sc.n}</b><small>成功率 ${sc.ok}% · 平均 ${sc.ms}ms</small></div>${signal(sc.ms)}<div class="sw ${i < 2 ? 'on' : ''}" style="margin-left:10px"></div></div>`), '每个平台有自己的脚本顺序，在「平台与解析脚本」里切换平台')}
  ${group('跨平台顺序', PLATFORMS.map((p, i) => `<div class="it">${platBadge(p, 30)}<div class="lb"><b>${p.n}</b><small>${scriptsOf(p.id).length} 个可用脚本</small></div><div class="val" style="gap:8px">${i + 1}<span style="color:var(--t3)">${ic('drag')}</span></div></div>`), '按住右侧拖动排序')}
  ${group('提醒', [item({ label:'音质降级时提醒', sw:'nQ' }), item({ label:'切换脚本源时提醒', sw:'nS' }), item({ label:'自动跳到下一首时提醒', sw:'nA' })])}` : ''}` };

PAGES.download = { render:() => `${appBar('下载')}
  <div class="grp-t" style="padding-left:var(--pad)">正在下载 · 2</div>
  ${[[13, .62, '12.4 / 20.1 MB'], [20, .18, '6.0 / 33.6 MB']].map(([id, p, t]) => { const s = SONGS[id]; return `<div class="row">${cover(s)}<div class="tx"><div class="t">${s.t}</div><div style="height:4px;border-radius:2px;background:var(--s3);margin-top:8px;overflow:hidden"><div style="width:${p * 100}%;height:100%;background:var(--accent)"></div></div><div class="s" style="margin-top:5px">${t} · ${s.q}</div></div><button class="ib" style="color:var(--t3)">${ic('pause')}</button></div>`; }).join('')}
  ${group('设置', [
    slider('同时下载', 'dlConc', 1, 8, 1),
    item({ icon:'edit', color:'violet', label:'文件命名', val:'歌名 - 歌手', act:'toast', args:{ msg:'可选顺序与分隔符，非法字符自动替换', icon:'edit' } }),
    item({ icon:'album', color:'orange', label:'内嵌封面与标签', sub:'FLAC / MP3 / M4A 自动写入元数据', sw:'dlCover' }),
    item({ icon:'quote', color:'pink', label:'另存歌词与封面文件', sub:'同目录生成 .lrc 与 cover.jpg', sw:'dlLyric' }),
    item({ icon:'folder', color:'blue', label:'保存位置', val:'/Music/Lyra', act:'toast', args:{ msg:'选择文件夹', icon:'folder' } }),
    item({ icon:'wifi', color:'cyan', label:'仅 Wi-Fi 下载', sw:'wifiOnly' }),
  ])}` };

PAGES.sources = { render:() => `${appBar('平台与解析脚本', { right:`<button class="ib" data-act="sheet" data-v="import">${ic('plus')}</button>` })}
  <div class="note">${ic('info')}<span>先选音乐平台，再选该平台的解析脚本。脚本由你自行导入，Lyra 只负责调度和播放，请仅使用你有权访问的内容。</span></div>
  <div class="grp-t">当前</div><div style="padding:0 var(--pad) 6px">${srcBar()}</div>
  ${PLATFORMS.map(p => group('', [`<div class="it" data-act="plat" data-v="${p.id}">${platBadge(p, 30)}<div class="lb"><b>${p.n}</b><small>${isIn(p.id) ? '已登录 · ' + S.platLogin[p.id] : '未登录 · 每日推荐与个人歌单不可用'}</small></div>${p.id === S.plat ? '<span class="badge acc">当前</span>' : ''}</div>`,
    ...scriptsOf(p.id).map(sc => `<div class="it noic" style="padding-left:56px"><div class="lb"><b style="font-size:14px">${sc.n} <span style="color:var(--t3);font-size:12px">v${sc.v}</span></b><small>${sc.q.join(' · ')} · 成功率 ${sc.ok}%</small></div>${signal(sc.ms)}<span style="width:46px;text-align:right;font:600 12px var(--font-num);color:var(--t3)">${sc.ms}ms</span></div>`)])).join('')}
  ${group('', [item({ icon:'plus', color:'blue', label:'导入解析脚本', sub:'从文件、链接或剪贴板导入', act:'sheet', args:{ v:'import' } })])}` };

PAGES.accounts3p = { render:() => `${appBar('平台账号')}
  <div class="note">${ic('link')}<span>登录平台账号后可同步该平台的收藏、歌单与每日推荐。账号凭据只保存在本机。</span></div>
  ${group('平台', PLATFORMS.map(p => `<div class="it">${platBadge(p, 30)}<div class="lb"><b>${p.n}</b><small>${p.login ? '已登录 · ' + p.login : '未登录'}</small></div><button class="btn ${p.login ? 'sec' : 'pri'} sm" data-act="toast" data-msg="${p.login ? '已退出 ' + p.n : '请在弹出的页面中完成登录'}" data-icon="link">${p.login ? '退出' : '登录'}</button></div>`))}
  ${group('登录方式', [item({ icon:'scan', color:'violet', label:'扫码登录', sub:'用对应平台 App 扫码', act:'toast', args:{ msg:'请用对应 App 扫码', icon:'scan' } }), item({ icon:'phone', color:'orange', label:'手机号登录', act:'toast', args:{ msg:'发送验证码', icon:'phone' } }), item({ icon:'code', color:'gray', label:'导入 Cookie', sub:'高级：从浏览器复制', act:'toast', args:{ msg:'粘贴 Cookie 字符串', icon:'code' } })])}` };

PAGES.account = { render:() => `${appBar('账号中心')}
  <div style="text-align:center;padding:4px 0 18px"><div class="avatar lg" style="width:84px;height:84px;border-radius:42px;font-size:34px;margin:0 auto">栗</div>
    <b style="display:block;font-size:20px;margin-top:12px">阿栗</b><div style="font-size:12.5px;color:var(--t2);margin-top:3px">UID 10086427</div>
    <div style="display:flex;gap:6px;justify-content:center;margin-top:10px"><span class="badge acc">${ic('crown')}已激活 · 永久</span></div></div>
  ${group('资料', [item({ icon:'user', color:'blue', label:'昵称与头像', val:'阿栗', act:'toast', args:{ msg:'编辑资料', icon:'edit' } }), item({ icon:'mail', color:'orange', label:'邮箱', val:'ali@example.com' }), item({ icon:'lock', color:'gray', label:'修改密码', act:'toast', args:{ msg:'验证码已发送至邮箱', icon:'mail' } }), item({ icon:'link', color:'cyan', label:'QQ 绑定', val:'未绑定', act:'toast', args:{ msg:'跳转 QQ 授权', icon:'link' } })])}
  ${group('会员', [item({ icon:'key', color:'gold', label:'激活码', sub:'输入激活码解锁全部功能', act:'sheet', args:{ v:'activate' } }), item({ icon:'crown', color:'pink', label:'会员权益', val:'6 项', act:'toast', args:{ msg:'Hi-Res 下载 · 粒子皮肤 · 云同步 …', icon:'crown' } })])}
  ${group('安全', [item({ icon:'phone', color:'violet', label:'登录设备', val:'3 台', act:'push', args:{ v:'devices' } }), item({ icon:'scan', color:'teal', label:'扫码登录电视 / 车机 / 桌面端', act:'openScan', args:{ v:'scan' } })])}
  ${group('', [item({ icon:'logout', color:'red', label:'退出登录', danger:true, chev:false, act:'dialog', args:{ v:'logout' } })])}` };

PAGES.devices = { render:() => `${appBar('登录设备')}
  <p class="hint" style="padding:0 var(--pad) 12px">最多同时登录 5 台设备。移除后该设备需要重新登录。</p>
  ${group('', [['phone', '阿栗的 iPhone', '本机 · iOS 19.1 · 上海', true], ['grid', 'Lyra 桌面端', 'Windows 11 · 2 小时前', false], ['tv', '客厅电视', 'Android TV · 昨天', false]].map(([i, n, d, me]) => `<div class="it"><div class="tile" style="background:${me ? TILE.green : TILE.gray}">${ic(i)}</div><div class="lb"><b>${n}</b><small>${d}</small></div>${me ? '<span class="badge acc">本机</span>' : `<button class="btn danger sm" data-act="toast" data-msg="已移除 ${n}" data-icon="logout">移除</button>`}</div>`))}` };

PAGES.backup = { render:() => `${appBar('备份与同步')}
  <div class="m card" style="padding:16px;display:flex;gap:14px;align-items:center;margin-bottom:14px">
    <div style="width:48px;height:48px;border-radius:16px;background:rgba(94,230,168,.14);color:var(--ok);display:flex;align-items:center;justify-content:center">${ic('cloud')}</div>
    <div style="flex:1"><b>云同步正常</b><div style="font-size:12.5px;color:var(--t2);margin-top:3px">收藏 ${S.liked.size} · 歌单 4 · 最后同步 刚刚</div></div></div>
  ${group('账号云同步', [item({ icon:'refresh', color:'green', label:'多端实时同步', sub:'收藏、歌单、播放进度', sw:'cloudSync' }), item({ icon:'cloud', color:'blue', label:'立即备份到账号', act:'toast', args:{ msg:'备份完成 · 1.2 MB', icon:'cloud' } }), item({ icon:'history', color:'gray', label:'历史备份', val:'12 份', act:'toast', args:{ msg:'选择一份备份进行恢复', icon:'history' } })])}
  <div class="note" data-act="push" data-v="cloud">${ic('cloud')}<span>WebDAV 已移到「我的 → 音乐云盘」，可以直接播放 NAS 上的音乐，也可以备份收藏和歌单。</span></div>` };

PAGES.about = { render:() => `${appBar('关于与更新')}
  <div style="text-align:center;padding:10px 0 22px"><div style="display:flex;justify-content:center">${appIcon(72)}</div><b style="display:block;font-size:20px;margin-top:14px">Lyra</b><div style="font-size:12.5px;color:var(--t2);margin-top:3px">v2.4.0 (2401) · 稳定版</div></div>
  ${group('', [item({ icon:'refresh', color:'green', label:'检查更新', val:'有新版本', act:'dialog', args:{ v:'update' } }), item({ icon:'bell', color:'orange', label:'公告历史', act:'push', args:{ v:'announcements' } }), item({ icon:'info', color:'blue', label:'使用须知', act:'toast', args:{ msg:'已打开使用须知', icon:'info' } })])}
  ${group('诊断', [item({ icon:'bug', color:'red', label:'崩溃报告', val:'0 条', act:'toast', args:{ msg:'没有崩溃记录', icon:'check' } }), item({ icon:'bug', color:'gray', label:'自动上报崩溃', sw:'crash' }), item({ icon:'code', color:'gray', label:'应用日志', act:'toast', args:{ msg:'日志已复制，可发给开发者', icon:'copy' } }), item({ icon:'trash', color:'gray', label:'清除缓存', val:'1.8 GB', act:'toast', args:{ msg:'已清除 1.8 GB', icon:'trash' } })])}
  <p class="hint" style="text-align:center;padding:10px 0 0">© 2026 Lyra · 开源许可</p>` };
