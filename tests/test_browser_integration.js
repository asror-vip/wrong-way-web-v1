// test_browser_integration.js
// -------------------------------------------------------------------
// WRONG WAY — COMPREHENSIVE CDP BROWSER VERIFICATION RUNNER
// Uses native Chrome DevTools Protocol (CDP) via WebSocket over
// Chrome --remote-debugging-port. Zero third-party dependencies.
//
// SUITE 1: Real Poki CDN Integration (Production Unmodified Build)
//   - Official Poki CDN endpoint HTTP 200, JS, >5KB
//   - Chrome CDP Network request, response status, MIME type, completion
//   - Complete error accounting:
//       * Runtime.exceptionThrown (0 fatal exceptions)
//       * Runtime.consoleAPICalled (0 error console logs)
//       * Network.loadingFailed (0 relevant network failures)
//       * Network.responseReceived (0 HTTP 404 responses)
//   - Runtime assertions: window.PokiSDK object and methods
//   - PokiSDK.gameLoadingFinished() was actually called by Godot
//   - WebGL active context created on #canvas (not lost)
//   - Godot LevelDatabase 60 canonical levels loaded in runtime
//   - Godot PokiService SdkState.READY and is_poki_available
//
// SUITE 2: Real Godot WASM + JavaScriptBridge + Mock Poki Promise E2E
//   - Real Godot WASM engine + real JavaScriptBridge in Chrome
//   - Injected controllable mock Poki SDK Promise queue
//   - Commercial: 400ms delay vs 100ms timeout -> Ad B -> Stale A ignored
//   - Rewarded:   400ms delay vs 100ms timeout -> Ad B -> Stale A ignored
//   - Direct assertions that _active_js_callbacks retains callbacks while
//     ads are pending and releases them after completion, timeout, rejection,
//     and stale callback delivery
//   - Commercial & Rewarded rejection verification (producing success=false)
//   - Independent commercial and rewarded test cycles
//
// SUITE 3: Browser Fault Injection (4 Scenarios via CDP)
//   - MOCK_SUCCESS: SdkState.READY, is_poki_available=true, game responsive
//   - MOCK_DELAYED: 500ms delay -> SdkState.READY, game responsive
//   - MOCK_REJECT:  Adblock reject -> SdkState.FAILED, game responsive
//   - MOCK_MISSING: Offline / 404 -> SdkState.FAILED, game responsive
//   - Active game loop confirmed via advancing godot_process_frames
// -------------------------------------------------------------------

'use strict';

const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const { spawn, execSync } = require('child_process');

const BUILD_DIR = path.join(__dirname, '..', 'build', 'web');
const CHROME_PATH = process.env.CHROME_PATH
    || (process.argv[2] && !process.argv[2].startsWith('--') ? process.argv[2] : null)
    || 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';

const MIME_TYPES = {
    '.html': 'text/html',
    '.js': 'application/javascript',
    '.wasm': 'application/wasm',
    '.pck': 'application/octet-stream',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.svg': 'image/svg+xml',
    '.json': 'application/json'
};

// -------------------------------------------------------------------
// CDP Client Implementation (Pure Native WebSocket)
// -------------------------------------------------------------------
class CDPClient {
    constructor(wsUrl) {
        this.ws = new WebSocket(wsUrl);
        this.nextId = 1;
        this.pending = new Map();
        this.handlers = new Map();
        this.connected = new Promise((resolve, reject) => {
            this.ws.onopen = () => resolve();
            this.ws.onerror = (e) => reject(e);
        });
        this.ws.onmessage = (event) => {
            try {
                const msg = JSON.parse(event.data);
                if (msg.id && this.pending.has(msg.id)) {
                    const { resolve, reject } = this.pending.get(msg.id);
                    this.pending.delete(msg.id);
                    if (msg.error) reject(new Error(msg.error.message));
                    else resolve(msg.result);
                } else if (msg.method && this.handlers.has(msg.method)) {
                    for (const fn of this.handlers.get(msg.method)) {
                        fn(msg.params);
                    }
                }
            } catch (err) {
                console.error('[CDP Parse Error]:', err.message);
            }
        };
    }

    async send(method, params = {}) {
        await this.connected;
        const id = this.nextId++;
        return new Promise((resolve, reject) => {
            this.pending.set(id, { resolve, reject });
            this.ws.send(JSON.stringify({ id, method, params }));
        });
    }

    on(event, handler) {
        if (!this.handlers.has(event)) {
            this.handlers.set(event, []);
        }
        this.handlers.get(event).push(handler);
    }

    async evaluate(expression) {
        const res = await this.send('Runtime.evaluate', {
            expression,
            returnByValue: true,
            awaitPromise: true
        });
        if (res && res.result) {
            return res.result.value;
        }
        return undefined;
    }

    close() {
        try { this.ws.close(); } catch (_) {}
    }
}

// -------------------------------------------------------------------
// Helper Utilities
// -------------------------------------------------------------------
function getChromeVersion(chromePath) {
    try {
        const escaped = chromePath.replace(/'/g, "''");
        const cmd = `powershell -NoProfile -Command "(Get-Item '${escaped}').VersionInfo.ProductVersion"`;
        return execSync(cmd).toString().trim();
    } catch {
        return 'Unknown';
    }
}

function sleep(ms) {
    return new Promise(r => setTimeout(r, ms));
}

async function waitForCondition(predicateFn, timeoutMs = 12000, intervalMs = 100) {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
        const result = await predicateFn();
        if (result) return result;
        await sleep(intervalMs);
    }
    return false;
}

