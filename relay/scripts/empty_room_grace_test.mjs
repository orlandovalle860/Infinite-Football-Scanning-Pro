/**
 * Focused relay tests: empty-room grace (15m default), cancel-on-reconnect, TTL, same-token.
 *
 * Uses fake timers — does not wait real wall-clock minutes.
 *
 * Run: node scripts/empty_room_grace_test.mjs
 */
import assert from 'assert';

import {
  createSession,
  claimCoachSlot,
  attachSocket,
  detachSocket,
  getRoom,
  _resetStoreForTests,
  EMPTY_ROOM_GRACE_MS,
  DEFAULT_TTL_MS,
} from '../src/roomStore.js';

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

function mockWs(label) {
  return { label, readyState: 1 };
}

// --- Fake timers (only for grace scheduling; Date.now for TTL uses real clock unless stubbed) ---

const pendingTimers = [];
let fakeNow = 0;
const realSetTimeout = globalThis.setTimeout;
const realClearTimeout = globalThis.clearTimeout;

function installFakeTimers() {
  fakeNow = 0;
  pendingTimers.length = 0;
  globalThis.setTimeout = (fn, ms, ...args) => {
    const handle = {
      fn,
      args,
      due: fakeNow + (Number(ms) || 0),
      cleared: false,
    };
    pendingTimers.push(handle);
    return handle;
  };
  globalThis.clearTimeout = (handle) => {
    if (handle && typeof handle === 'object') handle.cleared = true;
  };
}

function restoreRealTimers() {
  globalThis.setTimeout = realSetTimeout;
  globalThis.clearTimeout = realClearTimeout;
  pendingTimers.length = 0;
}

function advanceFakeMs(ms) {
  fakeNow += ms;
  const due = pendingTimers.filter((h) => !h.cleared && h.due <= fakeNow);
  for (const h of due) {
    h.cleared = true;
    h.fn(...h.args);
  }
}

function pendingGraceCount() {
  return pendingTimers.filter((h) => !h.cleared).length;
}

function bothAttachedRoom() {
  const room = createSession();
  const { coachToken } = claimCoachSlot(room.joinCode);
  const display = mockWs('display');
  const coach = mockWs('coach');
  attachSocket(room.sessionId, 'display', room.displayToken, display);
  attachSocket(room.sessionId, 'coach', coachToken, coach);
  return { room, coachToken, display, coach };
}

function detachBoth({ room, display, coach }) {
  assert(detachSocket(room, 'display', display) === true, 'display detach');
  assert(detachSocket(room, 'coach', coach) === true, 'coach detach');
}

console.log('\n[empty-room grace] constants');
try {
  assert.strictEqual(EMPTY_ROOM_GRACE_MS, 15 * 60 * 1000, 'default grace must be 15 minutes');
  assert.strictEqual(DEFAULT_TTL_MS, 24 * 60 * 60 * 1000, 'default ROOM_TTL must remain 24h');
  ok('F0. EMPTY_ROOM_GRACE_MS default is 15m; ROOM_TTL_MS default is 24h');
} catch (e) {
  fail('constants', e);
}

