(() => {
  const hash = location.hash.startsWith('#') ? location.hash.slice(1) : '';
  const params = new URLSearchParams(hash);
  const bridge = params.get('bridge');
  const token = params.get('token');
  let changed = false;

  if (bridge && /^https:\/\/[a-zA-Z0-9.-]+$/.test(bridge)) {
    localStorage.setItem('wemoteBridgeUrl', bridge.replace(/\/$/, ''));
    changed = true;
  }
  if (token && /^[a-fA-F0-9]{32,128}$/.test(token)) {
    localStorage.setItem('wemoteRemoteToken', token);
    changed = true;
  }
  if (changed) history.replaceState({}, document.title, location.pathname);

  const nativeFetch = window.fetch.bind(window);
  window.fetch = (input, init = {}) => {
    const bridgeUrl = (localStorage.getItem('wemoteBridgeUrl') || '').replace(/\/$/, '');
    const remoteToken = localStorage.getItem('wemoteRemoteToken') || '';
    const url = typeof input === 'string' ? input : input.url;
    if (bridgeUrl && remoteToken && url.startsWith(bridgeUrl + '/api/')) {
      const headers = new Headers(init.headers || (typeof input !== 'string' ? input.headers : undefined) || {});
      headers.set('X-Wemote-Token', remoteToken);
      init = {...init, headers};
    }
    return nativeFetch(input, init);
  };
})();
