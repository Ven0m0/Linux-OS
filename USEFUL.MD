## HTML

- <https://developer.mozilla.org/en-US/docs/Web/Performance/Guides/Speculative_loading>

```html
<link rel="prefetch" href="next.html" />
<link rel="dns-prefetch" href="[https://example.com/](https://example.com/)" />
<link rel="preconnect" href="[https://example.com](https://example.com)" />
<link rel="preload" href="main.js" as="script" />
<link rel="prerender" href="/next-page" />
<link rel="modulepreload" href="main.js" />
````

| Speculative loading features | Purpose | When to use |
| :--- | :--- | :--- |
| `<link rel="preconnect">` | Cross-origin connection warming | Use on your most critical cross-origin connections to provide performance improvements when connecting to them. |
| `<link rel="dns-prefetch">` | Cross-origin connection warming | Use on all of your cross-origin connections to provide small performance improvements when connecting to them. |
| `<link rel="preload">` | High-priority loading of current page subresources | Use to load high-priority resources faster on the current page, for strategic performance improvements. Don't preload everything, otherwise you won't see the benefit. Also has some other interesting uses — see Preload: What Is It Good For? on Smashing Magazine (2016) |
| `<link rel="modulepreload">` | High-priority loading of current page JavaScript modules | Use to preload high-priority JavaScript modules for strategic performance improvements. |
| `<link rel="prefetch">` | Pre-populating the HTTP cache | Use to prefetch same-site future navigation resources or subresources used on those pages. Uses HTTP cache therefore has a number of issues with document prefetches, such as being potentially blocked by Cache-Control headers. Use the Speculation Rules API for document prefetches instead, where it is supported. |
| `<link rel="prerender">` | Preparing for the next navigation | Deprecated; you are advised not to use this. Use Speculation Rules API prerender instead, where it is supported. |





## Useful websites

**Discord related**
- https://autocompressor.net/av1
- https://autocompressor.net
