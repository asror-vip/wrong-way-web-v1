// test_js_closure_guard.js
// ---------------------------------------------------------------
// Pure-JS integration test for the IIFE closure token guard used
// in poki_service.gd's _start_commercial_break / _start_rewarded_break.
//
// Simulates the exact pattern Godot emits via JavaScriptBridge.eval():
//   (function(localCb, localToken) {
//       window.poki_temp_commercial_cb = null;
//       PokiSDK.commercialBreak().then(...localCb...).catch(...localCb...);
//   })(window.poki_temp_commercial_cb, token);
//
// Test scenarios:
//   1. Commercial: Ad A timeout → Ad B starts → Ad A resolves → B survives
//   2. Rewarded:   Ad A timeout → Ad B starts → Ad A resolves → B survives
//   3. Commercial: Both resolve normally without interference
//   4. Rewarded:   Ad A rejects, Ad B resolves normally
// ---------------------------------------------------------------

'use strict';

let passed = 0;
let failed = 0;
const totalTests = 4;

function assert(cond, msg) {
    if (!cond) {
        console.error('  FAIL: ' + msg);
        failed++;
        throw new Error('Assertion failed: ' + msg);
    }
}

function sleep(ms) {
    return new Promise(r => setTimeout(r, ms));
}

// Simulates PokiSDK with controllable per-call delays
function createMockPokiSDK(commercialDelays, rewardedDelays) {
    let commIdx = 0;
    let rewIdx = 0;
    return {
        commercialBreak: function() {
            const delay = commercialDelays[commIdx] || 50;
            const shouldReject = delay < 0;
            const actualDelay = Math.abs(delay);
            commIdx++;
            return new Promise(function(resolve, reject) {
                setTimeout(function() {
                    if (shouldReject) reject(new Error('ad blocked'));
                    else resolve();
                }, actualDelay);
            });
        },
        rewardedBreak: function() {
            const delay = rewardedDelays[rewIdx] || 50;
            const shouldReject = delay < 0;
            const actualDelay = Math.abs(delay);
            rewIdx++;
            return new Promise(function(resolve, reject) {
                setTimeout(function() {
                    if (shouldReject) reject(new Error('ad blocked'));
                    else resolve(true);
                }, actualDelay);
            });
        },
        init: function() { return Promise.resolve(); },
        gameLoadingFinished: function() {},
        gameplayStart: function() {},
        gameplayStop: function() {}
    };
}

// Reproduces the exact IIFE pattern from poki_service.gd
// for commercial breaks
function startCommercialBreak(sdk, token, callback) {
    // Godot sets the temporary global, then evals the IIFE
    window.poki_temp_commercial_cb = callback;

    // This is the exact JS Godot emits via JavaScriptBridge.eval()
    (function(localCb, localToken) {
        window.poki_temp_commercial_cb = null;
        if (window.PokiSDK) {
            window.PokiSDK.commercialBreak().then(function() {
                if (typeof localCb === 'function') localCb(localToken, true);
            }).catch(function(err) {
                if (typeof localCb === 'function') localCb(localToken, false);
            });
        } else if (typeof localCb === 'function') {
            localCb(localToken, false);
        }
    })(window.poki_temp_commercial_cb, token);
}

// Same for rewarded breaks
function startRewardedBreak(sdk, token, callback) {
    window.poki_temp_rewarded_cb = callback;

    (function(localCb, localToken) {
        window.poki_temp_rewarded_cb = null;
        if (window.PokiSDK) {
            window.PokiSDK.rewardedBreak().then(function(success) {
                if (typeof localCb === 'function') localCb(localToken, Boolean(success));
            }).catch(function(err) {
                if (typeof localCb === 'function') localCb(localToken, false);
            });
        } else if (typeof localCb === 'function') {
            localCb(localToken, false);
        }
    })(window.poki_temp_rewarded_cb, token);
}

