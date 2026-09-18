#lang racket/base
(require racket/class
         pict
         racket/draw
         racket/path)
(provide pict->svg-file pict->pdf-file pict->png-file pict->manual-files!)

(define (pict-natural-width p)
  (inexact->exact (ceiling (max 1 (pict-width p)))))
(define (pict-natural-height p)
  (inexact->exact (ceiling (max 1 (pict-height p)))))

(define (draw-pict/at-origin p dc)
  (send dc set-smoothing 'smoothed)
  (draw-pict p dc 0 0))

(define (pict->svg-file p out)
  (define w (pict-natural-width p))
  (define h (pict-natural-height p))
  (define dc (new svg-dc% [width w] [height h] [output out] [exists 'replace]))
  (send dc start-doc "animate-manual")
  (send dc start-page)
  (draw-pict/at-origin p dc)
  (send dc end-page)
  (send dc end-doc))

(define (pict->pdf-file p out)
  (define w (pict-natural-width p))
  (define h (pict-natural-height p))
  (define dc (new pdf-dc% [width w] [height h] [output out] [interactive #f] [as-eps #f]))
  (send dc start-doc "animate-manual")
  (send dc start-page)
  (draw-pict/at-origin p dc)
  (send dc end-page)
  (send dc end-doc))

(define (pict->png-file p out)
  (define bm (pict->bitmap p 'smoothed))
  (unless (send bm save-file out 'png)
    (error 'pict->png-file "could not write PNG" out)))

(define (base-path out)
  (let ([p (if (path? out) out (string->path out))])
    (if (path-get-extension p)
        (path-replace-extension p #"")
        p)))

(define (pict->manual-files! p out)
  (define b (base-path out))
  (define s (string->path (string-append (path->string b) ".svg")))
  (define f (string->path (string-append (path->string b) ".pdf")))
  (define n (string->path (string-append (path->string b) ".png")))
  (pict->svg-file p s)
  (pict->pdf-file p f)
  (pict->png-file p n)
  (values s f n))
