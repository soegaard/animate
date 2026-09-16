#lang racket/base
(require "private/data.rkt" "private/prepare.rkt" "private/sample.rkt" "private/draw.rkt"
         (only-in "private/text.rkt" content-color content-width content-height content-theme content-format))
(provide slide->pict storyboard->pict storyboard->picts
         content-color content-width content-height content-theme content-format)
(define (slide->pict source #:at [at #f] #:theme [theme #f] #:format [format #f]
                     #:size [size #f] #:fit [fit 'error] #:debug [debug '()])
  (define prepared (resolve-slide source #:theme theme #:format format))
  (frame->pict (sample-slide prepared at) #:size size #:fit fit #:debug debug))
(define (storyboard->pict source #:at [at 'end] #:size [size #f] #:fit [fit 'error] #:debug [debug '()])
  (frame->pict (sample-storyboard (resolve-storyboard source) at) #:size size #:fit fit #:debug debug))
(define (storyboard->picts source #:size [size #f] #:fit [fit 'error] #:debug [debug '()])
  (define prepared (resolve-storyboard source))
  (for/list ([shot (in-list (prepared-storyboard-value-shots prepared))])
    (slide->pict (prepared-shot-clip shot) #:size size #:fit fit #:debug debug)))