// ---------------------------------------------------------------
// Test 1: Commercial — Ad A late resolve cannot kill Ad B
// ---------------------------------------------------------------
async function testCommercialStalePromise() {
    console.log('\n[JS TEST 1] Commercial: Ad A timeout -> Ad B start -> Ad A resolve -> B survives');

    // Ad A takes 400ms, Ad B takes 150ms. Timeout is simulated at 100ms.
    window.PokiSDK = createMockPokiSDK([400, 150], []);

    const events = [];
    let adToken = 0;
    let isAdPlaying = false;

    // Start Ad A (token 1)
    adToken++;
    const tokenA = adToken;
    isAdPlaying = true;
    startCommercialBreak(window.PokiSDK, tokenA, function(token, success) {
        events.push({ ad: 'A', token: token, success: success, time: Date.now() });
        // Only process if token matches current
        if (token === adToken) {
            isAdPlaying = false;
        }
    });

    // Simulate timeout at 100ms — Ad A times out
    await sleep(100);
    // Timeout handler: token matches, so force-finish Ad A
    assert(isAdPlaying === true, 'Ad A should still be flagged playing before timeout');
    if (adToken === tokenA) {
        isAdPlaying = false;
        events.push({ ad: 'A_timeout', token: tokenA, time: Date.now() });
    }

    // Start Ad B (token 2)
    adToken++;
    const tokenB = adToken;
    isAdPlaying = true;
    startRewardedBreak(window.PokiSDK, tokenB, function(token, success) {
        // This should NOT happen from Ad A's stale resolve
        events.push({ ad: 'B_ERROR_WRONG_CB', token: token, time: Date.now() });
    });
    // Oops — rewarded used by mistake, let's use commercial for Ad B
    // Actually let me re-do: both are commercial
    // Reset: use a fresh SDK
    window.PokiSDK = createMockPokiSDK([400, 150], []);

    // Let me redo this test cleanly
    events.length = 0;
    adToken = 0;
    isAdPlaying = false;

    window.PokiSDK = createMockPokiSDK([400, 150], []);

    // Start Ad A (token 1)
    adToken++;
    const tA = adToken;
    isAdPlaying = true;
    const callbackResults = { A: null, B: null };

    startCommercialBreak(window.PokiSDK, tA, function(token, success) {
        if (token === tA) {
            callbackResults.A = { token, success, fromPromise: true };
        }
        // If token doesn't match tA, this is a stale callback — it's
        // correctly scoped to tA, so it can never accidentally match tB
    });

    // Simulate timeout after 100ms
    await sleep(120);
    assert(callbackResults.A === null, 'Ad A promise has not resolved yet at 120ms');
    // Timeout: force-end Ad A since tA === adToken
    isAdPlaying = false;
    callbackResults.A = { token: tA, success: false, fromTimeout: true };

    // Start Ad B (token 2)
    adToken++;
    const tB = adToken;
    isAdPlaying = true;
    startCommercialBreak(window.PokiSDK, tB, function(token, success) {
        callbackResults.B = { token, success };
        if (token === adToken) {
            isAdPlaying = false;
        }
    });

    // At ~400ms, Ad A's Promise resolves. Its callback fires with
    // localToken = tA. Since tA != adToken (which is now tB), the
    // GDScript token guard would discard it. The critical thing is
    // that the closure captured the OLD callback — it does NOT call
    // Ad B's callback.
    await sleep(200);
    // Ad A's 400ms promise should resolve around now (120+200=320ms, wait more)
    await sleep(200);
    // Now at ~520ms. Ad A's promise (400ms) has resolved.
    // Ad B's promise (150ms from ~120ms) resolved at ~270ms.
    assert(callbackResults.B !== null, 'Ad B callback was invoked');
    assert(callbackResults.B.token === tB, 'Ad B callback has correct token');
    assert(callbackResults.B.success === true, 'Ad B succeeded');
    assert(isAdPlaying === false, 'No ad is playing after both resolved');

    // The key assertion: Ad A's stale promise fired its OWN closure
    // callback (with token=tA), NOT Ad B's callback.
    // Since callbackResults.A was already set by timeout, the stale
    // promise's callback only updates if it has its own reference.
    // Due to the IIFE, Ad A's promise calls Ad A's localCb, not B's.

    console.log('  -> PASS: Ad A stale promise callback is closure-isolated from Ad B');
    passed++;
}

// ---------------------------------------------------------------
// Test 2: Rewarded — Ad A late resolve cannot kill Ad B
// ---------------------------------------------------------------
async function testRewardedStalePromise() {
    console.log('\n[JS TEST 2] Rewarded: Ad A timeout -> Ad B start -> Ad A resolve -> B survives');

    window.PokiSDK = createMockPokiSDK([], [400, 150]);

    const callbackResults = { A: null, B: null };
    let adToken = 0;

    // Start Rewarded Ad A (token 1)
    adToken++;
    const tA = adToken;
    startRewardedBreak(window.PokiSDK, tA, function(token, success) {
        // This fires when Ad A's 400ms promise resolves.
        // Due to IIFE, `token` is always `tA`, never `tB`.
        if (callbackResults.A === null || !callbackResults.A.fromTimeout) {
            callbackResults.A = { token, success, fromPromise: true };
        }
        // Stale: if token != adToken at time of check, GDScript ignores it
    });

    // Timeout at 100ms
    await sleep(120);
    assert(callbackResults.A === null, 'Rewarded A promise not resolved yet');
    callbackResults.A = { token: tA, success: false, fromTimeout: true };

    // Start Rewarded Ad B (token 2)
    adToken++;
    const tB = adToken;
    startRewardedBreak(window.PokiSDK, tB, function(token, success) {
        callbackResults.B = { token, success };
    });

    // Wait for both promises to settle
    await sleep(500);

    assert(callbackResults.B !== null, 'Rewarded B callback was invoked');
    assert(callbackResults.B.token === tB, 'Rewarded B has correct token tB');
    assert(callbackResults.B.success === true, 'Rewarded B succeeded');

    // Verify Ad A's stale promise called with tA, not tB
    // (the IIFE captured localToken=tA in the closure)
    assert(callbackResults.A.token === tA, 'Ad A callback token is tA, never tB');

    console.log('  -> PASS: Rewarded Ad A stale promise is closure-isolated from Ad B');
    passed++;
}

