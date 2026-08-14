/**
 * In-memory session rooms: one display + one coach per session.
 */
import crypto from 'crypto';
import { generateJoinCode } from './codegen.js';
import { generateToken } from './token.js';

const DEFAULT_TTL_MS = Number(process.env.ROOM_TTL_MS) || 24 * 60 * 60 * 1000; // 24h
/** After both peers disconnect, keep the room for field walk-aways / lock cycles. */
const EMPTY_ROOM_GRACE_MS = Number(process.env.EMPTY_ROOM_GRACE_MS) || 15 * 60 * 1000; // 15 min

/** @typedef {import('ws').WebSocket} WebSocket */

/**
 * @typedef {Object} Room
 * @property {string} sessionId
 * @property {string} joinCode
 * @property {string} displayToken
 * @property {string | null} coachToken
 * @property {boolean} coachClaimedHttp
 * @property {WebSocket | null} displaySocket
 * @property {WebSocket | null} coachSocket
 * @property {number} expiresAt
 * @property {number} createdAt
 * @property {ReturnType<typeof setTimeout> | null} emptyGraceTimer
 */

/** @type {Map<string, Room>} */
const roomsBySessionId = new Map();
/** @type {Map<string, string>} joinCode -> sessionId */
const sessionIdByJoinCode = new Map();

function sessionSuffix(sessionId) {
  const s = String(sessionId || '');
  return s.length >= 4 ? s.slice(-4) : s || 'nil';
}

function joinSuffix(joinCode) {
  const s = String(joinCode || '');
  return s.length >= 2 ? s.slice(-2) : s || 'nil';
}

function cleanupJoinCode(room) {
  sessionIdByJoinCode.delete(room.joinCode);
}

function deleteRoom(sessionId) {
  const room = roomsBySessionId.get(sessionId);
  if (!room) return;
  if (room.emptyGraceTimer) {
    clearTimeout(room.emptyGraceTimer);
    room.emptyGraceTimer = null;
  }
  cleanupJoinCode(room);
  roomsBySessionId.delete(sessionId);
}

export function createSession() {
  let joinCode;
  do {
    joinCode = generateJoinCode(6);
  } while (sessionIdByJoinCode.has(joinCode));

  const sessionId = crypto.randomUUID();
  const displayToken = generateToken();
  const now = Date.now();
  const expiresAt = now + DEFAULT_TTL_MS;

  /** @type {Room} */
  const room = {
    sessionId,
    joinCode,
    displayToken,
    coachToken: null,
    coachClaimedHttp: false,
    displaySocket: null,
    coachSocket: null,
    expiresAt,
    createdAt: now,
    emptyGraceTimer: null,
  };

  roomsBySessionId.set(sessionId, room);
  sessionIdByJoinCode.set(joinCode, sessionId);
  return room;
}

/**
 * @param {string} joinCodeRaw
 * @returns {{ room: Room, coachToken: string }}
 */
export function claimCoachSlot(joinCodeRaw) {
  const joinCode = String(joinCodeRaw || '')
    .trim()
    .toUpperCase();
  const sessionId = sessionIdByJoinCode.get(joinCode);
  if (!sessionId) {
    const err = new Error('INVALID_JOIN_CODE');
    err.code = 'INVALID_JOIN_CODE';
    throw err;
  }
  const room = roomsBySessionId.get(sessionId);
  if (!room) {
    const err = new Error('SESSION_NOT_FOUND');
    err.code = 'SESSION_NOT_FOUND';
    throw err;
  }
  if (Date.now() > room.expiresAt) {
    deleteRoom(sessionId);
    const err = new Error('SESSION_EXPIRED');
    err.code = 'SESSION_EXPIRED';
    throw err;
  }
  if (room.coachClaimedHttp) {
    // Soft reclaim: coach process death left the HTTP claim but no live coach socket.
    // Re-issue the existing coachToken so clients can recover without a new room/join code.
    // If a coach socket is still registered, refuse (occupied).
    if (room.coachSocket) {
      const err = new Error('COACH_SLOT_TAKEN');
      err.code = 'COACH_SLOT_TAKEN';
      throw err;
    }
    if (!room.coachToken) {
      room.coachToken = generateToken();
    }
    console.log(
      `[PartnerSetup] coach soft-reclaim via join code sessionSuffix=${sessionSuffix(room.sessionId)} joinSuffix=${joinSuffix(room.joinCode)}`
    );
    return { room, coachToken: room.coachToken };
  }

  const coachToken = generateToken();
  room.coachToken = coachToken;
  room.coachClaimedHttp = true;
  return { room, coachToken };
}

export function getRoom(sessionId) {
  return roomsBySessionId.get(sessionId) ?? null;
}

/**
 * Attach a WebSocket to a room role.
 * Display: same valid displayToken may replace a stale/zombie prior display socket (hotspot walk-away).
 * A different token still fails INVALID_TOKEN — cannot steal the slot.
 *
 * @param {string} sessionId
 * @param {'display' | 'coach'} role
 * @param {string} token
 * @param {WebSocket} ws
 * @returns {{ room: Room, replacedPriorDisplay: boolean, replacedPriorCoach: boolean }}
 */
