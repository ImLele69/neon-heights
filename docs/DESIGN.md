# Neon Heights, design

A progressive tycoon themed around a vertical neon city. Every player owns a
floating platform that grows upwards as they buy modules.

The theme is there for a practical reason: it holds up with primitive geometry,
emissive materials and colored lights. No imported 3D models, no custom
animations, everything can be generated from scripts

## The loop

```
droppers generate credits
  credits ride the conveyor to the collector
  you buy the next module (rising price)
  cash/sec goes up
  you hit a price wall
  ASCENSION: wipe the base, keep a permanent multiplier
  run it again faster, get higher
```

Three nested cycles with different periods, and that's what holds retention:

| Cycle | Period | What it gives |
|---|---|---|
| Module purchase | 30 s to 3 min | the steady reward |
| Sector completed | 20 to 40 min | a visible change in look, a new mechanic |
| Ascension | 2 to 5 h of play | permanent multiplier, new tier of modules |

## Progression

Six sectors, each with its own look and color. The sector is the unit of a
"session": you go in, you finish it, you've seen something new.

| # | Sector | Color | Unlock | Mechanic | Status |
|---|---|---|---|---|---|
| 1 | Foundation | cyan | 0 | basic droppers | done |
| 2 | Refinery | magenta | 690K | refiner, multiplies yield | done |
| 3 | Reactor | acid green | 150M | energy, droppers need power | needs playtest |
| 4 | Archive | amber | 24.5B | data, a secondary currency from playtime | done |
| 5 | Orbit | violet | 1.2T | low gravity, floating platforms | needs playtest |
| 6 | Singularity | white/gold | 42T | fusions, eight maxed modules = bonus | done |

The two marked "needs playtest" aren't written on purpose. Energy can easily
become a boring tax instead of a choice, and low gravity has to be tried by
walking around in it: neither can be tuned by reading numbers

**Sector bonuses multiply with each other**, with ascension and with
gamepasses. The first tuning (refiner +4%/level, fusion +15%) dropped ascension
from 3h20 to 1h50, so they got halved. If you touch them run `just sim` before
trusting anything

The unlock column is total credits earned, and it's calibrated against the
simulation, not by eye: `just sim 5 0` has to stay inside the windows. If you
touch costs or income **run the simulation again**, the thresholds are tuned on
the curve, not on round numbers

Price curve: `cost(n) = base * 1.18^n`. 18% is where a purchase still feels
noticeable without turning into a wall too early. The real tuning happens on
retention data, not on paper

Ascension unlocks at 1.1e16 total credits, so after sector 6: resetting before
the last sector would turn ascension into a punishment. It gives a permanent
+25% per ascension, compounding. Resets modules and credits. Keeps data,
multiplier, gamepasses, cosmetics

**Measured curve** (`just sim 5 0`, 5h, no ascensions):

| | |
|---|---|
| sectors | 25m / 55m / 1h25 / 1h54 / 2h30 |
| ascension | 3h40 |
| average gap between purchases | 21s |
| max gap | 52s |

The max gap is the metric that matters most: a six minute hole in the first
twenty minutes costs D1 retention. The first version of the curve had one, and
that's why the seed module starts at level 3

## Retention systems, by impact

Listed by value/cost. The first four are the ones that actually move numbers

**1. Offline earnings.** On return: "while you were away you earned X". It's the
number one reason players reopen a tycoon. Capped at 4 hours, 12 with the
gamepass, and the cap is also the monetization hook

**2. Daily reward with a streak.** 7 days, the reward grows, day 7 is big (an
exclusive cosmetic or a long boost). The streak resets if you skip a day: the
lever is the streak, not what the reward is worth

**3. Always visible progression.** The next purchase bar is always on screen,
there's never a moment where you don't know what you're going for. The "next
goal 20 seconds away" is what keeps a session alive

**4. Short timed rewards.** A free crate every 15 min, with a notification on
screen. A reason to stay instead of closing

**5. Daily quests.** Three, simple, doable in one session: "earn X", "buy Y
modules", "ascend once"

