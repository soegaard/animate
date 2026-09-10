#lang racket/base

;; A semantic title remains unresolved in this module. The worker must receive
;; its complete typography datum with the render request to choose its pixels.

(require "../../main.rkt")

(provide worker-typography-scene)

(define worker-typography-scene
  (scene-wait
   (scene-add
    (make-scene #:camera (make-camera #:width 160 #:height 90 #:world-width 8
                                      #:background "white"))
    (title-text "Typography" #:id 'worker-typography-title #:center origin))
   1))
