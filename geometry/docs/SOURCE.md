# Source and compatibility notes

The containing system was inspected through the GitHub source connector.

- Repository: https://github.com/soegaard/animate
- Revision: `d189485eec4acf1e15e1fd05feb2043f35ffdb37`
- Package metadata at that revision: `animate` 1.23.0.
- Its CI declares Racket 8.12 and 9.3 coverage. This geometry delivery has not
  itself been executed on either version in the build environment.

## Runtime module boundaries

The new code imports only these public repository entry points:

- [`main.rkt`](https://github.com/soegaard/animate/blob/d189485eec4acf1e15e1fd05feb2043f35ffdb37/main.rkt)
  — semantic Visuals, cameras, paths, text, scenes, values, and relations.
- [`colors.rkt`](https://github.com/soegaard/animate/blob/d189485eec4acf1e15e1fd05feb2043f35ffdb37/colors.rkt)
  — native palette/role tokens, exact colors, and unresolved color mixing.
- [`render.rkt`](https://github.com/soegaard/animate/blob/d189485eec4acf1e15e1fd05feb2043f35ffdb37/render.rkt)
  — native PNG and FFmpeg output.

The relative imports intentionally bind to the checkout into which `geometry/`
is placed. The directory does not replace or patch any existing repository file.
It does not vendor the `animate` sources, a Racket runtime, or font files.

## API contracts checked in source

The implementation files consulted to verify the public contracts include:

| Source path | Details checked |
|---|---|
| `private/visual-model.rkt` | `circle`, `make-path-visual`, and the independent cosmetic stroke-width, stroke-color, and fill-color protocols. |
| `private/path-geometry.rkt` | `path-geometry`, `path-subpath`, line and cubic segment constructors. |
| `private/text-visual.rkt` | `plain-text`/`paragraph`, `#:center`, local-world font sizes, font options, wrapping width. |
| `private/group-visual.rkt` | Group construction and stable child identities. |
| `private/camera.rkt` | World width, output dimensions, centre, and background. |
| `private/parameter.rkt` | Immutable named scene-value handles. |
| `private/scene.rkt` | `scene-set-value`, `scene-add`, `scene-play`, random-access sampling. |
| `private/animation.rkt` | `(value-to target destination)` and semantic interpolation requests. |
| `private/relation-visual.rkt` | Two-argument resolver, explicit value dependencies, root-only output structure, and no assumed portable closure cache key. |
| `private/color-token.rkt` / `private/color-style.rkt` | Native family variants and unresolved token-aware `color-mix`. |
| `private/png-renderer.rkt` | Full-frame and selected-index rendering with color-theme/supersampling options. |
| `private/video-encoder.rkt` / `examples/private/run-demo.rkt` | Native MP4 output, resizing, frame-rate, and FFmpeg calling conventions. |

Inspection of private implementation files is not a runtime dependency on those
files. This first geometry kernel is a small local numerical implementation of
the agreed geometric vocabulary; it is not a claim to expose the complete `geo`
package API.
