# Semantic text and typography design inventory

This note records the boundary between Animate's low-level text API and its
semantic typography API.

## Raw text remains explicit

`plain-text`, `paragraph`, `rich-text`, and `text-span` are concrete text
layout requests. They keep the appearance stated in source and never inspect a
typography theme. `plain-text` accepts one line only. `paragraph` and
`rich-text` accept explicit line breaks and use `#:width` as a maximum
renderer-measured wrapping width, not as a fixed box width.

The raw outer properties are font face, portable font family, style, weight,
size, color, horizontal and vertical anchor, line alignment, line spacing, and
optional wrapping width. A rich span inherits every outer property it does not
explicitly override. The first line supplies a paragraph's baseline. The raw
default color is `theme-foreground`.

`text-visual-with-content` and `text-visual-with-spans` are immutable update
operations. They retain the original text visual's identity, transform,
opacity, and outer layout request while changing the specified source data.

Rendering freezes glyphs at a stable local origin. Translating text therefore
does not ask the font backend to rerasterize the same glyphs at a new device
position. Text measurement is renderer-aware: custom Pict renderers can supply
their own concrete `text-visual?` output, and layout helpers measure that
output.

## Semantic text is a separate layer

`title-text`, `body-text`, `code-text`, and the other semantic constructors
store a style key, source text/spans, immutable overrides, transform, and
identity. They do not select a platform font when the Scene is built. At a
render or layout boundary they lower once to the existing concrete text
visual under an explicit immutable typography theme. Color specifications in
that style are then resolved by the independent color theme.

This separation means changing typography can change width, line breaks,
baseline, and treatment padding. Any construction-time layout helper that
measures semantic text must receive the same explicit typography snapshot that
will be used for its intended output.

## Serialization and identity

Typography themes have a versioned, deterministic data representation and an
appearance fingerprint. Display name and provenance are descriptive metadata;
they do not alter the fingerprint. Render plans, preview cache keys, section
caches, and worker requests carry the complete typography snapshot and the
resolver version. A cached rendered frame cannot cross two typography
appearances merely because their color theme is unchanged.
