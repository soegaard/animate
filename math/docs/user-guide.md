# Semantic mathematical animation: user guide

**Implementation 0.3.0.** This document describes the supplied source, not future
API promises. The original design is archived separately as `proposal-v0.1.md`.

## 1. Separate mathematical meaning from presentation

You author three values: a mathematical state, a derivation, and a presentation
plan. A state owns an ordinary held S-expression and an immutable mathematical
context. A derivation applies named operations and records their justifications,
conditions and occurrence correspondences. A presentation chooses line groups,
retained history, timing, fades and movement.

```racket
(require animate/math)

(define initial
  (math '(= (+ (* 3 x) 5) 17)
        #:id 'example
        #:context (math-context #:real '(x))))

(define d
  (derive initial
    [subtract-five (both-sides 'subtract 5)]
    [cancel-five (cancel-addends #:at (lhs))]
    [compute-right (evaluate #:at (rhs))]))

(define p
  (present d #:groups '((subtract-five cancel-five compute-right))))
```

The expression progresses through `3x+5−5=17−5`, then `3x=17−5`, then `3x=12`.
Grouping those steps retains one completed working line, without losing the
intermediate mathematical states. Default durations use exact rational seconds;
the complete concrete linear lesson lasts exactly `54/5` seconds. Deliberately
supplied inexact durations remain inexact.

The `animate/math` module is pure: it imports neither native rendering nor CAS
execution. Import `animate/math/render` for the explicitly effectful native
preparation and output boundary:

```racket
(require animate/math/render)
(define (make-demo-scene)
  (math-plan->scene! p))
```

`math-plan->scene!` is the preparation/compilation boundary. It returns an
ordinary `animate` scene. No mathematical rewriting, CAS query, or TeX process
is performed while that compiled scene is sampled.

## 2. Held expressions

Use ordinary data:

```racket
'(+ x x)
'(* 2 x)
'(- 17 5)
'(/ (* 3 x) 3)
'(expt (+ x 3) 2)
'(or (= x -1) (= x -5))
```

`math` retains the expression exactly. It does not sort terms, combine repeated
variables, remove zeroes, evaluate arithmetic, or normalize subtraction into
addition. In particular, `(* 3 x)` is a product; `3x` is one symbol.

Prefer exact integer and rational constants. Inexact numbers can be displayed,
but the local arithmetic evaluator does not silently approximate them. Perfect
square roots evaluate exactly; `sqrt(2)` remains symbolic.

Built-in syntax includes `+`, unary/binary `-`, `*`, `/`, `expt`, `sqrt`, `abs`,
relations, `and`, `or`, `not`, and `parens`. Generic scalar applications can be
held and printed, but an unfamiliar function does not acquire algebraic rules
or real-domain guarantees merely because it is printable. Complex branches,
matrices, noncommutative multiplication, and binding-sensitive calculus rewrites
are outside this release.

Substitution is explicitly held and simultaneous:

```racket
(held-substitute '(+ x y) (hash 'x 'y 'y 'z)) ; '(+ y z)
(held-substitute '(+ (* x x) 0) (hash 'x 2))  ; '(+ (* 2 2) 0)
```

This is deliberately not implemented with `racket-cas`'s `subst` flag. That
operation still uses simplifying constructors internally. Traversal beneath
binders such as sums, integrals or lambdas is rejected until binding-aware
substitution is implemented.

## 3. Contexts, definedness and evidence

```racket
(math-context
  #:real '(a b c x)
  #:assuming '((not (= a 0)))
  #:definitions '((Δ (- (expt b 2) (* 4 a c)))))
```

Definitions are scoped and cycle-checked. `Δ` in this context denotes its stated
expression; it is not an unrelated free variable. The presentation displays
available definitions and assumptions above the working lines.

Source-definedness restrictions are retained separately from author assumptions.
For example, a state containing `(/ x x)` retains `x≠0` after cancellation.
A later step may not drop that exclusion, and `conclude 'all-real` refuses to
call a variable-restricted domain all of the reals.

An operation checks its requirements before changing the state. Dividing an
equation by `a` requires `a≠0`. Multiplying an inequality requires a known sign;
a negative multiplier reverses the relation. An unknown sign asks you to split
cases. Squaring both sides is available only as an explicitly one-way
implication:

```racket
(both-sides 'power 2 #:relationship 'implication)
```