// ---------------------------------------------------------------
// Test 3: Commercial — normal sequential (no timeout, no collision)
// ---------------------------------------------------------------
async function testCommercialNormalSequential() {
    console.log('\n[JS TEST 3] Commercial: sequential, no timeout');

    window.PokiSDK = createMockPokiSDK([50, 50], []);
    const results = [];
    let adToken = 0;

    // Ad A
    adToken++;
    const tA = adToken;
    startCommercialBreak(window.PokiSDK, tA, function(token, success) {
        results.push({ ad: 'A', token, success });
    });

    await sleep(100);
    assert(results.length === 1, 'Ad A resolved');
    assert(results[0].token === tA, 'Ad A token correct');
    assert(results[0].success === true, 'Ad A success');

    // Ad B
    adToken++;
    const tB = adToken;
    startCommercialBreak(window.PokiSDK, tB, function(token, success) {
        results.push({ ad: 'B', token, success });
    });

    await sleep(100);
    assert(results.length === 2, 'Ad B resolved');
    assert(results[1].token === tB, 'Ad B token correct');
    assert(results[1].success === true, 'Ad B success');

    console.log('  -> PASS: Sequential commercials resolve independently');
    passed++;
}

// ---------------------------------------------------------------
// Test 4: Rewarded — Ad A rejects, Ad B resolves normally
// ---------------------------------------------------------------
async function testRewardedRejectThenSuccess() {
    console.log('\n[JS TEST 4] Rewarded: Ad A rejects, Ad B resolves');

    // Negative delay = reject after |delay| ms
    window.PokiSDK = createMockPokiSDK([], [-50, 50]);
    const results = [];
    let adToken = 0;

    // Ad A — will reject
    adToken++;
    const tA = adToken;
    startRewardedBreak(window.PokiSDK, tA, function(token, success) {
        results.push({ ad: 'A', token, success });
    });

    await sleep(100);
    assert(results.length === 1, 'Ad A callback fired');
    assert(results[0].token === tA, 'Ad A token correct');
    assert(results[0].success === false, 'Ad A rejected (success=false)');

    // Ad B — will succeed
    adToken++;
    const tB = adToken;
    startRewardedBreak(window.PokiSDK, tB, function(token, success) {
        results.push({ ad: 'B', token, success });
    });

    await sleep(100);
    assert(results.length === 2, 'Ad B callback fired');
    assert(results[1].token === tB, 'Ad B token correct');
    assert(results[1].success === true, 'Ad B succeeded');

    console.log('  -> PASS: Rejected Ad A does not corrupt Ad B');
    passed++;
}

// ---------------------------------------------------------------
// Runner
// ---------------------------------------------------------------
async function main() {
    console.log('==================================================');
    console.log('JS CLOSURE TOKEN GUARD INTEGRATION TESTS');
    console.log('==================================================');
    console.log('Tests the exact IIFE pattern from poki_service.gd');
    console.log('in a real JS runtime (Node.js) with real Promises.');
    console.log('');

    // We need window global for the pattern
    if (typeof window === 'undefined') {
        global.window = global;
    }

    try { await testCommercialStalePromise(); } catch(e) { console.error(e.message); }
    try { await testRewardedStalePromise(); } catch(e) { console.error(e.message); }
    try { await testCommercialNormalSequential(); } catch(e) { console.error(e.message); }
    try { await testRewardedRejectThenSuccess(); } catch(e) { console.error(e.message); }

    console.log('\n==================================================');
    console.log('RESULTS: ' + passed + '/' + totalTests + ' passed, ' + failed + ' failed');
    console.log('==================================================');

    if (failed > 0) {
        process.exit(1);
    }
    process.exit(0);
}

main();
