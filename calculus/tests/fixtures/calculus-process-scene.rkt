#lang racket/base

;;;
;;; Reconstructible Calculus Process Fixture
;;;

;; This module deliberately owns all mathematical declarations.  A shared
;; project worker reloads it by module path instead of receiving closures or a
;; sampled polyline from its parent.


;;;
;;; Imports and Exports
;;;

(require "../../main.rkt"
         "../../render.rkt")

(provide calculus-process-scene)


;;;
;;; Lesson Source
;;;

;; calculus-process-lesson : calculus-lesson?
;;   Exercises an exact live `point-on` query while its input parameter moves.
(define-calculus-lesson calculus-process-lesson
  (model
    [a (parameter 0 #:domain (closed 0 1))]
    [f (function (x) (* x x))]
    [G (graph f)]
    [P (point-on G #:x a)])
  (views
    [plot (graph-view #:x (closed 0 1)
                      #:y (closed 0 1)
                      #:objects (G P))])
  (initially (show G P))
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step move-point (vary a #:to 1 #:duration 1)))

;; calculus-process-scene : scene?
;;   Keeps worker count and file output outside the calculus render API.
(define calculus-process-scene
  (lesson->scene calculus-process-lesson #:width 320 #:height 180))
