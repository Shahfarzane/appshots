// Serves the appshots-updates R2 bucket read-only on updates.nerd.ceo.
// Exists because the account's R2 custom-hostname certificate never deploys
// (SSL-for-SaaS issue); a Worker route rides the zone's Universal SSL instead.
export default {
  async fetch(request, env) {
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method not allowed", { status: 405 });
    }

    const url = new URL(request.url);
    const key = decodeURIComponent(url.pathname.slice(1));
    if (!key) {
      return new Response("Not found", { status: 404 });
    }

    const object = await env.UPDATES.get(key);
    if (!object) {
      return new Response("Not found", { status: 404 });
    }

    const headers = new Headers();
    object.writeHttpMetadata(headers);
    headers.set("etag", object.httpEtag);
    // Mutable feed objects (appcast.xml, latest pointers) must not cache long;
    // the immutable versioned DMGs/zips can.
    const mutable = /(?:appcast\.xml|latest[^/]*)$/.test(key);
    headers.set("cache-control", mutable ? "public, max-age=60" : "public, max-age=31536000, immutable");

    if (request.method === "HEAD") {
      return new Response(null, { headers });
    }
    return new Response(object.body, { headers });
  },
};
