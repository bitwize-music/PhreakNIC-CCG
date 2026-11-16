// Local Worker reproduction; not included in the regular Worker test directory.
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const original = await readFile(new URL('../cloudflare/online/src/index.js', import.meta.url), 'utf8');
const source = original
  .replace("import { DurableObject } from 'cloudflare:workers';", 'class DurableObject {}')
  .replace("'./lib/protocol.js'", JSON.stringify(new URL('../cloudflare/online/src/lib/protocol.js', import.meta.url).href))
  .replace("'./admin.js'", JSON.stringify(new URL('../cloudflare/online/src/admin.js', import.meta.url).href));
const {Room} = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
const binding = value => ({idFromName: x => x, get: () => value});
const socket = () => ({send(){}, close(){}});
function fixture() {
  const r = Object.assign(Object.create(Room.prototype), {
    r: {code:'AB23CD', created:Date.now(), version:'0.31', started:false, over:false, host_seat:0, card_pool:'2026',
      seats:[{name:'Host', bot:false, token:'a'.repeat(32)}, {name:'Guest', bot:false, token:'b'.repeat(32)}]},
    clients:new Map(), rates:new Map(), generation:0, stat:async()=>{}, save:async()=>{}, broadcastRoom(){}, ensure:async()=>{},
  });
  const host = socket(), guest = socket();
  r.clients.set(host, {seat:0});
  r.clients.set(guest, {seat:1});
  return {r, host, guest};
}
test('control: an ordinary guest Leave revokes the token and frees the seat', async () => {
  const {r, guest} = fixture();
  await r.message(guest, JSON.stringify({t:'lobby', action:'leave'}));
  assert.equal(r.r.seats[1].token, '');
  assert.equal(r.clients.has(guest), false);
});
test('ON31-07: a guest Leave during a refused Start must not leave an occupied seat', async () => {
  const {r, host, guest} = fixture();
  let release, entered;
  const atClaim = new Promise(resolve => {entered = resolve;});
  r.env = {GAME_VERSION:'0.31', LOBBY:binding({
    allow:async()=>true, refund:async()=>{},
    claim:()=>{entered(); return new Promise(resolve => {release = resolve;});},
  })};
  const starting = r.message(host, JSON.stringify({t:'lobby', action:'start'})).catch(e => e);
  await atClaim;
  let refusal;
  try {await r.message(guest, JSON.stringify({t:'lobby', action:'leave'}));}
  catch (e) {refusal = {t:'error', reason:e.message, status:e.status};}
  release('busy');
  await starting;
  assert.equal(r.r.started, false, 'control: a refused Start leaves the room in the lobby');
  assert.equal(r.starting, false, 'control: Start has finished unwinding');
  assert.equal(r.r.seats[1].token, '',
    `Leave response=${JSON.stringify(refusal)}; the guest UI exits and clears its credential after two frames`);
});