// -------------------------------------------------------------------
// HTTPS Pre-flight to Official CDN
// -------------------------------------------------------------------
function verifyOfficialCdnHealth() {
    const cdnUrl = 'https://game-cdn.poki.com/scripts/v2/poki-sdk.js';
    console.log(`\n[PRE-FLIGHT] Direct HTTPS GET to official Poki CDN: ${cdnUrl}`);
    return new Promise((resolve, reject) => {
        https.get(cdnUrl, (res) => {
            let data = '';
            res.on('data', chunk => { data += chunk; });
            res.on('end', () => {
                const ok200 = res.statusCode === 200;
                const ct = res.headers['content-type'] || '';
                const isJs = ct.includes('javascript');
                const hasPoki = data.includes('PokiSDK');
                const len = data.length;
                console.log(`  -> HTTP Status:    ${res.statusCode} ${res.statusMessage}`);
                console.log(`  -> Content-Type:   ${ct}`);
                console.log(`  -> Content-Length: ${len} bytes`);
                console.log(`  -> Contains PokiSDK: ${hasPoki}`);
                if (ok200 && isJs && hasPoki && len > 5000) {
                    resolve({ ok: true, statusCode: 200, contentType: ct, length: len });
                } else {
                    reject(new Error(`CDN health check failed (status: ${res.statusCode}, len: ${len})`));
                }
            });
        }).on('error', reject);
    });
}

// -------------------------------------------------------------------
// HTTP Test Server
// -------------------------------------------------------------------
function createServer(port, scenario, serverRequests) {
    return http.createServer((req, res) => {
        const urlPath = req.url.split('?')[0];
        const filePath = path.join(BUILD_DIR, urlPath === '/' ? 'index.html' : urlPath);

        res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
        res.setHeader('Cross-Origin-Embedder-Policy', 'credentialless');
        res.setHeader('Access-Control-Allow-Origin', '*');

        if (!fs.existsSync(filePath)) {
            serverRequests.push({ url: urlPath, status: 404 });
            res.writeHead(404);
            res.end('Not found');
            return;
        }

        serverRequests.push({ url: urlPath, status: 200 });
        const ext = path.extname(filePath).toLowerCase();
        res.setHeader('Content-Type', MIME_TYPES[ext] || 'application/octet-stream');

        if (urlPath === '/' || urlPath === '/index.html') {
            let html = fs.readFileSync(filePath, 'utf8');
            const pokiScriptTag = '<script src="https://game-cdn.poki.com/scripts/v2/poki-sdk.js"></script>';

            if (scenario === 'REAL_CDN') {
                // Untouched production HTML pointing to official CDN
                res.writeHead(200);
                res.end(html);
                return;
            }

            if (scenario === 'REAL_JSBRIDGE_E2E') {
                // Injects controllable mock PokiSDK Promise queues for JSBridge testing
                const injection = `
                <script>
                    window.__test_commercial_queue = [];
                    window.__test_rewarded_queue = [];
                    window.__poki_calls = [];

                    window.PokiSDK = {
                        init: function() {
                            return Promise.resolve();
                        },
                        gameLoadingFinished: function() {
                            window.__poki_loading_finished_called = true;
                        },
                        gameplayStart: function() {
                            window.__poki_gameplay_start_called = true;
                        },
                        gameplayStop: function() {
                            window.__poki_gameplay_stop_called = true;
                        },
                        commercialBreak: function() {
                            var item = window.__test_commercial_queue.shift() || { delay: 50, reject: false };
                            window.__poki_calls.push({ type: 'commercial', item: item, time: Date.now() });
                            return new Promise(function(resolve, reject) {
                                setTimeout(function() {
                                    if (item.reject) reject(new Error('Commercial rejected'));
                                    else resolve();
                                }, item.delay || 50);
                            });
                        },
                        rewardedBreak: function() {
                            var item = window.__test_rewarded_queue.shift() || { delay: 50, reject: false, success: true };
                            window.__poki_calls.push({ type: 'rewarded', item: item, time: Date.now() });
                            return new Promise(function(resolve, reject) {
                                setTimeout(function() {
                                    if (item.reject) reject(new Error('Rewarded rejected'));
                                    else resolve(Boolean(item.success));
                                }, item.delay || 50);
                            });
                        }
                    };
                </script>
                `;
                html = html.replace(pokiScriptTag, injection);
                res.writeHead(200);
                res.end(html);
                return;
            }

            if (scenario === 'MOCK_SUCCESS') {
                const injection = `
                <script>
                    window.PokiSDK = {
                        init: function() { return Promise.resolve(); },
                        gameLoadingFinished: function() { window.__poki_loading_finished = true; },
                        gameplayStart: function() {},
                        gameplayStop: function() {},
                        commercialBreak: function() { return Promise.resolve(); },
                        rewardedBreak: function() { return Promise.resolve(true); }
                    };
                </script>`;
                html = html.replace(pokiScriptTag, injection);
            } else if (scenario === 'MOCK_DELAYED') {
                const injection = `
                <script>
                    setTimeout(function() {
                        window.PokiSDK = {
                            init: function() { return Promise.resolve(); },
                            gameLoadingFinished: function() {},
                            gameplayStart: function() {},
                            gameplayStop: function() {}
                        };
                    }, 500);
                </script>`;
                html = html.replace(pokiScriptTag, injection);
            } else if (scenario === 'MOCK_REJECT') {
                const injection = `
                <script>
                    window.PokiSDK = {
                        init: function() {
                            return Promise.reject(new Error("Adblocker active / init rejected"));
                        }
                    };
                </script>`;
                html = html.replace(pokiScriptTag, injection);
            } else if (scenario === 'MOCK_MISSING') {
                html = html.replace(pokiScriptTag, '<!-- PokiSDK offline/missing -->');
            }

            res.writeHead(200);
            res.end(html);
            return;
        }

        const stream = fs.createReadStream(filePath);
        res.writeHead(200);
        stream.pipe(res);
    });
}

