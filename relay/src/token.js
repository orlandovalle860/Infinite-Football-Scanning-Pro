/**
 * Opaque bearer tokens for display/coach WebSocket auth.
 */
import crypto from 'crypto';

export function generateToken() {
  return crypto.randomBytes(32).toString('base64url');
}
