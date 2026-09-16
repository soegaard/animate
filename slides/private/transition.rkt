#lang racket/base

;; Pure transition geometry. Each frame is still a renderer-neutral snapshot;
;; both Pict and native Scene adapters receive the same transformed rectangles,
;; masks, colors, and opacity. No drawing, measurement, or asset work happens here.
(require racket/list "data.rkt" "check.rkt" "../../colors.rkt")
(provide transition-progress directional-bridge zoom-frame blend-frames fade-through-frame)

(define (transition-progress easing p)
  (define u (min 1 (max 0 p)))
  (case easing
    [(linear) u]
    [(smooth) (* u u (- 3 (* 2 u)))]
    [(ease-in) (* u u)]
    [(ease-out) (- 1 (* (- 1 u) (- 1 u)))]
    [(ease-in-out) (if (< u 1/2) (* 2 u u) (- 1 (* 2 (- 1 u) (- 1 u))))]
    [else (slides-error 'transition-easing (list easing) "unknown transition easing")]))

(define (canvas-box f)
  (box-value 0 0 (format-value-width (frame-value-format f))
                 (format-value-height (frame-value-format f))))
(define (intersect a b)
  (define x (max (box-value-x a) (box-value-x b)))
  (define y (max (box-value-y a) (box-value-y b)))
  (define r (min (+ (box-value-x a) (box-value-width a))
                 (+ (box-value-x b) (box-value-width b))))
  (define d (min (+ (box-value-y a) (box-value-height a))
                 (+ (box-value-y b) (box-value-height b))))
  (and (> r x) (> d y) (box-value x y (- r x) (- d y))))
(define (move-box b scale dx dy canvas)
  (define cx (/ (box-value-width canvas) 2))
  (define cy (/ (box-value-height canvas) 2))
  (box-value (+ cx dx (* scale (- (box-value-x b) cx)))
             (+ cy dy (* scale (- (box-value-y b) cy)))
             (* scale (box-value-width b)) (* scale (box-value-height b))))
(define (decoration-alpha d) (if (pair? (cddr d)) (caddr d) 1))
(define (fade-decorations ds weight)
  (for/list ([d (in-list ds)]) (list (car d) (cadr d) (* weight (decoration-alpha d)))))
(define (fade-leaves ls weight)
  (for/list ([l (in-list ls)])
    (struct-copy frame-leaf l [opacity (* weight (frame-leaf-opacity l))])))
(define (merge-slots a b)
  (for/fold ([h a]) ([(key value) (in-hash b)]) (hash-set h key value)))

;; Mask content AND decoration. Translation/scale carries any preexisting cover
;; crop with its object; the transition's viewport mask is intersected afterward.
(define (transform-frame f scale dx dy mask)
  (define canvas (canvas-box f))
  (define (move b) (move-box b scale dx dy canvas))
  (define limit (intersect canvas mask))
  (define leaves
    (filter values
      (for/list ([l (in-list (frame-value-leaves f))])
        (define clip (and limit
                          (if (frame-leaf-clip l)
                              (intersect limit (move (frame-leaf-clip l))) limit)))
        (and clip (struct-copy frame-leaf l [box (move (frame-leaf-box l))] [clip clip])))))
  (define decorations
    (filter values
      (for/list ([d (in-list (frame-value-decorations f))])
        (define visible (and limit (intersect limit (move (car d)))))
        (and visible (list visible (cadr d) (decoration-alpha d))))))
  (struct-copy frame-value f
    [leaves leaves] [decorations decorations]
    [slots (for/hash ([(key b) (in-hash (frame-value-slots f))]) (values key (move b)))]))

;; Direction names describe travel: 'left moves incoming material from the right.
;; In a wipe the boundary travels left, exposing the stationary destination from
;; its right edge. Source/destination masks partition the canvas; neither slide's
;; background can accidentally cover text belonging to the other slide.
(define (split-masks canvas direction p)
  (define w (box-value-width canvas)) (define h (box-value-height canvas))
  (case direction
    [(left)  (values (box-value 0 0 (* w (- 1 p)) h)
                    (box-value (* w (- 1 p)) 0 (* w p) h))]
    [(right) (values (box-value (* w p) 0 (* w (- 1 p)) h)
                    (box-value 0 0 (* w p) h))]
    [(up)    (values (box-value 0 0 w (* h (- 1 p)))
                    (box-value 0 (* h (- 1 p)) w (* h p)))]
    [(down)  (values (box-value 0 (* h p) w (* h (- 1 p)))
                    (box-value 0 0 w (* h p)))]))
(define (travel direction canvas)
  (case direction
    [(left) (values (- (box-value-width canvas)) 0)]
    [(right) (values (box-value-width canvas) 0)]
    [(up) (values 0 (- (box-value-height canvas)))]
    [(down) (values 0 (box-value-height canvas))]))
(define (directional-bridge from to effect direction p)
  (define canvas (canvas-box from))
  (define-values (source-mask destination-mask) (split-masks canvas direction p))
  (define-values (dx dy) (travel direction canvas))
  (define move-source? (memq effect '(push uncover)))
  (define move-destination? (memq effect '(push cover)))
  (define a (transform-frame from 1 (if move-source? (* p dx) 0)
                                     (if move-source? (* p dy) 0) source-mask))
  (define b (transform-frame to 1 (if move-destination? (* (- p 1) dx) 0)
                                   (if move-destination? (* (- p 1) dy) 0) destination-mask))
  (frame-value (frame-value-format from) (frame-value-background from)
               (append (frame-value-leaves a) (frame-value-leaves b))
               (merge-slots (frame-value-slots a) (frame-value-slots b))
               (frame-value-safe-box to)
               (append (list (list source-mask (frame-value-background from) 1))
                       (frame-value-decorations a)
                       (list (list destination-mask (frame-value-background to) 1))
                       (frame-value-decorations b))))

(define (zoom-frame f scale)
  (transform-frame f scale 0 0 (canvas-box f)))
(define (blend-frames from to p)
  (frame-value (frame-value-format from)
               (rgba-color-lerp (frame-value-background from) (frame-value-background to) p)
               (append (fade-leaves (frame-value-leaves from) (- 1 p))
                       (fade-leaves (frame-value-leaves to) p))
               (merge-slots (frame-value-slots from) (frame-value-slots to))
               (frame-value-safe-box to)
               (if (equal? (frame-value-decorations from) (frame-value-decorations to))
                   (frame-value-decorations from)
                   (append (fade-decorations (frame-value-decorations from) (- 1 p))
                           (fade-decorations (frame-value-decorations to) p)))))
(define (fade-through-frame from to color p)
  (define source-half? (< p 1/2))
  (define f (if source-half? from to))
  (define weight (if source-half? (- 1 (* 2 p)) (- (* 2 p) 1)))
  (struct-copy frame-value f
    [background (rgba-color-lerp color (frame-value-background f) weight)]
    [leaves (fade-leaves (frame-value-leaves f) weight)]
    [decorations (fade-decorations (frame-value-decorations f) weight)]))
