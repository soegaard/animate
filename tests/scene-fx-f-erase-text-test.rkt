#lang racket/base

;;;
;;; FX-F3 Frozen-Layout Text Erasure Tests
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
  (define caption
    (plain-text "sable" #:id 'caption #:font-size 1/2))
  (define initial-scene
    (scene-add (make-scene) caption))
  (define request (erase-text 'caption))
  (check-true (erase-text-request? request))
  (define erased
    (scene-play initial-scene request #:duration 2))

  ;; The original source is present without a wrapper at the exact local
  ;; start. Interior frame counts decrease directly with time, and the target
  ;; is absent at both the sampled and structural endpoint.
  (check-equal? (scene-visual-at erased 'caption 0) caption)
  (define partial (scene-visual-at erased 'caption 1/2))
  (check-true (text-reveal-visual? partial))
  (check-equal? (text-reveal-visual-revealed-count partial) 4)
  (check-false (scene-state-has? (scene-sample erased 2) 'caption))
  (check-false (scene-state-has? (scene-current-state erased) 'caption))
  (check-equal? (scene-sample erased 1/2)
                (scene-sample erased 1/2))
  (check-not-false (scene-frame->bitmap erased 0 #:fps 2))
  (check-not-false (scene-frame->bitmap erased 1 #:fps 2))
  (check-equal?
   (animation-inspection-kind
    (car (scene-animation-inspections-at erased 1/2)))
   'erase-text)

  ;; Run timing retains the semantic source order, including whitespace.
  (define words
    (plain-text "one two" #:id 'words))
  (define word-scene
    (scene-play (scene-add (make-scene) words)
                (erase-text words #:unit 'run)
                #:duration 1))
  (check-equal?
   (text-reveal-visual-revealed-count
    (scene-visual-at word-scene 'words 1/2))
   2)
  (check-false (scene-state-has? (scene-sample word-scene 1) 'words))

  ;; Rich spans and wrapped source text are rejected at interior frontiers
  ;; until a shaped-layout backend can provide exact fragment geometry. Their
  ;; endpoints remain available as ordinary source/removal states.
  (define rich-caption
    (rich-text #:id 'rich
               (text-span "warm " #:color "tomato")
               (text-span "cold" #:font-weight 'bold)))
  (define rich-erasure
    (scene-play (scene-add (make-scene) rich-caption)
                (erase-text 'rich)
                #:duration 2))
  (check-not-false (scene-frame->bitmap rich-erasure 0 #:fps 2))
  (check-exn exn:fail:contract?
             (lambda () (scene-frame->bitmap rich-erasure 1 #:fps 2)))
  (check-false (scene-state-has? (scene-sample rich-erasure 2) 'rich))

  (define multiline-caption
    (paragraph "sable line\nsecond line wraps here"
               #:id 'multiline #:font-size 1/2 #:width 9/5))
  (define multiline-erasure
    (scene-play (scene-add (make-scene) multiline-caption)
                (erase-text 'multiline)
                #:duration 2))
  (check-not-false (scene-frame->bitmap multiline-erasure 0 #:fps 2))
  (check-exn exn:fail:contract?
             (lambda () (scene-frame->bitmap multiline-erasure 1 #:fps 2)))
  (check-false (scene-state-has? (scene-sample multiline-erasure 2) 'multiline))

  (define ligature-erasure
    (scene-play (scene-add (make-scene) (plain-text "office" #:id 'ligature))
                (erase-text 'ligature)
                #:duration 1))
  (check-not-false (scene-frame->bitmap ligature-erasure 0 #:fps 2))
  (check-exn exn:fail:contract?
             (lambda () (scene-frame->bitmap ligature-erasure 1 #:fps 2)))

  ;; Erasure keeps its exact source at local progress zero. An optional cursor
  ;; appears only after the frontier begins to move and disappears together
  ;; with the target at the structural endpoint.
  (define cursor-caption (plain-text "cursor" #:id 'cursor #:font-size 1/2))
  (define cursor-erasure
    (scene-play (scene-add (make-scene) cursor-caption)
                (erase-text 'cursor #:cursor? #t #:cursor-style "tomato")
                #:duration 2))
  (define no-cursor-erasure
    (scene-play (scene-add (make-scene) cursor-caption)
                (erase-text 'cursor)
                #:duration 2))
  (check-equal? (scene-visual-at cursor-erasure 'cursor 0) cursor-caption)
  (define cursor-partial (scene-visual-at cursor-erasure 'cursor 1/2))
  (check-true (text-reveal-visual-cursor? cursor-partial))
  (check-equal? (text-reveal-visual-cursor-style cursor-partial) "tomato")
  (check-not-equal?
   (bitmap-bytes (scene-frame->bitmap cursor-erasure 1 #:fps 2))
   (bitmap-bytes (scene-frame->bitmap no-cursor-erasure 1 #:fps 2)))
  (check-false (scene-state-has? (scene-sample cursor-erasure 2) 'cursor))
  (define cursor-inspection
    (animation-inspection-data
     (car (scene-animation-inspections-at cursor-erasure 1/2))))
  (check-true (hash-ref cursor-inspection 'cursor?))
  (check-equal? (hash-ref cursor-inspection 'cursor-lifecycle) 'open-clip-only)

  (check-exn exn:fail:contract?
             (lambda () (erase-text (circle #:id 'not-text))))
  (check-exn exn:fail?
             (lambda ()
               (scene-play (make-scene) (erase-text 'missing))))
  (check-exn exn:fail:contract?
             (lambda () (erase-text 'caption #:cursor? 'yes)))
  (check-exn exn:fail:contract?
             (lambda () (erase-text 'caption #:cursor-style 'not-a-color))))
