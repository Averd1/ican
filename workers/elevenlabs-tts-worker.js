const VOICE_ENV = {
  default: 'ELEVENLABS_VOICE_DEFAULT',
  calm: 'ELEVENLABS_VOICE_CALM',
  fast: 'ELEVENLABS_VOICE_FAST',
};

const WINDOW_MS = 60_000;
const MAX_REQUESTS = 30;
const requestLog = new Map();

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname !== '/tts' || request.method !== 'POST') {
      return jsonError('not_found', 'Use POST /tts.', false, 404);
    }
    if (!env.ELEVENLABS_API_KEY) {
      return jsonError('server_config', 'TTS service is not configured.', false, 500);
    }

    const ip =
      request.headers.get('CF-Connecting-IP') ||
      request.headers.get('X-Forwarded-For') ||
      'unknown';
    if (!allowRequest(ip)) {
      return jsonError('rate_limited', 'Too many TTS requests.', true, 429);
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return jsonError('bad_json', 'Request body must be JSON.', false, 400);
    }

    const text = typeof body.text === 'string' ? body.text.trim() : '';
    const voice = typeof body.voice === 'string' ? body.voice : 'default';
    const format = typeof body.format === 'string' ? body.format : 'mp3';
    if (!text || text.length > 1200) {
      return jsonError('bad_text', 'Text must be 1 to 1200 characters.', false, 400);
    }
    if (!['default', 'calm', 'fast'].includes(voice) || format !== 'mp3') {
      return jsonError('bad_request', 'Unsupported voice or format.', false, 400);
    }

    const voiceId = env[VOICE_ENV[voice]] || env.ELEVENLABS_VOICE_DEFAULT;
    if (!voiceId) {
      return jsonError('server_config', 'No ElevenLabs voice is configured.', false, 500);
    }

    const elevenUrl =
      `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}` +
      '?output_format=mp3_44100_128';
    const upstream = await fetch(elevenUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'audio/mpeg',
        'xi-api-key': env.ELEVENLABS_API_KEY,
      },
      body: JSON.stringify({
        text,
        model_id: env.ELEVENLABS_MODEL_ID || 'eleven_multilingual_v2',
        voice_settings: voiceSettings(voice),
      }),
    });

    if (!upstream.ok) {
      const detail = await upstream.text();
      return jsonError(
        'elevenlabs_error',
        `ElevenLabs returned HTTP ${upstream.status}.`,
        upstream.status >= 500 || upstream.status === 429,
        upstream.status,
        detail.slice(0, 240),
      );
    }

    return new Response(upstream.body, {
      status: 200,
      headers: {
        'Content-Type': 'audio/mpeg',
        'Cache-Control': 'no-store',
      },
    });
  },
};

function voiceSettings(voice) {
  if (voice === 'fast') return { stability: 0.35, similarity_boost: 0.7 };
  if (voice === 'calm') return { stability: 0.7, similarity_boost: 0.75 };
  return { stability: 0.5, similarity_boost: 0.75 };
}

function allowRequest(ip) {
  const now = Date.now();
  const events = (requestLog.get(ip) || []).filter((time) => now - time < WINDOW_MS);
  if (events.length >= MAX_REQUESTS) return false;
  events.push(now);
  requestLog.set(ip, events);
  return true;
}

function jsonError(code, message, retryable, status, detail) {
  return new Response(JSON.stringify({ code, message, retryable, detail }), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store',
    },
  });
}
