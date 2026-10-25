/* Cloudflare Tunnel WebUI - 单页控制台 */
'use strict';

const params = new URLSearchParams(location.search);
if (params.get('token')) localStorage.setItem('cfToken', params.get('token'));
const TOKEN = localStorage.getItem('cfToken') || '';

const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => Array.from(document.querySelectorAll(sel));
const esc = (value) => String(value ?? '').replace(/[&<>"']/g, (c) => (
  { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
));
const timeOf = (ts) => new Date(ts * 1000).toTimeString().slice(0, 8);

let state = null;
let logCursor = 0;
let logEntries = [];
let activeSource = 'all';

async function api(path, options = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (TOKEN) headers['X-Auth-Token'] = TOKEN;
  const res = await fetch(path, {
    method: options.method || 'GET',
    headers,
    body: options.body ? JSON.stringify(options.body) : undefined,
    credentials: 'same-origin',
  });
  let data = {};
  try { data = await res.json(); } catch (_) { /* 空响应 */ }
  if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`);
  return data;
}

function toast(message, isError) {
  const el = $('#toast');
  el.textContent = message;
  el.className = 'toast show' + (isError ? ' err' : '');
  clearTimeout(toast._timer);
  toast._timer = setTimeout(() => { el.className = 'toast'; }, isError ? 5200 : 3200);
}

async function run(label, fn) {
  try { await fn(); } catch (error) { toast(`${label}：${error.message}`, true); }
  refresh();
}

/* ---------------- 弹窗 ---------------- */
function openModal({ title, fields, okText = '确定', onSubmit }) {
  const body = $('#modal-body');
  $('#modal-title').textContent = title;
  $('#modal-error').textContent = '';
  body.innerHTML = fields.map((f) => {
    if (f.type === 'note') return `<p class="hintline">${esc(f.text)}</p>`;
    if (f.type === 'seg') {
      return `<div class="field"><label>${esc(f.label)}</label><div class="seg" data-name="${f.name}">${
        f.options.map((o) => `<button type="button" data-value="${o.value}" class="${o.value === f.value ? 'on' : ''}">${esc(o.label)}</button>`).join('')
      }</div></div>`;
    }
    if (f.type === 'check') {
      return `<label class="checkline"><input type="checkbox" data-name="${f.name}" ${f.value ? 'checked' : ''}/> ${esc(f.label)}</label>`;
    }
    return `<div class="field"><label>${esc(f.label)}</label>
      <input type="${f.type || 'text'}" data-name="${f.name}" value="${esc(f.value ?? '')}"
        placeholder="${esc(f.placeholder || '')}" ${f.min ? `min="${f.min}" max="${f.max}"` : ''} style="${f.full ? '' : 'width:100%'}" /></div>`;
  }).join('');

  body.querySelectorAll('.seg button').forEach((btn) => {
    btn.addEventListener('click', () => {
      btn.parentElement.querySelectorAll('button').forEach((b) => b.classList.remove('on'));
      btn.classList.add('on');
    });
  });

  const modal = $('#modal');
  modal.classList.add('open');
  const first = body.querySelector('input');
  if (first) setTimeout(() => first.focus(), 40);

  $('#modal-ok').onclick = async () => {
    const values = {};
    body.querySelectorAll('[data-name]').forEach((el) => {
      if (el.tagName === 'INPUT' && el.type === 'checkbox') values[el.dataset.name] = el.checked;
      else if (el.classList.contains('seg')) {
        const on = el.querySelector('button.on');
        values[el.dataset.name] = on ? on.dataset.value : '';
      } else values[el.dataset.name] = el.value;
    });
    $('#modal-ok').disabled = true;
    $('#modal-error').textContent = '';
    try {
      await onSubmit(values);
      modal.classList.remove('open');
    } catch (error) {
      $('#modal-error').textContent = error.message;
    } finally {
      $('#modal-ok').disabled = false;
      refresh();
    }
  };
}
$$('[data-close]').forEach((el) => el.addEventListener('click', () => $('#modal').classList.remove('open')));

/* ---------------- 渲染 ---------------- */
const PHASE = {
  stopped: { label: '已停止', cls: '' },
  starting: { label: '连接中', cls: 'warn pulse' },
  connected: { label: '已连接', cls: 'ok pulse' },
  reconnecting: { label: '重连中', cls: 'warn pulse' },
  error: { label: '异常', cls: 'err' },
};

function renderShell(s) {
  const runtimeOk = s.ready;
  $('#dot-runtime').className = 'dot ' + (runtimeOk ? 'on' : 'warn');
  $('#dot-account').className = 'dot ' + (s.loggedIn ? 'on' : '');
  $('#foot-version').textContent = s.version ? 'v' + s.version : '—';
  $('#foot-account').textContent = s.loggedIn ? '已登录' : '未登录';
  const online = s.tunnels.filter((t) => t.runtime.phase !== 'stopped').length;
  const badge = $('#nav-online');
  badge.textContent = online;
  badge.classList.toggle('hidden', online === 0);
  $('#set-version').textContent = s.version ? 'v' + s.version : '未检测到';
  $('#set-binary').textContent = s.binary || '未安装';
  $('#set-platform').textContent = `${s.platform.os} / ${s.platform.arch}`;
  $('#set-data').textContent = s.dataDir;
  $('#runtime-pill').className = 'pill ' + (runtimeOk ? 'ok' : 'warn');
  $('#runtime-pill').textContent = runtimeOk ? '就绪' : '未就绪';
  $('#account-pill').className = 'pill ' + (s.loggedIn ? 'ok' : '');
  $('#account-pill').textContent = s.loggedIn ? '已授权' : '未连接';
}

function renderOverview(s) {
  const online = s.tunnels.filter((t) => t.runtime.phase === 'connected').length;
  const starting = s.tunnels.some((t) => t.runtime.phase === 'starting' || t.runtime.phase === 'reconnecting');
  const quickLive = s.quick.phase !== 'stopped';
  const quickReady = s.quick.phase === 'connected';
  const anyRunning = online > 0 || starting || quickLive;

  let pill = '待启动', pillCls = 'pill';
  if (online > 0) { pill = '网络运行中'; pillCls = 'pill ok pulse'; }
  else if (quickReady) { pill = '临时隧道在线'; pillCls = 'pill ok pulse'; }
  else if (starting || quickLive) { pill = '连接中'; pillCls = 'pill warn pulse'; }
  else if (!s.loggedIn) { pill = '待授权'; pillCls = 'pill warn'; }
  $('#hero-pill').className = pillCls;
  $('#hero-pill').textContent = pill;
  $('#hero-title').textContent = online > 0 ? '本地服务已安全接入公网'
    : quickReady ? '临时隧道已接入公网' : '内网服务，安全直达公网';
  $('#hero-desc').textContent = online > 0
    ? `当前有 ${online} 条命名隧道在线，流量经由 Cloudflare 加密边缘转发到本机。`
    : quickReady ? `公网请求经 Cloudflare 边缘转发到本机 :${s.quickPort}。`
    : '建立出站加密通道，把本地端口映射到托管域名，无需开放任何入站端口。';
  $('#btn-start-all').classList.toggle('hidden', !(s.tunnels.some((t) => t.endpoints.length && t.runtime.phase === 'stopped')));
  $('#btn-stop-all').classList.toggle('hidden', !anyRunning);

  const stats = [
    ['命名隧道', s.totals.tunnels, '条', '由面板管理', ''],
    ['在线隧道', online + (quickLive ? 1 : 0), '条', '已建立边缘连接', '⚡'],
    ['端口映射', s.totals.endpoints, '个', '域名 → 本机端口', '⇄'],
    ['边缘连接', s.totals.connections, '条', 'quic / http2 通道', '◈'],
  ];
  $('#stats').innerHTML = stats.map(([label, value, unit, cap, icon]) => `
    <div class="card stat"><div class="top"><i>${icon}</i>${esc(label)}</div>
      <div class="value"><b>${value}</b><span>${unit}</span></div>
      <div class="cap">${esc(cap)}</div></div>`).join('');

  const banner = $('#overview-banner');
  if (!s.ready) {
    banner.innerHTML = `<div class="banner err"><div class="ico">!</div>
      <div><h4>cloudflared 运行时不可用</h4><p>请在设置页安装官方运行时后再启动隧道。</p></div>
      <div class="act"><button class="btn primary" data-go="settings">前往设置</button></div></div>`;
  } else if (s.tunnels.some((t) => t.credsMissing)) {
    const missing = s.tunnels.filter((t) => t.credsMissing).length;
    banner.innerHTML = `<div class="banner"><div class="ico">⚿</div>
      <div><h4>${missing} 条隧道缺少本机凭证</h4>
        <p>换机器或清理过数据时会这样。从云端取回原隧道凭证即可继续启动，不需要重建隧道。</p></div>
      <div class="act"><button class="btn primary" id="banner-repair">取回凭证</button></div></div>`;
  } else if (!s.loggedIn) {
    banner.innerHTML = `<div class="banner"><div class="ico">🛡</div>
      <div><h4>连接 Cloudflare 账户</h4><p>登录后即可创建命名隧道、绑定自定义域名并自动写入 DNS CNAME。</p></div>
      <div class="act"><button class="btn primary" id="banner-login">立即登录</button></div></div>`;
  } else banner.innerHTML = '';
  const bannerLogin = $('#banner-login');
  if (bannerLogin) bannerLogin.onclick = startLoginFlow;
  const bannerRepair = $('#banner-repair');
  if (bannerRepair) bannerRepair.onclick = () => run('取回凭证', async () => {
    const res = await api('/api/sync', { method: 'POST' });
    toast(`云端 ${res.cloud} 条，导入 ${res.imported} 条，取回凭证 ${res.repaired} 条`);
  });

  renderQuick(s);
  const active = s.tunnels.filter((t) => t.runtime.phase !== 'stopped');
  $('#active-list').innerHTML = active.length ? active.map((t) => {
    const phase = PHASE[t.runtime.phase] || PHASE.stopped;
    return `<div class="card tunnel live"><div class="tunnel-head">
      <div class="tunnel-ico ${phase.cls.includes('ok') ? 'ok' : phase.cls.includes('warn') ? 'warn' : ''}">⛁</div>
      <div class="tunnel-title">
        <div class="row"><h3>${esc(t.name)}</h3><span class="pill ${phase.cls}">${phase.label}</span>
          ${t.runtime.connections ? `<span class="tag faint">${t.runtime.connections} 条边缘连接</span>` : ''}</div>
        <div class="tunnel-meta">${t.endpoints.slice(0, 3).map((e) =>
          `<a class="mono" href="${esc(e.publicUrl)}" target="_blank" rel="noreferrer">${esc(e.publicUrl)}</a>`).join('')}
          ${t.endpoints.length > 3 ? `<span>+${t.endpoints.length - 3} 个域名</span>` : ''}</div>
      </div>
      <div class="tunnel-actions">
        <button class="btn ghost" data-action="stop-tunnel" data-id="${t.id}">■ 停止</button>
        <button class="btn ghost" data-go="tunnels">管理</button>
      </div></div></div>`;
  }).join('') : `<div class="empty"><div class="big">◍</div><h4>暂无在线命名隧道</h4>
      <p>${s.tunnels.length ? '在「隧道」页启动映射后，公网入口会显示在这里。' : '创建一条命名隧道，把本机端口映射到你的 Cloudflare 域名。'}</p></div>`;
}

function renderQuick(s) {
  const box = $('#quick-card');
  const phase = PHASE[s.quick.phase] || PHASE.stopped;
  const head = `<div class="head"><div class="tunnel-ico warn">⚡</div>
    <div style="flex:1;min-width:0"><h4>临时隧道 <span class="tag faint">trycloudflare.com</span></h4>
      <p class="desc">不依赖域名与账户，生成随机公网地址用于快速测试本机服务。</p></div>
    ${s.quick.phase !== 'stopped' ? `<span class="pill ${phase.cls}">${phase.label}</span>` : ''}</div>`;
  if (s.quick.phase !== 'stopped') {
    box.innerHTML = head + `<div class="body">
      <div class="urlbox">🔗 ${s.quick.url
        ? `<a href="${esc(s.quick.url)}" target="_blank" rel="noreferrer">${esc(s.quick.url)}</a>`
        : '<span class="muted">正在申请公网地址…</span>'}
        <span class="spacer"></span><span class="faint">本机 :${s.quickPort}</span></div>
      <button class="btn ghost" title="复制地址" id="quick-copy">⧉</button>
      <a class="btn ghost" ${s.quick.url ? `href="${esc(s.quick.url)}" target="_blank" rel="noreferrer"` : ''}>↗</a>
      <button class="btn primary" data-action="stop-quick">■ 停止</button></div>`;
    const copy = $('#quick-copy');
    if (copy) copy.onclick = () => { navigator.clipboard.writeText(s.quick.url || ''); toast('已复制公网地址'); };
  } else {
    box.innerHTML = head + `<div class="body">
      <div class="field"><label>本机端口</label><input type="number" id="quick-port" min="1" max="65535" value="${s.quickPort}" style="width:150px" /></div>
      <button class="btn primary" data-action="start-quick">⚡ 生成临时地址</button>
      <span class="muted small">${esc(s.quick.error || '地址通常在 5–15 秒内就绪，停止后立即失效。')}</span></div>`;
  }
}

function renderTunnels(s) {
  const list = $('#tunnel-list');
  if (!s.tunnels.length) {
    list.innerHTML = `<div class="empty"><div class="big">⛁</div><h4>创建你的第一条命名隧道</h4>
      <p>命名隧道拥有固定域名入口与本机凭证，适合长期运行的服务。</p>
      <p style="margin-top:16px"><button class="btn primary" id="empty-new">＋ 新建隧道</button></p></div>`;
    const btn = $('#empty-new');
    if (btn) btn.onclick = newTunnelDialog;
    return;
  }
  list.innerHTML = s.tunnels.map((t) => {
    const phase = PHASE[t.runtime.phase] || PHASE.stopped;
    const live = t.runtime.phase !== 'stopped';
    const running = t.runtime.phase === 'connected';
    return `<div class="card tunnel ${running ? 'live' : ''}">
      <div class="tunnel-head">
        <div class="tunnel-ico ${running ? 'ok' : live ? 'warn' : t.runtime.phase === 'error' ? 'err' : ''}">⛁</div>
        <div class="tunnel-title">
          <div class="row"><h3>${esc(t.name)}</h3><span class="pill ${phase.cls}">${phase.label}</span>
            ${t.runtime.error && !running ? `<span class="tag amber">待重启生效</span>` : ''}</div>
          <div class="tunnel-meta"><span class="mono">${esc(t.id.slice(0, 8))}…</span>
            <span class="tag faint">${t.endpoints.length} 个映射</span>
            ${t.credsMissing ? '<span class="tag amber">缺少凭证</span>' : ''}
            ${t.remoteMissing ? '<span class="tag" style="color:var(--danger);background:rgba(255,107,129,.1);border-color:rgba(255,107,129,.26)">云端已删除</span>' : ''}
            <span>创建于 ${new Date(t.createdAt * 1000).toISOString().slice(0, 10)}</span></div>
        </div>
        <div class="tunnel-actions">
          ${t.credsMissing ? `<button class="btn ghost" data-action="repair-creds" data-id="${t.id}">⚿ 取回凭证</button>` : ''}
          ${t.unrouted ? `<button class="btn ghost" data-action="route-all" data-id="${t.id}">☁ 配置 DNS (${t.unrouted})</button>` : ''}
          ${live
            ? `<button class="btn ghost" data-action="stop-tunnel" data-id="${t.id}">■ 停止</button>`
            : `<button class="btn primary" data-action="start-tunnel" data-id="${t.id}">▶ 启动</button>`}
          <button class="icon-btn" data-action="del-tunnel" data-id="${t.id}" data-name="${esc(t.name)}" title="删除隧道">🗑</button>
        </div>
      </div>
      ${t.runtime.error ? `<div class="err-line" title="${esc(t.runtime.error)}">${esc(t.runtime.error)}</div>` : ''}
      <hr class="sep" />
      ${t.endpoints.length ? t.endpoints.map((e) => `
        <div class="ep">
          <div class="pub">
            <div class="host">${e.dnsRouted ? '🟢' : '⚪'}
              ${e.dnsRouted ? `<a href="${esc(e.publicUrl)}" target="_blank" rel="noreferrer">${esc(e.hostname)}</a>` : esc(e.hostname)}
              ${e.path ? `<span class="tag">${esc(e.path)}</span>` : ''}</div>
            <div class="url">${esc(e.publicUrl)}</div>
          </div>
          <span class="arrow">→</span>
          <span class="local">🖥 localhost:${e.port}<small>${e.scheme}</small></span>
          ${e.dnsRouted
            ? '<span class="tag green">DNS 已指向</span>'
            : `<button class="tag amber" data-action="route-one" data-id="${t.id}" data-eid="${e.id}" style="cursor:pointer;border:1px solid rgba(245,181,68,.24);background:rgba(245,181,68,.1)">待配置 DNS</button>`}
          <span class="tools">
            <button class="icon-btn" data-action="edit-ep" data-id="${t.id}" data-eid="${e.id}" title="编辑映射">⚙</button>
            <button class="icon-btn" data-action="del-ep" data-id="${t.id}" data-eid="${e.id}" title="删除映射">🗑</button>
          </span>
        </div>`).join('')
        : `<div class="empty" style="padding:18px"><p>还没有端口映射，添加一个域名指向本机端口。</p></div>`}
      <div class="tunnel-foot">
        <button class="btn ghost tiny" data-action="add-ep" data-id="${t.id}">＋ 添加端口映射</button>
        <span class="hint">${live ? '修改映射后需重启隧道生效' : '启动后流量经 Cloudflare 边缘转发'}</span>
      </div>
    </div>`;
  }).join('');
}

function renderLogs() {
  const box = $('#console');
  box.innerHTML = logEntries.slice(-900).map((e) => `
    <div class="log ${e.level}"><time>${timeOf(e.time)}</time>
      <span class="lvl">${e.level === 'error' ? 'ERR' : e.level === 'warn' ? 'WRN' : e.level === 'debug' ? 'DBG' : 'INF'}</span>
      <span class="src">${esc(e.source)}</span><span class="msg">${esc(e.message)}</span></div>`).join('');
  $('#log-count').textContent = `${logEntries.length} 行`;
  if ($('#log-auto').checked) box.scrollTop = box.scrollHeight;
}

/* ---------------- 交互 ---------------- */
function switchView(name) {
  $$('.view').forEach((v) => v.classList.toggle('active', v.id === 'view-' + name));
  $$('.nav-item').forEach((b) => b.classList.toggle('active', b.dataset.view === name));
  location.hash = name;
}

function newTunnelDialog() {
  openModal({
    title: '新建命名隧道',
    okText: '创建隧道',
    fields: [
      { name: 'name', label: '隧道名称', placeholder: 'home-nas' },
      { type: 'note', text: '只允许小写字母、数字与连字符；创建后会在本机保存隧道凭证。' },
    ],
    onSubmit: async (v) => {
      await api('/api/tunnels', { method: 'POST', body: { name: v.name } });
      toast('隧道已创建，继续添加端口映射');
      const state2 = await api('/api/state');
      state = state2;
      const tunnel = state.tunnels[state.tunnels.length - 1];
      if (tunnel) endpointDialog(tunnel.id, null);
    },
  });
}

function endpointDialog(tunnelId, endpoint) {
  openModal({
    title: endpoint ? '编辑端口映射' : '添加端口映射',
    okText: endpoint ? '保存修改' : '添加映射',
    fields: [
      { name: 'hostname', label: '公网域名', placeholder: 'app.example.com', value: endpoint?.hostname || '' },
      { name: 'scheme', label: '本机服务协议', type: 'seg', value: endpoint?.scheme || 'http',
        options: [{ value: 'http', label: 'HTTP' }, { value: 'https', label: 'HTTPS' }] },
      { name: 'port', type: 'number', label: '本机端口', placeholder: '8080', min: 1, max: 65535, value: endpoint?.port || '' },
      { name: 'path', label: '路径前缀（可选）', placeholder: '/api', value: endpoint?.path || '' },
      ...(endpoint ? [] : [
        { type: 'check', name: 'dns', label: '同时创建 DNS CNAME 记录', value: true },
        { type: 'check', name: 'overwrite', label: '覆盖已存在的 DNS 记录' },
      ]),
      { type: 'note', text: '域名必须已托管在 Cloudflare。若已有同名解析记录，需要勾选覆盖。' },
    ],
    onSubmit: async (v) => {
      const payload = {
        hostname: String(v.hostname).trim().toLowerCase(),
        port: Number(v.port),
        scheme: v.scheme || 'http',
        path: String(v.path || '').trim(),
        dns: !!v.dns,
        overwrite: !!v.overwrite,
      };
      if (endpoint) {
        await api(`/api/tunnels/${tunnelId}/endpoints/${endpoint.id}`, { method: 'PUT', body: payload });
        toast('映射已更新');
      } else {
        await api(`/api/tunnels/${tunnelId}/endpoints`, { method: 'POST', body: payload });
        toast('映射已保存');
      }
    },
  });
}

async function startLoginFlow() {
  let res;
  try {
    res = await api('/api/login/start', { method: 'POST' });
  } catch (error) {
    toast(`启动授权：${error.message}`, true);
    return;
  }
  openModal({
    title: '连接 Cloudflare 账户',
    okText: '我已完成授权',
    fields: [
      { type: 'note', text: '授权链接在服务器上生成，在你的浏览器中打开即可完成登录；证书会自动保存回服务器。' },
      { name: 'url', label: '授权链接', value: res.url || '正在生成授权链接…' },
    ],
    onSubmit: async () => {
      const check = await api('/api/login/check', { method: 'POST' });
      if (!check.loggedIn) throw new Error('尚未检测到授权证书，请先在浏览器完成登录');
      toast('Cloudflare 账户已连接');
    },
  });

  const body = $('#modal-body');
  const urlInput = body.querySelector('[data-name="url"]');
  urlInput.readOnly = true;

  const status = document.createElement('p');
  status.className = 'hintline';
  status.textContent = '正在请求 cloudflared 生成授权链接…';
  body.appendChild(status);

  const actions = document.createElement('div');
  actions.className = 'row-gap';
  actions.innerHTML = `
    <button type="button" class="btn primary" id="login-open" disabled>打开授权链接</button>
    <button type="button" class="btn ghost" id="login-copy" disabled>复制链接</button>`;
  body.appendChild(actions);

  let opened = false;
  let done = false;
  let closed = false;
  let timer = null;

  const finish = async (cancel) => {
    if (closed) return;
    closed = true;
    if (timer) clearInterval(timer);
    if (cancel && !done) {
      try { await api('/api/login/cancel', { method: 'POST' }); } catch (_) { /* 忽略 */ }
    }
  };

  const sync = async () => {
    if (!$('#modal').classList.contains('open')) { finish(true); return; }
    let st;
    try {
      st = await api('/api/login/check', { method: 'POST' });
    } catch (_) { return; }
    if (st.loggedIn) {
      done = true;
      urlInput.value = st.loginUrl || urlInput.value;
      status.textContent = '授权完成，证书已保存到服务器。';
      $('#login-open').disabled = !st.loginUrl;
      $('#login-copy').disabled = !st.loginUrl;
      if (timer) clearInterval(timer);
      return;
    }
    if (st.loginUrl) {
      urlInput.value = st.loginUrl;
      $('#login-open').disabled = false;
      $('#login-copy').disabled = false;
      status.textContent = '链接已生成，正在浏览器中打开；若没有反应请点「打开授权链接」。';
      if (!opened) {
        opened = true;
        window.open(st.loginUrl, '_blank', 'noopener');
      }
      return;
    }
    if (!st.loggingIn) {
      status.textContent = st.error
        ? `授权流程启动失败：${st.error}`
        : 'cloudflared 授权进程已退出，请查看「日志」后重试。';
      if (timer) clearInterval(timer);
    }
  };

  timer = setInterval(sync, 1200);
  $('#login-open').onclick = () => {
    if (urlInput.value) window.open(urlInput.value, '_blank', 'noopener');
  };
  $('#login-copy').onclick = async () => {
    if (!urlInput.value) return;
    try {
      await navigator.clipboard.writeText(urlInput.value);
      toast('授权链接已复制');
    } catch (_) {
      urlInput.select();
      toast('请按 Ctrl+C 复制');
    }
  };
  sync();
}

document.addEventListener('click', (event) => {
  const go = event.target.closest('[data-go]');
  if (go) { switchView(go.dataset.go); return; }
  const btn = event.target.closest('[data-action]');
  if (!btn) return;
  const { action, id, eid, name } = btn.dataset;
  const tunnel = state?.tunnels.find((t) => t.id === id);
  const handlers = {
    'start-tunnel': () => run('启动', () => api(`/api/tunnels/${id}/start`, { method: 'POST' })),
    'stop-tunnel': () => run('停止', () => api(`/api/tunnels/${id}/stop`, { method: 'POST' })),
    'route-all': () => run('配置 DNS', () => api(`/api/tunnels/${id}/dns`, { method: 'POST' })),
    'repair-creds': () => run('取回凭证', () => api(`/api/tunnels/${id}/credentials`, { method: 'POST' })),
    'route-one': () => run('配置 DNS', () => api(`/api/tunnels/${id}/endpoints/${eid}/dns`, { method: 'POST', body: { overwrite: false } })),
    'add-ep': () => tunnel && endpointDialog(id, null),
    'edit-ep': () => tunnel && endpointDialog(id, tunnel.endpoints.find((e) => e.id === eid)),
    'del-ep': () => {
      if (!confirm('删除该端口映射？已创建的 DNS 记录不会被删除。')) return;
      run('删除映射', () => api(`/api/tunnels/${id}/endpoints/${eid}`, { method: 'DELETE' }));
    },
    'del-tunnel': () => {
      if (!confirm(`删除隧道「${name}」？将从 Cloudflare 删除该隧道并清理本机凭证，DNS 记录需自行清理。`)) return;
      run('删除隧道', () => api(`/api/tunnels/${id}`, { method: 'DELETE' }));
    },
    'start-quick': () => run('启动临时隧道', () => api('/api/quick/start', { method: 'POST', body: { port: Number($('#quick-port').value) } })),
    'stop-quick': () => run('停止', () => api('/api/quick/stop', { method: 'POST' })),
  };
  if (handlers[action]) handlers[action]();
});

$('#nav').addEventListener('click', (event) => {
  const item = event.target.closest('.nav-item');
  if (item) switchView(item.dataset.view);
});
$('#btn-refresh').onclick = refresh;
$('#btn-new-tunnel').onclick = newTunnelDialog;
$('#btn-new-tunnel-2').onclick = newTunnelDialog;
$('#btn-start-all').onclick = () => run('启动全部', async () => {
  for (const t of state.tunnels) {
    if (t.endpoints.length && t.runtime.phase === 'stopped') {
      await api(`/api/tunnels/${t.id}/start`, { method: 'POST' });
    }
  }
});
$('#btn-stop-all').onclick = () => run('全部停止', async () => {
  await api('/api/quick/stop', { method: 'POST' }).catch(() => {});
  for (const t of state.tunnels) {
    if (t.runtime.phase !== 'stopped') await api(`/api/tunnels/${t.id}/stop`, { method: 'POST' });
  }
});
$('#btn-sync').onclick = () => run('同步云端', async () => {
  const res = await api('/api/sync', { method: 'POST' });
  const parts = [`云端 ${res.cloud} 条`];
  if (res.imported) parts.push(`导入 ${res.imported} 条`);
  if (res.repaired) parts.push(`取回凭证 ${res.repaired} 条`);
  toast(parts.join('，'));
});
$('#btn-login').onclick = startLoginFlow;
$('#btn-logout').onclick = () => {
  if (!confirm('退出账户会删除本机授权证书并停止所有隧道，配置会保留。继续？')) return;
  run('退出登录', () => api('/api/logout', { method: 'POST' }));
};
$('#btn-install').onclick = () => run('安装运行时', () => api('/api/runtime/install', { method: 'POST' }));
$('#btn-theme').onclick = () => {
  const next = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
  document.documentElement.dataset.theme = next;
  localStorage.setItem('cfTheme', next);
};
$('#log-source').addEventListener('change', (event) => {
  activeSource = event.target.value;
  logEntries = [];
  logCursor = 0;
  renderLogs();
});
$('#log-clear').onclick = () => run('清空日志', () => api('/api/logs/clear', { method: 'POST' }));
$('#log-copy').onclick = () => {
  navigator.clipboard.writeText(logEntries.map((e) =>
    `[${timeOf(e.time)}] [${e.source}] ${e.level.toUpperCase()} ${e.message}`).join('\n'));
  toast('已复制日志');
};

/* ---------------- 轮询 ---------------- */
async function refresh() {
  try {
    state = await api('/api/state');
    renderShell(state);
    renderOverview(state);
    renderTunnels(state);
  } catch (error) {
    if (String(error.message).includes('未授权')) toast('访问未授权，请带 ?token= 打开面板', true);
  }
}

async function pollLogs() {
  try {
    const data = await api(`/api/logs?since=${logCursor}&source=${encodeURIComponent(activeSource)}`);
    if (data.entries.length) {
      logEntries = logEntries.concat(data.entries).slice(-2000);
      renderLogs();
    }
    logCursor = data.cursor;
    const select = $('#log-source');
    const sources = ['系统', '登录', '临时隧道', ...((state?.tunnels || []).map((t) => t.name))];
    if (select.dataset.sig !== sources.join(',')) {
      select.dataset.sig = sources.join(',');
      select.innerHTML = ['all', ...new Set(sources)].map((v) =>
        `<option value="${esc(v)}">${v === 'all' ? '全部来源' : esc(v)}</option>`).join('');
      select.value = activeSource;
    }
  } catch (_) { /* 忽略瞬时错误 */ }
}

document.documentElement.dataset.theme = localStorage.getItem('cfTheme')
  || (window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark');
switchView((location.hash || '#overview').slice(1));
refresh();
pollLogs();
setInterval(refresh, 2500);
setInterval(pollLogs, 1500);
