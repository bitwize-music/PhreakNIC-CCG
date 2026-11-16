// Standalone hunt reproductions; excluded from the normal Worker test directory.
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const original = await readFile(new URL('../cloudflare/online/src/index.js', import.meta.url), 'utf8');
const source = original
  .replace("import { DurableObject } from 'cloudflare:workers';", 'class DurableObject {constructor(ctx,env){this.ctx=ctx;this.env=env;}}')
  .replace("'./lib/protocol.js'", JSON.stringify(new URL('../cloudflare/online/src/lib/protocol.js', import.meta.url).href))
  .replace("'./admin.js'", JSON.stringify(new URL('../cloudflare/online/src/admin.js', import.meta.url).href));
const {Room} = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
const makeRoom = () => Object.assign(Object.create(Room.prototype), {
  r: {code: 'AB23CD', created: Date.now(), version: '0.31', card_pool: '2026', started: false, over: false, host_seat: 0,
    seats: [{name:'Host', hero:'', token:'a'.repeat(32), bot:false, difficulty:0},
            {name:'Bot', hero:'', token:'', bot:true, difficulty:0},
            {name:'', hero:'', token:'', bot:false, difficulty:0}]},
  clients: new Map(), rates: new Map(), env: {GAME_VERSION:'0.31'},
  save: async () => {}, stat: async () => {}, broadcastRoom: () => {},
});
const joiner = {name:'Guest', hero:'', version:'0.31'};
test('control: ordinary join returns the occupied seat and its token', async () => {
  const r = makeRoom();
  const result = await r.join(joiner);
  assert.equal(result.seat, 2);
  assert.equal(r.r.seats[result.seat].token, result.token);
});
test('ON31-02: removing a lower seat during join must not leave an unreachable occupied seat', async () => {
  const r = makeRoom(), host = {send(){}, close(){}};
  r.clients.set(host, {seat:0});
  let release;
  const gate = new Promise(resolve => {release = resolve;});
  r.stat = async event => {if(event === 'join') await gate;};
  const pending = r.join(joiner);
  assert.equal(r.r.seats[2].name, 'Guest', 'control: join has reserved the open seat before its async write');
  await r.message(host, JSON.stringify({t:'lobby', action:'remove_seat', seat:1}));
  release();
  const result = await pending;
  const actual = r.r.seats.findIndex(s => s.name === 'Guest' && s.token);
  assert.ok(!result.failure ? result.seat === actual && result.token === r.r.seats[actual].token : actual === -1,
    `join response=${JSON.stringify(result)}, occupied guest seat=${actual}; failed joins must release their reservation`);
});
