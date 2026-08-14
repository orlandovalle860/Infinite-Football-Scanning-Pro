/**
 * Local smoke tests for same-token display + coach reconnect.
 * Run: PORT=3010 node scripts/same_token_display_reconnect_test.mjs
 */
import { WebSocket } from 'ws';

const PORT = Number(process.env.PORT) || 3000;
const BASE = `http://127.0.0.1:${PORT}`;
const WS_BASE = `ws://127.0.0.1:${PORT}/ws`;

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function connectWS({ sessionId, role, token }) {
  const url = `${WS_BASE}?sessionId=${encodeURIComponent(sessionId)}&role=${role}&token=${encodeURIComponent(token)}`;
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    const msgs = [];
    let settled = false;
    const timer = setTimeout(() => {
      if (!settled) {
        settled = true;
        reject(new Error('connect timeout'));
      }
    }, 5000);
    ws.on('message', (data) => {
      try {
        msgs.push(JSON.parse(data.toString()));
      } catch {
        msgs.push({ raw: data.toString() });
      }
    });
    ws.on('open', () => {
      setTimeout(() => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        resolve({ ws, msgs });
      }, 150);
    });
    ws.on('error', (err) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      reject(err);
    });
  });
}

async function createSession() {
  const res = await fetch(`${BASE}/v1/sessions`, { method: 'POST' });
  if (!res.ok) throw new Error(`create ${res.status}`);
  return res.json();
}

async function joinSession(joinCode) {
  const res = await fetch(`${BASE}/v1/sessions/join`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ joinCode }),
  });
  if (!res.ok) throw new Error(`join ${res.status} ${await res.text()}`);
  return res.json();
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

async function testA_normalDisplay() {
  const s = await createSession();
  const { ws, msgs } = await connectWS({
    sessionId: s.sessionId,
    role: 'display',
    token: s.displayToken,
  });
  assert(msgs.some((m) => m.type === 'control.ack'), 'A: expected control.ack');
  ws.close();
  console.log('PASS A normal display connection');
}

async function testB_cleanReconnect() {
  const s = await createSession();
  const first = await connectWS({
    sessionId: s.sessionId,
    role: 'display',
    token: s.displayToken,
  });
  first.ws.close();
  await sleep(100);
  const second = await connectWS({
    sessionId: s.sessionId,
    role: 'display',
    token: s.displayToken,
  });
  assert(second.msgs.some((m) => m.type === 'control.ack'), 'B: reconnect ack');
  assert(!second.msgs.some((m) => m.code === 'DISPLAY_ALREADY_CONNECTED'), 'B: no already connected');
  second.ws.close();
  console.log('PASS B clean reconnect');
}

async function testC_zombieReplace() {
  const s = await createSession();
  const first = await connectWS({
    sessionId: s.sessionId,
    role: 'display',
    token: s.displayToken,
  });
  const second = await connectWS({
    sessionId: s.sessionId,
    role: 'display',
    token: s.displayToken,
  });
  assert(second.msgs.some((m) => m.type === 'control.ack'), 'C: reclaim ack');
  assert(!second.msgs.some((m) => m.code === 'DISPLAY_ALREADY_CONNECTED'), 'C: no already connected');
  await sleep(100);
  assert(
    first.ws.readyState === WebSocket.CLOSED || first.ws.readyState === WebSocket.CLOSING,
    'C: old socket closed/replaced'
  );
  second.ws.close();
  console.log('PASS C zombie same-token replace');
}

async function testG_wrongTokenRejected() {
  const s = await createSession();
  const first = await connectWS({
    sessionId: s.sessionId,
    role: 'display',
    token: s.displayToken,
  });
  let rejected = false;
  try {
    const bad = await connectWS({
      sessionId: s.sessionId,
      role: 'display',
      token: 'not-the-display-token',
    });
    if (bad.msgs.some((m) => m.code === 'INVALID_TOKEN' || m.type === 'control.error')) {
      rejected = true;
    }
    bad.ws.close();
  } catch {
    rejected = true;
  }
  assert(rejected, 'G: wrong token must fail');
  assert(first.ws.readyState === WebSocket.OPEN, 'G: legitimate display still open');
  first.ws.close();
  console.log('PASS G unauthorized token rejected (legitimate display kept)');
}

