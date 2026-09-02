#lang racket/base

;;;
;;; SCENE-CU Deterministic Traced-Path Tests
;;;

(require rackunit
         "../main.rkt")

(define phase (parameter 'phase 0))

(define (parabola-position _context time)
  (vec2 time (* time time)))

(define (path-world-points path)
  (for*/list ([subpath-points
               (in-list (path-geometry-subpath-points
                         (path-visual-path path)))]
              [point (in-list subpath-points)])
    (affine-transform-apply-point (visual-transform path) point)))

(module+ test
  (define locus
    (traced-path phase parabola-position
                 #:id 'locus #:sample-count 5 #:stroke "crimson"))
  (define start
    (scene-add (scene-set-value (make-scene) phase) locus))
  (define animated
    (scene-play start (value-to phase 2) #:duration 2))

  ;; A trace at its starting phase is a valid invisible path, rather than a
  ;; degenerate line or a remembered previous frame.
  (define empty-locus (scene-visual-at animated 'locus 0))
  (check-true (path-visual? empty-locus))
  (check-true (path-geometry-empty? (path-visual-path empty-locus)))

  ;; The frame at time one reconstructs five exact samples over phase [0,1].
  ;; Sampling the same time twice gives equal data without rendering history.
  (define middle (scene-visual-at animated 'locus 1))
  (define middle-again (scene-visual-at animated 'locus 1))
  (check-equal? middle middle-again)
  (check-equal?
   (path-world-points middle)
   (list (vec2 0 0)
         (vec2 1/4 1/16)
         (vec2 1/2 1/4)
         (vec2 3/4 9/16)
         (vec2 1 1)))

  ;; A trailing window discards older deterministic samples instead of relying
  ;; on frame accumulation. It starts at current-phase minus trail length.
  (define windowed
    (traced-path phase parabola-position
                 #:id 'windowed #:sample-count 5 #:trail-length 1/2))
  (define windowed-scene
    (scene-play
     (scene-add (scene-set-value (make-scene) phase) windowed)
     (value-to phase 2) #:duration 2))
  (check-equal?
   (path-world-points (scene-visual-at windowed-scene 'windowed 2))
   (list (vec2 3/2 9/4)
         (vec2 13/8 169/64)
         (vec2 7/4 49/16)
         (vec2 15/8 225/64)
         (vec2 2 4)))

  ;; Dissipation is still deterministic: a resolved trace becomes an ordinary
  ;; group of individually faded path segments, with the requested tail alpha.
  (define fading
    (traced-path phase parabola-position
                 #:id 'fading #:sample-count 5 #:dissipate? #t
                 #:minimum-opacity 1/5 #:opacity 4/5))
  (define fading-scene
    (scene-play
     (scene-add (scene-set-value (make-scene) phase) fading)
     (value-to phase 1) #:duration 1))
  (define fading-middle (scene-visual-at fading-scene 'fading 1))
  (check-true (group-visual? fading-middle))
  (check-equal? (length (group-visual-children fading-middle)) 4)
  (check-equal?
   (map visual-opacity (group-visual-children fading-middle))
   (list 8/25 12/25 16/25 4/5))

  (check-exn exn:fail:contract?
             (lambda ()
               (traced-path phase (lambda (_context _time) origin)
                            #:id 'bad #:sample-count 1)))
  (check-exn exn:fail:contract?
             (lambda ()
               (traced-path phase (lambda (_context _time) origin)
                            #:id 'bad-window #:trail-length -1)))
  (check-exn exn:fail:contract?
             (lambda ()
               (define bad
                 (traced-path phase (lambda (_context _time) 42)
                              #:id 'bad-point))
               (define bad-scene
                 (scene-play
                  (scene-add (scene-set-value (make-scene) phase) bad)
                  (value-to phase 1) #:duration 1))
               (scene-visual-at bad-scene 'bad-point 1))))
