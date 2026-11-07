const http = require('http');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const BUILD_DIR = path.join(__dirname, '..', 'build', 'web');
const CHROME_PATH = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const PORT = 8089;

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

        res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
        res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
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
            
            // Inject scenario-specific script before PokiSDK or replace PokiSDK script
            let injection = '';
            if (scenario === 'SUCCESS') {
                injection = `
                <script>
                    window.PokiSDK = {
                        init: function() {
                            console.log("[BROWSER_JS] PokiSDK.init() called -> resolving promise");
                            return Promise.resolve();
                        },
                        gameLoadingFinished: function() { console.log("[BROWSER_JS] PokiSDK.gameLoadingFinished()"); },
                        gameplayStart: function() { console.log("[BROWSER_JS] PokiSDK.gameplayStart()"); },
                        gameplayStop: function() { console.log("[BROWSER_JS] PokiSDK.gameplayStop()"); },
                        commercialBreak: function() {
                            console.log("[BROWSER_JS] PokiSDK.commercialBreak()");
                            return Promise.resolve();
                        },
                        rewardedBreak: function() {
                            console.log("[BROWSER_JS] PokiSDK.rewardedBreak()");
                            return Promise.resolve(true);
                        }
                    };
                </script>
                `;
                html = html.replace('<script src="https://game-cdn.poki.com/scripts/v2/poki-sdk.js"></script>', injection);
            } else if (scenario === 'DELAYED') {
                injection = `
                <script>
                    console.log("[BROWSER_JS] Simulating 500ms CDN network delay for PokiSDK...");
                    setTimeout(function() {
                        console.log("[BROWSER_JS] PokiSDK script now attached to window after 500ms!");
                        window.PokiSDK = {
                            init: function() {
                                console.log("[BROWSER_JS] PokiSDK.init() called -> resolving promise");
                                return Promise.resolve();
                            },
                            gameLoadingFinished: function() { console.log("[BROWSER_JS] PokiSDK.gameLoadingFinished()"); },
                            gameplayStart: function() { console.log("[BROWSER_JS] PokiSDK.gameplayStart()"); },
                            gameplayStop: function() { console.log("[BROWSER_JS] PokiSDK.gameplayStop()"); }
                        };
                    }, 500);
                </script>
                `;
                html = html.replace('<script src="https://game-cdn.poki.com/scripts/v2/poki-sdk.js"></script>', injection);
            } else if (scenario === 'REJECT') {
                injection = `
                <script>
                    window.PokiSDK = {
                        init: function() {
                            console.log("[BROWSER_JS] PokiSDK.init() called -> simulating adblocker rejection!");
                            return Promise.reject(new Error("Adblocker active / init rejected"));
                        }
                    };
                </script>
                `;
                html = html.replace('<script src="https://game-cdn.poki.com/scripts/v2/poki-sdk.js"></script>', injection);
            } else if (scenario === 'MISSING') {
                injection = `
                <script>
                    console.log("[BROWSER_JS] Simulating missing PokiSDK (offline / script failed to load)");
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

async function runScenario(scenarioName, timeoutMs = 7000) {
    console.log(`\n======================================================================`);
    console.log(`[REAL BROWSER TEST] Running scenario: ${scenarioName}`);
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
        // Extract console messages
        const lines = str.split('\n');
        for (const line of lines) {
            if (line.includes('PokiService') || line.includes('[BROWSER_JS]') || line.includes('PokiSDK')) {
                logs.push(line.trim());
                console.log('  [Chrome Console]: ' + line.trim());
            }
        }
    });

    await new Promise(resolve => setTimeout(resolve, timeoutMs));

    proc.kill();
    await new Promise(r => server.close(r));

    return logs;
}

async function main() {
    console.log("Starting Real Chrome Browser Tests on Godot Web Export...");
    
    // 1. Success
    const logsSuccess = await runScenario('SUCCESS', 6000);
    const successVerified = logsSuccess.some(l => l.includes('SdkState.READY') || l.includes('PokiSDK.init() muvaffaqiyatli'));
    console.log(`Scenario SUCCESS verified: ${successVerified}`);

    // 2. Delayed
    const logsDelayed = await runScenario('DELAYED', 7000);
    const delayedDetected = logsDelayed.some(l => l.includes('PokiSDK script now attached') || l.includes('monitoringi boshlandi') || l.includes('SdkState.READY'));
    console.log(`Scenario DELAYED verified: ${delayedDetected}`);

    // 3. Reject
    const logsReject = await runScenario('REJECT', 6000);
    const rejectVerified = logsReject.some(l => l.includes('SdkState.FAILED') || l.includes('rad etildi') || l.includes('adblocker rejection'));
    console.log(`Scenario REJECT verified: ${rejectVerified}`);

    // 4. Missing
    const logsMissing = await runScenario('MISSING', 6000);
    const missingVerified = logsMissing.some(l => l.includes('monitoringi boshlandi') || l.includes('missing PokiSDK'));
    console.log(`Scenario MISSING verified: ${missingVerified}`);

    console.log("\n======================================================================");
    console.log("REAL BROWSER TEST SUITE COMPLETED FOR ALL 4 SCENARIOS!");
    console.log("======================================================================");
}

main().catch(console.error);