// -------------------------------------------------------------------
// Launch Chrome with Remote Debugging and Attach CDP
// -------------------------------------------------------------------
async function launchChromeWithCDP(port, debuggingPort, onNewDocumentScript = null) {
    const chromeArgs = [
        '--headless=new',
        '--no-sandbox',
        '--disable-gpu',
        '--disable-dev-shm-usage',
        `--remote-debugging-port=${debuggingPort}`,
        'about:blank'
    ];

    const proc = spawn(CHROME_PATH, chromeArgs);

    let pageWsUrl = null;
    const start = Date.now();
    while (Date.now() - start < 6000) {
        try {
            const res = await fetch(`http://127.0.0.1:${debuggingPort}/json`);
            const pages = await res.json();
            const page = pages.find(p => p.type === 'page');
            if (page && page.webSocketDebuggerUrl) {
                pageWsUrl = page.webSocketDebuggerUrl;
                break;
            }
        } catch (_) {}
        await sleep(150);
    }

    if (!pageWsUrl) {
        proc.kill();
        throw new Error(`Failed to obtain Chrome CDP WebSocket on port ${debuggingPort}`);
    }

    const client = new CDPClient(pageWsUrl);
    await client.connected;

    // Enable CDP domains BEFORE navigation
    await client.send('Network.enable');
    await client.send('Runtime.enable');
    await client.send('Page.enable');

    if (onNewDocumentScript) {
        await client.send('Page.addScriptToEvaluateOnNewDocument', {
            source: onNewDocumentScript
        });
    }

    // Do NOT navigate yet; caller registers all listeners before triggering navigate()
    return {
        proc,
        client,
        navigate: async () => {
            await client.send('Page.navigate', { url: `http://127.0.0.1:${port}/` });
        }
    };
}

