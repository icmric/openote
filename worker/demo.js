/**
 * The openote.org/demo Worker — serves the browser demo, and counts visits.
 *
 * **Why this is a second Worker and not part of the site.** Cloudflare uploads
 * an asset directory as the whole of what that Worker serves, so if the demo
 * lived in `site/` every deploy of the website would have to carry a fresh
 * 56 MB Flutter build with it — and a deploy made without one would silently
 * delete the demo. Two Workers on two routes keeps the cadences independent,
 * which is the point: the website changes when a sentence changes, and the
 * demo changes when somebody decides it should.
 *
 * **Why a Worker at all**, when this is a directory of static files: the
 * counting below. Without it, assets could be served with no code running.
 *
 * ## What is counted, and what is not
 *
 * One data point per PAGE LOAD — not per asset, or a single visit would count
 * as the seventy-seven requests it takes to start a Flutter app. No cookie and
 * no script in the page, so there is nothing for an ad blocker to object to:
 * the day, the country Cloudflare already knows from routing the request, the
 * site that linked here, and a visitor hash.
 *
 * **The visitor hash**, which is the one part worth being precise about. It is
 * SHA-256 over the day, the IP address, the user agent and a secret, truncated
 * to eight bytes, and it exists so that two loads can be told apart from one
 * visitor reloading. The day is INSIDE the hash, so it is a different value
 * tomorrow for the same person and nothing can be followed across days. The
 * IP is never stored — only the digest, which never leaves this account.
 *
 * It is still pseudonymous data rather than anonymous, and the honest reason
 * it is here is that the owner asked for a visitor count and decided the
 * trade was fine for a number nobody acts on. `VISIT_SALT` is what keeps the
 * digest from being brute-forceable across the IPv4 space by anyone who ever
 * saw the numbers; set it, and rotating it only costs a discontinuity in the
 * unique count on the day it changes.
 *
 * Bots inflate all of this and nothing here tries to tell a crawler from a
 * person, which is the other half of why exactness was never on offer.
 */

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // **Anything outside /demo goes to /demo/.**
    //
    // On openote.org this never runs: the routes hand this Worker `/demo` and
    // `/demo/*` and nothing else. It is for the workers.dev address, which is
    // the only way to check a deploy before those routes exist — and where
    // the root held nothing, because everything is published one level down
    // so that the paths match the route. An asset miss is a 404 with an empty
    // body, which a browser replaces with its own "page cannot be found", so
    // the first thing anyone saw after a successful deploy looked like a
    // failed one. It was reported as exactly that.
    if (!url.pathname.startsWith('/demo')) {
      return Response.redirect(new URL('/demo/', url).toString(), 302);
    }

    // `sec-fetch-dest: document` is the browser saying "this is a page I am
    // navigating to", which is exactly the event worth counting: one per
    // visit, not one per file. Anything without the header — curl, most
    // crawlers — is not counted rather than guessed at.
    if (request.headers.get('sec-fetch-dest') === 'document') {
      // `waitUntil`, because the hash is async and the page must not wait for
      // a number nobody reads in real time. Counting must never be able to
      // cost somebody the demo, which is also why the whole thing is inside
      // a catch: with no dataset binding — it needs a Workers plan that
      // includes Analytics Engine — this throws, and the page still loads.
      ctx.waitUntil(record(request, env, url).catch(() => {}));
    }

    return env.ASSETS.fetch(request);
  },
};

async function record(request, env, url) {
  if (!env.VISITS) return;

  const cf = request.cf || {};
  // UTC, so the days line up with however the numbers are later read.
  const day = new Date().toISOString().slice(0, 10);

  let from = '';
  try {
    const ref = request.headers.get('referer');
    // The HOST only. A full referrer can carry a search query, which is
    // somebody's words rather than a fact about traffic.
    if (ref) from = new URL(ref).host;
  } catch {
    // A malformed Referer is not worth a thought; it stays empty.
  }

  env.VISITS.writeDataPoint({
    // One index per data point, and the day is what every question starts
    // with: "how many this week".
    indexes: [day],
    blobs: [day, cf.country || '', from, url.pathname, await visitor(request, env, day)],
    doubles: [1],
  });
}

/**
 * Eight bytes of SHA-256 over the day, the address, the user agent and the
 * salt — enough to separate visitors within a day and useless beyond it.
 *
 * Returns '' rather than a weak value if there is nothing to hash, so an
 * empty address never collapses every visitor onto one shared key and
 * reports the day's traffic as a single person.
 */
async function visitor(request, env, day) {
  const ip = request.headers.get('cf-connecting-ip') || '';
  if (!ip) return '';
  const ua = request.headers.get('user-agent') || '';
  const bytes = new TextEncoder().encode(`${day}|${ip}|${ua}|${env.VISIT_SALT || ''}`);
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
  return Array.from(digest.subarray(0, 8), (b) => b.toString(16).padStart(2, '0')).join('');
}
