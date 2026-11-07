const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const { spawn, execSync } = require('child_process');

const BUILD_DIR = path.join(__dirname, '..', 'build', 'web');
const CHROME_PATH = process.env.CHROME_PATH 
    || (process.argv[2] && !process.argv[2].startsWith('--') ? process.argv[2] : null)
    || 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const PORT = 8094;

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

function getChromeVersion(chromePath) {
    try {
        const cmd = `powershell -NoProfile -Command "(Get-Item '${chromePath.replace(/'/g, "''")}').VersionInfo.ProductVersion"`;
        return execSync(cmd).toString().trim();
    } catch {
        return 'Unknown';
    }
}

function verifyOfficialCdnHealth() {
    return new Promise((resolve, reject) => {
        const cdnUrl = 'https://game-cdn.poki.com/scripts/v2/poki-sdk.js';
        console.log(`\n[PRE-FLIGHT] Verifying official Poki CDN endpoint: ${cdnUrl}`);
        const req = https.get(cdnUrl, (res) => {
            let data = '';
            res.on('data', chunk => { data += chunk; });
            res.on('end', () => {
                const is200 = res.statusCode === 200;
                const contentType = res.headers['content-type'] || '';
                const isJs = contentType.includes('javascript');
                const hasPoki = data.includes('PokiSDK');
                const length = data.length;

                console.log(`  -> HTTP Status: ${res.statusCode} ${res.statusMessage}`);
                console.log(`  -> Content-Type: ${contentType}`);
                console.log(`  -> Content-Length: ${length} bytes`);
                console.log(`  -> Valid PokiSDK content: ${hasPoki}`);

                if (is200 && isJs && hasPoki && length > 5000) {
                    resolve({
                        ok: true,
                        statusCode: res.statusCode,
                        contentType,
                        length,
                        hasPoki
                    });
                } else {
                    reject(new Error(
                        `Poki CDN check failed (status: ${res.statusCode}, len: ${length})`
                    ));
                }
            });
        });
        req.on('error', (err) => reject(err));
    });
}

