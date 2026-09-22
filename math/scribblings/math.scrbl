#lang scribble/manual

@(require (for-label (except-in racket/base numerator denominator)
                     racket/contract
                     "../main.rkt"
                     "../render.rkt"
                     "../cas.rkt"
                     "../cas/calcura.rkt"
                     "../cas/racket-cas.rkt"
                     (only-in "../../main.rkt" scene? camera? visual?)
                     (only-in pict pict?)))

@title[#:tag "animate-math"]{Semantic Mathematics for Animate}
@author{Animate math subsystem}

Version 0.5.0. This reference describes the implemented public API, not proposed
future capabilities. Keep the @tt{math/} folder in the root of the
@tt{animate} repository.

@section{Concept gallery}

The example @tt{math/examples/gallery.rkt} presents 25 selectable concept plates
in five chapters, with 31 replays including presentation comparisons. Run
@tt{--list-plates} or @tt{--list-chapters} without loading the native renderer.
@tt{--plate additive-cancellation} selects one demonstration; @tt{--chapter moves}
selects the hierarchy and recipe examples. The complete planned duration is
299.1 seconds.

Movie output uses the existing shared process renderer and parent-only formula
preparation. @tt{--review-stills} creates native stills, contact sheets, and an HTML
index; @tt{--review-zip} additionally packages the review. The gallery's unrelated
plates are not mathematical cases. Grouping and history comparison views reuse the
same derivation while varying only presentation policy.

The full catalogue, command examples, and safety/validation distinctions are in
@tt{math/docs/gallery.md}. The gallery does not add bindings to the algebra facade.

@section{Start with held data}

The mathematical layer uses ordinary scalar S-expressions with an immutable
sidecar for context and occurrence identity. It does not introduce a second
mathematical expression hierarchy. A mathematical derivation is independent of
how its steps are timed, typeset, and animated.

@racketblock[
(require animate/math animate/math/render)
(define problem
  (math '(= (+ (* 3 x) 5) 17)
        #:id 'lesson
        #:context (math-context #:real '(x))))
(define solution
  (derive problem
    [subtract-five (both-sides 'subtract 5)]
    [cancel-five (cancel-addends #:at (lhs))]
    [evaluate-twelve (evaluate #:at (rhs))]))
(define plan (present solution
                       #:groups '((subtract-five cancel-five evaluate-twelve))))
(define scene (math-plan->scene! plan))]

Constructing the mathematical data above performs no typesetting. The final
conversion is explicitly effectful. Once compiled, native scene sampling does
not call a CAS, run TeX, or replay earlier frames.

@section{Contracts and trust boundaries}

All geometric dimensions and times must be finite. Positive sizes exclude zero;
pauses may be zero. Time is measured in seconds, and prepared token dimensions
are local world units. Default schedule arithmetic is exact rational arithmetic.
A caller may supply finite inexact durations deliberately.

An operand path is a list of zero-based indices excluding the operator symbol.
The empty list denotes the complete expression. An occurrence ordinal is instead
one-based. Equal subexpressions can have different occurrence identities; visual
working copies also have separate view identities.

The local algebra checker supports elementary real-scalar arithmetic, not a
complete proof system. Evidence values carry the checker or provider identity.
A custom prover and external CAS are trusted code, not formal proof certificates.
Unknown and refuted results are distinct. Conditions and original-domain
exclusions remain attached to the derivation.

No raw constructors for mathematical states, derivations, rewrite traces, or
presentation plans are exported. Predicates and accessors allow inspection, and
the documented constructors enforce the public invariants. Private modules are
not a supported authoring API.

@section{Worked lessons}

The four supplied modules are @tt{math/examples/linear-concrete.rkt},
@tt{linear-general.rkt}, @tt{quadratic-concrete.rkt}, and
@tt{quadratic-general.rkt}. Each exports a held problem, a solution derivation,
a presentation plan, and an explicitly invoked native scene factory.

The concrete linear example solves @math{3x+5=17}, shows subtraction on both
sides, displays the fractions during division, retains @math{1\cdot x} as its own
checkpoint, and checks the root in the original equation. Its default presentation
lasts exactly @math{54/5} seconds.

The general linear example covers the nonzero-coefficient case and both zero
coefficient cases. The concrete quadratic example completes the square for
@math{x^2+6x+5=0} and retains both roots. The general quadratic example builds
@math{(2ax+b)^2=b^2-4ac}, branches on the discriminant, and includes every
degenerate coefficient case.

The prose walkthrough and supported limitations are in @tt{math/docs/user-guide.md}.
Run an example with @tt{--steps} to inspect all held checkpoints without TeX.
Run @tt{math/run-probes.rkt --dark} separately for actual native rendering
integration. It samples intermediate phases in all four examples, including
replacement-barrier boundaries, rather than only checking completed formulas.

The general quadratic lesson uses shared-prefix presentation: completing the
square is shown once before the discriminant cases. Its default duration is
@math{549/10} seconds. The concrete quadratic lesson explains the choice of 9
with @math{(6/2)^2=9} before inserting it into the working equation.

@section{Mathematical API}
@defmodule[animate/math]

This module exports held model values, deterministic local checking, explicit
rewrites, and presentation descriptions. It does not import rendering or
external CAS-execution modules. All accessors and ordinary constructors here are
pure when used with the default local prover. An explicitly installed custom
prover must honor its documented callback contract.



@subsection{Held states and occurrence identity}


@defproc[(math [datum math-datum?]
         [#:id id symbol? 'math]
         [#:context ctx math-context? (math-context)])
         math?]{
Constructs a held mathematical state with deterministic occurrence identities.

The expression remains held: term order, repeated occurrences, explicit units,
zeroes, and unevaluated arithmetic are retained. The default namespace is
@racket['math]; supply different @racket[#:id] values for independent roots.
Occurrence paths exclude the operator and are zero-based. Initial domain
requirements are retained in the context; a refuted definedness condition raises
@racket[exn:fail:math?]. No CAS or typesetter is loaded by this constructor.
}


@defproc[(math? [value any/c])
         boolean?]{
Reports whether the value is a mathematical state.
}


@defproc[(math-datum [record math?])
         math-datum?]{
Returns the exact held expression without normalizing it.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(math-id [record math?])
         symbol?]{
Returns the stable mathematical-state namespace.

Identity is deterministic and scoped to the mathematical root and derivation, not allocated by a process-global counter.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(math-context-of [state math?])
         math-context?]{
Returns the assumptions and retained domain of this state.
}


@defproc[(math-occurrences [record math?])
         (and/c hash? immutable?)]{
Returns the operand-path map for this immutable state.

Keys are operand paths. Hash enumeration has no semantic order; use
@racket[datum-paths] or the ordered selector results when order matters.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(math-revision [record math?])
         any/c]{
Returns the deterministic derivation revision, not a process-global counter.

Identity is deterministic and scoped to the mathematical root and derivation, not allocated by a process-global counter.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(math-with-context [state math?]
         [requested-context math-context?]
         [#:scope scope (or/c symbol? #f) #f])
         math?]{
Creates a scoped state while retaining the original domain restrictions.

Existing domain restrictions survive this update. An inconsistent context
is rejected. Scope must be a symbol or false. A supplied scope changes the
revision tag but does not silently allocate a new global identity namespace.
}


@defproc[(math-occurrence-at [state math?]
         [path (listof exact-nonnegative-integer?)])
         occurrence?]{
Selects the occurrence at an exact zero-based operand path.
}


@defproc[(math-inspect [state math?]
         [path (listof exact-nonnegative-integer?)])
         (and/c hash? immutable?)]{
Reports occurrence identity, held syntax, context, and revision.
}


@defproc[(math-datum? [x any/c])
         boolean?]{
Recognizes supported scalar-expression data without evaluating it.

Recognizes finite real atoms, booleans, symbols, and proper symbol-headed
application lists. The constructor additionally validates known operator arities.
This predicate does not establish mathematical validity or real-valuedness.
}


@defproc[(held-substitute [x math-datum?]
         [replacements (or/c hash? list?)])
         math-datum?]{
Performs simultaneous structural substitution and rejects traversal under binders.

Substitution is simultaneous: replacement results are not substituted again.
It does not rebuild ancestors through simplifying CAS constructors. Traversal
under binders is rejected rather than risking variable capture. The operation
returns ordinary data and retains no replacement map.
}


@defproc[(free-of? [x math-datum?]
         [target math-datum?])
         boolean?]{
Tests absence of a structurally equal complete subexpression.

Tests structural absence, not algebraic independence. Equivalent but
differently written expressions are not treated as equal.
}


@defproc[(datum-ref [x math-datum?]
         [p (listof exact-nonnegative-integer?)])
         math-datum?]{
Looks up a held subexpression by zero-based operand indices.

An empty path denotes the root. Each nonnegative index selects an operand,
not a list element including the operator. Invalid paths raise a diagnostic.
}


@defproc[(datum-paths [x math-datum?]
         [p (listof exact-nonnegative-integer?) '()])
         (listof (listof exact-nonnegative-integer?))]{
Enumerates the root and descendants in preorder without sorting operands.

Returns the root first, followed by operands recursively in their stored
order. The optional prefix is prepended to every returned path.
}


@defproc[(occurrence? [value any/c])
         boolean?]{
Reports whether its argument is a occurrence value.
}


@defproc[(occurrence-id [record occurrence?])
         symbol?]{
Returns the id field: stable occurrence identity, independent of rendered views.

Identity is deterministic and scoped to the mathematical root and derivation, not allocated by a process-global counter.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(occurrence-path [record occurrence?])
         (listof exact-nonnegative-integer?)]{
Returns the path field: zero-based path in this state only.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(occurrence-datum [record occurrence?])
         math-datum?]{
Returns the datum field: exact held subexpression.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(exn:fail:math? [value any/c])
         boolean?]{
Reports whether its argument is a exn:fail:math value.
}


@defproc[(exn:fail:math-code [record exn:fail:math?])
         symbol?]{
Returns the code field: stable mathematical diagnostic category.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(exn:fail:math-details [record exn:fail:math?])
         list?]{
Returns the details field: ordered diagnostic context.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defparam[current-math-validation mode (or/c 'strict 'draft)]{
Defaults to @racket['strict]. Strict construction rejects unresolved obligations;
draft construction retains them. Both modes reject refuted operations. A draft
presentation still requires an explicit visible-warning opt-in.
}

@defparam[current-math-prover prover procedure?]{
Defaults to @racket[context-prove]. The callback takes a mathematical context
and a proposition and returns exactly one verification report for that same
proposition. Mandatory keyword arguments and wrong arity are rejected when the
parameter is set; malformed or unrelated evidence is rejected at application.
The callback is used during construction and is not retained in a native scene.
}


@subsection{Contexts and evidence}


@defproc[(math-context [#:real real (listof symbol?) '()]
         [#:assuming assumptions (listof math-datum?) '()]
         [#:definitions definitions (or/c hash? list?) '()])
         math-context?]{
Validates real variables, ordered assumptions, and acyclic scoped definitions.

Only declared symbols are assumed real. Assumptions retain declaration order.
Definitions may be a hash or a list of two-element name/expression lists; names
must be symbols, duplicates in list input are rejected, and cycles are rejected.
The stored definition hash is immutable. A definition is an abbreviation, not a
new unconstrained variable.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(math-context? [value any/c])
         boolean?]{
Recognizes an immutable real-scalar context.
}


@defproc[(math-context-real [record math-context?])
         (listof symbol?)]{
Returns real-variable declarations in declaration order.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(math-context-assumptions [record math-context?])
         (listof math-datum?)]{
Returns the ordered assumption propositions.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(math-context-definitions [record math-context?])
         (and/c hash? immutable?)]{
Returns the immutable map of scoped definitions.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(math-context-restrictions [record math-context?])
         (listof math-datum?)]{
Returns domain exclusions retained independently of current syntax.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(context-assume [c math-context?]
         [guard math-datum?])
         math-context?]{
Adds a branch guard and the guard expression's definedness conditions.
}


@defproc[(context-add-restrictions [c math-context?]
         [rs (listof math-datum?)])
         math-context?]{
Adds validated domain obligations without deleting existing exclusions.
}


@defproc[(context-expand [c math-context?]
         [x math-datum?])
         math-datum?]{
Expands definitions and contextual equalities with a bounded substitution pass.
}


@defproc[(context-prove [c math-context?]
         [p math-datum?])
         verification?]{
Checks definedness before reporting an established, refuted, or unknown proposition.

Returns established, refuted, or unknown evidence. Definedness is checked
before algebraic identity reasoning, so simplifying a quotient cannot erase its
excluded points. This is a bounded elementary checker, not a complete prover.
}


@defproc[(context-signs [c math-context?]
         [expr math-datum?]
         [fuel exact-nonnegative-integer? 24])
         (listof exact-integer?)]{
Returns conservative possible signs; uncertainty is never treated as positivity.

The result is a conservative subset of @racket['(-1 0 1)]. Its entries mean
negative, zero, and positive. The default recursion budget is 24. Exhaustion
returns uncertainty; it never silently assumes positivity.
}


@defproc[(context-real? [c math-context?]
         [x math-datum?]
         [fuel exact-nonnegative-integer? 40])
         boolean?]{
Conservatively establishes real-valuedness within a finite recursion budget.

The default recursion budget is 40. Failure to establish real-valuedness
returns false, which does not prove non-real-valuedness.
}


@defproc[(context-inconsistent? [c math-context?])
         boolean?]{
Reports an established inconsistency without guessing from unknown evidence.
}


@defproc[(context-facts [c math-context?])
         (listof math-datum?)]{
Returns assumptions followed by retained domain restrictions.
}


@defproc[(check-case-coverage [c math-context?]
         [guards (listof math-datum?)])
         verification?]{
Checks exhaustiveness and disjointness over at most seven sign atoms.

Checks both exhaustiveness and pairwise disjointness using at most seven
propositional sign atoms. Unsupported guards or a larger problem return unknown
evidence. Branch declaration order is preserved separately by the derivation.
}


@defproc[(verification? [value any/c])
         boolean?]{
Reports whether its argument is a verification value.
}


@defproc[(verification-status [record verification?])
         (or/c 'established 'refuted 'unknown)]{
Returns the status field: three-valued decision.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(verification-method [record verification?])
         symbol?]{
Returns the method field: evidence source, not a formal-proof claim.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(verification-proposition [record verification?])
         any/c]{
Returns the proposition field: the exact proposition being checked.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(verification-obligations [record verification?])
         list?]{
Returns the obligations field: pending requirements in diagnostic order; empty after a decision.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(verification-message [record verification?])
         (and/c string? immutable?)]{
Returns the message field: copied diagnostic text.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(verification-details [record verification?])
         any/c]{
Returns the details field: snapshotted supporting metadata.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(established [method symbol?]
         [proposition math-datum?]
         [details any/c '()])
         verification?]{
Creates immutable evidence for an established proposition.

This constructs evidence metadata; it does not itself prove the proposition.
Custom provers and service adapters are trusted to supply truthful reports.
Acyclic metadata containers, including strings, vectors, boxes, and hashes,
are copied immutably; already validated verification records may be nested.
Cyclic metadata, procedures, and opaque native resources are rejected. This
prevents external result handles from changing previously recorded evidence.
}


@defproc[(unknown [method symbol?]
         [proposition math-datum?]
         [obligations list? (list proposition)]
         [message string? "Not established."]
         [details any/c '()])
         verification?]{
Creates pending evidence with explicit obligations and an immutable diagnostic.

Records explicit unresolved obligations. Unknown is never interpreted as
true. Empty obligation lists still leave the report status unknown.
}


@defproc[(refuted [method symbol?]
         [proposition math-datum?]
         [message string? "Refuted."]
         [details any/c '()])
         verification?]{
Creates immutable evidence for a refuted proposition.

Constructs a refutation report rather than throwing an exception.
Application of a refuted rewrite is rejected even in draft mode.
}


@defproc[(merge-verifications [checks (listof verification?)]
         [proposition math-datum? 'derivation])
         verification?]{
Combines ordered reports with refutation taking precedence over uncertainty.

Refutation takes precedence over unknown, and unknown takes precedence
over established. Report order is retained in the combined details.
}



@subsection{Selectors}


@defproc[(whole)
         selector?]{
Selects the complete root expression.

Selects the complete root. Selectors refer to the input snapshot of the
operation, not a location remembered from a different revision.
}


@defproc[(lhs [within selector? (whole)])
         selector?]{
Selects the left operand of a relation within the containing selection.

The containing selection must resolve to a binary relation. It is not a
text search for the material left of the first rendered equals sign.
}


@defproc[(rhs [within selector? (whole)])
         selector?]{
Selects the right operand of a relation within the containing selection.

The containing selection must resolve to a binary relation. The selector
returns its second mathematical operand.
}


@defproc[(numerator [within selector? (whole)])
         selector?]{
Selects the numerator of an explicitly held quotient.

Requires a held quotient @racket['(/ numerator denominator)]. It does not
invent a quotient view of a product with a negative exponent.
}


@defproc[(denominator [within selector? (whole)])
         selector?]{
Selects the denominator of an explicitly held quotient.

Requires explicit quotient syntax. No implicit CAS normalization is used
when resolving this selector.
}


@defproc[(at-path [p (listof exact-nonnegative-integer?)])
         selector?]{
Selects an exact zero-based operand path and validates the path immediately.

Validates the path shape immediately. Range validation occurs against a
specific held expression when the selector is resolved.
}


@defproc[(matching [datum math-datum?]
         [#:occurrence ordinal (or/c exact-positive-integer? #f) #f]
         [#:within within selector? (whole)])
         selector?]{
Selects structural matches, optionally choosing a one-based occurrence ordinal.

Matches structural data within the selected subtree in preorder.
@racket[#:occurrence] is one-based. Without it, all matches are returned; an
operation requiring one match diagnoses ambiguity instead of selecting the first.
}


@defproc[(all-matching [datum math-datum?]
         [#:within within selector? (whole)])
         selector?]{
Selects every structural match in held preorder within the containing selection.

Returns all structural matches in preorder. Repeated equal values retain
their distinct occurrence identities.
}


@defproc[(operator-of [within selector? (whole)])
         selector?]{
Selects the owning expression for inspection of an operator role.

Selects the owning mathematical expression. The visual adapter may then
address its operator role; this selector does not create a separate AST operand.
}


@defproc[(selector? [value any/c])
         boolean?]{
Reports whether its argument is a selector value.
}


@defproc[(resolve-selector [state (or/c math? math-datum?)]
         [s selector?])
         (listof (listof exact-nonnegative-integer?))]{
Resolves an immutable selector to ordered operand paths in one snapshot.
}


@defproc[(resolve-one [state (or/c math? math-datum?)]
         [s selector?])
         (listof exact-nonnegative-integer?)]{
Requires exactly one result and diagnoses missing or ambiguous selection.
}


@defproc[(math-select [state math?]
         [s selector?])
         (listof occurrence?)]{
Returns selected mathematical occurrences, not anonymous rendered glyphs.
}



@subsection{Operations and template rules}


@defproc[(math-operation? [value any/c])
         boolean?]{
Reports whether its argument is a math-operation value.
}


@defproc[(math-operation-name [record math-operation?])
         symbol?]{
Returns the name field: semantic operation name.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(math-operation-selector [record math-operation?])
         selector?]{
Returns the selector field: input focus resolved at application time.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(apply-math-operation [state math?]
         [op math-operation?]
         [#:name name symbol? (math-operation-name op)])
         rewrite-step?]{
Applies and verifies one named operation before committing a new state.

The focus must resolve uniquely. The operation constructs a held edit,
checks its obligations, retains the original domain restrictions, and commits a
new immutable state. No animation or typesetting is performed.
}


@defproc[(both-sides [op symbol?]
         [operand math-datum?]
         [#:at focus selector? (whole)]
         [#:relationship relationship symbol? 'equivalence])
         math-operation?]{
Applies a held operation to both relation operands with explicit invertibility guards.

Accepts @racket['add], @racket['subtract], @racket['multiply],
@racket['divide], or @racket['power]. Equivalence is the default.
Multiplication and division require the appropriate nonzero conditions.
Multiplying an inequality by a known negative value reverses its direction;
an undecided sign is not guessed. Squaring is available as an explicit
@racket['implication], not as an automatic solution-preserving equivalence.
}


@defproc[(cancel-addends [#:at focus selector? (whole)]
         [#:pair pair (or/c list? #f) #f])
         math-operation?]{
Cancels one specified or uniquely identified pair of additive inverses.

Cancels one additive-inverse pair in the selected sum. A supplied pair is
a two-element list of zero-based signed-addend indices. With no pair, cancellation
requires a unique match. More than one eligible pair is an ambiguity error.
}


@defproc[(cancel-factor [#:at focus selector? (whole)]
         [#:factor factor math-datum?]
         [#:keep-one? keep-one? boolean? #f])
         math-operation?]{
Cancels a selected common factor only under an established nonzero condition.

Requires an explicitly held quotient and the specified common factor.
The factor must be nonzero in the current context. Retained domain exclusions
survive cancellation. With @racket[#:keep-one? #t], a visible unit is retained
for a subsequent @racket[remove-unit] step.
}


@defproc[(remove-unit [#:at focus selector? (whole)])
         math-operation?]{
Removes an explicitly displayed unit factor as its own teaching step.

Removes an explicitly displayed multiplicative unit. This is separate
from cancellation so its disappearance can receive its own animation phase.
}


@defproc[(reduce-identities [#:at focus selector? (whole)])
         math-operation?]{
Reduces supported identities only inside the explicit focus.

Applies the implemented zero, unit, and sign identities within the
selected focus. Unrelated portions of the held expression are not normalized.
}


@defproc[(evaluate [#:at focus selector? (whole)]
         [#:mode mode symbol? 'all])
         math-operation?]{
Evaluates exact arithmetic at the selected focus, optionally one deepest layer.

The mode is @racket['all] or @racket['deepest]. Arithmetic is exact;
non-perfect radicals and unsupported operations remain held. Equations remain
visible equations instead of collapsing to booleans.
}


@defproc[(rewrite-to [target math-datum?]
         [#:at focus selector? (whole)]
         [#:using rule symbol? 'rational-identity])
         math-operation?]{
Requests a checked focused target and records an honest coarse rewrite event.

The target is explicit held data. The implemented policy checks rational
or polynomial identity and records a focused replacement. A rule name labels the
step; it does not manufacture a fine-grained derivation that a CAS never supplied.
Target equivalence does not authorize discarding domain restrictions.
}


@defproc[(reorder-addends [#:at focus selector? (whole)]
         [#:order order (listof exact-nonnegative-integer?)])
         math-operation?]{
Permutes signed addends by explicit zero-based indices.

The order must be a permutation of all zero-based signed-addend indices.
Signs travel with the terms. Missing, repeated, or out-of-range indices are rejected.
}


@defproc[(zero-product [#:at focus selector? (whole)])
         math-operation?]{
Splits a real product equation into the direct zero-factor alternatives.

Requires a product equation equal to zero over real scalars. The result
is an explicit disjunction of factor equations, retaining all alternatives.
}


@defproc[(square-solutions [#:at focus selector? (whole)])
         math-operation?]{
Solves a real square equation using explicit positive, zero, or negative cases.

Requires a square equation. A positive right side produces positive- and
negative-root alternatives; zero produces one alternative; a negative right side
has no real solutions. An unknown sign is an unresolved obligation rather than an
implicit choice of the positive branch.
}


@defproc[(abbreviate [name symbol?]
         [#:at focus selector? (whole)])
         math-operation?]{
Replaces a selected expression by an equivalent scoped definition name.

The name must have a scoped definition, and the selected expression must
match the defined value under the available checks. The definition remains in
the context for subsequent reasoning and display.
}


@defproc[(each-branch [op math-operation?])
         math-operation?]{
Applies one operation to each direct solution alternative in branch order.

Applies the supplied operation to each direct disjunction alternative.
It does not recursively search arbitrary nested case trees.
}


@defproc[(substitute [replacements (or/c hash? list?)]
         [#:at focus selector? (whole)])
         math-operation?]{
Snapshots a replacement map and constructs a held specialization operation.

Accepts a hash or an association list of replacement pairs. Captures an
immutable copy of the caller's replacement map when this
operation is constructed. Subsequent caller mutation cannot change its result.
The recorded relationship is specialization, not equation equivalence.
}


@defproc[(conclude [classification symbol?]
         [#:for variable symbol?])
         math-operation?]{
Requests a checked classification as all real values or no real solutions.

Accepts @racket['all-real] or @racket['no-solutions]. These are checked
classifications, not arbitrary labels. Original-domain restrictions prevent an
incorrect claim that every real value is allowed.
}


@defproc[(assert-step [target math-datum?]
         [#:at focus selector? (whole)]
         [#:reason reason string? "Author-supplied target."])
         math-operation?]{
Creates a deliberately unverified author target that strict mode cannot certify.

Creates an explicitly unverified author-supplied target. Strict mode
rejects unresolved application. Draft presentation requires an explicit opt-in
and displays an unverified warning.
}


@defform[(define-math-rule name
             #:metavariables (variable ...)
             #:from before-template
             #:to after-template)]{
Captures held templates without evaluating arithmetic. Optional clauses, in order,
are @racket[#:in real-scalars], @racket[#:check polynomial-identity],
@racket[#:requires (condition ...)], @racket[#:merge merge-expression], and
@racket[#:version version-expression]. The alternative check is
@racket[author-assertion]; the domain is currently only @racket[real-scalars].
Requires clauses are captured templates. Merge and version expressions are
ordinary evaluated configuration values.
@racketblock[
(define-math-rule distribute-left
  #:metavariables (u v w)
  #:from (* u (+ v w))
  #:to (+ (* u v) (* u w))
  #:check polynomial-identity)]
Repeated target occurrences of one source metavariable create explicit copies.
Several source occurrences contributing to a target require @racket[#:merge 'merge].
}

@defproc[(make-math-rule [name symbol?]
         [variables (listof symbol?)]
         [before math-datum?]
         [after math-datum?]
         [#:requires requires (listof math-datum?) '()]
         [#:merge merge (or/c symbol? #f) #f]
         [#:version version exact-positive-integer? 1]
         [#:check check symbol? 'polynomial-identity])
         math-rule?]{
Validates held templates, metavariables, merge policy, and rule version.

Metavariables are unique symbols in declaration order. Templates stay
held. Checks are @racket['polynomial-identity] or @racket['author-assertion].
A repeated source metavariable requires an explicit @racket[#:merge 'merge]
policy before several source occurrences can contribute to a destination.
Rule versions are positive exact integers.
}


@defproc[(math-rule? [value any/c])
         boolean?]{
Reports whether its argument is a math-rule value.
}


@defproc[(math-rule-name [record math-rule?])
         symbol?]{
Returns the name field: rule identity.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(use-rule [rule math-rule?]
         [#:at focus selector? (whole)])
         math-operation?]{
Creates an operation from a trace-aware held rule template.

Creates an operation descriptor. The selector is resolved and the rule
is checked only when the operation is applied to a mathematical state.
}


@defproc[(apply-rule [rule math-rule?]
         [#:at focus selector? (whole)])
         math-operation?]{
Creates an operation from a trace-aware held rule template.

An alias of @racket[use-rule]. It creates an operation, not an applied
rewrite step. Use @racket[apply-rewrite] for immediate application.
}


@defproc[(apply-rewrite [rule math-rule?]
         [state math?]
         [#:name name symbol? (math-rule-name rule)]
         [#:at focus selector? (whole)])
         rewrite-step?]{
Applies a traceable template rule directly to a mathematical state.

Combines @racket[use-rule] with @racket[apply-math-operation]. The
requested step name is independent of the reusable rule name.
}


@defproc[(template-bindings [template math-datum?]
         [value math-datum?]
         [variables (listof symbol?)])
         (values (and/c hash? immutable?) (and/c hash? immutable?))]{
Returns structural bindings and all source occurrence witnesses.

Returns two values: an immutable binding hash and an immutable hash of
ordered source witness paths. Matching is structural; it does not silently commute
or reassociate terms. Conflicting repeated metavariables raise an error.
}



@subsection{Derivations and branches}


@defform[(steps [name operation] ...)]{
Constructs a nonempty reusable mathematical recipe. Each name is a literal identifier;
each operation is a @racket[math-operation?] or nested @racket[step-sequence?]. Sibling
names are unique. No mathematical state is advanced until the recipe is used in a
named @racket[derive] slot. Recipes carry no presentation timing or native resources.
@racketblock[
(define (subtract-and-cancel amount)
  (steps [subtract (both-sides 'subtract amount)]
         [cancel (cancel-addends #:at (lhs))]))
(derive problem [isolate-term (subtract-and-cancel 5)])]
A recipe is not an elementary operation: use it in @racket[derive], not as an
argument to @racket[apply-math-operation] or @racket[each-branch]. For branchwise
recipes, wrap their elementary operations in @racket[each-branch] explicitly.
}

@defproc[(steps/proc [entries list?]) step-sequence?]{
Constructs a recipe from a nonempty ordered list of pairs
@racket[(cons name operation)]. The cdr is an elementary operation or another
recipe. Copies and validates the sibling list; duplicate symbols and invalid
operations are rejected before any operation is applied.
}

@defproc[(step-sequence? [value any/c]) boolean?]{
Recognizes an immutable unapplied recipe created by @racket[steps] or @racket[steps/proc].
The raw constructor is private.
}

@defproc[(derivation-tree [record derivation?]) (listof derivation-node?)]{
Returns ordered applied root nodes. Their elementary leaves are exactly
@racket[derivation-steps], in order. Composite nodes do not create extra checkpoints.
}

@defproc[(derivation-node? [value any/c]) boolean?]{
Recognizes one applied elementary leaf or composite move. Its raw constructor is private.
}

@defproc[(derivation-node-path [record derivation-node?]) (listof symbol?)]{
Returns its nonempty derivation-relative hierarchical address. Case paths are separate.
This is an authoring address, not a mathematical occurrence ID or a rendered view ID.
}

@defproc[(derivation-node-before [record derivation-node?]) math?]{
Returns the exact input state of the first elementary descendant.
}

@defproc[(derivation-node-after [record derivation-node?]) math?]{
Returns the exact output state of the last elementary descendant.
}

@defproc[(derivation-node-children [record derivation-node?]) (listof derivation-node?)]{
Returns ordered children for a composite and an empty list for an elementary leaf.
}

@defproc[(derivation-node-step [record derivation-node?]) (or/c rewrite-step? #f)]{
Returns the original primitive rewrite for a leaf, or @racket[#f] for a composite.
No opaque replacement rewrite is fabricated for a composite.
}

@defproc[(derivation-node-at [source (or/c derivation? case-derivation? solution-check?)]
                            [address (or/c symbol? (listof symbol?))]) derivation-node?]{
Looks up an exact nonempty hierarchical path, or an unambiguous local symbol.
Repeated child names in different moves require full paths. A symbol is not allowed
to guess a case branch. A case-qualified path prepends branch names to the move path.
Unknown or ambiguous addresses raise a mathematical diagnostic.
@racketblock[
(derivation-node-at solution '(isolate-term cancel-five))
(derivation-node-at general-solution '(ordinary isolate-x))]
}

@defproc[(derivation-node-relation [record derivation-node?]) symbol?]{
Conservatively summarizes leaf relationships. Identical kinds are retained;
expression/equation equivalences together give @racket['equivalence]; equivalences
plus implications give @racket['implication]; equivalences plus specializations give
@racket['specialization]. Other mixtures, including implication plus specialization,
are @racket['mixed]. This does not strengthen any child into equivalence.
}

@defproc[(derivation-node-verification [record derivation-node?]) verification?]{
Combines ordered primitive evidence without adding endpoint checks or external CAS
calls. Established child checks do not imply that the move preserves all solutions;
inspect @racket[derivation-node-relation] separately.
}

@defproc[(derivation-step-paths [record derivation?]) (listof (listof symbol?))]{
Returns full nonempty leaf paths in chronological order. Even a flat leaf has a
one-element path here. Schedule accessors retain a symbol for a flat root leaf
and return a full symbol list for a nested leaf.
}

@defform[(derive initial [name operation] ...)]{
Evaluates each operation expression and applies it in declaration order. Names
are captured as symbols. The input is a held state or an existing linear
derivation. Entries accept elementary operations or recipes. Names must be unique
among siblings; child names may repeat in different moves. An empty derivation is
allowed. Every elementary checkpoint and occurrence trace is retained unchanged.
@racketblock[
(derive (math '(= (+ (* 3 x) 5) 17)
              #:context (math-context #:real '(x)))
  [subtract-five (both-sides 'subtract 5)]
  [cancel-five (cancel-addends #:at (lhs))]
  [compute-right (evaluate #:at (rhs))])]
}

@defproc[(derive/proc [initial (or/c math? derivation?)]
         [named-operations list?])
         derivation?]{
Appends named operations in order while rejecting duplicate step names.

The second argument is an ordered list of pairs whose car is a symbol
step name and whose cdr is an elementary operation or recipe. Top-level names must
be unique in the extended derivation; child names are sibling-local. No partial
derivation is returned on failure, and an existing derivation is never mutated.
}


@defform[(derive-cases initial [name guard [step operation] ...] ...)]{
Builds named parameter cases, checks guard coverage, and adds the guard to each
branch's immutable context. A branch can instead have the form
@racket[[name guard #:then factory]], where the factory consumes the scoped state
and returns a derivation or a nested case tree. Ordinary step names are local to
a branch. Branch entries can contain recipes. Top-level names must remain unique
along a complete path including the prefix; nested names are resolved by full paths.
}

@defproc[(make-case-derivation [initial (or/c math? derivation?)]
         [branch-specs list?])
         case-derivation?]{
Builds scoped branches only after checking case coverage.

Requires a nonempty list of three-element branch specifications,
@racket[(list name guard factory)]. Names are symbols and guards are validated
mathematical data. The factory accepts the scoped input state, requires no
keyword arguments, and returns a derivation or case tree.
Factories run during construction, must honor the held-state contract, and are
not retained in scenes. Duplicate sibling names and unsupported strict-mode
coverage are rejected.
}


@defproc[(derivation? [value any/c])
         boolean?]{
Reports whether its argument is a derivation value.
}


@defproc[(derivation-initial [record derivation?])
         math?]{
Returns the initial field: initial checkpoint.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(derivation-steps [record derivation?])
         (listof rewrite-step?)]{
Returns the chronological elementary rewrite list, not the move tree. Nested recipes
are flattened here without dropping states or replacing their original witnesses.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(derivation-final [record derivation?])
         math?]{
Returns the final field: last checkpoint, or initial state for an empty derivation.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(case-branch? [value any/c])
         boolean?]{
Reports whether its argument is a case-branch value.
}


@defproc[(case-branch-name [record case-branch?])
         symbol?]{
Returns the name field: unique sibling branch name.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(case-branch-guard [record case-branch?])
         math-datum?]{
Returns the guard field: scoped parameter condition.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(case-branch-derivation [record case-branch?])
         any/c]{
Returns the derivation field: nested derivation or case tree.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(case-derivation? [value any/c])
         boolean?]{
Reports whether its argument is a case-derivation value.
}


@defproc[(case-derivation-prefix [record case-derivation?])
         derivation?]{
Returns the prefix field: shared mathematical prefix.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(case-derivation-branches [record case-derivation?])
         (listof case-branch?)]{
Returns the branches field: declared branch presentation order.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(case-derivation-coverage [record case-derivation?])
         verification?]{
Returns the coverage field: exhaustiveness and disjointness evidence.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(solution-check? [value any/c])
         boolean?]{
Reports whether its argument is a solution-check value.
}


@defproc[(solution-check-problem [record solution-check?])
         math?]{
Returns the problem field: original problem and domain.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(solution-check-variable [record solution-check?])
         symbol?]{
Returns the variable field: variable being specialized.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(solution-check-value [record solution-check?])
         math-datum?]{
Returns the value field: candidate value.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(solution-check-derivation [record solution-check?])
         (or/c derivation? #f)]{
Returns the derivation field: visible substitution steps, absent for an undefined candidate.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(solution-check-verification [record solution-check?])
         verification?]{
Returns the verification field: candidate membership report, not solution-set completeness.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(after [d (or/c math? derivation? case-derivation? solution-check?)]
         [label (or/c symbol? (listof symbol?) #f) #f])
         math?]{
Returns a unique endpoint or named checkpoint, requiring an explicit branch for case trees.

Without a label, a linear derivation returns its final state. A case tree
has no unique final state: select a branch path or inspect its branches explicitly.
A named path uses any required branch symbols followed by a move/leaf path.
Both composite and elementary addresses are accepted; a composite returns its final
child's state. Unqualified symbols must be unambiguous in the requested scope.
}


@defproc[(derivation-step [d (or/c derivation? case-derivation?)]
         [label (or/c symbol? (listof symbol?))])
         rewrite-step?]{
Looks up an elementary leaf by hierarchical path or unambiguous symbol. A composite
address raises an error: use @racket[derivation-node-at] for inspection or @racket[after]
for its endpoint. Case paths precede derivation-relative move/leaf paths.
}


@defproc[(derivation-states [d (or/c derivation? case-derivation?)])
         (listof math?)]{
Returns checkpoint states in significant derivation and branch order.
}


@defproc[(derivation-verification [d (or/c derivation? case-derivation?)])
         verification?]{
Combines rewrite evidence and parameter-case coverage without external CAS calls.
}


@defproc[(check-solution [problem math?]
         [#:for variable symbol?]
         [#:value value math-datum?])
         solution-check?]{
Checks a candidate in the original domain before constructing visible substitution steps.

Checks the candidate against the original problem and its original
context. A successful substitution check establishes membership, not completeness
of the solution set. An undefined or unestablished-domain candidate has no visible
checking derivation.
}


@defproc[(rewrite-step? [value any/c])
         boolean?]{
Reports whether its argument is a rewrite-step value.
}


@defproc[(rewrite-step-name [record rewrite-step?])
         symbol?]{
Returns the name field: unique step name within its derivation path.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(rewrite-step-before [record rewrite-step?])
         math?]{
Returns the before field: exact input checkpoint.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(rewrite-step-after [record rewrite-step?])
         math?]{
Returns the after field: exact output checkpoint.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(rewrite-step-rule [record rewrite-step?])
         symbol?]{
Returns the rule field: applied mathematical operation.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(rewrite-step-focus [record rewrite-step?])
         (listof exact-nonnegative-integer?)]{
Returns the focus field: selected input location.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(rewrite-step-bindings [record rewrite-step?])
         (and/c hash? immutable?)]{
Returns the bindings field: held metavariable bindings.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(rewrite-step-links [record rewrite-step?])
         (listof path-link?)]{
Returns the links field: ordered structural provenance.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(rewrite-step-trace [record rewrite-step?])
         (listof trace-relation?)]{
Returns the trace field: typed occurrence relationships in deterministic order.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(rewrite-step-relation [record rewrite-step?])
         symbol?]{
Returns the relation field: equivalence, implication, or specialization classification.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(rewrite-step-verification [record rewrite-step?])
         verification?]{
Returns the verification field: evidence and outstanding conditions.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(rewrite-step-details [record rewrite-step?])
         any/c]{
Returns the details field: snapshotted rule-specific metadata.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(rewrite-step-version [record rewrite-step?])
         exact-positive-integer?]{
Returns the version field: rule-version identity for reproducibility.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(trace-descendants [step rewrite-step?]
         [item (or/c occurrence? symbol?)])
         (listof occurrence?)]{
Returns traced descendants in numerical operand traversal order.
}


@defproc[(path-link? [value any/c])
         boolean?]{
Reports whether its argument is a path-link value.
}


@defproc[(path-link-source [record path-link?])
         (listof exact-nonnegative-integer?)]{
Returns the source field: source location in the input snapshot.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(path-link-target [record path-link?])
         (listof exact-nonnegative-integer?)]{
Returns the target field: destination location in the output snapshot.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(path-link-kind [record path-link?])
         symbol?]{
Returns the kind field: preserve, container, reorder, or copy relationship.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(path-link-subtree? [record path-link?])
         boolean?]{
Returns the subtree? field: whether an exact equal subtree is witnessed.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(trace-relation? [value any/c])
         boolean?]{
Reports whether its argument is a trace-relation value.
}


@defproc[(trace-relation-kind [record trace-relation?])
         symbol?]{
Returns the kind field: preserve, copy, merge, cancel, evaluate, or related event.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(trace-relation-sources [record trace-relation?])
         (listof symbol?)]{
Returns the sources field: source occurrence identities in witness order.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(trace-relation-targets [record trace-relation?])
         (listof symbol?)]{
Returns the targets field: target occurrence identities in witness order.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(trace-relation-details [record trace-relation?])
         any/c]{
Returns the details field: semantic explanation, not animation timing.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}



@subsection{Complete mathematical notation}


@defproc[(math->tex [d (or/c math? math-datum?)]
         [#:multiplication m symbol? 'school])
         string?]{
Returns complete TeX source without evaluating or normalizing the expression.

An alias of @racket[datum->tex]. Both held data and mathematical states
are accepted, and neither is normalized for display.
}


@defproc[(datum->tex [d (or/c math? math-datum?)]
         [#:multiplication m symbol? 'school])
         string?]{
Returns complete TeX source without evaluating or normalizing the expression.
}


@defproc[(format-math-source [datum (or/c math? math-datum?)]
         [#:multiplication multiplication symbol? 'school])
         math-source?]{
Formats one complete formula and retains half-open source spans for its occurrences.

Returns a complete TeX source string plus semantic half-open source
ranges, measured in Racket string character indices, not UTF-8 bytes. Expression
ranges may contain subordinate leaf or operator ranges. No TeX process is run.
}


@defproc[(math->string [x (or/c math? math-datum?)])
         string?]{
Prints the held S-expression for inspection.

Produces the readable diagnostic notation used by @tt{--steps} and
context captions. It is not a parser round-trip format.
}


@defproc[(math-source? [value any/c])
         boolean?]{
Reports whether its argument is a math-source value.
}


@defproc[(math-source-text [record math-source?])
         (and/c string? immutable?)]{
Returns the text field: one complete TeX formula.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(math-source-spans [record math-source?])
         (listof math-source-span?)]{
Returns the spans field: start-ordered possibly nested semantic ranges.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(math-source-span? [value any/c])
         boolean?]{
Reports whether its argument is a math-source-span value.
}


@defproc[(math-source-span-start [record math-source-span?])
         exact-nonnegative-integer?]{
Returns the start field: inclusive character offset.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(math-source-span-end [record math-source-span?])
         exact-positive-integer?]{
Returns the end field: exclusive character offset.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(math-source-span-path [record math-source-span?])
         (listof exact-nonnegative-integer?)]{
Returns the path field: mathematical owner location.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(math-source-span-role [record math-source-span?])
         symbol?]{
Returns the role field: expression, atom, relation, or operator role.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}



@subsection{Presentation policy and schedules}


@defproc[(math-presentation [#:anchor anchor symbol? 'relation]
         [#:history history symbol? 'keep-completed-groups]
         [#:start-group start-group symbol? 'copy]
         [#:new-parts new-parts symbol? 'fade]
         [#:removed-parts removed-parts symbol? 'fade]
         [#:reflow reflow symbol? 'staged]
         [#:multiplication multiplication symbol? 'school]
         [#:pause-between-groups pause (and/c real? (>=/c 0)) 3/5]
         [#:duration step-duration (and/c real? positive?) 4/5]
         [#:font-size font-size (and/c real? positive?) 11/20]
         [#:row-gap row-gap (and/c real? positive?) 21/20]
         [#:max-visible-rows max-rows (and/c exact-integer? (>=/c 2)) 5])
         math-presentation?]{
Constructs validated layout and timing policy with exact rational defaults.

The anchor is @racket['relation] or @racket['center]. History is
@racket['keep-completed-groups], @racket['keep-all-checkpoints], or @racket['replace].
Start-group is @racket['copy] or @racket['replace]. The supported appearance effect
is @racket['fade]; unsupported effects are rejected. Reflow is @racket['staged]
or @racket['simultaneous], and multiplication is @racket['school] or @racket['explicit].
Durations and pauses are seconds; font size and row gap are world units. Values
must be finite. Pauses may be zero, other sizes and durations are positive, and
at least two visible rows are required. Defaults use exact rational numbers.
}


@defproc[(math-presentation? [value any/c])
         boolean?]{
Recognizes a validated presentation style.
}


@defthing[classroom math-presentation?]{
Provides the exact-time, staged, retained-history classroom style.


}

@defproc[(present [source (or/c derivation? case-derivation? solution-check?)]
         [#:style style math-presentation? classroom]
         [#:groups groups (or/c 'top-level 'steps list? hash? #f) #f]
         [#:case case-path (or/c symbol? (listof symbol?) #f) #f]
         [#:case-layout case-layout (or/c 'complete-paths 'shared-prefix) 'complete-paths]
         [#:allow-unverified? allow? boolean? #f])
         presentation-plan?]{
Builds an explicit presentation while retaining verification status and case context.

Groups partition elementary steps exactly once in order. @racket['top-level]
(and the default @racket[#f]) uses one group per top-level move or elementary root;
@racket['steps] uses one per elementary rewrite. Explicit groups may name moves or
leaves; move references expand before partition validation. For several cases,
either symbolic mode applies to every case, or a hash maps case paths to modes or
group lists. Missing hash entries use the top-level default. The case selector is a symbol or a list of branch symbols. Strict
presentation rejects unverified derivations unless @racket[#:allow-unverified? #t]
is supplied; that flag must be a boolean and causes a visible warning.

The default @racket['complete-paths] plays a complete derivation for every leaf.
With @racket['shared-prefix], each nonempty common mathematical prefix is played
once before its descendant branch suffixes. Group declarations still describe
complete leaf paths; they are validated first, then projected onto the emitted
segments. Incompatible partitions of a shared prefix are rejected. Selecting a
single @racket[#:case] always restores its full prefix, irrespective of layout.
}


@defform[(choreograph plan [step-key phase ...] ...)]{
Adds explicit phase sequences to a presentation without changing its mathematical
derivation. Keys are captured as symbols or nonempty lists. Complete case-plus-step
paths take precedence over derivation-relative paths, then local-name shorthand,
then defaults. Shorthand matching different relative leaf paths is rejected.
Composite moves are not elementary phase targets. Duplicate keys in one call are
rejected. Use a precise address to replace an existing precise override.
@racketblock[
(choreograph plan
  [cancel-five (retire-cancelled #:duration 2/5)
               (hold 1/2)
               (compact #:duration 2/5)])]
}

@defproc[(presentation-style? [value any/c])
         boolean?]{
Reports whether its argument is a presentation-style value.
}


@defproc[(presentation-style-anchor [record presentation-style?])
         symbol?]{
Returns the anchor field: relation or center alignment.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(presentation-style-history [record presentation-style?])
         symbol?]{
Returns the history field: retained checkpoint policy.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(presentation-style-start-group [record presentation-style?])
         symbol?]{
Returns the start-group field: copy or replacement policy.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(presentation-style-new-parts [record presentation-style?])
         symbol?]{
Returns the new-parts field: validated appearance effect.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(presentation-style-removed-parts [record presentation-style?])
         symbol?]{
Returns the removed-parts field: validated disappearance effect.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(presentation-style-reflow [record presentation-style?])
         symbol?]{
Returns the reflow field: staged or simultaneous layout changes.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(presentation-style-multiplication [record presentation-style?])
         symbol?]{
Returns the multiplication field: school or explicit notation.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(presentation-style-pause-between-groups [record presentation-style?])
         (and/c real? (>=/c 0))]{
Returns the pause-between-groups field: seconds of reading time after each group.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(presentation-style-duration [record presentation-style?])
         (and/c real? positive?)]{
Returns the duration field: default step duration in seconds.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(presentation-style-font-size [record presentation-style?])
         (and/c real? positive?)]{
Returns the font-size field: formula size in local world units.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(presentation-style-row-gap [record presentation-style?])
         (and/c real? positive?)]{
Returns the row-gap field: requested row separation in world units.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(presentation-style-max-visible-rows [record presentation-style?])
         exact-positive-integer?]{
Returns the max-visible-rows field: at least two visible rows.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(presentation-plan? [value any/c])
         boolean?]{
Reports whether its argument is a presentation-plan value.
}


@defproc[(presentation-plan-source [record presentation-plan?])
         any/c]{
Returns the source field: original derivation, cases, or candidate check.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(presentation-plan-style [record presentation-plan?])
         math-presentation?]{
Returns the style field: validated immutable presentation policy.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(presentation-plan-segments [record presentation-plan?])
         (listof plan-segment?)]{
Returns the segments field: chronological branch presentations.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(presentation-plan-choreography [record presentation-plan?])
         (and/c hash? immutable?)]{
Returns the choreography field: step or case-step keys to ordered phase lists.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(presentation-plan-allow-unverified? [record presentation-plan?])
         boolean?]{
Returns the allow-unverified? field: whether a visible draft warning is required.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(plan-segment? [value any/c])
         boolean?]{
Reports whether its argument is a plan-segment value.
}


@defproc[(plan-segment-path [record plan-segment?])
         (listof symbol?)]{
Returns the path field: case path in declared branch order.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(plan-segment-derivation [record plan-segment?])
         derivation?]{
Returns this segment's mathematical steps. A shared segment contains just its
common prefix; a branch suffix starts at the corresponding prefix endpoint.
Under @racket['complete-paths], the segment contains the entire selected leaf.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(plan-segment-groups [record plan-segment?])
         list?]{
Returns the normalized ordered partition of elementary keys. A flat root leaf uses
a symbol; a nested leaf uses its complete derivation-relative symbol path.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(plan-segment-context [record plan-segment?])
         math-context?]{
Returns the context field: context displayed with this segment.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(plan-segment-verdict [record plan-segment?])
         (or/c verification? #f)]{
Returns the verdict field: optional candidate-check report.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(plan-segment-shared? [record plan-segment?]) boolean?]{
Reports whether this segment presents a common mathematical prefix rather than
one terminal case. A true result does not itself assert a completed solution.
}


@defproc[(presentation-phase? [value any/c])
         boolean?]{
Reports whether its argument is a presentation-phase value.
}


@defproc[(presentation-phase-kind [record presentation-phase?])
         symbol?]{
Returns the kind field: phase behavior.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(presentation-phase-duration [record presentation-phase?])
         (and/c real? (>=/c 0))]{
Returns the duration field: seconds; zero allowed only for an explicit hold.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(presentation-phase-effect [record presentation-phase?])
         symbol?]{
Returns the effect field: fade, move, or none.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(presentation-phase-layout [record presentation-phase?])
         symbol?]{
Returns the layout field: held or destination layout.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(presentation-phase-annotation [record presentation-phase?])
         (or/c #f (list/c math? string?))]{
Returns the held state and immutable single-line caption for an explanatory
inset, or @racket[#f] for an ordinary phase. Inspection performs no typesetting.
}


@defproc[(scheduled-phase? [value any/c])
         boolean?]{
Reports whether its argument is a scheduled-phase value.
}


@defproc[(scheduled-phase-segment [record scheduled-phase?])
         exact-nonnegative-integer?]{
Returns the segment field: zero-based segment index.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(scheduled-phase-step [record scheduled-phase?])
         (or/c symbol? (listof symbol?) #f)]{
Returns the canonical derivation-relative leaf key: a symbol for a flat root leaf,
a full symbol list for a nested leaf, or @racket[#f] for group/segment phases.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(scheduled-phase-kind [record scheduled-phase?])
         symbol?]{
Returns the kind field: scheduled phase category.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(scheduled-phase-start [record scheduled-phase?])
         (and/c real? (>=/c 0))]{
Returns the start field: absolute start time in seconds.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(scheduled-phase-duration [record scheduled-phase?])
         (and/c real? (>=/c 0))]{
Returns the duration field: phase duration in seconds.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(scheduled-phase-group [record scheduled-phase?])
         exact-integer?]{
Returns the group field: group index; minus one before the first group.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(scheduled-phase-phase [record scheduled-phase?])
         (or/c presentation-phase? #f)]{
Returns the phase field: explicit effect description when applicable.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(math-checkpoint? [value any/c])
         boolean?]{
Reports whether its argument is a math-checkpoint value.
}


@defproc[(math-checkpoint-index [record math-checkpoint?])
         exact-nonnegative-integer?]{
Returns the index field: stable chronological checkpoint index.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(math-checkpoint-segment [record math-checkpoint?])
         exact-nonnegative-integer?]{
Returns the segment field: owning segment index.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(math-checkpoint-step [record math-checkpoint?])
         (or/c symbol? (listof symbol?) #f)]{
Returns the canonical committed leaf key (symbol or full relative symbol path),
or @racket[#f] for the initial state.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(math-checkpoint-time [record math-checkpoint?])
         (and/c real? (>=/c 0))]{
Returns the time field: absolute commit time in seconds.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(math-checkpoint-state [record math-checkpoint?])
         math?]{
Returns the state field: committed mathematical state.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(math-checkpoint-case-path [record math-checkpoint?])
         (listof symbol?)]{
Returns the case-path field: owning case path.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(plan-checkpoints [plan presentation-plan?])
         immutable-vector?]{
Assigns deterministic checkpoint indices in chronological plan order.
}


@defproc[(checkpoint-at [plan presentation-plan?]
         [time (and/c real? (>=/c 0))])
         math-checkpoint?]{
Returns the latest committed mathematical checkpoint at the requested time.

Returns the latest mathematical checkpoint at or before the requested
time. Animation interiors do not invent partial mathematical assertions.
}


@defproc[(plan-schedule [plan presentation-plan?])
         (listof scheduled-phase?)]{
Computes an ordered exact-time phase schedule without creating native scenes.

Entries are in chronological order, with zero-duration mathematical
checkpoint records included. These data describe presentation; they are not a
second frame-sampling engine. Native compilation uses ordinary animate scenes.
}


@defproc[(plan-duration [plan presentation-plan?])
         (and/c real? (>=/c 0))]{
Sums the phase durations in seconds; exact inputs retain exactness.
}


@defproc[(plan-inspect [plan presentation-plan?]
         [t (and/c real? (>=/c 0))])
         scheduled-phase?]{
Selects a half-open phase interval, with the final endpoint handled explicitly.

Time lies in the closed interval from zero to @racket[plan-duration].
Active phase intervals are half-open. The total endpoint returns the final phase.
}


@defproc[(prepare-space [#:duration d (and/c real? positive?) 1/2])
         presentation-phase?]{
Moves preserved material to reserve space before revealing new parts.

Moves surviving parts to prepared positions before new material appears.
The duration is measured in seconds and must be positive and finite.
}


@defproc[(reveal-created [#:effect effect symbol? 'fade]
         [#:duration d (and/c real? positive?) 2/5])
         presentation-phase?]{
Fades in newly introduced material after space has been prepared.

Fades newly created material in while the established layout is held.
Only @racket['fade] is supported in this release.
}


@defproc[(retire-cancelled [#:effect effect symbol? 'fade]
         [#:layout layout symbol? 'hold]
         [#:duration d (and/c real? positive?) 2/5])
         presentation-phase?]{
Fades cancelled material while holding the surrounding layout fixed.

Fades cancelled material out without moving surviving parts. Only
@racket['fade] and @racket['hold] layout are supported. Follow with a hold and
@racket[compact] to separate cancellation from closing the resulting gap.
}


@defproc[(retire-removed [#:effect effect symbol? 'fade]
         [#:layout layout symbol? 'hold]
         [#:duration d (and/c real? positive?) 2/5])
         presentation-phase?]{
Fades removed material while holding the surrounding layout fixed.

Uses the same held-layout retirement mechanism as cancellation but
names a general removal event. It does not implicitly compact the expression.
}


@defproc[(compact [#:duration d (and/c real? positive?) 2/5])
         presentation-phase?]{
Closes reserved gaps by moving survivors to their prepared positions.

Moves surviving parts to their complete destination layout after
retirement. The duration is positive and finite seconds. Reordered signed terms
move in rigid units along two separated native-motion legs. Cancellation that
creates a unit coefficient introduces that coefficient only after compaction;
an explicit @racket[reveal-created] phase can separate those actions further.
}


@defproc[(hold [d (and/c real? (>=/c 0))])
         presentation-phase?]{
Retains the current presentation state for a nonnegative duration.

The duration may be zero. A hold adds no mathematical checkpoint or
scene-state mutation.
}


@defproc[(explain-math [state (or/c math? math-datum?)]
         [#:caption caption string? ""]
         [#:duration duration (and/c real? positive?) 2])
         presentation-phase?]{
Introduces a held mathematical inset without changing the working derivation.
The caption must be a single line. Native preparation typesets the complete
inset with the lesson and reserves a lower display band. The inset fades in for
one fifth of its duration, holds for three fifths, then fades out for one fifth.
It advances presentation time but does not add or advance a mathematical
checkpoint. The author supplies the explanatory content; this is not a new
proof rule or an implicit CAS calculation.
@racketblock[
(choreograph plan
  [add-nine
    (explain-math '(= (expt (/ 6 2) 2) 9)
                  #:caption "Half the coefficient of x, then square it")
    (prepare-space)
    (reveal-created)])]
}


@defproc[(transition [#:duration d (and/c real? positive?) 4/5])
         presentation-phase?]{
Performs a semantic replacement without displaying a hybrid expression.
The outgoing mathematical unit fades out during the first @math{9/20} of the
duration, survivors move during @math{1/10}, and the incoming unit fades in
during the final @math{9/20}. The new unit is invisible until all outgoing ink
has disappeared. This visibility barrier also applies under simultaneous reflow.
Unaffected expressions keep their provenance and are not glyph-matched by shape.
}


@defproc[(plan-with-choreography [plan presentation-plan?]
         [overrides list?])
         presentation-plan?]{
Validates named phase overrides and returns a new immutable plan.

Overrides are an ordered list of @racket[(cons step-key phases)]. A key
is a step name or a list of branch symbols followed by the step name. Each phase
list is nonempty. Unknown keys, duplicate keys within one call, and invalid phase
values are rejected. A case-specific override takes precedence over an unqualified
step-name override.
}



@section{Explicit Rendering Adapter}
@defmodule[animate/math/render]


These functions may load native dependencies and create cached assets. They are not imported by @racketmodname[animate/math].


@defproc[(math-plan->scene! [plan-or-prepared (or/c presentation-plan? prepared-math-plan?)]
         [#:camera camera any/c #f]
         [#:theme theme (or/c #f 'light 'dark) #f]
         [#:title title string? "Mathematical derivation"]
         [#:id id symbol? 'math-lesson]
         [#:cache-directory directory path-string? default-math-cache-directory])
         scene?]{
Prepares when necessary and compiles the lesson into the existing native scene engine.

Accepts a presentation plan or a prepared plan. An unprepared plan is
prepared before native scene assembly. Prepared plans capture their camera/theme;
supplying inconsistent options is rejected. The result is an ordinary animate
scene using existing movement, opacity, presence, and wait operations. Sampling
that scene performs no mathematical rewrites, CAS calls, or TeX execution.
}


@defproc[(prepare-math-plan! [plan presentation-plan?]
         [#:camera camera any/c #f]
         [#:theme theme symbol? 'light]
         [#:cache-directory cache-directory path-string? default-math-cache-directory])
         prepared-math-plan?]{
Typesets and measures all checkpoints before native scene construction or sampling.

May load native modules, launch trusted TeX and dvisvgm processes, measure
SVG geometry, and write cached assets. Preparation typesets each complete formula;
it never independently typesets leaves and guesses their spacing. Layout is fit
to the explicit camera or a native default camera. The camera's visible width
must exceed the 7/5-world-unit layout margin. The prepared result stores immutable
adapter data; it is not a new mathematical AST.
}


@defproc[(math->visual! [state math?]
         [#:id id symbol? 'math-snapshot]
         [#:font-size font-size (and/c real? positive?) 11/20]
         [#:theme theme (or/c 'light 'dark) 'light]
         [#:cache-directory directory path-string? default-math-cache-directory])
         visual?]{
Typesets one complete mathematical state and creates an ordinary native group.

Prepares the complete expression and returns a native group of ordered
SVG asset references. Cache files must remain available while the resulting Visual
is rendered. Font size is measured in world units.
}


@defproc[(math-plan->pict! [plan (or/c presentation-plan? prepared-math-plan?)]
         [time (and/c real? (>=/c 0))]
         [#:theme theme (or/c #f 'light 'dark) #f]
         [#:camera camera any/c #f]
         [#:renderers renderers (or/c list? #f) #f])
         pict?]{
Renders one sampled native frame using the explicit camera and renderer selection.

Prepares or uses the supplied plan, constructs its native scene, and
renders the requested time. The explicit renderer list is passed unchanged to
@tt{scene-state->pict}, along with the keyword camera argument. False selects
animate's default renderer list. False theme retains a prepared plan's captured
theme; an unprepared plan defaults to light. Layout uses the prepared complete-SVG
metrics. Custom renderer padding is not remeasured by this conversion, so a
renderer that changes extents may need explicitly adjusted layout.
This convenience function is effectful; prepare and compile once when sampling
many frames.
}


@defproc[(prepared-math-plan? [value any/c])
         boolean?]{
Reports whether its argument is a prepared-math-plan value.
}


@defproc[(prepared-math-plan-plan [record prepared-math-plan?])
         presentation-plan?]{
Returns the plan field: original immutable presentation.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(prepared-math-plan-layouts [record prepared-math-plan?])
         (and/c hash? immutable?)]{
Returns the layouts field: checkpoint states to prepared layouts.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(prepared-math-plan-schedule [record prepared-math-plan?])
         (listof scheduled-phase?)]{
Returns the schedule field: ordered frozen phase schedule.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(prepared-math-plan-camera [record prepared-math-plan?])
         any/c]{
Returns the camera field: explicit native camera used during preparation.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(prepared-math-plan-foreground [record prepared-math-plan?])
         string?]{
Returns the foreground field: prepared ink color.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(prepared-math-plan-background [record prepared-math-plan?])
         string?]{
Returns the background field: prepared background color.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(prepared-math-plan-row-gap [record prepared-math-plan?])
         (and/c real? positive?)]{
Returns the row-gap field: measured row separation in world units.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(prepared-math-plan-max-rows [record prepared-math-plan?])
         exact-positive-integer?]{
Returns the max-rows field: visible row limit.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(prepared-math-plan-diagnostics [record prepared-math-plan?])
         (listof string?)]{
Returns the diagnostics field: notes in checkpoint order, never hash iteration order.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(prepared-layout? [value any/c])
         boolean?]{
Reports whether its argument is a prepared-layout value.
}


@defproc[(prepared-layout-state [record prepared-layout?])
         math?]{
Returns the state field: exact input checkpoint.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(prepared-layout-tokens [record prepared-layout?])
         (listof prepared-token?)]{
Returns the tokens field: parts in deterministic drawing order with unique IDs.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(prepared-layout-source [record prepared-layout?])
         math-source?]{
Returns the source field: complete source and semantic ranges.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(prepared-layout-diagnostics [record prepared-layout?])
         (listof (and/c string? immutable?))]{
Returns the diagnostics field: ordered preparation notes.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(prepared-token? [value any/c])
         boolean?]{
Reports whether its argument is a prepared-token value.
}


@defproc[(prepared-token-path [record prepared-token?])
         (listof exact-nonnegative-integer?)]{
Returns the path field: mathematical owner in one checkpoint.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(prepared-token-role [record prepared-token?])
         symbol?]{
Returns the role field: owned mathematical or operator role.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(prepared-token-text [record prepared-token?])
         (and/c string? immutable?)]{
Returns the text field: copied complete source fragment.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(prepared-token-asset [record prepared-token?])
         (and/c string? immutable?)]{
Returns the asset field: frozen SVG asset reference, not a live renderer.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(prepared-token-x [record prepared-token?])
         real?]{
Returns the x field: center coordinate in local y-up world units.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(prepared-token-y [record prepared-token?])
         real?]{
Returns the y field: center coordinate in local y-up world units.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(prepared-token-width [record prepared-token?])
         (and/c real? positive?)]{
Returns the width field: measured prepared width in world units.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(prepared-token-height [record prepared-token?])
         (and/c real? positive?)]{
Returns the height field: measured prepared height in world units.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(prepared-token-id [record prepared-token?])
         symbol?]{
Returns the id field: unique prepared/view identity.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defthing[default-math-cache-directory path?]{
Names the adapter-owned content-addressed SVG cache directory.

The default asset directory is @tt{animate-math/svg-v1} under Racket's preference directory.
Treat it as an adapter cache, not a portable source artifact. A production build
may pass an explicit cache directory that remains available during rendering.
}


@section{Computer Algebra Services}
@defmodule[animate/math/cas]


@defstruct*[cas-service ([name symbol?] [version any/c]
                            [capabilities (listof symbol?)] [query procedure?])
                            #:transparent]{
A validated service descriptor. The name identifies the provider, version is
copied acyclic metadata, and capability order is retained. Version metadata
may contain ordinary data containers, but not procedures, cycles, or opaque
native resources. The callback must accept
three positional arguments and require no keyword arguments. It is executed
only through an explicit query boundary. The descriptor is immutable, but the
external callback may perform effects and must not be stored in scene state.
}

@defstruct*[cas-result ([status (or/c 'ok 'unknown 'unsupported 'unavailable 'timeout 'error)]
                           [value any/c] [evidence (or/c verification? #f)]
                           [diagnostics (listof string?)]) #:transparent]{
A validated external-service response. The value may be opaque backend data;
it is not inserted into a mathematical state automatically. Evidence is optional,
and diagnostics are copied into immutable strings in significant order. A failed
status cannot supply an established or refuted decision at the query boundary.
Verification reports copy the status, evidence, and diagnostics only; the opaque
value is not retained inside the mathematical evidence.
}

@defproc[(math-services [#:local local (or/c cas-service? #f) #f]
         [#:extended extended (or/c cas-service? #f) #f])
         math-services?]{
Collects optional local and extended service descriptors without executing them.

The local and extended descriptors are optional; false disables that
position. Construction does not execute a service callback. Local lookup order is
preserved before the extended service.
}


@defproc[(math-services? [value any/c])
         boolean?]{
Recognizes a pair of configured CAS service descriptors.
}


@defproc[(math-services-local [record math-services?])
         (or/c cas-service? #f)]{
Returns the configured service without loading its backend.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(math-services-extended [record math-services?])
         (or/c cas-service? #f)]{
Returns the configured service without loading its backend.

This accessor is pure. It does not copy, reorder, render, or mutate the record.
}


@defproc[(cas-query! [service cas-service?]
         [capability symbol?]
         [payload any/c]
         [context math-context?]
         [#:timeout timeout (and/c real? positive?) 10])
         cas-result?]{
Runs one bounded backend query and shuts down its custodian after every outcome.

The capability must be declared by the service. The callback receives
capability, payload, and mathematical context and must return one @racket[cas-result].
The positive finite timeout is in seconds and applies to this individual call.
A custodian terminates the owned thread on completion or timeout. This is a
resource boundary, not a security sandbox. Exceptions, invalid callback results,
evidence for another proposition, and decisions attached to failed statuses
become explicit error results.
}


@defproc[(cas-calculate! [service cas-service?]
         [operation symbol?]
         [datum math-datum?]
         [#:context context math-context? (math-context)]
         [#:timeout timeout (and/c real? positive?) 10])
         cas-result?]{
Requests a backend calculation without changing held presentation syntax.

Packages @racket[(list operation datum)] as a calculate query. The result
value is a proposed calculation result, never an invented pedagogical trace.
}


@defproc[(verify-derivation! [d (or/c derivation? case-derivation?)]
         [#:services backends math-services? (math-services)]
         [#:timeout timeout (and/c real? positive?) 10])
         verification?]{
Rechecks pending obligations without mutating the recorded derivation or its evidence.

Rechecks recorded unresolved obligations and returns new evidence. It
does not mutate or retroactively relabel the original derivation. Case coverage
records remain explicit. The timeout is per backend call, not a whole-derivation
deadline.
}


@defproc[(verify-proposition! [proposition math-datum?]
         [context math-context?]
         [#:services backends math-services? (math-services)]
         [#:timeout timeout (and/c real? positive?) 10])
         verification?]{
Checks definedness and queries explicit CAS services without silently resolving disagreements.

Checks local definedness first, then queries configured services when
needed. Only successful matching evidence can supply a decision. Conflicting
established/refuted service reports remain unknown; no backend silently wins.
}


@defproc[(call-with-math-services! [backends math-services?]
         [thunk procedure?]
         [#:timeout timeout (and/c real? positive?) 10])
         any]{
Installs explicit CAS services only for the dynamic extent of one construction callback.

Installs an explicit construction-time prover around a zero-argument
thunk. The thunk may trigger bounded CAS calls while constructing mathematics.
The service callbacks are not retained in the resulting animation scene.
}



@section{Optional Calcura Provider}
@defmodule[animate/math/cas/calcura]


@defproc[(calcura-service [#:module module any/c #f]
         [#:version version any/c 'configured]
         [#:query query (or/c procedure? #f) #f]
         [#:loader loader procedure? dynamic-require])
         cas-service?]{
Configures a lazy Calcura parser/Eval bridge without claiming unavailable capabilities.

No Calcura dependency is loaded during construction. Supply a module path
or an explicit three-argument query callback. The default bridge uses
@tt{parse-input-form-string} and @tt{Eval}; it accepts only recognized literal
truth values as decisions. The injected loader accepts a module path and a symbol.
Calls that cannot load the configured backend remain explicit failures.
}


@defproc[(datum->calcura-input [datum math-datum?])
         string?]{
Serializes the supported exact fragment with collision-resistant variable names.

Supports exact rational constants and the adapter's declared scalar
operator vocabulary. Scoped definitions should be expanded before transport.
Ordinary variable names are encoded in a dedicated namespace. Unsupported symbols
or operators are rejected rather than interpolated as arbitrary executable input.
}



@section{Optional Racket CAS Provider}
@defmodule[animate/math/cas/racket-cas]


@defproc[(racket-cas-service [#:module module any/c 'racket-cas]
         [#:version version any/c 'installed]
         [#:loader loader procedure? dynamic-require])
         cas-service?]{
Configures a lazy racket-cas bridge without importing it during construction.

Builds a lazy descriptor. The default module is @racket['racket-cas].
Supported calculate operations are @racket['normalize], @racket['expand],
@racket['simplify], and @racket['together]. A normalization result is not an
explanatory trace. The injected loader accepts a module path and export name.
}



@section{Build and integration}

The manual is registered by @tt{math/info.rkt}. A normal setup discovers the
subcollection manual without rewriting the parent package metadata. It can also
be built from the repository root:
@verbatim{scribble --htmls --dest math-output/docs math/scribblings/math.scrbl}

The parent @tt{scribblings/animate.scrbl} remains unchanged in this folder-only
delivery. It can link to this registered reference, or explicitly include its
section in a later repository-wide documentation change.

The mandatory tests require only the base Racket distribution. Native probes
require the actual animate checkout and its rendering dependencies. The optional
Rhombus example requires Rhombus. Neither a synthetic native contract test nor a
static documentation coverage check is presented as a real renderer or a
successful Scribble build.
