#lang racket/base

;;;
;;; SCENE-BO/BP Shared Renderer Resource Cache Tests
;;;

(require rackunit
         (only-in pict filled-rectangle)
         (submod "../private/latex-formula-pict-renderer.rkt" test-support)
         "../private/renderer-resources.rkt"
         "../main.rkt")

(module+ test
  ;; The generic cache uses a deterministic LRU policy and tracks resources
  ;; separately from semantic scene state.
  (define cache
    (make-renderer-resource-cache #:max-entries 2 #:max-bytes 6))
  (define load-count 0)
  (define (loader value bytes)
    (lambda ()
      (set! load-count (add1 load-count))
      (values value bytes)))
  (check-equal? (renderer-resource-cache-ref! cache 'a (loader 'one 3)) 'one)
  (check-equal? (renderer-resource-cache-ref! cache 'b (loader 'two 3)) 'two)
  ;; Refresh a, making b the least-recently used entry.
  (check-equal? (renderer-resource-cache-ref! cache 'a (loader 'wrong 3)) 'one)
  (check-equal? (renderer-resource-cache-ref! cache 'c (loader 'three 3)) 'three)
  (check-equal? load-count 3)
  (define first-stats (renderer-resource-cache-statistics cache))
  (check-equal? (renderer-resource-cache-stats-entries first-stats) 2)
  (check-equal? (renderer-resource-cache-stats-bytes first-stats) 6)
  (check-equal? (renderer-resource-cache-stats-hits first-stats) 1)
  (check-equal? (renderer-resource-cache-stats-misses first-stats) 3)
  (check-equal? (renderer-resource-cache-stats-evictions first-stats) 1)
  ;; b was evicted and therefore calls its loader again.
  (check-equal? (renderer-resource-cache-ref! cache 'b (loader 'two-again 3))
                'two-again)
  (check-equal? load-count 4)
  (renderer-resource-cache-clear! cache)
  (define cleared-stats (renderer-resource-cache-statistics cache))
  (check-equal? (renderer-resource-cache-stats-entries cleared-stats) 0)
  (check-equal? (renderer-resource-cache-stats-bytes cleared-stats) 0)
  (check-equal? (renderer-resource-cache-stats-evictions cleared-stats) 2)

  ;; Formula appearances remain cached through placement, opacity, and camera
  ;; panning, while appearance-changing scale and source invalidate the key.
  (define viewport
    (make-camera #:width 200 #:height 100 #:world-width 10))
  (define panned-viewport
    (make-camera #:width 200 #:height 100 #:world-width 10 #:center (vec2 3 -2)))
  (define formula-cache (make-renderer-resource-cache #:max-entries 8))
  (define typeset-count 0)
  (define (fake-typesetter _visual)
    (set! typeset-count (add1 typeset-count))
    (filled-rectangle 20 10 #:color "navy"))
  (define formula (latex-formula "x^2" #:id 'formula))
  (define local-pict
    (formula-visual->pict/cached-using formula viewport formula-cache fake-typesetter))
  (check-eq?
   (formula-visual->pict/cached-using
    (visual-with-position formula (vec2 2 1)) viewport formula-cache fake-typesetter)
   local-pict)
  (check-eq?
   (formula-visual->pict/cached-using
    (visual-with-opacity formula 1/2) panned-viewport formula-cache fake-typesetter)
   local-pict)
  (check-equal? typeset-count 1)
  (void
   (formula-visual->pict/cached-using
    (visual-with-scale formula 2) viewport formula-cache fake-typesetter))
  (void
   (formula-visual->pict/cached-using
    (formula-visual-with-source formula "y^2") viewport formula-cache fake-typesetter))
  (check-equal? typeset-count 3))
