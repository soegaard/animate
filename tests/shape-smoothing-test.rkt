#lang racket/base

(require racket/class
         (only-in rackunit test-case check-equal? check-true check-exn)
         (only-in pict dc draw-pict pict->bitmap pict-width pict-height
                  pict-ascent pict-descent filled-ellipse)
         (only-in racket/draw bitmap-dc% make-bitmap)
         (only-in "../main.rkt" make-scene make-camera scene-add scene-play
                  scene->pict scene-frame->bitmap circle rectangle group
                  move-to vec2)
         "../private/shape-smoothing.rkt")

(define (pixels bitmap)
  (define w (send bitmap get-width))
  (define h (send bitmap get-height))
  (define result (make-bytes (* w h 4)))
  (send bitmap get-argb-pixels 0 0 w h result)
  result)

(define (test-dc)
  (new bitmap-dc% [bitmap (make-bitmap 140 110)]))

(module+ test
  (test-case "smoothing is installed during drawing and the caller mode is restored"
    (define seen #f)
    (define source
      (dc (lambda (target _x _y) (set! seen (send target get-smoothing)))
          31 23 17 6))
    (define wrapped (shape-pict-with-smoothed-drawing source))
    (for ([mode '(unsmoothed aligned smoothed)])
      (define target (test-dc))
      (send target set-smoothing mode)
      (send target set-origin 1/4 3/4)
      (define transformation (send target get-transformation))
      (set! seen #f)
      (draw-pict wrapped target 1/3 2/3)
      (check-equal? seen 'smoothed)
      (check-equal? (send target get-smoothing) mode)
      (check-equal? (send target get-transformation) transformation))
    (check-equal? (list (pict-width wrapped) (pict-height wrapped)
                        (pict-ascent wrapped) (pict-descent wrapped))
                  (list (pict-width source) (pict-height source)
                        (pict-ascent source) (pict-descent source))))

  (test-case "the caller mode is restored after a draw exception"
    ;; Pict validates a dc callback at construction time; arm failure only later.
    (define fail? #f)
    (define source
      (dc (lambda (_target _x _y)
            (when fail? (error 'shape-smoothing-test "deliberate draw failure")))
          20 20))
    (define wrapped (shape-pict-with-smoothed-drawing source))
    (define target (test-dc))
    (send target set-smoothing 'aligned)
    (set! fail? #t)
    (check-exn exn:fail? (lambda () (draw-pict wrapped target 0 0)))
    (check-equal? (send target get-smoothing) 'aligned))

  (test-case "the wrapper changes no pixels when the caller already uses smoothed"
    (define source
      (filled-ellipse 640/7 640/7 #:color "tomato"
                      #:border-color "firebrick" #:border-width 2))
    (check-equal?
     (pixels (pict->bitmap (shape-pict-with-smoothed-drawing source) 'smoothed))
     (pixels (pict->bitmap source 'smoothed))))

  (test-case "native filled and unfilled shapes do not inherit coordinate snapping"
    (for* ([fill '("tomato" #f)] [width '(1 3/2 2 3)]
           [size '((160 90) (640 360) (1280 720))])
      (define camera (make-camera #:width (car size) #:height (cadr size)
                                  #:world-width 14))
      (define sc
        (scene-add (make-scene #:camera camera)
                   (circle #:id 'dot #:center (vec2 -2/7 1/11)
                           #:radius 1/2 #:fill fill #:stroke "firebrick"
                           #:stroke-width width)
                   (rectangle #:id 'box #:center (vec2 2 -1/13)
                              #:width 1 #:height 3/4 #:fill fill
                              #:stroke "firebrick" #:stroke-width width)))
      (define p (scene->pict sc 0))
      (define expected (pixels (pict->bitmap p 'smoothed)))
      (for ([mode '(aligned unsmoothed)])
        (check-equal? (pixels (pict->bitmap p mode)) expected))))

  (test-case "grouped animated circles retain the normal frame-rendering result"
    (define sc
      (scene-play
       (scene-add (make-scene)
                  (group
                   (list (circle #:id 'dot #:center (vec2 -1/7 1/11)
                                 #:radius 1/2 #:fill "tomato" #:stroke "firebrick"))
                   #:id 'pair #:center (vec2 2/9 0)))
       (move-to '(pair dot) (vec2 1 1)) #:duration 1))
    (for ([index '(0 1 7 15 29)])
      (define p (scene->pict sc (/ index 30)))
      (check-equal? (pixels (pict->bitmap p 'aligned))
                    (pixels (scene-frame->bitmap sc index #:fps 30))))))