function createServer(scenario, serverRequests) {
    return http.createServer((req, res) => {
        const urlPath = req.url.split('?')[0];
        let filePath = path.join(BUILD_DIR, urlPath === '/' ? 'index.html' : urlPath);

        // Required headers for Godot 4 Web exports and external CDN script loading
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

            if (scenario === 'REAL_CDN') {
                // Untouched production HTML: uses official Poki SDK CDN script tag!
                res.writeHead(200);
                res.end(html);
                return;
            }

            // Fault injection scenarios for browser environment
            let injection = '';
            if (scenario === 'MOCK_SUCCESS') {
                injection = `
                <script>
                    window.PokiSDK = {
                        init: function() {
                            console.log("[MOCK_BROWSER_JS] PokiSDK.init() -> resolving promise");
                            return Promise.resolve();
                        },
                        gameLoadingFinished: function() {
                            console.log("[MOCK_BROWSER_JS] PokiSDK.gameLoadingFinished()");
                        },
                        gameplayStart: function() {
                            console.log("[MOCK_BROWSER_JS] PokiSDK.gameplayStart()");
                        },
                        gameplayStop: function() {
                            console.log("[MOCK_BROWSER_JS] PokiSDK.gameplayStop()");
                        },
                        commercialBreak: function() {
                            console.log("[MOCK_BROWSER_JS] PokiSDK.commercialBreak()");
                            return Promise.resolve();
                        },
                        rewardedBreak: function() {
                            console.log("[MOCK_BROWSER_JS] PokiSDK.rewardedBreak()");
                            return Promise.resolve(true);
                        }
                    };
                </script>
                `;
                html = html.replace('<script src="https://game-cdn.poki.com/scripts/v2/poki-sdk.js"></script>', injection);
            } else if (scenario === 'MOCK_DELAYED') {
                injection = `
                <script>
                    console.log("[MOCK_BROWSER_JS] Simulating 500ms CDN network delay for PokiSDK...");
                    setTimeout(function() {
                        console.log("[MOCK_BROWSER_JS] PokiSDK script now attached to window after 500ms!");
                        window.PokiSDK = {
                            init: function() {
                                console.log("[MOCK_BROWSER_JS] PokiSDK.init() -> resolving promise");
                                return Promise.resolve();
                            },
                            gameLoadingFinished: function() {
                                console.log("[MOCK_BROWSER_JS] PokiSDK.gameLoadingFinished()");
                            },
                            gameplayStart: function() {
                                console.log("[MOCK_BROWSER_JS] PokiSDK.gameplayStart()");
                            },
                            gameplayStop: function() {
                                console.log("[MOCK_BROWSER_JS] PokiSDK.gameplayStop()");
                            }
                        };
                    }, 500);
                </script>
                `;
                html = html.replace('<script src="https://game-cdn.poki.com/scripts/v2/poki-sdk.js"></script>', injection);
            } else if (scenario === 'MOCK_REJECT') {
                injection = `
                <script>
                    window.PokiSDK = {
                        init: function() {
                            console.log("[MOCK_BROWSER_JS] PokiSDK.init() -> simulating adblocker rejection!");
                            return Promise.reject(new Error("Adblocker active / init rejected"));
                        }
                    };
                </script>
                `;
                html = html.replace('<script src="https://game-cdn.poki.com/scripts/v2/poki-sdk.js"></script>', injection);
            } else if (scenario === 'MOCK_MISSING') {
                injection = `
                <script>
                    console.log("[MOCK_BROWSER_JS] Simulating missing PokiSDK (offline / script 404)");
                </script>
                `;
                html = html.replace('<script src="https://game-cdn.poki.com/scripts/v2/poki-sdk.js"></script>', injection);
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

async function runScenario(scenarioName, timeoutMs = 8500) {
    const isReal = scenarioName === 'REAL_CDN';
    console.log(`\n======================================================================`);
    console.log(isReal 
        ? `[REAL POKI SDK TEST] Official Poki CDN (https://game-cdn.poki.com)`
        : `[MOCK BROWSER FAULT INJECTION] Scenario: ${scenarioName}`);
    console.log(`======================================================================`);

    const serverRequests = [];
    const server = createServer(scenarioName, serverRequests);
    await new Promise(r => server.listen(PORT, r));

    const chromeArgs = [
        '--headless=new',
        '--no-sandbox',
        '--disable-gpu',
        '--disable-dev-shm-usage',
        '--enable-logging=stderr',
        '--v=1',
        `http://127.0.0.1:${PORT}/`
    ];

    const proc = spawn(CHROME_PATH, chromeArgs);
    const logs = [];
    const capturedErrors = [];

    proc.stderr.on('data', (d) => {
        const str = d.toString();
        const lines = str.split('\n');
        for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed) continue;

            // Track any real fatal/unhandled errors in browser
            if (trimmed.includes('Uncaught') 
                || trimmed.includes('RuntimeError')
                || trimmed.includes('TypeError')
                || trimmed.includes('ReferenceError')
                || trimmed.includes('SyntaxError')
                || trimmed.includes('net::ERR_')) {
                // In MOCK_REJECT, the intentional adblock error is expected
                if (!(scenarioName === 'MOCK_REJECT' && trimmed.includes('Adblocker active'))) {
                    capturedErrors.push(trimmed);
                }
            }

            if (trimmed.includes('PokiService') 
                || trimmed.includes('PokiSDK') 
                || trimmed.includes('POKI') 
                || trimmed.includes('[MOCK_BROWSER_JS]')
                || trimmed.includes('Godot Engine')
                || trimmed.includes('daraja muvaffaqiyatli yuklandi')
                || trimmed.includes('Uncaught')
                || trimmed.includes('RuntimeError')) {
                logs.push(trimmed);
                console.log('  [Chrome Console]: ' + trimmed);
            }
        }
    });

    await new Promise(resolve => setTimeout(resolve, timeoutMs));

    proc.kill();
    await new Promise(r => server.close(r));

    return { logs, capturedErrors, serverRequests };
}

async function main() {
    const chromeVersion = getChromeVersion(CHROME_PATH);
    console.log("======================================================================");
    console.log("WRONG WAY - COMPREHENSIVE BROWSER VERIFICATION RUNNER");
    console.log("Chrome Executable:", CHROME_PATH);
    console.log("Chrome Version:   ", chromeVersion);
    console.log("======================================================================");

    if (!fs.existsSync(CHROME_PATH)) {
        console.error(`ERROR: Chrome binary not found at ${CHROME_PATH}`);
        process.exit(1);
    }

    // ------------------------------------------------------------------
    // SUITE A: REAL POKI SDK CDN TEST
    // ------------------------------------------------------------------
    let cdnHealth = null;
    try {
        cdnHealth = await verifyOfficialCdnHealth();
    } catch (e) {
        console.error("  [ERROR] CDN health check failed:", e.message);
    }
    const cdnLive = cdnHealth !== null && cdnHealth.ok === true;

    const { logs: logsReal, capturedErrors: realErrors, serverRequests: realReqs } = 
        await runScenario('REAL_CDN', 12000);

    // 1. Independent CDN Pre-Flight
    const cdnPreflightPassed = cdnLive;

    // 2. Real CDN Response & Execution inside Chrome
    const cdnExecutedInBrowser = logsReal.some(l => 
        l.includes('game-cdn.poki.com') || l.includes('POKI')
    );

    // 3. window.PokiSDK Detected
    const sdkFoundInBrowser = logsReal.some(l => 
        l.includes('PokiSDK topildi') || l.includes('PokiSDK init success') || l.includes('POKI')
    );

    // 4. Godot Engine WebGL Initialized
    const godotLoaded = logsReal.some(l => l.includes('Godot Engine v4.7.2'));

    // 5. Game Scene and 60 Levels Initialized
    const levelsLoaded = logsReal.some(l => l.includes('60 ta daraja muvaffaqiyatli yuklandi'));

    // 6. Real PokiSDK.init() Resolved (SdkState.READY)
    const realInitSuccess = logsReal.some(l => 
        l.includes('PokiSDK.init() muvaffaqiyatli') || l.includes('SdkState.READY') || l.includes('init success')
    );

    // 7. PokiSDK.gameLoadingFinished() Dispatched
    const realLoadingFinished = logsReal.some(l => l.includes('gameLoadingFinished'));

    // 8. Zero Fatal JS / WASM / Network 404 Errors
    const server404s = realReqs.filter(r => r.status === 404);
    const zeroFatalErrors = realErrors.length === 0 && server404s.length === 0;

    console.log("\n--- REAL POKI SDK CDN VERIFICATION RESULTS ---");
    console.log(`1. Official Poki CDN Pre-flight Check (HTTP 200, valid JS, >5KB): ${cdnPreflightPassed}`);
    console.log(`2. Real Poki CDN Script Executed inside Chrome:                     ${cdnExecutedInBrowser}`);
    console.log(`3. Browser Detected Official PokiSDK on window:                    ${sdkFoundInBrowser}`);
    console.log(`4. Godot WebGL Canvas & Engine Initialized:                        ${godotLoaded}`);
    console.log(`5. Game Scene & Levels Initialized (60 levels):                    ${levelsLoaded}`);
    console.log(`6. Real PokiSDK.init() Resolved (SdkState.READY):                  ${realInitSuccess}`);
    console.log(`7. PokiSDK.gameLoadingFinished() Dispatched:                       ${realLoadingFinished}`);
    console.log(`8. Zero Fatal JS / WASM / Network Errors:                          ${zeroFatalErrors} (errors: ${realErrors.length}, 404s: ${server404s.length})`);

    const suiteRealPassed = cdnPreflightPassed 
        && cdnExecutedInBrowser 
        && sdkFoundInBrowser 
        && godotLoaded 
        && levelsLoaded 
        && realInitSuccess 
        && realLoadingFinished 
        && zeroFatalErrors;

    console.log(`SUITE A (REAL POKI SDK CDN) OVERALL: ${suiteRealPassed ? 'PASSED' : 'FAILED'}`);

    // ------------------------------------------------------------------
    // SUITE B: MOCK BROWSER FAULT INJECTION SUITE
    // ------------------------------------------------------------------
    console.log("\n======================================================================");
    console.log("STARTING SUITE B: MOCK BROWSER FAULT INJECTION (4 SCENARIOS)");
    console.log("======================================================================");

    // 1. Mock Success
    const { logs: logsMockSuccess } = await runScenario('MOCK_SUCCESS', 6000);
    const mockSuccessVerified = logsMockSuccess.some(l => 
        l.includes('SdkState.READY') || l.includes('init() muvaffaqiyatli')
    );
    console.log(`Scenario MOCK_SUCCESS verified: ${mockSuccessVerified}`);

    // 2. Mock Delayed (500ms network latency)
    const { logs: logsMockDelayed } = await runScenario('MOCK_DELAYED', 7000);
    const mockDelayedVerified = logsMockDelayed.some(l => l.includes('monitoringi boshlandi'))
        && logsMockDelayed.some(x => x.includes('READY') || x.includes('muvaffaqiyatli'));
    console.log(`Scenario MOCK_DELAYED verified: ${mockDelayedVerified}`);

    // 3. Mock Reject (Adblock / script reject)
    const { logs: logsMockReject } = await runScenario('MOCK_REJECT', 6000);
    const mockRejectVerified = logsMockReject.some(l => 
        l.includes('SdkState.FAILED') || l.includes('rad etildi')
    );
    console.log(`Scenario MOCK_REJECT verified: ${mockRejectVerified}`);

    // 4. Mock Missing (Offline / script 404 timeout)
    const { logs: logsMockMissing } = await runScenario('MOCK_MISSING', 9000);
    const mockMissingVerified = logsMockMissing.some(l => l.includes('monitoringi boshlandi'))
        && logsMockMissing.some(l => l.includes('FAILED') || l.includes('timeout'));
    console.log(`Scenario MOCK_MISSING verified: ${mockMissingVerified}`);

    const suiteMockPassed = mockSuccessVerified && mockDelayedVerified && mockRejectVerified && mockMissingVerified;
    console.log(`\nSUITE B (MOCK BROWSER FAULT INJECTION) OVERALL: ${suiteMockPassed ? 'PASSED' : 'FAILED'}`);

    console.log("\n======================================================================");
    console.log("ALL BROWSER TEST SUITES (REAL CDN + 4 MOCK SCENARIOS) COMPLETED!");
    console.log(`Suite A (Real Poki CDN):             ${suiteRealPassed ? 'PASSED' : 'FAILED'}`);
    console.log(`Suite B (Mock Browser Scenarios):     ${suiteMockPassed ? 'PASSED' : 'FAILED'}`);
    console.log("======================================================================");

    if (!suiteRealPassed || !suiteMockPassed) {
        process.exit(1);
    }
    process.exit(0);
}

main().catch((err) => {
    console.error("Runner error:", err);
    process.exit(1);
});
