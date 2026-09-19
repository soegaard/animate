#lang racket/base

;;;
;;; Calculus Native Rendering Adapter
;;;

;; This module is intentionally the only calculus module that imports native
;; pict, Visual, and scene facilities.  The headless calculus module remains
;; usable in test runners and analysis tools with no drawing dependencies.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "main.rkt"
         "private/core.rkt"
         (prefix-in native: "../main.rkt")
         (prefix-in panel: "../private/prepared-pict-visual.rkt")
         (prefix-in pict: pict)
         (except-in racket/class make-generic)
         racket/list
         racket/math
         (prefix-in draw: racket/draw))

;; Exports
(provide
 (all-from-out "main.rkt")
 calculus-render-quality calculus-render-quality?
 prepare-calculus-lesson prepare-calculus-plan
 prepared-calculus-lesson? prepared-lesson-plan
 prepared-lesson->scene prepared-lesson->pict prepared-lesson->visual)


;;;
;;; Immutable Prepared Records
;;;

;; calculus-render-quality-data captures only native curve-sampling policy.
(struct calculus-render-quality-data (curve-tolerance max-depth) #:transparent)
;;  - curve-tolerance  positive-real?  maximum native chord deviation in pixels
;;  - max-depth        exact-positive-integer?  bounded native subdivision depth

;; prepared-calculus-lesson-data owns one semantic plan and one pixel layout.
(struct prepared-calculus-lesson-data (plan width height formula-backend quality) #:transparent)
;;  - plan             calculus-plan?  immutable headless plan prepared for output
;;  - width            exact-positive-integer?  target output width in pixels
;;  - height           exact-positive-integer?  target output height in pixels
;;  - formula-backend  any/c  accepted formula backend descriptor, retained as identity
;;  - quality          calculus-render-quality-data?  curve preparation policy

;; calculus-render-quality? : any/c -> boolean?
;;   Recognizes a validated native curve-sampling policy.
(define calculus-render-quality? calculus-render-quality-data?)

;; prepared-calculus-lesson? : any/c -> boolean?
;;   Recognizes a lesson with resolved output dimensions and semantic plan.
(define prepared-calculus-lesson? prepared-calculus-lesson-data?)

;; positive-real-value? : any/c -> boolean?
;;   Accepts finite real values appropriate for native configuration.
(define (positive-real-value? value)
  (and (real? value) (rational? value) (positive? value)))

;; calculus-render-quality : [#:curve-tolerance positive-real?]
;;                            [#:max-depth exact-positive-integer?]
;;                         -> calculus-render-quality?
;;   Builds a bounded rendering policy without changing mathematical accuracy.
(define (calculus-render-quality #:curve-tolerance [curve-tolerance 1/2]
                                 #:max-depth [max-depth 18])
  (unless (positive-real-value? curve-tolerance)
    (raise-argument-error 'calculus-render-quality "positive finite real curve tolerance" curve-tolerance))
  (unless (exact-positive-integer? max-depth)
    (raise-argument-error 'calculus-render-quality "exact-positive-integer? maximum depth" max-depth))
  (calculus-render-quality-data curve-tolerance max-depth))

;; check-dimensions : symbol? any/c any/c -> void?
;;   Rejects dimensions that cannot name one unambiguous pixel target.
(define (check-dimensions who width height)
  (unless (exact-positive-integer? width)
    (raise-argument-error who "exact-positive-integer? width" width))
  (unless (exact-positive-integer? height)
    (raise-argument-error who "exact-positive-integer? height" height)))

;; prepare-calculus-lesson : calculus-lesson? ... -> prepared-calculus-lesson?
;;   Compiles one lesson and binds its native layout to the supplied dimensions.
(define (prepare-calculus-lesson lesson
                                 #:profile [profile default-calculus-profile]
                                 #:values [values (hash)]
                                 #:computation [computation default-calculus-computation]
                                 #:width [width 1280]
                                 #:height [height 720]
                                 #:formula-backend [formula-backend 'default]
                                 #:quality [quality (calculus-render-quality)])
  (unless (calculus-lesson? lesson)
    (raise-argument-error 'prepare-calculus-lesson "calculus-lesson?" lesson))
  (check-dimensions 'prepare-calculus-lesson width height)
  (unless (calculus-render-quality? quality)
    (raise-argument-error 'prepare-calculus-lesson "calculus-render-quality?" quality))
  (prepare-calculus-plan
   (compile-calculus-lesson lesson #:profile profile #:values values #:computation computation)
   #:width width #:height height #:formula-backend formula-backend #:quality quality))

;; prepare-calculus-plan : calculus-plan? ... -> prepared-calculus-lesson?
;;   Resolves a native layout around an already compiled, headless plan.
(define (prepare-calculus-plan plan
                               #:width [width 1280]
                               #:height [height 720]
                               #:formula-backend [formula-backend 'default]
                               #:quality [quality (calculus-render-quality)])
  (unless (calculus-plan? plan)
    (raise-argument-error 'prepare-calculus-plan "calculus-plan?" plan))
  (check-dimensions 'prepare-calculus-plan width height)
  (unless (calculus-render-quality? quality)
    (raise-argument-error 'prepare-calculus-plan "calculus-render-quality?" quality))
  (prepared-calculus-lesson-data plan width height formula-backend quality))

;; prepared-lesson-plan : prepared-calculus-lesson? -> calculus-plan?
;;   Returns the exact headless plan that supplied the prepared composition.
(define (prepared-lesson-plan prepared)
  (unless (prepared-calculus-lesson? prepared)
    (raise-argument-error 'prepared-lesson-plan "prepared-calculus-lesson?" prepared))
  (prepared-calculus-lesson-data-plan prepared))


;;;
;;; Shared Pict Composition
;;;

;; target-address : any/c -> (or/c symbol? (non-empty-listof symbol?) #f)
;;   Converts semantic target records to their public inspection address.
(define (target-address target)
  (cond
    [(c-node? target) (c-node-id target)]
    [(c-part? target)
     (define parent (target-address (c-part-parent target)))
     (and parent
          (append (if (list? parent) parent (list parent))
                  (if (list? (c-part-name target))
                      (c-part-name target)
                      (list (c-part-name target)))))]
    [else #f]))

;; interval-bounds : any/c real? real? -> (values real? real?)
;;   Extracts ordinary authored view endpoints, with a stable fallback range.
(define (interval-bounds domain lower upper)
  (cond
    [(and (c-domain? domain)
          (memq (c-domain-kind domain) '(closed open closed-open open-closed))
          (= (length (c-domain-arguments domain)) 2)
          (andmap real? (c-domain-arguments domain)))
     (values (exact->inexact (first (c-domain-arguments domain)))
             (exact->inexact (second (c-domain-arguments domain))))]
    [else (values lower upper)]))

;; view-objects : c-view? -> list?
;;   Reads the documented object list from a prepared view descriptor.
(define (view-objects view)
  (define objects (hash-ref (c-view-options view) 'objects '()))
  (if (list? objects) objects '()))

;; snapshot-defined-value : calculus-snapshot? address -> any/c
;;   Returns a defined public result's value or #f for partial mathematical data.
(define (snapshot-defined-value snapshot address)
  (define result (calculus-snapshot-ref snapshot address))
  (and (eq? (calculus-result-status result) 'defined)
       (calculus-result-value result)))

;; hex-color : string? -> color%
;;   Converts the documented CSS-style palette literal into the color objects
;;   required by racket/draw; passing the string directly paints black.
(define (hex-color text)
  (unless (and (string? text) (regexp-match? #px"^#[0-9A-Fa-f]{6}$" text))
    (raise-argument-error 'hex-color "six-digit hexadecimal color string" text))
  (define (byte start)
    (string->number (substring text start (+ start 2)) 16))
  (draw:make-color (byte 1) (byte 3) (byte 5)))

;; draw-line-segment : drawing-context% real? real? real? real? string? real? -> void?
;;   Draws one native segment with an explicit, temporary pen configuration.
(define (draw-line-segment context x1 y1 x2 y2 color width)
  (send context set-pen (new draw:pen% [color (hex-color color)] [width width] [style 'solid]))
  (send context draw-line x1 y1 x2 y2))

;; function-source : any/c -> any/c
;;   Removes a public node wrapper before inspecting held function topology.
(define (function-source function)
  (if (c-node? function) (c-node-data function) function))

;; equality-branch-boundary : any/c symbol? -> (or/c real? #f)
;;   Extracts a declared equality boundary involving a held function variable.
(define (equality-branch-boundary condition variable)
  (and (c-expression? condition)
       (eq? (c-expression-op condition) '=)
       (= (length (c-expression-arguments condition)) 2)
       (let ([left (first (c-expression-arguments condition))]
             [right (second (c-expression-arguments condition))])
         (cond [(and (c-expression? left) (eq? (c-expression-op left) 'var)
                     (equal? (c-expression-arguments left) (list variable)) (real? right)) right]
               [(and (c-expression? right) (eq? (c-expression-op right) 'var)
                     (equal? (c-expression-arguments right) (list variable)) (real? left)) left]
               [else #f]))))

;; division-boundaries : any/c symbol? -> list?
;;   Finds simple held-variable divisors, which are guaranteed graph gaps.
(define (division-boundaries expression variable)
  (cond
    [(not (c-expression? expression)) '()]
    [else
     (append
      (if (eq? (c-expression-op expression) '/)
          (for/list ([denominator (in-list (rest (c-expression-arguments expression)))]
                     #:when (and (c-expression? denominator)
                                 (eq? (c-expression-op denominator) 'var)
                                 (equal? (c-expression-arguments denominator) (list variable))))
            0)
          '())
      (append-map (lambda (argument) (division-boundaries argument variable))
                  (c-expression-arguments expression)))]))

;; graph-boundaries : any/c -> list?
;;   Supplies mandatory known graph samples independently of adaptive pixel sampling.
(define (graph-boundaries function)
  (define source (function-source function))
  (cond
    [(c-piecewise? source)
     (filter real?
             (map (lambda (branch)
                    (equality-branch-boundary (car branch) (c-piecewise-variable source)))
                  (c-piecewise-branches source)))]
    [(c-function? source)
     (division-boundaries (c-function-body source) (c-function-variable source))]
    [else '()]))

;; piecewise-equality-boundaries : any/c -> list?
;;   Retains source branch IDs for equality boundaries with a possible isolated value.
(define (piecewise-equality-boundaries function)
  (define source (function-source function))
  (if (c-piecewise? source)
      (for/list ([branch (in-list (c-piecewise-branches source))]
                 [index (in-naturals)]
                 #:do [(define boundary
                          (equality-branch-boundary (car branch)
                                                    (c-piecewise-variable source)))]
                 #:when (real? boundary))
        (cons boundary index))
      '()))

;; draw-closed-point : drawing-context% real? real? -> void?
;;   Paints an included graph endpoint or isolated value from semantic topology.
(define (draw-closed-point context x y)
  (send context set-pen (new draw:pen% [color (hex-color "#2166C2")] [width 1] [style 'solid]))
  (send context set-brush (new draw:brush% [color (hex-color "#2166C2")] [style 'solid]))
  (send context draw-ellipse (- x 3) (- y 3) 6 6))

;; draw-open-point : drawing-context% real? real? -> void?
;;   Paints an excluded graph endpoint without adding a mathematical value.
(define (draw-open-point context x y)
  (send context set-pen (new draw:pen% [color (hex-color "#2166C2")] [width 2] [style 'solid]))
  (send context set-brush (new draw:brush% [color (hex-color "#FAFAFA")] [style 'solid]))
  (send context draw-ellipse (- x 4) (- y 4) 8 8))

;; draw-graph : drawing-context% calculus-snapshot? c-node? ... -> void?
;;   Samples a visible held graph from its semantic function, never from pixels.
(define (draw-graph context snapshot node xmin xmax ymin ymax left top width height)
  (define raw (c-node-data node))
  (when (and (c-object? raw) (memq (c-object-kind raw) '(graph graph-restriction)))
    (define function (first (c-object-arguments raw)))
    (define samples 160)
    (define (pixel-x x) (+ left (* width (/ (- x xmin) (- xmax xmin)))))
    (define (pixel-y y) (+ top height (* -1 height (/ (- y ymin) (- ymax ymin)))))
    (define previous #f)
    (define equality-boundaries (piecewise-equality-boundaries function))
    (define sample-inputs
      (sort (remove-duplicates
             (append (for/list ([index (in-range (add1 samples))])
                       (+ xmin (* (- xmax xmin) (/ index samples))))
                     (filter (lambda (boundary) (<= xmin boundary xmax))
                             (graph-boundaries function))))
            <))
    (for ([x (in-list sample-inputs)])
      (define result (calculus-snapshot-function-value snapshot function x))
      (define branch-result (calculus-snapshot-function-branch snapshot function x))
      (define next
        (and (eq? (calculus-result-status result) 'defined)
             (eq? (calculus-result-status branch-result) 'defined)
             (real? (calculus-result-value result))
             (let ([y (calculus-result-value result)])
               (and (<= ymin y ymax)
                    (list (pixel-x x) (pixel-y y) (calculus-result-value branch-result))))))
      (when (and previous next (equal? (third previous) (third next)))
        (draw-line-segment context (first previous) (second previous)
                           (first next) (second next) "#2166C2" 2))
      (define equality-boundary (assoc x equality-boundaries))
      (when (and next equality-boundary
                 (equal? (third next) (cdr equality-boundary)))
        (draw-closed-point context (first next) (second next)))
      (set! previous next))
    (for ([boundary+branch (in-list equality-boundaries)])
      (define boundary (car boundary+branch))
      (define selected
        (calculus-snapshot-function-branch snapshot function boundary))
      (define excluded
        (calculus-snapshot-function-branch-value snapshot function 'else boundary))
      (when (and (eq? (calculus-result-status selected) 'defined)
                 (equal? (calculus-result-value selected) (cdr boundary+branch))
                 (eq? (calculus-result-status excluded) 'defined)
                 (real? (calculus-result-value excluded))
                 (<= ymin (calculus-result-value excluded) ymax))
        (draw-open-point context (pixel-x boundary)
                         (pixel-y (calculus-result-value excluded)))))))

;; draw-point : drawing-context% calculus-snapshot? address ... -> void?
;;   Draws one defined point and intentionally omits partial point values.
(define (draw-point context snapshot address xmin xmax ymin ymax left top width height)
  (define point (snapshot-defined-value snapshot address))
  (when (and (pair? point) (real? (car point)) (real? (cdr point))
             (<= xmin (car point) xmax) (<= ymin (cdr point) ymax))
    (define x (+ left (* width (/ (- (car point) xmin) (- xmax xmin)))))
    (define y (+ top height (* -1 height (/ (- (cdr point) ymin) (- ymax ymin)))))
    (send context set-pen (new draw:pen% [color (hex-color "#B3261E")] [width 1] [style 'solid]))
    (send context set-brush (new draw:brush% [color (hex-color "#B3261E")] [style 'solid]))
    (send context draw-ellipse (- x 4) (- y 4) 8 8)))

;; draw-reading : drawing-context% calculus-snapshot? symbol? ... -> void?
;;   Renders an input-reading's semantic point and its two coordinate guides.
(define (draw-reading context snapshot name xmin xmax ymin ymax left top width height)
  (define point (snapshot-defined-value snapshot (list name 'point)))
  (when (and (pair? point) (real? (car point)) (real? (cdr point))
             (<= xmin (car point) xmax) (<= ymin (cdr point) ymax))
    (define (pixel-x x) (+ left (* width (/ (- x xmin) (- xmax xmin)))))
    (define (pixel-y y) (+ top height (* -1 height (/ (- y ymin) (- ymax ymin)))))
    (send context set-pen (new draw:pen% [color (hex-color "#6A6A6A")] [width 1] [style 'dot]))
    (send context draw-line (pixel-x (car point)) (pixel-y 0) (pixel-x (car point)) (pixel-y (cdr point)))
    (send context draw-line (pixel-x 0) (pixel-y (cdr point)) (pixel-x (car point)) (pixel-y (cdr point)))
    (draw-point context snapshot (list name 'point) xmin xmax ymin ymax left top width height)))

;; The graph painter needs the model, but a snapshot deliberately exposes only
;; inspection operations.  Keep the small model-aware walker separate so the
;; actual drawing loop is easy to audit.
(define (draw-graph-panel/model context snapshot model view left top width height)
  (define-values (xmin xmax) (interval-bounds (hash-ref (c-view-options view) 'x #f) -5 5))
  (define-values (ymin ymax) (interval-bounds (hash-ref (c-view-options view) 'y #f) -5 5))
  (send context set-pen (new draw:pen% [color (hex-color "#D0D0D0")] [width 1] [style 'solid]))
  (send context set-brush (new draw:brush% [color (hex-color "#FAFAFA")] [style 'solid]))
  (send context draw-rectangle left top width height)
  (define (pixel-x x) (+ left (* width (/ (- x xmin) (- xmax xmin)))))
  (define (pixel-y y) (+ top height (* -1 height (/ (- y ymin) (- ymax ymin)))))
  (when (<= xmin 0 xmax) (draw-line-segment context (pixel-x 0) top (pixel-x 0) (+ top height) "#8A8A8A" 1))
  (when (<= ymin 0 ymax) (draw-line-segment context left (pixel-y 0) (+ left width) (pixel-y 0) "#8A8A8A" 1))
  (for ([target (in-list (view-objects view))])
    (define address (target-address target))
    (when (and address (calculus-snapshot-visible? snapshot address))
      (define root (if (list? address) (first address) address))
      (define node (hash-ref (calculus-model-nodes model) root #f))
      (cond
        [(and node (memq (c-node-kind node) '(graph graph-restriction)))
         (draw-graph context snapshot node xmin xmax ymin ymax left top width height)]
        [(and node (memq (c-node-kind node) '(point point-on axis-point projection root-point intersection-point)))
         (draw-point context snapshot address xmin xmax ymin ymax left top width height)]
        [(and node (eq? (c-node-kind node) 'input-reading))
         (draw-reading context snapshot root xmin xmax ymin ymax left top width height)]
        [(and (list? address) (= (length address) 2) (eq? (second address) 'point))
         (draw-point context snapshot address xmin xmax ymin ymax left top width height)]
        [else (void)]))))

;; value->display-string : any/c -> string?
;;   Gives formula panels a concise, deterministic textual inspection value.
(define (value->display-string value)
  (cond [(number? value) (number->string value)]
        [(boolean? value) (if value "true" "false")]
        [(pair? value) (format "(~a, ~a)" (car value) (cdr value))]
        [else "—"]))

;; draw-formula-panel : drawing-context% calculus-snapshot? c-view? ... -> void?
;;   Draws a native textual formula/readout panel from semantic object values.
(define (draw-formula-panel context snapshot view left top width height)
  (send context set-pen (new draw:pen% [color (hex-color "#D0D0D0")] [width 1] [style 'solid]))
  (send context set-brush (new draw:brush% [color (hex-color "#FFFFFF")] [style 'solid]))
  (send context draw-rectangle left top width height)
  (send context set-text-foreground (hex-color "#202124"))
  (send context set-font (new draw:font% [size 15] [family 'modern]))
  (for ([target (in-list (view-objects view))] [index (in-naturals)])
    (define address (target-address target))
    (when (and address (calculus-snapshot-visible? snapshot address))
      (define value (snapshot-defined-value snapshot address))
      (define label (if (list? address) (format "~a" address) (symbol->string address)))
      (send context draw-text (format "~a  ~a" label (value->display-string value))
            (+ left 16) (+ top 20 (* 26 index))))))

;; lesson-views : calculus-lesson? -> list?
;;   Orders view names deterministically for the prepared panel layout.
(define (lesson-views lesson)
  (for/list ([name (in-list (sort (hash-keys (calculus-lesson-views lesson)) symbol<?))])
    (hash-ref (calculus-lesson-views lesson) name)))

;; render-snapshot->pict : prepared-calculus-lesson? calculus-snapshot? -> pict?
;;   Creates one native pict from one semantic state and the prepared dimensions.
(define (render-snapshot->pict prepared snapshot)
  (define plan (prepared-lesson-plan prepared))
  (define lesson (calculus-plan-lesson plan))
  (define model (calculus-lesson-model lesson))
  (define width (prepared-calculus-lesson-data-width prepared))
  (define height (prepared-calculus-lesson-data-height prepared))
  (define views (lesson-views lesson))
  (pict:dc
   (lambda (context x y)
     (define original-pen (send context get-pen))
     (define original-brush (send context get-brush))
     (define original-font (send context get-font))
     (define original-foreground (send context get-text-foreground))
     (dynamic-wind
      void
      (lambda ()
        (send context set-pen (new draw:pen% [color (hex-color "#FFFFFF")] [width 1] [style 'solid]))
        (send context set-brush (new draw:brush% [color (hex-color "#FFFFFF")] [style 'solid]))
        (send context draw-rectangle x y width height)
        (define margin 32)
        (define count (max 1 (length views)))
        (define panel-gap 18)
        (define panel-width (/ (- width (* 2 margin) (* (sub1 count) panel-gap)) count))
        (define panel-height (- height (* 2 margin)))
        (for ([view (in-list views)] [index (in-naturals)])
          (define left (+ x margin (* index (+ panel-width panel-gap))))
          (define top (+ y margin))
          (cond [(eq? (c-view-kind view) 'graph-view)
                 (draw-graph-panel/model context snapshot model view left top panel-width panel-height)]
                [else (draw-formula-panel context snapshot view left top panel-width panel-height)])))
      (lambda ()
        (send context set-pen original-pen)
        (send context set-brush original-brush)
        (send context set-font original-font)
        (send context set-text-foreground original-foreground))))
   width height))


;;;
;;; Public Prepared Output
;;;

;; prepared-lesson->pict : prepared-calculus-lesson? [#:at location] -> pict?
;;   Produces the shared prepared composition at one headless semantic moment.
(define (prepared-lesson->pict prepared #:at [at 'final])
  (unless (prepared-calculus-lesson? prepared)
    (raise-argument-error 'prepared-lesson->pict "prepared-calculus-lesson?" prepared))
  (render-snapshot->pict prepared
                         (calculus-plan-sample (prepared-lesson-plan prepared) #:at at)))

;; native-camera : prepared-calculus-lesson? -> camera?
;;   Chooses a one-pixel-per-world-unit camera for the prepared pict panel.
(define (native-camera prepared)
  (native:make-camera #:width (prepared-calculus-lesson-data-width prepared)
                      #:height (prepared-calculus-lesson-data-height prepared)
                      #:world-width (prepared-calculus-lesson-data-width prepared)
                      #:background "white"))

;; prepared-lesson->visual : prepared-calculus-lesson? [#:at location] -> Visual
;;   Wraps the prepared pict in Animate's standard Visual protocol.
(define (prepared-lesson->visual prepared #:at [at 'final])
  (unless (prepared-calculus-lesson? prepared)
    (raise-argument-error 'prepared-lesson->visual "prepared-calculus-lesson?" prepared))
  (panel:prepared-pict-panel (prepared-lesson->pict prepared #:at at)
                             #:width (prepared-calculus-lesson-data-width prepared)
                             #:height (prepared-calculus-lesson-data-height prepared)
                             #:id 'calculus-prepared-panel))

;; prepared-scene-times : calculus-plan? -> (listof nonnegative-real?)
;;   Selects semantic boundaries plus a deterministic thirty-frame-per-second grid.
(define (prepared-scene-times plan)
  (define duration (calculus-plan-duration plan))
  (define frame-count (max 1 (ceiling (* duration 30))))
  (sort
   (remove-duplicates
    (append (for/list ([index (in-range (add1 frame-count))]) (* duration (/ index frame-count)))
            (append-map (lambda (event) (list (c-event-start event) (c-event-end event)))
                        (calculus-plan-events plan))))
   <))

;; prepared-lesson->scene : prepared-calculus-lesson? -> scene?
;;   Builds a deterministic scene from the same prepared semantic picts used for stills.
;;   Frame boundaries include every command boundary and a fixed 30fps semantic grid.
(define (prepared-lesson->scene prepared)
  (unless (prepared-calculus-lesson? prepared)
    (raise-argument-error 'prepared-lesson->scene "prepared-calculus-lesson?" prepared))
  (define plan (prepared-lesson-plan prepared))
  (define times (prepared-scene-times plan))
  (define initial-time (first times))
  (define initial-scene
    (native:scene-add (native:make-scene #:camera (native-camera prepared))
                      (prepared-lesson->visual prepared #:at initial-time)))
  (for/fold ([scene initial-scene] [previous initial-time]
             #:result scene)
            ([time (in-list (rest times))])
    (define held
      (if (= time previous)
          scene
          (native:scene-wait scene (- time previous))))
    (values (native:scene-add (native:scene-remove held 'calculus-prepared-panel)
                              (prepared-lesson->visual prepared #:at time))
            time)))
