# Developing on Linux

There's no Roblox Studio for Linux and no real replacement: it's closed source
and you need it to open the place, test and publish. The only way is
**Vinegar**, an actively maintained Wine wrapper that runs Studio inside a
flatpak. I work on Fedora, it should be the same on any distro with flatpak

The rest of the toolchain (Rojo, Lune, StyLua, selene, luau-lsp) is native and
honestly works better than anywhere else

## Setup

```
flatpak install flathub org.vinegarhq.Vinegar
flatpak override --user --filesystem=/path/to/neon-heights org.vinegarhq.Vinegar
```

The second command is needed because the flatpak only sees Documents and
Pictures by default, without it Studio can't reach the project

## First start (once)

```bash
just studio
```

The first start downloads Studio from Roblox and creates the Wine prefix. It
takes a while, that's normal. It'll ask you to log in

Then, with Studio open or closed:

```bash
just plugin
```

`rojo plugin install` answers *"Your platform is not currently supported"*,
it only knows the Windows and macOS paths. The script in `tools/linux/` copies
`Rojo.rbxm` into the Wine prefix instead:

```
prefixes/studio/drive_c/users/<you>/AppData/Local/Roblox/Plugins/
```

Careful: there's another Plugins folder under `versions/<hash>/Plugins`, but
that's the Studio install and it gets **wiped on every update**. A plugin put
there disappears by itself after a few days

## "You haven't installed any plugins yet"

**Studio only reads the plugin folder on startup.** If it was open when you ran
`just plugin` the plugin won't show up, close Studio and open it again

The script notices and tells you. To check by hand that the file is there:

```bash
ls ~/.var/app/org.vinegarhq.Vinegar/data/vinegar/prefixes/studio/drive_c/users/*/AppData/Local/Roblox/Plugins/
```

There should be a `Rojo.rbxm` of about 555 KB

## Day to day

```bash
just serve      # in one terminal, leave it running
just studio     # in another one
```

In Studio: **Plugins, Rojo, Connect**. From then on every save on disk shows up
in Studio

The connection works despite the sandbox: the flatpak has the `network`
permission and `localhost:34872` is reachable from inside. I checked, it's not
a guess

## What works and what doesn't

**Works**: editing, syncing with Rojo, hitting Play, testing the game,
publishing to Roblox

**Expect**: slow startup (it's Wine), a few graphical glitches, Studio heavier
than native. If something looks broken try restarting Studio before blaming
the code

**Doesn't work**: Team Create has always been flaky under Wine. Not a problem if
you work alone

## Why Linux isn't really a problem here

Almost all the work on this project **doesn't go through Studio**:

```bash
just check      # lint + every test, in about a second
just sim 5 0    # the five hour progression curve
```

Economy, balance, persistence, security, all checked from the CLI with Lune
without ever opening Studio. Studio is only for the things you actually have to
look at: rendering, physics, input and the *feel*

That's also why `tests/robloxshim.luau` exists: it fakes `game`, `script`,
`Instance`, `Enum` and the geometry types so modules written for Roblox run
under Lune

## If Vinegar acts up

- `flatpak run org.vinegarhq.Vinegar --help` lists the subcommands
- logs are in `~/.var/app/org.vinegarhq.Vinegar/cache/vinegar/logs`
- `flatpak update org.vinegarhq.Vinegar`
- to start from scratch delete `~/.var/app/org.vinegarhq.Vinegar/data/vinegar`
  (it rebuilds the prefix and downloads Studio again, so run `just plugin`
  again too)

If Wine gets unbearable the fallback is Studio on a Windows VM or another
machine, with `rojo serve --address 0.0.0.0` here and the plugin pointing at
this machine's IP instead of localhost. The code stays where it is
