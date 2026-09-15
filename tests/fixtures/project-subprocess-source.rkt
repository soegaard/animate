#lang racket/base

;;;
;;; Project Subprocess Source Fixture
;;;

;; Supplies a small restartable scene and authored timeline for PR-D's normal
;; project execution tests. The fixture has no process behavior of its own.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "../../authoring.rkt"
         "../../main.rkt")

;; Exports
(provide project-subprocess-scene
         project-subprocess-timeline)


;;;
;;; Restartable Values
;;;

; project-subprocess-scene : scene?
;;   Holds a deterministic dot long enough for all, range, and frame targets.
(define project-subprocess-scene
  (scene-wait
   (scene-add
    (make-scene #:camera (make-camera #:width 80 #:height 50 #:world-width 8))
    (circle #:id 'project-subprocess-dot #:radius 1 #:fill "tomato"))
   2))

; project-subprocess-timeline : authored-timeline?
;;   Divides the fixture scene into two one-second named target sections.
(define project-subprocess-timeline
  (make-authored-timeline
   project-subprocess-scene
   #:sections (list (section 'first 0 1)
                    (section 'second 1 2))))
