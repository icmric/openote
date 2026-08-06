/**
 * The openote.org Worker.
 *
 * **What it is for.** The page itself is one static HTML file and Cloudflare's
 * static-asset handling serves it without any code running — so this Worker
 * exists for exactly one route, `/api/latest`, and that route is the reason to
 * be on a Worker at all rather than on plain static hosting.
 *
 * The page needs to know the newest release. Asking GitHub from the *browser*
 * works and is what shipped first, but it has two real costs: the
 * unauthenticated GitHub API allows 60 requests an hour **per visitor IP**, so
 * a lecture theatre behind one NAT can exhaust it between them, and every
 * visitor pays a fresh cross-origin round trip to api.github.com before the
 * download buttons resolve.
 *
 * Fetching it here instead fixes both: one origin request per cache period,
 * shared by everyone, and the response is already on Cloudflare's edge next to
 * the visitor. It also lets the response be trimmed to the six fields the page
 * actually uses, which turns a ~90 KB release payload into well under a
 * kilobyte.
 *
 * **The page still works without this.** `index.html` falls back to calling
 * GitHub directly if `/api/latest` is unavailable, so the file can be opened
 * from disk, served from anywhere, and keeps working if this Worker is ever
 * removed. A hosting choice should not be able to break the page.
 */

/** How long the edge may serve a cached release without re-asking GitHub. */
const CACHE_SECONDS = 600;

/**
 * Served stale for this long past expiry while a refresh happens in the
 * background — so a GitHub outage degrades to "slightly old version number"
 * rather than to a page with no download links.
 */
const STALE_SECONDS = 3_600;

const REPO = 'icmric/openote';

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (url.pathname === '/api/latest') {
      return latestRelease(request, ctx);
    }

    // Everything else is a static asset. `env.ASSETS` is bound by the
    // `assets` block in wrangler.jsonc; the binding is what makes this a
    // Worker *with* assets rather than a Worker that has to serve HTML from a
    // string literal.
    return env.ASSETS.fetch(request);
  },
};

async function latestRelease(request, ctx) {
  // Only GET. A download page has no reason to accept anything else, and
  // saying so is cheaper than reasoning about what a POST here would mean.
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return new Response('Method not allowed', { status: 405 });
  }

  const cache = caches.default;
  const key = new Request(new URL('/api/latest', request.url).toString(), {
    method: 'GET',
  });

  const hit = await cache.match(key);
  if (hit) return hit;

  let payload;
  try {
    const res = await fetch(
      `https://api.github.com/repos/${REPO}/releases/latest`,
      {
        headers: {
          // GitHub rejects API requests with no User-Agent outright.
          'user-agent': 'openote.org (+https://github.com/icmric/openote)',
          accept: 'application/vnd.github+json',
        },
        // A second cache layer, at the fetch itself: this is what stops a
        // burst of simultaneous misses becoming a burst of origin requests.
        cf: { cacheTtl: CACHE_SECONDS, cacheEverything: true },
      },
    );
    if (!res.ok) throw new Error(`github ${res.status}`);
    payload = trim(await res.json());
  } catch (e) {
    // 503 rather than a fabricated empty release: the page's fallback path is
    // written for "I could not find out", and handing it an authoritative
    // "there are no releases" would make it say something untrue.
    return json({ error: 'upstream unavailable' }, 503, 0);
  }

  const response = json(payload, 200, CACHE_SECONDS);
  ctx.waitUntil(cache.put(key, response.clone()));
  return response;
}

/**
 * Keep only what the page renders.
 *
 * Not merely a size optimisation — it is also the seam that stops the page
 * accidentally depending on some other field of GitHub's release schema, which
 * would then be this Worker's problem to keep supplying.
 */
function trim(rel) {
  return {
    name: rel.name,
    tag_name: rel.tag_name,
    html_url: rel.html_url,
    published_at: rel.published_at,
    assets: (rel.assets || []).map((a) => ({
      name: a.name,
      size: a.size,
      browser_download_url: a.browser_download_url,
    })),
  };
}

function json(body, status, maxAge) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': maxAge
        ? `public, max-age=${maxAge}, stale-while-revalidate=${STALE_SECONDS}`
        : 'no-store',
    },
  });
}
