# Animating Mathematical Expressions with `animate`
## Proposed user guide — version 0.1

**Status:** design for discussion, not an implemented package. All APIs introduced in this guide are proposed. The Racket snippets describe the intended authoring experience; they are not runnable against the current library. Nothing in this guide requires changing the `animate` repository yet.

The system turns explicitly chosen mathematical steps into animations that explain those steps. Its primary mathematical data is ordinary `racket-cas`-compatible S-expressions. Occurrence identities, justifications, assumptions, and visual presentation live alongside that data rather than inside a competing expression algebra.

A mathematical derivation determines **what changes and why**. A presentation determines **how viewers see that change**. Neither is the other.

## Contents

1. What you author
2. Expressions that preserve what you wrote
3. Selecting mathematical parts
4. Rewrites, correspondence, and mathematical validity
5. Constructing a derivation
6. Presenting a derivation
7. Concrete linear equation
8. General linear equation
9. Concrete quadratic equation
10. General quadratic equation
11. Defining your own rewrite rules
12. Using `racket-cas` and Calcura
13. Rendering, inspection, and reproducibility
14. Decisions proposed for discussion
15. Source notes

---

## 1. What you author

You normally author three things:

| Object | Meaning |
|---|---|
| Mathematical state | An expression together with its context and occurrence identities. |
| Derivation | Named applications of mathematical rules, possibly branching. |
| Presentation | Layout, retained lines, visual effects, timing, and pauses. |

For example:

```racket
;; Proposed API throughout this guide.
(require animate/math)

(define problem
  (math '(= (+ (* 3 x) 5) 17)
        #:id 'linear-example
        #:context (math-context #:real '(x))))

(define working
  (derive problem
    [subtract-five (both-sides 'subtract 5)]
    [cancel-five   (cancel-addends #:at (lhs))]
    [evaluate-rhs  (evaluate #:at (rhs))]))
```

This describes the checkpoints

\[
3x+5=17
\quad\longrightarrow\quad
3x+5-5=17-5
\quad\longrightarrow\quad
3x=17-5
\quad\longrightarrow\quad
3x=12.
\]

It does not yet say whether the original equation remains above the working line, whether the new terms fade in, or how long cancellation takes.

```racket
(define plan
  (present working
           #:style (math-presentation
                     #:anchor 'relation
                     #:history 'keep-completed-groups
                     #:start-group 'copy)
           #:groups '((subtract-five cancel-five evaluate-rhs))))
```

Here the three mathematical steps form one presentation group. The original line remains visible; its copy becomes the working line. The group finishes with a retained line reading `3x = 12`.

**The system is author-directed.** It may calculate, validate, or suggest a step, but it does not silently choose the lesson's algebraic route.

### Relationship to existing work

MF_Algebra's expression/action/timeline design is the closest reference: it already separates expression structure from actions and obtains visual correspondence from algebraic templates. This proposal keeps those ideas, but separates derivations from playback and adds typed provenance and validity conditions. [S1]

The new layer also builds on `animate`, rather than creating another animation engine. The existing `formula-derivation` already packages anchored, author-supplied formula transitions; its source explicitly excludes mathematical parsing and validation. This proposal supplies that missing mathematical layer and lowers its output to the existing formula and scene facilities. [S2]

## 2. Expressions that preserve what you wrote

### 2.1 Mathematical data

The initial supported vocabulary consists of numbers, symbols, arithmetic applications, equations, inequalities, and Boolean combinations. The representation follows `racket-cas`, whose expressions are ordinary Racket data. [S3]

```racket
'(+ (* 3 x) 5)
'(- 17 5)
'(/ (* 3 x) 3)
'(expt (+ x 3) 2)
'(= (+ (* a (expt x 2)) (* b x) c) 0)
'(or (= x -5) (= x -1))
```

`(* 3 x)` represents multiplication. The symbol `3x` would be a single name, not a product.

`math` receives a datum and creates an immutable **mathematical state**. The datum remains available through `math-datum`. The state adds a context and an occurrence table; it does not replace the datum with a hierarchy of sum/product/fraction classes.

### 2.2 No implicit normalization

These are deliberately different displayed expressions:

```racket
'( + x x )
'(* 2 x)
'(* 1 x)
'x
```

Their relationships can be understood mathematically without destroying their displayed form. In particular, `math` does not sort terms, collect coefficients, remove zeroes, simplify fractions, evaluate arithmetic, or collapse a true equation to `#t`.

This differs from `racket-cas`'s smart constructors. Its `⊕`, `⊗`, and power constructors simplify during construction: equal terms can merge, repeated factors can become powers, and neutral elements can disappear. [S4]

The authoring distinction is therefore:

```racket
(math '(+ 5 -5))         ; retain both displayed terms
```

versus an explicitly requested CAS calculation whose result is `0`.

Do not load `racket-cas/repl`'s quote-rebinding convenience into a display-preserving authoring module. Once data has been normalized before `math` receives it, the original structure is already gone. [S5]

**Correction to our earlier discussion:** `subst` with `#:normalize? #f` is not a general structure-preserving substitution operation. It skips the final `normalize` call, but still reconstructs sums, products, powers, and relations using simplifying constructors internally. Our held substitution therefore needs its own documented behavior. [S6]

### 2.3 Notation is separate from algebra

A presentation can show `(* 3 x)` as `3x` and `(* 1 x)` as `1·x`. It can use a fraction bar for `(/ u v)`, retain parentheses, or display a negative addend as subtraction.

