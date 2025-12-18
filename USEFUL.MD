## HTML

- [https://developer.mozilla.org/en-US/docs/Web/Performance/Guides/Speculative_loading](https://developer.mozilla.org/en-US/docs/Web/Performance/Guides/Speculative_loading)

```html
<link rel="prefetch" href="next.html" />
<link rel="dns-prefetch" href="[https://example.com/](https://example.com/)" />
<link rel="preconnect" href="[https://example.com](https://example.com)" />
<link rel="preload" href="main.js" as="script" />
<link rel="prerender" href="/next-page" />
<link rel="modulepreload" href="main.js" />
```

| Speculative loading features | Purpose | When to use |
| :--------------------------- | :------------------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `<link rel="preconnect">` | Cross-origin connection warming | Use on your most critical cross-origin connections to provide performance improvements when connecting to them. |
| `<link rel="dns-prefetch">` | Cross-origin connection warming | Use on all of your cross-origin connections to provide small performance improvements when connecting to them. |
| `<link rel="preload">` | High-priority loading of current page subresources | Use to load high-priority resources faster on the current page, for strategic performance improvements. Don't preload everything, otherwise you won't see the benefit. Also has some other interesting uses — see Preload: What Is It Good For? on Smashing Magazine (2016) |
| `<link rel="modulepreload">` | High-priority loading of current page JavaScript modules | Use to preload high-priority JavaScript modules for strategic performance improvements. |
| `<link rel="prefetch">` | Pre-populating the HTTP cache | Use to prefetch same-site future navigation resources or subresources used on those pages. Uses HTTP cache therefore has a number of issues with document prefetches, such as being potentially blocked by Cache-Control headers. Use the Speculation Rules API for document prefetches instead, where it is supported. |
| `<link rel="prerender">` | Preparing for the next navigation | Deprecated; you are advised not to use this. Use Speculation Rules API prerender instead, where it is supported. |

## Markdown

- Use `<br>` to insert a line break.
- Use `<p></p>` to create a new paragraph with extra spacing.
- Use `&nbsp;` to add a single space between words or elements.

## Useful websites

**Discord related**

- https://autocompressor.net/av1
- https://autocompressor.net

## Bash

- https://github.com/adrianlarion/useful-sed
- [https://dotfiles.github.io/](https://dotfiles.github.io/)
- [https://terminal.sexy/](https://terminal.sexy/)
- [https://wiki.archlinux.org/title/Git](https://wiki.archlinux.org/title/Git)
- [Pure-bash-bible](https://github.com/dylanaraps/pure-bash-bible)
- [Pure-sh-bible](https://github.com/dylanaraps/pure-sh-bible)
- [Bash Guide](https://guide.bash.academy) **|** [Bash Guide old](https://mywiki.wooledge.org/BashGuide)
- [Google's shellguide](https://google.github.io/styleguide/shellguide.html)
- [Bash optimizations](https://www.reddit.com/r/bash/comments/1ky4r7l/stop_writing_slow_bash_scripts_performance)

### FFMPEG

```bash
ffmpeg -i input.mkv -c:v libsvtav1 \
  -preset 4 -crf 30 -g 600 -pix_fmt yuv420p10le \
  -svtav1-params tune=0:film-grain=8:enable-qm=1:qm-min=0:fast-decode=1 \
  -vf "scale='if(gt(iw,ih),min(1920,iw),-2)':'if(gt(iw,ih),-2,min(1920,ih))',deband" \
  -c:a libopus -b:a 96k -ac 2 -rematrix_maxval 1.0 \
  -f mkv -hide_banner -y -nostdin -loglevel error -stats \
  -map_metadata 0 output.mkv
```

or depending on speed `-preset 5` or `-preset 6`
