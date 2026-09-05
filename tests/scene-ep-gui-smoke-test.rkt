#lang racket/base

;;;
;;; SCENE-EP GUI Production Preview Smoke Test
;;;

;; This test is intentionally safe in the ordinary headless suite: requiring
;; animate/preview does not initialize a GUI, and the body only opens a window
;; when the current launcher is GRacket.  The CI GUI lane runs this file under
;; Xvfb + GRacket, which exercises the actual canvas paint/eventspace path
;; rather than only the headless preview controller.

(require rackunit
         racket/class
         racket/draw
         "../main.rkt"
         "../preview.rkt")

(define (wait-for-value thunk)
  (let loop ([remaining 40])
    (define value (thunk))
    (cond
      [value value]
      [(zero? remaining) #f]
      [else (sleep 1/20) (loop (sub1 remaining))])))

(module+ test
  (when (preview-available?)
    ;; Use a real bitmap so the canvas performs normal preview painting while
    ;; keeping this smoke test independent of Pict/LaTeX renderers.
    (define bitmap (make-object bitmap% 16 16))
    (define title "Animate: EP GUI smoke")
    (define session
      (open-scene-preview
       (scene-wait (make-scene) 1)
       #:fps 2
       #:prefetch 0
       #:title title
       #:producer
       (lambda (_document _sample _render-spec _cancellation-token) bitmap)))
    (check-true (preview-open? session))
    (check-true
     (is-a? (wait-for-value (lambda () (preview-current-bitmap session)))
            bitmap%))
    ;; The public session deliberately does not leak a frame% value.  In this
    ;; isolated GUI test process, find the titled top-level window through the
    ;; GUI API and close it as an author would.  Its augmentable on-close hook
    ;; owns controller shutdown, so this also verifies preview resource
    ;; cleanup from the window side.
    (define top-level-windows
      (dynamic-require 'racket/gui/base 'get-top-level-windows))
    (define preview-window
      (for/first ([window (in-list (top-level-windows))]
                  #:when (equal? (send window get-label) title))
        window))
    (check-not-false preview-window)
    (send preview-window on-close)
    (let loop ([remaining 40])
      (when (and (preview-open? session) (positive? remaining))
        (sleep 1/20)
        (loop (sub1 remaining))))
    (check-false (preview-open? session))
    ;; A top-level GUI eventspace keeps GRacket alive after `raco test` has
    ;; completed. This file is run as the one isolated test in the GUI CI
    ;; lane, so terminate that launcher only after all assertions have passed.
    ;; Ordinary headless `raco test tests` never enters this branch.
    (exit 0)))