**6. Leaderboards.** Global, by total credits, ascensions and hours.
Competition means coming back. Three physical totems in the lobby, visible,
with names

**7. Cosmetic rebirth.** Every ascension visibly changes something on the base
(aura color, particles, collector shape). Progress has to be something other
players can look at, not just a number

**8. Codes.** Redeemable codes to post on socials. Next to no implementation
cost and it pushes people back on every update

## Monetization

Hard rule: **no gamepass may make the game unplayable without it**. A hard
paywall burns retention, and without retention the discovery algorithm shows
you to nobody. Sell speed and convenience, never access

### Gamepasses (one time)

| Product | R$ | What it does |
|---|---:|---|
| 2x Credits | 199 | doubles all earnings |
| Auto-Collect | 249 | the collector collects by itself |
| Offline 12h | 199 | raises the offline cap from 4 to 12 h |
| +2 dropper slots | 349 | more droppers at once per module |
| VIP Aura | 149 | purely cosmetic, very visible |
| Sector teleport | 99 | quality of life |

### Dev products (repeatable, this is where most of the revenue is)

| Product | R$ | What it does |
|---|---:|---|
| 2x Boost 15 min | 49 | a short burst |
| Credit pack (S/M/L) | 99 / 249 / 599 | shortcut |
| Instant ascension | 399 | skips the final grind |
| Fill crate | 79 | skips the 15 min timer |

Realistically gamepasses bring volume and dev products bring margin. A player
who buys a 49 R$ boost buys it again

### The cut, so nobody gets illusions

A player spends $5, that's 400 R$. Roblox keeps 30% on in-game purchases so you
get 280 R$. DevEx pays $0.0035/R$, so **$0.98**. Around 20% of what the player
spent, always do the math with that factor

## Look

It isn't decoration: on Roblox the thumbnail and the first ten seconds decide
whether the player stays, and so whether the algorithm shows you to others. The
style is overloaded on purpose, full colors, round fonts, everything big and
moving. Sober here means invisible

The one place the overload stops is number readability: the player must always
know how much they have and how much they're missing. If an effect makes those
two numbers harder to read the effect goes

**Palette** (in `Juice.PALETTE`, one place only):

| | |
|---|---|
| background | `#090816` almost black, violet tint |
| primary | cyan `#00F5FF` |
| secondary | magenta `#FF00BE` |
| accents | lime, amber, violet, hot pink |

Fonts: `FredokaOne` for text, `LuckiestGuy` for numbers. Round and heavy,
readable even small on a phone

**UI rules**
- panels with very rounded corners, thick border and a hard shadow (not a soft
  one), it reads better on small screens
- big buttons in a column on the right: on mobile that's where the thumb is,
  and mobile is most of the players
- a ready button *breathes*, a waiting one is dimmed and shows its countdown,
  so the player knows if it's worth waiting
- moving gradients on the goal bar, hue cycling on the multiplier

**Feedback on every action**, this is where the reward feeling comes from,
not from the numbers:
- elastic pop on every purchase, physical confetti from the module you bought
- toasts that come in with a bounce and a shake
- module cores spin and float, the bought ones faster
- the bar flashes white when the goal is reached

**World**: `Neon` and colored `PointLight`s everywhere, `Future` lighting, high
bloom, pushed saturation. Each sector has its own color so progress shows from
far away, even from someone else's base

All the effects live in `src/shared/Juice.luau`, one place to touch to change
the visual style of the whole game

## Tech

- all the money logic is on the server. The client only sends intents
  (`RemoteEvent`), never values, no money math client side
- saves with session locking (the ProfileService pattern): only one server
  writes a profile at a time, otherwise money gets duplicated on teleport
- rate limit on every remote
- big numbers: past `2^53` floats lose precision, so it's mantissa + exponent
  (`{m, e}`) formatted idle game style, `1.24aa`
- parts on the conveyor are the number one source of lag: a pool of reused
  parts with a hard cap, not `Instance.new` on every drop
- droppers don't spawn parts if nobody is watching, the value piles up and
  gets applied on return
