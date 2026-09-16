#lang racket/base
(require racket/list "data.rkt" "check.rkt" "appearance.rkt" "layout.rkt")
(provide arrange-slide slide-safe-box)

(define (slide-safe-box s format theme subtitles)
  (define mx (theme-spacing theme 'safe-x)) (define my (theme-spacing theme 'safe-y))
  (define foot (if (hash-has-key? (slide-value-slots s) 'footer)
                   (+ (theme-spacing theme 'footer-height) (theme-spacing theme 'section-gap)) 0))
  (define w (- (format-value-width format) (* 2 mx)))
  (define h (- (format-value-height format) (* 2 my) subtitles foot))
  (unless (and (> w 0) (> h 0)) (slides-error 'empty-safe-area (list (slide-value-id s)) "margins and subtitle band leave no content area"))
  (box-value mx my w h))
(define (arrange-slide s format theme subtitles measure)
  ;; measure : slot-name available-width -> (values intrinsic-width height)
  (define safe (slide-safe-box s format theme subtitles))
  (define x (box-value-x safe)) (define y (box-value-y safe))
  (define w (box-value-width safe)) (define h (box-value-height safe))
  (define gap (theme-spacing theme 'section-gap))
  (define column-gap (theme-spacing theme 'column-gap))
  (define present (slide-value-slots s))
  (define out (make-hash))
  (define (has? name) (hash-has-key? present name))
  (define (height name width)
    (if (has? name) (let-values ([(mw mh) (measure name width)]) mh) 0))
  (define (put name x y w h [align 'left] [valign 'top])
    (when (has? name)
      (unless (and (nonnegative-number? w) (nonnegative-number? h))
        (slides-error 'layout-overflow (list (slide-value-id s) name) "layout has negative or invalid available size" w h))
      (hash-set! out name (placement (box-value x y w h) align valign))))
  (define (heading)
    (define th (if (has? 'title) (height 'title w) 0))
    (put 'title x y w th)
    (values (+ y th (if (has? 'title) gap 0)) (- h th (if (has? 'title) gap 0))))
  (define l (slide-value-layout s))
  (cond
    [(eq? (layout-value-wide l) 'builtin)
     (define portrait? (< (format-value-width format) (format-value-height format)))
     (case (layout-value-id l)
       [(title section)
        (define th (height 'title w)) (define sh (height 'subtitle w))
        (define total (+ th sh (if (has? 'subtitle) gap 0)))
        (define top (+ y (/ (- h total) 2)))
        (when (> total h) (slides-error 'layout-overflow (list (slide-value-id s) 'title) "title card exceeds its safe area"))
        (put 'title x top w th 'center 'center)
        (put 'subtitle x (+ top th gap) w sh 'center 'center)]
       [(title+body)
        (define-values (cy ch) (heading)) (put 'body x cy w ch)]
       [(title+two-column title+figure)
        (define-values (cy ch) (heading))
        (define figure? (eq? (layout-value-id l) 'title+figure))
        (cond [(and figure? (not (has? 'body))) (put 'figure x cy w ch 'center 'center)]
              [portrait?
               (define a (if figure? 'body 'left)) (define b (if figure? 'figure 'right))
               (cond
                 [figure?
                  ;; Explanatory text takes only its natural height (up to a
                  ;; modest cap); the figure owns the remaining portrait area.
                  (define ah (min (* 0.38 (- ch gap)) (height a w)))
                  (put a x cy w ah)
                  (put b x (+ cy ah gap) w (- ch ah gap) 'center 'center)]
                 [else
                  ;; Two text columns become a compact vertical stack in
                  ;; portrait. Splitting the complete remaining height 50/50
                  ;; made short lists look unrelated and several screens apart.
                  (define ah (height a w))
                  (define bh (height b w))
                  (define total (+ ah gap bh))
                  (when (> total (+ ch 1e-8))
                    (slides-error 'layout-overflow (list (slide-value-id s) 'title+two-column)
                                  "stacked portrait columns exceed the available height"
                                  (hash 'required-height total 'available-height ch)))
                  (put a x cy w ah)
                  (put b x (+ cy ah gap) w bh)])]
              [else
               (define left-width (* (if figure? 0.37 0.5) (- w column-gap)))
               (put (if figure? 'body 'left) x cy left-width ch)
               (put (if figure? 'figure 'right) (+ x left-width column-gap) cy (- w left-width column-gap) ch
                    (if figure? 'center 'left) (if figure? 'center 'top))])]
       [(figure+caption)
        (define caption-height (height 'caption w))
        (define cut (+ caption-height (if (has? 'caption) gap 0)))
        (put 'figure x y w (- h cut) 'center 'center)
        (put 'caption x (+ y h (- caption-height)) w caption-height 'center 'center)]
       [(figure-full)
        (define full-height (- (format-value-height format) subtitles
                               (if (has? 'footer) (+ (theme-spacing theme 'safe-y)
                                                     (theme-spacing theme 'footer-height) gap) 0)))
        (put 'figure 0 0 (format-value-width format) full-height 'center 'center)]
       [(equation-focus)
        ;; Treat the equation and its annotation as one centered rhetorical
        ;; unit.  The old layout centered the equation in almost the full frame
        ;; but pinned the annotation to the bottom safe edge, visually
        ;; disconnecting the question from the expression it describes.
        (define eh (height 'equation w))
        (define ah (height 'annotation w))
        (define total (+ eh ah (if (has? 'annotation) gap 0)))
        (when (> total (+ h 1e-8))
          (slides-error 'layout-overflow (list (slide-value-id s) 'equation-focus)
                        "equation and annotation exceed the available height"
                        (hash 'required-height total 'available-height h)))
        (define top (+ y (/ (- h total) 2)))
        (put 'equation x top w eh 'center 'center)
        (put 'annotation x (+ top eh (if (has? 'annotation) gap 0)) w ah 'center 'center)]
       [(equation+explanation)
        (define-values (cy ch) (heading))
        (if portrait?
            (begin (put 'equation x cy w (* 0.5 (- ch gap)) 'center 'center)
                   (put 'body x (+ cy (* 0.5 (- ch gap)) gap) w (* 0.5 (- ch gap))))
            (let ([ew (* 0.55 (- w column-gap))])
              (put 'equation x cy ew ch 'center 'center)
              (put 'body (+ x ew column-gap) cy (- w ew column-gap) ch 'left 'center)))]
       [(theorem)
        (define-values (cy ch) (heading))
        (define sh (height 'statement w))
        (put 'statement x cy w sh)
        (put 'body x (+ cy sh gap) w (- ch sh gap))]
       [(quote)
        (define qh (height 'quote w)) (define ah (height 'attribution w))
        (define total (+ qh ah (if (has? 'attribution) gap 0)))
        (when (> total h) (slides-error 'layout-overflow (list (slide-value-id s) 'quote) "quotation exceeds its safe area"))
        (define top (+ y (/ (- h total) 2)))
        (put 'quote x top w qh 'center 'center)
        (put 'attribution x (+ top qh gap) w ah 'right 'center)]
       [(blank) (put 'content x y w h)])]
    [else
     (define variant
       (case (format-value-id format)
         [(widescreen) (layout-value-wide l)]
         [(standard) (or (layout-value-standard l) (layout-value-wide l))]
         [(portrait) (layout-value-portrait l)]
         [else (and (eq? (layout-value-fallback l) 'wide) (layout-value-wide l))]))
     (unless variant (slides-error 'missing-layout-variant (list (layout-value-id l) (format-value-id format)) "custom layout has no variant for this format"))
     (define (intrinsic node width)
       (define pad (* 2 (layout-node-padding node)))
       (cond [(eq? (layout-node-kind node) 'region)
              (define-values (mw mh) (if (has? (layout-node-name node))
                                         (measure (layout-node-name node) (max 0 (- width pad)))
                                         (values 0 0)))
              (values (+ pad mw) (+ pad mh))]
             [else
              (define children (layout-node-children node))
              (define gap (theme-spacing theme (layout-node-gap node)))
              (define child-width (if (and (eq? (layout-node-kind node) 'hbox) (pair? children))
                                      (/ (max 0 (- width pad (* gap (sub1 (length children))))) (length children))
                                      (max 0 (- width pad))))
              (define dims
                (for/list ([child (in-list children)])
                  (call-with-values (lambda () (intrinsic child child-width)) cons)))
              (define space (* gap (max 0 (sub1 (length children)))))
              (if (eq? (layout-node-kind node) 'hbox)
                  (values (+ pad space (apply + (map car dims))) (+ pad (apply max 0 (map cdr dims))))
                  (values (+ pad (apply max 0 (map car dims))) (+ pad space (apply + (map cdr dims)))))]))
     (define (walk node rectangle)
       (define padding (layout-node-padding node))
       (define rx (+ (box-value-x rectangle) padding)) (define ry (+ (box-value-y rectangle) padding))
       (define rw (- (box-value-width rectangle) (* 2 padding)))
       (define rh (- (box-value-height rectangle) (* 2 padding)))
       (when (or (< rw 0) (< rh 0)) (slides-error 'layout-padding (list (layout-value-id l)) "padding exceeds region size"))
       (cond [(eq? (layout-node-kind node) 'region)
              (put (layout-node-name node) rx ry rw rh (layout-node-align node) (layout-node-valign node))]
             [else
              (define children (layout-node-children node))
              (define horizontal? (eq? (layout-node-kind node) 'hbox))
              (define gap (theme-spacing theme (layout-node-gap node)))
              (define total (- (if horizontal? rw rh) (* gap (max 0 (sub1 (length children))))))
              (define bases
                (for/list ([child (in-list children)])
                  (define natural
                    (if (eq? (layout-node-basis child) 'content)
                        (let-values ([(mw mh) (intrinsic child rw)]) (if horizontal? mw mh))
                        (layout-node-basis child)))
                  (min (layout-node-maximum child) (max (layout-node-minimum child) natural))))
              (when (< total (- (apply + bases) 1e-8))
                (slides-error 'unsatisfiable-layout (list (layout-value-id l)) "basis sizes and gaps exceed available space"))
              ;; Bounded water filling honors maxima while redistributing spare
              ;; space among the remaining growing children. No search ordering.
              (define sizes (list->vector bases))
              (let fill ([left (- total (apply + bases))])
                (define eligible
                  (for/list ([child (in-list children)] [i (in-naturals)]
                             #:when (and (> (layout-node-grow child) 0)
                                         (< (vector-ref sizes i) (layout-node-maximum child)))) i))
                (when (and (> left 1e-8) (pair? eligible))
                  (define weight (for/sum ([i (in-list eligible)]) (layout-node-grow (list-ref children i))))
                  (define used
                    (for/sum ([i (in-list eligible)])
                      (define child (list-ref children i))
                      (define delta (min (- (layout-node-maximum child) (vector-ref sizes i))
                                         (* left (/ (layout-node-grow child) weight))))
                      (vector-set! sizes i (+ (vector-ref sizes i) delta)) delta))
                  (when (> used 1e-8) (fill (- left used)))))
              (for/fold ([offset 0]) ([child (in-list children)] [size (in-vector sizes)])
                (walk child (if horizontal? (box-value (+ rx offset) ry size rh)
                                (box-value rx (+ ry offset) rw size)))
                (+ offset size gap))]))
     (walk variant safe)])
  (when (has? 'footer)
    (put 'footer (theme-spacing theme 'safe-x)
         (- (format-value-height format) (theme-spacing theme 'safe-y) subtitles (theme-spacing theme 'footer-height))
         w (theme-spacing theme 'footer-height) 'left 'center))
  (values (make-immutable-hash (hash->list out)) safe))
