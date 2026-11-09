(function () {
  'use strict';

  var bootstrap = { serverName: 'CalmBar 互传', authMode: 'link', passcodeRequired: false };
  var permissions = { download: true, upload: true, text: true };
  var currentFolder = null;
  var toastTimer = null;
  var pollTimer = null;
  var lastRevision = null;

  var els = {
    serverName: document.getElementById('serverName'),
    logoutButton: document.getElementById('logoutButton'),
    authView: document.getElementById('authView'),
    authTitle: document.getElementById('authTitle'),
    authHint: document.getElementById('authHint'),
    authError: document.getElementById('authError'),
    passcodeForm: document.getElementById('passcodeForm'),
    passcodeInput: document.getElementById('passcodeInput'),
    passcodeSubmit: document.getElementById('passcodeSubmit'),
    mainView: document.getElementById('mainView'),
    statusText: document.getElementById('statusText'),
    refreshButton: document.getElementById('refreshButton'),
    dropZone: document.getElementById('dropZone'),
    fileInput: document.getElementById('fileInput'),
    uploadList: document.getElementById('uploadList'),
    uploadHint: document.getElementById('uploadHint'),
    textInput: document.getElementById('textInput'),
    introInput: document.getElementById('introInput'),
    textSubmit: document.getElementById('textSubmit'),
    itemList: document.getElementById('itemList'),
    itemCount: document.getElementById('itemCount'),
    breadcrumb: document.getElementById('breadcrumb'),
    emptyHint: document.getElementById('emptyHint'),
    toast: document.getElementById('toast')
  };

  // MARK: - 请求

  function api(path, options) {
    options = options || {};
    var headers = options.headers || {};
    var isForm = options.body instanceof FormData;
    if (options.body && !isForm) {
      headers['Content-Type'] = 'application/json';
    }
    if (options.method && options.method !== 'GET') {
      headers['X-CalmBar-Client'] = 'web';
    }
    var request = {
      method: options.method || 'GET',
      credentials: 'same-origin',
      headers: headers,
      body: options.body
    };
    return fetch(path, request).then(function (response) {
      if (response.status === 401) {
        showAuth('expired');
        throw new Error('链接已失效，请向对方重新获取');
      }
      var type = response.headers.get('content-type') || '';
      var parsing = type.indexOf('application/json') >= 0
        ? response.json().catch(function () { return null; })
        : Promise.resolve(null);
      return parsing.then(function (payload) {
        if (!response.ok) {
          throw new Error((payload && payload.message) || '操作失败，请重试');
        }
        return payload;
      });
    });
  }

  // MARK: - 启动

  function boot() {
    fetch('/api/bootstrap', { credentials: 'same-origin' })
      .then(function (response) { return response.json(); })
      .then(function (data) {
        bootstrap = data;
        els.serverName.textContent = data.serverName || 'CalmBar 互传';
        return probeSession();
      })
      .catch(function () {
        showAuth('offline');
      });
  }

  function probeSession() {
    return api('/api/state').then(function (state) {
      if (state && state.permissions) {
        permissions = state.permissions;
      }
      showMain();
    }).catch(function () {
      if (bootstrap.authMode === 'passcode') {
        showAuth('passcode');
        return;
      }
      var token = readLinkToken();
      if (!token) {
        showAuth('link-missing');
        return;
      }
      return loginWithToken(token);
    });
  }

  function loginWithToken(token) {
    return api('/api/session', {
      method: 'POST',
      body: JSON.stringify({ linkToken: token })
    }).then(function (data) {
      if (data && data.permissions) {
        permissions = data.permissions;
      }
      clearLinkToken();
      showMain();
    }).catch(function (error) {
      showAuth('link-failed');
      setAuthError(error.message);
    });
  }

  function readLinkToken() {
    var hash = window.location.hash || '';
    var match = hash.match(/[#&]t=([^&]+)/);
    return match ? decodeURIComponent(match[1]) : null;
  }

  function clearLinkToken() {
    if (window.history && window.history.replaceState) {
      window.history.replaceState(null, '', window.location.pathname);
    }
  }

  // MARK: - 认证界面

  function showAuth(reason) {
    stopPolling();
    els.mainView.hidden = true;
    els.authView.hidden = false;
    els.logoutButton.hidden = true;
    setAuthError('');
    els.passcodeForm.hidden = true;
    els.passcodeInput.value = '';
    setAuthBusy(false);

    if (bootstrap.authMode === 'passcode' || reason === 'passcode') {
      els.authTitle.textContent = '连接到这台 Mac';
      els.authHint.textContent = '请输入分享者提供的 6 位数字口令';
      els.passcodeForm.hidden = false;
    } else if (reason === 'link-missing') {
      els.authTitle.textContent = '链接缺少访问令牌';
      els.authHint.textContent = '请让分享者重新发送完整链接（包含 #t= 部分）';
    } else if (reason === 'link-failed') {
      els.authTitle.textContent = '链接已失效';
      els.authHint.textContent = '请让分享者重新发送完整链接';
    } else if (reason === 'expired') {
      els.authTitle.textContent = '连接已断开';
      els.authHint.textContent = '会话已过期，请重新获取访问链接或输入口令';
    } else if (reason === 'logout') {
      els.authTitle.textContent = '已断开连接';
      els.authHint.textContent = '如需继续访问，请重新获取访问链接';
    } else {
      els.authTitle.textContent = '无法连接到这台 Mac';
      els.authHint.textContent = '请确认双方在同一 Wi-Fi，并稍后刷新重试';
    }
  }

  function setAuthError(message) {
    els.authError.textContent = message || '';
    els.authError.hidden = !message;
  }

  function setAuthBusy(busy) {
    els.passcodeSubmit.disabled = busy;
    els.passcodeInput.disabled = busy;
    els.passcodeSubmit.textContent = busy ? '连接中…' : '连接';
  }

  els.passcodeForm.addEventListener('submit', function (event) {
    event.preventDefault();
    var code = els.passcodeInput.value.trim();
    if (!/^\d{6}$/.test(code)) {
      setAuthError('请输入 6 位数字口令');
      return;
    }
    setAuthError('');
    setAuthBusy(true);
    api('/api/session', {
      method: 'POST',
      body: JSON.stringify({ passcode: code })
    }).then(function (data) {
      if (data && data.permissions) {
        permissions = data.permissions;
      }
      setAuthBusy(false);
      showMain();
    }).catch(function (error) {
      setAuthBusy(false);
      setAuthError(error.message);
      els.passcodeInput.select();
    });
  });

  // MARK: - 主界面

  function showMain() {
    els.authView.hidden = true;
    els.mainView.hidden = false;
    els.logoutButton.hidden = false;
    els.statusText.textContent = '同一 Wi-Fi 下的设备可访问';
    els.uploadHint.textContent = permissions.upload ? '' : '分享者已关闭上传';
    var uploadCard = els.dropZone.closest('.card');
    var textCard = els.textInput.closest('.card');
    if (uploadCard) { uploadCard.hidden = !permissions.upload; }
    if (textCard) { textCard.hidden = !permissions.text; }
    loadItems();
    startPolling();
  }

  function loadItems(silent) {
    currentFolder = null;
    els.breadcrumb.hidden = true;
    return api('/api/items').then(function (payload) {
      lastRevision = payload.revision;
      renderItems(payload.items || []);
    }).catch(function (error) {
      if (!silent) { toast(error.message); }
    });
  }

  // 多客户端场景：其他设备上传后，本页在数秒内自动同步列表。
  function pollItems() {
    if (document.visibilityState === 'hidden') { return; }
    if (els.mainView.hidden) { return; }
    if (currentFolder) {
      api('/api/items?item=' + encodeURIComponent(currentFolder.item.id) + '&path=' + encodeURIComponent(currentFolder.path))
        .then(function (payload) {
          if (payload.revision === lastRevision) { return; }
          lastRevision = payload.revision;
          renderFolder(currentFolder.item, currentFolder.path, payload.entries || []);
        })
        .catch(function () { /* 目录轮询失败静默处理 */ });
      return;
    }
    api('/api/items').then(function (payload) {
      if (payload.revision === lastRevision) { return; }
      lastRevision = payload.revision;
      renderItems(payload.items || []);
    }).catch(function () { /* 轮询失败静默处理 */ });
  }

  function startPolling() {
    stopPolling();
    pollTimer = setInterval(pollItems, 4000);
  }

  function stopPolling() {
    if (pollTimer) {
      clearInterval(pollTimer);
      pollTimer = null;
    }
  }

  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'visible' && !els.mainView.hidden) {
      pollItems();
    }
  });

  function renderItems(items) {
    els.itemList.innerHTML = '';
    els.emptyHint.hidden = items.length > 0;
    els.itemCount.textContent = items.length > 0 ? items.length + ' 项' : '';
    // 按添加时间倒序展示，最新内容置顶。
    items.slice().sort(function (a, b) {
      return String(b.addedAt || '').localeCompare(String(a.addedAt || ''));
    }).forEach(function (item) {
      els.itemList.appendChild(buildItemRow(item));
    });
  }

  function buildItemRow(item) {
    var li = document.createElement('li');
    li.className = 'item';

    var icon = document.createElement('span');
    icon.className = 'item-icon';
    icon.textContent = item.kind === 'text' ? '文' : (item.kind === 'folder' ? '夹' : '件');

    var main = document.createElement('div');
    main.className = 'item-main';

    var name;
    if (item.kind === 'text') {
      // 用 span 代替 button：iOS Safari 下按钮内的长文本不会正确省略，会溢出压住右侧操作。
      name = document.createElement('span');
      name.className = 'item-name item-name--text';
      name.setAttribute('role', 'button');
      name.tabIndex = 0;
      name.textContent = item.name;
      name.addEventListener('click', function () { viewText(item); });
      name.addEventListener('keydown', function (event) {
        if (event.key === 'Enter' || event.key === ' ') {
          event.preventDefault();
          viewText(item);
        }
      });
    } else if (item.kind === 'file') {
      name = document.createElement('a');
      name.className = 'item-name';
      name.href = downloadURL(item.id, '');
      name.textContent = item.name;
    } else {
      name = document.createElement('a');
      name.className = 'item-name';
      name.href = '#';
      name.textContent = item.name;
      name.addEventListener('click', function (event) {
        event.preventDefault();
        openFolder(item, '');
      });
    }
    main.appendChild(name);

    var sub = document.createElement('span');
    sub.className = 'item-sub';
    sub.textContent = subtitleFor(item);
    main.appendChild(sub);

    var actions = document.createElement('div');
    actions.className = 'item-actions';

    if (item.kind === 'text') {
      actions.appendChild(actionButton('查看', function () { viewText(item); }));
    }
    if (item.kind === 'folder') {
      actions.appendChild(actionButton('打开', function () { openFolder(item, ''); }));
      actions.appendChild(linkButton('下载 ZIP', downloadURL(item.id, '')));
    } else {
      actions.appendChild(linkButton('下载', downloadURL(item.id, '')));
    }

    li.appendChild(icon);
    li.appendChild(main);
    li.appendChild(actions);
    return li;
  }

  function subtitleFor(item) {
    var parts = [];
    if (item.kind === 'folder') { parts.push('文件夹'); }
    if (item.kind === 'text') { parts.push('文本'); }
    if (item.sizeText) { parts.push(item.sizeText); }
    if (item.intro) { parts.push(item.intro); }
    if (!item.isValid && item.invalidReason) { parts.push(item.invalidReason); }
    return parts.join(' · ');
  }

  function actionButton(title, handler) {
    var button = document.createElement('button');
    button.type = 'button';
    button.textContent = title;
    button.addEventListener('click', handler);
    return button;
  }

  function linkButton(title, href) {
    var link = document.createElement('a');
    link.textContent = title;
    link.href = href;
    return link;
  }

  function downloadURL(itemID, path) {
    var url = '/api/download?item=' + encodeURIComponent(itemID);
    if (path) {
      url += '&path=' + encodeURIComponent(path);
    }
    return url;
  }

  // MARK: - 文件夹浏览

  function openFolder(item, path) {
    api('/api/items?item=' + encodeURIComponent(item.id) + '&path=' + encodeURIComponent(path))
      .then(function (payload) {
        currentFolder = { item: item, path: path };
        lastRevision = payload.revision;
        renderFolder(item, path, payload.entries || []);
      })
      .catch(function (error) { toast(error.message); });
  }

  function renderFolder(item, path, entries) {
    els.itemList.innerHTML = '';
    els.emptyHint.hidden = entries.length > 0;
    els.emptyHint.textContent = '这个文件夹是空的';
    els.itemCount.textContent = entries.length > 0 ? entries.length + ' 项' : '';
    renderBreadcrumb(item, path);

    entries.forEach(function (entry) {
      var li = document.createElement('li');
      li.className = 'item';

      var icon = document.createElement('span');
      icon.className = 'item-icon';
      icon.textContent = entry.isDirectory ? '夹' : '件';

      var main = document.createElement('div');
      main.className = 'item-main';
      var name = document.createElement('span');
      name.className = 'item-name';
      name.textContent = entry.name;
      main.appendChild(name);
      var sub = document.createElement('span');
      sub.className = 'item-sub';
      sub.textContent = entry.isDirectory ? '文件夹' : formatSize(entry.size);
      main.appendChild(sub);

      var actions = document.createElement('div');
      actions.className = 'item-actions';
      if (entry.isDirectory) {
        actions.appendChild(actionButton('打开', function () {
          openFolder(item, joinPath(path, entry.name));
        }));
      }
      actions.appendChild(linkButton('下载', downloadURL(item.id, joinPath(path, entry.name))));

      li.appendChild(icon);
      li.appendChild(main);
      li.appendChild(actions);
      els.itemList.appendChild(li);
    });
  }

  function renderBreadcrumb(item, path) {
    els.breadcrumb.hidden = false;
    els.breadcrumb.innerHTML = '';
    var parts = path ? path.split('/').filter(Boolean) : [];

    var root = document.createElement('button');
    root.type = 'button';
    root.textContent = item.name;
    root.addEventListener('click', function () { openFolder(item, ''); });
    els.breadcrumb.appendChild(root);

    var accumulated = '';
    parts.forEach(function (part) {
      accumulated = joinPath(accumulated, part);
      var sep = document.createElement('span');
      sep.className = 'sep';
      sep.textContent = '/';
      els.breadcrumb.appendChild(sep);
      var segment = document.createElement('button');
      segment.type = 'button';
      segment.textContent = part;
      var target = accumulated;
      segment.addEventListener('click', function () { openFolder(item, target); });
      els.breadcrumb.appendChild(segment);
    });
  }

  function joinPath(base, name) {
    return base ? base + '/' + name : name;
  }

  // MARK: - 文本

  function viewText(item) {
    api('/api/items?item=' + encodeURIComponent(item.id)).then(function (payload) {
      var text = (payload && payload.item && payload.item.text) || '';
      showTextDialog(item.name, text);
    }).catch(function (error) { toast(error.message); });
  }

  function showTextDialog(title, text) {
    var dialog = document.createElement('dialog');
    dialog.className = 'preview';

    var heading = document.createElement('h2');
    heading.textContent = title;

    var pre = document.createElement('pre');
    pre.textContent = text;

    var actions = document.createElement('div');
    actions.className = 'preview-actions';

    var copy = document.createElement('button');
    copy.type = 'button';
    copy.className = 'primary';
    copy.textContent = '复制文本';
    copy.addEventListener('click', function () {
      copyText(text).then(function () { toast('已复制'); });
    });

    var close = document.createElement('button');
    close.type = 'button';
    close.className = 'ghost';
    close.textContent = '关闭';
    close.addEventListener('click', function () { dialog.close(); });

    actions.appendChild(copy);
    actions.appendChild(close);
    dialog.appendChild(heading);
    dialog.appendChild(pre);
    dialog.appendChild(actions);
    document.body.appendChild(dialog);
    dialog.addEventListener('close', function () { dialog.remove(); });
    dialog.showModal();
  }

  function copyText(text) {
    if (navigator.clipboard && window.isSecureContext) {
      return navigator.clipboard.writeText(text);
    }
    return new Promise(function (resolve) {
      var area = document.createElement('textarea');
      area.value = text;
      area.style.position = 'fixed';
      area.style.opacity = '0';
      document.body.appendChild(area);
      area.select();
      try { document.execCommand('copy'); } catch (error) { /* ignore */ }
      document.body.removeChild(area);
      resolve();
    });
  }

  // MARK: - 上传

  els.dropZone.addEventListener('dragover', function (event) {
    event.preventDefault();
    els.dropZone.classList.add('dragging');
  });

  els.dropZone.addEventListener('dragleave', function () {
    els.dropZone.classList.remove('dragging');
  });

  els.dropZone.addEventListener('drop', function (event) {
    event.preventDefault();
    els.dropZone.classList.remove('dragging');
    if (event.dataTransfer && event.dataTransfer.files.length > 0) {
      uploadFiles(event.dataTransfer.files);
    }
  });

  els.fileInput.addEventListener('change', function () {
    if (els.fileInput.files.length > 0) {
      uploadFiles(els.fileInput.files);
    }
    els.fileInput.value = '';
  });

  function uploadFiles(files) {
    if (!permissions.upload) {
      toast('分享者已关闭上传');
      return;
    }
    Array.prototype.forEach.call(files, uploadSingle);
  }

  function uploadSingle(file) {
    if (file.size > 20 * 1024 * 1024 * 1024) {
      toast(file.name + ' 超过 20GB 上限');
      return;
    }

    var row = document.createElement('div');
    row.className = 'upload-row';
    var name = document.createElement('span');
    name.className = 'name';
    name.textContent = file.name;
    var meta = document.createElement('span');
    meta.className = 'meta';
    meta.textContent = '等待中';
    var progress = document.createElement('div');
    progress.className = 'progress';
    var bar = document.createElement('span');
    progress.appendChild(bar);
    row.appendChild(name);
    row.appendChild(meta);
    row.appendChild(progress);
    els.uploadList.appendChild(row);

    var form = new FormData();
    form.append('file', file, file.name);

    var xhr = new XMLHttpRequest();
    xhr.open('POST', '/api/upload');
    xhr.setRequestHeader('X-CalmBar-Client', 'web');

    xhr.upload.onprogress = function (event) {
      if (!event.lengthComputable) { return; }
      var ratio = event.total > 0 ? event.loaded / event.total : 0;
      bar.style.width = Math.min(100, Math.round(ratio * 100)) + '%';
      meta.textContent = Math.round(ratio * 100) + '%';
    };

    xhr.onload = function () {
      if (xhr.status === 201) {
        bar.style.width = '100%';
        meta.textContent = '已发送';
        toast('已发送：' + file.name);
        loadItems();
        return;
      }
      var message = '发送失败';
      try {
        var payload = JSON.parse(xhr.responseText);
        message = payload.message || message;
      } catch (error) { /* ignore */ }
      meta.textContent = '失败';
      bar.style.width = '100%';
      bar.style.background = 'var(--danger)';
      toast(message);
      if (xhr.status === 401) {
        showAuth('expired');
      }
    };

    xhr.onerror = function () {
      meta.textContent = '网络中断';
      bar.style.width = '100%';
      bar.style.background = 'var(--danger)';
    };

    xhr.send(form);
  }

  // MARK: - 文本发送

  els.textSubmit.addEventListener('click', function () {
    var text = els.textInput.value.trim();
    if (!text) {
      toast('请输入要发送的文本');
      els.textInput.focus();
      return;
    }
    els.textSubmit.disabled = true;
    api('/api/text', {
      method: 'POST',
      body: JSON.stringify({ text: text, intro: els.introInput.value.trim() })
    }).then(function () {
      els.textInput.value = '';
      els.introInput.value = '';
      toast('文本已发送');
      loadItems();
    }).catch(function (error) {
      toast(error.message);
    }).then(function () {
      els.textSubmit.disabled = false;
    });
  });

  // MARK: - 其它交互

  els.refreshButton.addEventListener('click', function () {
    if (currentFolder) {
      openFolder(currentFolder.item, currentFolder.path);
    } else {
      loadItems();
    }
    toast('已刷新');
  });

  els.logoutButton.addEventListener('click', function () {
    api('/api/session', { method: 'DELETE' })
      .catch(function () { /* 断开失败也回到认证页 */ })
      .then(function () { showAuth('logout'); });
  });

  function formatSize(size) {
    if (typeof size !== 'number' || size < 0) { return ''; }
    if (size < 1024) { return size + ' B'; }
    var units = ['KB', 'MB', 'GB', 'TB'];
    var value = size / 1024;
    var index = 0;
    while (value >= 1024 && index < units.length - 1) {
      value /= 1024;
      index += 1;
    }
    return (value >= 10 ? Math.round(value) : value.toFixed(1)) + ' ' + units[index];
  }

  function toast(message) {
    els.toast.textContent = message;
    els.toast.hidden = false;
    if (toastTimer) { clearTimeout(toastTimer); }
    toastTimer = setTimeout(function () {
      els.toast.hidden = true;
    }, 2600);
  }

  boot();
})();
