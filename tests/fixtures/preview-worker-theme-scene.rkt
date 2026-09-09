#lang racket/base

;;;
;;; Themeable Isolated Preview Fixture
;;;

;; This module deliberately retains a palette token until the subprocess
;; preview worker receives its explicit serialized theme snapshot.

(require "../../colors.rkt"
         "../../main.rkt")

(provide worker-theme-scene)

(define worker-theme-scene
  (scene-wait
   (scene-add
    (make-scene #:camera (make-camera #:width 80 #:height 60 #:world-width 4))
    (circle #:id 'worker-theme-dot #:radius 1 #:fill aqua-c #:stroke #f))
   1))
