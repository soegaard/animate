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
         "formula-visual.rkt"
         "geometry.rkt"
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
         formula-part-copy
         formula-part-copy?
         formula-part-copy-source-name
         formula-part-copy-destination-name
         formula-part-copy-route
         formula-transition-plan?
         make-formula-transition-plan
         formula-transition-plan-source-parts
         formula-transition-plan-destination-parts
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

(define straight-formula-route (formula-arc #:angle 0))

(struct formula-transition-layer
  (name template from-transform to-transform route from-opacity to-opacity)
  #:transparent)

;; formula-transition-layer represents one independently rendered interior layer.
;;  - name            symbol?             deterministic temporary local identity.
;;  - template        formula-visual?     source of LaTeX and typesetting data.
;;  - from-transform  affine-transform?   local transform at progress zero.
;;  - to-transform    affine-transform?   local transform at progress one.
;;  - route           formula-route?      local translation trajectory.
;;  - from-opacity    opacity?            local opacity at progress zero.
;;  - to-opacity      opacity?            local opacity at progress one.

(struct formula-transition-plan
  (source-parts layers destination-parts)
  #:transparent)

;; formula-transition-plan represents one compiled formula-part transformation.
;;  - source-parts       (listof formula-part?)  exact current source order.
;;  - layers             (listof formula-transition-layer?)
;;                       deterministic interior drawing order.
;;  - destination-parts  (listof formula-part?)  exact destination order.
;;
;; The layer order is source-only parts, matched layers in correspondence order,
;; and destination-only parts. A changed matched part contributes a source layer
;; followed by a destination layer.

(struct formula-transition-spec
  (template from-transform to-transform route from-opacity to-opacity)
  #:transparent)

;; formula-transition-spec is one layer before a temporary name is allocated.
;;  - template        formula-visual?    source of LaTeX and typesetting data.
;;  - from-transform  affine-transform?  local transform at progress zero.
;;  - to-transform    affine-transform?  local transform at progress one.
;;  - route           formula-route?     local translation trajectory.
;;  - from-opacity    opacity?           local opacity at progress zero.
;;  - to-opacity      opacity?           local opacity at progress one.


;;;
;;; Plan Construction
;;;

; make-formula-transition-plan : formula-assembly-visual?
;                                formula-correspondence?
;                                [#:path-arc finite-real?]
;                                [#:part-paths (listof formula-part-path?)]
;                                [#:copies (listof formula-part-copy?)]
;                                [#:mismatch-mode formula-mismatch-mode?]
;                                -> formula-transition-plan?
;;   Compiles correspondence against the current source assembly.
(define (make-formula-transition-plan current-source correspondence
                                      #:path-arc [path-arc 0]
                                      #:part-paths [part-paths '()]
                                      #:copies [copies '()]
                                      #:mismatch-mode [mismatch-mode 'fade])
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
  (define copies-by-destination
    (make-copies-by-destination current-source correspondence copies))
  ;; A tagged TeX fragment has a crop from the complete formula in which it
  ;; was typeset.  Two fragments with equal TeX can consequently have distinct
  ;; SVG view boxes.  Retain the source artifact for an unchanged fragment at
  ;; its destination transform: interior and endpoint frames then use the
  ;; same glyph geometry instead of swapping crops on the final frame.
  (define settled-destination-parts
    (settle-destination-parts
     destination-parts
     (make-endpoint-templates-by-destination
      current-source correspondence copies-by-destination)))
  ;; Validate that the settled destination parts can occupy the current
  ;; assembly identity before any timeline is constructed.
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
                         part-paths-by-match)
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
   settled-destination-parts))

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
     0)))

; make-matched-specs : formula-assembly-visual?
;                      formula-correspondence? formula-arc? hash?
;                      -> (listof formula-transition-spec?)
;;   Creates moving matched layers in explicit correspondence order.
(define (make-matched-specs current-source correspondence default-route
                            part-paths-by-match)
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
     (make-one-match-specs source-formula destination-formula route))))

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
(define (make-one-match-specs source-formula destination-formula route)
  (define source-transform
    (visual-transform source-formula))
  (define destination-transform
    (visual-transform destination-formula))
  (cond
    [(formula-rendering-equivalent? source-formula destination-formula)
     (list
      (formula-transition-spec
       source-formula
       source-transform
       destination-transform
       route
       (visual-opacity source-formula)
       (visual-opacity destination-formula)))]
    [else
     (list
      (formula-transition-spec
       source-formula
       source-transform
       destination-transform
       route
       (visual-opacity source-formula)
       0)
     (formula-transition-spec
       destination-formula
       source-transform
       destination-transform
       route
       0
       (visual-opacity destination-formula)))]))

;; make-endpoint-templates-by-destination : formula-assembly-visual?
;;                                              formula-correspondence?
;;                                              hash? -> hash?
;; Selects the rendering template to retain for every semantically unchanged
;; matched or copied destination part.  The destination's transform, opacity,
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
    (if (formula-rendering-equivalent? source-formula destination-formula)
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
     (visual-opacity formula))))

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
  (and (equal? (formula-visual-source source)
               (formula-visual-source destination))
       (eq? (formula-visual-mode source)
            (formula-visual-mode destination))
       (= (formula-visual-font-size source)
          (formula-visual-font-size destination))
       (equal? (formula-visual-preamble source)
               (formula-visual-preamble destination))
       (equal? (formula-visual-document-class-options source)
               (formula-visual-document-class-options destination))
       (equal? (formula-visual-preview-options source)
               (formula-visual-preview-options destination))
       (eq? (formula-visual-horizontal-alignment source)
            (formula-visual-horizontal-alignment destination))
       (eq? (formula-visual-vertical-alignment source)
            (formula-visual-vertical-alignment destination))))

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
         (formula-transition-spec-to-opacity spec))
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
  (define formula-with-id
    (formula-visual-with-id
     (formula-transition-layer-template layer)
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
      progress)))
  (formula-part name sampled-formula))

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
