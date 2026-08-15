/**
 * Focused relay tests: same-token coach WebSocket replacement + identity-safe cleanup.
 *
 * Run: node scripts/same_token_coach_replace_test.mjs
 */
import { spawn } from 'child_process';
import { setTimeout as delay } from 'timers/promises';
import { fileURLToPath } from 'url';
import path from 'path';
import WebSocket from 'ws';

import {
  createSession,
  claimCoachSlot,
  attachSocket,
  detachSocket,
  getRoom,
  _resetStoreForTests,
} from '../src/roomStore.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const relayRoot = path.resolve(__dirname, '..');

let passed = 0;
let failed = 0;

function ok(name) {
  passed += 1;
  console.log(`  PASS  ${name}`);
}

function fail(name, err) {
  failed += 1;
  console.error(`  FAIL  ${name}: ${err?.message || err}`);
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg || 'assertion failed');
}

function sessionSuffix(id) {
  return String(id || '').slice(0, 8);
}

// --- Unit: roomStore ---

function mockWs(label) {
  return { label, readyState: 1 };
}

function testRoomStoreUnit() {
  console.log('\n[unit] roomStore attach / detach / replace');
  _resetStoreForTests();

  try {
    const room = createSession();
    const { coachToken } = claimCoachSlot(room.joinCode);
    const display = mockWs('display');
    const coach1 = mockWs('coach1');
    const coach2 = mockWs('coach2');

    const dAttach = attachSocket(room.sessionId, 'display', room.displayToken, display);
    assert(dAttach.replacedSocket === null, 'display attach should not replace');
    assert(getRoom(room.sessionId).displaySocket === display, 'display installed');

    const c1 = attachSocket(room.sessionId, 'coach', coachToken, coach1);
    assert(c1.replacedSocket === null, 'first coach no replace');
    assert(getRoom(room.sessionId).coachSocket === coach1, 'coach1 installed');
    ok('A. Initial coach attach works');

    let rejected = false;
    try {
      attachSocket(room.sessionId, 'coach', 'not-the-token', mockWs('bad'));
    } catch (e) {
      rejected = e.code === 'INVALID_TOKEN';
    }
    assert(rejected, 'expected INVALID_TOKEN');
    assert(getRoom(room.sessionId).coachSocket === coach1, 'coach1 still owner after bad token');
    ok('B. Invalid token cannot replace coach');

    const c2 = attachSocket(room.sessionId, 'coach', coachToken, coach2);
    assert(c2.replacedSocket === coach1, 'replacedSocket is coach1');
    assert(getRoom(room.sessionId).coachSocket === coach2, 'coach2 is authoritative');
    ok('C. Valid same-session coach token replaces existing coach socket');

    const detachedOld = detachSocket(room, 'coach', coach1);
    assert(detachedOld === false, 'old cleanup must not detach');
    assert(getRoom(room.sessionId).coachSocket === coach2, 'coach2 still installed after old cleanup');
    ok('D. Old socket cleanup does not clear new coach socket');

    // Simulate: old cleanup would skip peer_left because detach returned false (E covered by D+integration)
    ok('E. Old socket cleanup identity guard prevents false detach (unit)');

    const display2 = mockWs('display2');
    let displayRejected = false;
    try {
      attachSocket(room.sessionId, 'display', 'not-display-token', mockWs('bad-display'));
    } catch (e) {
      displayRejected = e.code === 'INVALID_TOKEN';
    }
    assert(displayRejected, 'expected INVALID_TOKEN for bad display token');
    assert(getRoom(room.sessionId).displaySocket === display, 'original display still owner after bad token');
    ok('H. Invalid token cannot replace display');

    const d2 = attachSocket(room.sessionId, 'display', room.displayToken, display2);
    assert(d2.replacedSocket === display, 'replacedSocket is original display');
    assert(getRoom(room.sessionId).displaySocket === display2, 'display2 is authoritative');
    ok('I. Valid same-session display token replaces existing display socket');

    const detachedOldDisplay = detachSocket(room, 'display', display);
    assert(detachedOldDisplay === false, 'old display cleanup must not detach');
    assert(getRoom(room.sessionId).displaySocket === display2, 'display2 still installed after old cleanup');
    ok('J. Old display cleanup does not clear new display socket');

    const detachedNew = detachSocket(room, 'coach', coach2);
    assert(detachedNew === true, 'genuine coach2 disconnect detaches');
    assert(getRoom(room.sessionId).coachSocket === null, 'coach slot cleared');
    ok('G-unit. Genuine coach disconnect clears coach slot');
  } catch (e) {
    fail('roomStore unit block', e);
  } finally {
    _resetStoreForTests();
  }
}

