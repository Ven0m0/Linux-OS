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
ffmpeg -i input.mp4 -c:v libsvtav1 \
  -preset 3 -crf 26 -g 600 -pix_fmt yuv420p10le \
  -svtav1-params "tune=0:film-grain=6:enable-qm=1:qm-min=0:enable-variance-boost=1:tf-strength=1:sharpness=1:tile-columns=1:tile-rows=0:enable-dlf=2:scd=1" \
  -vf "hqdn3d=1.5:1.5:6:6,scale='if(gte(iw,ih),min(1920,iw),-2)':'if(gte(iw,ih),-2,min(1080,ih))',deband,format=yuv420p10le" \
  -c:a libopus -b:a 128k -ac 2 -rematrix_maxval 1.0 \
  -hide_banner -y -nostdin -loglevel error -stats \
  -map_metadata 0 -sn output.mkv
```

### AV1 [Presets](https://gitlab.com/AOMediaCodec/SVT-AV1/-/blob/master/Docs/CommonQuestions.md#what-presets-do)

- Slow preset: 3
- Fast preset: 4-6
- 1080p: `tile-columns=1:tile-rows=0`
- 4k: `tile-columns=2:tile-rows=0`
- Sharpness: `sharpness=-2` up to `sharpness=2` 

- [Auto superres](https://gitlab.com/AOMediaCodec/SVT-AV1/-/blob/master/Docs/Appendix-Super-Resolution.md): `superres-mode=4`
