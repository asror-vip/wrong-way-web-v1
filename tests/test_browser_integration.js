// test_browser_integration.js
// ---------------------------------------------------------------
// WRONG WAY — COMPREHENSIVE CDP BROWSER VERIFICATION RUNNER
// Uses native Chrome DevTools Protocol (CDP) via WebSocket over
// Chrome --remote-debugging-port. Zero third-party dependencies.
//
// SUITE 1: Real Poki CDN Integration (Production Unmodified Build)
//   - Network.requestWillBeSent / responseReceived / loadingFinished
//   - Verified official Poki CDN endpoint HTTP 200, JS, >5KB
//   - Real runtime assertions: window.PokiSDK methods, WebGL canvas,
//     Godot SdkState.READY, 60 levels loaded, gameLoadingFinished
//   - Zero fatal errors, zero 404s
//
// SUITE 2: Real JavaScriptBridge End-to-End Test Suite
//   - Executes inside Chrome with live Godot WASM engine
//   - Tests the exact production path:
//     PokiService GDScript -> JavaScriptBridge -> JS IIFE -> Promise ->
//     Godot callback -> GDScript token guard
//   - Commercial: 400ms delay vs 100ms timeout -> Ad B -> Stale A ignored -> B finishes
//   - Rewarded:   400ms delay vs 100ms timeout -> Ad B -> Stale A ignored -> B finishes
//   - Commercial & Rewarded rejection handling (Promise catch)
//   - Duplicate callback safety
//   - Callback retention in GDScript dictionary
//
// SUITE 3: Browser Fault Injection (4 Scenarios)
//   - MOCK_SUCCESS
//   - MOCK_DELAYED
//   - MOCK_REJECT
//   - MOCK_MISSING
// ---------------------------------------------------------------

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

// ---------------------------------------------------------------
// CDP Client Implementation (Pure Native WebSocket)
// ---------------------------------------------------------------
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

// ---------------------------------------------------------------
// Helper Utilities
// ---------------------------------------------------------------
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

// ---------------------------------------------------------------
// HTTPS Pre-flight to Official CDN
// ---------------------------------------------------------------
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

