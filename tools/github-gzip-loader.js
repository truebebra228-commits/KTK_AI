/* IMPULSE: serve the official Godot WASM as a small static gzip file.
 * Only the matching WASM fetch is intercepted; game and browser APIs are intact.
 * No Content-Encoding, service worker, COOP or COEP server configuration needed.
 */
(() => {
  'use strict';
  const engineUrl = new URL('index.wasm', document.baseURI).href;
  const originalFetch = globalThis.fetch.bind(globalThis);
  globalThis.IMPULSE_COMPACT_WEB = { compressedWasm: 'index.wasm.gz', loads: 0 };
  globalThis.fetch = async (input, options) => {
    const requested = new URL(input instanceof Request ? input.url : input, document.baseURI).href;
    if (requested !== engineUrl) {
      return originalFetch(input, options);
    }
    if (typeof DecompressionStream !== 'function') {
      throw new Error('Для запуска обновите браузер: требуется DecompressionStream (gzip).');
    }
    const response = await originalFetch(`${engineUrl}.gz`, options);
    if (!response.ok) {
      throw new Error(`Не удалось загрузить движок (${response.status}).`);
    }
    globalThis.IMPULSE_COMPACT_WEB.loads += 1;
    const stream = response.body.pipeThrough(new DecompressionStream('gzip'));
    return new Response(stream, {
      status: 200,
      headers: { 'Content-Type': 'application/wasm' },
    });
  };
})();
