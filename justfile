# tools come from rokit (rokit.toml), make sure ~/.rokit/bin is on your PATH

default: test

test:
    @for f in tests/*.spec.luau; do lune run "$f" || exit 1; done

# progression curve: [hours] [ascensions]
sim hours="5" asc="0":
    @lune run tools/simulate.luau {{hours}} {{asc}}

lint:
    @selene src tests tools
    @stylua --check src tests tools

fmt:
    @stylua src tests tools

# sync with Studio, then Connect from the Rojo plugin
serve:
    @rojo serve

# Studio through Vinegar (Wine), there's no native Linux build
studio:
    @flatpak run org.vinegarhq.Vinegar studio

# puts the Rojo plugin in the Wine prefix (after Studio's first start)
plugin:
    @./tools/linux/install-rojo-plugin.sh

build:
    @rojo build -o build/NeonHeights.rbxlx

# sourcemap for luau-lsp, Roblox type autocomplete in the editor
sourcemap:
    @rojo sourcemap default.project.json -o sourcemap.json

check: lint test