Every step records its relationship: expression equivalence, equation equivalence,
implication, specialization, or a case split. The evidence status is
`established`, `refuted`, or `unknown`. Established means supported by the named
implementation/checker; these records are not formal proof-assistant certificates.
CAS-supported evidence is labeled separately. Numerical tests are not proofs.

Strict validation is the default. Drafting is explicit:

```racket
(define draft
  (parameterize ([current-math-validation 'draft])
    (derive initial [unresolved (assert-step '(= x 4))])))

(present draft #:allow-unverified? #t)
```

The draft presentation has a visible warning. Refuted requirements are rejected
even in draft mode. A mathematical step can be well justified without an entire
solving strategy being complete: specialization and implication do not become
solution-set equivalences simply because their individual operations are valid.

## 4. Selection, occurrence identity and traces

Selectors operate on the input state of each step:

```racket
(lhs)
(rhs)
(numerator (lhs))
(denominator (rhs))
(at-path '(0 1))
(matching 'x #:occurrence 2)
(all-matching 'x)
```

Paths are zero-based operand paths, excluding the operator symbol. Explicit
occurrence ordinals are one-based. `resolve-one`, and operations needing one
focus, reject ambiguity. `math-select` returns a list; `matching` without an
ordinal can be used as a query returning several occurrences.

```racket
(math-select initial (matching 'x))
(math-inspect initial '(0 0 1))
```

The three `x`s in `(+ x x x)` have distinct occurrence IDs. Paths locate them in
one state. Persistent lineage comes from rewrite witnesses, not their numerical
positions or equality as expressions. Use different root `#:id` values for
independently authored expressions.

A working copy creates a new *view* without pretending that mathematical
multiplicity changed. Distribution, in contrast, has actual copy lineage:
`a(b+c)` has one `a` occurrence and `ab+ac` has two descendants.

Useful accessors include:

```racket
(define s (derivation-step d 'subtract-five))
(rewrite-step-before s)
(rewrite-step-after s)
(rewrite-step-trace s)
(rewrite-step-verification s)
(rewrite-step-bindings s)
(trace-descendants s some-old-occurrence)
```

Traces distinguish preservation/container identity, copying, reordering,
evaluation, cancellation, creation, removal, and explicitly declared merges.
They do not claim that the digit `7` in `17−5` becomes the digit `2` in `12`.

Rendered operators have ownership roles in `math-source-span` and
`prepared-token` records. `operator-of` resolves the owning expression; it is
not a separate algebraic operand. The rendering records distinguish its relation,
operator, parentheses and structural geometry. Prefer mathematical selectors for
rewrites and role records when implementing an inspector or visual emphasis.

## 5. Operations

| Constructor | Behavior |
|---|---|
| `(both-sides 'subtract 5)` | Introduces the operation on both sides without simplifying |
| `(cancel-addends #:at (lhs))` | Removes a unique additive inverse pair |
| `(cancel-addends #:pair '(1 2))` | Explicit zero-based pair in the selected signed-addend sequence |
| `(cancel-factor #:factor 3 #:at (lhs) #:keep-one? #t)` | Cancels structurally present factors; optionally leaves `1·x` |
| `(remove-unit #:at (lhs))` | Removes a unit factor as its own step |
| `(reduce-identities #:at (rhs))` | Applies local zero, unit and sign identities |
| `(evaluate #:at (rhs))` | Exact arithmetic, leaving equations as equations |
| `(evaluate #:mode 'deepest)` | One bottom-up numeric layer |
| `(rewrite-to target #:at focus #:using rule-name)` | Checks an explicitly requested local target |
| `(reorder-addends #:order '(1 0))` | Reorders whole signed terms, retaining signs |
| `(zero-product)` | Turns a real scalar product equation equal to zero into alternatives |
| `(square-solutions)` | Handles a square equation using the known sign of its right side |
| `(each-branch operation)` | Applies an operation to every direct `or` alternative |
| `(abbreviate 'Δ #:at (rhs))` | Uses a checked scoped definition |
| `(substitute '((a . 0)))` | Held specialization, not implicit normalization |
| `(conclude 'no-solutions #:for 'x)` | Checked solution classification |

