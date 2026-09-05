#lang racket/base

;;;
;;; Formula Part Transition Model
;;;

;; Compiles and samples deterministic transitions between explicitly matched
;; formula parts.
;;
;; This module contains no Pict, drawing-context, bitmap, filesystem, process,
;; browser, or JavaScript dependencies.


;;;
;;; Imports and Exports
;;;

;; Imports
(require (only-in racket/math pi)
         "affine-transform.rkt"
         "formula-parts-visual.rkt"
         "formula-source-normalization.rkt"
         "formula-visual.rkt"
         "geometry.rkt"
         "glyph-outline-morph-visual.rkt"
         "path-geometry.rkt"
         "visual-model.rkt")

;; Exports
(provide formula-arc
         formula-arc?
         formula-arc-angle
         formula-relative-path
         formula-relative-path?
         formula-relative-path-geometry
         formula-route?
         formula-route-position-at
         formula-mismatch-mode?
         formula-part-path
         formula-part-path?
         formula-part-path-source-name
         formula-part-path-destination-name
         formula-part-path-route
         (struct-out formula-part-appearance-trigger)
         formula-part-copy
         formula-part-copy?
         formula-part-copy-source-name
         formula-part-copy-destination-name
         formula-part-copy-route
         (struct-out formula-part-outline-morph)
         (struct-out formula-transition-route)
         formula-transition-plan?
         make-formula-transition-plan
         formula-transition-plan-source-parts
         formula-transition-plan-destination-parts
         formula-transition-plan-match-routes
         formula-transition-plan-source-map-at
         formula-transition-plan-sample-parts)


;;;
;;; Compiled Transition Data
;;;

;; A formula arc is a route descriptor rather than a precomputed path: its
;; concrete endpoints are known only when scene-play compiles a transition.
(struct formula-arc-route (angle)
  #:transparent
  #:guard
  (lambda (angle who)
    (unless (finite-real? angle)
      (raise-argument-error who "finite real?" angle))
    (unless (< (abs angle) (* 2 pi))
      (raise-arguments-error
       who
       "an arc angle whose magnitude is smaller than 2*pi"
       "angle" angle))
    angle))

