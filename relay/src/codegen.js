/**
 * 6-character join codes (uppercase alphanumeric, no ambiguous chars).
 */
import crypto from 'crypto';

const CHARSET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

export function generateJoinCode(length = 6) {
  let out = '';
  const buf = crypto.randomBytes(length);
  for (let i = 0; i < length; i++) {
    out += CHARSET[buf[i] % CHARSET.length];
  }
  return out;
}
