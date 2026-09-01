#lang racket/base

;;;
;;; SCENE-O Model Tests
;;;

;; Tests deterministic formula-part transitions, matched movement, cross-fades,
;; unmatched fades, exact endpoints, and concurrent assembly transforms.


;;;
;;; Imports
;;;

(require rackunit
         "../main.rkt")


(module+ test
  ; make-part : symbol? string? real? -> formula-part?
  ;;   Creates one baseline-aligned formula part at local x.
  (define (make-part name source x)
    (latex-formula-part source
                        #:name name
                        #:center (vec2 x 0)
                        #:mode 'inline
                        #:font-size 1/3
                        #:vertical-alignment 'baseline))

  ; source-parts : (listof formula-part?)
  ;;   Gives the source equation in significant order.
  (define source-parts
    (list (make-part 'a "a^2" -2)
          (make-part 'plus "+" -1)
          (make-part 'b "b^2" 0)
          (make-part 'equals "=" 1)
          (make-part 'c "c^2" 2)))

  ; destination-parts : (listof formula-part?)
  ;;   Gives the destination equation in significant order.
  (define destination-parts
    (list (make-part 'c "c^2" -2)
          (make-part 'minus "-" -1)
          (make-part 'a "a^2" 0)
          (make-part 'equals "=" 1)
          (make-part 'b "b^2" 2)))

  ; source-assembly : formula-assembly-visual?
  ;;   Gives the present source assembly and its outer semantic state.
  (define source-assembly
    (formula-assembly source-parts
                      #:id 'equation
                      #:center (vec2 -2 1)
                      #:rotation 1/10
                      #:scale 4/5
                      #:opacity 3/4))

  ; destination-template : formula-assembly-visual?
  ;;   Gives destination parts with deliberately different outer state and id.
  (define destination-template
    (formula-assembly destination-parts
                      #:id 'destination-template
                      #:center (vec2 20 20)
                      #:rotation 3
                      #:scale 3
                      #:opacity 1/5))

  ; correspondence : formula-correspondence?
  ;;   Matches preserved terms and deliberately cross-fades plus into minus.
  (define correspondence
    (formula-correspondence
     source-assembly
     destination-template
     (list (formula-part-match 'a 'a)
           (formula-part-match 'plus 'minus)
           (formula-part-match 'b 'b)
           (formula-part-match 'equals 'equals))))

  ; request : transform-formula-parts-request?
  ;;   Gives one public matched-part transformation request.
  (define request
    (transform-formula-parts correspondence))

  (check-true (transform-formula-parts-request? request))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (transform-formula-parts 'not-a-correspondence)))

  ; transformed : scene?
  ;;   Gives a two-second formula-part transformation.
  (define transformed
    (scene-play (scene-add (make-scene) source-assembly)
                request
                #:duration 2))

  ; start-assembly : formula-assembly-visual?
  ;;   Gives the exact semantic source at progress zero.
  (define start-assembly
    (scene-state-ref (scene-sample transformed 0) 'equation))

  (check-equal? (formula-assembly-visual-parts start-assembly)
                source-parts)
  (check-equal? (formula-assembly-visual-part-names start-assembly)
                '(a plus b equals c))

  ; midpoint-assembly : formula-assembly-visual?
  ;;   Gives deterministic transition layers at eased progress one half.
  (define midpoint-assembly
    (scene-state-ref (scene-sample transformed 1) 'equation))

  ; midpoint-parts : (listof formula-part?)
  ;;   Gives source-only, matched, and destination-only interior layers.
  (define midpoint-parts
    (formula-assembly-visual-parts midpoint-assembly))

  (check-equal?
   (formula-assembly-visual-part-names midpoint-assembly)
   '(__formula-transition-0
     __formula-transition-1
     __formula-transition-2
     __formula-transition-3
     __formula-transition-4
     __formula-transition-5
     __formula-transition-6))
  (check-equal?
   (map (lambda (part)
          (formula-visual-source (formula-part-formula part)))
        midpoint-parts)
   '("c^2" "a^2" "+" "-" "b^2" "=" "c^2"))
  (check-equal?
   (map (lambda (part)
          (visual-opacity (formula-part-formula part)))
        midpoint-parts)
   '(1/2 1 1/2 1/2 1 1 1/2))
  (check-equal?
   (map (lambda (part)
          (visual-position (formula-part-formula part)))
        midpoint-parts)
   (list (vec2 2 0)
         (vec2 -1 0)
         (vec2 -1 0)
         (vec2 -1 0)
         (vec2 1 0)
         (vec2 1 0)
         (vec2 -2 0)))

  ;; A transition changes only assembly parts. Destination outer state and its
  ;; top-level identity do not replace the current scene participant.
  ; endpoint-assembly : formula-assembly-visual?
  ;;   Gives the exact structural endpoint after the play clip.
  (define endpoint-assembly
    (scene-state-ref (scene-current-state transformed) 'equation))

  (check-eq? (visual-id endpoint-assembly) 'equation)
  (check-equal? (formula-assembly-visual-parts endpoint-assembly)
                destination-parts)
  (check-equal? (formula-assembly-visual-part-names endpoint-assembly)
                '(c minus a equals b))
  (check-equal? (visual-transform endpoint-assembly)
                (visual-transform source-assembly))
  (check-equal? (visual-opacity endpoint-assembly)
                (visual-opacity source-assembly))
  (check-false
   (scene-state-has? (scene-current-state transformed)
                     'destination-template))

  ;; Translation, rotation, scale, and opacity are independent components. The
  ;; result is independent of request order.
  ; neutral-source : formula-assembly-visual?
  ;;   Gives a source with identity transform and full opacity.
  (define neutral-source
    (formula-assembly source-parts #:id 'moving-equation))

  ; neutral-destination : formula-assembly-visual?
  ;;   Gives a destination template for moving-equation.
  (define neutral-destination
    (formula-assembly destination-parts #:id 'moving-template))

  ; neutral-correspondence : formula-correspondence?
  ;;   Gives the same semantic mapping for the neutral source.
  (define neutral-correspondence
    (formula-correspondence
     neutral-source
     neutral-destination
     (formula-correspondence-matches correspondence)))

  ; concurrent-a : scene?
  ;;   Gives one request order for five disjoint animation components.
  (define concurrent-a
    (scene-play
     (scene-add (make-scene) neutral-source)
     (transform-formula-parts neutral-correspondence)
     (move-to neutral-source (vec2 4 2))
     (rotate-to neutral-source 1)
     (scale-to neutral-source 2)
     (fade-to neutral-source 1/2)
     #:duration 2))

  ; concurrent-b : scene?
  ;;   Gives the reverse request order for the same component endpoints.
  (define concurrent-b
    (scene-play
     (scene-add (make-scene) neutral-source)
     (fade-to neutral-source 1/2)
     (scale-to neutral-source 2)
     (rotate-to neutral-source 1)
     (move-to neutral-source (vec2 4 2))
     (transform-formula-parts neutral-correspondence)
     #:duration 2))

  (check-equal? (scene-sample concurrent-a 1)
                (scene-sample concurrent-b 1))
  (check-equal? (scene-current-state concurrent-a)
                (scene-current-state concurrent-b))

  ; concurrent-midpoint : formula-assembly-visual?
  ;;   Gives the concurrently transformed assembly at one second.
  (define concurrent-midpoint
    (scene-state-ref (scene-sample concurrent-a 1)
                     'moving-equation))

  (check-equal? (visual-position concurrent-midpoint) (vec2 2 1))
  (check-equal? (visual-rotation concurrent-midpoint) 1/2)
  (check-equal? (visual-scale concurrent-midpoint) (vec2 3/2 3/2))
  (check-equal? (visual-opacity concurrent-midpoint) 3/4)

  ; concurrent-endpoint : formula-assembly-visual?
  ;;   Gives the exact destination parts with independent outer endpoints.
  (define concurrent-endpoint
    (scene-state-ref (scene-current-state concurrent-a)
                     'moving-equation))

  (check-equal? (formula-assembly-visual-parts concurrent-endpoint)
                destination-parts)
  (check-equal? (visual-position concurrent-endpoint) (vec2 4 2))
  (check-equal? (visual-rotation concurrent-endpoint) 1)
  (check-equal? (visual-scale concurrent-endpoint) (vec2 2 2))
  (check-equal? (visual-opacity concurrent-endpoint) 1/2)

  ;; Presence-changing requests conflict with formula-part transformation, and
  ;; two formula-part requests conflict on the same assembly.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play (scene-add (make-scene) neutral-source)
                 (transform-formula-parts neutral-correspondence)
                 (fade-out neutral-source)
                 #:duration 1)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play (scene-add (make-scene) neutral-source)
                 (transform-formula-parts neutral-correspondence)
                 (transform-formula-parts neutral-correspondence)
                 #:duration 1)))

  ;; The source identity must be present and must identify a formula assembly.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play (make-scene)
                 (transform-formula-parts neutral-correspondence)
                 #:duration 1)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene)
                 (circle #:id 'moving-equation #:radius 1))
      (transform-formula-parts neutral-correspondence)
      #:duration 1)))

  ;; The current source namespace must match the correspondence source exactly.
  ; reordered-source : formula-assembly-visual?
  ;;   Gives the right identity with a different current part order.
  (define reordered-source
    (formula-assembly (reverse source-parts)
                      #:id 'moving-equation))

  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene) reordered-source)
      (transform-formula-parts neutral-correspondence)
      #:duration 1)))

  ;; Destination parts must also be valid under the stable current assembly id.
  ; colliding-destination : formula-assembly-visual?
  ;;   Gives a template whose child name collides only with the current target id.
  (define colliding-destination
    (formula-assembly
     (list (make-part 'moving-equation "q" 0))
     #:id 'noncolliding-template))

  ; colliding-correspondence : formula-correspondence?
  ;;   Gives a valid correspondence value that cannot become the target endpoint.
  (define colliding-correspondence
    (formula-correspondence
     neutral-source
     colliding-destination
     '()))

  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene) neutral-source)
      (transform-formula-parts colliding-correspondence)
      #:duration 1)))

  ;; Structural completion installs exact destination parts even when easing
  ;; never advances interior progress.
  ; frozen-easing-scene : scene?
  ;;   Gives a transformation whose easing always returns zero.
  (define frozen-easing-scene
    (scene-play
     (scene-add (make-scene) neutral-source)
     (transform-formula-parts neutral-correspondence)
     #:duration 1
     #:easing (lambda (_progress) 0)))

  (check-equal?
   (formula-assembly-visual-part-names
    (scene-state-ref (scene-sample frozen-easing-scene 1/2)
                     'moving-equation))
   '(a plus b equals c))
  (check-equal?
   (formula-assembly-visual-part-names
    (scene-state-ref (scene-current-state frozen-easing-scene)
                     'moving-equation))
   '(c minus a equals b))

  ;; A later correspondence compiles against the exact result of the earlier
  ;; clip while preserving the same top-level Visual identity.
  ; reverse-source-template : formula-assembly-visual?
  ;;   Gives the current destination namespace under the stable target id.
  (define reverse-source-template
    (formula-assembly destination-parts #:id 'moving-equation))

  ; reverse-destination-template : formula-assembly-visual?
  ;;   Gives the original source parts as the second destination.
  (define reverse-destination-template
    (formula-assembly source-parts #:id 'reverse-template))

  ; reverse-correspondence : formula-correspondence?
  ;;   Gives the explicit inverse mapping, including minus into plus.
  (define reverse-correspondence
    (formula-correspondence
     reverse-source-template
     reverse-destination-template
     (list (formula-part-match 'a 'a)
           (formula-part-match 'minus 'plus)
           (formula-part-match 'b 'b)
           (formula-part-match 'equals 'equals))))

  ; round-trip : scene?
  ;;   Transforms to the destination and then back to the source part list.
  (define round-trip
    (scene-play concurrent-a
                (transform-formula-parts reverse-correspondence)
                #:duration 1))

  (check-equal?
   (formula-assembly-visual-part-names
    (scene-state-ref (scene-current-state round-trip)
                     'moving-equation))
   '(a plus b equals c))

  ;; Compilation uses the current formula values, not stale source-template
  ;; formula values, after confirming the exact ordered local namespace.
  ; value-template-source : formula-assembly-visual?
  ;;   Gives a correspondence source template whose formula says x.
  (define value-template-source
    (formula-assembly
     (list (make-part 'term "x" -2))
     #:id 'current-value-equation))

  ; value-current-source : formula-assembly-visual?
  ;;   Gives the current scene value with the same namespace but formula y.
  (define value-current-source
    (formula-assembly
     (list (make-part 'term "y" -4))
     #:id 'current-value-equation))

  ; value-template-destination : formula-assembly-visual?
  ;;   Gives the destination formula x at a new local position.
  (define value-template-destination
    (formula-assembly
     (list (make-part 'term "x" 2))
     #:id 'current-value-template))

  ; value-correspondence : formula-correspondence?
  ;;   Matches the one shared name between the endpoint templates.
  (define value-correspondence
    (formula-correspondence
     value-template-source
     value-template-destination
     (list (formula-part-match 'term 'term))))

  ; value-midpoint : formula-assembly-visual?
  ;;   Gives two cross-fading layers because current y differs from destination x.
  (define value-midpoint
    (scene-state-ref
     (scene-sample
      (scene-play
       (scene-add (make-scene) value-current-source)
       (transform-formula-parts value-correspondence)
       #:duration 2)
      1)
     'current-value-equation))

  (check-equal?
   (map (lambda (part)
          (formula-visual-source (formula-part-formula part)))
        (formula-assembly-visual-parts value-midpoint))
   '("y" "x"))
  (check-equal?
   (map (lambda (part)
          (visual-position (formula-part-formula part)))
        (formula-assembly-visual-parts value-midpoint))
   (list (vec2 -1 0) (vec2 -1 0)))

  ;; Temporary names avoid collisions with endpoint part namespaces.
  ; collision-source : formula-assembly-visual?
  ;;   Gives a source that deliberately uses the first reserved-looking name.
  (define collision-source
    (formula-assembly
     (list (make-part '__formula-transition-0 "z" -1))
     #:id 'collision-equation))

  ; collision-destination : formula-assembly-visual?
  ;;   Gives a compatible destination for the reserved-looking name.
  (define collision-destination
    (formula-assembly
     (list (make-part '__formula-transition-0 "z" 1))
     #:id 'collision-template))

  ; collision-midpoint : formula-assembly-visual?
  ;;   Gives an interior layer whose generated name does not collide.
  (define collision-midpoint
    (scene-state-ref
     (scene-sample
      (scene-play
       (scene-add (make-scene) collision-source)
       (transform-formula-parts
        (formula-correspondence
         collision-source
         collision-destination
         (list
          (formula-part-match '__formula-transition-0
                              '__formula-transition-0))))
       #:duration 2)
      1)
     'collision-equation))

  (check-equal?
   (formula-assembly-visual-part-names collision-midpoint)
   '(__formula-transition-0-1))

  ;; Empty assemblies and an empty explicit match list remain valid.
  ; empty-source : formula-assembly-visual?
  ;;   Gives an empty present formula assembly.
  (define empty-source
    (formula-assembly '() #:id 'empty-equation))

  ; empty-destination : formula-assembly-visual?
  ;;   Gives an empty destination template with another identity.
  (define empty-destination
    (formula-assembly '() #:id 'empty-template))

  ; empty-transformation : scene?
  ;;   Gives a valid transformation with no interior layers.
  (define empty-transformation
    (scene-play
     (scene-add (make-scene) empty-source)
     (transform-formula-parts
      (formula-correspondence empty-source empty-destination '()))
     #:duration 1))

  (check-equal?
   (formula-assembly-visual-parts
    (scene-state-ref (scene-sample empty-transformation 1/2)
                     'empty-equation))
   '())
  (check-equal?
   (formula-assembly-visual-parts
    (scene-state-ref (scene-current-state empty-transformation)
                     'empty-equation))
   '()))