However, changing `(+ x x)` into `(* 2 x)` is a mathematical rewrite, not a typography setting.

Formatting may introduce visible parts that are not operand nodes: a plus sign, fraction bar, pair of parentheses, or radical. These parts receive role-based visual identities associated with the mathematical occurrence. A number such as `17` may produce multiple glyphs but remains one mathematical occurrence.

The first version covers scalar algebra. An unfamiliar function can be displayed without pretending that its algebraic properties are known. Bound-variable operations involving integrals, sums, or substitutions under binders require later, explicit binding semantics.

## 3. Selecting mathematical parts

Selectors locate parts in the **current input state of a step**.

```racket
(lhs)
(rhs)
(numerator (lhs))
(denominator (rhs))
(at-path '(0 1))
(matching 'x #:occurrence 2)
```

Operand paths are zero-based and exclude the operator symbol. Explicit occurrence ordinals are one-based in display-tree traversal order. For example, in

```racket
'(= (+ (* 3 x) 5) 17)
```

path `(0)` is the left-hand side, `(0 0)` is `3x`, and `(0 1)` is `5`.

A selector that must identify one object reports an error when it matches zero or multiple candidates. It never silently chooses the first `x` in `x+x+x`. An explicit `all-matching` selector can select several occurrences.

An occurrence handle identifies a specific occurrence in a specific state. Across a step, the trace tells you whether that occurrence survives, is copied, merges with others, or disappears. Following a copied handle can yield several descendants; using it where a unique descendant is required is an ambiguity, not an arbitrary selection.

### Expression identity is not occurrence identity

The three occurrences of `x` in `(+ x x x)` share a mathematical value but have different occurrence identities.

There is a further distinction when retaining derivation lines: two views can display the same state. Copying an equation onto a new working line creates new **view instances**, not new algebraic facts. Rewriting `a(b+c)` into `ab+ac`, by contrast, creates two algebraic descendant occurrences of `a`.

Paths identify locations within a snapshot. Stable IDs and lineage identify continuity between snapshots. Neither structural equality nor object-address equality is a substitute for lineage.

## 4. Rewrites, correspondence, and mathematical validity

### 4.1 What a step records

An applied step contains its name, before/after states, rule, selected focus, pattern bindings, occurrence correspondence, context, validity relationship, and evidence or unresolved obligations.

Correspondence is typed. The core relations are **preserve, copy, merge, split, create, remove, cancel, evaluate, and reorder**. A general replacement is available when a more explanatory relation is unavailable.

For instance, distributing `a(b+c)` records the duplication of `a`; evaluating `17-5` records that the whole arithmetic expression produces `12`. It must not claim that the old digit `7` mathematically becomes the new digit `2`.

A semantic cancellation and its visual treatment are different. The same cancellation can be shown by fading terms, crossing them out temporarily, or highlighting them before removal.

### 4.2 Different mathematical relationships

The system distinguishes:

| Relationship | Example | Interpretation |
|---|---|---|
| Expression equivalence | `a(b+c) → ab+ac` | Equal values on the declared domain. |
| Equation equivalence | Subtract 5 from both sides | Same solution set in the stated variable and context. |
| Implication | `x=2 → x²=4` | Every old solution satisfies the new equation, not conversely. |
| Specialization | Substitute `x=4` in the original equation | Evaluate a candidate or parameter choice; not an equivalent equation-solving step. |
| Case split | Separate `a=0` from `a≠0` | Restrict different branches and justify their coverage. |

Numeric spot checks can find counterexamples, but are not proofs of symbolic equivalence. Checking candidate roots in the original equation establishes that they are solutions; it does not establish that the list is complete.

### 4.3 Conditions are never silently added

```racket
(both-sides 'divide 'a)
```

requires `a ≠ 0` for equivalence. If the context cannot establish this, the proposed default is to report a pending obligation and stop treating the step as a verified equivalence.

The author can put the condition in the initial problem, create separate cases, or keep the step explicitly marked as conditional during drafting. A validated final presentation cannot silently suppress the condition.

The distinction is equally important for domain preservation. Cancelling `x/x` produces `1` only while retaining the exclusion `x ≠ 0`. The result is not suddenly defined at the excluded point.

### 4.4 Verification is not a Boolean shortcut

A check reports **established, refuted, or unknown**, together with the proposition checked and its evidence. Conditional results retain explicit obligations. An inconsistent context is diagnosed separately rather than used to justify arbitrary steps.

Evidence can come from a built-in law, exact arithmetic/polynomial checking, a recorded CAS result, or an author assertion. A CAS-supported claim is labeled as such; it is not automatically a formal proof certificate. Author assertions remain visibly unverified unless independently discharged.

### 4.5 Two kinds of branching

**Parameter cases** introduce different assumptions, such as `a=0` and `a≠0`. They use `derive-cases`.

**Solution alternatives** describe several solutions within one context, such as `x=2 or x=-2`. Their mathematical datum is an `or` expression; `each-branch` lifts an operation across its direct alternatives.

These are not interchangeable. A two-root formula does not introduce two contradictory parameter assumptions.

## 5. Constructing a derivation

```racket
(derive initial-state
  [step-name operation]
  [next-name operation])
```

`derive` is proposed as a builder macro. Each operation sees the previous output state. The input may also be an existing derivation, in which case its endpoint becomes the continuation's input. The original state and earlier steps remain immutable.

