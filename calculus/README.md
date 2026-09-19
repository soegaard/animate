# animate/calculus

`animate/calculus` is Animate's immutable, headless calculus lesson layer.
It keeps mathematical evaluation and exposition separate from native drawing;
`animate/calculus/render` explicitly prepares the same lesson for a Pict,
Visual, or scene.

```racket
#lang racket/base
(require animate/calculus
         animate/calculus/render)

(define-calculus-lesson reading-square
  (model
    [a (parameter 2 #:domain (closed -2 2))]
    [f (function (x) (* x x))]
    [G (graph f)]
    [R (input-reading G a)])
  (views
    [plot (graph-view #:x (closed -5/2 5/2)
                      #:y (closed -1/2 5)
                      #:objects (G R))])
  (initially (show G))
  (step read-output (read R))
  (step vary-input (vary a #:to -2 #:duration 4)))

(define plan (compile-calculus-lesson reading-square))
(calculus-result-value
 (calculus-snapshot-ref (calculus-plan-sample plan #:at 'final)
                        '(R output))) ; => 4

(define prepared (prepare-calculus-plan plan #:width 1280 #:height 720))
(prepared-lesson->pict prepared)
(prepared-lesson->scene prepared)
```

The core module performs no typesetting, native drawing, GUI work, file I/O,
or frame rendering. Results preserve ordinary mathematical partiality:
`'outside-domain`, `'undefined`, and `'unresolved` are distinct from a defined
value. Inspect `calculus-result-status` before treating a result's value as a
number.

## Module boundary

| Module | Responsibility |
| --- | --- |
| `animate/calculus` | Declaration macros, immutable models, domains, held functions, headless plans, snapshots, profiles, and computation policy. |
| `animate/calculus/render` | Explicit output preparation plus shared Pict, Visual, and Animate scene conversion. |

Use `define-calculus-model` when an immutable mathematical model is shared
outside an individual lesson. `define-calculus-component` records a reusable
component descriptor. Contextual mathematical forms such as `function`,
`graph`, `show`, and `read` are valid only within calculus declarations; they
do not replace ordinary Racket bindings elsewhere in the module.

Finite analysis remains semantic data rather than render-frame state:
`sequence` binds an integer index at or above `#:from`, `partial-sum` is
inclusive (and yields zero for an empty range), and `iteration-map` and
`newton-iteration` evaluate every inspected prefix from their declared seed.
`sequence-points` returns only discrete indexed samples. Newton iteration
requires a derivative declared for the same function and reports a partial
result when a derivative or an update is unavailable; it never restarts from
another seed.

Candidate constructors (`level-set`, `root-point`, and `intersection-point`)
validate only author-supplied candidates. They do not search for roots.
Analysis claims retain their supplied domain, category, and nonempty
justification; they are not upgraded to machine-proved theorems.

Limits use the same distinction. `neighborhood` and
`punctured-neighborhood` retain open-domain boundaries and require positive
radii. A `limit-statement` validates its direct real parameter, target, side,
and justification without evaluating the source expression at the limiting
target. Epsilon–delta conditions require finite positive epsilon and delta;
continuity conditions report a declared limit that conflicts with the actual
function value rather than silently displaying it as continuous.
An `asymptote-line` must similarly match the finite/infinite shape and value
of its supplied limit claim; it is not inferred from the edge of a view.

For differential constructions, `tangent` and `linearization` require a
`derivative-function` declared for the same held function. A
`vertical-tangent` is a separate supplied claim and therefore requires its own
nonempty justification rather than a fabricated finite slope.
`taylor-polynomial` evaluates the supplied ordered compatible derivatives;
with no derivatives it is the documented constant approximation at its base.
`approximation-error` remains signed, and `error-segment` joins the two exact
graph values at its authored input rather than measuring a screen distance.
`slope-triangle` derives directed horizontal and vertical legs, including
signed `dx` and `dy`, from an increment or a nonvertical line and authored run.

A `trace` command accepts a `trace-of` locus only when it uses one direct real
parameter over a closed, finite, increasing interval and the parameter starts
at that interval's left endpoint. Invalid sweeps are diagnosed during plan
compilation and do not change the sampled parameter state; a preceding
`set-parameter` can establish a valid trace start.

`together` children share one pre-group state. The compiler rejects a group
when children write the same parameter, an overlapping target's same
persistent presentation property, or the same view window; rejected groups
leave no partial sampled updates behind.

`snapshot-of` accepts the documented `#:values ([parameter constant] ...)`
bindings. It fixes the requested object at those values; unlisted parameters
use the model or lesson's compiled initial values (including `#:values`
overrides), never whichever frame is currently being sampled.

`limit-transition` verifies a matching finite slope-limit claim for two
nonvertical lines through the same anchor. A valid transition hides the finite
source line and reveals the separate target line without assigning the limit
to its approaching parameter; an invalid transition leaves presentation state
unchanged.

## Test

From the repository root:

```sh
raco test calculus/tests/core-smoke-test.rkt \
          calculus/tests/guide-lessons-test.rkt \
          calculus/tests/render-smoke-test.rkt \
          calculus/tests/component-declaration-test.rkt \
          calculus/tests/external-function-test.rkt
```

The tests exercise Guide-style graph reading, candidate validation, finite
sequences and Newton prefixes, supplied derivatives, piecewise function
values, domains, deterministic action sampling, component declarations,
external functions, and native output dimensions.
