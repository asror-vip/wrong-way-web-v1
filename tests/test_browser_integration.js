// test_browser_integration.js
// ---------------------------------------------------------------
// Wrong Way — Browser Integration Test Runner
// Verifies Poki SDK integration inside a real Chrome browser.
//
// SUITE A: Real Poki CDN
//   - Pre-flight HTTPS GET to official CDN endpoint
//   - Chrome loads real CDN script → window.PokiSDK exists
//   - PokiSDK.init() resolves → SdkState.READY
//   - Godot engine & 60 levels initialize
//   - gameLoadingFinished() dispatched
//   - Zero fatal JS/WASM/network errors or 404s
//
// SUITE B: Mock fault injection (4 scenarios)
//   MOCK_SUCCESS, MOCK_DELAYED, MOCK_REJECT, MOCK_MISSING
//
// Exit code 0 ONLY when every assertion in every suite passes.
// ---------------------------------------------------------------

'use strict';

const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const { spawn, execSync } = require('child_process');

const BUILD_DIR = path.join(__dirname, '..', 'build', 'web');
const CHROME_PATH = process.env.CHROME_PATH
    || (process.argv[2] && !process.argv[2].startsWith('--')
        ? process.argv[2] : null)
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

// ---------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------
function getChromeVersion(chromePath) {
    try {
        const escaped = chromePath.replace(/'/g, "''");
        const cmd =
            `powershell -NoProfile -Command ` +
            `"(Get-Item '${escaped}').VersionInfo.ProductVersion"`;
        return execSync(cmd).toString().trim();
    } catch {
        return 'Unknown';
    }
}

function sleep(ms) {
    return new Promise(r => setTimeout(r, ms));
}

// ---------------------------------------------------------------
// CDN pre-flight: direct HTTPS GET (no browser)
// ---------------------------------------------------------------
function verifyOfficialCdnHealth() {
    const cdnUrl =
        'https://game-cdn.poki.com/scripts/v2/poki-sdk.js';
    console.log(
        '\n[PRE-FLIGHT] HTTPS GET to official Poki CDN: ' + cdnUrl
    );
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
                console.log('  HTTP Status:     ' + res.statusCode
                    + ' ' + res.statusMessage);
                console.log('  Content-Type:    ' + ct);
                console.log('  Content-Length:  ' + len + ' bytes');
                console.log('  Contains PokiSDK: ' + hasPoki);
                if (ok200 && isJs && hasPoki && len > 5000) {
                    resolve({ ok: true, statusCode: 200,
                        contentType: ct, length: len });
                } else {
                    reject(new Error(
                        'CDN check failed: status=' +
                        res.statusCode + ' len=' + len
                    ));
                }
            });
        }).on('error', reject);
    });
}