Step labels are unique within their branch scope and provide stable references for presentation and inspection. A nested reference includes its case path, such as `(two-real-roots subtract-b)`. `derivation-step` retrieves an applied step; `after` retrieves its output state. Continuing an existing derivation or splitting its endpoint retains the shared prefix by reference.

The initial operation vocabulary is intentionally small:

| Operation | Effect and boundary |
|---|---|
| `both-sides` | Add, subtract, multiply, or divide by an explicitly supplied expression. Retain the operation on both sides. |
| `cancel-addends` | Remove a specified or uniquely identifiable additive inverse pair in the selected region. |
| `cancel-factor` | Cancel an explicitly named common factor; optionally retain `1·u`. Requires the factor to be nonzero. |
| `remove-unit` | Remove an explicit multiplicative identity, as its own step. |
| `reduce-identities` | Apply the declared zero/unit/sign identity rules within a focus, recording their substeps. No general sorting or collection. |
| `evaluate` | Evaluate numeric arithmetic in the focus. Does not decide an entire equation's truth. |
| `rewrite-to` | Reach an author-specified target using a named rule or bounded, documented rule sequence. |
| `reorder-addends` | Reorder signed terms explicitly, carrying their signs and occurrence identities. |
| `zero-product` | Replace a real scalar product equation equal to zero by its factor alternatives. |
| `square-solutions` | Handle a real equation `u²=v`, with the appropriate sign case for `v`. |
| `abbreviate` | Replace a focus by a locally defined mathematical name, retaining its definition. |
| `each-branch` | Apply an operation separately to each direct solution alternative. |

Rules do not opportunistically normalize the rest of the equation. Their focus and named scope are part of their contract.

A target-directed example is:

```racket
(rewrite-to '(expt (+ x 3) 2)
            #:at (lhs)
            #:using 'perfect-square)
```

This asks for a particular square, not any expression that happens to be equivalent. The named rule must justify its application and supply a compatible explanation trace. Merely receiving “equivalent” from a CAS does not reconstruct that trace.

`'expand-products` is a documented composite rule: it distributes products and collects the resulting monomial coefficients within the requested focus. Its elementary substeps remain inspectable. Such composites make source code manageable without turning the system into an unrestricted simplifier.

## 6. Presenting a derivation

### 6.1 Presentation groups and retained lines

A presentation group is a sequence of adjacent mathematical steps that should be treated as one line of a worked solution.

```racket
(present derivation
         #:style classroom
         #:groups '((subtract-five cancel-five evaluate-twelve)
                    (divide-three reduce-left remove-one evaluate-four)))
```

When supplied, groups must partition all steps once, in order. When `#:groups` is omitted, the default is one group per step. With `keep-completed-groups`, the initial state and group endpoints remain on screen. Intermediate states still appear on the working line but do not each consume another permanent row.

An alternative history mode, `keep-all-checkpoints`, retains every mathematical checkpoint. A `replace` mode uses one line only.

These choices affect presentation, not the stored derivation.

### 6.2 Classroom presentation

```racket
(define classroom
  (math-presentation
    #:anchor 'relation
    #:history 'keep-completed-groups
    #:start-group 'copy
    #:new-parts 'fade
    #:removed-parts 'fade
    #:reflow 'staged
    #:multiplication 'school
    #:pause-between-groups 0.6))
```

The equality sign remains fixed within a working line. New groups receive a new row with the same horizontal relation alignment. A branch layout can allocate separate rows or columns with explicit anchors.

“Staged reflow” means removal and closing the gap are separate phases. During cancellation, the terms fade while the surrounding layout is held. A subsequent compaction phase moves the surviving terms. This prevents the surviving `3x` from drifting while `+5-5` is disappearing.

Visible fraction bars are real formula parts, not text approximations. The `keep-one?` cancellation option requests an explicit `1·x` checkpoint even when the surrounding school notation normally uses juxtaposition.

### 6.3 Overriding the choreography

```racket
(define tuned-plan
  (choreograph plan
    [subtract-five
      (prepare-space #:duration 0.5)
      (reveal-created #:effect 'fade #:duration 0.4)]
    [cancel-five
      (retire-cancelled #:effect 'fade
                        #:layout 'hold
                        #:duration 0.4)
      (hold 0.5)
      (compact #:duration 0.4)]))
```

Each named entry replaces that step's default visual phases. Group copying is a separate prelude managed by `present`. Mathematical operations, their order, and their validity cannot be changed by a choreography override.

`prepare-space` lays out the destination geometry but keeps created parts invisible. `reveal-created` introduces the trace's newly created parts. Retirement phases retain outgoing drawables temporarily; `compact` releases their reserved space. These are presentation objects, not malformed intermediate equations fed to the CAS.

Pauses and durations are presentation values. A named phase can later be synchronized with a narration cue without making voice-over a dependency of the mathematical layer.

### 6.4 Checkpoints versus intermediate frames

Only mathematical checkpoints assert complete mathematical statements. A halfway-faded cancellation or morphing glyph is not a new theorem. At every committed checkpoint the exact requested expression, notation, and context must be restored.

---

## 7. Concrete linear equation

### Goal

Find every real number which makes

\[
3x+5=17
\]

true. Isolating `x` is the method; preserving the solution set is what justifies the method.

### Authoring the solution