The implemented target rule names are `perfect-square`, `expand-products`,
`rational-identity`, `factor`, `split-linear-term`, and `factor-by-grouping`.
They use bounded exact rational-polynomial checking. Except for structural
constraints such as a squared-binomial target, these names identify the author's
intent, not independent automatic solvers.

**Important implementation boundary:** `rewrite-to` records a checked focused
replacement. `expand-products` does not reconstruct a multi-step explanatory
trace automatically. Write those elementary steps explicitly or use template
rules when detailed factor-copying animation is wanted. Within an opaque
replacement, incoming and outgoing parts fade rather than receive invented
fine-grained provenance. Merge records likewise do not yet have a dedicated
many-to-one path-morph effect.

The sparse checker is bounded; a computation exceeding its budget is not
accepted as an identity. It is an internal checking aid, not a second public CAS.

## 6. Presentation groups and choreography

```racket
(define style
  (math-presentation
    #:anchor 'relation
    #:history 'keep-completed-groups
    #:start-group 'copy
    #:reflow 'staged
    #:multiplication 'school
    #:pause-between-groups 3/5
    #:duration 4/5
    #:font-size 11/20
    #:row-gap 21/20
    #:max-visible-rows 5))
```

`classroom` is this default style. Supported alternatives include `#:anchor
'center`, `#:history 'replace` or `'keep-all-checkpoints`, `#:start-group
'replace`, `#:reflow 'simultaneous`, and explicit multiplication. New/removed
parts currently support `'fade`; unsupported effects are rejected.

Groups partition all step names once and in order. Use unique names along a
complete case path, including its shared prefix. There is no silent skipping or
reordering of mathematical steps.

```racket
(define tuned
  (choreograph p
    [cancel-five
      (retire-cancelled #:duration 2/5 #:layout 'hold)
      (hold 1/2)
      (compact #:duration 2/5)]))
```

Supported phase constructors are `prepare-space`, `reveal-created`,
`retire-cancelled`, `retire-removed`, `compact`, `hold`, `transition`, and
`explain-math`.
A complete override must actually retire outgoing material, reveal new material,
and place retained material. Incomplete choreography raises an error during
scene compilation rather than ending with missing terms. Revealing a replacement
before retiring its old expression is also rejected.

**Typed transformation choreography.** Evaluation and coarse rewrites treat the
entire focused subexpression as an indivisible visual unit. For a default
`transition`, the old unit fades out over 45% of the duration, survivors move
over 10%, and the new unit fades in over 45%. Thus neither `12−5` while evaluating
`17−5`, nor `4/3` while evaluating `12/3`, is produced by displaying a new result
beside old arithmetic. Unaffected subexpressions remain visible.

Cancellation holds survivors still during retirement and pauses; only `compact`
moves them. Square-root splits copy the common left-hand expression into the
branch destinations before introducing complete radical right sides. Reorders
move signed terms as rigid units on separated paths; a minus sign never travels
independently of its term. Metric differences between SVG crops do not invalidate
mathematical occurrence identity. At checkpoints the exact prepared endpoint
assets replace the temporary moving views.

For example, an explanatory inset is separate from the working equation:

```racket
(choreograph p
  [add-nine
    (explain-math '(= (expt (/ 6 2) 2) 9)
                  #:caption "Half the coefficient of x, then square it"
                  #:duration 2)
    (prepare-space #:duration 11/25)
    (reveal-created #:duration 9/25)])
```

Use a plan with an `add-nine` step for this example. The inset reserves a lower
display band, is typeset during preparation, and disappears before equation work
resumes. It does not advance the mathematical checkpoint. The author supplies
its content; `explain-math` is not a mathematical verification operation.

The relation anchor keeps a working line's first equality/relation fixed. In an
`or` line the first relation is the primary anchor; separate independently
anchored branch columns are not yet a presentation mode.

History remains on screen up to the available row budget. The original line is
pinned; older intermediate retained lines scroll out as necessary. The whole
lesson is uniformly scaled to fit its widest formula. Width, font metrics and
row geometry are prepared once, not recalculated during a frame.

## 7. Concrete linear equation

The complete source is `examples/linear-concrete.rkt`.

```racket
(define solution
  (derive initial
    [subtract-five (both-sides 'subtract 5)]
    [cancel-five (cancel-addends #:at (lhs))]
    [evaluate-twelve (evaluate #:at (rhs))]
    [divide-three (both-sides 'divide 3)]
    [reduce-left (cancel-factor #:at (lhs) #:factor 3 #:keep-one? #t)]
    [remove-one (remove-unit #:at (lhs))]
    [evaluate-four (evaluate #:at (rhs))]))
```

