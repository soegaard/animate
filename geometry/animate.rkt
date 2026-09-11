#lang racket/base

;; Public animate adapter. This is the only pure module that imports animate;
;; ../main.rkt and ../colors.rkt are public entry points of the containing repo.
;; All mathematical realization and label placement are frozen before playback.
(require racket/list (only-in racket/math pi)
         (prefix-in a: "../main.rkt")
         (prefix-in colors: "../colors.rkt")
         "core.rkt" "private/drawing.rkt")
(provide construction->scene geometry-timeline->scene geometry-timeline->visual
         geometry-timeline->camera geometry-style-color)

(define (vec p) (a:vec2 (point-x p) (point-y p)))
(define (paint-key channel suffix) (string->symbol (format "~a-~a" channel suffix)))
(define (key id suffix) (string->symbol (format "~a/~a" id suffix)))
(define (mix-number x y t) (+ x (* (- y x) t)))
(define (unit x) (max 0 (min 1 x)))
(define transparent (colors:rgba-color 0 0 0 0))

;; Native palette references remain unresolved until animate's render boundary.
;; No literal RGB copy of the animate palette is embedded in this package.
(define (geometry-style-color style channel)
  (define exact (hash-ref style (paint-key channel 'color)))
  (define color
    (cond [(eq? exact 'inherit)
           (colors:palette-color
            (string->symbol (format "~a-~a" (hash-ref style (paint-key channel 'family))
                                    (hash-ref style (paint-key channel 'variant)))))]
          [(not exact) transparent]
          [(symbol? exact)
           (case exact
             [(white) colors:white] [(black) colors:black]
             [(foreground background muted accent highlight axis grid surface)
              (colors:role-color exact)]
             [else (colors:palette-color exact)])]
          [else exact]))
  (unless (colors:color-spec? color)
    (geometry-error 'geometry-style-color "not an animate color specification: ~e" exact))
  color)

;; Native cubic circle arcs: at most pi/8 radians per segment. This avoids a
;; resolution-dependent polygonal appearance for ordinary solid circles.
(define (circle-path c progress)
  (define p (unit progress))
  (cond [(zero? p) a:empty-path-geometry]
        [else
         (define center (circle-center c))
         (define v (point- (circle-through c) center))
         (define theta (atan (point-y v) (point-x v)))
         (define radius (circle-radius c))
         (define count (max 1 (inexact->exact (ceiling (* 16 p)))))
         (define from (- theta (* pi p)))
         (define delta (/ (* 2 pi p) count))
         (define (at t) (point+ center (point (* radius (cos t)) (* radius (sin t)))))
         (define (derivative t) (point (* (- radius) (sin t)) (* radius (cos t))))
         (define segments
           (for/list ([i (in-range count)])
             (define u (+ from (* i delta)))
             (define w (+ u delta))
             (define factor (* 4/3 (tan (/ delta 4))))
             (a:cubic-bezier-path-segment
              (vec (point+ (at u) (point* (derivative u) factor)))
              (vec (point- (at w) (point* (derivative w) factor)))
              (vec (at w)))))
         (a:path-geometry (list (a:path-subpath (vec (at from)) segments (= p 1))))]))
(define (polylines-path polylines)
  (a:path-geometry
   (for/list ([points (in-list polylines)] #:when (>= (length points) 2))
     (a:path-subpath (vec (car points))
                     (map (lambda (p) (a:line-path-segment (vec p))) (cdr points)) #f))))
(define (curve-path value view progress pattern pixels)
  (cond [(and (circle? value) (eq? pattern 'solid)) (circle-path value progress)]
        [else
         (define points (curve-polyline value view progress))
         (define runs (dash-polylines points pattern (/ (geometry-view-width view) pixels)))
         (polylines-path (append-map (lambda (ps) (clipped-polylines ps view)) runs))]))

;; Four endpoints describe continuous normal/secondary and transient-highlight
;; composition. Numeric properties and native color expressions interpolate;
;; differing dash patterns cross-fade without an abrupt pattern change.
(define (style-weights appearance)
  (define s (unit (geometry-appearance-secondary appearance)))
  (define h (unit (geometry-appearance-highlight appearance)))
  (list (* (- 1 s) (- 1 h)) (* s (- 1 h)) (* (- 1 s) h) (* s h)))
(define (style-number styles weights property)
  (for/sum ([style (in-list styles)] [weight (in-list weights)]) (* weight (hash-ref style property))))
(define (style-color styles appearance channel)
  (define s (unit (geometry-appearance-secondary appearance)))
  (define h (unit (geometry-appearance-highlight appearance)))
  (define colors (map (lambda (style) (geometry-style-color style channel)) styles))
  (colors:color-mix
   (colors:color-mix (list-ref colors 0) (list-ref colors 1) s)
   (colors:color-mix (list-ref colors 2) (list-ref colors 3) s) h))

(define (make-frame-builder timeline pixels root-id captions? labels)
  (unless (and (geometry-timeline? timeline) (exact-positive-integer? pixels) (symbol? root-id))
    (geometry-error 'geometry-timeline->visual "invalid timeline, pixel width or root id"))
  (define realization (geometry-timeline-realization timeline))
  (define program (geometry-realization-program realization))
  (define view (geometry-realization-view realization))
  (define theme (geometry-timeline-theme timeline))
  (define environment (geometry-realization-values realization))
  (define label-table (label-positions realization theme #:labels labels))
  (define nodes
    (filter (lambda (n) (memq (geometry-node-type n) '(Point Line Segment Ray Circle)))
            (geometry-program-nodes program)))
  (define ordered-nodes
    (append (filter (lambda (n) (not (eq? (geometry-node-type n) 'Point))) nodes)
            (filter (lambda (n) (eq? (geometry-node-type n) 'Point)) nodes)))
  (define style-table
    (for/hash ([node (in-list nodes)])
      (define id (geometry-node-id node))
      (define kind (geometry-node-type node))
      (define overrides (object-style-overrides program id))
      (define styles
        (list (resolve-geometry-style theme kind 'normal overrides)
              (resolve-geometry-style theme kind 'deemphasized overrides)
              (resolve-geometry-style theme kind 'normal overrides #:highlight? #t)
              (resolve-geometry-style theme kind 'deemphasized overrides #:highlight? #t)))
      ;; Validate all colors at scene construction, not midway through a render.
      (for* ([style (in-list styles)] [channel (in-list '(stroke fill label))])
        (geometry-style-color style channel))
      (values id styles)))
  (define (object-group node frame)
    (define id (geometry-node-id node))
    (define value (hash-ref environment id))
    (define appearance (hash-ref (geometry-frame-appearances frame) id))
    (define styles (hash-ref style-table id))
    (define weights (style-weights appearance))
    (define (number property) (style-number styles weights property))
    (define alpha (* (geometry-appearance-opacity appearance) (number 'opacity)))
    (define label-alpha (* (geometry-appearance-label-opacity appearance)
                           (number 'opacity) (number 'label-opacity)))
    (define stroke-color (style-color styles appearance 'stroke))
    (define fill-color (style-color styles appearance 'fill))
    (define label-color (style-color styles appearance 'label))
    (define reveal (geometry-appearance-reveal appearance))
    (define body
      (cond [(<= alpha 0) '()]
            [(point? value)
             (define radius (* (number 'radius) (+ 0.65 (* 0.35 reveal))))
             ;; Separate fill and outline respect the two native paint channels.
             (define marker
               (a:circle #:id (key id 'marker-fill) #:center (vec value)
                         #:radius radius #:fill fill-color #:stroke transparent #:stroke-width 0))
             (define outline
               (a:circle #:id (key id 'marker-stroke) #:center (vec value)
                         #:radius radius #:fill transparent #:stroke stroke-color))
             (list
              (a:visual-with-opacity (a:visual-with-fill-color marker fill-color)
                                      (unit (* alpha reveal (number 'fill-opacity))))
              (a:visual-with-opacity
               (a:visual-with-stroke-width (a:visual-with-stroke-color outline stroke-color)
                                           (number 'stroke-width))
               (unit (* alpha reveal (number 'stroke-opacity)))))]
            [else
             (define patterns (remove-duplicates (map (lambda (s) (hash-ref s 'dash)) styles)))
             (for/list ([pattern (in-list patterns)] [i (in-naturals)])
               (define weight
                 (for/sum ([s (in-list styles)] [w (in-list weights)] #:when (equal? pattern (hash-ref s 'dash))) w))
               (a:visual-with-opacity
                (a:visual-with-stroke-width
                 (a:visual-with-stroke-color
                  (a:make-path-visual (curve-path value view reveal pattern pixels)
                                     #:id (key id (format "stroke-~a" i)) #:fill #f)
                  stroke-color)
                 (number 'stroke-width))
                (unit (* alpha weight (number 'stroke-opacity)))))]))
    (define label
      (if (and (> label-alpha 0) (hash-has-key? label-table id))
          (let ([base (car styles)])
            (list (a:plain-text
                   (display-label id) #:id (key id 'label) #:center (vec (hash-ref label-table id))
                   #:font-size (number 'font-size) #:font-family (hash-ref base 'font-family)
                   #:font-face (hash-ref base 'font-face) #:font-style (hash-ref base 'font-style)
                   #:font-weight (hash-ref base 'font-weight) #:color label-color #:opacity (unit label-alpha))))
          '()))
    (a:group (append body label) #:id id))
  (define-values (xmin xmax ymin ymax) (view-bounds view))
  (define caption-size (min 0.28 (* 0.025 (geometry-view-width view))))
  (lambda (time)
    (define frame (sample-geometry-timeline timeline time))
    (define text (geometry-frame-narration frame))
    (define caption
      (if (and captions? text)
          (list (a:paragraph text #:id (key root-id 'caption)
                             #:center (a:vec2 (point-x (geometry-view-center view)) (+ ymin (* 1.6 caption-size)))
                             #:font-size caption-size #:font-family 'swiss
                             #:color colors:theme-foreground #:width (* 0.88 (geometry-view-width view))
                             #:line-alignment 'center))
          '()))
    (a:group (append (map (lambda (n) (object-group n frame)) ordered-nodes) caption) #:id root-id)))

(define (default-root-id timeline)
  (key '$geometry (geometry-program-name (geometry-realization-program (geometry-timeline-realization timeline)))))
(define (geometry-timeline->visual timeline time #:width [width 1280]
                                   #:id [id (default-root-id timeline)]
                                   #:captions? [captions? #t] #:labels [labels (hash)])
  ((make-frame-builder timeline width id captions? labels) time))
(define (geometry-timeline->camera timeline #:width [width 1280] #:height [height 720]
                                   #:background [background colors:theme-background])
  (define view (geometry-realization-view (geometry-timeline-realization timeline)))
  (unless (< (abs (- (/ width height) (geometry-view-aspect view))) 1e-8)
    (geometry-error 'geometry-timeline->camera
                    "output aspect ~a does not match realized aspect ~a; realize with #:aspect first"
                    (/ width height) (geometry-view-aspect view)))
  (a:make-camera #:width width #:height height #:center (vec (geometry-view-center view))
                 #:world-width (geometry-view-width view) #:background background))

;; geometry-timeline->scene : geometry-timeline? ... -> animate scene?
;; A single immutable clock drives a pure relation. Native scene sampling can
;; jump forward/backward; no layout search or mutable updates occur per frame.
(define (geometry-timeline->scene timeline #:width [width 1280] #:height [height 720]
                                  #:id [id (default-root-id timeline)]
                                  #:captions? [captions? #t] #:labels [labels (hash)]
                                  #:background [background colors:theme-background])
  (define duration (geometry-timeline-duration timeline))
  (define camera (geometry-timeline->camera timeline #:width width #:height height #:background background))
  (define frame-at (make-frame-builder timeline width id captions? labels))
  (define clock-id (key id 'clock))
  (define clock (a:parameter clock-id 0))
  (define relation
    (a:relation-visual
     (a:group '() #:id id)
     #:depends-on (list (a:value-dependency clock-id)) #:structure 'root-only
     ;; Deliberately leave cache-key false: opaque closures must not pretend to
     ;; be portable cache data. All closure-captured inputs are immutable.
     (lambda (context template)
       (frame-at (a:relation-context-value-ref context clock-id)))))
  (define initial (a:scene-add (a:scene-set-value (a:make-scene #:camera camera) clock) relation))
  (a:scene-play initial #:duration duration #:easing a:linear (a:value-to clock duration)))

(define (construction->scene program #:theme [theme default-geometry-theme]
                             #:view [view #f] #:width [width 1280] #:height [height 720]
                             #:margin [margin 0.1] #:padding [padding 0.45]
                             #:samples [samples 256] #:givens [givens (hash)] #:choices [choices (hash)]
                             #:read-delay [read-delay #f] #:action-duration [action-duration #f]
                             #:step-pause [step-pause #f] #:hold [hold #f]
                             #:opening-pause [opening-pause #f] #:opening-hold [opening-hold #f]
                             #:captions? [captions? #t] #:labels [labels (hash)]
                             #:background [background colors:theme-background])
  (unless (and (exact-positive-integer? width) (exact-positive-integer? height))
    (geometry-error 'construction->scene "width and height must be positive pixel counts"))
  (define timeline
    (construction->timeline program #:theme theme #:view view #:aspect (/ width height)
                            #:margin margin #:padding padding #:samples samples
                            #:givens givens #:choices choices #:read-delay read-delay
                            #:action-duration action-duration #:step-pause step-pause
                            #:opening-pause opening-pause #:hold hold #:opening-hold opening-hold))
  (geometry-timeline->scene timeline #:width width #:height height #:captions? captions?
                            #:labels labels #:background background))
