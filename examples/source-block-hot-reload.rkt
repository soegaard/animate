#lang racket/base

;; SCENE-EH: edit either block below while this preview remains open. The
;; `setup` checkpoint is reused when only `move-dot` changes; edits outside a
;; scene-block deliberately rebuild the complete program. The preview's
;; `block` selector lists these source-level units directly.

(require racket/runtime-path
         "../authoring.rkt"
         "../main.rkt"
         "../preview.rkt")

(define dot
  (circle #:id 'dot #:center (vec2 -3 0) #:radius 1/2
          #:fill "tomato" #:stroke "firebrick"))

(define label
  (plain-text "Edit a named scene block and save"
              #:id 'label #:center (vec2 0 2)
              #:font-size 1/3 #:font-family 'swiss #:color "navy"))

(define-scene-program hot-reload-demo
  #:initial (make-scene)

  (scene-block setup (scene)
    (scene-wait (scene-add scene dot label) 1))

  (scene-block move-dot (scene)
    (scene-play scene (move-to 'dot (vec2 3 0)) #:duration 2))

  (scene-block hold (scene)
    (scene-wait scene 1)))

(provide hot-reload-demo)

(define-runtime-path source-path "source-block-hot-reload.rkt")

(module+ main
  (void
   (open-program-preview source-path 'hot-reload-demo #:title "animate: hot reload")))
