#lang racket/base

;;;
;;; SCENE-DG/DH: Authored Media Assembly and Incremental Partials
;;;

;; The image is intentionally an ordinary scene diagram: it illustrates the
;; production data flow without requiring a local narration file. The real
;; assembly API is exercised with a generated audio source in scene-dg-test.rkt.

(require "../main.rkt"
         "private/run-demo.rkt")

(provide make-demo-scene
         make-demo-timeline)

(define (card id center title detail fill stroke)
  (group
   (list
    (rectangle #:id 'body #:center origin #:width 14/5 #:height 6/5
               #:fill fill #:stroke stroke #:stroke-width 2)
    (plain-text title #:id 'title #:center (vec2 0 1/6)
                #:font-size 1/4 #:font-family 'swiss #:font-weight 'bold
                #:color stroke)
    (plain-text detail #:id 'detail #:center (vec2 0 -1/5)
                #:font-size 3/20 #:font-family 'modern #:color "darkslategray"))
   #:id id #:center center))

(define (make-demo-scene)
  (define title
    (plain-text "SCENE-DG/DH: assemble only what changed"
                #:id 'title #:center (vec2 0 18/5)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define explanation
    (plain-text "cached section frames → visual partials → one final audio/caption mux"
                #:id 'explanation #:center (vec2 0 61/20)
                #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define opening
    (card 'opening (vec2 -4 1) "opening" "frames 0–2 s"
          "lightsteelblue" "navy"))
  (define proof
    (card 'proof (vec2 0 1) "proof" "frames 2–6 s"
          "honeydew" "forestgreen"))
  (define closing
    (card 'closing (vec2 4 1) "closing" "frames 6–8 s"
          "lemonchiffon" "goldenrod"))
  (define partials-label
    (plain-text "invalidated sections are re-rendered as visual-only MP4 partials"
                #:id 'partials-label #:center (vec2 0 -3/10)
                #:font-size 1/5 #:font-family 'swiss #:color "darkred"))
  (define partials
    (group
     (list
      (card 'opening-partial (vec2 -3 -8/5) "opening.mp4" "reused"
            "aliceblue" "steelblue")
      (card 'proof-partial (vec2 0 -8/5) "proof.mp4" "re-rendered"
            "mistyrose" "crimson")
      (card 'closing-partial (vec2 3 -8/5) "closing.mp4" "reused"
            "aliceblue" "steelblue"))
     #:id 'partials))
  (define final-movie
    (card 'final-movie (vec2 0 -31/10) "production.mp4"
          "AAC narration + captions" "lavender" "darkviolet"))
  (define down-arrow-one
    (arrow (vec2 0 1/5) (vec2 0 -2/5) #:id 'down-arrow-one
           #:stroke "slategray" #:stroke-width 2
           #:tip-length 1/5 #:tip-width 1/5))
  (define down-arrow-two
    (arrow (vec2 0 -47/20) (vec2 0 -5/2) #:id 'down-arrow-two
           #:stroke "slategray" #:stroke-width 2
           #:tip-length 1/5 #:tip-width 1/5))
  (define initial
    (scene-wait
     (scene-add (make-scene)
                title explanation opening proof closing)
     1))
  (define partials-appear
    (scene-play initial
                (fade-in partials-label)
                (fade-in partials)
                (fade-in down-arrow-one)
                #:duration 2))
  (define final-appears
    (scene-play partials-appear
                (fade-in final-movie)
                (fade-in down-arrow-two)
                #:duration 2))
  (scene-wait final-appears 1))

(define (make-demo-timeline)
  (define scene (make-demo-scene))
  (make-authored-timeline
   scene
   #:sections (list (section 'overview 0 1)
                    (section 'partials 1 3)
                    (section 'final-mux 3 5)
                    (section 'hold 5 6))
   #:subtitles
   (list (subtitle 0 1 "Three named sections share one output grid.")
         (subtitle 1 3 "Only an invalidated partial is rendered again.")
         (subtitle 3 5 "Audio and captions are muxed once at the end."))))

(module+ main
  (run-demo "authored-media-assembly.rkt" make-demo-scene))
