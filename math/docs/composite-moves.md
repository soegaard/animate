# Named mathematical moves — design and user guide

**Implemented in animate/math 0.4.0.** Based on Animate commit
`525253b2c8d6aa47bf7a5ddad1c51f82d322ccb0`, including its completed process renderer.

## 1. Three levels, not one

An elementary mathematical step changes a held state and carries its original
verification and occurrence trace. A **move** is a named, ordered composition of
such steps, possibly containing other moves. A **presentation group** determines
which elementary steps are worked through on one classroom row.

These concepts remain separate. Moves have no timing or rendering fields.
Presentation can use their structure, but it cannot strengthen their mathematical
claims. In particular, collecting a one-way implication into a move does not turn
it into an equivalence.

The system does not become an automatic equation solver. The author still chooses
the method, operations, targets, and mathematical context. Existing local checkers
and optional CAS services keep their existing responsibilities.

## 2. A complete concrete linear lesson

```racket
#lang racket/base
(require animate/math)

(define problem
  (math '(= (+ (* 3 x) 5) 17)
        #:id 'linear-lesson
        #:context (math-context #:real '(x))))

(define solution
  (derive problem
    [isolate-term
     (steps
       [subtract-five   (both-sides 'subtract 5)]
       [cancel-five     (cancel-addends #:at (lhs))]
       [evaluate-twelve (evaluate #:at (rhs))])]
    [isolate-x
     (steps
       [divide-three (both-sides 'divide 3)]
       [reduce-left  (cancel-factor #:at (lhs) #:factor 3 #:keep-one? #t)]
       [remove-one   (remove-unit #:at (lhs))]
       [evaluate-four (evaluate #:at (rhs))])]))

(define plan
  (present solution #:style classroom #:groups 'top-level))

(define answer-check
  (check-solution problem #:for 'x #:value 4))
```

The seven elementary steps are still exactly:

```text
3x+5 = 17
3x+5-5 = 17-5
3x = 17-5
3x = 12
(3x)/3 = 12/3
1·x = 12/3
x = 12/3
x = 4
```

Neither `steps` nor presentation grouping simplifies these expressions. The
candidate check establishes that 4 satisfies the original equation; completeness
comes from the equivalence-preserving solving derivation, not from one successful
substitution.

The shipped `examples/linear-concrete.rkt` additionally retains the previously
reviewed timing overrides. They address elementary steps inside the two moves.

## 3. What `steps` constructs

`(steps [name operation] ...)` constructs a **nonempty recipe**, recognized by
`step-sequence?`. Each operation must be an existing `math-operation?` or another
`step-sequence?`. Each name is a literal identifier, captured as a symbol.

Constructing a recipe does not apply it. Operation expressions are evaluated by
ordinary Racket evaluation, but no mathematical state is advanced by the `steps`
constructor. As before, authors should use pure operation constructors.

When a recipe occupies a named `derive` slot, the outer slot names the move and
its children run in order. Nesting has no implicit algebraic, timing, or visual
consequences beyond that declared order.

```racket
(derive problem
  [isolate
   (steps
     [remove-constant
      (steps
        [subtract (both-sides 'subtract 5)]
        [cancel   (cancel-addends #:at (lhs))])]
     [evaluate (evaluate #:at (rhs))])])
```

A recipe is **not** a `math-operation?`: `apply-math-operation` returns one
`rewrite-step?`, whereas a recipe may produce many. Apply a recipe as a named
`derive` entry. There is no automatic recipe lifting through `each-branch` in
this release; a branchwise recipe can contain explicitly branchwise elementary
operations instead:

```racket
(define (subtract-in-each-alternative amount)
  (steps
    [subtract (each-branch (both-sides 'subtract amount))]
    [cancel   (each-branch (cancel-addends #:at (lhs)))]))
```

This makes the order of branchwise mathematical actions explicit rather than
silently choosing between “finish one branch” and “apply each operation to all
branches.” Parameter-case trees remain the responsibility of `derive-cases`.

## 4. Ordinary functions make reusable recipes

