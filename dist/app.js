const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];
const storageKey = 'elaina-room-v1';
const defaults = { nickname: '', affection: 0, stars: 0, rugs: ['blue'], rug: 'blue', reducedMotion: false };
let saved;
try { saved = JSON.parse(localStorage.getItem(storageKey) || '{}'); } catch { saved = {}; }
const state = { ...defaults, ...saved };
state.nickname = typeof state.nickname === 'string' ? state.nickname.slice(0, 16) : '';
state.affection = Math.max(0, Number(state.affection) || 0);
state.stars = Math.max(0, Number(state.stars) || 0);
state.rugs = Array.isArray(state.rugs) ? [...new Set(['blue', ...state.rugs.filter(x => ['blue', 'pink', 'violet'].includes(x))])] : ['blue'];
if (!state.rugs.includes(state.rug)) state.rug = 'blue';
function save() { try { localStorage.setItem(storageKey, JSON.stringify(state)); } catch { $('#chatMode').textContent = '浏览器未允许存储 · 当前体验仍可使用'; } }
function updateStats() {
  $('#affectionLabel').textContent = `♡ 亲密度 ${state.affection}`;
  $('#starsLabel').textContent = `${state.stars} 星`;
  $('#shopStars').textContent = state.stars;
  $('#rug').className = `rug ${state.rug}`;
  $$('.shop-item').forEach(button => {
    const id = button.dataset.rug, owned = state.rugs.includes(id);
    button.querySelector('b').textContent = state.rug === id ? '使用中' : owned ? '使用' : '解锁';
    button.querySelector('small').textContent = owned ? '已拥有 · 免费切换' : `${id === 'pink' ? 3 : 5} 星解锁`;
    button.setAttribute('aria-pressed', state.rug === id ? 'true' : 'false');
  });
}
updateStats();
document.body.classList.toggle('reduce-motion', !!state.reducedMotion);
$('#motionButton').setAttribute('aria-pressed', String(!!state.reducedMotion));
$('#motionButton').textContent = state.reducedMotion ? '恢复动态' : '减少动态';