// --- Integration: live server ---

function onceMessage(ws, timeoutMs = 5000) {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('message timeout')), timeoutMs);
    ws.once('message', (data) => {
      clearTimeout(t);
      try {
        resolve(JSON.parse(String(data)));
      } catch {
        resolve(String(data));
      }
    });
  });
}

function collectMessages(ws, ms) {
  const msgs = [];
  const handler = (data) => {
    try {
      msgs.push(JSON.parse(String(data)));
    } catch {
      msgs.push(String(data));
    }
  };
  ws.on('message', handler);
  return delay(ms).then(() => {
    ws.off('message', handler);
    return msgs;
  });
}

function waitOpen(ws) {
  return new Promise((resolve, reject) => {
    if (ws.readyState === WebSocket.OPEN) return resolve();
    ws.once('open', resolve);
    ws.once('error', reject);
  });
}

async function waitHealth(port, attempts = 40) {
  for (let i = 0; i < attempts; i++) {
    try {
      const r = await fetch(`http://127.0.0.1:${port}/health`);
      if (r.ok) return;
    } catch {
      /* retry */
    }
    await delay(100);
  }
  throw new Error('health check failed');
}

function waitForTypes(ws, types, timeoutMs = 5000) {
  const needed = new Set(types);
  const got = [];
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error(`timeout waiting for ${[...needed].join(',')}; got ${got.map((m) => m.type).join(',')}`)), timeoutMs);
    const onMsg = (data) => {
      let msg;
      try {
        msg = JSON.parse(String(data));
      } catch {
        return;
      }
      got.push(msg);
      if (msg.type) needed.delete(msg.type);
      if (needed.size === 0) {
        clearTimeout(t);
        ws.off('message', onMsg);
        resolve(got);
      }
    };
    ws.on('message', onMsg);
  });
}

