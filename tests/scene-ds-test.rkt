#lang racket/base

;;;
;;; SCENE-DS Mathematical Effect Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  (define marker
    (circle #:id 'marker #:center origin #:radius 1/2
            #:fill "aliceblue" #:stroke "navy"))
  (define trail
    (line (vec2 -2 -1) (vec2 2 -1) #:id 'trail
          #:stroke "steelblue" #:stroke-width 2))
  (define initial (scene-add (make-scene) marker trail))

  (check-true (flash-request? (flash 'marker)))
  (check-true (focus-on-request? (focus-on 'marker)))
  (check-true (show-passing-flash-request?
               (show-passing-flash 'trail)))
  (check-true (grow-from-center-request?
               (grow-from-center marker)))
  (check-true (grow-arrow-request?
               (grow-arrow (arrow (vec2 -1 0) (vec2 1 0) #:id 'arrow))))
  (check-true (draw-border-then-fill-request?
               (draw-border-then-fill
                (make-path-visual (polygon-path (list (vec2 -1/2 -1/2)
                                                    (vec2 1/2 -1/2)
                                                    (vec2 1/2 1/2)
                                                    (vec2 -1/2 1/2)))
                                  #:id 'panel #:fill "gold"))))

  ;; Decorative effects add only one transient frontmost overlay at interior
  ;; samples and leave the exact scene state untouched at either endpoint.
  (for ([effect (in-list (list (flash 'marker)
                               (focus-on 'marker)
                               (show-passing-flash 'trail)))])
    (define animated (scene-play initial effect #:duration 1))
    (check-equal? (scene-state-count (scene-sample animated 0)) 2)
    (check-equal? (scene-state-count (scene-sample animated 1/2)) 3)
    (check-equal? (scene-state-count (scene-sample animated 1)) 2)
    (check-not-false (scene-frame->bitmap animated 1 #:fps 2)))

  ;; A nested ordinary path has the same list representation as a rooted 3D
  ;; spatial path.  It must still compile as the 2D passing-flash effect.
  (define nested-trail
    (group (list (line (vec2 -1 0) (vec2 1 0) #:id 'median
                       #:stroke "darkred" #:stroke-width 2))
           #:id 'spread))
  (check-not-exn
   (lambda ()
     (scene-play (scene-add (make-scene) nested-trail)
                 (show-passing-flash '(spread median))
                 #:duration 1)))

  ;; Wiggle is a normal sequential rotation composition and returns exactly to
  ;; the same orientation.
  (define wiggled (scene-play initial (wiggle 'marker #:angle 1/10 #:cycles 2)
                              #:duration 1))
  (check-equal? (visual-rotation (scene-visual-at wiggled 'marker 1)) 0)

  ;; Structural growth starts invisible and tiny, then restores the supplied
  ;; endpoint Visual exactly.
  (define grown-visual
    (circle #:id 'grown #:center (vec2 -1 1) #:radius 1/2 #:fill "coral"))
  (define grown
    (scene-play (make-scene) (grow-from-center grown-visual) #:duration 1))
  (check-equal? (visual-opacity (scene-visual-at grown 'grown 0)) 0)
  (check-equal? (scene-visual-at grown 'grown 1) grown-visual)

  (define grown-arrow
    (arrow (vec2 -2 1) (vec2 2 1) #:id 'grown-arrow #:stroke "darkgreen"))
  (define arrow-scene
    (scene-play (make-scene) (grow-arrow grown-arrow) #:duration 1))
  (check-equal? (visual-opacity (scene-visual-at arrow-scene 'grown-arrow 0)) 0)
  (check-equal? (scene-visual-at arrow-scene 'grown-arrow 1) grown-arrow)

  ;; DrawBorderThenFill uses arc-length tracing during its first half and
  ;; restores the caller's exact filled path at completion.
  (define filled
    (make-path-visual
     (polygon-path (list (vec2 -1 -1/2) (vec2 1 -1/2)
                         (vec2 1 1/2) (vec2 -1 1/2)))
     #:id 'filled #:fill "gold" #:stroke "sienna"))
  (define border-fill
    (scene-play (make-scene) (draw-border-then-fill filled) #:duration 1))
  (check-true (path-geometry-empty?
               (path-visual-path (scene-visual-at border-fill 'filled 0))))
  (check-equal? (scene-visual-at border-fill 'filled 1) filled))
