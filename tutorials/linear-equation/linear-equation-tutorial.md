# Tutorial: Solving a Linear Equation with `animate`

This tutorial is intentionally mathematically basic. Its purpose is to teach how a complete `animate` video is built from several scenes while still containing enough equation choreography to exercise the mathematical-authoring API.

The source file is **API-first**: the proposed author-facing API and two small composite helpers appear at the top of the file. The six tutorial scenes come afterward and use only that API.

## Learning goals

After the tutorial, a reader should understand how to:

- build one video from several named scenes;
- place and copy mathematical equations;
- keep the equality sign fixed while equation parts move around it;
- make room for a new term before introducing it;
- fade mathematical terms in and out independently;
- perform structure-preserving mathematical rewrites;
- build a real displayed fraction from an existing equation;
- preserve selected formula parts through a rewrite;
- substitute a value into an equation;
- pause deliberately at pedagogically important moments;
- render one scene while developing and then render the complete video.

## Mathematical story

The equation is

\[
3x+5=17.
\]

The goal is **not merely to “get \(x\) alone.”** The goal is to find all numbers that fit in the equation: numbers which, when inserted for \(x\), make the equation true.

The method used to find them is to isolate \(x\).

## Scene 1 — The problem

Show the title and

\[
3x+5=17.
\]

Narration:

> Let's solve the equation \(3x+5=17\).

Keep this scene very short.
Keep the equation on screen when the next scene begins.

## Scene 2 — What “solve” means

Move the equation from Scene 1 upward, then emphasize \(x\). This keeps the
viewer oriented: it is the same equation, now placed to make room for the
explanation below.

Explain:

> The goal is to find all numbers that fit in the equation. That is, all numbers which, when inserted for \(x\), make the equation true.

Then introduce the method:

> We transform the equation until \(x\) is isolated.

This scene establishes the distinction between the **meaning of a solution** and the **method used to find one**.

## Scene 3 — Subtract 5 from both sides

Begin with the original equation on an upper line and copy it to a working line below.

The transition is deliberately decomposed:

1. Copy \(3x+5=17\).
2. Make room for \(-5\) on the left-hand side.
3. Fade in \(-5\) on both sides:

   \[
   3x+5-5=17-5.
   \]

4. Fade out \(+5-5\) on the left **without automatically closing the gap**.
5. Move \(3x\) toward the equality sign.
6. Transform \(17-5\) into \(12\).

Throughout these steps, the equality sign is fixed.

The result is

\[
3x=12.
\]

The explicit gap-closing step matters: it makes simplification visible instead of letting layout reflow hide the algebraic operation.

## Scene 4 — Divide both sides by 3

Again, keep the previous result as a reference line and make a working copy below it.

The choreography is:

1. Copy \(3x=12\).
2. Add division by 3 to both sides as genuine fractions:

   \[
   \frac{3x}{3}=\frac{12}{3}.
   \]

   The existing expressions become numerators; fraction bars and denominator 3 are introduced.

3. Reduce the left side from

   \[
   \frac{3x}{3}
   \]

   to

   \[
   1\cdot x,
   \]

   preserving the visual identity of \(x\).

4. Fade \(1\cdot\) away, leaving \(x\).
5. Pause. At this moment the viewer should register that \(x\) is isolated.
6. Only after the pause, transform

   \[
   \frac{12}{3}
   \]

   into \(4\).

The result is

\[
x=4.
\]

## Scene 5 — Check the solution

Return to the original equation:

\[
3x+5=17.
\]

Copy it to a working line.

Substitute \(x=4\):

\[
3(4)+5=17.
\]

Then simplify in separate steps:

\[
12+5=17,
\]

then

\[
17=17.
\]

Show a checkmark and explain that the resulting statement is true, so \(4\) really is a solution.

This deliberately returns to the definition introduced in Scene 2.

## Scene 6 — Summary

Show

\[
\begin{aligned}
3x+5 &= 17\\
3x   &= 12\\
x    &= 4.
\end{aligned}
\]

Recap:

- A solution is a number that makes the original equation true.
- The method was to isolate \(x\).
- Subtract 5 from both sides.
- Divide both sides by 3.
- Check the resulting value in the original equation.

## API design demonstrated by the tutorial

### Presentation text

