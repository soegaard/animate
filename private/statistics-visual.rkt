#lang racket/base

;; Immutable statistical/probability diagrams. These are ordinary Visual groups
;; whose children are explicitly named for the usual nested scene operations.

(require racket/list
         "geometry.rkt"
         "group-visual.rkt"
         "text-visual.rkt"
         "visual-model.rkt")

(provide bar-chart bar-chart-bar-id bar-chart-bar-path histogram
         stacked-bar-chart stacked-bar-id stacked-bar-segment-id
         stacked-bar-path stacked-bar-segment-path
         sample-space sample-space-cell-id sample-space-cell-path
         probability-branch probability-branch? probability-branch-id
         probability-branch-label probability-branch-probability
         probability-branch-children probability-tree probability-tree-node-path
         box-plot box-plot-summary box-plot-summary? box-plot-summary-minimum
         box-plot-summary-lower-quartile box-plot-summary-median
         box-plot-summary-upper-quartile box-plot-summary-maximum
         error-bar-point error-bar-point? error-bar-point-x error-bar-point-y
         error-bar-point-error error-bars error-bar-path)

(define palette '("cornflowerblue" "coral" "mediumseagreen" "goldenrod"
                  "mediumpurple" "darkturquoise"))
(define (iid prefix n) (string->symbol (format "~a-~a" prefix n)))
(define (positive who name value)
  (unless (and (finite-real? value) (positive? value))
    (raise-arguments-error who "positive finite real" name value)))
(define (nonnegative who name value)
  (unless (and (finite-real? value) (>= value 0))
    (raise-arguments-error who "nonnegative finite real" name value)))
(define (root-id who id) (unless (symbol? id) (raise-argument-error who "symbol?" id)))
(define (checked-values who values)
  (unless (and (list? values) (pair? values)) (raise-argument-error who "nonempty list" values))
  (for ([value (in-list values)]) (nonnegative who "value" value)))
(define (check-labels who labels n)
  (when (and labels (not (and (list? labels) (= (length labels) n) (andmap string? labels))))
    (raise-argument-error who "#f or a list of one string per value" labels)))
(define (color-at colors n) (list-ref colors (modulo n (length colors))))

