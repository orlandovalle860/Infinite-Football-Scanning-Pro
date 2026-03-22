/**
 * In-memory session rooms: one display + one coach per session.
 */
import crypto from 'crypto';
import { generateJoinCode } from './codegen.js';
import { generateToken } from './token.js';

const DEFAULT_TTL_MS = Number(process.env.ROOM_TTL_MS) || 24 * 60 * 60 * 1000; // 24h
const EMPTY_ROOM_GRACE_MS = Number(process.env.EMPTY_ROOM_GRACE_MS) || 5 * 60 * 1000; // 5 min after both gone

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
 * @param {string} sessionId
 * @param {'display' | 'coach'} role
 * @param {string} token
 * @param {WebSocket} ws
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
  if (role === 'display') {
    if (token !== room.displayToken) {
      const err = new Error('INVALID_TOKEN');
      err.code = 'INVALID_TOKEN';
      throw err;
    }
    if (room.displaySocket && room.displaySocket !== ws) {
      const err = new Error('DISPLAY_ALREADY_CONNECTED');
      err.code = 'DISPLAY_ALREADY_CONNECTED';
      throw err;
    }
    room.displaySocket = ws;
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
      const err = new Error('COACH_ALREADY_CONNECTED');
      err.code = 'COACH_ALREADY_CONNECTED';
      throw err;
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
  }

  return room;
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
    room.emptyGraceTimer = setTimeout(() => {
      deleteRoom(room.sessionId);
    }, EMPTY_ROOM_GRACE_MS);
  }
}

export { deleteRoom, DEFAULT_TTL_MS, EMPTY_ROOM_GRACE_MS };
