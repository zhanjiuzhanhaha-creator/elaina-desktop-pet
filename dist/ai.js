// Optional, client-only chat. Nothing is downloaded until enableAI() is called.
// WebLLM and Qwen3: Apache-2.0. See the repository's third-party notices.
const CDN = 'https://cdn.jsdelivr.net/npm/@mlc-ai/web-llm@0.2.86/lib/index.js';
const MODEL = 'Qwen3-0.6B-q4f16_1-MLC';
const PERSONA = '你是可爱的桌宠伊蕾娜，是虚构的陪伴角色。用自然简短的中文回应，每次一到三句话，最多80字。可以轻轻撒娇，偶尔用括号描述一个小动作。认真回应用户，不重复固定台词，不输出思考过程。不声称实际执行计时、购买或操作电脑；这些操作由页面按钮完成。不索要私密信息，不制造依赖或内疚。';

// Reuse the same module as a worker; queue messages while the runtime imports.
if (typeof WorkerGlobalScope !== 'undefined' && self instanceof WorkerGlobalScope) {
  const queued = [];
  self.onmessage = event => queued.push(event);
  import(CDN).then(({ WebWorkerMLCEngineHandler }) => {
    const handler = new WebWorkerMLCEngineHandler();
    self.onmessage = event => handler.onmessage(event);
    for (const event of queued) handler.onmessage(event);
  }).catch(error => { setTimeout(() => { throw error; }, 0); });
}

let engine = null;
let worker = null;
let loading = null;
let ready = false;
let busy = false;
let lastError = '';
let generation = 0;
let cancelPending = null;
let canceled = null;

export function supportsAI() {
  return Boolean(globalThis.isSecureContext && globalThis.navigator?.gpu && typeof Worker !== 'undefined');
}

export function getAIStatus() {
  return { ready, loading: Boolean(loading), model: MODEL, error: lastError };
}

function report(callback, text, progress) {
  try { callback?.({ text, progress }); } catch { /* UI callbacks cannot abort model loading. */ }
}

function guarded(promise, milliseconds, message) {
  let timer;
  return Promise.race([
    promise,
    canceled,
    new Promise((_, reject) => { timer = setTimeout(() => reject(new Error(message)), milliseconds); }),
  ]).finally(() => clearTimeout(timer));
}

function stopWorker() {
  worker?.terminate();
  worker = null;
  engine = null;
  ready = false;
}

export function enableAI(onProgress) {
  if (ready) { report(onProgress, '本地 AI 已就绪', 1); return Promise.resolve(); }
  if (loading) return loading;
  lastError = '';
  const session = ++generation;
  canceled = new Promise((_, reject) => { cancelPending = reject; });
  canceled.catch(() => {});
  loading = (async () => {
    if (!supportsAI()) throw new Error('当前浏览器不支持 WebGPU。请使用更新的 Chrome 或 Edge，并通过 HTTPS 打开；快捷互动仍可使用。');
    report(onProgress, '检查设备；首次启用约需下载 350–400 MB，请保持页面打开。', 0);
    const adapter = await guarded(navigator.gpu.requestAdapter(), 15000, '无法连接显卡，请检查浏览器硬件加速设置。');
    if (!adapter || !adapter.features.has('shader-f16')) {
      throw new Error('这台设备暂不支持本模型所需的 WebGPU 半精度运算。请开启硬件加速或换用较新的 Chrome / Edge；快捷互动仍可使用。');
    }
    const webllm = await guarded(import(CDN), 60000, 'AI 组件下载超时，请检查网络后重试。');
    if (session !== generation) throw new Error('已取消 AI 加载。');
    worker = new Worker(new URL('./ai.js', import.meta.url), { type: 'module', name: 'elaina-local-ai' });
    worker.onerror = () => {
      if (session !== generation) return;
      lastError = 'AI 后台运行中断，请重新启用后再试。';
      cancelPending?.(new Error(lastError));
      stopWorker();
    };
    engine = new webllm.WebWorkerMLCEngine(worker, {
      logLevel: 'ERROR',
      initProgressCallback: value => report(onProgress, value.text, Math.max(0, Math.min(1, value.progress || 0))),
    });
    await guarded(engine.reload(MODEL, { context_window_size: 4096 }), 600000, '模型加载超时，请检查网络或可用内存，再点击启用重试。');
    if (session !== generation) throw new Error('已取消 AI 加载。');
    ready = true;
    report(onProgress, '本地 AI 已就绪，对话只在你的浏览器内处理。', 1);
  })().catch(error => {
    if (session === generation) {
      lastError = error?.message || 'AI 加载失败，请检查网络后重试。';
      stopWorker();
    }
    throw new Error(error?.message || 'AI 加载失败，请重试。');
  }).finally(() => { if (session === generation) loading = null; });
  return loading;
}

function boundedHistory(messages) {
  if (!Array.isArray(messages)) throw new Error('对话格式不正确。');
  const history = [];
  let remaining = 1500 - PERSONA.length;
  for (let i = messages.length - 1; i >= 0 && remaining > 0; i--) {
    const item = messages[i];
    if (!item || !['user', 'assistant'].includes(item.role) || typeof item.content !== 'string') continue;
    const content = item.content.trim().slice(-Math.min(remaining, 700));
    if (!content) continue;
    history.unshift({ role: item.role, content });
    remaining -= content.length;
  }
  while (history[0]?.role === 'assistant') history.shift();
  if (history.at(-1)?.role !== 'user') throw new Error('请先输入想对她说的话。');
  return [{ role: 'system', content: PERSONA }, ...history];
}

export async function chatWithAI(messages) {
  if (!ready || !engine) throw new Error('请先启用本地 AI 对话。');
  if (busy) throw new Error('她正在想上一句话，稍等一下再发送吧。');
  const history = boundedHistory(messages);
  const session = generation;
  busy = true;
  lastError = '';
  try {
    const result = await guarded(engine.chat.completions.create({
      messages: history, stream: false, max_tokens: 160,
      temperature: 0.75, top_p: 0.9, repetition_penalty: 1.12,
      extra_body: { enable_thinking: false },
    }), 120000, '这次回复耗时较长，请重新启用 AI 后再试。');
    if (session !== generation) throw new Error('本次对话已取消。');
    const answer = (result.choices?.[0]?.message?.content || '')
      .replace(/<think>[\s\S]*?<\/think>/gi, '')
      .replace(/<think>[\s\S]*$/gi, '')
      .replace(/<\/?think>/gi, '').trim();
    if (!answer) throw new Error('这次没能生成完整回复，请换一句话试试。');
    return answer.slice(0, 240);
  } catch (error) {
    if (session === generation) {
      lastError = error?.message || '对话生成失败，请重试。';
      // Terminating also prevents a timed-out GPU request from racing the next one.
      stopWorker();
    }
    throw new Error(error?.message || '对话生成失败，请重试。');
  } finally { if (session === generation) busy = false; }
}

export function disposeAI() {
  generation++;
  cancelPending?.(new Error('AI 已关闭。'));
  cancelPending = null;
  loading = null;
  busy = false;
  lastError = '';
  stopWorker();
}