// -------------------------------------------------------------------
// SUITE 1: REAL POKI CDN INTEGRATION (CDP Instrumentation)
// -------------------------------------------------------------------
async function runSuite1RealCDN(port = 8101, debugPort = 9231) {
    console.log('\n======================================================================');
    console.log('SUITE 1: REAL POKI CDN INTEGRATION (CHROME DEVTOOLS PROTOCOL)');
    console.log('======================================================================');

    const serverRequests = [];
    const server = createServer(port, 'REAL_CDN', serverRequests);
    await new Promise(r => server.listen(port, r));

    // 1. Direct HTTPS Pre-flight
    let cdnPreflight = null;
    try {
        cdnPreflight = await verifyOfficialCdnHealth();
    } catch (e) {
        console.error('  [ERROR] Pre-flight failed:', e.message);
    }

    // Pre-document spy strictly recording actual PokiSDK.gameLoadingFinished invocation
    const spyScript = `
        (function() {
            window.__poki_game_loading_finished_called = false;
            let _poki = window.PokiSDK;
            let _glf = undefined;

            function hookPoki(sdk) {
                if (!sdk || sdk.__spy_hooked) return;
                sdk.__spy_hooked = true;
                _glf = sdk.gameLoadingFinished;
                Object.defineProperty(sdk, 'gameLoadingFinished', {
                    configurable: true,
                    enumerable: true,
                    get: function() {
                        return function(...args) {
                            window.__poki_game_loading_finished_called = true;
                            if (typeof _glf === 'function') {
                                return _glf.apply(this, args);
                            }
                        };
                    },
                    set: function(fn) {
                        _glf = fn;
                    }
                });
            }

            Object.defineProperty(window, 'PokiSDK', {
                configurable: true,
                enumerable: true,
                get: function() { return _poki; },
                set: function(sdk) {
                    _poki = sdk;
                    hookPoki(sdk);
                }
            });

            const pollInterval = setInterval(function() {
                if (window.PokiSDK) {
                    hookPoki(window.PokiSDK);
                    if (window.PokiSDK.__spy_hooked) clearInterval(pollInterval);
                }
            }, 5);
            setTimeout(function() { clearInterval(pollInterval); }, 15000);
        })();
    `;

    const { proc, client, navigate } = await launchChromeWithCDP(port, debugPort, spyScript);

    // Track network events via CDP - ALL REGISTERED BEFORE Page.navigate
    const networkRequests = new Map();
    const networkResponses = [];
    const networkFailures = [];
    const externalFailures = [];
    const canceledRequests = [];
    const http404s = [];
    const external404s = [];
    let pokiCdnReq = null;
    let pokiCdnRes = null;
    let pokiCdnFinished = false;
    let pokiCdnFailed = false;

    // Helper: strictly isolate local game server & official Poki CDN from third-party domains
    function isTargetResourceUrl(url) {
        if (!url || typeof url !== 'string') return false;
        if (url.startsWith(`http://127.0.0.1:${port}`) || url.startsWith(`http://localhost:${port}`)) {
            return true;
        }
        if (url.includes('game-cdn.poki.com') || url.includes('poki-sdk')) {
            return true;
        }
        return false;
    }

    client.on('Network.requestWillBeSent', (params) => {
        networkRequests.set(params.requestId, params);
        if (params.request.url.includes('game-cdn.poki.com/scripts/v2/poki-sdk.js')) {
            pokiCdnReq = params.request;
            console.log(`  [CDP Network] Chrome requested Poki CDN: ${params.request.url}`);
        }
    });

    client.on('Network.responseReceived', (params) => {
        networkResponses.push(params.response);
        const url = params.response.url;
        if (params.response.status === 404) {
            if (isTargetResourceUrl(url)) {
                http404s.push(url);
                console.error(`  [CDP Game Network 404] Game/CDN resource not found: ${url}`);
            } else {
                external404s.push(url);
                console.log(`  [CDP External 404 Logged] External non-game resource 404: ${url}`);
            }
        }
        if (url.includes('game-cdn.poki.com/scripts/v2/poki-sdk.js')) {
            pokiCdnRes = params.response;
            console.log(`  [CDP Network] Poki CDN response: ${params.response.status} (${params.response.mimeType})`);
        }
    });

    client.on('Network.loadingFinished', (params) => {
        const req = networkRequests.get(params.requestId);
        if (req && req.request.url.includes('game-cdn.poki.com/scripts/v2/poki-sdk.js')) {
            pokiCdnFinished = true;
            console.log(`  [CDP Network] Poki CDN loading finished successfully.`);
        }
    });

    client.on('Network.loadingFailed', (params) => {
        const req = networkRequests.get(params.requestId);
        const url = req ? req.request.url : 'unknown';
        const isPoki = url.includes('game-cdn.poki.com') || url.includes('poki-sdk');
        const isTarget = isTargetResourceUrl(url);

        if (isPoki) {
            pokiCdnFailed = true;
            console.error(`  [CDP Poki CDN Failure] Poki CDN request failed: ${params.errorText}`);
        }

        if (params.canceled) {
            canceledRequests.push({ url, errorText: params.errorText, type: params.type, isTarget });
            console.log(`  [CDP Canceled Request] ${url} (${params.errorText}) [target: ${isTarget}]`);
            // Required target resource (local game or Poki CDN) cancellation is a fatal failure!
            if (isTarget && !url.includes('about:blank') && url !== 'unknown') {
                networkFailures.push({
                    url,
                    errorText: `${params.errorText} (canceled)`,
                    type: params.type
                });
            }
        } else {
            // Resource-aware: only fail on Poki CDN or local game resource failures
            if (isTarget) {
                networkFailures.push({ url, errorText: params.errorText, type: params.type });
                console.error(`  [CDP Game Network Failed] ${url}: ${params.errorText}`);
            } else {
                externalFailures.push({ url, errorText: params.errorText, type: params.type });
                console.log(`  [CDP External Block Ignored] ${url}: ${params.errorText}`);
            }
        }
    });

    // Track console & runtime errors - ALL REGISTERED BEFORE Page.navigate
    const consoleErrors = [];
    const runtimeExceptions = [];
    client.on('Runtime.consoleAPICalled', (params) => {
        if (params.type === 'error') {
            const text = params.args ? params.args.map(a => a.value || a.description || '').join(' ') : '';
            consoleErrors.push({ text, timestamp: params.timestamp });
            console.warn(`  [CDP Console Error]: ${text}`);
        }
    });
    client.on('Runtime.exceptionThrown', (params) => {
        runtimeExceptions.push(params.exceptionDetails);
        console.warn(`  [CDP Runtime Exception]:`, params.exceptionDetails.text);
    });

    // All listeners active -> begin navigation!
    await navigate();

    // Synchronize by waiting until Godot reaches SdkState.READY in runtime
    console.log('  [CDP Sync] Awaiting Godot SdkState.READY in browser runtime...');
    const readyStateReached = await waitForCondition(async () => {
        const state = await client.evaluate('window.godot_poki_state');
        return state && state.sdk_state === 2; // SdkState.READY
    }, 15000);

    // Collect direct runtime assertions
    const sdkObjectValid = await client.evaluate(
        'typeof window.PokiSDK === "object" && ' +
        'typeof window.PokiSDK.init === "function" && ' +
        'typeof window.PokiSDK.commercialBreak === "function" && ' +
        'typeof window.PokiSDK.rewardedBreak === "function" && ' +
        'typeof window.PokiSDK.gameLoadingFinished === "function"'
    );

    // Strictly require pre-document spy to record SDK method invocation
    console.log('  [CDP Sync] Awaiting PokiSDK.gameLoadingFinished() invocation...');
    const gameLoadingFinishedInvoked = await waitForCondition(async () => {
        return await client.evaluate('window.__poki_game_loading_finished_called === true');
    }, 8000);

    const webglContextValid = await client.evaluate(`
        (function() {
            const canvas = document.getElementById('canvas');
            if (!canvas || !(canvas instanceof HTMLCanvasElement)) return false;
            const gl = canvas.getContext('webgl2') || canvas.getContext('webgl');
            if (!gl) return false;
            if (typeof gl.isContextLost === 'function' && gl.isContextLost()) return false;
            return typeof gl.drawArrays === 'function' || typeof gl.clear === 'function';
        })()
    `);

    const levelCount = await client.evaluate('window.godot_level_count');
    const pokiState = await client.evaluate('window.godot_poki_state');

    // Clean up Chrome & Server
    client.close();
    proc.kill();
    await new Promise(r => server.close(r));

    // Assertions Evaluation (15 granular assertions)
    const checks = [
        { name: '1. Official Poki CDN Pre-flight: HTTP 200, valid JS, >5KB', pass: cdnPreflight !== null && cdnPreflight.ok === true },
        { name: '2. Chrome requested official Poki CDN script via CDP (Network.requestWillBeSent)', pass: pokiCdnReq !== null },
        { name: '3. Official Poki CDN returned HTTP status 200 (Network.responseReceived)', pass: pokiCdnRes !== null && pokiCdnRes.status === 200 },
        { name: '4. Official Poki CDN returned JavaScript MIME type (text/javascript)', pass: pokiCdnRes !== null && (pokiCdnRes.mimeType.includes('javascript') || pokiCdnRes.mimeType.includes('ecmascript')) },
        { name: '5. Official Poki CDN script loading completed cleanly (Network.loadingFinished)', pass: pokiCdnFinished === true && pokiCdnFailed === false },
        { name: '6. window.PokiSDK object & required methods exist in browser runtime', pass: sdkObjectValid === true },
        { name: '7. PokiSDK.gameLoadingFinished() was actually called by Godot runtime', pass: gameLoadingFinishedInvoked === true },
        { name: '8. WebGL context created and active on #canvas (not lost, functions valid)', pass: webglContextValid === true },
        { name: '9. Godot LevelDatabase: exactly 60 canonical levels loaded in runtime', pass: levelCount === 60 },
        { name: '10. Godot PokiService reached SdkState.READY (state === 2)', pass: readyStateReached !== false && pokiState && pokiState.sdk_state === 2 },
        { name: '11. Godot PokiService reports is_poki_available is true', pass: pokiState && pokiState.is_poki_available === true },
        { name: '12. Zero fatal JS / WASM runtime exceptions via CDP (Runtime.exceptionThrown)', pass: runtimeExceptions.length === 0 },
        { name: '13. Zero console error events via CDP (Runtime.consoleAPICalled type===error)', pass: consoleErrors.length === 0 },
        { name: '14. Zero relevant game/CDN network loading failures via CDP (Network.loadingFailed)', pass: networkFailures.length === 0 && pokiCdnFailed === false },
        { name: '15. Zero HTTP 404 game/CDN network responses collected via CDP', pass: http404s.length === 0 }
    ];

    console.log('\n--- SUITE 1 VERIFICATION RESULTS ---');
    let suite1Pass = true;
    for (const c of checks) {
        const mark = c.pass ? 'PASS' : 'FAIL';
        console.log(`  [${mark}] ${c.name}`);
        if (!c.pass) suite1Pass = false;
    }
    console.log(`SUITE 1 OVERALL: ${suite1Pass ? 'PASSED' : 'FAILED'}`);
    return {
        pass: suite1Pass,
        checks,
        runtimeExceptions: runtimeExceptions.length,
        consoleErrors: consoleErrors.length,
        networkFailures: networkFailures.length,
        externalFailures: externalFailures.length,
        canceledRequests: canceledRequests.length,
        http404s: http404s.length,
        external404s: external404s.length
    };
}

