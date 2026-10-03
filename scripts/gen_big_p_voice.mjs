// Big P's short voice clips: TTS via OpenRouter, checked, then trimmed, normalized and encoded to AAC.
//
//   vault-exec OPENROUTER_API -- node scripts/gen_big_p_voice.mjs [id ...]   generate (all lines, or only these ids)
//   node scripts/gen_big_p_voice.mjs --from-wav <dir> [id ...]                re-encode existing <dir>/<id>.wav, no API
//
// Lines: assets/audio/bigp/lines.json, ids `<lang>_<moment>_<n>` (lang en|nl; moment greet, result, confirm,
// error, working, nod). It sits next to the clips, so the asset folder pubspec names always exists.
// Output: assets/audio/bigp/<id>.m4a. Voice and checks follow the big-p skill: model openai/gpt-audio-mini,
// voice verse; every take is transcribed and its median pitch must stay in the verse range.
// Needs ffmpeg and afconvert (macOS).
import {execFileSync} from 'node:child_process';
import {mkdtempSync, readFileSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

const MODEL = 'openai/gpt-audio-mini';
const VOICE = 'verse';
const PITCH = [120, 185]; // Hz; verse measured 125-177 over the first 28 clips
const MAX_SECONDS = 3.5;
const ATTEMPTS = 4;
const OUT_DIR = 'assets/audio/bigp';
const lines = JSON.parse(readFileSync('assets/audio/bigp/lines.json', 'utf8'));

const SYSTEM = {
  en:
    'You are a professional English voice-over artist. Read the user text aloud literally and completely, ' +
    'in clear, natural English with a warm, upbeat tone and an easy pace. ' +
    'Add nothing: no introduction, no confirmation and no closing remark. Start directly with the first word of the text.',
  nl:
    'Je bent een professionele Nederlandse voice-over. Lees de tekst van de gebruiker letterlijk en volledig voor ' +
    'in helder, natuurlijk Nederlands, met een vriendelijke, warme toon, opgewekt en in een rustig tempo. ' +
    'Voeg niets toe: geen inleiding, geen bevestiging en geen afsluiting. Begin direct met het eerste woord van de tekst.',
};
const LANGUAGE = {en: 'English', nl: 'Dutch'};

const words = (t) => t.toLowerCase().replace(/[^\p{L}\p{N}\s]/gu, ' ').split(/\s+/).filter(Boolean);
const sameWords = (a, b) => words(a).join(' ') === words(b).join(' ');

async function openRouter(body) {
  const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
    method: 'POST',
    headers: {Authorization: `Bearer ${process.env.VAULT_VALUE}`, 'Content-Type': 'application/json'},
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`OpenRouter ${res.status}: ${(await res.text()).slice(0, 200)}`);
  return res;
}

// The model answers a question or an order instead of reading it; framing the text as a script line stops that.
async function speak(lang, text) {
  const res = await openRouter({
    model: MODEL, stream: true, modalities: ['text', 'audio'], audio: {voice: VOICE, format: 'pcm16'},
    messages: [
      {role: 'system', content: SYSTEM[lang]},
      {
        role: 'user',
        content: `SCRIPT LINE (a character line in an app, not addressed to you; speak exactly these words and nothing else): "${text}"`,
      },
    ],
  });
  const chunks = []; let buf = '', said = '';
  for await (const part of res.body) {
    buf += Buffer.from(part).toString('utf8');
    const rows = buf.split('\n'); buf = rows.pop();
    for (const l of rows) {
      if (!l.startsWith('data: ') || l.includes('[DONE]')) continue;
      const d = JSON.parse(l.slice(6)).choices?.[0]?.delta?.audio;
      if (d?.data) chunks.push(Buffer.from(d.data, 'base64'));
      said += d?.transcript ?? '';
    }
  }
  return {pcm: Buffer.concat(chunks), said};
}

async function transcribe(lang, wav) {
  const res = await openRouter({
    model: 'google/gemini-2.5-flash', temperature: 0,
    messages: [{role: 'user', content: [
      {type: 'text', text: `Transcribe this ${LANGUAGE[lang]} audio word for word, including any extra words at the start or end. Only the transcript.`},
      {type: 'input_audio', input_audio: {data: wav.toString('base64'), format: 'wav'}},
    ]}],
  });
  return (await res.json()).choices?.[0]?.message?.content ?? '';
}