Use semantic text constructors for the explanatory text around an equation.
For example, use `title-text` for the opening title instead of choosing a
font, weight, size, and color by hand:

```racket
(title-text "Solving a Linear Equation"
            #:id     'problem-title
            #:center (vec2 0 2))
```

The selected typography theme supplies the title's appearance. This keeps the
tutorial source about the mathematical story, while still allowing a project
to use a different typography theme later. Equations remain structured formula
actors; they are not ordinary presentation text.

### `video` and `scene`

The top-level source should read like a storyboard:

```racket
(video
  #:title "Solving a Linear Equation"
  (scene "problem" ...)
  (scene "meaning" ...)
  (scene "subtract-five" ...)
  (scene "divide-by-three" ...)
  (scene "check" ...)
  (scene "summary" ...))
```

A named scene should be independently renderable during development.

### Equations are structured actors

`equation` should not merely create a picture of TeX/Typst output. It should create a mathematical actor with semantic structure and addressable visual parts.

That makes calls such as these meaningful:

```racket
(part eq "x")
(part eq "+5")
(part eq "=")
```

The string syntax is intended as author convenience. Internally, matching should use the parsed mathematical structure.

### Fixed anchors

For ordinary equation transformations, `=` should be the default anchor:

```racket
(equation "3x+5=17" #:anchor "=")
```

Edits then preserve the equality sign's screen position unless explicitly told otherwise.

This is important enough to be a first-class layout concept rather than an ad-hoc coordinate trick in every tutorial.

### Working copies

A repeated pattern in explanatory mathematics is:

1. preserve the previous line;
2. copy it below;
3. transform the copy.

The proposed helper is therefore:

```racket
(working-copy! eq)
```

It schedules the copying animation and returns a new equation handle.

### Separate semantic change from layout choreography

The subtraction scene deliberately does **not** let deletion automatically compact the equation:

```racket
(fade-out-part! eq
                #:side 'lhs
                "+5-5"
                #:collapse? #f)
```

The author then explicitly asks to move \(3x\):

```racket
(move-part-toward! eq
                   "3x"
                   #:target "=")
```

This distinction is useful in mathematical animation: what disappears and how the remaining material moves are separate authoring decisions.

### Structure-preserving rewrites

The central primitive is:

```racket
(rewrite-part! eq
               #:side 'lhs
               #:from ...
               #:to ...
               #:keep ...)
```

The `#:keep` argument lets the author state which mathematical objects should retain visual continuity.

For example:

```racket
(rewrite-part! eq
               #:side 'lhs
               #:from "\\frac{3x}{3}"
               #:to "1\\cdot x"
               #:keep '("x"))
```

should visibly simplify the \(3/3\) while leaving \(x\) recognizably the same object.

### Fractions should be built, not replaced wholesale

`divide-both-sides!` is more than a textual rewrite:

```racket
(divide-both-sides! eq "3"
                    #:style 'fraction
                    #:build 'bars-and-denominators)
```

The implementation should turn the existing left and right sides into numerators, then introduce fraction bars and denominators. That preserves continuity and communicates the mathematical operation.

### Narration belongs on the timeline

Calls such as

```racket
(say! "Now we divide both sides by 3.")
```

are timeline metadata. Initially they can be used for script extraction. Later they can drive subtitles, recorded narration alignment, or generated voice-over.

### Deliberate pauses

`hold` is not filler. In Scene 4 the pause after removing \(1\cdot\) is pedagogically significant:

```racket
(fade-out-part! ...)
(hold 1.0)
(rewrite-part! ... "\\frac{12}{3}" ... "4")
```

The viewer gets a moment to see that \(x\) has been isolated before arithmetic on the right resumes.

## Suggested implementation order

For this tutorial, the minimal implementation order is:

1. `video`, named `scene`, render-one-scene support;
2. `equation`, `part`, and a fixed equation anchor;
3. `show!`, `fade-in!`, `fade-out!`, `hold`;
4. `copy-equation!`;
5. `make-room!` and explicit part movement;
6. `rewrite-part!` with structural matching;
7. `divide-both-sides!` with fraction construction;
8. `substitute!`;
9. narration metadata via `say!`.

The tutorial is then a useful acceptance test: if these six scenes can be authored cleanly, the first version of the mathematical multi-scene API is probably at the right level.
