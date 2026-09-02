#lang racket/base

;;;
;;; SCENE-CS Multiline and Rich Text Tests
;;;

(require racket/class
         rackunit
         (only-in pict pict->bitmap)
         "../main.rkt")

(define (bitmap-has-rgb? bitmap red green blue)
  (define width (send bitmap get-width))
  (define height (send bitmap get-height))
  (define pixels (make-bytes (* width height 4)))
  (send bitmap get-argb-pixels 0 0 width height pixels)
  (for/or ([index (in-range 0 (bytes-length pixels) 4)])
    (and (= (bytes-ref pixels index) 255)
         (= (bytes-ref pixels (+ index 1)) red)
         (= (bytes-ref pixels (+ index 2)) green)
         (= (bytes-ref pixels (+ index 3)) blue))))

(module+ test
  (define test-camera
    (make-camera #:width 400 #:height 240 #:world-width 20 #:background "white"))
  (define content
    "A stable paragraph has enough words to wrap into several measured lines.")

  ;; The original one-line constructor remains strict, while paragraph accepts
  ;; explicit lines and retains their immutable source content.
  (check-exn exn:fail:contract?
             (lambda () (plain-text "first\nsecond" #:id 'plain)))
  (define explicit-lines
    (paragraph "first\nsecond" #:id 'explicit-lines
               #:horizontal-alignment 'left #:vertical-alignment 'baseline))
  (check-equal? (text-visual-content explicit-lines) "first\nsecond")
  (check-equal? (length (text-visual-spans explicit-lines)) 1)

  ;; A renderer-measured local width reflows words without changing the
  ;; paragraph's semantic source. The wrapped box is narrower and taller.
  (define unwrapped (paragraph content #:id 'unwrapped #:font-size 1/2))
  (define wrapped
    (paragraph content #:id 'wrapped #:font-size 1/2
               #:width 4 #:line-spacing 6/5 #:line-alignment 'center))
  (define unwrapped-box (visual-layout-box unwrapped #:camera test-camera))
  (define wrapped-box (visual-layout-box wrapped #:camera test-camera))
  (check-equal? (text-visual-content wrapped) content)
  (check-equal? (text-visual-width wrapped) 4)
  (check-equal? (text-visual-line-spacing wrapped) 6/5)
  (check-equal? (text-visual-line-alignment wrapped) 'center)
  (check-true (< (layout-box-width wrapped-box)
                 (layout-box-width unwrapped-box)))
  (check-true (> (layout-box-height wrapped-box)
                 (layout-box-height unwrapped-box)))

  ;; Per-span typography inherits only unspecified fields from the surrounding
  ;; Visual and paints through the same cached Pict renderer.
  (define rich
    (rich-text
     #:id 'rich #:width 9 #:font-size 1/2 #:line-alignment 'left
     "The "
     (text-span "unknown" #:color "royalblue" #:font-weight 'bold)
     " is "
     (text-span "highlighted" #:color "firebrick" #:font-style 'italic)
     "."))
  (check-equal? (text-visual-content rich)
                "The unknown is highlighted.")
  (check-equal? (length (text-visual-spans rich)) 5)
  (check-equal? (text-span-color (list-ref (text-visual-spans rich) 1))
                "royalblue")
  (check-equal? (text-span-font-weight (list-ref (text-visual-spans rich) 1))
                'bold)
  (check-equal? (text-span-font-style (list-ref (text-visual-spans rich) 3))
                'italic)
  (define rich-scene (scene-add (make-scene #:camera test-camera) rich))
  (check-true
   (bitmap-has-rgb? (pict->bitmap (scene->pict rich-scene 0) 'aligned)
                    65 105 225))
  (check-true
   (bitmap-has-rgb? (pict->bitmap (scene->pict rich-scene 0) 'aligned)
                    178 34 34))

  ;; Immutable updates preserve outer geometry/styles and replace the rich
  ;; content representation atomically.
  (define replaced (text-visual-with-content rich "new\ntext"))
  (check-equal? (visual-id replaced) 'rich)
  (check-equal? (text-visual-content replaced) "new\ntext")
  (check-equal? (length (text-visual-spans replaced)) 1)
  (define restyled
    (text-visual-with-spans
     replaced
     (list (text-span "new " #:color "darkgreen")
           (text-span "text" #:font-weight 'bold))))
  (check-equal? (text-visual-content restyled) "new text")
  (check-equal? (length (text-visual-spans restyled)) 2)

  ;; Layout and span validation rejects ambiguous or impossible source values.
  (check-exn exn:fail:contract?
             (lambda () (paragraph "text" #:id 'bad #:width 0)))
  (check-exn exn:fail:contract?
             (lambda () (paragraph "text" #:id 'bad #:line-spacing 0)))
  (check-exn exn:fail:contract?
             (lambda () (paragraph "text" #:id 'bad #:line-alignment 'justify)))
  (check-exn exn:fail:contract?
             (lambda () (text-span "span" #:font-size 0)))
  (check-exn exn:fail:contract?
             (lambda () (rich-text #:id 'bad 12))))
