#lang racket/base
(require racket/class racket/list racket/match
         (only-in racket/draw make-pen make-brush)
         (prefix-in p: pict)
         "data.rkt" "check.rkt" "content.rkt" "text.rkt")
(provide frame->pict output-size asset->pict)
(define (output-size format supplied)
  (define size (or supplied (list (inexact->exact (round (* 80 (format-value-width format))))
                                  (inexact->exact (round (* 80 (format-value-height format)))))))
  (match size
    [(list (? exact-positive-integer? w) (? exact-positive-integer? h)) (values w h)]
    [_ (raise-argument-error 'slide->pict "(list positive-integer positive-integer) as #:size" supplied)]))
(define (asset->pict a t)
  (if (eq? (asset-kind a) 'pict) (asset-value a)
      ((native-operation 'native-asset->pict) a t)))
(define (draw-outline b color)
  (p:dc
   (lambda (dc x y)
     (define pen (send dc get-pen)) (define brush (send dc get-brush))
     (dynamic-wind
      void
      (lambda ()
        (send dc set-pen (make-pen #:color color #:width 1 #:style 'solid))
        (send dc set-brush (make-brush #:style 'transparent))
        (send dc draw-rectangle x y (* measure-scale (box-value-width b)) (* measure-scale (box-value-height b))))
      (lambda () (send dc set-pen pen) (send dc set-brush brush))))
   (* measure-scale (box-value-width b)) (* measure-scale (box-value-height b))))
(define (frame->pict f #:size [size #f] #:fit [fit 'error] #:debug [debug '()])
  (check-enum 'frame->pict fit '(error letterbox))
  (for ([d (in-list debug)]) (check-enum 'frame->pict d '(slots safe-area baselines)))
  (define format (frame-value-format f))
  (define fw (* measure-scale (format-value-width format)))
  (define fh (* measure-scale (format-value-height format)))
  (define color (color->draw (frame-value-background f)))
  (define initial (p:filled-rectangle fw fh #:draw-border? #f #:color color))
  (define decorated
    (for/fold ([p initial]) ([entry (in-list (frame-value-decorations f))])
      (define box (car entry))
      (p:pin-over p (* measure-scale (box-value-x box)) (* measure-scale (box-value-y box))
                  (p:cellophane
                   (p:filled-rectangle (* measure-scale (box-value-width box)) (* measure-scale (box-value-height box))
                                       #:draw-border? #f #:color (color->draw (cadr entry)))
                   (if (pair? (cddr entry)) (caddr entry) 1)))))
  (define composed
    (for/fold ([canvas decorated]) ([l (in-list (frame-value-leaves f))] #:when (> (frame-leaf-opacity l) 0))
      (define a (frame-leaf-asset l))
      (define picture (asset->pict a (frame-leaf-time l)))
      (define b (frame-leaf-box l))
      (define pulse (frame-leaf-scale l))
      (define w (* measure-scale pulse (box-value-width b)))
      (define h (* measure-scale pulse (box-value-height b)))
      (define x (* measure-scale (+ (box-value-x b) (* 0.5 (- 1 pulse) (box-value-width b)))))
      (define y (* measure-scale (+ (box-value-y b) (* 0.5 (- 1 pulse) (box-value-height b)))))
      (define painted
        (p:cellophane (p:scale picture (if (= (p:pict-width picture) 0) 1 (/ w (p:pict-width picture)))
                                      (if (= (p:pict-height picture) 0) 1 (/ h (p:pict-height picture))))
                      (frame-leaf-opacity l)))
      (cond [(frame-leaf-clip l)
             (define clip (frame-leaf-clip l))
             (define cx (* measure-scale (box-value-x clip))) (define cy (* measure-scale (box-value-y clip)))
             (p:pin-over canvas cx cy
                         (p:clip (p:pin-over (p:blank (* measure-scale (box-value-width clip)) (* measure-scale (box-value-height clip)))
                                             (- x cx) (- y cy) painted)))]
            [else (p:pin-over canvas x y painted)])))
  (define debugged
    (for/fold ([canvas composed]) ([b (in-list (append
                                               (if (memq 'safe-area debug) (list (frame-value-safe-box f)) '())
                                               (if (memq 'slots debug) (hash-values (frame-value-slots f)) '())))])
      (p:pin-over canvas (* measure-scale (box-value-x b)) (* measure-scale (box-value-y b))
                  (draw-outline b "magenta"))))
  (define with-baselines
    (if (not (memq 'baselines debug)) debugged
        (for/fold ([canvas debugged]) ([l (in-list (frame-value-leaves f))])
          (define a (frame-leaf-asset l)) (define b (frame-leaf-box l))
          (define ratio (if (= (asset-height a) 0) 1 (/ (box-value-height b) (asset-height a))))
          (p:pin-over canvas (* measure-scale (box-value-x b))
                      (* measure-scale (+ (box-value-y b) (* ratio (asset-baseline a))))
                      (p:colorize (p:filled-rectangle (* measure-scale (box-value-width b)) 1 #:draw-border? #f) "cyan")))))
  (define-values (ow oh) (output-size format size))
  (unless (or (eq? fit 'letterbox) (< (abs (- (/ ow oh) (/ fw fh))) 1e-8))
    (slides-error 'output-aspect '() "output size has a different aspect ratio; select a format or #:fit 'letterbox"))
  (define factor (min (/ ow fw) (/ oh fh)))
  (define fitted (p:scale (p:clip with-baselines) factor))
  (p:pin-over (p:filled-rectangle ow oh #:draw-border? #f #:color color)
              (/ (- ow (* fw factor)) 2) (/ (- oh (* fh factor)) 2) fitted))
