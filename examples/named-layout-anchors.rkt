#lang racket/base

;;;
;;; SCENE-CC Named Layout Anchors
;;;

;; Shows one shared nine-point vocabulary for renderer-aware layout. The panel,
;; captions, and marker dots are positioned from measured render-box anchors;
;; no hand-tuned text bounds are required.


;;;
;;; Imports
;;;

(require racket/cmdline
         animate
         animate/render)

(provide make-demo-scene)


;;;
;;; Scene Definition
;;;

; make-demo-scene : -> scene?
;;   Builds a compact diagram of named render-box anchors.
(define (make-demo-scene)
  (define panel
    (rectangle #:id 'panel
               #:center (vec2 0 -1/4)
               #:width 6
               #:height 7/2
               #:fill "aliceblue"
               #:stroke "navy"
               #:stroke-width 3))

  (define title
    (visual-place-at
     (plain-text "SCENE-CC: named layout anchors"
                 #:id 'title
                 #:font-size 2/5
                 #:font-family 'swiss
                 #:font-weight 'bold
                 #:color "navy")
     (vec2 0 7/2)
     #:anchor 'top))

  (define top-caption
    (visual-place-at
     (plain-text "top"
                 #:id 'top-caption
                 #:font-size 3/10
                 #:font-family 'swiss
                 #:color "midnightblue")
     (vec2+ (visual-layout-anchor panel 'top)
            (vec2 0 1/4))
     #:anchor 'bottom))

  (define corner-caption
    (visual-place-at
     (plain-text "top-right"
                 #:id 'corner-caption
                 #:font-size 3/10
                 #:font-family 'swiss
                 #:color "midnightblue")
     (vec2+ (visual-layout-anchor panel 'top-right)
            (vec2 1/4 1/4))
     #:anchor 'bottom-left))

  (define right-caption
    (visual-place-at
     (plain-text "right"
                 #:id 'right-caption
                 #:font-size 3/10
                 #:font-family 'swiss
                 #:color "midnightblue")
     (vec2+ (visual-layout-anchor panel 'right)
            (vec2 1/4 0))
     #:anchor 'left))

  (define center-caption
    (visual-align-to
     (plain-text "center"
                 #:id 'center-caption
                 #:font-size 3/10
                 #:font-family 'swiss
                 #:color "midnightblue")
     panel))

  (define anchors
    (for/list ([entry
                (in-list
                 (list (cons 'top-left "crimson")
                       (cons 'top "crimson")
                       (cons 'top-right "crimson")
                       (cons 'left "seagreen")
                       (cons 'center "darkorange")
                       (cons 'right "seagreen")
                       (cons 'bottom-left "crimson")
                       (cons 'bottom "crimson")
                       (cons 'bottom-right "crimson")))]
               [index (in-naturals)])
      (circle #:id (string->symbol (format "anchor-~a" index))
              #:center (visual-layout-anchor panel (car entry))
              #:radius 1/10
              #:fill (cdr entry)
              #:stroke "white"
              #:stroke-width 1)))

  (define initial
    (scene-add (make-scene) title))
  (define introduced
    (apply scene-play
           initial
           #:duration 1
           (append (list (fade-in panel)
                         (fade-in top-caption)
                         (fade-in corner-caption)
                         (fade-in right-caption)
                         (fade-in center-caption))
                   (map fade-in anchors))))
  (scene-wait introduced 2))


;;;
;;; Command-Line Entry Point
;;;

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "named-layout-anchors.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define frame-paths
    (render-frames! (make-demo-scene) output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n" (length frame-paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
