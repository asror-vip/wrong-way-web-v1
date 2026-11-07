const http = require('http');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

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

function createServer(scenario) {
    return http.createServer((req, res) => {
        const urlPath = req.url.split('?')[0];
        let filePath = path.join(BUILD_DIR, urlPath === '/' ? 'index.html' : urlPath);

        // Required headers for Godot 4 Web exports and external CDN script loading
        res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
        res.setHeader('Cross-Origin-Embedder-Policy', 'credentialless');
        res.setHeader('Access-Control-Allow-Origin', '*');

        if (!fs.existsSync(filePath)) {
            res.writeHead(404);
            res.end('Not found');
            return;
        }

        const ext = path.extname(filePath).toLowerCase();
        res.setHeader('Content-Type', MIME_TYPES[ext] || 'application/octet-stream');

        if (urlPath === '/' || urlPath === '/index.html') {
            let html = fs.readFileSync(filePath, 'utf8');

            if (scenario === 'REAL_CDN') {
                // DO NOT TOUCH html: uses real official Poki SDK CDN script tag!
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
                        gameLoadingFinished: function() { console.log("[MOCK_BROWSER_JS] PokiSDK.gameLoadingFinished()"); },
                        gameplayStart: function() { console.log("[MOCK_BROWSER_JS] PokiSDK.gameplayStart()"); },
                        gameplayStop: function() { console.log("[MOCK_BROWSER_JS] PokiSDK.gameplayStop()"); },
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
                            gameLoadingFinished: function() { console.log("[MOCK_BROWSER_JS] PokiSDK.gameLoadingFinished()"); },
                            gameplayStart: function() { console.log("[MOCK_BROWSER_JS] PokiSDK.gameplayStart()"); },
                            gameplayStop: function() { console.log("[MOCK_BROWSER_JS] PokiSDK.gameplayStop()"); }
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

async function runScenario(scenarioName, timeoutMs = 8000) {
    const isReal = scenarioName === 'REAL_CDN';
    console.log(`\n======================================================================`);
    console.log(isReal 
        ? `[REAL POKI SDK TEST] Official Poki CDN (https://game-cdn.poki.com)`
        : `[MOCK BROWSER FAULT INJECTION] Scenario: ${scenarioName}`);
    console.log(`======================================================================`);

    const server = createServer(scenarioName);
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

    proc.stderr.on('data', (d) => {
        const str = d.toString();
        const lines = str.split('\n');
        for (const line of lines) {
            const trimmed = line.trim();
            if (trimmed.includes('PokiService') 
                || trimmed.includes('PokiSDK') 
                || trimmed.includes('POKI') 
                || trimmed.includes('[MOCK_BROWSER_JS]')
                || trimmed.includes('Godot Engine')
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

    return logs;
}

async function main() {
    console.log("======================================================================");
    console.log("WRONG WAY - BROWSER VERIFICATION RUNNER");
    console.log("Using Chrome Executable:", CHROME_PATH);
    console.log("======================================================================");

    if (!fs.existsSync(CHROME_PATH)) {
        console.error(`ERROR: Chrome binary not found at ${CHROME_PATH}`);
        process.exit(1);
    }

    // ------------------------------------------------------------------
    // SUITE A: REAL POKI SDK CDN TEST
    // ------------------------------------------------------------------
    const logsReal = await runScenario('REAL_CDN', 8500);
    const realSdkLoaded = logsReal.some(l => l.includes('game-cdn.poki.com') || l.includes('POKI'));
    const godotLoaded = logsReal.some(l => l.includes('Godot Engine v4.7.2'));
    const realInitSuccess = logsReal.some(l => l.includes('PokiSDK.init() muvaffaqiyatli') || l.includes('SdkState.READY'));
    const realLoadingFinished = logsReal.some(l => l.includes('gameLoadingFinished'));
    const noFatalError = !logsReal.some(l => l.includes('Uncaught') || l.includes('RuntimeError'));

    console.log("\n--- REAL POKI SDK CDN VERIFICATION RESULTS ---");
    console.log(`1. Official Poki CDN Script Loaded: ${realSdkLoaded}`);
    console.log(`2. Godot WebGL Canvas Initialized: ${godotLoaded}`);
    console.log(`3. Real PokiSDK.init() Resolved (SdkState.READY): ${realInitSuccess}`);
    console.log(`4. PokiSDK.gameLoadingFinished() Dispatched: ${realLoadingFinished}`);
    console.log(`5. No Fatal JS/Wasm Errors: ${noFatalError}`);

    const suiteRealPassed = realSdkLoaded && godotLoaded && realInitSuccess && realLoadingFinished && noFatalError;
    console.log(`SUITE A (REAL POKI SDK CDN) OVERALL: ${suiteRealPassed ? 'PASSED' : 'FAILED'}`);

    // ------------------------------------------------------------------
    // SUITE B: MOCK BROWSER FAULT INJECTION SUITE
    // ------------------------------------------------------------------
    console.log("\n======================================================================");
    console.log("STARTING SUITE B: MOCK BROWSER FAULT INJECTION (4 SCENARIOS)");
    console.log("======================================================================");

    // 1. Mock Success
    const logsMockSuccess = await runScenario('MOCK_SUCCESS', 6000);
    const mockSuccessVerified = logsMockSuccess.some(l => l.includes('SdkState.READY') || l.includes('init() muvaffaqiyatli'));
    console.log(`Scenario MOCK_SUCCESS verified: ${mockSuccessVerified}`);

    // 2. Mock Delayed (500ms network latency)
    const logsMockDelayed = await runScenario('MOCK_DELAYED', 7000);
    const mockDelayedVerified = logsMockDelayed.some(l => l.includes('monitoringi boshlandi'))
        && logsMockDelayed.some(x => x.includes('READY') || x.includes('muvaffaqiyatli'));
    console.log(`Scenario MOCK_DELAYED verified: ${mockDelayedVerified}`);

    // 3. Mock Reject (Adblock / script reject)
    const logsMockReject = await runScenario('MOCK_REJECT', 6000);
    const mockRejectVerified = logsMockReject.some(l => l.includes('SdkState.FAILED') || l.includes('rad etildi'));
    console.log(`Scenario MOCK_REJECT verified: ${mockRejectVerified}`);

    // 4. Mock Missing (Offline / script 404 timeout)
    const logsMockMissing = await runScenario('MOCK_MISSING', 9000);
    const mockMissingVerified = logsMockMissing.some(l => l.includes('monitoringi boshlandi'))
        && logsMockMissing.some(l => l.includes('FAILED') || l.includes('timeout'));
    console.log(`Scenario MOCK_MISSING verified: ${mockMissingVerified}`);

    const suiteMockPassed = mockSuccessVerified && mockDelayedVerified && mockRejectVerified && mockMissingVerified;
    console.log(`\nSUITE B (MOCK BROWSER FAULT INJECTION) OVERALL: ${suiteMockPassed ? 'PASSED' : 'FAILED'}`);

    console.log("\n======================================================================");
    console.log("ALL BROWSER TEST SUITES (REAL CDN + 4 MOCK SCENARIOS) COMPLETED!");
    console.log("======================================================================");

    if (!suiteRealPassed || !suiteMockPassed) {
        process.exit(1);
    }
}

main().catch((err) => {
    console.error("Runner error:", err);
    process.exit(1);
});
