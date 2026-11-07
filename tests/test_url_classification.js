/**
 * WRONG WAY — URL CLASSIFICATION & SPOOFING RESILIENCE UNIT TESTS
 *
 * Validates strict URL parsing via WHATWG URL API:
 * 1. Local game resources require protocol === "http:", hostname === "127.0.0.1" || "localhost",
 *    and port matching the exact active test port.
 * 2. Poki SDK requires protocol === "https:", hostname === "game-cdn.poki.com",
 *    pathname === "/scripts/v2/poki-sdk.js", port === "", search === "", hash === "",
 *    username === "", and password === "".
 * 3. Never uses string.includes() or regex heuristics that can be fooled by spoofed URLs.
 */

const { isOfficialPokiSdkUrl, isLocalGameResourceUrl, isTargetResourceUrl } = require('./test_browser_integration.js');

const PORT = 8101;

const testCases = [
    {
        name: 'Spoofed hostname with IP prefix (127.0.0.1:8101.evil.example)',
        url: `http://127.0.0.1:${PORT}.evil.example/index.html`,
        expectTarget: false,
        expectPoki: false
    },
    {
        name: 'Spoofed path containing Poki CDN domain (evil.example/path/game-cdn.poki.com)',
        url: 'http://evil.example/path/game-cdn.poki.com',
        expectTarget: false,
        expectPoki: false
    },
    {
        name: 'Spoofed filename prefix on evil domain (evil.example/poki-sdk-fake.js)',
        url: 'http://evil.example/poki-sdk-fake.js',
        expectTarget: false,
        expectPoki: false
    },
    {
        name: 'Incorrect port on loopback (127.0.0.1:9999 vs expected ' + PORT + ')',
        url: 'http://127.0.0.1:9999/index.html',
        expectTarget: false,
        expectPoki: false
    },
    {
        name: 'Subdomain spoofing Poki CDN (game-cdn.poki.com.evil.example)',
        url: 'https://game-cdn.poki.com.evil.example/scripts/v2/poki-sdk.js',
        expectTarget: false,
        expectPoki: false
    },
    {
        name: 'Path spoofing on official CDN (game-cdn.poki.com/scripts/v2/poki-sdk-fake.js)',
        url: 'https://game-cdn.poki.com/scripts/v2/poki-sdk-fake.js',
        expectTarget: false,
        expectPoki: false
    },
    {
        name: 'Incorrect scheme on loopback (ftp://127.0.0.1:' + PORT + '/index.html)',
        url: `ftp://127.0.0.1:${PORT}/index.html`,
        expectTarget: false,
        expectPoki: false
    },
    {
        name: 'Non-standard port on Poki CDN (https://game-cdn.poki.com:8443/scripts/v2/poki-sdk.js)',
        url: 'https://game-cdn.poki.com:8443/scripts/v2/poki-sdk.js',
        expectTarget: false,
        expectPoki: false
    },
    {
        name: 'Explicit standard HTTPS port :443 (https://game-cdn.poki.com:443/scripts/v2/poki-sdk.js)',
        url: 'https://game-cdn.poki.com:443/scripts/v2/poki-sdk.js',
        expectTarget: true,
        expectPoki: true
    },
    {
        name: 'Insecure HTTP on Poki CDN (http://game-cdn.poki.com/scripts/v2/poki-sdk.js)',
        url: 'http://game-cdn.poki.com/scripts/v2/poki-sdk.js',
        expectTarget: false,
        expectPoki: false
    },
    {
        name: 'Query parameter pollution on Poki CDN (https://game-cdn.poki.com/scripts/v2/poki-sdk.js?x=1)',
        url: 'https://game-cdn.poki.com/scripts/v2/poki-sdk.js?x=1',
        expectTarget: false,
        expectPoki: false
    },
    {
        name: 'Userinfo pollution on Poki CDN (https://user:pass@game-cdn.poki.com/scripts/v2/poki-sdk.js)',
        url: 'https://user:pass@game-cdn.poki.com/scripts/v2/poki-sdk.js',
        expectTarget: false,
        expectPoki: false
    },
    {
        name: 'Poki CDN path traversal attack (game-cdn.poki.com/scripts/v2/poki-sdk.js/../../evil)',
        url: 'https://game-cdn.poki.com/scripts/v2/poki-sdk.js/../../evil',
        expectTarget: false,
        expectPoki: false
    },
    {
        name: 'Canonical official Poki SDK CDN URL (https://game-cdn.poki.com/scripts/v2/poki-sdk.js)',
        url: 'https://game-cdn.poki.com/scripts/v2/poki-sdk.js',
        expectTarget: true,
        expectPoki: true
    },
    {
        name: 'Official local game HTML via 127.0.0.1 (http://127.0.0.1:' + PORT + '/index.html)',
        url: `http://127.0.0.1:${PORT}/index.html`,
        expectTarget: true,
        expectPoki: false
    },
    {
        name: 'Official local game WASM via localhost (http://localhost:' + PORT + '/index.wasm)',
        url: `http://localhost:${PORT}/index.wasm`,
        expectTarget: true,
        expectPoki: false
    },
    {
        name: 'Official local game PCK bundle via 127.0.0.1 (http://127.0.0.1:' + PORT + '/index.pck)',
        url: `http://127.0.0.1:${PORT}/index.pck`,
        expectTarget: true,
        expectPoki: false
    }
];

console.log('======================================================================');
console.log('RUNNING URL CLASSIFICATION & SPOOFING RESILIENCE UNIT TESTS');
console.log('======================================================================');

let failures = 0;
for (let i = 0; i < testCases.length; i++) {
    const tc = testCases[i];
    const isTarget = isTargetResourceUrl(tc.url, PORT);
    const isPoki = isOfficialPokiSdkUrl(tc.url);

    const targetMatch = isTarget === tc.expectTarget;
    const pokiMatch = isPoki === tc.expectPoki;
    const pass = targetMatch && pokiMatch;

    if (pass) {
        console.log(`  [PASS] Test ${i + 1}: ${tc.name}`);
    } else {
        failures++;
        console.error(`  [FAIL] Test ${i + 1}: ${tc.name}`);
        console.error(`         URL:      ${tc.url}`);
        console.error(`         Expected: target=${tc.expectTarget}, poki=${tc.expectPoki}`);
        console.error(`         Actual:   target=${isTarget}, poki=${isPoki}`);
    }
}

console.log('\n======================================================================');
if (failures === 0) {
    console.log(`ALL ${testCases.length}/${testCases.length} URL CLASSIFICATION UNIT TESTS PASSED CLEANLY (EXIT CODE 0)`);
    console.log('======================================================================');
    process.exit(0);
} else {
    console.error(`CRITICAL: ${failures} URL CLASSIFICATION UNIT TESTS FAILED (EXIT CODE 1)`);
    console.log('======================================================================');
    process.exit(1);
}

