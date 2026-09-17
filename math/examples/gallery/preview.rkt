#lang racket/base

;;;
;;; Direct Gallery Preview Construction
;;;
;; Makes a local scene through the same preparation and compiler as the restartable
;; source. The command-line process renderer uses the separate source callbacks.

;;;
;;; Imports and Exports
;;;
(require "model.rkt" "render.rkt")
(provide make-gallery-scene!)

; make-gallery-scene! : list? [#:theme symbol?] [#:width integer?] [#:height integer?]
;   [#:show-api? boolean?] -> scene?
;;   Prepares the selected independent views once and constructs a local native scene.
(define (make-gallery-scene! plates #:theme [theme 'light] #:width [width 1280]
                            #:height [height 720] #:show-api? [show-api? #f])
  (define entries (gallery-entries plates))
  (define camera (make-gallery-camera! width height theme))
  (build-gallery-scene! entries (prepare-gallery-views! entries camera theme #:show-api? show-api?) camera
                        #:show-api? show-api?))