async function testH_coachPreserved() {
  const s = await createSession();
  const display1 = await connectWS({
    sessionId: s.sessionId,
    role: 'display',
    token: s.displayToken,
  });
  const joined = await joinSession(s.joinCode);
  const coach = await connectWS({
    sessionId: joined.sessionId,
    role: 'coach',
    token: joined.coachToken,
  });
  assert(coach.msgs.some((m) => m.type === 'control.ack'), 'H: coach ack');
  const coachMsgsBefore = coach.msgs.length;
  const display2 = await connectWS({
    sessionId: s.sessionId,
    role: 'display',
    token: s.displayToken,
  });
  assert(display2.msgs.some((m) => m.type === 'control.ack'), 'H: display2 ack');
  await sleep(200);
  assert(coach.ws.readyState === WebSocket.OPEN, 'H: coach still open after display replace');
  const later = coach.msgs.slice(coachMsgsBefore);
  assert(!later.some((m) => m.type === 'control.error'), 'H: coach no control.error');
  display2.ws.close();
  coach.ws.close();
  void display1;
  console.log('PASS H coach preserved while display replaced');
}

async function testCoachZombieReplace() {
  const s = await createSession();
  await connectWS({
    sessionId: s.sessionId,
    role: 'display',
    token: s.displayToken,
  });
  const joined = await joinSession(s.joinCode);
  const coach1 = await connectWS({
    sessionId: joined.sessionId,
    role: 'coach',
    token: joined.coachToken,
  });
  const coach2 = await connectWS({
    sessionId: joined.sessionId,
    role: 'coach',
    token: joined.coachToken,
  });
  assert(coach2.msgs.some((m) => m.type === 'control.ack'), 'coach zombie: reclaim ack');
  assert(!coach2.msgs.some((m) => m.code === 'COACH_ALREADY_CONNECTED'), 'coach zombie: no already connected');
  await sleep(100);
  assert(
    coach1.ws.readyState === WebSocket.CLOSED || coach1.ws.readyState === WebSocket.CLOSING,
    'coach zombie: old socket closed'
  );
  coach2.ws.close();
  console.log('PASS coach same-token zombie replace (process-death path)');
}

async function testCoachSoftReclaimJoin() {
  const s = await createSession();
  await connectWS({
    sessionId: s.sessionId,
    role: 'display',
    token: s.displayToken,
  });
  const joined1 = await joinSession(s.joinCode);
  const coach1 = await connectWS({
    sessionId: joined1.sessionId,
    role: 'coach',
    token: joined1.coachToken,
  });
  coach1.ws.close();
  await sleep(150);
  const joined2 = await joinSession(s.joinCode);
  assert(joined2.coachToken === joined1.coachToken, 'soft reclaim returns same coach token');
  const coach2 = await connectWS({
    sessionId: joined2.sessionId,
    role: 'coach',
    token: joined2.coachToken,
  });
  assert(coach2.msgs.some((m) => m.type === 'control.ack'), 'soft reclaim WS ack');
  coach2.ws.close();
  console.log('PASS coach soft-reclaim via /join when socket gone');
}

async function testD_immediateReplace() {
  const s = await createSession();
  const a = await connectWS({
    sessionId: s.sessionId,
    role: 'display',
    token: s.displayToken,
  });
  await sleep(1000);
  const b = await connectWS({
    sessionId: s.sessionId,
    role: 'display',
    token: s.displayToken,
  });
  assert(b.msgs.some((m) => m.type === 'control.ack'), 'D: 1s reclaim');
  b.ws.close();
  console.log('PASS D reconnect ~1s after loss (zombie still present)');
  void a;
}

async function main() {
  const health = await fetch(`${BASE}/health`);
  if (!health.ok) throw new Error('relay not healthy — start with npm start');
  await testA_normalDisplay();
  await testB_cleanReconnect();
  await testC_zombieReplace();
  await testD_immediateReplace();
  await testG_wrongTokenRejected();
  await testH_coachPreserved();
  await testCoachZombieReplace();
  await testCoachSoftReclaimJoin();
  console.log('\nAll automated relay smoke tests passed.');
}

main().catch((e) => {
  console.error('FAIL', e);
  process.exit(1);
});
