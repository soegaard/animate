#lang racket/base

;;;
;;; FX-F2 Frozen-Layout Typewrite Tests
;;;

(require racket/class
         rackunit
         "../main.rkt"
         "../private/text-reveal-visual.rkt")

(define (bitmap-bytes bitmap)
  (define width (send bitmap get-width))
  (define height (send bitmap get-height))
  (define pixels (make-bytes (* 4 width height)))
  (send bitmap get-argb-pixels 0 0 width height pixels)
  pixels)

(module+ test
  ;; `office` is deliberately ligature-sensitive in many fonts.  The partial
  ;; frames are rendered as clips of the final shaped run, not as independently
  ;; laid-out prefix strings.
  (define caption
    (plain-text "office" #:id 'caption #:font-size 1/2))
  (define request
    (typewrite caption))
  (check-true (typewrite-request? request))
  (check-equal? request (typewrite caption))

  (define animated
    (scene-play (make-scene) request #:duration 2))
  (define initial (scene-visual-at animated 'caption 0))
  (define partial (scene-visual-at animated 'caption 1/2))
  (define complete (scene-visual-at animated 'caption 2))
  (check-true (text-reveal-visual? initial))
  (check-equal? (text-reveal-visual-revealed-count initial) 0)
  (check-true (text-reveal-visual? partial))
  (check-equal? (text-reveal-visual-revealed-count partial) 1)
  (check-equal? complete caption)
  (check-equal? (scene-current-state animated)
                (scene-sample animated 2))
  (check-equal? (scene-sample animated 1/2)
                (scene-sample animated 1/2))

  ;; The ordinary software rendering path accepts both the empty and clipped
  ;; presentations, while the final sampled frame remains the authored Visual.
  (check-not-false (scene-frame->bitmap animated 0 #:fps 2))
  (check-not-false (scene-frame->bitmap animated 1 #:fps 2))
  (check-not-false (scene-frame->bitmap animated 3 #:fps 2))
  (check-equal?
   (animation-inspection-kind
    (car (scene-animation-inspections-at animated 1/2)))
   'typewrite)

  ;; Source segmentation is independent from the visible grapheme front, so a
  ;; word request still reveals all preceding whitespace deterministically.
  (define word-request
    (typewrite (plain-text "one two" #:id 'words) #:unit 'word))
  (define word-scene
    (scene-play (make-scene) word-request #:duration 1))
  (check-equal?
   (text-reveal-visual-revealed-count
    (scene-visual-at word-scene 'words 1/2))
   1)
  (check-not-false (scene-frame->bitmap word-scene 1 #:fps 2))

  ;; Rich and reflowing sources use prepared cluster rectangles over their one
  ;; final layout. Their interior frames therefore render without replacing the
  ;; source with transient prefixes.
  (define rich-caption
    (rich-text #:id 'rich
               (text-span "warm " #:color "tomato")
               (text-span "cold" #:font-weight 'bold)))
  (define rich-scene
    (scene-play
     (make-scene)
     (typewrite rich-caption)
     #:duration 2))
  (check-not-false (scene-frame->bitmap rich-scene 0 #:fps 2))
  (check-equal? (scene-visual-at rich-scene 'rich 2) rich-caption)
  (define rich-start (scene-frame->bitmap rich-scene 0 #:fps 2))
  (define rich-middle (scene-frame->bitmap rich-scene 1 #:fps 2))
  (define rich-end (scene-frame->bitmap rich-scene 3 #:fps 2))
  (check-not-equal? (bitmap-bytes rich-start) (bitmap-bytes rich-middle))
  (check-not-equal? (bitmap-bytes rich-middle) (bitmap-bytes rich-end))

  (define multiline-caption
    (paragraph "first line\nsecond line wraps here"
               #:id 'multiline #:font-size 1/2 #:width 9/5))
  (define multiline-scene
    (scene-play (make-scene) (typewrite multiline-caption) #:duration 2))
  (define multiline-middle (scene-frame->bitmap multiline-scene 1 #:fps 2))
  (define multiline-end (scene-frame->bitmap multiline-scene 3 #:fps 2))
  (check-not-equal? (bitmap-bytes multiline-middle) (bitmap-bytes multiline-end))

  ;; An optional cursor is renderer-local presentation during the open clip.
  ;; It changes the clipped frame but does not survive the exact authored
  ;; endpoint or become a helper Visual in the semantic Scene state.
  (define cursor-caption (plain-text "cursor" #:id 'cursor #:font-size 1/2))
  (define cursor-scene
    (scene-play (make-scene)
                (typewrite cursor-caption #:cursor? #t #:cursor-style "tomato")
                #:duration 2))
  (define no-cursor-scene
    (scene-play (make-scene) (typewrite cursor-caption) #:duration 2))
  (define cursor-start (scene-visual-at cursor-scene 'cursor 0))
  (check-true (text-reveal-visual-cursor? cursor-start))
  (check-equal? (text-reveal-visual-cursor-style cursor-start) "tomato")
  (check-not-equal?
   (bitmap-bytes (scene-frame->bitmap cursor-scene 1 #:fps 2))
   (bitmap-bytes (scene-frame->bitmap no-cursor-scene 1 #:fps 2)))
  (check-equal? (scene-visual-at cursor-scene 'cursor 2) cursor-caption)
  (define cursor-inspection
    (animation-inspection-data
     (car (scene-animation-inspections-at cursor-scene 1/2))))
  (check-true (hash-ref cursor-inspection 'cursor?))
  (check-equal? (hash-ref cursor-inspection 'cursor-lifecycle) 'open-clip-only)

  (check-exn exn:fail:contract?
             (lambda () (typewrite (circle #:id 'not-text))))
  (check-exn exn:fail:contract?
             (lambda () (typewrite caption #:unit 'letter)))
  (check-exn exn:fail:contract?
             (lambda () (typewrite caption #:cursor? 'yes)))
  (check-exn exn:fail:contract?
             (lambda () (typewrite caption #:cursor-style 'not-a-color))))