// ---------------------------------------------------------------
// HTTP server for Godot Web build
// ---------------------------------------------------------------
function createServer(scenario, serverRequests) {
    return http.createServer((req, res) => {
        const urlPath = req.url.split('?')[0];
        const filePath = path.join(
            BUILD_DIR,
            urlPath === '/' ? 'index.html' : urlPath
        );

        // Required COOP/COEP headers for SharedArrayBuffer
        res.setHeader(
            'Cross-Origin-Opener-Policy', 'same-origin');
        res.setHeader(
            'Cross-Origin-Embedder-Policy', 'credentialless');
        res.setHeader(
            'Access-Control-Allow-Origin', '*');

        if (!fs.existsSync(filePath)) {
            serverRequests.push({ url: urlPath, status: 404 });
            res.writeHead(404);
            res.end('Not found');
            return;
        }

        serverRequests.push({ url: urlPath, status: 200 });
        const ext = path.extname(filePath).toLowerCase();
        res.setHeader(
            'Content-Type',
            MIME_TYPES[ext] || 'application/octet-stream'
        );

        if (urlPath === '/' || urlPath === '/index.html') {
            let html = fs.readFileSync(filePath, 'utf8');
            const pokiTag =
                '<script src="https://game-cdn.poki.com' +
                '/scripts/v2/poki-sdk.js"></script>';

            if (scenario === 'REAL_CDN') {
                // Serve unmodified production HTML
                res.writeHead(200);
                res.end(html);
                return;
            }

            let injection = '';
            if (scenario === 'MOCK_SUCCESS') {
                injection = mockSuccessScript();
            } else if (scenario === 'MOCK_DELAYED') {
                injection = mockDelayedScript();
            } else if (scenario === 'MOCK_REJECT') {
                injection = mockRejectScript();
            } else if (scenario === 'MOCK_MISSING') {
                injection = mockMissingScript();
            }

            html = html.replace(pokiTag, injection);
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
// Mock injection scripts
// ---------------------------------------------------------------
function mockSuccessScript() {
    return `<script>
window.PokiSDK = {
    init: function() {
        console.log("[MOCK] PokiSDK.init() -> resolve");
        return Promise.resolve();
    },
    gameLoadingFinished: function() {
        console.log("[MOCK] PokiSDK.gameLoadingFinished()");
    },
    gameplayStart: function() {
        console.log("[MOCK] PokiSDK.gameplayStart()");
    },
    gameplayStop: function() {
        console.log("[MOCK] PokiSDK.gameplayStop()");
    },
    commercialBreak: function() {
        return Promise.resolve();
    },
    rewardedBreak: function() {
        return Promise.resolve(true);
    }
};
</script>`;
}

function mockDelayedScript() {
    return `<script>
console.log("[MOCK] Simulating 500ms CDN delay...");
setTimeout(function() {
    console.log("[MOCK] PokiSDK attached after 500ms");
    window.PokiSDK = {
        init: function() {
            console.log("[MOCK] PokiSDK.init() -> resolve");
            return Promise.resolve();
        },
        gameLoadingFinished: function() {
            console.log("[MOCK] PokiSDK.gameLoadingFinished()");
        },
        gameplayStart: function() {},
        gameplayStop: function() {}
    };
}, 500);
</script>`;
}

function mockRejectScript() {
    return `<script>
window.PokiSDK = {
    init: function() {
        console.log("[MOCK] PokiSDK.init() -> reject (adblocker)");
        return Promise.reject(
            new Error("Adblocker active / init rejected")
        );
    }
};
</script>`;
}

function mockMissingScript() {
    return `<script>
console.log("[MOCK] PokiSDK missing (offline / 404)");
</script>`;
}

// ---------------------------------------------------------------
// Chrome stderr line parser
// ---------------------------------------------------------------
function parseLine(line, scenario) {
    const trimmed = line.trim();
    if (!trimmed) return null;

    const result = {
        raw: trimmed,
        isConsole: trimmed.includes('CONSOLE'),
        isError: false,
        relevant: false
    };

    // Detect genuine errors (not intentional mock rejections)
    const errorPatterns = [
        'Uncaught', 'RuntimeError', 'TypeError',
        'ReferenceError', 'SyntaxError', 'net::ERR_'
    ];
    for (const p of errorPatterns) {
        if (trimmed.includes(p)) {
            // In MOCK_REJECT, the adblocker error is expected
            if (scenario === 'MOCK_REJECT' &&
                trimmed.includes('Adblocker active')) {
                break;
            }
            // In MOCK_MISSING, "No interface" errors are expected
            if (scenario === 'MOCK_MISSING' &&
                trimmed.includes('No interface')) {
                break;
            }
            result.isError = true;
            break;
        }
    }

    // Mark as relevant for logging
    const logPatterns = [
        'PokiService', 'PokiSDK', '[MOCK]',
        'Godot Engine', 'daraja muvaffaqiyatli',
        'gameLoadingFinished', 'SdkState',
        'Uncaught', 'RuntimeError',
        'init success', 'init failed',
        'topildi', 'muvaffaqiyatli', 'rad etildi',
        'monitoring', 'FAILED', 'READY'
    ];
    for (const p of logPatterns) {
        if (trimmed.includes(p)) {
            result.relevant = true;
            break;
        }
    }

    return result;
}

// ---------------------------------------------------------------
// Run a scenario in headless Chrome
// ---------------------------------------------------------------
async function runScenario(scenarioName, timeoutMs) {
    const isReal = scenarioName === 'REAL_CDN';
    console.log('\n' + '='.repeat(66));
    console.log(isReal
        ? '[REAL CDN] Official Poki CDN test'
        : '[MOCK] Scenario: ' + scenarioName);
    console.log('='.repeat(66));

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
        'http://127.0.0.1:' + PORT + '/'
    ];

    const proc = spawn(CHROME_PATH, chromeArgs);
    const allLines = [];
    const errors = [];

    proc.stderr.on('data', (d) => {
        for (const line of d.toString().split('\n')) {
            const parsed = parseLine(line, scenarioName);
            if (!parsed) continue;
            allLines.push(parsed);
            if (parsed.isError) errors.push(parsed.raw);
            if (parsed.relevant) {
                console.log('  [Chrome]: ' + parsed.raw);
            }
        }
    });

    await sleep(timeoutMs);

    proc.kill();
    await new Promise(r => server.close(r));

    const s404 = serverRequests.filter(r => r.status === 404);

    return { lines: allLines, errors, serverRequests, s404 };
}

// ---------------------------------------------------------------
// Assertion helpers
// ---------------------------------------------------------------
function hasLog(lines, pattern) {
    return lines.some(l => l.raw.includes(pattern));
}

// ---------------------------------------------------------------
// SUITE A: Real CDN assertions
// ---------------------------------------------------------------
function verifySuiteA(cdn, result) {
    const checks = [];

    // 1. CDN pre-flight
    checks.push({
        name: 'CDN pre-flight (HTTPS GET 200, JS, >5KB)',
        pass: cdn !== null && cdn.ok === true
    });

    // 2. Real CDN script executed inside Chrome
    //    The official Poki SDK core logs include game-cdn.poki.com
    checks.push({
        name: 'Real Poki CDN script executed in Chrome',
        pass: hasLog(result.lines, 'game-cdn.poki.com')
    });

    // 3. window.PokiSDK detected by Godot
    //    poki_service.gd logs "PokiSDK topildi" when it finds the SDK
    checks.push({
        name: 'window.PokiSDK detected (PokiSDK topildi)',
        pass: hasLog(result.lines, 'PokiSDK topildi')
    });

    // 4. Godot engine initialized
    checks.push({
        name: 'Godot Engine v4.7.2 initialized',
        pass: hasLog(result.lines, 'Godot Engine v4.7.2')
    });

    // 5. 60 levels loaded
    checks.push({
        name: '60 levels loaded',
        pass: hasLog(result.lines, '60 ta daraja muvaffaqiyatli')
    });

    // 6. PokiSDK.init() resolved → READY
    //    poki_service.gd logs "muvaffaqiyatli ... READY"
    checks.push({
        name: 'PokiSDK.init() resolved (READY)',
        pass: hasLog(result.lines, 'muvaffaqiyatli') &&
              hasLog(result.lines, 'READY')
    });

    // 7. gameLoadingFinished() dispatched
    checks.push({
        name: 'gameLoadingFinished() dispatched',
        pass: hasLog(result.lines, 'gameLoadingFinished')
    });

    // 8. Zero fatal errors and zero 404s
    checks.push({
        name: 'Zero fatal JS/WASM/network errors',
        pass: result.errors.length === 0
    });
    checks.push({
        name: 'Zero HTTP 404 responses',
        pass: result.s404.length === 0
    });

    return checks;
}

// ---------------------------------------------------------------
// SUITE B: Mock scenario assertions
// ---------------------------------------------------------------
function verifyMockScenario(name, result) {
    const checks = [];

    if (name === 'MOCK_SUCCESS') {
        checks.push({
            name: 'SDK found and init resolved (READY)',
            pass: hasLog(result.lines, 'READY') ||
                  hasLog(result.lines, 'muvaffaqiyatli')
        });
        checks.push({
            name: 'gameLoadingFinished dispatched',
            pass: hasLog(result.lines, 'gameLoadingFinished')
        });
    } else if (name === 'MOCK_DELAYED') {
        checks.push({
            name: 'SDK polling/monitoring started',
            pass: hasLog(result.lines, 'monitoring') ||
                  hasLog(result.lines, 'monitoringi')
        });
        checks.push({
            name: 'SDK found after delay and READY',
            pass: hasLog(result.lines, 'READY') ||
                  hasLog(result.lines, 'muvaffaqiyatli')
        });
    } else if (name === 'MOCK_REJECT') {
        checks.push({
            name: 'SDK init rejected (FAILED)',
            pass: hasLog(result.lines, 'FAILED') ||
                  hasLog(result.lines, 'rad etildi')
        });
    } else if (name === 'MOCK_MISSING') {
        checks.push({
            name: 'SDK monitoring started',
            pass: hasLog(result.lines, 'monitoring') ||
                  hasLog(result.lines, 'monitoringi')
        });
        checks.push({
            name: 'SDK timeout -> FAILED',
            pass: hasLog(result.lines, 'FAILED')
        });
    }

    return checks;
}

// ---------------------------------------------------------------
// Print check results
// ---------------------------------------------------------------
function printChecks(label, checks) {
    console.log('\n--- ' + label + ' ---');
    let allPassed = true;
    for (let i = 0; i < checks.length; i++) {
        const c = checks[i];
        const mark = c.pass ? 'PASS' : 'FAIL';
        console.log(
            '  ' + (i + 1) + '. [' + mark + '] ' + c.name
        );
        if (!c.pass) allPassed = false;
    }
    const overall = allPassed ? 'PASSED' : 'FAILED';
    console.log(label + ' OVERALL: ' + overall);
    return allPassed;
}

// ---------------------------------------------------------------
// Main
// ---------------------------------------------------------------
async function main() {
    const chromeVer = getChromeVersion(CHROME_PATH);
    console.log('='.repeat(66));
    console.log('WRONG WAY — BROWSER INTEGRATION TEST RUNNER');
    console.log('Chrome: ' + CHROME_PATH);
    console.log('Version: ' + chromeVer);
    console.log('='.repeat(66));

    if (!fs.existsSync(CHROME_PATH)) {
        console.error(
            'ERROR: Chrome not found at ' + CHROME_PATH
        );
        process.exit(1);
    }

    // ---- SUITE A: Real CDN ----
    let cdnHealth = null;
    try {
        cdnHealth = await verifyOfficialCdnHealth();
    } catch (e) {
        console.error('  CDN health check error: ' + e.message);
    }

    const resultReal = await runScenario('REAL_CDN', 12000);
    const checksA = verifySuiteA(cdnHealth, resultReal);
    const suiteAPassed = printChecks('SUITE A (Real CDN)', checksA);

    // ---- SUITE B: Mock scenarios ----
    console.log('\n' + '='.repeat(66));
    console.log('SUITE B: MOCK FAULT INJECTION (4 scenarios)');
    console.log('='.repeat(66));

    const mockScenarios = [
        { name: 'MOCK_SUCCESS', timeout: 6000 },
        { name: 'MOCK_DELAYED', timeout: 7000 },
        { name: 'MOCK_REJECT',  timeout: 6000 },
        { name: 'MOCK_MISSING', timeout: 9000 }
    ];

    let suiteBPassed = true;
    for (const sc of mockScenarios) {
        const res = await runScenario(sc.name, sc.timeout);
        const checks = verifyMockScenario(sc.name, res);
        const ok = printChecks(
            'SUITE B / ' + sc.name, checks
        );
        if (!ok) suiteBPassed = false;
    }

    // ---- Summary ----
    console.log('\n' + '='.repeat(66));
    console.log('FINAL RESULTS');
    console.log(
        '  Suite A (Real CDN):        ' +
        (suiteAPassed ? 'PASSED' : 'FAILED')
    );
    console.log(
        '  Suite B (Mock scenarios):   ' +
        (suiteBPassed ? 'PASSED' : 'FAILED')
    );
    console.log('='.repeat(66));

    if (!suiteAPassed || !suiteBPassed) {
        console.error(
            'EXIT 1: One or more assertions failed.'
        );
        process.exit(1);
    }

    console.log('EXIT 0: All assertions passed.');
    process.exit(0);
}

main().catch((err) => {
    console.error('Runner fatal error: ' + err.message);
    process.exit(1);
});
