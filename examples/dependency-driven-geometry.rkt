#lang racket/base

;;;
;;; Dependency-Driven Geometry Example
;;;

;; SCENE-AX lets one pure derived Visual depend on another resolved top-level
;; Visual from the same immutable sampled scene state.

(require racket/cmdline
         "../main.rkt")

(provide make-demo-scene)

(define (smoothstep progress)
  (* progress progress (- 3 (* 2 progress))))

(define (make-demo-scene)
  (define camera
    (make-camera #:width 960
                 #:height 540
                 #:world-width 18
                 #:background "white"))

  ;; The leader is driven only by scalar values.
  (define leader
    (derived-visual
     (circle #:id 'leader
             #:center (vec2 -5 0)
             #:radius 3/4
             #:fill "royalblue"
             #:stroke "midnightblue"
             #:stroke-width 4)
     (lambda (context template)
       (visual-with-position
        template
        (vec2 (derived-context-value-ref context 'x)
              (* 2 (derived-context-value-ref context 'lift)))))))

  ;; The halo follows the resolved leader Visual. It is inserted before the
  ;; leader so the example also demonstrates drawing-order-independent lookup.
  (define halo
    (derived-visual
     (circle #:id 'halo
             #:center origin
             #:radius 6/5
             #:fill #f
             #:stroke "gold"
             #:stroke-width 5)
     (lambda (context template)
       (visual-with-position
        template
        (visual-position
         (derived-context-visual-ref context 'leader))))))

  ;; The tether also depends on the leader and reconstructs path geometry from
  ;; that resolved position.
  (define tether-anchor (vec2 -7 -3))
  (define tether
    (derived-visual
     (line tether-anchor origin
           #:id 'tether
           #:stroke "gray"
           #:stroke-width 2)
     (lambda (context template)
       (line tether-anchor
             (visual-position
              (derived-context-visual-ref context 'leader))
             #:id (visual-id template)
             #:stroke "gray"
             #:stroke-width 2))))

  ;; This is a second dependency level: the tag follows the halo, which itself
  ;; follows the scalar-driven leader.
  (define tag
    (derived-visual
     (plain-text "dependent"
                 #:id 'tag
                 #:font-size 2/5
                 #:font-family 'swiss
                 #:color "black")
     (lambda (context template)
       (visual-with-position
        template
        (vec2+ (visual-position
                (derived-context-visual-ref context 'halo))
               (vec2 0 3/2))))))

  (define title
    (fixed-in-frame
     (plain-text "SCENE-AX: dependency-driven geometry"
                 #:id 'title-text
                 #:font-size 2/5
                 #:font-family 'swiss
                 #:color "black")
     #:camera camera
     #:at (vec2 0 4)))

  (define initial
    (scene-add
     (scene-set-value
      (scene-set-value (make-scene #:camera camera) 'x -5)
      'lift 0)
     tether
     halo
     leader
     tag
     title))
  (define intro (scene-wait initial 1))
  (define animated
    (scene-play
     intro
     (animation-group
      (value-to 'x 5)
      (succession
       (value-to 'lift 1)
       (value-to 'lift -1)
       (value-to 'lift 0)))
     #:duration 6
     #:easing smoothstep))
  (scene-wait animated 1))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "dependency-driven-geometry.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define frame-paths
    (render-frames! (make-demo-scene) output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n"
          (length frame-paths)
          output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
