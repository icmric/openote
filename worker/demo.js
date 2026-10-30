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
 * as the seventy-seven requests it takes to start a Flutter app. No cookie, no
 * script in the page, nothing for an ad blocker to object to and nothing a
 * visitor can be identified by: the day, the country Cloudflare already knows
 * from routing the request, and the site that linked here.
 *
 * **There is deliberately no unique-visitor count.** Counting uniques without
 * cookies means keeping a rotating hash of each visitor's IP address, which is
 * pseudonymous rather than anonymous data, and the owner's brief was numbers
 * "nothing tying the specific user to it". So this counts loads. Bots inflate
 * that and some visitors block nothing at all, which is the other half of why
 * exactness was never on offer here.
 */

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // `sec-fetch-dest: document` is the browser saying "this is a page I am
    // navigating to", which is exactly the event worth counting: one per
    // visit, not one per file. Anything without the header — curl, most
    // crawlers — is not counted rather than guessed at.
    if (request.headers.get('sec-fetch-dest') === 'document') {
      try {
        record(request, env, url);
      } catch {
        // Counting must never be able to cost somebody the demo. If the
        // dataset binding is absent — it needs a Workers plan that includes
        // Analytics Engine — this throws, and the page still loads.
      }
    }

    return env.ASSETS.fetch(request);
  },
};

function record(request, env, url) {
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
    blobs: [day, cf.country || '', from, url.pathname],
    doubles: [1],
  });
}