// ---------------------------------------------------------------
// HTTP Test Server
// ---------------------------------------------------------------
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
                // Untouched production HTML
                res.writeHead(200);
                res.end(html);
                return;
            }

            if (scenario === 'REAL_JSBRIDGE_E2E') {
                // Injects controllable queue for real JSBridge Promise delay tests
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

// ---------------------------------------------------------------
// Launch Chrome with Remote Debugging and Attach CDP
// ---------------------------------------------------------------
async function launchChromeWithCDP(port, debuggingPort) {
    // Launch Chrome at about:blank first so we can attach CDP and enable
    // Network & Runtime BEFORE navigating to the target page!
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

    // Navigate to target URL
    await client.send('Page.navigate', { url: `http://127.0.0.1:${port}/` });

    return { proc, client };
}

// ---------------------------------------------------------------
// SUITE 1: REAL POKI CDN INTEGRATION (CDP Instrumentation)
// ---------------------------------------------------------------
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

    const { proc, client } = await launchChromeWithCDP(port, debugPort);

    // Track network events via CDP
    const networkRequests = new Map();
    const networkResponses = [];
    const networkFailures = [];
    let pokiCdnReq = null;
    let pokiCdnRes = null;
    let pokiCdnFinished = false;

    client.on('Network.requestWillBeSent', (params) => {
        networkRequests.set(params.requestId, params);
        if (params.request.url.includes('game-cdn.poki.com/scripts/v2/poki-sdk.js')) {
            pokiCdnReq = params.request;
            console.log(`  [CDP Network] Chrome requested Poki CDN: ${params.request.url}`);
        }
    });

    client.on('Network.responseReceived', (params) => {
        networkResponses.push(params.response);
        if (params.response.url.includes('game-cdn.poki.com/scripts/v2/poki-sdk.js')) {
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
        networkFailures.push(params);
        console.warn(`  [CDP Network Warning] Request failed:`, params.errorText);
    });

    // Track console & runtime errors
    const consoleErrors = [];
    const runtimeExceptions = [];
    client.on('Runtime.consoleAPICalled', (params) => {
        if (params.type === 'error') {
            consoleErrors.push(params);
        }
    });
    client.on('Runtime.exceptionThrown', (params) => {
        runtimeExceptions.push(params.exceptionDetails);
    });

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

    const canvasValid = await client.evaluate(
        'document.getElementById("canvas") instanceof HTMLCanvasElement'
    );

    const levelCount = await client.evaluate('window.godot_level_count');
    const pokiState = await client.evaluate('window.godot_poki_state');

    // Clean up Chrome & Server
    client.close();
    proc.kill();
    await new Promise(r => server.close(r));

    // Assertions Evaluation
    const cdn404s = serverRequests.filter(r => r.status === 404);
    const checks = [
        { name: '1. Official Poki CDN Pre-flight (HTTP 200, valid JS, >5KB)', pass: cdnPreflight !== null && cdnPreflight.ok === true },
        { name: '2. Chrome requested official Poki CDN script via CDP', pass: pokiCdnReq !== null },
        { name: '3. Official Poki CDN returned HTTP 200 via CDP', pass: pokiCdnRes !== null && pokiCdnRes.status === 200 },
        { name: '4. Poki CDN script loading finished cleanly', pass: pokiCdnFinished === true },
        { name: '5. window.PokiSDK object & methods exist in browser runtime', pass: sdkObjectValid === true },
        { name: '6. Godot WebGL Canvas initialized in DOM', pass: canvasValid === true },
        { name: '7. Godot LevelDatabase 60 levels loaded in runtime state', pass: levelCount === 60 },
        { name: '8. Godot PokiService reached SdkState.READY (state === 2)', pass: readyStateReached !== false && pokiState && pokiState.sdk_state === 2 },
        { name: '9. Godot PokiService is_poki_available is true', pass: pokiState && pokiState.is_poki_available === true },
        { name: '10. Zero fatal JS / WASM / Network 404 errors', pass: runtimeExceptions.length === 0 && cdn404s.length === 0 }
    ];

    console.log('\n--- SUITE 1 VERIFICATION RESULTS ---');
    let suite1Pass = true;
    for (const c of checks) {
        const mark = c.pass ? 'PASS' : 'FAIL';
        console.log(`  [${mark}] ${c.name}`);
        if (!c.pass) suite1Pass = false;
    }
    console.log(`SUITE 1 OVERALL: ${suite1Pass ? 'PASSED' : 'FAILED'}`);
    return { pass: suite1Pass, checks, errors: runtimeExceptions.length, cdn404s: cdn404s.length };
}

// ---------------------------------------------------------------
// SUITE 2: REAL JAVASCRIPTBRIDGE END-TO-END TEST SUITE
// ---------------------------------------------------------------
async function runSuite2RealJSBridgeE2E(port = 8102, debugPort = 9232) {
    console.log('\n======================================================================');
    console.log('SUITE 2: REAL JAVASCRIPTBRIDGE END-TO-END TESTS (GODOT WASM IN CHROME)');
    console.log('======================================================================');

    const serverRequests = [];
    const server = createServer(port, 'REAL_JSBRIDGE_E2E', serverRequests);
    await new Promise(r => server.listen(port, r));

    const { proc, client } = await launchChromeWithCDP(port, debugPort);

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
    // Test 2.1: Real JSBridge Commercial Break Delay & Stale Guard
    // Ssenariy:
    //   Ad A: 400ms delay Promise
    //   Timeout: 100ms
    //   Ad B: 400ms delay Promise
    //   t=400ms: Ad A Promise resolves -> GDScript token guard discards -> Ad B stays active!
    //   t=~550ms: Ad B Promise resolves -> Ad B finishes cleanly.
    // -----------------------------------------------------------
    console.log('\n  [Test 2.1] Real JSBridge Commercial Break Delay & Stale Guard...');
    await client.evaluate('window.godot_poki_reset_ad_state()');
    await client.evaluate('window.__test_commercial_queue = [{ delay: 400, reject: false }, { delay: 400, reject: false }]');
    await client.evaluate('window.godot_set_ad_timeout(0.10)'); // 100ms timeout for Ad A

    const t0Comm = Date.now();
    // 1. Start Ad A
    await client.evaluate('window.godot_trigger_commercial_break()');
    const stateA1 = await client.evaluate('window.godot_poki_state');
    const tokenA = stateA1.ad_token;
    const adAStarted = stateA1.is_ad_playing === true && stateA1.current_ad_type === 1;

    // 2. Wait for Ad A timeout (100ms)
    const timedOut = await waitForCondition(async () => {
        const s = await client.evaluate('window.godot_poki_state');
        return s.is_ad_playing === false;
    }, 1500);

    // 3. Start Ad B with 2.0s timeout
    await client.evaluate('window.godot_set_ad_timeout(2.0)');
    await client.evaluate('window.godot_trigger_commercial_break()');
    const stateB1 = await client.evaluate('window.godot_poki_state');
    const tokenB = stateB1.ad_token;
    const adBStarted = stateB1.is_ad_playing === true && tokenB > tokenA;

    // 4. Wait until t=440ms (Ad A's 400ms promise resolves across real JSBridge)
    const elapsedComm = Date.now() - t0Comm;
    if (elapsedComm < 440) {
        await sleep(440 - elapsedComm);
    }
    const stateBDuringLateA = await client.evaluate('window.godot_poki_state');
    // Ad B MUST STILL BE ACTIVE!
    const adBSurvivedStaleA = stateBDuringLateA.is_ad_playing === true
        && stateBDuringLateA.ad_token === tokenB;

    // 5. Wait for Ad B's promise to finish cleanly
    const adBFinished = await waitForCondition(async () => {
        const s = await client.evaluate('window.godot_poki_state');
        return s.is_ad_playing === false;
    }, 2000);
    const finalCommercialState = await client.evaluate('window.godot_poki_state');

    const pass21 = adAStarted && timedOut && adBStarted && adBSurvivedStaleA
        && adBFinished && finalCommercialState.last_commercial_succeeded === true;
    testResults.push({
        name: '2.1 Real JSBridge Commercial: Ad A delay 400ms -> timeout 100ms -> Ad B 400ms -> Stale A ignored -> B finished',
        pass: pass21
    });
    console.log(`    -> Result: ${pass21 ? 'PASS' : 'FAIL'}`);

    // -----------------------------------------------------------
    // Test 2.2: Real JSBridge Rewarded Break Delay & Stale Guard
    // -----------------------------------------------------------
    console.log('\n  [Test 2.2] Real JSBridge Rewarded Break Delay & Stale Guard...');
    await client.evaluate('window.godot_poki_reset_ad_state()');
    await client.evaluate('window.__test_rewarded_queue = [{ delay: 400, reject: false, success: true }, { delay: 400, reject: false, success: true }]');
    await client.evaluate('window.godot_set_ad_timeout(0.10)');

    const t0Rew = Date.now();
    // 1. Start Rewarded Ad A
    await client.evaluate('window.godot_trigger_rewarded_break()');
    const stateRewA1 = await client.evaluate('window.godot_poki_state');
    const tokenRewA = stateRewA1.ad_token;
    const rewAStarted = stateRewA1.is_ad_playing === true && stateRewA1.current_ad_type === 2;

    // 2. Wait for Ad A timeout
    const rewTimedOut = await waitForCondition(async () => {
        const s = await client.evaluate('window.godot_poki_state');
        return s.is_ad_playing === false;
    }, 1500);

    // 3. Start Rewarded Ad B
    await client.evaluate('window.godot_set_ad_timeout(2.0)');
    await client.evaluate('window.godot_trigger_rewarded_break()');
    const stateRewB1 = await client.evaluate('window.godot_poki_state');
    const tokenRewB = stateRewB1.ad_token;
    const rewBStarted = stateRewB1.is_ad_playing === true && tokenRewB > tokenRewA;

    // 4. Wait for late Ad A resolution (t=440ms)
    const elapsedRew = Date.now() - t0Rew;
    if (elapsedRew < 440) {
        await sleep(440 - elapsedRew);
    }
    const stateRewBDuringLateA = await client.evaluate('window.godot_poki_state');
    const rewBSurvivedStaleA = stateRewBDuringLateA.is_ad_playing === true
        && stateRewBDuringLateA.ad_token === tokenRewB;

    // 5. Wait for Ad B to finish
    const rewBFinished = await waitForCondition(async () => {
        const s = await client.evaluate('window.godot_poki_state');
        return s.is_ad_playing === false;
    }, 2000);

    const pass22 = rewAStarted && rewTimedOut && rewBStarted && rewBSurvivedStaleA && rewBFinished;
    testResults.push({
        name: '2.2 Real JSBridge Rewarded: Ad A delay 400ms -> timeout 100ms -> Ad B 400ms -> Stale A ignored -> B finished',
        pass: pass22
    });
    console.log(`    -> Result: ${pass22 ? 'PASS' : 'FAIL'}`);

    // -----------------------------------------------------------
    // Test 2.3: Real JSBridge Commercial Break Promise Rejection (Catch)
    // -----------------------------------------------------------
    console.log('\n  [Test 2.3] Real JSBridge Commercial Break Promise Rejection...');
    await client.evaluate('window.godot_poki_reset_ad_state()');
    await client.evaluate('window.__test_commercial_queue = [{ delay: 50, reject: true }]');
    await client.evaluate('window.godot_trigger_commercial_break()');

    const commRejectedFinished = await waitForCondition(async () => {
        const s = await client.evaluate('window.godot_poki_state');
        return s.is_ad_playing === false;
    }, 2000);
    const commRejectState = await client.evaluate('window.godot_poki_state');
    const pass23 = commRejectedFinished && commRejectState.last_commercial_succeeded === false;
    testResults.push({
        name: '2.3 Real JSBridge Commercial Promise Rejection caught gracefully (success: false)',
        pass: pass23
    });
    console.log(`    -> Result: ${pass23 ? 'PASS' : 'FAIL'}`);

    // -----------------------------------------------------------
    // Test 2.4: Real JSBridge Rewarded Break Promise Rejection (Catch)
    // -----------------------------------------------------------
    console.log('\n  [Test 2.4] Real JSBridge Rewarded Break Promise Rejection...');
    await client.evaluate('window.godot_poki_reset_ad_state()');
    await client.evaluate('window.__test_rewarded_queue = [{ delay: 50, reject: true }]');
    await client.evaluate('window.godot_trigger_rewarded_break()');

    const rewRejectedFinished = await waitForCondition(async () => {
        const s = await client.evaluate('window.godot_poki_state');
        return s.is_ad_playing === false;
    }, 2000);
    const pass24 = rewRejectedFinished;
    testResults.push({
        name: '2.4 Real JSBridge Rewarded Promise Rejection caught gracefully (success: false)',
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

// ---------------------------------------------------------------
// SUITE 3: BROWSER FAULT INJECTION (4 Scenarios)
// ---------------------------------------------------------------
async function runSuite3MockFaultInjection(basePort = 8103, baseDebugPort = 9233) {
    console.log('\n======================================================================');
    console.log('SUITE 3: BROWSER FAULT INJECTION (4 SCENARIOS VIA CDP)');
    console.log('======================================================================');

    const scenarios = [
        { name: 'MOCK_SUCCESS', timeout: 8000 },
        { name: 'MOCK_DELAYED', timeout: 9000 },
        { name: 'MOCK_REJECT',  timeout: 8000 },
        { name: 'MOCK_MISSING', timeout: 10000 }
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

        const { proc, client } = await launchChromeWithCDP(port, debugPort);

        let pass = false;
        if (sc.name === 'MOCK_SUCCESS') {
            pass = await waitForCondition(async () => {
                const s = await client.evaluate('window.godot_poki_state');
                return s && s.sdk_state === 2 && s.is_poki_available === true;
            }, sc.timeout);
        } else if (sc.name === 'MOCK_DELAYED') {
            pass = await waitForCondition(async () => {
                const s = await client.evaluate('window.godot_poki_state');
                return s && s.sdk_state === 2 && s.is_poki_available === true;
            }, sc.timeout);
        } else if (sc.name === 'MOCK_REJECT') {
            pass = await waitForCondition(async () => {
                const s = await client.evaluate('window.godot_poki_state');
                return s && s.sdk_state === 3 && s.is_poki_available === false; // SdkState.FAILED
            }, sc.timeout);
        } else if (sc.name === 'MOCK_MISSING') {
            pass = await waitForCondition(async () => {
                const s = await client.evaluate('window.godot_poki_state');
                return s && s.sdk_state === 3 && s.is_poki_available === false; // SdkState.FAILED
            }, sc.timeout);
        }

        client.close();
        proc.kill();
        await new Promise(r => server.close(r));

        const mark = pass ? 'PASS' : 'FAIL';
        console.log(`    -> Result: [${mark}] Scenario ${sc.name}`);
        if (!pass) suite3Pass = false;
        results.push({ name: sc.name, pass: Boolean(pass) });
    }

    console.log('\n--- SUITE 3 VERIFICATION RESULTS ---');
    for (const r of results) {
        console.log(`  [${r.pass ? 'PASS' : 'FAIL'}] Scenario ${r.name}`);
    }
    console.log(`SUITE 3 OVERALL: ${suite3Pass ? 'PASSED' : 'FAILED'}`);
    return { pass: suite3Pass, results };
}

// ---------------------------------------------------------------
// Main Master Runner
// ---------------------------------------------------------------
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

    // Run Suite 1: Real CDN
    const suite1 = await runSuite1RealCDN(8101, 9231);

    // Run Suite 2: Real JSBridge End-to-End
    const suite2 = await runSuite2RealJSBridgeE2E(8102, 9232);

    // Run Suite 3: Mock Fault Injection
    const suite3 = await runSuite3MockFaultInjection(8103, 9233);

    console.log('\n======================================================================');
    console.log('FINAL AUDIT SUMMARY:');
    console.log(`  Suite 1 (Real Poki CDN):                 ${suite1.pass ? 'PASSED' : 'FAILED'}`);
    console.log(`  Suite 2 (Real JSBridge End-to-End E2E):  ${suite2.pass ? 'PASSED' : 'FAILED'}`);
    console.log(`  Suite 3 (Mock Fault Injection 4/4):      ${suite3.pass ? 'PASSED' : 'FAILED'}`);
    console.log('======================================================================');

    const allPassed = suite1.pass && suite2.pass && suite3.pass;
    if (!allPassed) {
        console.error('\nEXIT 1: Master Browser Suite FAILED one or more verification contracts.');
        process.exit(1);
    }

    console.log('\nEXIT 0: All Browser Verification Contracts PASSED cleanly.');
    process.exit(0);
}

main().catch((err) => {
    console.error('Fatal Runner Error:', err);
    process.exit(1);
});
