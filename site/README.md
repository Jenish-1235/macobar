# macobar landing page

A single static page for macobar: what it is, Macie (the AI agent that lives in it), how it sits in the Dock, what's coming, how you stay in control, and a waitlist link. The hero recreates the Dock with macobar's field in it and plays a short demo: Macie listens while a prompt types itself, Return is pressed, Macie hops while the reply card rises out of the Dock and streams, then looks finished (or asks for your OK).

No framework and no build step.

## Files
| File | Job |
|---|---|
| `index.html` | All page content and structure |
| `styles.css` | Design tokens on `:root` (palette, type, spacing, shape, motion), the Macie component, then one commented block per section |
| `main.js` | Macie's blinking, and the hero demo: typing, Return press, Macie's moods, the reply card rising and streaming |

The only external resource is the Newsreader serif from Google Fonts, used as a fallback where `ui-serif` (Apple's New York in Safari) isn't available.

## Preview
```sh
open site/index.html
# or
cd site && python3 -m http.server 8000   # then visit http://localhost:8000
```

## Waitlist link (placeholder)
Every "Join the waitlist" button scrolls to the closing section, which holds the page's one external link. Its URL is a placeholder, `https://example.com/macobar-waitlist`, marked with a `WAITLIST URL` comment in `index.html`. Replace that one `href` with the real waitlist.

## Macie
Macie is a small HTML/CSS component, used wherever the old mark was (header, hero field, diagram field, confirmation sheet, closing, footer) and in the "Meet Macie" row:

```html
<span class="macie" data-mood="resting" aria-hidden="true"><span class="macie-figure"><span class="macie-body"></span><span class="macie-face"></span></span><span class="macie-ground"></span></span>
```

- **Size:** set `font-size` on `.macie`; `1em` is the body width, and every other measurement is relative to it.
- **Mood:** `data-mood` is one of `resting`, `listening`, `working`, `done`, `asking`, `stuck`. The faces are SVG data URIs (`--face-*`) in the Macie block of `styles.css`, drawn on a 100-unit grid where 100 is the body width.
- **Ground line:** leave out `.macie-ground` inside the Dock field, where Macie already sits on the Dock.
- **Greeting:** the hero has a big `done` Macie with the class `.macie-greeting`. It drops in once on load (`macie-arrive`: falls, squashes on landing, rebounds once, settles) and then stays still. It sits to the right of the headline on wide screens and above it on narrow ones.
- **Motion:** `working` hops with the `macie-hop` keyframes (lift = 0.2w × |sin(t / 0.55s × π)|, squash on landing, stretch in the air). `.macie-still` freezes it mid-hop. `main.js` blinks every resting Macie every 3–6 s. With reduced motion, nothing blinks or hops.

## Editing the demo
The prompts, replies and the mood Macie ends on (`done` or `asking`) are in `DEMO_EXCHANGES` at the top of `main.js`; pacing is in `TIMING`. People who prefer reduced motion see the first exchange already answered, with nothing animating.