const pet = $('#petArea'), root = $('#petRoot');
// Keep the current pose when an interaction interrupts another animation.
const handoff = document.createElement('div'); handoff.className = 'pose-handoff';
root.before(handoff); handoff.append(root);
let poseTransition;
let mode = 'idle', lockedUntil = 0, headHover = false, pointerInside = false, actionTimer, idleTimer;
let faceTimers = [], idleBag = [], lastIdle = '', lastAction = 'pat', lastAffectionTime = 0;
const pick = choices => choices[Math.floor(Math.random() * choices.length)];
const name = () => state.nickname || '你';
let speechTimer;
function speech(text) {
  clearTimeout(speechTimer); $('#speech').textContent = text.length > 40 ? `${text.slice(0,39)}…` : text;
  $('#speech').style.opacity = '1';
  speechTimer = setTimeout(() => { $('#speech').style.opacity = '0'; }, 6500);
}
function setFace(face) { $$('.face').forEach(image => image.classList.toggle('active', image.dataset.face === face)); }
function clearFaceTimers() { faceTimers.forEach(clearTimeout); faceTimers = []; }
function setMode(next) {
  const previousPose = new DOMMatrix(getComputedStyle(handoff).transform).multiply(new DOMMatrix(getComputedStyle(root).transform));
  mode = next;
  const form = ['click', 'hug'].includes(next) ? 'clickForm' : ['pat', 'hover', 'praise', 'tease'].includes(next) ? 'patForm' : 'normalForm';
  $$('.pet-form').forEach(element => element.classList.toggle('active', element.id === form));
  root.dataset.mode = next;
  const nextPose = new DOMMatrix(getComputedStyle(root).transform);
  const correction = previousPose.multiply(nextPose.inverse());
  poseTransition?.cancel();
  if (!state.reducedMotion && !matchMedia('(prefers-reduced-motion: reduce)').matches) {
    poseTransition = handoff.animate([{transform:correction.toString()},{transform:'matrix(1,0,0,1,0,0)'}],{duration:800,easing:'ease-in-out'});
  }
  $('#sleepMarks').classList.toggle('visible', next === 'sleep');
  setFace(next === 'sleep' ? 'blink' : next === 'smile' ? 'mouth' : 'idle');
  const statuses = {idle:'正在陪你发呆',glance:'偷偷看看你',smile:'想到你就有一点开心',sleep:'在你身边安心打盹',pat:'摸摸头…还想再多一点',hover:'看到你就很开心',click:'兔耳朵也藏不住开心',hug:'抱紧一点点',praise:'被夸得有一点害羞',tease:'哼，才没有被逗到呢'};
  $('#petStatus').textContent = statuses[next] || statuses.idle;
}
function blink(double = false) {
  clearFaceTimers();
  const frames = [[0,'half'],[170,'blink'],[400,'half'],[590,'idle']];
  if (double) frames.push([890,'half'],[1060,'blink'],[1270,'half'],[1470,'idle']);
  for (const [delay, face] of frames) faceTimers.push(setTimeout(() => { if (mode === 'idle' || mode === 'glance') setFace(face); }, delay));
}
function nextIdle() {
  clearTimeout(idleTimer);
  if (Date.now() < lockedUntil || pointerInside) { idleTimer = setTimeout(nextIdle, 600); return; }
  if (!idleBag.length) {
    idleBag = ['idle','glance','smile','double','sleep'];
    for (let i = idleBag.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [idleBag[i],idleBag[j]] = [idleBag[j],idleBag[i]]; }
    if (idleBag[0] === lastIdle) [idleBag[0],idleBag[1]] = [idleBag[1],idleBag[0]];
  }
  const selected = idleBag.shift(); lastIdle = selected; clearFaceTimers();
  setMode(selected === 'double' ? 'idle' : selected);
  if (selected === 'idle' || selected === 'double' || selected === 'glance') faceTimers.push(setTimeout(() => blink(selected === 'double'), 900));
  idleTimer = setTimeout(nextIdle, ['smile','sleep'].includes(selected) ? 5000 : 3000);
}
function returnToIdle() {
  lockedUntil = 0;
  if (pointerInside) setMode(headHover ? 'pat' : 'hover');
  else { setMode('idle'); clearTimeout(idleTimer); idleTimer = setTimeout(nextIdle, 2400); }
}
function animate(next, duration = 5000) {
  clearTimeout(actionTimer); clearFaceTimers();
  lockedUntil = Date.now() + duration;
  setMode(next);
  actionTimer = setTimeout(returnToIdle, duration);
}
function burst(count = 18) {
  if ($('#effects').childElementCount > 48) return;
  for (let i = 0; i < count; i++) {
    const particle = document.createElement('span'); particle.className = 'particle';
    particle.textContent = i % 4 ? '♥' : pick(['✦','✧','·']);
    const angle = (-175 + Math.random() * 170) * Math.PI / 180;
    const radius = 100 + Math.random() * 140;
    particle.style.setProperty('--dx', `${Math.cos(angle) * radius}px`);
    particle.style.setProperty('--dy', `${Math.sin(angle) * radius - 35}px`);
    particle.style.setProperty('--rot', `${Math.random() * 55 - 28}deg`);
    particle.style.setProperty('--scale', `${.7 + Math.random() * .6}`);
    particle.style.animationDelay = `${i * .055}s`;
    particle.style.color = pick(['#e690b2','#dcb96e','#a694ce','#9ac8d4']);
    $('#effects').append(particle); setTimeout(() => particle.remove(), 3300);
  }
}
function affection() {
  if (Date.now() - lastAffectionTime > 1000) { state.affection++; lastAffectionTime = Date.now(); save(); updateStats(); }
}
const history = [];
function addMessage(role, content, source = '互动') {
  const item = document.createElement('div'); item.className = `message ${role}`;
  const label = document.createElement('small'); label.textContent = role === 'user' ? (state.nickname || '你') : `伊蕾娜 · ${source}`;
  const body = document.createElement('p'); body.textContent = content;
  item.append(label, body); $('#messages').append(item);
  $('#messages').scrollTop = $('#messages').scrollHeight;
  if (role === 'assistant' || role === 'user') { history.push({role, content}); if (history.length > 24) history.splice(0, history.length - 24); }
  while ($('#messages').childElementCount > 80) $('#messages').firstElementChild.remove();
  return item;
}
function reply(text, source = '互动') { addMessage('assistant', text, source); speech(text.length > 65 ? `${text.slice(0,64)}…` : text); }
function interaction(action, showUser = true) {
  if (action === 'again') action = lastAction;
  else lastAction = action;
  const labels = {pat:'摸摸头',hug:'抱抱',praise:'你好可爱！',tease:'逗逗你～',rps:'我们来猜拳吧',sleep:'晚安'};
  if (showUser) addMessage('user', labels[action] || '再来一次');
  affection();
  switch (action) {
    case 'pat': animate('pat'); reply(pick([`唔…${name()}的手暖暖的。再摸一小会儿嘛。`,'呆毛都被摸弯啦…不过，我很喜欢。','欸嘿，今天的摸摸头额度可以再加一点吗？'])); break;
    case 'hug': animate('hug'); burst(26); reply(pick(['接住你啦！这次换我抱紧一点点。',`${name()}，今天辛苦啦。抱抱可以慢慢来。`,'把烦恼先放在旁边吧，抱抱的时候只要暖暖的。'])); break;
    case 'praise': animate('praise'); burst(13); reply(pick(['你这样夸我，兔耳朵都快藏不住啦。','那…今天也要把这句夸奖偷偷收藏起来。',`被${name()}喜欢的我，当然会有一点得意呀～`])); break;
    case 'tease': animate('tease'); reply(pick(['哼！再逗我就…就多陪我五分钟！','谁害羞啦？才、才没有呢。','被你发现我在偷看了。那你也要看看我呀。'])); break;
    case 'sleep': animate('sleep'); reply(`晚安，${name()}。借你的身边睡五秒钟…呼。`); break;
    case 'rps': animate('glance',3000); $('#rpsOptions').hidden = false; reply('石头、剪刀、布！你先悄悄选一个，我已经准备好啦。'); break;
  }
}
$('#quickActions').addEventListener('click', event => { const button = event.target.closest('[data-action]'); if (button) interaction(button.dataset.action); });
pet.addEventListener('pointermove', event => {
  if (event.pointerType === 'touch') return;
  pointerInside = true;
  const rect = pet.getBoundingClientRect(), x = event.clientX - rect.left, y = event.clientY - rect.top;
  headHover = y < rect.height * .52 && x > rect.width * .13 && x < rect.width * .88;
  pet.classList.toggle('petting', headHover);
  $('#paw').style.left = `${x}px`; $('#paw').style.top = `${y}px`;
  if (Date.now() >= lockedUntil && mode !== (headHover ? 'pat' : 'hover')) { clearFaceTimers(); setMode(headHover ? 'pat' : 'hover'); }
});
pet.addEventListener('pointerleave', () => { pointerInside = false; headHover = false; pet.classList.remove('petting'); if (Date.now() >= lockedUntil) returnToIdle(); });
function petClick() { animate('click'); burst(25); setTimeout(() => { if (mode === 'click') burst(12); },1500); affection(); speech(pick(['呀！耳朵也跟着开心起来了～','被你点到啦。要不要再抱抱？','今天的可爱，分给你一点点。'])); }
pet.addEventListener('click', petClick);
pet.addEventListener('keydown', event => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); petClick(); } });
$('#motionButton').addEventListener('click', () => {
  state.reducedMotion = !state.reducedMotion; save();
  document.body.classList.toggle('reduce-motion', state.reducedMotion);
  $('#motionButton').setAttribute('aria-pressed', String(state.reducedMotion));
  $('#motionButton').textContent = state.reducedMotion ? '恢复动态' : '减少动态';
});
function playRps(choice) {
  const options = ['石头','剪刀','布'], theirs = pick(options), beats = {'石头':'剪刀','剪刀':'布','布':'石头'};
  const result = choice === theirs ? '平局！好有默契呀，再来一次？' : beats[choice] === theirs ? '你赢啦！送你一颗小爱心～' : '嘿嘿，我赢啦。奖励我一个摸摸头好不好？';
  $('#rpsOptions').hidden = false; animate('click',3500); burst(12); affection();
  reply(`你出${choice}，我出${theirs}。${result}`);
}
$('#rpsOptions').addEventListener('click', event => { const button = event.target.closest('[data-choice]'); if (button) { addMessage('user',button.dataset.choice); playRps(button.dataset.choice); } });
function ruleReply(text) {
  const nickname = text.match(/^(?:请)?(?:以后)?(?:叫我|称呼我|喊我)[：:\s]*(.{1,16})[。！!]?$/u);
  if (nickname) { state.nickname = nickname[1].replace(/[。！!]$/u,'').trim(); save(); reply(`记住啦，${name()}。以后就这样轻轻叫你。`); return true; }
  if (/我叫什么|我的名字|我的称呼/.test(text)) { reply(state.nickname ? `当然记得，你是${state.nickname}呀。` : '还不知道你的小称呼呢。告诉我“叫我小星”，我就记住啦。'); return true; }
  if (/^(石头|剪刀|布)[！!。]?$/.test(text)) { playRps(text.replace(/[！!。]/g,'')); return true; }
  if (/再来|继续刚才|还要/.test(text)) { interaction('again',false); return true; }
  if (/摸摸|摸头|摸一下/.test(text)) { interaction('pat',false); return true; }
  if (/抱抱|抱一下|抱一抱|拥抱/.test(text)) { interaction('hug',false); return true; }
  if (/可爱|漂亮|好看|好棒|夸夸/.test(text)) { interaction('praise',false); return true; }
  if (/逗你|逗逗|笨蛋/.test(text)) { interaction('tease',false); return true; }
  if (/晚安|睡觉|打瞌睡/.test(text)) { interaction('sleep',false); return true; }
  if (/猜拳/.test(text)) { interaction('rps',false); return true; }
  if (/专注|番茄钟|一起学习/.test(text)) { $('#focusDialog').showModal(); reply('好呀。先选好时长，按“开始专注”，我就安静陪着你。'); return true; }
  if (/装扮|地毯|装饰|小窝/.test(text)) { $('#wardrobeDialog').showModal(); reply('给小窝换个颜色吧。完成专注就能攒到小星星。'); return true; }
  if (/^(你好|嗨|早上好|早安|下午好|晚上好|hello|hi)[呀啊～~！!。\s]*$/i.test(text)) { reply(`${name()}，你来啦～今天想聊聊天，还是先给我一个抱抱？`); animate('praise',3000); return true; }
  if (/谢谢|喜欢你|爱你/.test(text)) { reply(pick(['听到了，已经把这句话好好收在心里啦。','那我也把今天的一点温柔分给你。'])); animate('hug'); burst(18); affection(); return true; }
  return false;
}
let aiModule, aiReady = false, sending = false;
$('#enableAI').addEventListener('click', async () => {
  const button = $('#enableAI'); button.disabled = true;
  try {
    $('#aiStatus').textContent = '正在检查浏览器支持…';
    aiModule ??= await import('./ai.js');
    const support = await aiModule.supportsAI();
    if (support === false || (typeof support === 'object' && support && (support.supported === false || support.ok === false))) throw new Error(support?.reason || '此浏览器或显卡暂不支持 WebGPU。互动与常用短句仍然可用。');
    $('#aiProgress').hidden = false;
    await aiModule.enableAI(({text, progress}) => {
      $('#aiStatus').textContent = text || '正在准备本地模型…';
      if (Number.isFinite(progress)) $('#aiProgress').value = Math.max(0, Math.min(1, progress));
    });
    aiReady = true; $('#aiProgress').hidden = true;
    button.textContent = '本地 AI 已启用';
    $('#aiStatus').textContent = '模型在你的浏览器运行 · 对话不上传 · 速度取决于设备';
    $('#chatMode').textContent = '本地 AI + 动作互动';
    reply('准备好啦。除了抱抱和摸摸头，现在也可以慢慢聊聊你今天的事。','本地提示');
  } catch (error) {
    aiReady = false; button.disabled = false; button.textContent = '重新尝试启用 AI';
    $('#aiProgress').hidden = true;
    $('#aiStatus').textContent = `未启用：${String(error?.message || error).slice(0,220)}`;
  }
});
function localFallback(text) {
  if (/累|难过|烦|不开心|压力|焦虑/.test(text)) { animate('hug'); burst(10); return '辛苦啦。先在这里靠一会儿，想说就慢慢说。需要的话，给我发“抱抱”，我会接住你。'; }
  if (/你是谁|介绍|你会|功能|帮助/.test(text)) return '我是这里的小伊蕾娜呀。你可以摸摸头、抱抱、夸我、逗我、猜拳、说晚安，也可以和我一起专注。想聊更多的话，可以在下方启用本地 AI。';
  return pick(['我在听呀～现在是本地互动模式，可以试试“抱抱”“摸摸头”或“猜拳”。想自由聊聊，点下面的“启用本地 AI”就好。','先把这句话收下啦。当前我会回应常用互动短句；开启下面的本地 AI 后，就能和你聊更多啦。']);
}
$('#chatForm').addEventListener('submit', async event => {
  event.preventDefault(); const input = $('#chatInput'), text = input.value.trim();
  if (!text || sending) return;
  input.value = ''; addMessage('user',text);
  if (ruleReply(text)) return;
  if (!aiReady) { reply(localFallback(text),'本地互动'); return; }
  sending = true; $('#sendButton').disabled = true;
  const pending = document.createElement('div'); pending.className = 'message pending';
  const bubble = document.createElement('p'); bubble.textContent = '伊蕾娜正在想怎么回答…'; pending.append(bubble); $('#messages').append(pending); $('#messages').scrollTop = $('#messages').scrollHeight;
  try {
    const messages = history.slice(-16);
    const answer = await aiModule.chatWithAI(messages);
    pending.remove(); reply(String(answer || '唔，刚才有一点走神。再说一次好不好？').slice(0,1600),'本地 AI');
    if (!['sleep','click','hug','pat'].includes(mode) || Date.now() >= lockedUntil) animate('smile',5000);
  } catch (error) {
    pending.remove(); reply('这次本地模型没有成功回应。摸头、抱抱和其他互动仍然可以用。','本地提示');
    aiReady = !!aiModule.getAIStatus().ready;
    if (!aiReady) {
      $('#enableAI').disabled = false; $('#enableAI').textContent = '重新启用本地 AI';
      $('#chatMode').textContent = '本地互动 · AI 需要重新启用';
    }
    $('#aiStatus').textContent = `回复失败：${String(error?.message || error).slice(0,180)}`;
  } finally { sending = false; $('#sendButton').disabled = false; }
});
$('#chatInput').addEventListener('keydown', event => { if (event.key === 'Enter' && !event.shiftKey && !event.isComposing) { event.preventDefault(); $('#chatForm').requestSubmit(); } });

