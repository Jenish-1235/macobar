// Macie's blinking, and the hero demo: the Dock field types a prompt while Macie listens,
// Return is pressed, Macie hops while the reply card rises and streams, then shows how it went.

/** Prompts typed into the demo field, the replies streamed back, and Macie's mood once each reply is in. */
const DEMO_EXCHANGES = [
  {
    prompt: "Clean up my Desktop into folders by type",
    reply: "I'll sort the 48 files on your Desktop into Images, Documents, Screenshots and Archives. Nothing gets deleted. Go ahead?",
    finalMood: "asking",
  },
  {
    prompt: "Find the PDF Maya sent me last week",
    reply: "Found it: Q3 plan.pdf in Downloads, from Maya on Tuesday. Opening it now.",
    finalMood: "done",
  },
  {
    prompt: "Mute notifications until 3pm",
    reply: "Done. Do Not Disturb is on until 3:00 PM.",
    finalMood: "done",
  },
];

/** How often a resting Macie blinks, and for how long its eyes stay shut, in milliseconds. */
const BLINK = { minGap: 3000, maxGap: 6000, duration: 120 };
/** Longest wait for a hop to land before changing mood anyway (one hop is 550 ms). */
const LANDING_TIMEOUT_MS = 600;

/** Pauses that pace the demo, in milliseconds. */
const TIMING = {
  beforeFocus: 900,
  afterFocus: 450,
  typeMin: 34,
  typeMax: 82,
  beforeReturn: 650,
  keyPress: 170,
  beforeReply: 700,
  streamMin: 38,
  streamMax: 75,
  holdReply: 4200,
  afterCollapse: 900,
  visibilityCheck: 500,
};

const demo = {
  field: document.querySelector("[data-chat-field]"),
  draft: document.querySelector("[data-draft]"),
  returnKey: document.querySelector("[data-return-key]"),
  macie: document.querySelector("[data-demo-macie]"),
  card: document.querySelector("[data-reply-card]"),
  cardPrompt: document.querySelector("[data-reply-prompt]"),
  cardReply: document.querySelector("[data-reply-text]"),
};

const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

/** Resolves after `ms` milliseconds. */
function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** A random whole number of milliseconds between `min` and `max`. */
function randomBetween(min, max) {
  return Math.round(min + Math.random() * (max - min));
}

/** Whether the demo field is on screen in a visible tab. */
function isHeroVisible() {
  const field = demo.field.getBoundingClientRect();
  return !document.hidden && field.bottom > 0 && field.top < window.innerHeight;
}

/** Resolves once the hero is on screen, so the demo never plays unseen. */
async function whenHeroVisible() {
  while (!isHeroVisible()) {
    await wait(TIMING.visibilityCheck);
  }
}

/** Places the reply card centred over the field, kept inside the viewport. */
function positionReplyCard() {
  const wrap = demo.card.offsetParent.getBoundingClientRect();
  const field = demo.field.getBoundingClientRect();
  const cardWidth = demo.card.offsetWidth;
  const gutter = 16;
  const centred = field.left + field.width / 2 - cardWidth / 2 - wrap.left;
  const minLeft = gutter - wrap.left;
  const maxLeft = document.documentElement.clientWidth - gutter - cardWidth - wrap.left;
  demo.card.style.left = `${Math.max(minLeft, Math.min(centred, maxLeft))}px`;
}

/** Shows `text` in the field, toggling the placeholder and Return hint. */
function setDraft(text) {
  demo.draft.textContent = text;
  demo.field.classList.toggle("has-draft", text.length > 0);
}

/** Types `text` into the field one character at a time. */
async function typePrompt(text) {
  for (let length = 1; length <= text.length; length += 1) {
    setDraft(text.slice(0, length));
    const pauseAfterWord = text[length - 1] === " " ? 40 : 0;
    await wait(randomBetween(TIMING.typeMin, TIMING.typeMax) + pauseAfterWord);
  }
}

/** Flashes the Return keycap as if it were pressed. */
async function pressReturn() {
  demo.returnKey.classList.add("is-pressed");
  await wait(TIMING.keyPress);
  demo.returnKey.classList.remove("is-pressed");
}

/** Blinks `macie` every few seconds while it's resting. */
function keepBlinking(macie) {
  setTimeout(() => {
    if (macie.dataset.mood === "resting") {
      macie.classList.add("is-blinking");
      setTimeout(() => macie.classList.remove("is-blinking"), BLINK.duration);
    }
    keepBlinking(macie);
  }, randomBetween(BLINK.minGap, BLINK.maxGap));
}

/** Sets Macie's mood in the demo field. */
function setMood(mood) {
  demo.macie.dataset.mood = mood;
}

/** Changes Macie's mood once its current hop lands, so it never stops in mid-air. */
function setMoodAfterLanding(mood) {
  return new Promise((resolve) => {
    const land = () => {
      demo.macie.removeEventListener("animationiteration", land);
      clearTimeout(timeout);
      setMood(mood);
      resolve();
    };
    const timeout = setTimeout(land, LANDING_TIMEOUT_MS);
    demo.macie.addEventListener("animationiteration", land);
  });
}

/** Streams `text` into the reply card a few words at a time. */
async function streamReply(text) {
  const pieces = text.split(/(\s+)/);
  let shown = "";
  for (let index = 0; index < pieces.length; index += 2) {
    shown += pieces[index] + (pieces[index + 1] ?? "");
    demo.cardReply.textContent = shown;
    await wait(randomBetween(TIMING.streamMin, TIMING.streamMax));
  }
}

/** Plays one exchange: listen while typing, press Return, hop while the reply streams, show how it went, collapse. */
async function playExchange({ prompt, reply, finalMood }) {
  await wait(TIMING.beforeFocus);
  demo.field.classList.add("is-active");
  setMood("listening");
  await wait(TIMING.afterFocus);
  await typePrompt(prompt);
  await wait(TIMING.beforeReturn);
  await pressReturn();

  setDraft("");
  demo.cardPrompt.textContent = prompt;
  demo.cardReply.textContent = "";
  positionReplyCard();
  demo.card.classList.add("is-open");
  setMood("working");
  await wait(TIMING.beforeReply);
  await streamReply(reply);
  await setMoodAfterLanding(finalMood);

  await wait(TIMING.holdReply);
  demo.card.classList.remove("is-open");
  demo.field.classList.remove("is-active");
  setMood("resting");
  await wait(TIMING.afterCollapse);
}

/** Shows the first exchange already answered, for people who prefer reduced motion. */
function showStaticEndState() {
  const [first] = DEMO_EXCHANGES;
  demo.cardPrompt.textContent = first.prompt;
  demo.cardReply.textContent = first.reply;
  setMood(first.finalMood);
  positionReplyCard();
  demo.card.classList.add("is-open");
}

/** Runs the demo forever, pausing whenever the hero is off screen. */
async function runDemo() {
  if (prefersReducedMotion.matches) {
    showStaticEndState();
    return;
  }
  for (let index = 0; ; index = (index + 1) % DEMO_EXCHANGES.length) {
    await whenHeroVisible();
    await playExchange(DEMO_EXCHANGES[index]);
  }
}

if (!prefersReducedMotion.matches) {
  document.querySelectorAll(".macie").forEach(keepBlinking);
}

if (demo.field) {
  window.addEventListener("resize", positionReplyCard);
  runDemo();
}
