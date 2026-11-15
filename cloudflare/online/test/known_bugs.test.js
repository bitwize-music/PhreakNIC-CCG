// Known online bugs, written as checks of the CORRECT behaviour: each B-numbered test fails while its bug is
// present and passes once it is fixed. `control:` tests pass today and show the harness drives the real code.
// Run: node --test cloudflare/online/test/known_bugs.test.js
// The real Worker, Room and Lobby classes run unmodified (loaded like runtime.test.js does). The Lobby keeps its
// rate limits and live-slot ledger in a real in-memory SQLite database (node:sqlite, Node 22.13+). Only the
// platform is faked: Durable Object storage, WebSocket pairs, and a container whose /link answers `ready`.
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {deflateSync} from 'node:zlib';
const source=(await readFile(new URL('../src/index.js',import.meta.url),'utf8')).replace("import { DurableObject } from 'cloudflare:workers';","class DurableObject {constructor(ctx,env){this.ctx=ctx;this.env=env;}} ").replace("'./lib/protocol.js'",JSON.stringify(new URL('../src/lib/protocol.js',import.meta.url).href)).replace("'./admin.js'",JSON.stringify(new URL('../src/admin.js',import.meta.url).href));
const {Room,Lobby,default:worker}=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
const {ALPHABET}=await import('../src/lib/protocol.js');
const sqlite=await import('node:sqlite').catch(()=>null);
const needs=sqlite?{}:{skip:'node:sqlite (Node 22.13+) is needed to run the real Lobby'};
const sleep=ms=>new Promise(r=>setTimeout(r,ms));

// ---- platform fakes -------------------------------------------------------------------------------------
const OriginalResponse=globalThis.Response;
class UpgradeResponse extends OriginalResponse {constructor(body,init){if(init?.status===101){super(null);Object.defineProperty(this,'status',{value:101});this.webSocket=init.webSocket;}else super(body,init);}}
let lastPair=null;
const socket=()=>({readyState:1,sent:[],closed:null,listeners:{},accept(){},addEventListener(type,fn){(this.listeners[type]??=[]).push(fn);},send(v){this.sent.push(JSON.parse(v));},close(code,reason){this.closed={code,reason};this.readyState=3;},emit(type,event){for(const fn of this.listeners[type]??[])fn(event);}});
class Pair {constructor(){this[0]=socket();this[1]=socket();lastPair=this;}}
// Swap in the WebSocket fakes for one test only, as runtime.test.js does.
// The Room's container progress lines (console.log) are muted; console.error stays visible.
async function sandbox(fn){const saved=[globalThis.Response,globalThis.WebSocketPair,console.log];globalThis.Response=UpgradeResponse;globalThis.WebSocketPair=Pair;console.log=()=>{};try{return await fn();}finally{[globalThis.Response,globalThis.WebSocketPair,console.log]=saved;}}