The checkpoints are:

```text
3x+5 = 17
3x+5−5 = 17−5
3x = 17−5
3x = 12
(3x)/3 = 12/3
1·x = 12/3
x = 12/3
x = 4
```

The supplied plan groups subtraction/cancellation/evaluation into one retained
line and division/unit removal/evaluation into another. Cancellation explicitly
fades before gap-closing. Removing `1·` has its own pause.

```racket
(define check (check-solution initial #:for 'x #:value 4))
(present check)
```

Candidate checking substitutes into the original expression, checks its original
assumptions/domain, evaluates numeric layers, and leaves `17=17` visible with a
verdict. It establishes that the candidate works; completeness additionally
depends on the solving derivation's equivalences and case coverage.

## 8. General linear equation

`examples/linear-general.rkt` starts with `ax+b=c` over the reals and constructs
three mutually exclusive, exhaustive coefficient cases.

```racket
(derive-cases general-problem
  [ordinary '(not (= a 0))
    [subtract-b (both-sides 'subtract 'b)]
    [cancel-b (cancel-addends #:at (lhs))]
    [divide-a (both-sides 'divide 'a)]
    [cancel-a (cancel-factor #:at (lhs) #:factor 'a #:keep-one? #t)]
    [remove-one (remove-unit #:at (lhs))]]
  [identity '(and (= a 0) (= b c))
    [all-values (conclude 'all-real #:for 'x)]]
  [inconsistent '(and (= a 0) (not (= b c)))
    [no-values (conclude 'no-solutions #:for 'x)]]))
```

The ordinary branch ends with `(c−b)/a`. The other branches conclude all real
values or no solutions. The supplied example also visibly specializes `a=0`
and reduces the equation before classification.

A case guard extends only that branch's context. It is not inferred from a
requested division. Coverage checking is a conservative propositional partition
check over real sign atoms. It has a seven-atom budget; more complicated
partitions can remain unknown rather than being guessed complete.

## 9. Concrete quadratic equation

`examples/quadratic-concrete.rkt` solves `x²+6x+5=0` by completing the square:

```text
x²+6x+5 = 0
x²+6x+5−5 = 0−5
x²+6x = −5
x²+6x+9 = −5+9
(x+3)² = 4
x+3 = √4  or  x+3 = −√4
x+3 = 2   or  x+3 = −2
x+3−3 = 2−3  or  x+3−3 = −2−3
x = −1  or  x = −5
```

The key operations are `rewrite-to ... #:using 'perfect-square`,
`square-solutions`, and `each-branch`. Both alternatives are actual logical
branches, not a scalar `±` operator. A zero right side produces only one root;
a negative right side produces no real solutions. An unknown sign requires
explicit cases.

The supplied plan inserts the explanatory inset `(6/2)^2=9` before adding nine,
so the viewer sees where that number comes from. Its ordinary mathematical
checkpoints are unchanged.

The file exports candidate checks for both answers. A factored approach is also
possible by explicitly showing a target factorization and applying `zero-product`.
The system does not silently change the author's chosen solution method.

## 10. General quadratic equation

`examples/quadratic-general.rkt` provides the entire real-coefficient
classification, including the degenerate linear and constant equations.

For `a≠0`, it derives:

```text
ax²+bx+c = 0
ax²+bx = −c
4a(ax²+bx) = 4a(−c)
4a²x²+4abx = −4ac
4a²x²+4abx+b² = −4ac+b²
(2ax+b)² = b²−4ac
(2ax+b)² = Δ
```

It then splits on the sign of `Δ`. With `Δ>0`, square solutions and explicit
subtract/divide steps give:

```text
x = (−b+√Δ)/(2a)  or  x = (−b−√Δ)/(2a)
```

This scaled-square route works for negative as well as positive `a`; it never
uses the generally invalid real identity `√(a²)=a`.

| Conditions | Result |
|---|---|
| `a≠0, Δ>0` | Two real roots |
| `a≠0, Δ=0` | One distinct root `−b/(2a)` |
| `a≠0, Δ<0` | No real roots |
| `a=0, b≠0` | Linear root `−c/b` |
| `a=0, b=0, c=0` | Every real number |
| `a=0, b=0, c≠0` | No solution |