// -------------------------------------------------------------------
// SUITE 2: REAL GODOT WASM + JAVASCRIPTBRIDGE + MOCK POKI PROMISE E2E
// -------------------------------------------------------------------
async function runSuite2RealJSBridgeE2E(port = 8102, debugPort = 9232) {
    console.log('\n======================================================================');
    console.log('SUITE 2: REAL GODOT WASM + JAVASCRIPTBRIDGE + MOCK POKI PROMISE E2E TESTS');
    console.log('Note: Godot WASM engine & JavaScriptBridge run real production code.');
    console.log('PokiSDK is an injected mock queue for precise Promise delay & rejection tests.');
    console.log('======================================================================');

    const serverRequests = [];
    const server = createServer(port, 'REAL_JSBRIDGE_E2E', serverRequests);
    await new Promise(r => server.listen(port, r));

    const { proc, client, navigate } = await launchChromeWithCDP(port, debugPort);
    await navigate();

    // Wait until Godot finishes loading and Web Bridge is ready
    console.log('  [CDP Sync] Awaiting Godot Web Bridge initialization...');
    const ready = await waitForCondition(async () => {
        const state = await client.evaluate('window.godot_poki_state');
        const triggerReady = await client.evaluate('typeof window.godot_trigger_commercial_break === "function"');
        return state && state.sdk_state === 2 && triggerReady;
    }, 15000);

    if (!ready) {
        client.close();
        proc.kill();
        await new Promise(r => server.close(r));
        throw new Error('Godot Web export failed to reach ready state in Chrome.');
    }

    const testResults = [];

    // -----------------------------------------------------------
    // Test 2.1: Real JSBridge Commercial: Callback Retention, Delay & Stale Guard
    // Ssenariy:
    //   Ad A: 400ms delay Promise
    //   Timeout: 100ms
    //   Ad B: 400ms delay Promise
    //   t=400ms: Ad A Promise resolves -> GDScript token guard discards -> Ad B stays active!
    //   t=~550ms: Ad B Promise resolves -> Ad B finishes cleanly.
    // -----------------------------------------------------------
    console.log('\n  [Test 2.1] Real JSBridge Commercial: Callback Retention, Delay & Stale Guard...');
    await client.evaluate('window.godot_poki_reset_ad_state()');
    const initCommState = await client.evaluate('window.godot_poki_state');
    const initCommClean = initCommState.active_callbacks_count === 0;

    await client.evaluate('window.__test_commercial_queue = [{ delay: 400, reject: false }, { delay: 400, reject: false }]');
    await client.evaluate('window.godot_set_ad_timeout(0.10)'); // 100ms timeout for Ad A

    const t0Comm = Date.now();
    // 1. Start Ad A
    await client.evaluate('window.godot_trigger_commercial_break()');
    const stateA1 = await client.evaluate('window.godot_poki_state');
    const tokenA = stateA1.ad_token;
    const adAStarted = stateA1.is_ad_playing === true && stateA1.current_ad_type === 1;
    // Callback retained in dictionary while pending
    const cbARetained = stateA1.active_callbacks_count === 1
        && stateA1.active_callbacks_tokens.map(Number).includes(Number(tokenA));

    // 2. Wait for Ad A timeout (100ms)
    const timedOut = await waitForCondition(async () => {
        const s = await client.evaluate('window.godot_poki_state');
        return s.is_ad_playing === false;
    }, 1500);
    const stateATimedOut = await client.evaluate('window.godot_poki_state');
    // Callback released upon timeout
    const cbAReleasedOnTimeout = stateATimedOut.active_callbacks_count === 0;

    // 3. Start Ad B with 2.0s timeout
    await client.evaluate('window.godot_set_ad_timeout(2.0)');
    await client.evaluate('window.godot_trigger_commercial_break()');
    const stateB1 = await client.evaluate('window.godot_poki_state');
    const tokenB = stateB1.ad_token;
    const adBStarted = stateB1.is_ad_playing === true && tokenB > tokenA;
    // Callback B retained
    const cbBRetained = stateB1.active_callbacks_count === 1
        && stateB1.active_callbacks_tokens.map(Number).includes(Number(tokenB));

    // 4. Wait until t=440ms (Ad A's 400ms promise resolves across real JSBridge)
    const elapsedComm = Date.now() - t0Comm;
    if (elapsedComm < 440) {
        await sleep(440 - elapsedComm);
    }
    const stateBDuringLateA = await client.evaluate('window.godot_poki_state');
    // Ad B MUST STILL BE ACTIVE and Callback B still retained!
    const adBSurvivedStaleA = stateBDuringLateA.is_ad_playing === true
        && stateBDuringLateA.ad_token === tokenB;
    const cbBRetainedAfterStaleA = stateBDuringLateA.active_callbacks_count === 1
        && stateBDuringLateA.active_callbacks_tokens.map(Number).includes(Number(tokenB));

    // 5. Wait for Ad B's promise to finish cleanly
    const adBFinished = await waitForCondition(async () => {
        const s = await client.evaluate('window.godot_poki_state');
        return s.is_ad_playing === false;
    }, 2000);
    const finalCommercialState = await client.evaluate('window.godot_poki_state');
    const cbBReleasedOnFinish = finalCommercialState.active_callbacks_count === 0;

    const pass21 = initCommClean && adAStarted && cbARetained && timedOut
        && cbAReleasedOnTimeout && adBStarted && cbBRetained && adBSurvivedStaleA
        && cbBRetainedAfterStaleA && adBFinished && cbBReleasedOnFinish
        && finalCommercialState.last_commercial_succeeded === true;

    testResults.push({
        name: '2.1 Real JSBridge Commercial: Ad A 400ms -> timeout 100ms -> Ad B 400ms -> Stale A ignored -> B finished cleanly (callback retention & release verified)',
        pass: pass21
    });
    console.log(`    -> Result: ${pass21 ? 'PASS' : 'FAIL'}`);

    // -----------------------------------------------------------
    // Test 2.2: Real JSBridge Rewarded: Callback Retention, Delay & Stale Guard
    // -----------------------------------------------------------
    console.log('\n  [Test 2.2] Real JSBridge Rewarded: Callback Retention, Delay & Stale Guard...');
    await client.evaluate('window.godot_poki_reset_ad_state()');
    const initRewState = await client.evaluate('window.godot_poki_state');
    const initRewClean = initRewState.active_callbacks_count === 0;

    await client.evaluate('window.__test_rewarded_queue = [{ delay: 400, reject: false, success: true }, { delay: 400, reject: false, success: true }]');
    await client.evaluate('window.godot_set_ad_timeout(0.10)');

    const t0Rew = Date.now();
    // 1. Start Rewarded Ad A
    await client.evaluate('window.godot_trigger_rewarded_break()');
    const stateRewA1 = await client.evaluate('window.godot_poki_state');
    const tokenRewA = stateRewA1.ad_token;
    const rewAStarted = stateRewA1.is_ad_playing === true && stateRewA1.current_ad_type === 2;
    const cbRewARetained = stateRewA1.active_callbacks_count === 1
        && stateRewA1.active_callbacks_tokens.map(Number).includes(Number(tokenRewA));

    // 2. Wait for Ad A timeout
    const rewTimedOut = await waitForCondition(async () => {
        const s = await client.evaluate('window.godot_poki_state');
        return s.is_ad_playing === false;
    }, 1500);
    const stateRewATimedOut = await client.evaluate('window.godot_poki_state');
    const cbRewAReleasedOnTimeout = stateRewATimedOut.active_callbacks_count === 0;

    // 3. Start Rewarded Ad B
    await client.evaluate('window.godot_set_ad_timeout(2.0)');
    await client.evaluate('window.godot_trigger_rewarded_break()');
    const stateRewB1 = await client.evaluate('window.godot_poki_state');
    const tokenRewB = stateRewB1.ad_token;
    const rewBStarted = stateRewB1.is_ad_playing === true && tokenRewB > tokenRewA;
    const cbRewBRetained = stateRewB1.active_callbacks_count === 1
        && stateRewB1.active_callbacks_tokens.map(Number).includes(Number(tokenRewB));

    // 4. Wait for late Ad A resolution (t=440ms)
    const elapsedRew = Date.now() - t0Rew;
    if (elapsedRew < 440) {
        await sleep(440 - elapsedRew);
    }
    const stateRewBDuringLateA = await client.evaluate('window.godot_poki_state');
    const rewBSurvivedStaleA = stateRewBDuringLateA.is_ad_playing === true
        && stateRewBDuringLateA.ad_token === tokenRewB;
    const cbRewBRetainedAfterStaleA = stateRewBDuringLateA.active_callbacks_count === 1
        && stateRewBDuringLateA.active_callbacks_tokens.map(Number).includes(Number(tokenRewB));

    // 5. Wait for Ad B to finish
    const rewBFinished = await waitForCondition(async () => {
        const s = await client.evaluate('window.godot_poki_state');
        return s.is_ad_playing === false;
    }, 2000);
    const finalRewState = await client.evaluate('window.godot_poki_state');
    const cbRewBReleasedOnFinish = finalRewState.active_callbacks_count === 0;

    const pass22 = initRewClean && rewAStarted && cbRewARetained && rewTimedOut
        && cbRewAReleasedOnTimeout && rewBStarted && cbRewBRetained && rewBSurvivedStaleA
        && cbRewBRetainedAfterStaleA && rewBFinished && cbRewBReleasedOnFinish
        && finalRewState.last_rewarded_succeeded === true;

    testResults.push({
        name: '2.2 Real JSBridge Rewarded: Ad A 400ms -> timeout 100ms -> Ad B 400ms -> Stale A ignored -> B finished cleanly (callback retention & release verified)',
        pass: pass22
    });
    console.log(`    -> Result: ${pass22 ? 'PASS' : 'FAIL'}`);

    // -----------------------------------------------------------
    // Test 2.3: Real JSBridge Commercial Break Promise Rejection (Catch)
    // -----------------------------------------------------------
    console.log('\n  [Test 2.3] Real JSBridge Commercial Break Promise Rejection...');
    await client.evaluate('window.godot_poki_reset_ad_state()');
    await client.evaluate('window.__test_commercial_queue = [{ delay: 300, reject: true }]');
    await client.evaluate('window.godot_trigger_commercial_break()');

    const stateCommRejDuring = await client.evaluate('window.godot_poki_state');
    const commRejRetained = stateCommRejDuring.active_callbacks_count === 1;

    const commRejectedFinished = await waitForCondition(async () => {
        const s = await client.evaluate('window.godot_poki_state');
        return s.is_ad_playing === false;
    }, 2000);
    const commRejectState = await client.evaluate('window.godot_poki_state');
    const commRejReleased = commRejectState.active_callbacks_count === 0;
    const commRejSuccessFalse = commRejectState.last_commercial_succeeded === false;

    const pass23 = commRejRetained && commRejectedFinished && commRejReleased && commRejSuccessFalse;
    testResults.push({
        name: '2.3 Real JSBridge Commercial Promise Rejection caught gracefully (success: false, callback released)',
        pass: pass23
    });
    console.log(`    -> Result: ${pass23 ? 'PASS' : 'FAIL'}`);

    // -----------------------------------------------------------
    // Test 2.4: Real JSBridge Rewarded Break Promise Rejection (Catch)
    // -----------------------------------------------------------
    console.log('\n  [Test 2.4] Real JSBridge Rewarded Break Promise Rejection...');
    await client.evaluate('window.godot_poki_reset_ad_state()');
    await client.evaluate('window.__test_rewarded_queue = [{ delay: 300, reject: true }]');
    await client.evaluate('window.godot_trigger_rewarded_break()');

    const stateRewRejDuring = await client.evaluate('window.godot_poki_state');
    const rewRejRetained = stateRewRejDuring.active_callbacks_count === 1;

    const rewRejectedFinished = await waitForCondition(async () => {
        const s = await client.evaluate('window.godot_poki_state');
        return s.is_ad_playing === false;
    }, 2000);
    const rewRejectState = await client.evaluate('window.godot_poki_state');
    const rewRejReleased = rewRejectState.active_callbacks_count === 0;
    const rewRejSuccessFalse = rewRejectState.last_rewarded_succeeded === false;

    const pass24 = rewRejRetained && rewRejectedFinished && rewRejReleased && rewRejSuccessFalse;
    testResults.push({
        name: '2.4 Real JSBridge Rewarded Promise Rejection caught gracefully (success: false, callback released)',
        pass: pass24
    });
    console.log(`    -> Result: ${pass24 ? 'PASS' : 'FAIL'}`);

    // Clean up
    client.close();
    proc.kill();
    await new Promise(r => server.close(r));

    console.log('\n--- SUITE 2 VERIFICATION RESULTS ---');
    let suite2Pass = true;
    for (const t of testResults) {
        const mark = t.pass ? 'PASS' : 'FAIL';
        console.log(`  [${mark}] ${t.name}`);
        if (!t.pass) suite2Pass = false;
    }
    console.log(`SUITE 2 OVERALL: ${suite2Pass ? 'PASSED' : 'FAILED'}`);
    return { pass: suite2Pass, results: testResults };
}

