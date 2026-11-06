// MEGAN AI relay: Cloudflare Worker that keeps your API key secret.
// Setup: Workers & Pages > Create Worker > paste this > Settings > Variables and Secrets:
//   add a SECRET named ANTHROPIC_API_KEY (your key from console.anthropic.com)
//   (optional) add a variable MODEL, default is claude-haiku-5-5 (fast and cheap)
const ALLOWED = ['https://morgankat.github.io'];

export default {
  async fetch(req, env) {
    const origin = req.headers.get('Origin') || '';
    const okOrigin = ALLOWED.includes(origin);
    const cors = {
      'Access-Control-Allow-Origin': okOrigin ? origin : ALLOWED[0],
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
      'Vary': 'Origin'
    };
    const json = (obj, status) => new Response(JSON.stringify(obj), { status: status || 200, headers: { ...cors, 'Content-Type': 'application/json' } });
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
    if (req.method !== 'POST' || !okOrigin) return json({ error: 'not allowed' }, 403);
    try {
      const { systemPrompt, userPrompt, history } = await req.json();
      const msgs = [];
      for (const m of (history || []).slice(-20)) {
        const role = m.role === 'assistant' ? 'assistant' : 'user';
        const text = String(m.content || m.text || '');
        if (!text) continue;
        if (msgs.length && msgs[msgs.length - 1].role === role) msgs[msgs.length - 1].content += '\n' + text;
        else msgs.push({ role, content: text });
      }
      while (msgs.length && msgs[0].role !== 'user') msgs.shift();
      if (msgs.length && msgs[msgs.length - 1].role === 'user') msgs[msgs.length - 1].content += '\n\n' + String(userPrompt || '');
      else msgs.push({ role: 'user', content: String(userPrompt || '') });
      const r = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: { 'x-api-key': env.ANTHROPIC_API_KEY, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
        body: JSON.stringify({ model: env.MODEL || 'claude-haiku-5-5', max_tokens: 600, system: String(systemPrompt || ''), messages: msgs })
      });
      const data = await r.json();
      if (!r.ok) return json({ error: (data.error && data.error.message) || ('upstream ' + r.status) }, 502);
      const text = (data.content || []).filter(b => b.type === 'text').map(b => b.text).join('');
      return json({ choices: [{ message: { content: text } }] });
    } catch (e) {
      return json({ error: String((e && e.message) || e) }, 500);
    }
  }
};