; formula-arc : #:angle finite-real? -> formula-arc?
;; Describes a circular source-to-destination route. Positive angles travel
;; counter-clockwise in the formula's local coordinates. Zero is straight.
(define (formula-arc #:angle angle)
  (formula-arc-route angle))

(define formula-arc? formula-arc-route?)
(define formula-arc-angle formula-arc-route-angle)

;; A relative path is expressed in a unit chord coordinate system: `(0, 0)` is
;; the source centre and `(1, 0)` is the destination centre.  At compilation
;; it is mapped onto the actual source/destination chord, with positive local
;; y pointing to the chord's left.  This keeps author supplied routes portable
;; across formula layout changes.
(struct formula-relative-path-route (geometry)
  #:transparent
  #:guard
  (lambda (geometry who)
    (unless (path-geometry? geometry)
      (raise-argument-error who "path-geometry?" geometry))
    (unless (positive? (path-geometry-length geometry))
      (raise-arguments-error
       who
       "a nonempty route with positive length"
       "path" geometry))
    (unless (vec2-coordinate=? (path-geometry-point-at geometry 0)
                               (vec2 0 0))
      (raise-arguments-error
       who
       "a route beginning at (vec2 0 0)"
       "start" (path-geometry-point-at geometry 0)))
    (unless (vec2-coordinate=? (path-geometry-point-at geometry 1)
                               (vec2 1 0))
      (raise-arguments-error
       who
       "a route ending at (vec2 1 0)"
       "end" (path-geometry-point-at geometry 1)))
    geometry))

; formula-relative-path : path-geometry? -> formula-relative-path?
;; Describes an arbitrary source-to-destination route in unit chord
;; coordinates.  The path must begin at `(vec2 0 0)` and end at `(vec2 1 0)`.
(define (formula-relative-path geometry)
  (formula-relative-path-route geometry))

(define formula-relative-path? formula-relative-path-route?)
(define formula-relative-path-geometry formula-relative-path-route-geometry)

; formula-route? : any/c -> boolean?
;; Recognises a supported formula-part movement route.
(define (formula-route? value)
  (or (formula-arc? value)
      (formula-relative-path? value)))

; formula-mismatch-mode? : any/c -> boolean?
;; Recognises the policies for source/destination formula parts that have no
;; correspondence.  `fade` leaves each one in place while fading it; a
;; `fade-transform` pairs remaining source and destination parts by order and
;; cross-fades each pair while it travels between its endpoints.
(define (formula-mismatch-mode? value)
  (and (memq value '(fade fade-transform)) #t))

;; formula-part-path selects one named formula correspondence for a route.
(struct formula-part-path (source-name destination-name route)
  #:transparent
  #:guard
  (lambda (source-name destination-name route who)
    (unless (symbol? source-name)
      (raise-argument-error who "symbol?" source-name))
    (unless (symbol? destination-name)
      (raise-argument-error who "symbol?" destination-name))
    (unless (formula-route? route)
      (raise-argument-error who "formula-route?" route))
    (values source-name destination-name route)))

;; Keeps a changed fragment on its ordinary motion route while making its
;; replacement fully visible when that route first reaches a reference part's
;; x-coordinate. `duration` is the short normalized-progress lead-in.
(struct formula-part-appearance-trigger
  (source-name destination-name reference-source-name duration)
  #:transparent
  #:guard
  (lambda (source-name destination-name reference-source-name duration who)
    (unless (symbol? source-name)
      (raise-argument-error who "symbol?" source-name))
    (unless (symbol? destination-name)
      (raise-argument-error who "symbol?" destination-name))
    (unless (symbol? reference-source-name)
      (raise-argument-error who "symbol?" reference-source-name))
    (unless (and (finite-real? duration) (positive? duration) (<= duration 1))
      (raise-argument-error who "positive finite real in [0, 1]" duration))
    (values source-name destination-name reference-source-name duration)))

;; formula-part-copy directs one existing source part to an otherwise unmatched
;; destination part while leaving the source part in place.  It is the
;; formula-aware counterpart of TransformFromCopy.
(struct formula-part-copy (source-name destination-name route)
  #:transparent
  #:guard
  (lambda (source-name destination-name route who)
    (unless (symbol? source-name)
      (raise-argument-error who "symbol?" source-name))
    (unless (symbol? destination-name)
      (raise-argument-error who "symbol?" destination-name))
    (unless (formula-route? route)
      (raise-argument-error who "formula-route?" route))
    (values source-name destination-name route)))

;; formula-part-outline-morph supplies one conservative interior replacement
;; for an explicitly matched pair.  The endpoints remain their original
;; tagged SVG fragments; source/destination paths have already been aligned
;; and normalized by the glyph adapter before this generic transition compiler
;; sees them.
(struct formula-part-outline-morph
  (source-name destination-name source-path destination-path fill stroke stroke-width)
  #:transparent
  #:guard
  (lambda (source-name destination-name source-path destination-path
                       fill stroke stroke-width who)
    (unless (symbol? source-name)
      (raise-argument-error who "symbol?" source-name))
    (unless (symbol? destination-name)
      (raise-argument-error who "symbol?" destination-name))
    (unless (path-geometry-morph-compatible? source-path destination-path)
      (raise-arguments-error
       who
       "compatible normalized path geometries"
       "source-path" source-path
       "destination-path" destination-path))
    (unless (and (finite-real? stroke-width) (not (negative? stroke-width)))
      (raise-argument-error who "nonnegative finite real?" stroke-width))
    (values source-name destination-name source-path destination-path
            fill stroke stroke-width)))

(define straight-formula-route (formula-arc #:angle 0))

(struct formula-transition-layer
  (name template from-transform to-transform route from-opacity to-opacity
        appearance-start appearance-end)
  #:transparent)

;; formula-transition-layer represents one independently rendered interior layer.
;;  - name            symbol?             deterministic temporary local identity.
;;  - template        formula-visual?     source of LaTeX and typesetting data.
;;  - from-transform  affine-transform?   local transform at progress zero.
;;  - to-transform    affine-transform?   local transform at progress one.
;;  - route           formula-route?      local translation trajectory.
;;  - from-opacity    opacity?            local opacity at progress zero.
;;  - to-opacity      opacity?            local opacity at progress one.
;;  - appearance-start/end finite-real?   replacement's local timing window.

(struct formula-transition-route
  (source-name destination-name from-transform to-transform route)
  #:transparent)

;; formula-transition-route records one author-visible correspondence after it
;; has been compiled against the current source formula. It is deliberately
;; separate from temporary transition layers: a changed fragment may render as
;; two fading layers, but it still has one semantic source-to-destination path.

(struct formula-transition-plan
  (source-parts layers destination-parts source-map destination-source-map routes)
  #:transparent)

;; formula-transition-plan represents one compiled formula-part transformation.
;;  - source-parts       (listof formula-part?)  exact current source order.
;;  - layers             (listof formula-transition-layer?)
;;                       deterministic interior drawing order.
;;  - destination-parts  (listof formula-part?)  exact destination order.
;;  - source-map         any/c                   exact source endpoint metadata.
;;  - destination-source-map any/c               exact destination endpoint metadata.
;;  - routes             (listof formula-transition-route?) semantic movement
;;                       descriptions independent of temporary layer names.
;;
;; The layer order is source-only parts, matched layers in correspondence order,
;; and destination-only parts. A changed matched part contributes a source layer
;; followed by a destination layer.

(struct formula-transition-spec
  (template from-transform to-transform route from-opacity to-opacity
            appearance-start appearance-end)
  #:transparent)

;; formula-transition-spec is one layer before a temporary name is allocated.
;;  - template        formula-visual?    source of LaTeX and typesetting data.
;;  - from-transform  affine-transform?  local transform at progress zero.
;;  - to-transform    affine-transform?  local transform at progress one.
;;  - route           formula-route?     local translation trajectory.
;;  - from-opacity    opacity?           local opacity at progress zero.
;;  - to-opacity      opacity?           local opacity at progress one.
;;  - appearance-start/end finite-real?  replacement's local timing window.


;;;
;;; Plan Construction
;;;

; make-formula-transition-plan : formula-assembly-visual?
;                                formula-correspondence?
;                                [#:path-arc finite-real?]
;                                [#:part-paths (listof formula-part-path?)]
;                                [#:appearance-triggers
;                                 (listof formula-part-appearance-trigger?)]
;                                [#:copies (listof formula-part-copy?)]
;                                [#:mismatch-mode formula-mismatch-mode?]
;                                [#:outline-morphs (listof formula-part-outline-morph?)]
;                                -> formula-transition-plan?
;;   Compiles correspondence against the current source assembly.
(define (make-formula-transition-plan current-source correspondence
                                      #:path-arc [path-arc 0]
                                      #:part-paths [part-paths '()]
                                      #:appearance-triggers [appearance-triggers '()]
                                      #:copies [copies '()]
                                      #:mismatch-mode [mismatch-mode 'fade]
                                      #:outline-morphs [outline-morphs '()])
  (unless (formula-assembly-visual? current-source)
    (raise-argument-error
     'make-formula-transition-plan
     "formula-assembly-visual?"
     current-source))
  (unless (formula-correspondence? correspondence)
    (raise-argument-error
     'make-formula-transition-plan
     "formula-correspondence?"
     correspondence))
  (unless (formula-mismatch-mode? mismatch-mode)
    (raise-argument-error
     'make-formula-transition-plan
     "(or/c 'fade 'fade-transform)"
     mismatch-mode))
  (check-current-source-names current-source correspondence)
  (define destination
    (formula-correspondence-destination correspondence))
  (define destination-parts
    (formula-assembly-visual-parts destination))
  (define default-route (formula-arc #:angle path-arc))
  (define part-paths-by-match
    (make-part-paths-by-match correspondence part-paths))
  (define appearance-windows-by-match
    (make-appearance-windows-by-match
     current-source correspondence default-route part-paths-by-match
     appearance-triggers))
  (define copies-by-destination
    (make-copies-by-destination current-source correspondence copies))
  (define outline-morphs-by-match
    (make-outline-morphs-by-match correspondence outline-morphs))
  ;; A tagged TeX fragment has a crop from the complete formula in which it
  ;; was typeset. Two fragments with equivalent visible TeX can consequently
  ;; have distinct SVG view boxes. Retain the source artifact for an unchanged
  ;; fragment at its destination transform: interior and endpoint frames then
  ;; use the same glyph geometry instead of swapping crops on the final frame.
  (define settled-destination-parts
    (settle-destination-parts
     destination-parts
     (make-endpoint-templates-by-destination
      current-source correspondence copies-by-destination)))
  (formula-assembly-visual-with-parts current-source settled-destination-parts)
  (define-values (mismatch-before-specs mismatch-after-specs)
    (make-mismatch-specs current-source
                         correspondence
                         default-route
                         mismatch-mode
                         (hash-keys copies-by-destination)))
  (define specs
    (append
     mismatch-before-specs
     (make-matched-specs current-source
                         correspondence
                         default-route
                         part-paths-by-match
                         appearance-windows-by-match
                         outline-morphs-by-match)
     (make-copy-specs current-source
                      correspondence
                      copies-by-destination)
     mismatch-after-specs))
  (formula-transition-plan
   (formula-assembly-visual-parts current-source)
   (name-transition-specs
    (visual-id current-source)
   current-source
   destination
   specs)
   settled-destination-parts
   (formula-assembly-visual-source-map current-source)
   (formula-assembly-visual-source-map destination)
   (make-transition-routes current-source
                           correspondence
                           default-route
                           part-paths-by-match)))

;; formula-transition-plan-match-routes : formula-transition-plan? symbol? symbol?
;;                                        -> (listof formula-transition-route?)
;; Returns the compiled routes for one named semantic correspondence. The list
;; form leaves room for future one-to-many transparent specifications, while
;; today's ordinary formula correspondence is one-to-one.
(define (formula-transition-plan-match-routes plan source-name destination-name)
  (unless (formula-transition-plan? plan)
    (raise-argument-error 'formula-transition-plan-match-routes
                          "formula-transition-plan?" plan))
  (unless (symbol? source-name)
    (raise-argument-error 'formula-transition-plan-match-routes "symbol?" source-name))
  (unless (symbol? destination-name)
    (raise-argument-error 'formula-transition-plan-match-routes "symbol?" destination-name))
  (filter
   (lambda (route)
     (and (eq? source-name (formula-transition-route-source-name route))
          (eq? destination-name (formula-transition-route-destination-name route))))
   (formula-transition-plan-routes plan)))

;; Captures exactly the route selected for every semantic correspondence. The
;; rendering compiler may later split a changed fragment into two cross-fading
;; layers; inspector clients still see one planned route rather than an
;; implementation-detail pair of temporary paths.
(define (make-transition-routes current-source correspondence default-route
                                part-paths-by-match)
  (for/list ([match (in-list (formula-correspondence-matches correspondence))])
    (define source-name (formula-part-match-source-name match))
    (define destination-name (formula-part-match-destination-name match))
    (define source-formula
      (formula-part-formula
       (formula-assembly-visual-ref current-source source-name)))
    (define destination-formula
      (formula-part-formula
       (formula-assembly-visual-ref
        (formula-correspondence-destination correspondence)
        destination-name)))
    (formula-transition-route
     source-name
     destination-name
     (visual-transform source-formula)
     (visual-transform destination-formula)
     (hash-ref part-paths-by-match
               (match-key source-name destination-name)
               default-route))))

; check-current-source-names : formula-assembly-visual?
;                              formula-correspondence?
;                              -> void?
;;   Requires the current source to have the correspondence source namespace.
(define (check-current-source-names current-source correspondence)
  (define expected-names
    (formula-assembly-visual-part-names
     (formula-correspondence-source correspondence)))
  (define current-names
    (formula-assembly-visual-part-names current-source))
  (unless (equal? current-names expected-names)
    (raise-arguments-error
     'scene-play
     "the current formula assembly does not match the correspondence source"
     "visual-id" (visual-id current-source)
     "expected part-names" expected-names
     "current part-names" current-names)))

; make-mismatch-specs : formula-assembly-visual? formula-correspondence?
;                       formula-arc? formula-mismatch-mode?
;                       -> (values (listof formula-transition-spec?)
;                                  (listof formula-transition-spec?))
;; Creates interior layers for unmatched pieces. `fade` preserves the existing
;; stationary fade behaviour. `fade-transform` pairs the remaining source and
;; destination names by their respective orders; every pair receives the same
;; moving cross-fade used for an explicit changed-part correspondence. The two
;; resulting lists preserve the historical layer order: source-side layers,
;; then matched layers, then destination-side layers.
(define (make-mismatch-specs current-source correspondence route mismatch-mode
                             copied-destination-names)
  (define source-names
    (formula-correspondence-unmatched-source-names correspondence))
  (define destination-names
    (filter (lambda (name)
              (not (member name copied-destination-names)))
            (formula-correspondence-unmatched-destination-names correspondence)))
  (case mismatch-mode
    [(fade)
     (values
      (make-unmatched-source-specs current-source source-names)
      (make-unmatched-destination-specs correspondence destination-names))]
    [(fade-transform)
     (define-values (pair-specs remaining-source remaining-destination)
       (make-fade-transform-mismatch-specs current-source
                                           correspondence
                                           source-names
                                           destination-names
                                           route))
     (values
      (append pair-specs
              (make-unmatched-source-specs current-source remaining-source))
      (make-unmatched-destination-specs correspondence
                                        remaining-destination))]))

; make-unmatched-source-specs : formula-assembly-visual? (listof symbol?)
;                               -> (listof formula-transition-spec?)
;; Creates stationary fade-out layers in current source order.
(define (make-unmatched-source-specs current-source source-names)
  (for/list ([name
              (in-list source-names)])
    (define formula
      (formula-part-formula
       (formula-assembly-visual-ref current-source name)))
    (formula-transition-spec
     formula
     (visual-transform formula)
     (visual-transform formula)
     straight-formula-route
     (visual-opacity formula)
     0
     0
     1)))

; make-matched-specs : formula-assembly-visual?
;                      formula-correspondence? formula-arc? hash?
;                      hash? hash?
;                      -> (listof formula-transition-spec?)
;;   Creates moving matched layers in explicit correspondence order.
(define (make-matched-specs current-source correspondence default-route
                            part-paths-by-match appearance-windows-by-match
                            outline-morphs-by-match)
  (define destination
    (formula-correspondence-destination correspondence))
  (apply
   append
   (for/list ([match
               (in-list
                (formula-correspondence-matches correspondence))])
     (define source-formula
       (formula-part-formula
        (formula-assembly-visual-ref
         current-source
         (formula-part-match-source-name match))))
     (define destination-formula
       (formula-part-formula
        (formula-assembly-visual-ref
         destination
         (formula-part-match-destination-name match))))
     (define route
       (hash-ref
        part-paths-by-match
        (match-key (formula-part-match-source-name match)
                   (formula-part-match-destination-name match))
        default-route))
     (define appearance-window
       (hash-ref
        appearance-windows-by-match
        (match-key (formula-part-match-source-name match)
                   (formula-part-match-destination-name match))
        #f))
     (define outline-morph
       (hash-ref
        outline-morphs-by-match
        (match-key (formula-part-match-source-name match)
                   (formula-part-match-destination-name match))
        #f))
     (make-one-match-specs source-formula destination-formula route
                           outline-morph appearance-window))))

; make-copy-specs : formula-assembly-visual? formula-correspondence? hash?
;                   -> (listof formula-transition-spec?)
;; Constructs the independently rendered transient copies in destination order.
(define (make-copy-specs current-source correspondence copies-by-destination)
  (define destination
    (formula-correspondence-destination correspondence))
  (apply
   append
   (for/list ([destination-name
               (in-list
                (formula-assembly-visual-part-names destination))]
              #:when (hash-has-key? copies-by-destination destination-name))
     (define copy
       (hash-ref copies-by-destination destination-name))
     (define source-formula
       (formula-part-formula
        (formula-assembly-visual-ref
         current-source
         (formula-part-copy-source-name copy))))
     (define destination-formula
       (formula-part-formula
        (formula-assembly-visual-ref destination destination-name)))
     (make-one-match-specs source-formula
                           destination-formula
                           (formula-part-copy-route copy)))))

; make-one-match-specs : formula-visual? formula-visual? formula-arc?
;                        -> (listof formula-transition-spec?)
;;   Creates one moving layer or a moving cross-fade pair for a match.
(define (make-one-match-specs source-formula destination-formula route
                              [outline-morph #f]
                              [appearance-window #f])
  (define source-transform
    (visual-transform source-formula))
  (define destination-transform
    (visual-transform destination-formula))
  (define appearance-start (if appearance-window (car appearance-window) 0))
  (define appearance-end (if appearance-window (cdr appearance-window) 1))
  (cond
    [(formula-transition-equivalent? source-formula destination-formula)
     (list
      (formula-transition-spec
       source-formula
       source-transform
       destination-transform
       route
       (visual-opacity source-formula)
       (visual-opacity destination-formula)
       appearance-start
       appearance-end))]
    [outline-morph
     (list
      (formula-transition-spec
       (make-glyph-outline-morph-visual
        source-formula
        (formula-part-outline-morph-source-path outline-morph)
        (formula-part-outline-morph-destination-path outline-morph)
        (formula-part-outline-morph-fill outline-morph)
        (formula-part-outline-morph-stroke outline-morph)
        (formula-part-outline-morph-stroke-width outline-morph))
       source-transform
       destination-transform
       route
       (visual-opacity source-formula)
       (visual-opacity destination-formula)
       appearance-start
       appearance-end))]
    [else
     (list
      (formula-transition-spec
       source-formula
       source-transform
       destination-transform
       route
       (visual-opacity source-formula)
       0
       appearance-start
       appearance-end)
     (formula-transition-spec
       destination-formula
       source-transform
       destination-transform
       route
       0
       (visual-opacity destination-formula)
       appearance-start
       appearance-end))]))

;; make-endpoint-templates-by-destination : formula-assembly-visual?
;;                                              formula-correspondence?
;;                                              hash? -> hash?
;; Selects the rendering template to retain for every semantically unchanged
;; matched or copied destination part. The destination's transform, opacity,
;; and identity remain authoritative; only its renderer artifact is carried
;; from the source to make the handoff raster-continuous.
(define (make-endpoint-templates-by-destination current-source
                                                 correspondence
                                                 copies-by-destination)
  (define destination
    (formula-correspondence-destination correspondence))
  (define (add-if-equivalent result source-name destination-name)
    (define source-formula
      (formula-part-formula
       (formula-assembly-visual-ref current-source source-name)))
    (define destination-formula
      (formula-part-formula
       (formula-assembly-visual-ref destination destination-name)))
    (if (formula-transition-equivalent? source-formula destination-formula)
        (hash-set result destination-name source-formula)
        result))
  (define matched-templates
    (for/fold ([result (hash)])
              ([match (in-list (formula-correspondence-matches correspondence))])
      (add-if-equivalent result
                         (formula-part-match-source-name match)
                         (formula-part-match-destination-name match))))
  (for/fold ([result matched-templates])
            ([(destination-name copy) (in-hash copies-by-destination)])
    (add-if-equivalent result
                       (formula-part-copy-source-name copy)
                       destination-name)))

;; settle-destination-parts : (listof formula-part?) hash?
;;                            -> (listof formula-part?)
;; Reuses a source renderer artifact while installing the destination's exact
;; transform, opacity, and local part identity.
(define (settle-destination-parts destination-parts templates-by-destination)
  (for/list ([part (in-list destination-parts)])
    (define destination-name (formula-part-name part))
    (define destination-formula (formula-part-formula part))
    (define source-template
      (hash-ref templates-by-destination destination-name #f))
    (if source-template
        (formula-part
         destination-name
         (visual-with-opacity
          (visual-with-transform
           (formula-visual-with-id source-template
                                   (visual-id destination-formula))
           (visual-transform destination-formula))
          (visual-opacity destination-formula)))
        part)))

; make-unmatched-destination-specs : formula-correspondence? (listof symbol?)
;                                    -> (listof formula-transition-spec?)
;;   Creates stationary fade-in layers in destination order.
(define (make-unmatched-destination-specs correspondence destination-names)
  (define destination
    (formula-correspondence-destination correspondence))
  (for/list ([name
              (in-list destination-names)])
    (define formula
      (formula-part-formula
       (formula-assembly-visual-ref destination name)))
    (formula-transition-spec
     formula
     (visual-transform formula)
     (visual-transform formula)
     straight-formula-route
     0
     (visual-opacity formula)
     0
     1)))

; make-fade-transform-mismatch-specs : formula-assembly-visual?
;                                      formula-correspondence?
;                                      (listof symbol?) (listof symbol?) formula-arc?
;                                      -> (values (listof formula-transition-spec?)
;                                                 (listof symbol?)
;                                                 (listof symbol?))
;; Pairs uncorresponded pieces in source/destination order. If one side has
;; more parts than the other, its remaining parts retain the ordinary fade
;; behaviour. This mirrors Manim's useful `fade_transform_mismatches` policy
;; while making the pairing deterministic and visible in Animate's API.
(define (make-fade-transform-mismatch-specs current-source
                                            correspondence
                                            source-names
                                            destination-names
                                            route)
  (let loop ([remaining-source source-names]
             [remaining-destination destination-names]
             [reversed-specs '()])
    (cond
      [(and (pair? remaining-source)
            (pair? remaining-destination))
       (define source-formula
         (formula-part-formula
          (formula-assembly-visual-ref current-source
                                       (car remaining-source))))
       (define destination-formula
         (formula-part-formula
          (formula-assembly-visual-ref
           (formula-correspondence-destination correspondence)
           (car remaining-destination))))
       (loop
        (cdr remaining-source)
        (cdr remaining-destination)
        (append (reverse (make-one-match-specs source-formula
                                               destination-formula
                                               route))
                reversed-specs))]
      [else
       (values (reverse reversed-specs)
               remaining-source
               remaining-destination)])))

; formula-rendering-equivalent? : formula-visual? formula-visual? -> boolean?
;;   Reports whether two formulas differ only in identity, transform, or opacity.
(define (formula-rendering-equivalent? source destination)
  (equal? (formula-visual-rendering-key source)
          (formula-visual-rendering-key destination)))

; formula-transition-equivalent? : formula-visual? formula-visual? -> boolean?
;; Identifies formulas that can use one opaque moving layer during an interior
;; transition.  A source-addressed formula keeps the original TeX source for
;; its map but may attach an adjacent invisible gap to either physical
;; fragment.  For example, the same `7` can arrive as `"7"` or `"7 "`.
;;
;; This broader predicate applies to endpoint artifact retention as well as
;; the interior layer. The semantic destination identity and source map remain
;; authoritative; only an equivalent renderer artifact is retained.
(define (formula-transition-equivalent? source destination)
  (or (formula-rendering-equivalent? source destination)
      (equal?
       (formula-rendering-key-with-boundary-source source)
       (formula-rendering-key-with-boundary-source destination))))

(define (formula-rendering-key-with-boundary-source visual)
  (define source (formula-visual-source visual))
  (replace-rendering-key-source
   (formula-visual-rendering-key visual)
   source
   (formula-source-boundary-rendering-key source)))

;; The generic rendering key is deliberately opaque: styled formula leaves
;; nest the base key and add paint, while specialised leaves may contribute
;; renderer artifacts.  Replacing just the exact source datum retains every
;; other key component, including style, font options, and glyph outlines.
(define (replace-rendering-key-source key source replacement)
  (cond
    [(equal? key source) replacement]
    [(pair? key)
     (cons (replace-rendering-key-source (car key) source replacement)
           (replace-rendering-key-source (cdr key) source replacement))]
    [else key]))

; name-transition-specs : symbol?
;                         formula-assembly-visual?
;                         formula-assembly-visual?
;                         (listof formula-transition-spec?)
;                         -> (listof formula-transition-layer?)
;;   Assigns deterministic temporary names without colliding with model names.
(define (name-transition-specs target-id source destination specs)
  (define initial-used
    (for/fold ([used (hash target-id #t)])
              ([name
                (in-list
                 (append
                  (formula-assembly-visual-part-names source)
                  (formula-assembly-visual-part-names destination)))])
      (hash-set used name #t)))
  (define-values (reversed-layers _used)
    (for/fold ([layers '()]
               [used initial-used])
              ([spec (in-list specs)]
               [index (in-naturals)])
      (define name
        (fresh-transition-name used index))
      (values
       (cons
        (formula-transition-layer
         name
         (formula-transition-spec-template spec)
         (formula-transition-spec-from-transform spec)
         (formula-transition-spec-to-transform spec)
         (formula-transition-spec-route spec)
         (formula-transition-spec-from-opacity spec)
         (formula-transition-spec-to-opacity spec)
         (formula-transition-spec-appearance-start spec)
         (formula-transition-spec-appearance-end spec))
        layers)
       (hash-set used name #t))))
  (reverse reversed-layers))

; fresh-transition-name : immutable-hash? exact-nonnegative-integer? -> symbol?
;;   Returns the first deterministic reserved name absent from used.
(define (fresh-transition-name used index)
  (let loop ([suffix 0])
    (define candidate
      (string->symbol
       (string-append
        "__formula-transition-"
        (number->string index)
        (if (zero? suffix)
            ""
            (string-append "-" (number->string suffix))))))
    (if (hash-has-key? used candidate)
        (loop (add1 suffix))
        candidate)))


;;;
;;; Plan Sampling
;;;

;; formula-transition-plan-source-map-at : formula-transition-plan?
;;                                           finite-real? -> any/c
;; Source maps describe exact endpoint leaf trees. Interior transition layers
;; deliberately have no map, preventing stale source paths from targeting
;; temporary transition identities.
(define (formula-transition-plan-source-map-at plan progress)
  (unless (formula-transition-plan? plan)
    (raise-argument-error
     'formula-transition-plan-source-map-at
     "formula-transition-plan?"
     plan))
  (unless (and (finite-real? progress)
               (<= 0 progress 1))
    (raise-argument-error
     'formula-transition-plan-source-map-at
     "finite real in [0, 1]"
     progress))
  (cond [(zero? progress) (formula-transition-plan-source-map plan)]
        [(= progress 1) (formula-transition-plan-destination-source-map plan)]
        [else #f]))

; formula-transition-plan-sample-parts : formula-transition-plan?
;                                        finite-real?
;                                        -> (listof formula-part?)
;;   Returns exact endpoint parts or deterministic interior transition layers.
(define (formula-transition-plan-sample-parts plan progress)
  (unless (formula-transition-plan? plan)
    (raise-argument-error
     'formula-transition-plan-sample-parts
     "formula-transition-plan?"
     plan))
  (unless (and (finite-real? progress)
               (<= 0 progress 1))
    (raise-argument-error
     'formula-transition-plan-sample-parts
     "finite real in [0, 1]"
     progress))
  (cond
    [(zero? progress)
     (formula-transition-plan-source-parts plan)]
    [(= progress 1)
     (formula-transition-plan-destination-parts plan)]
    [else
     (for/list ([layer
                 (in-list
                  (formula-transition-plan-layers plan))])
       (sample-formula-transition-layer layer progress))]))

; sample-formula-transition-layer : formula-transition-layer? finite-real?
;                                   -> formula-part?
;;   Samples one temporary formula layer at interior progress.
(define (sample-formula-transition-layer layer progress)
  (define name
    (formula-transition-layer-name layer))
  ;; Motion always uses the clip's original progress. Only the changing
  ;; renderer and its opacity use the short, per-part appearance interval.
  (define appearance-progress
    (formula-transition-appearance-progress-at layer progress))
  (define formula-with-id
   (formula-visual-with-id
     (formula-visual-at-transition-progress
      (formula-transition-layer-template layer)
      appearance-progress)
     name))
  (define formula-with-transform
    (visual-with-transform
     formula-with-id
     (formula-transition-transform-at layer progress)))
  (define sampled-formula
    (visual-with-opacity
     formula-with-transform
     (real-lerp
      (formula-transition-layer-from-opacity layer)
      (formula-transition-layer-to-opacity layer)
      appearance-progress)))
  (formula-part name sampled-formula))

(define (formula-transition-appearance-progress-at layer progress)
  (define start (formula-transition-layer-appearance-start layer))
  (define end (formula-transition-layer-appearance-end layer))
  (cond
    [(<= progress start) 0]
    [(>= progress end) 1]
    [else (/ (- progress start) (- end start))]))

(define (formula-transition-transform-at layer progress)
  (define from-transform (formula-transition-layer-from-transform layer))
  (define to-transform (formula-transition-layer-to-transform layer))
  (affine-transform-with-translation
   (affine-transform-lerp from-transform to-transform progress)
   (formula-route-position-at
    (formula-transition-layer-route layer)
    (affine-transform-translation from-transform)
    (affine-transform-translation to-transform)
    progress)))

(define (formula-route-position-at route start end progress)
  (cond
    [(formula-arc? route)
     (formula-arc-position-at route start end progress)]
    [(formula-relative-path? route)
     (formula-relative-path-position-at route start end progress)]
    [else
     (raise-argument-error 'formula-route-position-at "formula-route?" route)]))

(define (formula-arc-position-at route start end progress)
  (define angle (formula-arc-angle route))
  (define chord (vec2- end start))
  (cond
    [(or (zero? angle)
         (and (zero? (vec2-x chord))
              (zero? (vec2-y chord))))
     (vec2-lerp start end progress)]
    [else
     (define half-chord (vec2-scale 1/2 chord))
     (define center
       (vec2+
        (vec2+ start half-chord)
        (vec2-scale (/ 1 (tan (/ angle 2)))
                    (left-normal half-chord))))
     (vec2+
      center
      (rotate-vector (vec2- start center) (* progress angle)))]))

(define (formula-relative-path-position-at route start end progress)
  (define chord (vec2- end start))
  (cond
    [(and (zero? (vec2-x chord))
          (zero? (vec2-y chord)))
     start]
    [else
     (define point
       (path-geometry-point-at
        (formula-relative-path-geometry route)
        progress))
     (vec2+
      start
      (vec2+
       (vec2-scale (vec2-x point) chord)
       (vec2-scale (vec2-y point) (left-normal chord))))]))

(define (left-normal vector)
  (vec2 (- (vec2-y vector)) (vec2-x vector)))

(define (vec2-coordinate=? left right)
  (and (= (vec2-x left) (vec2-x right))
       (= (vec2-y left) (vec2-y right))))

(define (rotate-vector vector angle)
  (define cosine (cos angle))
  (define sine (sin angle))
  (vec2 (- (* cosine (vec2-x vector))
           (* sine (vec2-y vector)))
        (+ (* sine (vec2-x vector))
           (* cosine (vec2-y vector)))))

(define (make-part-paths-by-match correspondence part-paths)
  (unless (and (list? part-paths)
               (andmap formula-part-path? part-paths))
    (raise-argument-error
     'make-formula-transition-plan
     "(listof formula-part-path?)"
     part-paths))
  (define valid-matches
    (for/hash ([match (in-list (formula-correspondence-matches correspondence))])
      (values
       (match-key (formula-part-match-source-name match)
                  (formula-part-match-destination-name match))
       #t)))
  (for/fold ([result (hash)]) ([part-path (in-list part-paths)])
    (define key
      (match-key (formula-part-path-source-name part-path)
                 (formula-part-path-destination-name part-path)))
    (unless (hash-has-key? valid-matches key)
      (raise-arguments-error
       'make-formula-transition-plan
       "a part path for a matched source/destination pair"
       "source-name" (formula-part-path-source-name part-path)
       "destination-name" (formula-part-path-destination-name part-path)))
    (when (hash-has-key? result key)
      (raise-arguments-error
       'make-formula-transition-plan
       "at most one route for each matched source/destination pair"
       "source-name" (formula-part-path-source-name part-path)
       "destination-name" (formula-part-path-destination-name part-path)))
    (hash-set result key (formula-part-path-route part-path))))

;; Compiles source-addressed appearance deadlines only after anchoring has
;; installed the destination's current-world transforms. The route itself is
;; unchanged; the result merely maps global progress to a shorter opacity and
;; renderer-progress interval for the selected changed fragment.
(define (make-appearance-windows-by-match current-source correspondence
                                          default-route part-paths-by-match
                                          triggers)
  (unless (and (list? triggers)
               (andmap formula-part-appearance-trigger? triggers))
    (raise-argument-error
     'make-formula-transition-plan
     "(listof formula-part-appearance-trigger?)"
     triggers))
  (define destination (formula-correspondence-destination correspondence))
  (define valid-matches
    (for/hash ([match (in-list (formula-correspondence-matches correspondence))])
      (values
       (match-key (formula-part-match-source-name match)
                  (formula-part-match-destination-name match))
       #t)))
  (define source-names (formula-assembly-visual-part-names current-source))
  (for/fold ([result (hash)]) ([trigger (in-list triggers)])
    (define source-name (formula-part-appearance-trigger-source-name trigger))
    (define destination-name
      (formula-part-appearance-trigger-destination-name trigger))
    (define key (match-key source-name destination-name))
    (unless (hash-has-key? valid-matches key)
      (raise-arguments-error
       'make-formula-transition-plan
       "an appearance trigger for a matched source/destination pair"
       "source-name" source-name
       "destination-name" destination-name))
    (when (hash-has-key? result key)
      (raise-arguments-error
       'make-formula-transition-plan
       "at most one appearance trigger for each matched pair"
       "source-name" source-name
       "destination-name" destination-name))
    (define reference-name
      (formula-part-appearance-trigger-reference-source-name trigger))
    (unless (member reference-name source-names)
      (raise-arguments-error
       'make-formula-transition-plan
       "an appearance reference part present in the current source formula"
       "reference-source-name" reference-name))
    (define source-formula
      (formula-part-formula
       (formula-assembly-visual-ref current-source source-name)))
    (define destination-formula
      (formula-part-formula
       (formula-assembly-visual-ref destination destination-name)))
    (define reference-formula
      (formula-part-formula
       (formula-assembly-visual-ref current-source reference-name)))
    (define route (hash-ref part-paths-by-match key default-route))
    (define complete-progress
      (formula-route-first-x-progress
       route
       (visual-position source-formula)
       (visual-position destination-formula)
       (vec2-x (visual-position reference-formula))
       source-name
       destination-name
       reference-name))
    (hash-set
     result
     key
     (cons (max 0 (- complete-progress
                     (formula-part-appearance-trigger-duration trigger)))
           complete-progress))))

;; Returns the first route progress whose x-coordinate equals `target-x`.
;; A bounded scan supplies a deterministic bracket for all supported route
;; types; bisection then makes the deadline accurate enough for raster output.
(define (formula-route-first-x-progress route start end target-x
                                        source-name destination-name reference-name)
  (define (x-offset progress)
    (- (vec2-x (formula-route-position-at route start end progress)) target-x))
  (define tolerance 1e-10)
  (define (zeroish? value) (<= (abs value) tolerance))
  (define initial (x-offset 0))
  (cond
    [(zeroish? initial) 0]
    [else
     (let loop ([index 1] [previous-progress 0] [previous-value initial])
       (cond
         [(> index 256)
          (raise-arguments-error
           'make-formula-transition-plan
           "a changed-part route that reaches its appearance reference x-coordinate"
           "source-name" source-name
           "destination-name" destination-name
           "reference-source-name" reference-name
           "target-x" target-x)]
         [else
          (define progress (/ index 256))
          (define value (x-offset progress))
          (cond
            [(zeroish? value) progress]
            [(<= (* previous-value value) 0)
             (let bisect ([low previous-progress]
                           [low-value previous-value]
                           [high progress]
                           [iterations 0])
               (if (= iterations 48)
                   (/ (+ low high) 2)
                   (let* ([middle (/ (+ low high) 2)]
                          [middle-value (x-offset middle)])
                     (cond
                       [(zeroish? middle-value) middle]
                       [(<= (* low-value middle-value) 0)
                        (bisect low low-value middle (add1 iterations))]
                       [else
                        (bisect middle middle-value high (add1 iterations))]))))]
            [else (loop (add1 index) progress value)])]))]))

; make-outline-morphs-by-match : formula-correspondence? any/c -> hash?
;; Validates the glyph adapter's optional interior replacements.  The generic
;; compiler never infers them: callers must explicitly opt in and every entry
;; must correspond to one declared or automatically matched pair.
(define (make-outline-morphs-by-match correspondence outline-morphs)
  (unless (and (list? outline-morphs)
               (andmap formula-part-outline-morph? outline-morphs))
    (raise-argument-error
     'make-formula-transition-plan
     "(listof formula-part-outline-morph?)"
     outline-morphs))
  (define valid-matches
    (for/hash ([match (in-list (formula-correspondence-matches correspondence))])
      (values
       (match-key (formula-part-match-source-name match)
                  (formula-part-match-destination-name match))
       #t)))
  (for/fold ([result (hash)]) ([outline-morph (in-list outline-morphs)])
    (define key
      (match-key (formula-part-outline-morph-source-name outline-morph)
                 (formula-part-outline-morph-destination-name outline-morph)))
    (unless (hash-has-key? valid-matches key)
      (raise-arguments-error
       'make-formula-transition-plan
       "an outline morph for a matched source/destination pair"
       "source-name" (formula-part-outline-morph-source-name outline-morph)
       "destination-name" (formula-part-outline-morph-destination-name outline-morph)))
    (when (hash-has-key? result key)
      (raise-arguments-error
       'make-formula-transition-plan
       "at most one outline morph for each matched source/destination pair"
       "source-name" (formula-part-outline-morph-source-name outline-morph)
       "destination-name" (formula-part-outline-morph-destination-name outline-morph)))
    (hash-set result key outline-morph)))

(define (make-copies-by-destination current-source correspondence copies)
  (unless (and (list? copies)
               (andmap formula-part-copy? copies))
    (raise-argument-error
     'make-formula-transition-plan
     "(listof formula-part-copy?)"
     copies))
  (define source-names
    (formula-assembly-visual-part-names current-source))
  (define unmatched-destination-names
    (formula-correspondence-unmatched-destination-names correspondence))
  (for/fold ([result (hash)]) ([copy (in-list copies)])
    (define source-name (formula-part-copy-source-name copy))
    (define destination-name (formula-part-copy-destination-name copy))
    (unless (member source-name source-names)
      (raise-arguments-error
       'make-formula-transition-plan
       "a copy source part present in the current source formula"
       "source-name" source-name))
    (unless (member destination-name unmatched-destination-names)
      (raise-arguments-error
       'make-formula-transition-plan
       "a copy destination part that is unmatched in the correspondence"
       "destination-name" destination-name))
    (when (hash-has-key? result destination-name)
      (raise-arguments-error
       'make-formula-transition-plan
       "at most one copy for each destination part"
       "destination-name" destination-name))
    (hash-set result destination-name copy)))

(define (match-key source-name destination-name)
  (cons source-name destination-name))