```racket
(define linear-problem
  (math '(= (+ (* 3 x) 5) 17)
        #:id 'concrete-linear
        #:context (math-context #:real '(x))))

(define linear-solution
  (derive linear-problem
    [subtract-five (both-sides 'subtract 5)]
    [cancel-five   (cancel-addends #:at (lhs))]
    [evaluate-twelve (evaluate #:at (rhs))]

    [divide-three (both-sides 'divide 3)]
    [reduce-left  (cancel-factor #:at (lhs)
                                 #:factor 3
                                 #:keep-one? #t)]
    [remove-one   (remove-unit #:at (lhs))]
    [evaluate-four (evaluate #:at (rhs))]))

(define linear-plan
  (present linear-solution
           #:style classroom
           #:groups '((subtract-five cancel-five evaluate-twelve)
                      (divide-three reduce-left remove-one evaluate-four))))
```

### Mathematical checkpoints

\[
\begin{aligned}
3x+5&=17\\
3x+5-5&=17-5\\
3x&=17-5\\
3x&=12\\[2pt]
\frac{3x}{3}&=\frac{12}{3}\\
1\cdot x&=\frac{12}{3}\\
x&=\frac{12}{3}\\
x&=4.
\end{aligned}
\]

### What the viewer sees

First retain the original equation and create a working copy. Keep its equals sign fixed. Make room for `−5` on the left, and reserve the corresponding room on the right. Fade in the two `−5` terms together. Fade out `+5−5` without closing the gap. Pause, move `3x` to its new position, and then evaluate `17−5` to `12`.

For division, create the next working copy and form the two fractions. Reduce the left side to `1·x`, remove `1·` in a separate fade, pause, and only then evaluate `12/3`.

These choices are explicitly adjustable; none require changing the algebraic derivation. For example, the pause after removing `1·` can be adjusted independently:

```racket
(define linear-plan-with-pause
  (choreograph linear-plan
    [remove-one
      (retire-removed #:effect 'fade
                      #:layout 'hold
                      #:duration 0.3)
      (hold 0.5)
      (compact #:duration 0.3)]))
```

### Checking the answer

```racket
(define linear-check
  (check-solution linear-problem #:for 'x #:value 4))
```

This creates a separate checking derivation from the original equation:

\[
3\cdot4+5=17
\quad\longrightarrow\quad
12+5=17
\quad\longrightarrow\quad
17=17.
\]

The check should display the final equality and a truth annotation, rather than unexpectedly replacing it with `#t`. Internally the truth result is recorded.

The check establishes that `4` works. The equivalence-preserving solving derivation establishes that there are no other solutions.

## 8. General linear equation

We now solve

\[
ax+b=c,\qquad a,b,c,x\in\mathbb R.
\]

### 8.1 The ordinary case: `a ≠ 0`

The same operations give

\[
\begin{aligned}
ax+b&=c\\
ax+b-b&=c-b\\
ax&=c-b\\
\frac{ax}{a}&=\frac{c-b}{a}\\
1\cdot x&=\frac{c-b}{a}\\
x&=\frac{c-b}{a}.
\end{aligned}
\]

Unlike the concrete example, `c-b` is not evaluated numerically. It remains an expression.

### 8.2 The complete parameter classification

The proposed case-building syntax can express the entire result:

```racket
(define general-linear-problem
  (math '(= (+ (* a x) b) c)
        #:id 'general-linear
        #:context (math-context #:real '(a b c x))))

(define general-linear-solution
  (derive-cases general-linear-problem
    [ordinary '(not (= a 0))
      [subtract-b (both-sides 'subtract 'b)]
      [cancel-b   (cancel-addends #:at (lhs))]
      [divide-a   (both-sides 'divide 'a)]
      [reduce-a   (cancel-factor #:at (lhs)
                                 #:factor 'a
                                 #:keep-one? #t)]
      [remove-one (remove-unit #:at (lhs))]]

    [identity '(and (= a 0) (= b c))
      [all-values (conclude 'all-real #:for 'x)]]

    [inconsistent '(and (= a 0) (not (= b c)))
      [no-values (conclude 'no-solutions #:for 'x)]]))
```

`derive-cases` attaches each guard to that branch's context. The ordinary branch therefore has the nonzero condition needed by `divide-a`.

`conclude` requests a checked classification. It is not an unchecked author assertion. Here it can reduce the equation under `a=0` to `b=c`, and use the branch's equality or inequality condition. If the classification cannot be established, it returns a diagnostic instead of a claimed result.

| Conditions | Complete real solution set |
|---|---|
| `a ≠ 0` | `{(c-b)/a}` |
| `a = 0` and `b = c` | All real numbers |
| `a = 0` and `b ≠ c` | No solutions |

These guards are mutually exclusive and exhaustive over the declared real parameters. The system records this coverage. Arbitrary user-written case splits must establish coverage before being advertised as a complete solution.

### 8.3 Presentation

Show `a ≠ 0` before the division step, not as a footnote after it. Keep that condition attached to the final formula.

The degenerate cases should visibly reduce the equation to `b=c`. Then show either “every real x” or “no real x.” They should not attempt to divide by zero and repair the result afterward.

Changing a parameter in a later interactive version must reselect or rebuild the applicable branch; it cannot reuse a derivation whose assumptions have become false.

## 9. Concrete quadratic equation

For the first quadratic example we use completing the square:

\[
x^2+6x+5=0,\qquad x\in\mathbb R.
\]

This illustrates an introduced term, a many-part rewrite into a square, solution alternatives, and a separate check of each result.

### 9.1 Constructing the square