console.log('\n[empty-room grace] A–E fake timers');
installFakeTimers();
try {
  _resetStoreForTests();
  const ctx = bothAttachedRoom();
  const sid = ctx.room.sessionId;

  detachBoth(ctx);
  assert(pendingGraceCount() === 1, 'grace timer scheduled when both gone');
  assert(getRoom(sid) != null, 'room still present immediately after empty');
  ok('schedule: both sockets gone starts empty-room grace');

  // A. Not deleted before 15-minute grace
  advanceFakeMs(15 * 60 * 1000 - 1);
  assert(getRoom(sid) != null, 'room must survive until grace elapses');
  ok('A. Room NOT deleted before 15-minute grace');

  // Reset for B: reconnect before grace cancels deletion
  _resetStoreForTests();
  const ctxB = bothAttachedRoom();
  const sidB = ctxB.room.sessionId;
  const { coachToken: tokenB } = { coachToken: ctxB.coachToken };
  detachBoth(ctxB);
  assert(pendingGraceCount() === 1, 'grace armed');
  advanceFakeMs(5 * 60 * 1000); // past old 5m, still within 15m
  assert(getRoom(sidB) != null, 'still alive at 5m');

  const display2 = mockWs('display2');
  attachSocket(sidB, 'display', ctxB.room.displayToken, display2);
  assert(pendingGraceCount() === 0, 'grace timer cancelled on peer reconnect');
  assert(getRoom(sidB) != null, 'room retained after cancel');
  advanceFakeMs(15 * 60 * 1000);
  assert(getRoom(sidB) != null, 'room must not delete after cancelled grace');
  ok('B. Reconnect before grace cancels deletion');

  // D. Same-token coach reconnect still works before grace expiry
  const coachOld = mockWs('coach-old');
  const coachNew = mockWs('coach-new');
  attachSocket(sidB, 'coach', tokenB, coachOld);
  const replaced = attachSocket(sidB, 'coach', tokenB, coachNew);
  assert(replaced.replacedSocket === coachOld, 'same-token replace returns old socket');
  assert(getRoom(sidB).coachSocket === coachNew, 'new coach owns slot');
  assert(detachSocket(getRoom(sidB), 'coach', coachOld) === false, 'old cleanup identity-safe');
  ok('D. Same-token reconnect works before grace expiry');

  // C. Room deleted after full grace (fresh empty)
  detachSocket(getRoom(sidB), 'display', display2);
  detachSocket(getRoom(sidB), 'coach', coachNew);
  assert(pendingGraceCount() === 1, 'grace re-armed');
  advanceFakeMs(15 * 60 * 1000);
  assert(getRoom(sidB) == null, 'room deleted after grace');
  ok('C. Room is deleted after grace');

  // E. SESSION_NOT_FOUND after room truly deleted
  let notFound = false;
  try {
    attachSocket(sidB, 'display', ctxB.room.displayToken, mockWs('late'));
  } catch (e) {
    notFound = e.code === 'SESSION_NOT_FOUND';
  }
  assert(notFound, 'expected SESSION_NOT_FOUND');
  ok('E. SESSION_NOT_FOUND after room is truly deleted');

  // G. Genuine peer disconnect clears slot (peer_left path precondition)
  _resetStoreForTests();
  const ctxG = bothAttachedRoom();
  const detachedDisplay = detachSocket(ctxG.room, 'display', ctxG.display);
  assert(detachedDisplay === true, 'genuine display detach returns true');
  assert(getRoom(ctxG.room.sessionId).displaySocket === null, 'display slot cleared');
  assert(getRoom(ctxG.room.sessionId).coachSocket === ctxG.coach, 'coach still present');
  assert(pendingGraceCount() === 0, 'grace not scheduled while peer remains');
  ok('G. Genuine single-peer disconnect clears only that slot; no empty grace yet');
} catch (e) {
  fail('A–E/G block', e);
} finally {
  _resetStoreForTests();
  restoreRealTimers();
}

console.log('\n[empty-room grace] F TTL unchanged (real timers)');
try {
  _resetStoreForTests();
  const room = createSession();
  const span = room.expiresAt - room.createdAt;
  assert.strictEqual(span, DEFAULT_TTL_MS, 'expiresAt uses DEFAULT_TTL_MS');
  assert.strictEqual(DEFAULT_TTL_MS, 24 * 60 * 60 * 1000, '24h TTL constant');

  // Force TTL expiry path without waiting 24h
  room.expiresAt = Date.now() - 1;
  let expired = false;
  try {
    claimCoachSlot(room.joinCode);
  } catch (e) {
    expired = e.code === 'SESSION_EXPIRED';
  }
  // claimCoachSlot deletes on expiry — room may already be gone
  assert(expired || getRoom(room.sessionId) == null, 'TTL expiry path removes or rejects session');
  ok('F. 24h TTL behavior remains unchanged (constant + expiry path)');
} catch (e) {
  fail('TTL', e);
} finally {
  _resetStoreForTests();
}

console.log(`\n[empty-room grace] ${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