```racket
(define (subtract-and-cancel amount)
  (steps
    [subtract (both-sides 'subtract amount)]
    [cancel   (cancel-addends #:at (lhs))]))

(define working
  (derive problem
    [remove-constant (subtract-and-cancel 5)]
    [compute-right   (evaluate #:at (rhs))]))
```

The helper does not evaluate the right-hand side, skip ambiguous selection, or
invent a nonzero assumption. Its children retain the exact conditions and
failure behavior of the original primitives.

For generated recipes, use `steps/proc`:

```racket
(define (subtract-and-cancel/proc amount)
  (steps/proc
    (list (cons 'subtract (both-sides 'subtract amount))
          (cons 'cancel (cancel-addends #:at (lhs))))))
```

`derive/proc` accepts the same pair format, with an elementary operation or recipe
in the cdr. The pair format is `(cons name operation)`, not `(list name operation)`.
An empty `derive` remains useful as an identity derivation; an empty `steps` recipe
is rejected rather than introducing a meaningless move.

All sibling entries are validated before mathematical application. A failure
returns no partial derivation and does not mutate the input. This is not a rollback
promise for arbitrary external effects in a custom prover or operation callback.

## 5. Names and addresses

Names must be unique among siblings. The same local child name may occur in two
separate moves:

```racket
(define d
  (derive problem
    [first  (steps [shift (both-sides 'add 1)])]
    [second (steps [shift (both-sides 'add 2)])]))
```

The elementary addresses are `(first shift)` and `(second shift)`. They are lists
of symbols, not strings with slash parsing. The command-line inspector displays
slashes for readability only.

A symbol is an unqualified shorthand and succeeds only when there is exactly one
matching node in the requested derivation. Thus `(derivation-step d 'shift)` is
an error. `(derivation-step d '(first shift))` is exact. A one-element list, such
as `'(first)`, selects the exact root; no implicit descendant search is applied
to a list path.

Appending to a derivation requires a fresh top-level name. A complete parameter
case path also requires distinct top-level names across its shared prefix and
suffix. Repeated child names are fine when their full move paths differ.

Mathematical occurrence IDs and move addresses are different kinds of identity:

* An occurrence ID identifies mathematical material across elementary rewrites.
* A move address identifies an authored step within the derivation hierarchy.
* A visual working copy has a separate rendering identity.

Wrapping unchanged named elementary operations in `steps` does not rename those
operations or alter their mathematical revision/occurrence lineage. Hierarchy
is stored alongside the elementary trace, not by pretending that a composite is
an additional algebraic rewrite.

## 6. Inspecting applied moves

```racket
(derivation-tree solution)
(derivation-step-paths solution)

(define move (derivation-node-at solution 'isolate-term))
(derivation-node-before move)
(derivation-node-after move)
(derivation-node-path move)
(derivation-node-children move)
(derivation-node-relation move)
(derivation-node-verification move)

(after solution 'isolate-term)
(after solution '(isolate-term cancel-five))
(derivation-step solution '(isolate-term cancel-five))
```

`derivation-tree` returns the ordered root nodes. Every `derivation-node?` is one
of two kinds:

| Node | `derivation-node-children` | `derivation-node-step` |
| --- | --- | --- |
| Elementary leaf | Empty list | The original `rewrite-step?` |
| Composite move | Nonempty ordered child list | `#f` |

The node's before/after states are the exact endpoints of its elementary
subsequence. `after` accepts either kind of node. `derivation-step` intentionally
rejects a composite; use `derivation-node-at` to inspect the move instead.

`derivation-steps` still returns the flat chronological list of original primitive
rewrites. `derivation-states` still enumerates elementary checkpoints. Moves add
neither fabricated checkpoints nor duplicate states.

For cases, prepend branch names when selecting a branch-specific node:

```racket
(derivation-node-at general-solution '(ordinary isolate-x))
(derivation-step general-solution '(ordinary isolate-x divide-a))
```