```racket
(define quadratic-problem
  (math '(= (+ (expt x 2) (* 6 x) 5) 0)
        #:id 'concrete-quadratic
        #:context (math-context #:real '(x))))

(define quadratic-solution
  (derive quadratic-problem
    [subtract-five (both-sides 'subtract 5)]
    [cancel-five   (cancel-addends #:at (lhs))]
    [negative-five (evaluate #:at (rhs))]

    [add-nine      (both-sides 'add 9)]
    [make-square   (rewrite-to '(expt (+ x 3) 2)
                               #:at (lhs)
                               #:using 'perfect-square)]
    [evaluate-four (evaluate #:at (rhs))]

    [split-roots   (square-solutions)]
    [evaluate-roots (each-branch (evaluate #:at (rhs)))]
    [subtract-three (each-branch (both-sides 'subtract 3))]
    [cancel-three   (each-branch (cancel-addends #:at (lhs)))]
    [evaluate-answers (each-branch (evaluate #:at (rhs)))]))
```

The main checkpoints are

\[
\begin{aligned}
x^2+6x+5&=0\\
x^2+6x+5-5&=0-5\\
x^2+6x&=-5\\
x^2+6x+9&=-5+9\\
(x+3)^2&=4.
\end{aligned}
\]

The displayed explanation for adding `9` can be “Half of 6 is 3; add its square to both sides.” This explanation can itself contain a small mathematical object showing `(6/2)^2=9`; it need not be embedded into the equation's transformation rule.

### 9.2 Taking square roots without losing a solution

`square-solutions` creates the alternatives

\[
x+3=\sqrt4\quad\text{or}\quad x+3=-\sqrt4.
\]

`evaluate-roots` makes these

\[
x+3=2\quad\text{or}\quad x+3=-2.
\]

The final three operations run independently on both alternatives:

\[
x+3-3=2-3
\quad\text{or}\quad
x+3-3=-2-3,
\]

and produce

\[
x=-1\quad\text{or}\quad x=-5.
\]

The complete real solution set is therefore `{-5, -1}`. Sets are unordered; the presentation may preserve branch order without changing that mathematical result.

### 9.3 Choreography

Keep the square checkpoint in place before branching. Duplicate it into two branch views, then reveal the positive- and negative-root alternatives. Do not animate a single square root as though it supplied both signs automatically.

The rewrite into `(x+3)^2` should be described as a square identity. The trace maps whole participating subexpressions and records the newly created exponent and parentheses. It does not pretend that two separate written `x` glyphs existed in the original expanded polynomial merely because they occur in a possible expansion of the destination.

An optional explanatory inset may expand `(x+3)(x+3)` to demonstrate the identity. That is a separate derivation, not invented occurrence history for the main line.

### 9.4 Checking both candidates

```racket
(define check-minus-one
  (check-solution quadratic-problem #:for 'x #:value -1))

(define check-minus-five
  (check-solution quadratic-problem #:for 'x #:value -5))
```

The checks reach

\[
1-6+5=0,
\qquad
25-30+5=0,
\]

and then `0=0` in each case.

Again, checking the candidates confirms membership. Completeness comes from the equivalence of the square equation with its two alternatives, together with the preceding reversible steps.

### 9.5 Choosing a different method

The same problem also admits

\[
x^2+6x+5=(x+1)(x+5),
\]

followed by the zero-product rule. A pedagogically explicit factoring derivation could show

\[
x^2+x+5x+5
\to x(x+1)+5(x+1)
\to (x+1)(x+5).
\]

An author can choose this route instead. The system must not switch from completing the square to factoring simply because a CAS finds the factorization first.

## 10. General quadratic equation

We now derive the quadratic formula for

\[
ax^2+bx+c=0,\qquad a,b,c,x\in\mathbb R.
\]

The quadratic branch assumes `a ≠ 0`. Degenerate cases are covered separately below.

### 10.1 Why use the scaled-square route?

We will construct

\[
(2ax+b)^2=b^2-4ac.
\]

This avoids introducing a square root of `a²` in the derivation. In particular, no step needs the generally false replacement `sqrt(a²) → a`; over the reals the correct expression is `|a|`.

Multiplication by `4a` preserves equivalence because this branch already knows `a ≠ 0`. The only final division is by `2a`, with the same explicit condition.

### 10.2 Constructing the discriminant checkpoint

```racket
(define quadratic-context
  (math-context
    #:real '(a b c x)
    #:assuming '((not (= a 0)))
    #:definitions '((Δ (- (expt b 2) (* 4 a c))))))

(define general-quadratic-problem
  (math '(= (+ (* a (expt x 2)) (* b x) c) 0)
        #:id 'general-quadratic
        #:context quadratic-context))

(define completed-square
  (derive general-quadratic-problem
    [subtract-c (both-sides 'subtract 'c)]
    [cancel-c   (cancel-addends #:at (lhs))]
    [negative-c (reduce-identities #:at (rhs))]

    [multiply-four-a (both-sides 'multiply '(* 4 a))]
    [expand-products
      (rewrite-to
        '(= (+ (* 4 (expt a 2) (expt x 2)) (* 4 a b x))
            (* -4 a c))
        #:using 'expand-products)]

    [add-b-squared (both-sides 'add '(expt b 2))]
    [make-square
      (rewrite-to '(expt (+ (* 2 a x) b) 2)
                  #:at (lhs)
                  #:using 'perfect-square)]
    [order-rhs (reorder-addends #:at (rhs) #:order '(1 0))]
    [name-discriminant (abbreviate 'Δ #:at (rhs))]))
```

A context definition is not an unrelated new variable. `Δ` has the scoped definition `b²-4ac`; the checker expands it when necessary. Definitions must be acyclic, and the presentation must expose the definition before relying on the abbreviation.