// -------------------------------------------------------------------
// SUITE 3: BROWSER FAULT INJECTION (4 Scenarios via CDP)
// -------------------------------------------------------------------
async function runSuite3MockFaultInjection(basePort = 8103, baseDebugPort = 9233) {
    console.log('\n======================================================================');
    console.log('SUITE 3: BROWSER FAULT INJECTION (4 SCENARIOS VIA CDP)');
    console.log('Testing browser resilience against network failure, late SDK, adblock & missing script.');
    console.log('Asserts state/availability AND active engine game loop responsiveness.');
    console.log('======================================================================');

    const scenarios = [
        { name: 'MOCK_SUCCESS', expectedState: 2, expectedAvail: true,  timeout: 8000 },
        { name: 'MOCK_DELAYED', expectedState: 2, expectedAvail: true,  timeout: 9000 },
        { name: 'MOCK_REJECT',  expectedState: 3, expectedAvail: false, timeout: 8000 },
        { name: 'MOCK_MISSING', expectedState: 3, expectedAvail: false, timeout: 10000 }
    ];

    const results = [];
    let suite3Pass = true;

    for (let i = 0; i < scenarios.length; i++) {
        const sc = scenarios[i];
        const port = basePort + i;
        const debugPort = baseDebugPort + i;
        console.log(`\n  [Scenario ${i + 1}/4] ${sc.name}...`);

        const serverRequests = [];
        const server = createServer(port, sc.name, serverRequests);
        await new Promise(r => server.listen(port, r));

        const { proc, client, navigate } = await launchChromeWithCDP(port, debugPort);
        await navigate();

        // 1. Wait for target SdkState
        const stateReached = await waitForCondition(async () => {
            const s = await client.evaluate('window.godot_poki_state');
            return s && s.sdk_state === sc.expectedState && s.is_poki_available === sc.expectedAvail;
        }, sc.timeout);

        // 2. Responsiveness check: verify engine game loop is actively processing frames!
        const f1 = await client.evaluate('window.godot_process_frames || 0');
        await sleep(250);
        const f2 = await client.evaluate('window.godot_process_frames || 0');
        const loopRunning = f2 > f1;

        client.close();
        proc.kill();
        await new Promise(r => server.close(r));

        const pass = Boolean(stateReached && loopRunning);
        const mark = pass ? 'PASS' : 'FAIL';
        console.log(`    -> State reached:  ${Boolean(stateReached)} (expected state=${sc.expectedState}, avail=${sc.expectedAvail})`);
        console.log(`    -> Engine loop:    ${loopRunning ? 'RUNNING (frames ' + f1 + ' -> ' + f2 + ')' : 'STALLED'}`);
        console.log(`    -> Result: [${mark}] Scenario ${sc.name}`);
        if (!pass) suite3Pass = false;
        results.push({
            name: `${sc.name} (state=${sc.expectedState}, avail=${sc.expectedAvail}, loop=${loopRunning})`,
            pass
        });
    }

    console.log('\n--- SUITE 3 VERIFICATION RESULTS ---');
    for (const r of results) {
        console.log(`  [${r.pass ? 'PASS' : 'FAIL'}] Scenario ${r.name}`);
    }
    console.log(`SUITE 3 OVERALL: ${suite3Pass ? 'PASSED' : 'FAILED'}`);
    return { pass: suite3Pass, results };
}