The current presentation uses explicit `or`, not automatic `±` compaction. Cases
are shown sequentially, with the relevant context visible. This example uses
`(present solution #:case-layout 'shared-prefix ...)`: it derives the square
once, then presents each discriminant case from that common checkpoint. The
six terminal cases remain complete, but the default duration is now `549/10`
seconds (54.9), rather than 74.7.

The ordinary `present` default remains `'complete-paths`. With `'shared-prefix`,
group hashes still describe full case paths and are validated before being
projected onto common and branch segments. `plan-segment-shared?` distinguishes
common-work segments from terminal cases. Shared prefixes are not listed as
separate selectable solutions by `--list-cases`.

The header shows authored assumptions and definitions. Derived exclusions
already established by those assumptions are omitted from the display, but not
from mathematical evidence. A genuine original-domain exclusion, such as
`x≠0` for `x/x`, remains visible. This is not blanket suppression of restrictions.

Selecting one path restores its full derivation from the original equation: 

```sh
racket math/examples/quadratic-general.rkt \
  --case quadratic/two-real-roots --workers 10 \
  --mp4 math-output/formula.mp4 math-output/formula-frames
```

## 11. Traceable template rules

```racket
(define-math-rule distribute-left
  #:metavariables (u v w)
  #:from (* u (+ v w))
  #:to (+ (* u v) (* u w))
  #:in real-scalars
  #:check polynomial-identity)

(define distribution
  (derive (math '(* a (+ b c))
                #:context (math-context #:real '(a b c)))
    [distribute (use-rule distribute-left)]))
```

The syntax is held, not evaluated as Racket multiplication. The pattern matcher
returns both value bindings and occurrence witnesses. A repeated destination
metavariable creates copy lineage. Repeated source metavariables require an
explicit merge policy:

```racket
(define-math-rule twice
  #:metavariables (u)
  #:from (+ u u)
  #:to (* 2 u)
  #:check polynomial-identity
  #:merge 'merge)
```

Optional clauses include `#:requires (...)` and `#:version 1`. `use-rule` accepts
`#:at`. `apply-rewrite` returns one `rewrite-step` directly.

This implementation uses exact structural matching. It does not pretend that a
`math-match` view which synthesizes a grouped tail automatically provides an
occurrence witness. Explicit template matching supplies reliable provenance
without requiring a second mathematical expression AST.

Raw operation, edit, state, trace, and presentation constructors are private.
They are not part of the supported authoring API. Use `make-math-rule` or
`define-math-rule`, built-in operations, and the public inspection accessors.

`current-math-prover` is a documented trusted extension boundary. A custom
prover accepts a context and a proposition and returns one `verification` for
that same proposition. It must require no keyword arguments. The framework
validates the result's protocol but does not turn trusted code into a formal
proof checker. Evidence metadata is copied recursively into immutable,
acyclic data. Cycles, procedures, and opaque native resources are rejected;
validated nested verification records are allowed.

## 12. Optional CAS services

Neither backend is required by the examples or core tests.

```racket
(require animate/math/cas
         animate/math/cas/racket-cas
         animate/math/cas/calcura)

(define services
  (math-services
    #:local (racket-cas-service)
    #:extended (calcura-service #:module "/absolute/path/to/calcura.rkt")))

;; Route construction-time obligations through the selected services.
(call-with-math-services! services
  (lambda ()
    ;; Construct a derivation here.
    (derive initial [subtract-five (both-sides 'subtract 5)])))

;; Or obtain a separate report for an existing immutable derivation.
(verify-derivation! d #:services services)
```

The local checker runs first. Optional services receive undecided propositions.
Calls are synchronous, bounded and terminated at timeout; no query continues in
the background. Unsupported, unavailable, timeout, error and undecided results
remain explicit. Contradictory backend decisions remain unknown. A callback
returning `#f` is an invalid result, not a timeout. A failed response cannot supply
a decision, and evidence for a different proposition is rejected. Verification
reports retain copied status/evidence/diagnostics, never an opaque mutable
backend result. Raw calculation results remain at the adapter boundary.

`racket-cas-service` offers explicit `normalize`, `expand`, `simplify` and
`together` calculations through `cas-calculate!`, plus conservative literal
boolean decisions. Calculation results do not replace held display expressions
unless the author explicitly imports the returned value.

