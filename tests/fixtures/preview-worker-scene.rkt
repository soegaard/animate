#lang racket/base

;; A deliberately small module-backed scene used by the subprocess-preview
;; protocol test. It has no GUI dependency and proves that a fresh Racket
;; process can recreate declared scene semantics from a module binding.

(require "../../main.rkt")

(provide worker-scene)

(define worker-scene
  (scene-wait
   (scene-add
    (make-scene)
    (circle #:id 'worker-dot #:center (vec2 0 0) #:radius 1
            #:fill "tomato" #:stroke "firebrick"))
   1))