The main mathematical checkpoints are

\[
\begin{aligned}
ax^2+bx+c&=0\\
ax^2+bx&=-c\\
4a(ax^2+bx)&=4a(-c)\\
4a^2x^2+4abx&=-4ac\\
4a^2x^2+4abx+b^2&=-4ac+b^2\\
(2ax+b)^2&=b^2-4ac\\
(2ax+b)^2&=\Delta.
\end{aligned}
\]

As with the concrete examples, subtraction and cancellation are separate recorded steps even where this printed overview omits a temporary line.

### 10.3 Splitting into discriminant cases

```racket
(define general-quadratic-solution
  (derive-cases completed-square
    [two-real-roots '(> Δ 0)
      [split (square-solutions)]
      [subtract-b (each-branch (both-sides 'subtract 'b))]
      [cancel-b   (each-branch (cancel-addends #:at (lhs)))]
      [divide-two-a
        (each-branch (both-sides 'divide '(* 2 a)))]
      [cancel-two-a
        (each-branch
          (cancel-factor #:at (lhs)
                         #:factor '(* 2 a)
                         #:keep-one? #f))]
      [order-numerators
        (each-branch
          (reorder-addends #:at (numerator (rhs))
                           #:order '(1 0)))]]

    [one-real-root '(= Δ 0)
      [single-root (square-solutions)]
      [subtract-b (both-sides 'subtract 'b)]
      [cancel-b   (cancel-addends #:at (lhs))]
      [divide-two-a (both-sides 'divide '(* 2 a))]
      [cancel-two-a
        (cancel-factor #:at (lhs)
                       #:factor '(* 2 a)
                       #:keep-one? #f)]
      [reduce-numerator (reduce-identities #:at (numerator (rhs)))]]

    [no-real-roots '(< Δ 0)
      [impossible-square (square-solutions)]]))
```

When `Δ > 0`, the square step generates

\[
2ax+b=\sqrt\Delta
\quad\text{or}\quad
2ax+b=-\sqrt\Delta.
\]

Subtracting `b` and dividing by `2a` gives

\[
x=\frac{\sqrt\Delta-b}{2a}
\quad\text{or}\quad
x=\frac{-\sqrt\Delta-b}{2a}.
\]

The final reorder is explicit. It carries each term's sign and produces

\[
\boxed{\displaystyle
x=\frac{-b+\sqrt\Delta}{2a}
\quad\text{or}\quad
x=\frac{-b-\sqrt\Delta}{2a}.}
\]

When `Δ = 0`, `square-solutions` produces only `2ax+b=0`, leading to the single distinct solution

\[
\boxed{x=-\frac{b}{2a}.}
\]

When `Δ < 0`, a real square cannot equal the negative right-hand side, so the branch concludes that there are no real solutions.

### 10.4 Plus/minus is a display of alternatives

A presentation may compact the two compatible branches into

\[
x=\frac{-b\pm\sqrt{b^2-4ac}}{2a}.
\]

Internally the alternatives remain separate. `±` is not passed to a CAS as a mysterious scalar operator. Compaction is allowed only when the paired branches support that notation; repeated sign occurrences must remain correlated within each alternative.

For `Δ = 0`, the presentation must state that there is one distinct root, not advertise two different solutions merely because the compact formula contains two signs.

### 10.5 Complete classification, including `a = 0`

The code above is complete within its initial assumption `a ≠ 0`. For all real coefficients, the outer case tree must also contain the degenerate branches:

| Conditions | Complete real solution set |
|---|---|
| `a ≠ 0`, `Δ > 0` | `{(-b+sqrt Δ)/(2a), (-b-sqrt Δ)/(2a)}` |
| `a ≠ 0`, `Δ = 0` | `{-b/(2a)}` |
| `a ≠ 0`, `Δ < 0` | No real solutions |
| `a = 0`, `b ≠ 0` | `{-c/b}` |
| `a = 0`, `b = 0`, `c = 0` | All real numbers |
| `a = 0`, `b = 0`, `c ≠ 0` | No solutions |

The `a=0, b≠0` branch is a linear-equation derivation, not a special numerical interpretation of the quadratic formula. The same named-rule machinery handles it.

A complex-number lesson would use an explicitly different context and root rule. It must not silently reinterpret the “no real solutions” branch as a claim about all complex solutions.

### 10.6 Presentation suggestions specific to this derivation

Keep the condition `a ≠ 0` visible throughout. Treat introducing `b²` on both sides as a distinct visual event. Use an explanatory brace or temporary comparison to identify the three terms of `(2ax+b)²`.

Show the definition of `Δ` beside the equation before replacing the right-hand side by its name. Present the three sign cases in separate labeled panels or consecutive sections. Within the positive case, animate two solution alternatives. Restore `b²-4ac` in the final formula only as an explicit expansion of the abbreviation.

The main derivation, the discriminant definition, and any explanatory inset have separate mathematical states and view instances. Highlighting matching pieces across them uses explicit links rather than guessing from equal TeX strings.

## 11. Defining your own rewrite rules

The system should support reusable, renderer-independent rules without requiring authors to create a new expression hierarchy.

A proposed declarative rule form is:

```racket
(define-math-rule distribute-left
  #:metavariables (u v w)
  #:from (* u (+ v w))
  #:to   (+ (* u v) (* u w))
  #:in real-scalars
  #:check polynomial-identity)
```

The `from` and `to` clauses are syntax captured by the proposed macro, not expressions evaluated as ordinary Racket multiplication and addition.

