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

## Test

From the repository root:

```sh
raco test calculus/tests/core-smoke-test.rkt \
          calculus/tests/guide-lessons-test.rkt \
          calculus/tests/render-smoke-test.rkt
```

The tests exercise Guide-style graph reading, supplied derivatives, piecewise
function values, domains, deterministic action sampling, and native output
dimensions.
