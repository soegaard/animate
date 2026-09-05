#lang racket/base

;; SCENE-EI: click a nested Visual in the preview, then use the returned REPL
;; from a Racket listener. For example: (checkpoint! 'before-experiment),
;; (wait! 1), (undo!), (inspect), or (reload!).

(require racket/runtime-path
         animate/authoring
         animate
         animate/preview)

(define-scene-program inspector-demo
  #:initial
  (scene-add
   (make-scene)
   (group
    (list (rectangle #:id 'panel #:width 5 #:height 3 #:fill "aliceblue")
          (group (list (circle #:id 'dot #:radius 1/2 #:fill "orange"))
                 #:id 'nested #:center (vec2 -1 0)))
    #:id 'diagram))

  (scene-block move-dot (scene)
    (scene-play scene (move-to '(diagram nested dot) (vec2 2 0)) #:duration 2))

  (scene-block settle (scene)
    (scene-wait scene 1)))

(provide inspector-demo
         open-inspector-preview)

(define-runtime-path source-path "preview-repl-inspector.rkt")

(define (open-inspector-preview)
  (define preview
    (open-program-preview source-path 'inspector-demo #:title "Animate: inspector"))
  (values preview (open-preview-repl! preview)))

(module+ main
  (define-values (preview repl) (open-inspector-preview))
  (displayln "Preview REPL ready. Try (inspect), (checkpoint! 'before-experiment), or (reload!).")
  repl)
