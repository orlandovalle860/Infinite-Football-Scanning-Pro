/**
 * In-memory session rooms: one display + one coach per session.
 */
import crypto from 'crypto';
import { generateJoinCode } from './codegen.js';
import { generateToken } from './token.js';

const DEFAULT_TTL_MS = Number(process.env.ROOM_TTL_MS) || 24 * 60 * 60 * 1000; // 24h
/** After both peers disconnect, keep the room for field walk-aways / hotspot recovery. */
const EMPTY_ROOM_GRACE_MS = Number(process.env.EMPTY_ROOM_GRACE_MS) || 15 * 60 * 1000; // 15 min after both gone

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

/**
 * @typedef {Object} AttachResult
 * @property {Room} room
 * @property {WebSocket | null} replacedSocket  Same-token replace (display or coach); otherwise null.
 */

/** @type {Map<string, Room>} */
const roomsBySessionId = new Map();
/** @type {Map<string, string>} joinCode -> sessionId */
const sessionIdByJoinCode = new Map();

function sessionSuffix(sessionId) {
  const raw = String(sessionId || '').trim();
  if (!raw) return 'nil';
  return raw.slice(0, 8);
}

function cleanupJoinCode(room) {
  sessionIdByJoinCode.delete(room.joinCode);
}

/**
 * @param {string} sessionId
 * @param {string} [reason]
 */
function deleteRoom(sessionId, reason) {
  const room = roomsBySessionId.get(sessionId);
  if (!room) return;
  if (room.emptyGraceTimer) {
    clearTimeout(room.emptyGraceTimer);
    room.emptyGraceTimer = null;
  }
  cleanupJoinCode(room);
  roomsBySessionId.delete(sessionId);
  if (reason === 'empty_room_grace') {
    console.log(
      `[pba-relay] RELAY room_deleted reason=empty_room_grace sessionSuffix=${sessionSuffix(sessionId)}`
    );
  }
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
    const err = new Error('COACH_SLOT_TAKEN');
    err.code = 'COACH_SLOT_TAKEN';
    throw err;
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
 * Authenticate and attach a display or coach WebSocket.
 *
 * Same-token replacement (display + coach): after validating the role token for this session,
 * if a different socket already owns the slot, the NEW socket is installed first and the
 * previous socket is returned as `replacedSocket` for the caller to close. This recovers from
 * zombie sockets after hotspot drops / client idle disconnects without DISPLAY_ALREADY_CONNECTED
 * / coach attach rejection loops.
 *
 * @param {string} sessionId
 * @param {'display' | 'coach'} role
 * @param {string} token
 * @param {WebSocket} ws
 * @returns {AttachResult}
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

  /** @type {WebSocket | null} */
  let replacedSocket = null;

  if (role === 'display') {
    if (token !== room.displayToken) {
      const err = new Error('INVALID_TOKEN');
      err.code = 'INVALID_TOKEN';
      throw err;
    }
    if (room.displaySocket && room.displaySocket !== ws) {
      // Same valid display token: capture old socket, install NEW as authoritative first.
      replacedSocket = room.displaySocket;
    }
    room.displaySocket = ws;
  } else if (role === 'coach') {
    if (!room.coachClaimedHttp || !room.coachToken) {
      const err = new Error('COACH_NOT_CLAIMED');
      err.code = 'COACH_NOT_CLAIMED';
      throw err;
    }
    // Token must match this session's coach credentials before any replacement.
    if (token !== room.coachToken) {
      const err = new Error('INVALID_TOKEN');
      err.code = 'INVALID_TOKEN';
      throw err;
    }
    if (room.coachSocket && room.coachSocket !== ws) {
      // Same valid coach token: capture old socket, install NEW as authoritative first.
      replacedSocket = room.coachSocket;
    }
    room.coachSocket = ws;
  } else {
    const err = new Error('INVALID_ROLE');
    err.code = 'INVALID_ROLE';
    throw err;
  }

  if (room.emptyGraceTimer) {
    clearTimeout(room.emptyGraceTimer);
    room.emptyGraceTimer = null;
    console.log(
      `[pba-relay] RELAY empty_room_grace_cancelled sessionSuffix=${sessionSuffix(room.sessionId)} reason=peer_reconnected`
    );
  }

  return { room, replacedSocket };
}

/**
 * Detach only if `ws` still owns the role slot (identity-safe for same-token coach replace).
 *
 * @param {Room} room
 * @param {'display' | 'coach'} role
 * @param {WebSocket} ws  Socket being cleaned up
 * @returns {boolean} true if the slot was cleared; false if this socket no longer owns the slot
 */
export function detachSocket(room, role, ws) {
  if (role === 'display') {
    if (room.displaySocket !== ws) return false;
    room.displaySocket = null;
  } else {
    if (room.coachSocket !== ws) return false;
    room.coachSocket = null;
  }

  const bothGone = !room.displaySocket && !room.coachSocket;
  if (bothGone) {
    if (room.emptyGraceTimer) clearTimeout(room.emptyGraceTimer);
    const sid = room.sessionId;
    console.log(
      `[pba-relay] RELAY empty_room_grace_scheduled sessionSuffix=${sessionSuffix(sid)} graceMs=${EMPTY_ROOM_GRACE_MS}`
    );
    room.emptyGraceTimer = setTimeout(() => {
      room.emptyGraceTimer = null;
      deleteRoom(sid, 'empty_room_grace');
    }, EMPTY_ROOM_GRACE_MS);
  }
  return true;
}

/** Test helper: wipe in-memory rooms (not used in production). */
export function _resetStoreForTests() {
  for (const room of roomsBySessionId.values()) {
    if (room.emptyGraceTimer) clearTimeout(room.emptyGraceTimer);
  }
  roomsBySessionId.clear();
  sessionIdByJoinCode.clear();
}

export { deleteRoom, DEFAULT_TTL_MS, EMPTY_ROOM_GRACE_MS };