Shared-prefix nodes may be addressed directly in the case tree's prefix scope.
A bare symbol never silently selects one of several parameter branches. A
case-qualified local-name shorthand is retained for existing flat callers; full
move paths are preferable in new authoring code. An address that could mean both
a shared move and a branch is rejected; rename the conflicting scope.

## 7. Relationship and verification are separate

`derivation-node-relation` summarizes the kinds of elementary relationships. A
single kind is retained. A mixture of expression and equation equivalences is
reported as `equivalence`; equivalences plus implications are `implication`;
equivalences plus specializations are `specialization`. A mixture that cannot
safely be classified that way, including implication plus specialization, is
`mixed`.

`derivation-node-verification` combines the existing leaf evidence in order. A
move can have established checks while its relationship is only `implication` or
`mixed`. “Established” is not a claim that its endpoint equations have identical
solution sets, and is not a proof-assistant certificate.

Conditions are checked at each actual input state. Dividing by `a` inside a recipe
still requires `a != 0`. A branch guard may establish that condition; a recipe
cannot silently assume it. In strict mode unresolved requirements fail. Draft
mode retains unresolved evidence and the existing visible-warning requirement.
Refuted requirements remain errors in both modes.

Mathematical errors raised while applying a primitive retain their existing error
code and include the complete leaf address in the diagnostic. Grouping does not suppress a failed primitive.

## 8. Presentation groups from structure

```racket
(present solution #:groups 'top-level) ; one group per root node
(present solution #:groups 'steps)     ; one group per elementary rewrite
(present solution)                    ; defaults to top-level structure
```

For a flat derivation, the new default is the old default: every root is already
an elementary step. For a structured derivation, the default follows its outer
moves. Every descendant step still animates.

Explicit groups accept elementary or composite references. A composite expands
to its leaves before validation:

```racket
(present solution #:groups '((isolate-term) (isolate-x)))
(present solution #:groups '((isolate-term isolate-x)))
(present solution
  #:groups '(((isolate-term subtract-five))
             ((isolate-term cancel-five) (isolate-term evaluate-twelve))
             (isolate-x)))
```

The flattened result must partition **every** elementary step exactly once and
in its original order. Missing, duplicated, reordered, overlapping, empty, or
unknown selections are errors. No step is silently skipped or simplified.

`#:history 'keep-all-checkpoints` continues to retain elementary checkpoints,
regardless of the requested larger group partition. This deliberately does not
remove intermediates. A compact history is not an abbreviated proof.

For multiple cases, `'top-level` and `'steps` apply to every complete path. A
case-path hash can choose a mode or explicit groups for each case. Missing hash
entries use the top-level default; unknown case-path keys are errors.

With `#:case-layout 'shared-prefix`, grouping is first validated against complete
case paths and then projected onto displayed prefix/suffix segments. Shared
prefix groups must agree in all descendants. The general quadratic now needs
only:

```racket
(present solution #:case-layout 'shared-prefix #:groups 'top-level)
```

There is no separate repeated `prefix-groups` table. Selecting one case restores
its mathematical prefix and its effective phase overrides.

## 9. Choreography addresses elementary actions

```racket
(choreograph plan
  [(isolate-term cancel-five)
   (retire-cancelled #:duration 2/5 #:layout 'hold)
   (hold 1/2)
   (compact #:duration 2/5)])
```

Override specificity, from highest to lowest, is:

1. A complete case path followed by a move/leaf path.
2. A derivation-relative move/leaf path, shared across applicable cases.
3. An unambiguous local leaf-name shorthand.
4. The existing safe typed-transition defaults.

For example, `(ordinary isolate-x divide-a)` overrides only that case, whereas
`(isolate-x divide-a)` can apply to every case containing exactly that relative
leaf address. A bare label that matches different relative paths is rejected.
A path with conflicting case-qualified and relative interpretations is rejected.

Specificity does not depend on hash iteration or override declaration order.
Adding a broad shorthand override later does not erase an existing more-specific
path override. Use the same precise address to replace that override.

A composite move is not an elementary phase target. This release does not invent
whole-move duration scaling or distribute one primitive phase sequence among
several mathematical operations. Address its children explicitly.

