#lang racket/base

;;;
;;; FX-D5 Target-Local Wave Tests
;;;

(require racket/list
         racket/math
         rackunit
         "../main.rkt")

(define (visual-points visual)
  (car (path-geometry-subpath-points (path-visual-path visual))))

(module+ test
  (define vertical
    (line (vec2 0 0) (vec2 0 1) #:id 'vertical #:stroke "navy"))

  ;; The wave is sampled from immutable source geometry. A phase chosen at the
  ;; peak makes the direct local displacement easy to observe at mid-clip;
  ;; both exact endpoints retain the authored source rather than an approximate
  ;; pointwise result.
  (define waved
    (scene-play
     (scene-add (make-scene) vertical)
     (apply-wave 'vertical #:direction (vec2 1 0)
                 #:amplitude 1/5 #:wavelength 1 #:cycles 1 #:phase (/ pi 2))
     #:duration 2))
  (check-true
   (apply-wave-request?
    (apply-wave 'vertical #:direction (vec2 1 0))))
  (check-equal? (scene-visual-at waved 'vertical 0) vertical)
  (define middle-points (visual-points (scene-visual-at waved 'vertical 1)))
  (check-= (vec2-x (first middle-points)) -1/5 1e-12)
  (check-= (vec2-y (first middle-points)) 0 1e-12)
  (check-= (vec2-x (last middle-points)) -1/5 1e-12)
  (check-= (vec2-y (last middle-points)) 1 1e-12)
  (check-equal? (scene-visual-at waved 'vertical 2) vertical)

  ;; Frame queries have no history dependence: the same local time samples the
  ;; same original geometry even after endpoint and earlier-time samples.
  (define mid (scene-visual-at waved 'vertical 1))
  (check-equal? (scene-visual-at waved 'vertical 2) vertical)
  (check-equal? (scene-visual-at waved 'vertical 1) mid)
  (check-equal? (scene-visual-at waved 'vertical 1/2)
                (scene-visual-at waved 'vertical 1/2))

  ;; A nested target is rebased through its enclosing transform while an
  ;; unrelated sibling remains exact. The completion boundary restores the
  ;; original nested target, not the temporary mapped wrapper.
  (define guide
    (line (vec2 0 -1) (vec2 1 -1) #:id 'guide #:stroke "gray"))
  (define nested
    (scene-play
     (scene-add (make-scene)
                (group (list vertical guide) #:id 'diagram #:center (vec2 2 0)))
     (apply-wave '(diagram vertical) #:direction (vec2 1 0)
                 #:amplitude 1/5 #:phase (/ pi 2))
     #:duration 1))
  (check-true (affine-map-visual? (scene-visual-at nested '(diagram vertical) 1/2)))
  (check-equal? (scene-visual-at nested '(diagram guide) 1) guide)
  (check-equal? (scene-visual-at nested '(diagram vertical) 1) vertical)

  ;; A wave owns the same replacement components as a homotopy, so it rejects
  ;; simultaneous target writers rather than depending on request order.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play (scene-add (make-scene) vertical)
                 (apply-wave 'vertical)
                 (move-to 'vertical (vec2 2 0)))))
  (check-exn exn:fail:contract?
             (lambda () (apply-wave 'vertical #:direction (vec2 0 0))))
  (check-exn exn:fail:contract?
             (lambda () (apply-wave 'vertical #:wavelength 0)))
  (check-exn exn:fail?
             (lambda () (scene-play (make-scene) (apply-wave 'missing)))))
