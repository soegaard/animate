#lang racket/base

;;;
;;; Pure Scene Frame Grid
;;;

;; Defines the deterministic conversion between an immutable scene timeline
;; and its zero-based output-frame grid. This has no Pict or output dependency.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "scene.rkt")

;; Exports
(provide scene-frame-count
         frame-index->time)


;;;
;;; Frame Grid
;;;

; scene-frame-count : scene? [#:fps exact-positive-integer?]
;                    -> exact-nonnegative-integer?
;;   Returns the number of sampled frames needed for scene.
(define (scene-frame-count scn #:fps [fps 30])
  (unless (scene? scn)
    (raise-argument-error 'scene-frame-count "scene?" scn))
  (check-fps 'scene-frame-count fps)
  (define count
    (ceiling (* (scene-duration scn) fps)))
  (if (exact-integer? count)
      count
      (inexact->exact count)))

; frame-index->time : exact-nonnegative-integer?
;                     [#:fps exact-positive-integer?]
;                     -> nonnegative-real?
;;   Converts a zero-based frame index to its exact sample time.
(define (frame-index->time frame-index #:fps [fps 30])
  (check-fps 'frame-index->time fps)
  (unless (exact-nonnegative-integer? frame-index)
    (raise-argument-error
     'frame-index->time
     "exact-nonnegative-integer?"
     frame-index))
  (/ frame-index fps))


;;;
;;; Validation
;;;

(define (check-fps who fps)
  (unless (exact-positive-integer? fps)
    (raise-argument-error who "exact-positive-integer?" fps)))