The rule captures the occurrence bound to `u`, places descendants into the two result positions, and records a copy relation. The occurrences bound to `v` and `w` each have one result descendant. The checker validates the scalar polynomial identity rather than trusting an arbitrary law name supplied by the author.

Rules with repeated source metavariables, such as collecting `u+u`, require an explicit merge policy or a rule-specific occurrence mapping. Arbitrary many-to-many matches are not resolved by connecting every source to every destination.

The design can reuse Racket's pattern-matching facilities and the ideas in `math-match`. However, existing mathematical match expanders sometimes expose a computed view rather than an actual source subtree. For example, the binary sum matcher can group the remaining operands of an n-ary sum into a synthetic sum. A trace-aware matcher must return occurrence witnesses for such groups, not just the computed value. [S7]

A custom rule must therefore provide or derive three things: its mathematical action, its validity obligations, and its correspondence. Timing, colours, fades, and motion paths belong to a separate presentation recipe.

Rules are versioned. A prepared derivation records the rule version used, so later rule changes do not silently alter an already prepared video.

## 12. Using `racket-cas` and Calcura

### 12.1 The intended division of responsibility

| Component | Responsibility |
|---|---|
| Mathematical authoring layer | Held expressions, selectors, local pedagogical rules, occurrence lineage, conditions, derivations. |
| `racket-cas` adapter | Explicitly requested normalization, arithmetic/symbolic calculations, polynomial services, and useful local checks. |
| Optional Calcura adapter | Heavier symbolic queries, domain/assumption queries, and candidate solution or equivalence checks where its implemented capabilities apply. |
| Presentation adapter | Typesetting, formula-part mapping, choreography, and lowering to `animate`. |

This is a capability-based interface, not an assumption that one backend can answer every query. Missing capabilities, timeouts, undecided results, and conflicting answers remain explicit diagnostics.

The `racket-cas` source supports treating its normalizer and operations as computational services rather than a universal proof engine: its assumptions experiment is commented out, and its solver documents implicit conditions on some inverse operations. [S8]

### 12.2 Explicit backend use

Proposed optional adapters are separate modules:

```racket
(require animate/math/cas/racket-cas
         animate/math/cas/calcura)

(define services
  (math-services
    #:local (racket-cas-service)
    #:extended (calcura-service)))

(verify-derivation general-quadratic-solution
                   #:services services)
```

Loading, constructing, displaying, or sampling an elementary derivation must not require Calcura. Backend calls occur at an explicit calculation or verification boundary, never once per rendered frame.

The adapter receives a projection of the mathematical datum plus its context. It may normalize that projection, but it cannot replace the displayed datum without an explicit rewrite step.

### 12.3 A CAS result is not a pedagogical trace

Suppose a backend factors `x²+6x+5` into `(x+1)(x+5)` but returns no derivation. The system can record a checked **focused replacement**. It cannot honestly claim that the backend followed the factor-by-grouping derivation shown earlier.

The author can choose the focused replacement, provide a rule-based explanation, or insert smaller intermediate steps. Unchanged surroundings retain their identities, while the changed focus receives the correspondence actually justified by the available evidence.

Similarly, normalization can establish a useful equality in a supported algebraic class, but failure to normalize two expressions identically is not a proof that they are unequal. Domain exclusions must be carried independently of any simplifications that erase their original syntax.

### 12.4 Suggested results require an author decision

A future `suggest-steps` facility may rank possible moves or propose targets using either CAS. Accepting a suggestion creates an ordinary, inspectable step. It must not become an invisible automatic solver running whenever an expression is edited.

## 13. Rendering, inspection, and reproducibility

### 13.1 Bind semantics to existing formula parts

The semantic source of truth is the held datum and its occurrence table. A typesetting adapter supplies a mapping from occurrences and operator roles to rendered parts and layout anchors.

The adapter should typeset complete formula contexts so that fractions, scripts, kerning, and spacing remain correct. It should not independently typeset every leaf and assume that concatenating the results reproduces a correctly typeset formula.

A renderer may not be able to recover a reliable glyph map for every construct. The safe response is to animate a larger identified unit or ask for an explicit mapping, with a diagnostic. A fallback must not silently create a false fine-grained mathematical correspondence.

`animate` already exposes formula source maps, formula-part transitions, tagged formulas, and derivation facilities through its main module. These are the intended rendering/animation integration points. [S9]

### 13.2 One scene system

```racket
(define lesson-scene
  (math-plan->scene linear-plan))
```

`math-plan->scene` is a proposed adapter returning an ordinary `animate` scene. There is no separate mathematical renderer, scene timeline, preview application, or video exporter. Embedding a prepared mathematical plan into an existing scene should use the same scene composition mechanisms as other visuals.

The mathematical layer can also expose static checkpoint visuals for ordinary `pict`-based use through an adapter, without making the CAS depend on an animation engine.

### 13.3 Preparation before frame sampling

Before playback or rendering, preparation fixes the expression states, branch contexts, verification results, occurrence correspondence, typesetting outputs, layouts, durations, and phase boundaries.

The prepared plan is immutable. Sampling a time does not rerun rewrites, solve equations, mutate the derivation, or contact a service. This allows deterministic seeking and parallel frame rendering within the same prepared environment.

Cache identities include relevant expression content, context and definitions, rule/backend versions, notation settings, fonts/typesetter settings, and presentation choices. Stable author labels and deterministic local ID allocation support reproducibility; the design does not promise that arbitrary source edits preserve every generated identity.