(define (bar-chart-bar-id index) (iid "bar" index))
(define (bar-chart-bar-path id index) (list id 'bars (bar-chart-bar-id index)))

;; Values are nonnegative and measured upward from the local y=0 baseline.
(define (bar-chart values #:id id #:labels [labels #f] #:center [center origin]
                   #:width [width 6] #:height [height 3] #:maximum [maximum #f]
                   #:fill [fill "cornflowerblue"] #:stroke [stroke "navy"]
                   #:stroke-width [stroke-width 2] #:value-labels? [value-labels? #t])
  (root-id 'bar-chart id) (checked-values 'bar-chart values) (check-labels 'bar-chart labels (length values))
  (positive 'bar-chart "width" width) (positive 'bar-chart "height" height)
  (nonnegative 'bar-chart "stroke-width" stroke-width)
  (unless (vec2? center) (raise-argument-error 'bar-chart "vec2?" center))
  (unless (boolean? value-labels?) (raise-argument-error 'bar-chart "boolean?" value-labels?))
  (define top (or maximum (max 1 (apply max values)))) (positive 'bar-chart "maximum" top)
  (define slot (/ width (length values)))
  (define x-at (lambda (i) (+ (- (/ width 2)) (* (- i 1/2) slot))))
  (define bars
    (for/list ([value (in-list values)] [i (in-naturals 1)])
      (define h (* height (/ value top)))
      (rectangle #:id (bar-chart-bar-id i) #:center (vec2 (x-at i) (/ h 2))
                 #:width (* 3/4 slot) #:height (max h 1/1000)
                 #:fill fill #:stroke stroke #:stroke-width stroke-width)))
  (define captions
    (append
     (if labels (for/list ([label (in-list labels)] [i (in-naturals 1)])
                  (plain-text label #:id (iid "label" i) #:center (vec2 (x-at i) -1/4)
                              #:font-size 1/5 #:font-family 'swiss #:color "midnightblue")) '())
     (if value-labels? (for/list ([value (in-list values)] [i (in-naturals 1)])
                         (plain-text (number->string value) #:id (iid "value" i)
                                     #:center (vec2 (x-at i) (+ (* height (/ value top)) 1/6))
                                     #:font-size 1/6 #:font-family 'modern #:color "midnightblue")) '())))
  (group (list (line (vec2 (- (/ width 2)) 0) (vec2 (/ width 2) 0) #:id 'baseline #:stroke stroke #:stroke-width stroke-width)
               (group bars #:id 'bars) (group captions #:id 'labels)) #:id id #:center center))

(define (histogram samples #:id id #:bins [bins 8] #:range [range #f]
                   #:center [center origin] #:width [width 6] #:height [height 3]
                   #:fill [fill "cornflowerblue"] #:stroke [stroke "navy"])
  (unless (and (list? samples) (pair? samples) (andmap finite-real? samples))
    (raise-argument-error 'histogram "nonempty list of finite reals" samples))
  (unless (and (exact-integer? bins) (positive? bins))
    (raise-argument-error 'histogram "positive exact integer" bins))
  (define-values (lo hi)
    (if range
        (begin (unless (and (pair? range) (finite-real? (car range)) (finite-real? (cdr range)) (< (car range) (cdr range)))
                 (raise-argument-error 'histogram "increasing pair of finite reals" range))
               (values (car range) (cdr range)))
        (let ([a (apply min samples)] [b (apply max samples)])
          (if (= a b) (values (- a 1/2) (+ b 1/2)) (values a b)))))
  (define step (/ (- hi lo) bins)) (define counts (make-vector bins 0))
  (for ([x (in-list samples)] #:when (<= lo x hi))
    (define i (min (sub1 bins) (max 0 (inexact->exact (floor (/ (- x lo) step))))))
    (vector-set! counts i (add1 (vector-ref counts i))))
  (bar-chart (vector->list counts) #:id id #:center center #:width width #:height height
             #:fill fill #:stroke stroke #:value-labels? #f))

(define (stacked-bar-id index) (iid "bar" index))
(define (stacked-bar-segment-id index) (iid "segment" index))
(define (stacked-bar-path id index) (list id 'bars (stacked-bar-id index)))
(define (stacked-bar-segment-path id bar segment)
  (append (stacked-bar-path id bar) (list (stacked-bar-segment-id segment))))

(define (stacked-bar-chart rows #:id id #:center [center origin] #:width [width 6] #:height [height 3]
                           #:maximum [maximum #f] #:colors [colors palette]
                           #:stroke [stroke "navy"] #:stroke-width [stroke-width 1])
  (root-id 'stacked-bar-chart id)
  (unless (and (list? rows) (pair? rows) (andmap (lambda (r) (and (list? r) (pair? r))) rows))
    (raise-argument-error 'stacked-bar-chart "nonempty list of nonempty rows" rows))
  (define pieces (length (car rows)))
  (unless (andmap (lambda (r) (= (length r) pieces)) rows)
    (raise-argument-error 'stacked-bar-chart "rows with equal lengths" rows))
  (for ([row (in-list rows)]) (checked-values 'stacked-bar-chart row))
  (unless (and (list? colors) (pair? colors)) (raise-argument-error 'stacked-bar-chart "nonempty list of colors" colors))
  (positive 'stacked-bar-chart "width" width) (positive 'stacked-bar-chart "height" height)
  (nonnegative 'stacked-bar-chart "stroke-width" stroke-width)
  (define max-total (or maximum (max 1 (apply max (map (lambda (r) (apply + r)) rows)))))
  (positive 'stacked-bar-chart "maximum" max-total)
  (define slot (/ width (length rows)))
  (define bars
    (for/list ([row (in-list rows)] [bar-index (in-naturals 1)])
      (define x (+ (- (/ width 2)) (* (- bar-index 1/2) slot)))
      (define-values (segments _)
        (for/fold ([out '()] [bottom 0]) ([value (in-list row)] [segment-index (in-naturals 1)])
          (define h (* height (/ value max-total)))
          (values (append out (list (rectangle #:id (stacked-bar-segment-id segment-index)
                                               #:center (vec2 x (+ bottom (/ h 2)))
                                               #:width (* 3/4 slot) #:height (max h 1/1000)
                                               #:fill (color-at colors (sub1 segment-index))
                                               #:stroke stroke #:stroke-width stroke-width)))
                  (+ bottom h))))
      (group segments #:id (stacked-bar-id bar-index))))
  (group (list (line (vec2 (- (/ width 2)) 0) (vec2 (/ width 2) 0) #:id 'baseline #:stroke stroke #:stroke-width stroke-width)
               (group bars #:id 'bars)) #:id id #:center center))

(define (sample-space-cell-id row col) (string->symbol (format "cell-~a-~a" row col)))
(define (sample-space-cell-path id row col) (list id 'cells (sample-space-cell-id row col)))

;; The matrix supplies outcome weights; equal cells make the finite outcome
;; structure readable, while labels retain the author supplied probabilities.
(define (sample-space rows #:id id #:center [center origin] #:width [width 5] #:height [height 3]
                      #:colors [colors palette] #:stroke [stroke "white"])
  (root-id 'sample-space id)
  (unless (and (list? rows) (pair? rows) (andmap (lambda (r) (and (list? r) (pair? r))) rows))
    (raise-argument-error 'sample-space "nonempty rectangular list of rows" rows))
  (define cols (length (car rows)))
  (unless (andmap (lambda (r) (= (length r) cols)) rows)
    (raise-argument-error 'sample-space "rectangular list of rows" rows))
  (for ([row (in-list rows)]) (checked-values 'sample-space row))
  (unless (and (list? colors) (pair? colors)) (raise-argument-error 'sample-space "nonempty list of colors" colors))
  (positive 'sample-space "width" width) (positive 'sample-space "height" height)
  (define cw (/ width cols)) (define ch (/ height (length rows)))
  (define cells
    (append-map
     (lambda (row row-index)
       (for/list ([value (in-list row)] [col-index (in-naturals 1)])
         (define x (+ (- (/ width 2)) (* (- col-index 1/2) cw)))
         (define y (+ (/ height 2) (- (* (- row-index 1/2) ch))))
         (group (list (rectangle #:id 'body #:center (vec2 x y) #:width cw #:height ch
                                #:fill (color-at colors (+ (* (sub1 row-index) cols) (sub1 col-index)))
                                #:stroke stroke #:stroke-width 1)
                      (plain-text (number->string value) #:id 'probability #:center (vec2 x y)
                                  #:font-size 1/5 #:font-family 'modern #:color "black"))
                #:id (sample-space-cell-id row-index col-index))))
     rows (range 1 (add1 (length rows)))))
  (group (list (group cells #:id 'cells)) #:id id #:center center))

(struct probability-branch (id label probability children) #:transparent
  #:guard (lambda (id label probability children who)
            (root-id who id) (unless (string? label) (raise-argument-error who "string?" label))
            (nonnegative who "probability" probability)
            (unless (and (list? children) (andmap probability-branch? children))
              (raise-argument-error who "list of probability-branch?" children))
            (values id label probability children)))
(define (probability-tree-node-path id branch-id) (list id 'nodes branch-id))
(define (tree-all branches) (append-map (lambda (b) (cons b (tree-all (probability-branch-children b)))) branches))
(define (tree-leaves branches) (append-map (lambda (b) (if (null? (probability-branch-children b)) (list b) (tree-leaves (probability-branch-children b)))) branches))

(define (probability-tree branches #:id id #:center [center origin] #:width [width 6] #:level-gap [gap 1]
                          #:node-radius [radius 1/6] #:stroke [stroke "slategray"] #:node-fill [fill "aliceblue"])
  (root-id 'probability-tree id)
  (unless (and (list? branches) (pair? branches) (andmap probability-branch? branches))
    (raise-argument-error 'probability-tree "nonempty list of probability-branch?" branches))
  (positive 'probability-tree "width" width) (positive 'probability-tree "level-gap" gap) (positive 'probability-tree "node-radius" radius)
  (define all (tree-all branches)) (define ids (map probability-branch-id all))
  (unless (= (length ids) (length (remove-duplicates ids))) (raise-argument-error 'probability-tree "unique branch ids" branches))
  (define leaves (tree-leaves branches)) (define leaf-index 0) (define positions (make-hash)) (define depths (make-hash))
  (define (place branch depth)
    (hash-set! depths branch depth)
    (define children (probability-branch-children branch))
    (define x (if (null? children)
                  (let ([answer (+ (- (/ width 2)) (* (+ leaf-index 1/2) (/ width (length leaves))))]) (set! leaf-index (add1 leaf-index)) answer)
                  (/ (apply + (map (lambda (c) (vec2-x (place c (add1 depth)))) children)) (length children))))
    (define at (vec2 x (* -1 depth gap))) (hash-set! positions branch at) at)
  (for ([branch (in-list branches)]) (place branch 1))
  (define edge-visuals
    (append-map (lambda (branch)
                  (append-map (lambda (child)
                                (define from (hash-ref positions branch)) (define to (hash-ref positions child))
                                (list (group (list (line from to #:id 'line #:stroke stroke #:stroke-width 2)
                                                   (plain-text (number->string (probability-branch-probability child)) #:id 'probability
                                                               #:center (vec2-lerp from to 1/2) #:font-size 1/6 #:font-family 'modern #:color "darkred"))
                                             #:id (string->symbol (format "edge-~a" (probability-branch-id child))))))
                              (probability-branch-children branch))) all))
  (define node-visuals
    (for/list ([branch (in-list all)])
      (define at (hash-ref positions branch))
      (group (list (circle #:id 'body #:center at #:radius radius #:fill fill #:stroke stroke #:stroke-width 2)
                   (plain-text (probability-branch-label branch) #:id 'label #:center (vec2+ at (vec2 0 -2/5))
                               #:font-size 1/6 #:font-family 'swiss #:color "midnightblue"))
             #:id (probability-branch-id branch))))
  (group (list (group edge-visuals #:id 'edges) (group node-visuals #:id 'nodes)) #:id id #:center center))

(struct box-plot-summary (minimum lower-quartile median upper-quartile maximum) #:transparent)
(define (quantile sorted fraction)
  (define p (* fraction (sub1 (length sorted)))) (define lo (inexact->exact (floor p))) (define hi (inexact->exact (ceiling p)))
  (+ (list-ref sorted lo) (* (- p lo) (- (list-ref sorted hi) (list-ref sorted lo)))))
(define (box-plot values #:id id #:center [center origin] #:width [width 5] #:height [height 3/4]
                  #:stroke [stroke "navy"] #:fill [fill "aliceblue"] #:stroke-width [stroke-width 2])
  (root-id 'box-plot id) (unless (and (list? values) (>= (length values) 2) (andmap finite-real? values)) (raise-argument-error 'box-plot "list of at least two finite reals" values))
  (positive 'box-plot "width" width) (positive 'box-plot "height" height) (nonnegative 'box-plot "stroke-width" stroke-width)
  (define s (sort values <)) (define stat (box-plot-summary (car s) (quantile s 1/4) (quantile s 1/2) (quantile s 3/4) (last s)))
  (define lo (box-plot-summary-minimum stat)) (define hi (box-plot-summary-maximum stat)) (define span (max 1/1000 (- hi lo)))
  (define (x v) (+ (- (/ width 2)) (* width (/ (- v lo) span))))
  (define q1 (x (box-plot-summary-lower-quartile stat))) (define med (x (box-plot-summary-median stat))) (define q3 (x (box-plot-summary-upper-quartile stat)))
  (group (list (line (vec2 (x lo) 0) (vec2 q1 0) #:id 'left-whisker #:stroke stroke #:stroke-width stroke-width)
               (line (vec2 q3 0) (vec2 (x hi) 0) #:id 'right-whisker #:stroke stroke #:stroke-width stroke-width)
               (rectangle #:id 'quartile-box #:center (vec2 (/ (+ q1 q3) 2) 0) #:width (max 1/1000 (- q3 q1)) #:height height #:fill fill #:stroke stroke #:stroke-width stroke-width)
               (line (vec2 med (- (/ height 2))) (vec2 med (/ height 2)) #:id 'median #:stroke "darkred" #:stroke-width stroke-width)) #:id id #:center center))

(struct error-bar-point (x y error) #:transparent
  #:guard (lambda (x y error who) (unless (and (finite-real? x) (finite-real? y)) (raise-argument-error who "finite coordinates" (list x y))) (nonnegative who "error" error) (values x y error)))
(define (error-bar-path id index) (list id 'bars (iid "bar" index)))
(define (error-bars points #:id id #:center [center origin] #:cap-width [cap 1/5]
                    #:stroke [stroke "darkred"] #:stroke-width [stroke-width 2] #:marker-fill [marker-fill "white"])
  (root-id 'error-bars id) (unless (and (list? points) (pair? points) (andmap error-bar-point? points)) (raise-argument-error 'error-bars "nonempty list of error-bar-point?" points))
  (positive 'error-bars "cap-width" cap) (nonnegative 'error-bars "stroke-width" stroke-width)
  (group (list (group (for/list ([point (in-list points)] [i (in-naturals 1)])
                        (define x (error-bar-point-x point)) (define y (error-bar-point-y point)) (define e (error-bar-point-error point))
                        (group (list (line (vec2 x (- y e)) (vec2 x (+ y e)) #:id 'stem #:stroke stroke #:stroke-width stroke-width)
                                     (line (vec2 (- x cap) (- y e)) (vec2 (+ x cap) (- y e)) #:id 'lower-cap #:stroke stroke #:stroke-width stroke-width)
                                     (line (vec2 (- x cap) (+ y e)) (vec2 (+ x cap) (+ y e)) #:id 'upper-cap #:stroke stroke #:stroke-width stroke-width)
                                     (circle #:id 'point #:center (vec2 x y) #:radius 1/10 #:fill marker-fill #:stroke stroke #:stroke-width stroke-width)) #:id (iid "bar" i))) #:id 'bars)) #:id id #:center center))