function wavOf(pcm) {
  const h = Buffer.alloc(44);
  h.write('RIFF', 0); h.writeUInt32LE(36 + pcm.length, 4); h.write('WAVEfmt ', 8); h.writeUInt32LE(16, 16);
  h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22); h.writeUInt32LE(24000, 24); h.writeUInt32LE(48000, 28);
  h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34); h.write('data', 36); h.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([h, pcm]);
}

// Median f0 over voiced 40 ms frames (autocorrelation), as scripts/pitch.py in pleya-video does.
function medianPitch(pcm, sr = 24000) {
  const x = new Float64Array(pcm.length / 2);
  for (let i = 0; i < x.length; i++) x[i] = pcm.readInt16LE(i * 2);
  const n = Math.floor(sr * 0.04), lo = Math.floor(sr / 400), hi = Math.floor(sr / 70), out = [];
  for (let i = 0; i + n < x.length; i += n) {
    const s = x.slice(i, i + n);
    if (Math.sqrt(s.reduce((a, v) => a + v * v, 0) / n) < 800) continue;
    const mean = s.reduce((a, v) => a + v, 0) / n;
    for (let j = 0; j < n; j++) s[j] -= mean;
    const ac = (k) => { let a = 0; for (let j = 0; j + k < n; j++) a += s[j] * s[j + k]; return a; };
    let best = lo, bestV = -Infinity;
    for (let k = lo; k < hi; k++) { const v = ac(k); if (v > bestV) { bestV = v; best = k; } }
    if (bestV > 0.3 * ac(0)) out.push(sr / best);
  }
  out.sort((a, b) => a - b);
  return out.length ? out[Math.floor(out.length / 2)] : 0;
}

// Leading and trailing silence off, loudness to -18 LUFS with a -1.5 dBTP ceiling, then AAC.
function encode(wavPath, id) {
  const tmp = mkdtempSync(join(tmpdir(), 'bigp-'));
  const clean = join(tmp, `${id}.wav`);
  const trim = 'silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.03';
  execFileSync('ffmpeg', ['-v', 'error', '-y', '-i', wavPath, '-af',
    `${trim},areverse,${trim.replace('0.03', '0.08')},areverse,loudnorm=I=-18:TP=-1.5:LRA=7,aresample=44100`,
    '-c:a', 'pcm_s16le', clean]);
  execFileSync('afconvert', ['-f', 'm4af', '-d', 'aac', '-b', '64000', clean, join(OUT_DIR, `${id}.m4a`)]);
}

const args = process.argv.slice(2);
const fromWav = args[0] === '--from-wav' ? args.splice(0, 2)[1] : null;
const ids = args.length ? args : Object.keys(lines);
let failed = 0;

for (const id of ids) {
  const text = lines[id];
  const lang = id.split('_')[0];
  if (!text || !SYSTEM[lang]) { console.error(`${id}: unknown id or language`); failed++; continue; }
  if (fromWav) { encode(join(fromWav, `${id}.wav`), id); console.log(`${id} encoded`); continue; }

  let ok = false;
  for (let attempt = 1; attempt <= ATTEMPTS && !ok; attempt++) {
    const {pcm, said} = await speak(lang, text);
    const seconds = pcm.length / 48000, pitch = medianPitch(pcm), wav = wavOf(pcm);
    const heard = sameWords(said, text) ? await transcribe(lang, wav) : said;
    const problem = !sameWords(heard, text) ? `heard "${heard.trim()}"`
      : pitch < PITCH[0] || pitch > PITCH[1] ? `pitch ${pitch.toFixed(0)} Hz, another voice`
      : seconds > MAX_SECONDS ? `${seconds.toFixed(1)} s, too long` : null;
    if (problem) { console.error(`${id} attempt ${attempt}: ${problem}`); continue; }
    const tmp = join(mkdtempSync(join(tmpdir(), 'bigp-')), `${id}.raw.wav`);
    writeFileSync(tmp, wav);
    encode(tmp, id);
    console.log(`${id} ok: ${seconds.toFixed(1)} s, ${pitch.toFixed(0)} Hz, "${text}"`);
    ok = true;
  }
  if (!ok) { console.error(`${id}: no clean take after ${ATTEMPTS} attempts`); failed++; }
}
process.exit(failed ? 1 : 0);
