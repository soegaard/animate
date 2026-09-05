#lang racket/base

;;;
;;; SCENE-CW: Authored Timeline Sections
;;;

;; A normal immutable scene is decorated with named, half-open sections and
;; cue/audio-placement metadata. The red playhead represents the unchanged
;; global output timeline; selected section renders write those global samples
;; as a separately numbered local frame sequence.

(require animate
         animate/authoring
         "private/run-demo.rkt")

(provide make-demo-scene
         make-demo-timeline)

(define (make-demo-scene)
  (define title
    (plain-text "SCENE-CW: authored timeline sections"
                #:id 'title #:center (vec2 0 16/5)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define explanation
    (plain-text "Named spans select the original frame grid; each render is numbered locally."
                #:id 'explanation #:center (vec2 0 13/5)
                #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define opening
    (rectangle #:id 'opening #:center (vec2 -3 1/4)
               #:width 2 #:height 4/5
               #:fill "lightsteelblue" #:stroke "navy" #:stroke-width 2))
  (define derivation
    (rectangle #:id 'derivation #:center (vec2 0 1/4)
               #:width 4 #:height 4/5
               #:fill "palegreen" #:stroke "forestgreen" #:stroke-width 2))
  (define conclusion
    (rectangle #:id 'conclusion #:center (vec2 3 1/4)
               #:width 2 #:height 4/5
               #:fill "moccasin" #:stroke "goldenrod" #:stroke-width 2))
  (define opening-label
    (paragraph "opening\n0–2 s" #:id 'opening-label #:center (vec2 -3 1/4)
               #:width 9/5 #:line-alignment 'center #:line-spacing 9/10
               #:font-size 1/5 #:font-family 'swiss #:font-weight 'bold
               #:color "navy"))
  (define derivation-label
    (paragraph "derivation\n2–6 s" #:id 'derivation-label #:center (vec2 0 1/4)
               #:width 19/5 #:line-alignment 'center #:line-spacing 9/10
               #:font-size 1/5 #:font-family 'swiss #:font-weight 'bold
               #:color "darkgreen"))
  (define conclusion-label
    (paragraph "conclusion\n6–8 s" #:id 'conclusion-label #:center (vec2 3 1/4)
               #:width 9/5 #:line-alignment 'center #:line-spacing 9/10
               #:font-size 1/5 #:font-family 'swiss #:font-weight 'bold
               #:color "darkgoldenrod"))
  (define cue-one
    (circle #:id 'cue-one #:center (vec2 -2 7/8) #:radius 1/12
            #:fill "crimson" #:stroke "firebrick" #:stroke-width 1))
  (define cue-two
    (circle #:id 'cue-two #:center (vec2 2 7/8) #:radius 1/12
            #:fill "crimson" #:stroke "firebrick" #:stroke-width 1))
  (define cue-label
    (plain-text "cue markers: begin derivation · conclusion"
                #:id 'cue-label #:center (vec2 0 -3/4)
                #:font-size 1/5 #:font-family 'swiss #:color "crimson"))
  (define playhead
    (line (vec2 -4 -3/10) (vec2 -4 4/5)
          #:id 'playhead #:stroke "crimson" #:stroke-width 4))
  (define playhead-label
    (follow-anchor
     (plain-text "global frame time" #:id 'playhead-label #:center origin
                 #:font-size 1/5 #:font-family 'swiss #:color "firebrick")
     'playhead #:target-anchor 'top #:self-anchor 'bottom
     #:offset (vec2 0 1/5)))
  (define note
    (plain-text "render-timeline-section! writes a reusable local clip cache"
                #:id 'note #:center (vec2 0 -12/5)
                #:font-size 1/5 #:font-family 'modern #:color "darkslategray"))
  (define initial
    (scene-wait
     (scene-add (make-scene)
                title explanation opening derivation conclusion
                opening-label derivation-label conclusion-label
                cue-one cue-two cue-label playhead playhead-label note)
     1))
  (scene-wait
   ;; `move-to` targets the line's midpoint, which starts at y = 1/4. Preserve
   ;; that ordinate so the playhead represents time with horizontal motion only.
   (scene-play initial (move-to 'playhead (vec2 4 1/4)) #:duration 6)
   1))

(define (make-demo-timeline)
  (make-authored-timeline
   (make-demo-scene)
   #:sections
   (list (section 'opening 0 2)
         (section 'derivation 2 6)
         (section 'conclusion 6 8))
   #:cues
   (list (cue 'begin-derivation 2)
         (cue 'conclusion 6))
   #:audio-cues
   (list (audio-cue "narration.wav" #:start 0 #:duration 8))))

(module+ main
  (run-demo "authoring-sections.rkt" make-demo-scene))
