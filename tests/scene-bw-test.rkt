#lang racket/base

;; SCENE-BW: source-preserving copies, temporary attention, and general
;; formula-part routes.

(require rackunit
         "../main.rkt")

(define (part name source position)
  (formula-part
   name
   (latex-formula source #:id name #:center position)))

(define (assembly id parts)
  (formula-assembly parts #:id id))

(define (part-by-source formula source)
  (for/first ([part (in-list (formula-assembly-visual-parts formula))]
              #:when (string=? (formula-visual-source
                                (formula-part-formula part))
                               source))
    (formula-part-formula part)))

(module+ test
  ;; A general copy leaves the source scene Visual intact, adds only a
  ;; transient overlay in the interior, then installs its new endpoint.
  (define source-dot
    (circle #:id 'source-dot #:center (vec2 -2 0) #:radius 1))
  (define copied-dot
    (circle #:id 'copied-dot #:center (vec2 2 0) #:radius 1 #:fill "skyblue"))
  (define copied-scene
    (scene-play
     (scene-add (make-scene) source-dot)
     (transform-from-copy 'source-dot copied-dot #:path-arc 1)
     #:duration 2))
  (define copied-middle (scene-sample copied-scene 1))
  (check-true (scene-state-has? copied-middle 'source-dot))
  (check-false (scene-state-has? copied-middle 'copied-dot))
  (check-equal? (scene-state-count copied-middle) 2)
  (check-true (scene-state-has? (scene-current-state copied-scene) 'source-dot))
  (check-true (scene-state-has? (scene-current-state copied-scene) 'copied-dot))
  (check-equal? (scene-state-count (scene-current-state copied-scene)) 2)

  ;; Overlay wrappers isolate descendant identities, so general copies also
  ;; work when source and destination composite trees reuse local child names.
  (define source-group
    (group (list (circle #:id 'shared-child #:radius 1))
           #:id 'source-group #:center (vec2 -2 0)))
  (define destination-group
    (group (list (circle #:id 'shared-child #:radius 1 #:fill "skyblue"))
           #:id 'destination-group #:center (vec2 2 0)))
  (define composite-copy-scene
    (scene-play
     (scene-add (make-scene) source-group)
     (transform-from-copy 'source-group destination-group)
     #:duration 2))
  (check-equal? (scene-state-count (scene-sample composite-copy-scene 1)) 2)
  (check-true (scene-state-has? (scene-current-state composite-copy-scene)
                                'destination-group))

  ;; Attention has no structural endpoint and never mutates the target.
  (define attention-dot
    (circle #:id 'attention-dot #:radius 1 #:fill "plum"))
  (define circumscribed
    (scene-play
     (scene-add (make-scene) attention-dot)
     (circumscribe 'attention-dot)
     #:duration 1))
  (define indicated
    (scene-play
     (scene-add (make-scene) attention-dot)
     (indicate 'attention-dot)
     #:duration 1))
  (check-equal? (scene-state-count (scene-sample circumscribed 1/2)) 2)
  (check-equal? (scene-state-count (scene-sample indicated 1/2)) 2)
  (check-equal? (scene-current-state circumscribed)
                (scene-current-state
                 (scene-add (make-scene) attention-dot)))
  (check-equal? (scene-current-state indicated)
                (scene-current-state
                 (scene-add (make-scene) attention-dot)))

  ;; Two formula copies create two new x parts while the original source x is
  ;; still represented by its ordinary matched part.
  (define copy-source
    (assembly
     'equation
     (list (part 'x-left "x" (vec2 -1 0))
           (part 'equals "=" (vec2 0 0))
           (part 'two "2" (vec2 1 0)))))
  (define copy-destination
    (assembly
     'equation
     (list (part 'x-left "x" (vec2 -2 0))
           (part 'plus-left "+" (vec2 -1 0))
           (part 'x-added-left "x" (vec2 0 0))
           (part 'equals "=" (vec2 1 0))
           (part 'two "2" (vec2 2 0))
           (part 'plus-right "+" (vec2 3 0))
           (part 'x-added-right "x" (vec2 4 0)))))
  (define copy-correspondence
    (formula-correspondence
     copy-source
     copy-destination
     (list (formula-part-match 'x-left 'x-left)
           (formula-part-match 'equals 'equals)
           (formula-part-match 'two 'two))))
  (define formula-copy-scene
    (scene-play
     (scene-add (make-scene) copy-source)
     (transform-formula-parts
      copy-correspondence
      #:copies
      (list (formula-part-copy 'x-left 'x-added-left (formula-arc #:angle 1/2))
            (formula-part-copy 'x-left 'x-added-right (formula-arc #:angle -1/2)))
      #:mismatch-mode 'fade)
     #:duration 2))
  (define formula-copy-middle
    (scene-visual-at formula-copy-scene 'equation 1))
  (check-equal?
   (length
    (filter (lambda (part)
              (string=? (formula-visual-source (formula-part-formula part)) "x"))
            (formula-assembly-visual-parts formula-copy-middle)))
   3)
  (check-equal? (formula-assembly-visual-part-names
                 (scene-visual-at formula-copy-scene 'equation 2))
                '(x-left plus-left x-added-left equals two plus-right x-added-right))

  ;; A unit-chord path can lift a formula part above its straight chord.
  (define route-source
    (assembly 'route-formula (list (part 'old-x "x" (vec2 -1 0)))))
  (define route-destination
    (assembly 'route-formula (list (part 'new-x "x" (vec2 1 0)))))
  (define route
    (formula-relative-path
     (polyline-path (list (vec2 0 0) (vec2 1/2 1) (vec2 1 0)))))
  (define routed-scene
    (scene-play
     (scene-add (make-scene) route-source)
     (transform-formula-parts
      (formula-correspondence
       route-source route-destination
       (list (formula-part-match 'old-x 'new-x)))
      #:part-paths (list (formula-part-path 'old-x 'new-x route)))
     #:duration 2))
  (define routed-middle
    (part-by-source (scene-visual-at routed-scene 'route-formula 1) "x"))
  (check-= (vec2-y (visual-position routed-middle)) 2 1e-12))