The safe defaults are unchanged: cancellations retire material before compaction;
arithmetic evaluation replaces its entire focus; root copies appear at their
destinations; additive reorderings retire/reveal the whole affected focus.
Rendered parentheses, fraction bars and separators keep their existing ownership.
The cancellation, replacement, root-split, and case-handoff fixes remain in place.

## 10. Explanations remain presentation, not proof

An explanatory formula does not advance the working equation:

```racket
(choreograph quadratic-plan
  [(complete-square add-nine)
   (explain-math '(= (expt (/ 6 2) 2) 9)
                 #:caption "Half the coefficient of x, then square it"
                 #:duration 2)
   (prepare-space #:duration 11/25)
   (reveal-created #:duration 9/25)])
```

The inset remains separately prepared. Its content is author supplied; displaying
it is not a mathematical verification operation.

## 11. The four migrated examples

| Example | Top-level moves and branch organization | Duration retained |
| --- | --- | ---: |
| `linear-concrete` | `isolate-term`, `isolate-x` | 10.8 s |
| `linear-general` | Two moves in the ordinary case; one classification move in each degenerate case | 18.0 s |
| `quadratic-concrete` | `isolate-terms`, `complete-square`, `take-roots`, `isolate-x` | 17.6 s |
| `quadratic-general` | Three shared completing-square moves; discriminant branches and original degenerate cases | 51.9 s |

Every example retains its original primitive operation names, order, held states,
contexts, evidence, occurrence trace, timings, and scene-construction choices.
The new hierarchy changes authoring and addresses, not the lesson's mathematics.

## 12. Rendering and inspection

From the repository root:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

"$RACKET" math/examples/linear-concrete.rkt --tree
"$RACKET" math/examples/linear-concrete.rkt --steps
"$RACKET" math/examples/quadratic-general.rkt --list-cases
"$RACKET" math/examples/quadratic-general.rkt --tree --case quadratic/two-real-roots

"$RACKET" math/examples/linear-concrete.rkt \
  --dark --workers 10 \
  --mp4 math-output/moves/linear-concrete.mp4 \
  math-output/moves/frames/linear-concrete
```

`--tree`, `--steps`, and `--list-cases` return before native module loading,
preparation, typesetting, output mutation, or worker creation. Lesson source
callbacks retain their fixed two-/three-argument generic loader contracts through
lazy adapters. The runtime adapter's import closure is declared explicitly as a
preparation dependency, so the lazy boundary does not hide its source identity.

Rendering still uses the parent repository's project executor. The parent
prepares formulas/layout once. Workers consume the portable prepared plan and
compile ordinary native scenes. No process scheduler, frame evaluator, or CAS
execution framework is added here.

The portable math payload is versioned as `animate-math-prepared-plan-v2`; it
includes the move hierarchy, canonical leaf addresses, and existing prepared
layouts. Stale v1 payloads are rejected rather than reinterpreted. SVG
canonicalization, artifact verification and shared worker support are retained.

## 13. Validation commands and boundaries

```sh
"$RACKET" math/run-tests.rkt
"$RACKET" math/run-style-checks.rkt
"$RACKET" math/run-process-contracts.rkt

# Actual native rendering, including flat-versus-structured pixel comparison:
"$RACKET" math/run-probes.rkt --dark --compare-flat math-output/moves/probes
```

`run-process-contracts.rkt` uses eight real Racket processes to produce and consume
four serialized prepared-plan payloads. Its native geometry is explicitly
synthetic: it verifies independent reconstruction, not rasterizer performance or
actual process rendering. The last command requires the installed Animate,
LaTeX, and dvisvgm pipeline and compares actual intermediate pixels against the
frozen flat lesson declarations.

See `validation.md` for the checks actually performed in this delivery.

## 14. Deliberate limits

This release does not add an automatic tutor, infix parser, GUI inspector,
automatic recipe lifting over alternatives, composite-level phase overrides,
simultaneous branch-column layout, proof assistant, new CAS, or new renderer.
Flat APIs remain available, while new hierarchical inspection gives tools and
advanced authors a precise extension surface.