// -------------------------------------------------------------------
// Main Master Runner
// -------------------------------------------------------------------
async function main() {
    const chromeVer = getChromeVersion(CHROME_PATH);
    console.log('======================================================================');
    console.log('WRONG WAY — MASTER BROWSER AUDIT SUITE (CHROME DEVTOOLS PROTOCOL)');
    console.log('Chrome Binary:  ', CHROME_PATH);
    console.log('Chrome Version: ', chromeVer);
    console.log('======================================================================');

    if (!fs.existsSync(CHROME_PATH)) {
        console.error(`ERROR: Chrome binary not found at ${CHROME_PATH}`);
        process.exit(1);
    }

    let s1, s2, s3;
    try {
        s1 = await runSuite1RealCDN(8101, 9231);
        s2 = await runSuite2RealJSBridgeE2E(8102, 9232);
        s3 = await runSuite3MockFaultInjection(8103, 9233);
    } catch (err) {
        console.error('\n[FATAL RUNNER ERROR]:', err);
        process.exit(1);
    }

    console.log('\n======================================================================');
    console.log('FINAL AUDIT SUMMARY:');
    console.log(`  Suite 1 (Real Poki CDN):                 ${s1.pass ? 'PASSED' : 'FAILED'}`);
    console.log(`  Suite 2 (Real JSBridge Mock E2E):        ${s2.pass ? 'PASSED' : 'FAILED'}`);
    console.log(`  Suite 3 (Mock Fault Injection 4/4):      ${s3.pass ? 'PASSED' : 'FAILED'}`);
    console.log('======================================================================');

    const allPassed = s1.pass && s2.pass && s3.pass;
    if (allPassed) {
        console.log('\nEXIT 0: All Browser Verification Contracts PASSED cleanly.');
        process.exit(0);
    } else {
        console.error('\nEXIT 1: Verification failed.');
        process.exit(1);
    }
}

main().catch(e => {
    console.error('Unhandled fatal error in master runner:', e);
    process.exit(1);
});
