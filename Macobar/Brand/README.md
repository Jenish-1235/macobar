# Brand
Macie, the character shared by every screen. macobar is the product (the bar in the Dock); Macie is the agent who lives in it.

## Files
- `Macie.swift`: Macie, a soft pebble sitting on the Dock line. Its face shows its mood; it hops like a launching app while working and blinks while resting. Drawn in the surrounding foreground style with the eyes cut out, so it works on glass, charcoal, light or dark.

## Public surface
- `Macie(mood:size:showsGround:)`
- `Macie.Mood`: `.resting`, `.listening`, `.working`, `.done`, `.asking`, `.stuck`

## Character
- Calm, quick, a little playful. Speaks in short plain sentences, says what it did, never pretends, and asks before anything risky.
- Monochrome: the body takes the foreground colour, the eyes are holes. No other colours.
- Moods map to real states; never show a mood the app isn't actually in.

| Mood | When |
|---|---|
| resting | Idle; blinks every few seconds |
| listening | The user is focused in the field or typing |
| working | A reply or task is in progress; hops |
| done | The last request finished |
| asking | Waiting for the user's OK (e.g. permission in setup) |
| stuck | The last request failed |

## Depends on
Nothing.