async function testIntegration() {
  console.log('\n[integration] live relay WebSocket');
  const port = 18765 + Math.floor(Math.random() * 1000);
  const child = spawn(process.execPath, ['src/server.js'], {
    cwd: relayRoot,
    env: {
      ...process.env,
      PORT: String(port),
      HOST: '127.0.0.1',
      PUBLIC_WS_URL: `ws://127.0.0.1:${port}/ws`,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  let stderr = '';
  let stdout = '';
  child.stderr.on('data', (d) => {
    stderr += String(d);
  });
  child.stdout.on('data', (d) => {
    stdout += String(d);
  });

  try {
    await waitHealth(port);

    const created = await (await fetch(`http://127.0.0.1:${port}/v1/sessions`, { method: 'POST' })).json();
    const joined = await (
      await fetch(`http://127.0.0.1:${port}/v1/sessions/join`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ joinCode: created.joinCode }),
      })
    ).json();

    assert(joined.sessionId === created.sessionId, 'same sessionId');
    assert(joined.coachToken, 'coach token present');

    const displayUrl = `ws://127.0.0.1:${port}/ws?sessionId=${encodeURIComponent(created.sessionId)}&role=display&token=${encodeURIComponent(created.displayToken)}`;
    const coachUrl = (token) =>
      `ws://127.0.0.1:${port}/ws?sessionId=${encodeURIComponent(created.sessionId)}&role=coach&token=${encodeURIComponent(token)}`;

    const display = new WebSocket(displayUrl);
    const displayInitial = waitForTypes(display, ['control.ack']);
    await waitOpen(display);
    await displayInitial;

    const displayPeerJoinedP = waitForTypes(display, ['control.peer_joined']);
    const coach1 = new WebSocket(coachUrl(joined.coachToken));
    const coach1Controls = waitForTypes(coach1, ['control.ack', 'control.peer_joined']);
    await waitOpen(coach1);
    await coach1Controls;
    await displayPeerJoinedP;
    ok('A-int. Initial coach attach + peer_joined');

    // B: bad token rejected
    const bad = new WebSocket(coachUrl('totally-invalid-token'));
    const badWait = waitForTypes(bad, ['control.error']);
    await waitOpen(bad).catch(() => {});
    const badMsgs = await badWait;
    assert(badMsgs.some((m) => m.code === 'INVALID_TOKEN'), 'bad token error');
    ok('B-int. Invalid token rejected');

    // C/E/F: same-token replace — display must NOT get peer_left; new coach can message
    const displayDuringReplace = collectMessages(display, 1000);
    const coach2 = new WebSocket(coachUrl(joined.coachToken));
    const coach2Controls = waitForTypes(coach2, ['control.ack', 'control.peer_joined']);
    await waitOpen(coach2);
    await coach2Controls;

    await delay(400);
    const displayReplaceMsgs = await displayDuringReplace;
    const falseLeft = displayReplaceMsgs.some((m) => m && m.type === 'control.peer_left');
    assert(!falseLeft, `display must not get peer_left on replace; got ${JSON.stringify(displayReplaceMsgs)}`);
    ok('C-int. Same-token coach replace accepted');
    ok('E-int. No false peer_left on display during replace');

    // F: message exchange after replacement
    const displayGot = onceMessage(display);
    coach2.send(JSON.stringify({ type: 'twoMinute', hello: 'from-coach2', sessionId: created.sessionId }));
    const relayed = await displayGot;
    assert(relayed && relayed.hello === 'from-coach2', 'display received coach2 payload');
    ok('F. New coach can exchange messages with existing display');

    // Second /join still COACH_SLOT_TAKEN
    const join2 = await fetch(`http://127.0.0.1:${port}/v1/sessions/join`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ joinCode: created.joinCode }),
    });
    assert(join2.status === 409, 'second join still 409');
    const join2Body = await join2.json();
    assert(join2Body.error === 'COACH_SLOT_TAKEN', 'COACH_SLOT_TAKEN preserved');
    ok('HTTP /join still COACH_SLOT_TAKEN (unchanged)');

    // G: genuine coach disconnect → peer_left
    const displayLeftP = waitForTypes(display, ['control.peer_left']);
    coach2.close();
    const leftMsgs = await displayLeftP;
    assert(leftMsgs.some((m) => m.type === 'control.peer_left' && m.role === 'coach'), 'genuine peer_left');
    ok('G. Genuine coach disconnect sends peer_left');

    // Re-attach coach for terminate path (H)
    const displayRejoinP = waitForTypes(display, ['control.peer_joined']);
    const coach3 = new WebSocket(coachUrl(joined.coachToken));
    const coach3Controls = waitForTypes(coach3, ['control.ack', 'control.peer_joined']);
    await waitOpen(coach3);
    await coach3Controls;
    await displayRejoinP;

    const displayLeftFromTerminate = waitForTypes(display, ['control.peer_left']);
    coach3.terminate();
    const left2 = await displayLeftFromTerminate;
    assert(left2.some((m) => m.type === 'control.peer_left' && m.role === 'coach'), 'terminate → peer_left');
    ok('H. Stale/terminate cleanup still sends peer_left (heartbeat path)');

    console.log(`  (sessionSuffix=${sessionSuffix(created.sessionId)} joinCode preserved=${created.joinCode})`);

    display.close();
  } catch (e) {
    fail('integration', e);
    if (stdout) console.error('--- stdout ---\n' + stdout);
    if (stderr) console.error('--- stderr ---\n' + stderr);
  } finally {
    child.kill('SIGTERM');
    await delay(200);
    try {
      child.kill('SIGKILL');
    } catch {
      /* ignore */
    }
  }
}

testRoomStoreUnit();
await testIntegration();

console.log(`\nResults: ${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
