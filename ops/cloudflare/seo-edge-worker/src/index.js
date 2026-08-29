export default {
  async fetch(request) {
    const url = new URL(request.url)
    if (url.pathname !== "/robots.txt") return new Response("Not Found", { status: 404 })
    if (!new Set(["GET", "HEAD"]).has(request.method)) {
      return new Response("Method Not Allowed", { status: 405, headers: { Allow: "GET, HEAD" } })
    }

    const body = [
      "User-agent: *",
      "Allow: /",
      "Disallow: /admin",
      "Disallow: /my",
      `Sitemap: ${url.origin}/sitemap.xml`,
      ""
    ].join("\n")

    return new Response(request.method === "HEAD" ? null : body, {
      headers: {
        "Content-Type": "text/plain; charset=utf-8",
        "Cache-Control": "public, max-age=3600"
      }
    })
  }
}
