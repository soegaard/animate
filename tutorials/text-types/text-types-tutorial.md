# Tutorial: Text Types in `animate`

This tutorial shows the text tools in `animate`. Its source program is
[`text-types-tutorial.rkt`](text-types-tutorial.rkt). Open it in the previewer
to view one named block at a time:

```sh
raco animate preview tutorials/text-types/text-types-tutorial.rkt text-types-tutorial
```

## Typography in one minute

Use semantic text for presentation text. A semantic constructor says what a
piece of text is for, such as a title, a caption, or a note. It does not choose
a font by itself.

A typography theme supplies the font, size, weight, colour, alignment, and any
treatment box for each role. This lets one source program use a different look
without rewriting its story.

`#:center` places the text box. For body paragraphs, the box is centered on
that point while the lines inside it are left-aligned. Supply `#:width` when a
paragraph should wrap.

## The built-in semantic roles

The tutorial's `headings`, `explanatory-text`, and `technical-text` blocks
show all nine built-in roles.

| Constructor | Use it for |
| --- | --- |
| `title-text` | The main presentation title. |
| `subtitle-text` | Supporting text below a title. |
| `section-heading-text` | The start of a section. |
| `body-text` | Normal explanation and paragraphs. |
| `caption-text` | Small supporting detail. |
| `label-text` | A short name near an object, control, or value. |
| `quotation-text` | A quotation or important statement. |
| `code-text` | Source code or a literal command. The theme can give it a box. |
| `annotation-text` | A quiet note that should not compete with the main text. |

For example:

```racket
(body-text "A typography theme supplies the appearance."
           #:id 'explanation
           #:center (vec2 0 0)
           #:width 12)
```

## Named styles and inline emphasis

Use `styled-text` when a typography theme contains a named style that has no
dedicated constructor. It can select one of the standard styles or a style you
add to your own theme.

Use `styled-rich-text` when one sentence needs inline emphasis while the whole
sentence still has a semantic style:

```racket
(styled-rich-text #:style 'body #:id 'note #:center origin #:width 10
                  "This word is "
                  (text-span "important" #:font-weight 'bold)
                  ".")
```

## Low-level text tools

The `raw-text` block shows three lower-level constructors:

- `plain-text` is a single line.
- `paragraph` is ordinary text that can wrap at `#:width`.
- `rich-text` is raw text with inline `text-span` formatting.

Use these when the source must choose the exact appearance. Otherwise, prefer
a semantic role. Semantic roles make a complete video easier to restyle later.

## Render the tutorial

Render PNG frames:

```sh
racket tutorials/text-types/text-types-tutorial.rkt frames
```

Render frames and encode an MP4:

```sh
racket tutorials/text-types/text-types-tutorial.rkt frames text-types.mp4
```
