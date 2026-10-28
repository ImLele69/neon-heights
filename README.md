# Neon Heights

A progressive tycoon for Roblox, written in strict Luau and built with Rojo. You
own a floating platform in a neon city, buy modules that drop credits onto a
conveyor, unlock six sectors with their own mechanics and eventually ascend:
wipe the base, keep a permanent multiplier, climb again faster

The whole game loop is there and tested (base, purchases, sectors, ascension,
saving, offline earnings, daily streak, crates, quests, codes, global
leaderboards, shop). It hasn't been published on Roblox yet, see
[status](#status)

## Why it might be interesting to read

Most of the work here went into the parts of a Roblox game you can't see but
that bite you in production:

- **server authoritative economy.** the client only sends intents, never
  values. `Economy` is pure logic that takes a profile and says what should
  happen without applying it, the server is the only thing that mutates state
- **session locked saves** (`DataService`). the lock is taken with
  `UpdateAsync`, not get + set, stale locks from crashed servers can be stolen
  after a window longer than autosave, old or corrupted saves get reconciled
  field by field instead of crashing the server
- **idempotent purchases** (`ShopService`). grant, save, and only then return
  `PurchaseGranted`. receipts already granted are never granted twice, and the
  cleanup matches on the full `_<userId>` suffix so user 42 can't wipe user
  142's receipts
- **rate limiting** on every remote with a token bucket per player and per
  action
- **big numbers** (`BigNum`): mantissa + exponent because past 2^53 doubles
  lose integer precision and a tycoon gets there in a few hours. leaderboards
  store a scaled log since OrderedDataStore only takes 64-bit ints
- **deterministic daily quests** from day + userId with an xorshift, so nothing
  needs saving except progress
- **a balance simulator** (`tools/simulate.luau`) that plays the curve with a
  greedy bot and checks it against the design windows

## Tests without Studio

[Lune](https://github.com/lune-org/lune) runs Luau from the command line and
`tests/robloxshim.luau` fakes the bits of `game`, `script`, `Instance`, `Enum`
and the geometry types that the modules touch. So economy, balance,
persistence and security get checked in about a second instead of by hitting
Play and staring at it

    just check     # selene + stylua --check + 226 tests

What the shim can't cover and needs Studio: physics, rendering, input and the
feel of the game

## Balance

    $ just sim 5 0

    time           credits        total  modules event
    25m02s           24.0K         692K      139 SECTOR 2: Refinery
    54m58s           2.56M         150M      280 SECTOR 3: Reactor
    1h25m             673M        24.5B      413 SECTOR 4: Archive
    1h54m            29.6B        1.20T      515 SECTOR 5: Orbit
    2h30m             912B        42.0T      608 SECTOR 6: Singularity
    3h40m             128T       11.0aa      754 ASCENSION available
    5h00m           17.8aa        897aa      869 end

    average gap        20.7s
    max gap            0m52s

The sector thresholds in `Config.luau` are tuned **against this simulation**,
not on round numbers. If you touch costs, income or `dropInterval` run it again
and check the windows still hold, especially the max gap between purchases,
which is the metric that decides first day retention

The full design (loop, progression, retention systems, monetization, look) is in
[docs/DESIGN.md](docs/DESIGN.md)

## Getting started

The toolchain is pinned with [rokit](https://github.com/rojo-rbx/rokit) in
`rokit.toml`: Rojo, Lune, StyLua, selene, luau-lsp. You also need
[just](https://github.com/casey/just)

```bash
rokit install      # first time, or after a pull
just check         # lint + every test
just sim 5 0       # 5 hour progression curve, 0 ascensions
```

To work in Studio:

```bash
just sourcemap     # once, for Roblox type autocomplete in the editor
just serve         # then Connect from the Rojo plugin inside Studio
```

`just build` writes a place file to `build/NeonHeights.rbxlx` if you just want
to open it

I develop on Linux, where Studio runs through Vinegar (Wine): `just studio`
opens it and `just plugin` installs the Rojo plugin the first time. Details and
gotchas in [docs/LINUX.md](docs/LINUX.md)

## Layout

```
src/shared/    BigNum, Config, Economy, Sectors, Rewards, Quests, Juice, Remotes
src/server/    DataService, PlayerService, PlotService, BaseBuilder,
               Leaderboard, ShopService, RateLimiter
src/client/    HUD and panels: goal, gift, crate, quests, codes, shop, archive
tests/         specs + harness + Roblox shim, run with Lune
tools/         simulate.luau, Linux helper for the Rojo plugin
```

Everything is built from primitives: no imported meshes or animations, the look
is color, Neon, lights and post processing. All the "game feel" (pops,
gradients, flying numbers, count ups) lives in `src/shared/Juice.luau`

## Status

Done: the full loop above, plus the mechanics that make sectors different
(refiner, data spent on permanent upgrades, fusions)

Not done yet:

- **gamepass and dev product ids.** In `Config.luau` `GAMEPASSES` and `PRODUCTS`
  all have `id = 0`, meaning "not created yet". The game runs anyway and buying
  answers "not available yet". Once the products exist on the Creator Dashboard
  the zeros get replaced with the real ids (they're public numbers, not secrets)
- **energy (sector 3) and low gravity (sector 5)**. both depend on how it feels
  to move around and need tuning by playing, so they're not written yet
- **playtesting**, the part no test can replace. The first upgrade should come
  within about twenty seconds, if it doesn't something in the curve broke and
  `just sim` will say so before Studio does

## License

MIT, see [LICENSE](LICENSE)
