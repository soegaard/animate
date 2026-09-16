#lang racket/base
(require racket/class racket/list racket/string
         (only-in racket/draw make-font color%)
         (prefix-in p: pict)
         "data.rkt" "check.rkt" "appearance.rkt"
         "../../colors.rkt" "../../typography.rkt"
         "../../private/camera.rkt"
         "../../private/text-treatment-pict.rkt"
         "../../private/render-color-context.rkt")
(provide measure-scale text-asset pict-asset content-color content-width content-height
         content-theme content-format color->draw asset-pict capture-colors)

(define measure-scale 100)
(define measurement-camera (make-camera #:width 1600 #:height 900 #:world-width 16))
(define (color->draw color)
  (make-object color%
    (inexact->exact (round (rgba-color-red color)))
    (inexact->exact (round (rgba-color-green color)))
    (inexact->exact (round (rgba-color-blue color)))
    (rgba-color-alpha color)))
(define (content-color ctx key)
  (color->draw (resolve-color (role-color key) (theme-value-colors (content-context-value-theme ctx)))))
(define (content-width ctx) (box-value-width (content-context-value-box ctx)))
(define (content-height ctx) (box-value-height (content-context-value-box ctx)))
(define (content-theme ctx) (content-context-value-theme ctx))
(define (content-format ctx) (content-context-value-format ctx))

;; Delayed Pict callbacks run with the same explicit color snapshot as their
;; preparation. They never inherit an unrelated later project's theme.
(define (capture-colors picture theme)
  (define context (make-render-color-context theme))
  (p:dc (lambda (dc x y)
          (parameterize ([current-render-color-context context]) (p:draw-pict picture dc x y)))
        (p:pict-width picture) (p:pict-height picture)
        (p:pict-ascent picture) (p:pict-descent picture)))

(define (text-asset text role width theme #:align [align #f])
  (define style (role-style theme role))
  (define pixels (* measure-scale (text-style-font-size style)))
  (define font (make-font #:size pixels #:size-in-pixels? #t
                          #:family (text-style-font-family style)
                          #:face (text-style-font-face style)
                          #:style (text-style-font-style style)
                          #:weight (text-style-font-weight style)))
  (define draw-color (color->draw (resolve-color (text-style-color style) (theme-value-colors theme))))
  (define (run s) (p:colorize (p:text s font) draw-color))
  (define cache (make-hash))
  (define (run-width s) (hash-ref! cache s (lambda () (p:pict-width (run s)))))
  (define treatment (text-style-treatment style))
  (define px (if treatment (* pixels (text-treatment-padding-x treatment)) 0))
  (define available (max 0 (- (* width measure-scale) (* 2 px))))
  (define (wrap-line line)
    (define words (string-split line))
    (cond [(null? words) (list "")]
          [else
           (let loop ([words (cdr words)] [current (car words)] [result '()])
             (cond [(null? words) (reverse (cons current result))]
                   [else
                    (define candidate (string-append current " " (car words)))
                    (if (<= (run-width candidate) (+ available 1e-7))
                        (loop (cdr words) candidate result)
                        (loop (cdr words) (car words) (cons current result)))]))]))
  (define lines (append-map wrap-line (regexp-split #rx"\n" text)))
  (define pictures (map (lambda (s) (if (string=? s "")
                                      (let ([m (run "M")])
                                        (p:blank 0 (p:pict-height m) (p:pict-ascent m) (p:pict-descent m)))
                                      (run s))) lines))
  (define line-height (apply max (map p:pict-height pictures)))
  (define stride (* line-height (text-style-line-spacing style)))
  (define w (apply max (map p:pict-width pictures)))
  (define h (+ line-height (* (sub1 (length pictures)) stride)))
  (define alignment (or align (text-style-line-alignment style)))
  (define paragraph
    (for/fold ([base (p:blank w h (p:pict-ascent (car pictures))
                             (p:pict-descent (last pictures)))])
              ([picture (in-list pictures)] [i (in-naturals)])
      (p:pin-over base
                  (case alignment [(center) (/ (- w (p:pict-width picture)) 2)]
                        [(right) (- w (p:pict-width picture))] [else 0])
                  (* i stride) picture)))
  (define treated
    (parameterize ([current-render-color-context (make-render-color-context (theme-value-colors theme))])
      (apply-text-treatment-to-pict paragraph treatment (text-style-font-size style) measurement-camera)))
  (define frozen (capture-colors treated (theme-value-colors theme)))
  (asset 'pict frozen (/ (p:pict-width frozen) measure-scale)
         (/ (p:pict-height frozen) measure-scale) (/ (p:pict-ascent frozen) measure-scale)
         0 'end (hash)
         (list 'text text role lines alignment (text-style->datum style)
               (color-theme-fingerprint (theme-value-colors theme)))
         (hash 'role role 'font-size (text-style-font-size style)
               'font-face (text-style-font-face style) 'lines lines)))
(define (pict-asset picture identity)
  (unless (p:pict? picture) (raise-argument-error 'pict-content "pict or factory returning pict" picture))
  (define w (/ (p:pict-width picture) measure-scale))
  (define h (/ (p:pict-height picture) measure-scale))
  (unless (and (nonnegative-number? w) (nonnegative-number? h))
    (slides-error 'invalid-pict '() "pict must have finite nonnegative dimensions"))
  (asset 'pict picture w h (/ (p:pict-ascent picture) measure-scale) 0 'end (hash) identity (hash)))
(define (asset-pict a t)
  (case (asset-kind a)
    [(pict) (asset-value a)]
    [else (slides-error 'native-adapter-required '() "native asset needs the optional native adapter")]))
