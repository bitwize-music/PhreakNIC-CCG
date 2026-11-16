// Standalone local reproductions; no production requests or room creation.
import {test} from 'node:test';
import assert from 'node:assert/strict';
import site from '../cloudflare/site/src/index.js';
import {code, validCode} from '../cloudflare/online/src/lib/protocol.js';

function fixture() {
  const forwarded = [];
  // No /join/<code> file exists in the Godot export. The site config does not
  // enable single-page-application fallback, so the asset miss returns 404.
  const env = {ASSETS:{fetch:async request => {
    forwarded.push(new URL(request.url).pathname);
    return new Response('Not found', {status:404});
  }}};
  return {env, forwarded};
}

test('control: legacy four-character invite redirects to the root with its code', async () => {
  const {env, forwarded} = fixture();
  const response = await site.fetch(new Request('https://phreaknic-ccg.net/join/AB23'), env, {});
  assert.equal(response.status, 302);
  assert.equal(response.headers.get('location'), 'https://phreaknic-ccg.net/?join=AB23');
  assert.deepEqual(forwarded, []);
});

test('W31-01: current generated room codes must work in the UI invite-link format', async () => {
  const roomCode = code({getRandomValues(bytes){bytes.fill(0); return bytes;}});
  assert.equal(roomCode.length, 6, 'control: use the actual current room-code generator');
  assert(validCode(roomCode), 'control: the room service accepts this code');
  const {env, forwarded} = fixture();
  const response = await site.fetch(new Request('https://phreaknic-ccg.net/join/' + roomCode), env, {});
  assert.equal(response.status, 302,
    `Generated code ${roomCode} fell through to ASSETS at ${JSON.stringify(forwarded)}`);
  assert.equal(response.headers.get('location'), 'https://phreaknic-ccg.net/?join=' + roomCode);
});