export function attachSocket(sessionId, role, token, ws) {
  const room = roomsBySessionId.get(sessionId);
  if (!room) {
    const err = new Error('SESSION_NOT_FOUND');
    err.code = 'SESSION_NOT_FOUND';
    throw err;
  }
  if (Date.now() > room.expiresAt) {
    deleteRoom(sessionId);
    const err = new Error('SESSION_EXPIRED');
    err.code = 'SESSION_EXPIRED';
    throw err;
  }

  let replacedPriorDisplay = false;
  let replacedPriorCoach = false;

  if (role === 'display') {
    if (token !== room.displayToken) {
      const err = new Error('INVALID_TOKEN');
      err.code = 'INVALID_TOKEN';
      throw err;
    }
    if (room.displaySocket && room.displaySocket !== ws) {
      // Bearer displayToken already proved same authorized display identity for this session.
      const old = room.displaySocket;
      const coachPreserved = !!(room.coachSocket);
      console.log(
        `[PartnerSetup] stale display detected sessionSuffix=${sessionSuffix(room.sessionId)} joinSuffix=${joinSuffix(room.joinCode)} coachPreserved=${coachPreserved}`
      );
      old.__relayReplacedByNewer = true;
      room.displaySocket = ws;
      replacedPriorDisplay = true;
      try {
        old.close(4000, 'replaced_by_same_display_token');
      } catch (_) {
        /* ignore */
      }
      console.log(
        `[PartnerSetup] same-token display reconnect accepted sessionSuffix=${sessionSuffix(room.sessionId)} oldDisplaySocketReplaced=true coachPreserved=${coachPreserved}`
      );
      console.log(
        `[PartnerSetup] new display socket registered sessionSuffix=${sessionSuffix(room.sessionId)} joinSuffix=${joinSuffix(room.joinCode)}`
      );
    } else {
      room.displaySocket = ws;
    }
  } else if (role === 'coach') {
    if (!room.coachClaimedHttp || !room.coachToken) {
      const err = new Error('COACH_NOT_CLAIMED');
      err.code = 'COACH_NOT_CLAIMED';
      throw err;
    }
    if (token !== room.coachToken) {
      const err = new Error('INVALID_TOKEN');
      err.code = 'INVALID_TOKEN';
      throw err;
    }
    if (room.coachSocket && room.coachSocket !== ws) {
      // Same authorized coachToken may reclaim after process death / zombie socket.
      const old = room.coachSocket;
      const displayPreserved = !!(room.displaySocket);
      console.log(
        `[PartnerSetup] stale coach detected sessionSuffix=${sessionSuffix(room.sessionId)} joinSuffix=${joinSuffix(room.joinCode)} displayPreserved=${displayPreserved}`
      );
      old.__relayReplacedByNewer = true;
      room.coachSocket = ws;
      replacedPriorCoach = true;
      try {
        old.close(4000, 'replaced_by_same_coach_token');
      } catch (_) {
        /* ignore */
      }
      console.log(
        `[PartnerSetup] same-token coach reconnect accepted sessionSuffix=${sessionSuffix(room.sessionId)} oldCoachSocketReplaced=true displayPreserved=${displayPreserved}`
      );
    } else {
      room.coachSocket = ws;
    }
  } else {
    const err = new Error('INVALID_ROLE');
    err.code = 'INVALID_ROLE';
    throw err;
  }

  if (room.emptyGraceTimer) {
    clearTimeout(room.emptyGraceTimer);
    room.emptyGraceTimer = null;
    console.log(
      `[PartnerSetup] room empty-grace timer cancel sessionSuffix=${sessionSuffix(room.sessionId)} joinSuffix=${joinSuffix(room.joinCode)}`
    );
  }

  return { room, replacedPriorDisplay, replacedPriorCoach };
}

/**
 * @param {Room} room
 * @param {'display' | 'coach'} role
 */
export function detachSocket(room, role) {
  if (role === 'display') room.displaySocket = null;
  else room.coachSocket = null;

  const bothGone = !room.displaySocket && !room.coachSocket;
  if (bothGone) {
    if (room.emptyGraceTimer) clearTimeout(room.emptyGraceTimer);
    console.log(
      `[PartnerSetup] room empty-grace timer start sessionSuffix=${sessionSuffix(room.sessionId)} joinSuffix=${joinSuffix(room.joinCode)} graceMs=${EMPTY_ROOM_GRACE_MS}`
    );
    room.emptyGraceTimer = setTimeout(() => {
      console.log(
        `[PartnerSetup] room empty-grace delete sessionSuffix=${sessionSuffix(room.sessionId)} joinSuffix=${joinSuffix(room.joinCode)}`
      );
      deleteRoom(room.sessionId);
    }, EMPTY_ROOM_GRACE_MS);
  }
}

export { deleteRoom, DEFAULT_TTL_MS, EMPTY_ROOM_GRACE_MS, sessionSuffix, joinSuffix };