The configured Calcura adapter loads `parse-input-form-string` and `Eval`. It
transports supported scalar operations into an InputForm `Simplify` query,
expands definitions, supplies real-variable assumptions, and isolates user
variable names from built-in names. Only recognized literal truth values count
as decisions. `#:query` allows an application-specific service callback returning
`cas-result`; unconfigured Calcura reports unavailable.

Definedness is checked before accepting a backend simplification. A `True`
answer for `x/x=1` must not erase the unresolved exclusion at zero.

Live integrations with these two CAS packages were not available in the delivery
environment; transport, failure and service contracts are covered by tests, not
represented as successful live CAS testing.

## 13. Native preparation and inspection

```racket
(require (prefix-in a: animate)
         (prefix-in mr: animate/math/render))

(define prepared (mr:prepare-math-plan! p #:theme 'dark))
(define scn (mr:math-plan->scene! prepared))
(define frame-state (a:scene-sample scn 3/2))
(define frame (a:scene-state->pict frame-state #:camera (a:scene-camera-at scn 3/2)))

(mr:prepared-math-plan-diagnostics prepared)
(plan-schedule p)
(plan-inspect p 3/2)
(checkpoint-at p 3/2)
```

Every formula is typeset once as a complete TeX expression. Hierarchical DVI/SVG
markers associate visible material with mathematical occurrences and operator
roles, including the internals of fractions and powers. SVG pieces retain
ancestor transforms and shared glyph definitions. The implementation does not
independently typeset every leaf and guess the resulting spacing.

Assets are content-addressed SVG files under the user's Racket preferences
folder, `animate-math/svg-v1`. Preparation returns frozen geometry and asset
references. Native scenes use normal `svg-image`, `move-to`, `fade-to`, and
scene composition. Native frame workers can read the same prepared files.
Do not delete that cache while a scene using it is rendering. Reprepare after
moving prepared asset files, changing the camera, or changing the theme.

Native named scene values accept interpolable values, not arbitrary metadata.
The scene therefore stores the numeric checkpoint index under
`'math-lesson.checkpoint` by default. Look up its complete record in
`(plan-checkpoints p)`. A custom `#:id` changes the key prefix.

```racket
(define index (a:scene-value-at scn 'math-lesson.checkpoint 3/2))
(define checkpoint (vector-ref (plan-checkpoints p) index))
(math-datum (math-checkpoint-state checkpoint))
```

Between checkpoints, the record denotes the most recently committed state;
partially faded frames are not new mathematical assertions. Inspection data is
available programmatically; this release does not add a graphical inspector.

`math->visual!` returns a native group for a static expression. `math-plan->pict!`
is a convenience function that compiles and samples; for repeated frames,
prepare/compile once and use the native scene sampler instead. The
`#:renderers` option is forwarded to native final painting together with
`#:camera`; `#f` selects the native renderer list. Omitting `#:theme` retains a
prepared plan's captured theme. Preparation fits complete-SVG artifact metrics,
not arbitrary custom-renderer padding. When a custom renderer changes extents,
adjust the layout explicitly rather than assuming automatic remeasurement.

## 14. Validation and practical boundaries

The defining reference for every public binding is
[`scribblings/math.scrbl`](../scribblings/math.scrbl). The JSON API index is in
[`public-api.json`](public-api.json). For changes from 0.1.1, read
[`house-style-review.md`](house-style-review.md).

Run `math/run-tests.rkt` for base-only checks and `math/run-style-checks.rkt` for
the separate source/dependency/reference audit. Run
`math/run-probes.rkt --dark math-output/review-v0.3/probes` for the actual installed
animate/TeX pipeline, dense intermediate PNG reviews and random-access pixel tests.
The manifest identifies both the active animation step/phase and the last committed
mathematical checkpoint, so a midpoint is no longer mislabeled as a completed step.
`--checkpoints-only` requests a smaller endpoint-only probe set.
`tests/tex-layout-probe.rkt` independently checks that semantic annotations do
not change TeX layout; it requires `latex` and `dvipng`.

This delivery does not claim a successful native end-to-end rendering run in its
build environment. See `validation.md` for the exact executed tests and omitted
integration tests. The limitation is test coverage of the installed renderer,
not a placeholder replacement for the native scene compiler.