$('#nicknameOpen').addEventListener('click', () => { $('#nicknameInput').value = state.nickname; $('#nicknameDialog').showModal(); });
$('#nicknameClose').addEventListener('click', () => $('#nicknameDialog').close());
$('#nicknameForm').addEventListener('submit', event => { event.preventDefault(); state.nickname = $('#nicknameInput').value.trim().slice(0,16); save(); $('#nicknameDialog').close(); reply(state.nickname ? `记住啦，${state.nickname}。这个称呼很好听呢。` : '好，那我就先叫你“你”啦。想好小称呼再告诉我。'); });
$('#wardrobeOpen').addEventListener('click', () => { updateStats(); $('#wardrobeDialog').showModal(); });
$$('.shop-item').forEach(button => button.addEventListener('click', () => {
  const rug = button.dataset.rug, cost = rug === 'pink' ? 3 : rug === 'violet' ? 5 : 0;
  if (!state.rugs.includes(rug)) {
    if (state.stars < cost) { $('#shopNote').textContent = `还差 ${cost - state.stars} 星。一起完成一次专注，再回来看看吧。`; return; }
    state.stars -= cost; state.rugs.push(rug);
  }
  state.rug = rug; save(); updateStats();
  $('#shopNote').textContent = '换好啦。已拥有的软毯可以随时免费切换。';
}));
let focus = null;
const durationNormal = 25 * 60 * 1000, durationDemo = 25 * 1000;
function focusRemaining() { return focus ? Math.max(0, focus.remaining - (focus.paused ? 0 : Date.now() - focus.started)) : ($('#demoMode').checked ? durationDemo : durationNormal); }
function formatTime(ms) { const seconds = Math.ceil(ms / 1000); return `${Math.floor(seconds / 60).toString().padStart(2,'0')}:${(seconds % 60).toString().padStart(2,'0')}`; }
function updateFocus() {
  const remaining = focusRemaining(); $('#timerDisplay').textContent = formatTime(remaining);
  $('#focusMini').textContent = focus ? `${focus.paused ? '暂停 ' : ''}${formatTime(remaining)}` : '';
  $('#focusStart').disabled = !!focus; $('#focusPause').disabled = !focus; $('#focusEnd').disabled = !focus; $('#demoMode').disabled = !!focus;
  $('#focusPause').textContent = focus?.paused ? '继续' : '暂停';
  if (focus && remaining <= 0 && !focus.paused) finishFocus(true);
}
function finishFocus(completed) {
  if (!focus) return;
  const session = focus; const elapsed = session.duration - focusRemaining(); focus = null;
  const reward = completed ? (session.demo ? 1 : 5) : (!session.demo && elapsed >= 5 * 60 * 1000 ? 1 : 0);
  state.stars += reward; save(); updateStats(); updateFocus();
  $('#timerNote').textContent = completed ? `完成啦！收下 ${reward} 颗小星星。` : reward ? `这段努力也值得一颗星。已获得 ${reward} 星。` : '已经结束。下次准备好，再一起开始。';
  reply(completed ? `专注完成啦，${name()}！${reward} 颗星星送给努力的你。起来伸个懒腰吧。` : '好，先休息一会儿。我还在这里。');
  if (completed) { animate('click'); burst(24); }
}
$('#focusOpen').addEventListener('click', () => { updateFocus(); $('#focusDialog').showModal(); });
$('#demoMode').addEventListener('change', updateFocus);
$('#focusStart').addEventListener('click', () => {
  if (focus) return;
  const demo = $('#demoMode').checked, duration = demo ? durationDemo : durationNormal;
  focus = {demo,duration,remaining:duration,started:Date.now(),paused:false};
  $('#timerNote').textContent = demo ? '演示专注进行中，完成可获得 1 星。' : '慢慢来，一次只做一件事。';
  updateFocus(); speech('开始啦。我会在这里安静陪你。');
});
$('#focusPause').addEventListener('click', () => {
  if (!focus) return;
  if (!focus.paused) { focus.remaining = focusRemaining(); focus.paused = true; }
  else { focus.started = Date.now(); focus.paused = false; }
  $('#timerNote').textContent = focus.paused ? '暂停啦。准备好了再继续。' : '继续啦，我陪着你。'; updateFocus();
});
$('#focusEnd').addEventListener('click', () => finishFocus(false));
setInterval(updateFocus,250);
document.addEventListener('visibilitychange', () => { if (!document.hidden) updateFocus(); });
window.addEventListener('pagehide', () => { aiModule?.disposeAI?.(); aiReady = false; });
window.addEventListener('pageshow', event => { if (event.persisted && aiModule) { $('#enableAI').disabled = false; $('#enableAI').textContent = '重新启用本地 AI'; $('#chatMode').textContent = '本地互动 · AI 需要重新启用'; } });
reply(`你来啦${state.nickname ? `，${state.nickname}` : ''}。抱枕已经准备好了，要来坐一会儿吗？\n可以直接和我说“摸摸头”“抱抱”或“猜拳”。`);
speech('你来啦。今天也想被摸摸头呀～');
idleTimer = setTimeout(nextIdle,2800);