function makeEnv({version='0.27',latency=0}={}) {
 const env={GAME_VERSION:version,ONLINE_ENABLED:'1',linkLog:[],links:[],pending:[],rooms:new Map(),meta:new Map()};
 const db=new sqlite.DatabaseSync(':memory:');
 env.lobby=new Lobby({storage:{sql:{exec:(query,...params)=>db.prepare(query).all(...params)}}},env);
 // Every Lobby call crosses an async boundary, like a Durable Object RPC.
 const stub=new Proxy({},{get:(_,name)=>async(...args)=>{if(latency)await sleep(latency);const value=env.lobby[name](...args);if(latency)await sleep(latency);return value;}});
 env.LOBBY={idFromName:x=>x,get:()=>stub};
 // Like blockConcurrencyWhile, no call reaches a Room before its constructor has loaded storage.
 env.ROOMS={idFromName:x=>x,get:code=>{if(!env.rooms.has(code))boot(env,code);const room=env.rooms.get(code);return new Proxy(room,{get:(target,name)=>typeof target[name]==='function'?async(...args)=>{await env.meta.get(code).ready;return target[name](...args);}:target[name]});}};
 return env;
}
// Start (or restart, keeping storage) the Room Durable Object for a code.
function boot(env,code) {
 const meta=env.meta.get(code)??{store:new Map()};env.meta.set(code,meta);
 const store=meta.store;
 meta.container={running:false,starts:0,images:{base:'image'},async start(){this.running=true;this.starts++;},async destroy(){this.running=false;},setInactivityTimeout(){},monitor(){return new Promise(()=>{});},
  getTcpPort(){return {fetch:async request=>{
   if(new URL(request.url).pathname==='/health')return new OriginalResponse('ok');
   const link=socket();link.send=v=>env.linkLog.push({code,...JSON.parse(v)});
   link.accept=()=>setTimeout(()=>link.emit('message',{data:JSON.stringify({t:'ready'})}),0);
   env.links.push({code,link});return {webSocket:link};}};}};
 const ctx={storage:{get:async k=>store.has(k)?structuredClone(store.get(k)):undefined,put:async(k,v)=>{store.set(k,structuredClone(v));},setAlarm:async()=>{},deleteAll:async()=>store.clear()},
  container:meta.container,waitUntil:p=>env.pending.push(p),blockConcurrencyWhile:fn=>(meta.ready=fn())};
 env.rooms.set(code,new Room(ctx,env));
}
async function http(env,method,path,body,ip='198.51.100.1') {
 const res=await worker.fetch(new Request('https://online.test'+path,{method,headers:{'CF-Connecting-IP':ip,'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body)}),env);
 let data={};try{data=await res.json();}catch{}
 return {status:res.status,data};
}
// The returned object is the Room's end of the player's socket: `sent` holds what the player receives.
async function connect(env,code,token,ip='198.51.100.1') {
 lastPair=null;
 const res=await worker.fetch(new Request(`https://online.test/ws/room/${code}?token=${token}`,{headers:{Upgrade:'websocket','CF-Connecting-IP':ip}}),env);
 return res.status===101?lastPair[1]:Object.assign(socket(),{refused:res.status});
}
const say=(player,message)=>player.emit('message',{data:JSON.stringify(message)});
async function until(predicate,ms=3000){const end=Date.now()+ms;while(Date.now()<end){if(predicate())return true;await sleep(2);}return predicate();}
async function idle(env,code){const room=env.rooms.get(code);await until(()=>!room.starting&&!room.boot&&!room.stopping);await sleep(5);}
const human={bot:false,difficulty:0},bot={bot:true,difficulty:1};
const ident=(env,name)=>({name,hero:'',version:env.GAME_VERSION,platform:'linux'});
async function create(env,seats,{card_pool='2026',ip='198.51.100.1',name='Host'}={}) {
 const res=await http(env,'POST','/rooms',{...ident(env,name),public:false,card_pool,starting_life:0,seats},ip);
 assert.equal(res.status,201,'room creation failed: '+JSON.stringify(res.data));return res.data;
}
async function join(env,code,name,ip) {const res=await http(env,'POST',`/rooms/${code}/join`,ident(env,name),ip);assert.equal(res.status,200,'join failed: '+JSON.stringify(res.data));return res.data;}
const rooms=player=>player.sent.filter(m=>m.t==='room');
const errors=player=>player.sent.filter(m=>m.t==='error');
const live=env=>[...env.lobby.sql.exec('SELECT code FROM live')].map(r=>r.code);
function deck(name){const cards={};for(let i=0;i<15;i++)cards['card'+i]=4;return 'PNDK1.'+deflateSync(Buffer.from(JSON.stringify({name,cards}))).toString('base64url');}
// Create, connect and start a room; resolves once the start was answered.
async function startRoom(env,seats,ip) {
 const room=await create(env,seats,{ip});const host=await connect(env,room.code,room.token,ip);
 say(host,{t:'lobby',action:'start'});
 await until(()=>errors(host).length>0||env.linkLog.some(m=>m.code===room.code&&m.t==='setup'));await idle(env,room.code);
 return {...room,host};
}
// A custom room with two humans who both submitted a deck.
async function customLobby(env) {
 const room=await create(env,[human,human],{card_pool:'custom'});const guest=await join(env,room.code,'Bob','203.0.113.2');
 const host=await connect(env,room.code,room.token),bob=await connect(env,room.code,guest.token,'203.0.113.2');
 say(host,{t:'lobby',action:'submit_deck',code:deck('Host deck')});say(bob,{t:'lobby',action:'submit_deck',code:deck('Bob deck')});
 await until(()=>rooms(bob).at(-1)?.seats.every(s=>s.deck));
 return {code:room.code,host,bob};
}

// ---- B02 ------------------------------------------------------------------------------------------------
async function finishedWhileBobAway(env) {
 const room=await create(env,[human,human]);const guest=await join(env,room.code,'Bob','203.0.113.2');
 const host=await connect(env,room.code,room.token),bob=await connect(env,room.code,guest.token,'203.0.113.2');
 say(host,{t:'lobby',action:'start'});
 await until(()=>env.linkLog.some(m=>m.code===room.code&&m.t==='connect'));await idle(env,room.code);
 bob.emit('close',{});await until(()=>!env.rooms.get(room.code).connected(1));
 // The container reports the result over the trusted link, as link_server.gd does.
 env.links.at(-1).link.emit('message',{data:JSON.stringify({t:'over',winner:0,turns:9})});
 await until(()=>host.sent.some(m=>m.t==='over'));await idle(env,room.code);
 return {room,guest,host};
}
test('B02 reconnecting player is told the game is over',needs,()=>sandbox(async()=>{
 const env=makeEnv(),{room,guest}=await finishedWhileBobAway(env);
 const again=await connect(env,room.code,guest.token,'203.0.113.2');await sleep(20);
 // Either an `over` message or a room message carrying over:true lets the client finish (online_session.gd:82-83).
 assert(again.sent.some(m=>m.t==='over'||(m.t==='room'&&m.over===true)),'B02 reconnecting player is told the game is over; upgrade '+(again.refused??101)+', received: '+JSON.stringify(again.sent));
}));
test('control: a player connected when the game ends receives over',needs,()=>sandbox(async()=>{
 const {host}=await finishedWhileBobAway(makeEnv());
 assert.deepEqual(host.sent.filter(m=>m.t==='over'),[{t:'over',winner:0}]);
}));

// ---- B16 ------------------------------------------------------------------------------------------------
test('B16 one address starting 20 one-human games does not take every live slot',needs,()=>sandbox(async()=>{
 const env=makeEnv(),hog='198.51.100.66';
 for(let i=0;i<20;i++)await startRoom(env,[human,bot,bot,bot],hog);
 const other=await startRoom(env,[human,bot],'203.0.113.77');
 // How many live games one address may hold is a policy choice; this only asserts it is not all of them.
 assert(env.rooms.get(other.code).r.started&&!errors(other.host).length,'B16 another address can still start a game after one address started 20; it got '+JSON.stringify(errors(other.host))+', live slots held by the first address: '+live(env).length);
}));

// ---- B21 ------------------------------------------------------------------------------------------------
test('B21 a player renumbered by Remove seat can learn the seat that is now theirs',needs,()=>sandbox(async()=>{
 const env=makeEnv(),room=await create(env,[human,human,bot,human]);
 const ann=await join(env,room.code,'Ann','203.0.113.2'),bob=await join(env,room.code,'Bob','203.0.113.3');
 assert.deepEqual([ann.seat,bob.seat],[1,3]);
 const host=await connect(env,room.code,room.token),a=await connect(env,room.code,ann.token,'203.0.113.2'),b=await connect(env,room.code,bob.token,'203.0.113.3');
 a.sent.length=0;b.sent.length=0;
 say(host,{t:'lobby',action:'remove_seat',seat:2});
 await until(()=>a.sent.length&&b.sent.length);await sleep(10);
 const now=env.rooms.get(room.code).clients.get(b)?.seat,view=p=>JSON.stringify({sent:p.sent,closed:p.closed});
 // Least prescriptive: either Bob keeps the index his client stored from the join reply, or the Worker tells
 // him something it doesn't tell Ann, whose index didn't change (e.g. his new seat). Today both get the same broadcast.
 assert(now===bob.seat||view(b)!==view(a),`B21 a player renumbered by Remove seat can learn the seat that is now theirs; server seat ${now}, client stored ${bob.seat}, and Bob received exactly what Ann did: ${view(b)}`);
}));

// ---- B22 ------------------------------------------------------------------------------------------------
async function lobbyAcrossDeploy(env,deployTo) {
 const room=await create(env,[human,bot]);
 if(deployTo){env.GAME_VERSION=deployTo;boot(env,room.code);}// the deploy restarts the Room object from storage
 const host=await connect(env,room.code,room.token);
 if(!host.refused){say(host,{t:'lobby',action:'start'});await until(()=>errors(host).length>0||env.linkLog.some(m=>m.code===room.code&&m.t==='setup'));}
 await idle(env,room.code);
 return {room,host};
}
test('B22 Start does not boot a 0.26 lobby on a 0.27 deployment',needs,()=>sandbox(async()=>{
 const env=makeEnv({version:'0.26'}),{room,host}=await lobbyAcrossDeploy(env,'0.27');
 // The new container refuses every connect carrying the room's 0.26 version (link_server.gd:225), so the start
 // must be refused (with any reason) instead of holding a live slot and a container.
 assert(!live(env).includes(room.code)&&!env.meta.get(room.code).container.running,'B22 Start does not boot a 0.26 lobby on a 0.27 deployment; live slot held: '+live(env).includes(room.code)+', link got '+JSON.stringify(env.linkLog.filter(m=>m.t==='connect'))+', host got '+JSON.stringify(host.sent.map(m=>m.t+(m.reason?'('+m.reason+')':''))));
}));
test('control: Start without a deploy claims a live slot and boots the container',needs,()=>sandbox(async()=>{
 const env=makeEnv({version:'0.26'}),{room}=await lobbyAcrossDeploy(env,null);
 assert(live(env).includes(room.code)&&env.meta.get(room.code).container.running);
 assert.deepEqual(env.linkLog.filter(m=>m.t==='connect').map(m=>m.version),['0.26']);
}));

// ---- B44 ------------------------------------------------------------------------------------------------
// Any refusal from the Lobby claim (index.js:214) takes this path; maintenance mode is used because it is a
// refusal that doesn't depend on the live-game cap policy.
async function refusedCustomStart(env) {
 const lobby=await customLobby(env);
 env.ONLINE_ENABLED='0';say(lobby.host,{t:'lobby',action:'start'});
 await until(()=>errors(lobby.host).length>0);await idle(env,lobby.code);env.ONLINE_ENABLED='1';
 assert(!env.rooms.get(lobby.code).r.started,'setup: the start should have been refused');
 return lobby;
}
test('B44 a refused start leaves no deck roll in the lobby',needs,()=>sandbox(async()=>{
 const env=makeEnv(),{bob}=await refusedCustomStart(env);
 const before=rooms(bob).length;say(bob,{t:'lobby',action:'withdraw_deck'});await until(()=>rooms(bob).length>before);
 assert.deepEqual(rooms(bob).at(-1).deck_roll??[],[],'B44 a refused start leaves no deck roll in the lobby');
}));
test('B44 a later standard-set game does not open with the stale deck roll',needs,()=>sandbox(async()=>{
 const env=makeEnv(),{code,host,bob}=await refusedCustomStart(env);
 say(host,{t:'lobby',action:'settings',card_pool:'2026'});await until(()=>rooms(bob).at(-1).card_pool==='2026');
 say(host,{t:'lobby',action:'start'});await until(()=>rooms(bob).some(m=>m.started));await idle(env,code);
 // table.gd:2134-2135 shows the start broadcast's deck_roll as a notice when the table opens.
 assert.deepEqual(rooms(bob).find(m=>m.started).deck_roll??[],[],'B44 a later standard-set game does not open with the stale deck roll');
}));
test('B44 after every submitted deck was invalid, a standard-set game does not open with the deck roll',needs,()=>sandbox(async()=>{
 const env=makeEnv(),{code,host,bob}=await customLobby(env);
 say(host,{t:'lobby',action:'start'});
 for(const attempt of [0,1]){
  await until(()=>env.linkLog.some(m=>m.t==='setup'&&m.attempt===attempt));
  env.links.at(-1).link.emit('message',{data:JSON.stringify({t:'setup_error',attempt,reason:'invalid'})});
 }
 await until(()=>errors(host).some(m=>m.reason.startsWith('No valid submitted decks')));await idle(env,code);
 say(host,{t:'lobby',action:'settings',card_pool:'2026'});await until(()=>rooms(bob).at(-1).card_pool==='2026');
 const before=rooms(bob).length;say(host,{t:'lobby',action:'start'});await until(()=>rooms(bob).slice(before).some(m=>m.started));await idle(env,code);
 assert.deepEqual(rooms(bob).slice(before).find(m=>m.started).deck_roll??[],[],'B44 after every submitted deck was invalid, a standard-set game does not open with the deck roll');
}));

// ---- B45 ------------------------------------------------------------------------------------------------
async function tapStart(times) {
 const env=makeEnv({latency:5}),room=await create(env,[human,bot]),host=await connect(env,room.code,room.token);
 for(let i=0;i<times;i++)say(host,{t:'lobby',action:'start'});
 await until(()=>env.linkLog.some(m=>m.t==='setup'));await idle(env,room.code);
 assert(env.rooms.get(room.code).r.started,'setup: the first Start should start the game');
 return host;
}
test('B45 a second Start while the first is starting is not reported as busy',needs,()=>sandbox(async()=>{
 const host=await tapStart(2);
 // `busy` is what the client shows as "The servers are full right now…" (online_api.gd:40). A duplicate Start
 // may be ignored or answered differently, just not as busy while the game is starting.
 assert.deepEqual(errors(host).filter(m=>m.reason==='busy'),[],'B45 a second Start while the first is starting is not reported as busy');
}));
test('control: a single Start starts the game with no error',needs,()=>sandbox(async()=>{
 assert.deepEqual(errors(await tapStart(1)),[]);
}));

// ---- B47 ------------------------------------------------------------------------------------------------
async function guessCodes(env,ip) {
 const room=await create(env,[human,human]);let misses=0;
 for(let i=0;misses<300;i++){const guess=ALPHABET[i%31]+ALPHABET[Math.floor(i/31)%31]+'ZZ';if(guess===room.code)continue;const res=await http(env,'POST',`/rooms/${guess}/join`,ident(env,'Guess'),ip);assert.equal(res.status,404);misses++;}
 return room;
}
test('B47 a neighbour in the same IPv6 /64 shares the failed-join limit',needs,()=>sandbox(async()=>{
 const env=makeEnv(),room=await guessCodes(env,'2001:db8:1:2::1');
 const res=await http(env,'POST',`/rooms/${room.code}/join`,ident(env,'Guess'),'2001:db8:1:2::2');
 // Treating a /64 (one subscriber or LAN) as one address is a policy choice; it matches how the con's shared
 // IPv4 address is already treated. Today the neighbour joins and claims the open seat.
 assert.equal(res.status,429,'B47 a neighbour in the same IPv6 /64 shares the failed-join limit; got '+res.status+' '+JSON.stringify(res.data));
}));
test('control: 300 failed joins lock that address out of joining',needs,()=>sandbox(async()=>{
 const env=makeEnv(),room=await guessCodes(env,'2001:db8:1:2::1');
 const res=await http(env,'POST',`/rooms/${room.code}/join`,ident(env,'Guess'),'2001:db8:1:2::1');
 assert.deepEqual([res.status,res.data.error],[429,'rate_limit']);
}));