### 13.4 Inspector information

Selecting a displayed term should reveal its datum, occurrence handle, source path, view instance, producing step, lineage, current mathematical conditions, and presentation phase.

Selecting a step should show its before/after expressions, validity relationship, obligations, evidence, correspondence map, and any coarse replacement or renderer fallback.

Useful diagnostics include:

```text
Step divide-a requires a ≠ 0; the current context does not establish it.

Selector (matching 'x) found 3 occurrences; choose one or request all.

This cancellation changes the domain unless x ≠ 0 remains attached.

The CAS supplied an equivalent target, but no fine-grained rewrite trace.

The supplied cases are not known to cover the original parameter domain.
```

### 13.5 Acceptance criteria for this design

The four example families above are the principal acceptance scenarios. In particular, a future implementation should preserve the original equation, retain explicit `−5` and `1·x` intermediates, hold layout during removal, separate parameter cases from solution alternatives, and never lose the second quadratic root or divide by an unhandled zero coefficient.

Additional tests should exercise repeated equal occurrences, copying and merging, domain exclusions, negative `a` in the quadratic formula, discriminant zero, unverified CAS results, and exact checkpoint restoration after intermediate animation frames.

## 14. Decisions proposed for discussion

The central proposal is **ordinary mathematical data plus explicit, immutable records of mathematical work**. It avoids both a second CAS and a system that knows only how to match rendered strings.

The most important defaults are:

| Decision | Proposed default |
|---|---|
| Expression representation | Held `racket-cas`-compatible S-expressions with orthogonal context/occurrence metadata. |
| Evaluation | Explicit and scoped; never automatic at authoring boundaries. |
| Authoring abstraction | Named rule applications assembled into immutable derivations. |
| Mathematical safety | Explicit validity relationship and obligations; unknown is not true. |
| Algebra versus choreography | Separate objects; one derivation can have several presentations. |
| History | Retain completed presentation groups, not every microstep. |
| Identity | Occurrence lineage distinct from expression equality and view copying. |
| Branches | Separate parameter case trees and solution alternatives. |
| CAS integration | Optional computational/checking services, not the owner of the displayed state. |
| Renderer integration | Compile to existing `animate` formula/scene facilities. |
| First scope | Scalar arithmetic, polynomial expressions, equations, and the illustrated real solution cases. |

The main authoring question left open is the balance between explicit small steps and documented composite rules. This guide deliberately shows both: elementary operations for the linear lesson, and a small number of inspectable composites for the quadratic derivation. It does not propose implementing a general automatic equation tutor before those workflows work well.

## 15. Source notes

These references ground the observations about existing software. The proposed APIs, contracts, and examples in the rest of the guide are design choices, not claims that those APIs currently exist.

**[S1] MF_Algebra:** README and algebraic/action core establish the expression/action/timeline structure and template-to-address correspondence.

`https://github.com/TheMathematicFanatic/MF_Algebra/blob/main/README.md`

`https://github.com/TheMathematicFanatic/MF_Algebra/blob/main/src/MF_Algebra/algebra/algebra_core.py`

`https://github.com/TheMathematicFanatic/MF_Algebra/blob/main/src/MF_Algebra/actions/action_core.py`

**[S2] Existing animate derivations:** the source describes anchored author-provided rewrites and explicitly excludes algebra parsing/validation.

`https://github.com/soegaard/animate/blob/main/private/formula-derivation.rkt`

**[S3] racket-cas data representation:** documentation and core describe ordinary symbolic S-expressions and distinguish them from normalized forms.

`https://github.com/soegaard/racket-cas/blob/b4ec476c69f72dc694ba1d510c4213058197f48f/racket-cas-doc/racket-cas.scrbl`

**[S4] Smart constructors:** `plus2`, `times2`, and power construction simplify and reorder expressions.

`https://github.com/soegaard/racket-cas/blob/b4ec476c69f72dc694ba1d510c4213058197f48f/racket-cas/core.rkt`

**[S5] Quote normalization:** the REPL/start convenience replaces quote and quasiquote with normalization-wrapped versions.

`https://github.com/soegaard/racket-cas/blob/b4ec476c69f72dc694ba1d510c4213058197f48f/racket-cas/racket-cas.rkt`

**[S6] Substitution behavior:** `subst` still uses smart constructors when `#:normalize?` is false.

`https://github.com/soegaard/racket-cas/blob/b4ec476c69f72dc694ba1d510c4213058197f48f/racket-cas/simplify-expand.rkt`

**[S7] Pattern matching:** `math-match` and the core match expanders provide mathematical views of expressions, including synthetic groupings.

`https://github.com/soegaard/racket-cas/blob/b4ec476c69f72dc694ba1d510c4213058197f48f/racket-cas/math-match.rkt`

`https://github.com/soegaard/racket-cas/blob/b4ec476c69f72dc694ba1d510c4213058197f48f/racket-cas/core.rkt`

**[S8] Checking limitations:** the postponed assumptions experiment in core and comments on inverse-solving conditions motivate explicit obligations and qualified backend evidence.

`https://github.com/soegaard/racket-cas/blob/b4ec476c69f72dc694ba1d510c4213058197f48f/racket-cas/core.rkt`

`https://github.com/soegaard/racket-cas/blob/b4ec476c69f72dc694ba1d510c4213058197f48f/racket-cas/solve.rkt`

**[S9] animate integration surface:** the main module imports the existing formula, source-map, transition, and scene facilities.

`https://github.com/soegaard/animate/blob/main/main.rkt`
