#lang racket/base

;;;
;;; Built-in Pict Renderers
;;;

;; Defines Pict renderer implementations for the built-in Visual primitives.
;;
;; This adapter module may depend on both the semantic Visual model and the
;; Racket Pict and drawing backends. The Visual model does not depend on this
;; module.


;;;
;;; Imports and Exports
;;;

;; Imports
(require racket/class
         (only-in pict
                  blank
                  colorize
                  dc
                  draw-pict
                  ellipse
                  filled-ellipse
                  filled-rectangle
                  hb-append
                  pict-ascent
                  pict-descent
                  pict-height
                  pict->bitmap
                  pict-width
                  scale
                  text)
         (only-in pict [rectangle pict-rectangle])
         (only-in racket/draw
                  dc-path%
                  make-brush
                  make-color
                  make-font
                  make-pen)
         "affine-transform.rkt"
         "arrow-visual.rkt"
         "axes-visual.rkt"
         "anchored-pict.rkt"
         "camera.rkt"
         "color-style.rkt"
         "geometry.rkt"
         "glyph-outline-morph-pict-renderer.rkt"
         "image-pict-renderer.rkt"
         "latex-formula-pict-renderer.rkt"
         (only-in "path-pict-renderer.rkt" path-pict-renderer)
         "path-geometry.rkt"
         "pict-renderer.rkt"
         "renderer-resources.rkt"
         "svg-pict-renderer.rkt"
         "tagged-formula-pict-renderer.rkt"
         "text-visual.rkt"
         "visual-model.rkt")

;; Exports
(provide default-pict-renderers
         default-pict-renderer-cache-counters
         (struct-out renderer-cache-counters))


;;;
;;; Renderer Data
;;;

(struct circle-pict-renderer ()
  #:transparent
  #:methods gen:pict-renderer
  [(define (pict-renderer-supports? _renderer visual)
     (circle-visual? visual))
   (define (pict-renderer-render _renderer visual camera)
     (circle-visual->pict visual camera))])

;; circle-pict-renderer renders semantic circle Visuals with the Pict backend.

(struct rectangle-pict-renderer ()
  #:transparent
  #:methods gen:pict-renderer
  [(define (pict-renderer-supports? _renderer visual)
     (rectangle-visual? visual))
   (define (pict-renderer-render _renderer visual camera)
     (rectangle-visual->pict visual camera))])

;; rectangle-pict-renderer renders semantic rectangle Visuals with the Pict
;; backend.

(struct arrow-pict-renderer ()
  #:transparent
  #:methods gen:pict-renderer
  [(define (pict-renderer-supports? _renderer visual)
     (arrow-visual? visual))
   (define (pict-renderer-render _renderer visual camera)
     (arrow-visual->pict visual camera))])

;; arrow-pict-renderer renders semantic shafts and triangular tips through the
;; shared path backend.

(struct axes-pict-renderer ()
  #:transparent
  #:methods gen:pict-renderer
  [(define (pict-renderer-supports? _renderer visual)
     (axes-visual? visual))
   (define (pict-renderer-render _renderer visual camera)
     (axes-visual->pict visual camera))])

;; axes-pict-renderer renders semantic axis shafts, ticks, and maximum-end tips
;; through the shared path backend.

;;;
;;; Plain-Text Raster Cache
;;;

; maximum-text-raster-cache-entries : exact-positive-integer?
;;   Bounds the number of cached plain-text appearances independently from bytes.
(define maximum-text-raster-cache-entries
  256)

; maximum-text-raster-cache-bytes : exact-positive-integer?
;;   Bounds cached plain-text raster storage. Oversize text still gets frozen at
;;   a stable local origin, but its bitmap is not retained between render calls.
(define maximum-text-raster-cache-bytes
  (* 32 1024 1024))

; make-text-raster-cache : -> renderer-resource-cache?
;;   Creates one empty bounded cache for a text Pict renderer.
(define (make-text-raster-cache)
  (make-renderer-resource-cache
   #:max-entries maximum-text-raster-cache-entries
   #:max-bytes maximum-text-raster-cache-bytes))

(struct text-pict-renderer (raster-cache)
  #:transparent
  #:methods gen:pict-renderer
  [(define (pict-renderer-supports? _renderer visual)
     (text-visual? visual))
   (define (pict-renderer-render renderer visual camera)
     (text-visual->pict visual
                        camera
                        (text-pict-renderer-raster-cache renderer)))])

;; text-pict-renderer renders immutable plain, paragraph, and rich text Visuals
;; with Pict fonts.


;;;
;;; Default Renderer Set
;;;

; default-pict-renderers : (listof pict-renderer?)
;;   Gives built-in renderers in significant first-match selection order.
(define default-pict-renderers
  (list (circle-pict-renderer)
        (rectangle-pict-renderer)
        (path-pict-renderer)
        (arrow-pict-renderer)
        (axes-pict-renderer)
        (image-pict-renderer (make-image-raster-cache))
        (svg-pict-renderer (make-svg-pict-cache))
        (text-pict-renderer (make-text-raster-cache))
        (glyph-outline-morph-pict-renderer)
        (tagged-formula-pict-renderer (make-tagged-formula-pict-cache))
        default-latex-formula-pict-renderer))

;; renderer-cache-counters summarize performance-only resources owned by the
;; supplied built-in renderer instances. Unknown custom renderers contribute no
;; counters because their caching policy is entirely their own.
(struct renderer-cache-counters (hits misses evictions)
  #:transparent)

; default-pict-renderer-cache-counters : (listof pict-renderer?)
;                                         -> renderer-cache-counters?
(define (default-pict-renderer-cache-counters renderers)
  (define-values (hits misses evictions)
    (for/fold ([hits 0] [misses 0] [evictions 0])
              ([renderer (in-list renderers)])
      (define cache
        (cond [(image-pict-renderer? renderer)
               (image-pict-renderer-raster-cache renderer)]
              [(svg-pict-renderer? renderer)
               (svg-pict-renderer-pict-cache renderer)]
              [(tagged-formula-pict-renderer? renderer)
               (tagged-formula-pict-renderer-pict-cache renderer)]
              [(text-pict-renderer? renderer)
               (text-pict-renderer-raster-cache renderer)]
              [(latex-formula-pict-renderer? renderer)
               (latex-formula-pict-renderer-appearance-cache renderer)]
              [else #f]))
      (if cache
          (let ([statistics (renderer-resource-cache-statistics cache)])
            (values (+ hits (renderer-resource-cache-stats-hits statistics))
                    (+ misses (renderer-resource-cache-stats-misses statistics))
                    (+ evictions (renderer-resource-cache-stats-evictions statistics))))
          (values hits misses evictions))))
  (renderer-cache-counters hits misses evictions))

; maximum-default-pict-stroke-width : exact-positive-integer?
;;   Gives racket/draw's maximum pen width. The semantic Visual model deliberately
;;   accepts larger widths because custom renderers may support them.
(define maximum-default-pict-stroke-width 255)

; check-default-pict-stroke-width : symbol? nonnegative-real? -> void?
;;   Reports the default Pict backend's pen-width limit before racket/draw emits a
;;   lower-level contract failure.
(define (check-default-pict-stroke-width who stroke-width)
  (when (> stroke-width maximum-default-pict-stroke-width)
    (raise-arguments-error
     who
     "the default Pict renderer supports cosmetic stroke widths from 0 through 255 pixels"
     "stroke-width" stroke-width
     "maximum-stroke-width" maximum-default-pict-stroke-width)))


;;;
;;; Closed Shape Conversion
;;;

; circle-visual->pict : circle-visual? camera? -> pict?
;;   Converts circle to a scaled and rotated ellipse Pict.
(define (circle-visual->pict circle camera)
  (check-default-pict-stroke-width
   'circle-visual->pict
   (circle-visual-stroke-width circle))
  (define scale
    (visual-scale circle))
  (define diameter
    (* 2 (circle-visual-radius circle)))
  (define width
    (camera-length->pixels camera
                           (* diameter (vec2-x scale))))
  (define height
    (camera-length->pixels camera
                           (* diameter (vec2-y scale))))
  (define shape
    (if (circle-visual-fill circle)
        (filled-ellipse width
                        height
                        #:color (draw-color-spec (circle-visual-fill circle))
                        #:border-color
                        (draw-color-spec (circle-visual-stroke circle))
                        #:border-width (circle-visual-stroke-width circle))
        (ellipse width
                 height
                 #:border-color (draw-color-spec (circle-visual-stroke circle))
                 #:border-width (circle-visual-stroke-width circle))))
  (if (or (zero? (visual-rotation circle))
          (= (vec2-x scale) (vec2-y scale)))
      shape
      (rotate-pict-if-needed shape
                             (visual-rotation circle))))

; rectangle-visual->pict : rectangle-visual? camera? -> pict?
;;   Converts rectangle to a scaled and rotated rectangle Pict.
(define (rectangle-visual->pict rectangle camera)
  (check-default-pict-stroke-width
   'rectangle-visual->pict
   (rectangle-visual-stroke-width rectangle))
  (define scale
    (visual-scale rectangle))
  (define width
    (camera-length->pixels
     camera
     (* (rectangle-visual-width rectangle)
        (vec2-x scale))))
  (define height
    (camera-length->pixels
     camera
     (* (rectangle-visual-height rectangle)
        (vec2-y scale))))
  (define shape
    (if (rectangle-visual-fill rectangle)
        (filled-rectangle width
                          height
                          #:color
                          (draw-color-spec (rectangle-visual-fill rectangle))
                          #:border-color
                          (draw-color-spec (rectangle-visual-stroke rectangle))
                          #:border-width
                          (rectangle-visual-stroke-width rectangle))
        (pict-rectangle width
                        height
                        #:border-color
                        (draw-color-spec (rectangle-visual-stroke rectangle))
                        #:border-width
                        (rectangle-visual-stroke-width rectangle))))
  (rotate-pict-if-needed shape
                         (visual-rotation rectangle)))

;;;
;;; Arrow and Axes Conversion
;;;

; arrow-visual->pict : arrow-visual? camera? -> pict?
;;   Converts one semantic arrow through the shared path renderer.  Arrow tips
;;   are filled but deliberately not stroked: a mitered outline at an acute
;;   triangular apex projects beyond the semantic endpoint.
(define (arrow-visual->pict visual camera)
  (arrow-path-visual->pict
   (make-path-visual
    (arrow-render-path-geometry visual)
    #:id (visual-id visual)
    #:center (visual-position visual)
    #:rotation (visual-rotation visual)
    #:scale (visual-scale visual)
    #:fill (arrow-visual-stroke visual)
    #:stroke (arrow-visual-stroke visual)
    #:stroke-width (arrow-visual-stroke-width visual))
   camera))

; arrow-render-path-geometry : arrow-visual? -> path-geometry?
;;   Gives the rendering geometry for an arrow.  The semantic endpoint is the
;; apex of each tip, while the stroked shaft stops at the base of that tip.
;; This avoids a round shaft cap protruding through a filled arrowhead.
(define (arrow-render-path-geometry visual)
  (define original-geometry
    (arrow-visual-path-geometry visual))
  (define original-shaft
    (for/first ([subpath
                 (in-list
                  (path-geometry-subpaths original-geometry))]
                #:unless (path-subpath-closed? subpath))
      subpath))
  (define local-start
    (path-subpath-start original-shaft))
  (define local-end
    (line-path-segment-end
     (car (path-subpath-segments original-shaft))))
  (define direction
    (vec2- local-end local-start))
  (define length
    (sqrt (+ (* (vec2-x direction) (vec2-x direction))
             (* (vec2-y direction) (vec2-y direction)))))
  (define start-inset
    (if (arrow-visual-start-tip? visual)
        (arrow-visual-tip-length visual)
        0))
  (define end-inset
    (if (arrow-visual-end-tip? visual)
        (arrow-visual-tip-length visual)
        0))
  (define shaft-subpaths
    (if (> length (+ start-inset end-inset))
        (let* ([unit-direction
                (vec2-scale (/ 1 length) direction)]
               [shaft-start
                (vec2+ local-start
                       (vec2-scale start-inset unit-direction))]
               [shaft-end
                (vec2- local-end
                       (vec2-scale end-inset unit-direction))])
          (list (path-subpath shaft-start
                              (list (line-path-segment shaft-end))
                              #f)))
        '()))
  (define tip-subpaths
    (filter path-subpath-closed?
            (path-geometry-subpaths
             original-geometry)))
  (path-geometry
   (append shaft-subpaths tip-subpaths)))

; axes-visual->pict : axes-visual? camera? -> pict?
;;   Converts semantic axes through the shared path renderer.
(define (axes-visual->pict visual camera)
  (diagram-path->pict visual
                      (axes-visual-path-geometry visual)
                      (axes-visual-stroke visual)
                      (axes-visual-stroke-width visual)
                      camera))

; diagram-path->pict : affine-visual? path-geometry? any/c
;                      nonnegative-real? camera? -> pict?
;;   Renders styled local diagram geometry with one Visual's affine transform.
(define (diagram-path->pict visual geometry stroke stroke-width camera)
  (path-visual->pict
   (make-path-visual geometry
                     #:id (visual-id visual)
                     #:center (visual-position visual)
                     #:rotation (visual-rotation visual)
                     #:scale (visual-scale visual)
                     #:fill stroke
                     #:stroke stroke
                     #:stroke-width stroke-width)
   camera))

;;;
;;; Text Conversion
;;;

; minimum-font-pixel-size : positive-real?
;;   Gives the smallest font size passed directly to racket/draw.
(define minimum-font-pixel-size
  1)

; maximum-font-pixel-size : positive-real?
;;   Gives the largest font size passed directly to racket/draw.
(define maximum-font-pixel-size
  1024)

; text-visual->pict : text-visual? camera? renderer-resource-cache? -> pict?
;;   Converts anchored text content to a stable local raster Pict. The glyphs
;;   are rasterized before scene placement, so changing only the Visual position
;;   translates identical pixels instead of asking the font backend to rasterize
;;   the glyph run at a new device-space origin on every frame.
(define (text-visual->pict visual camera raster-cache)
  (if (string=? (text-visual-content visual) "")
      (blank 1 1)
      (let-values ([(cacheable? cache-key)
                    (text-raster-cache-key visual camera)])
        (cond
          [cacheable?
           (renderer-resource-cache-ref!
            raster-cache
            (list 'plain-text cache-key)
            (lambda ()
              (freeze-text-pict-at-local-origin
               (text-visual->live-pict visual camera))))]
          [else
           (let-values ([(frozen-pict _byte-count)
                         (freeze-text-pict-at-local-origin
                          (text-visual->live-pict visual camera))])
             frozen-pict)]))))

; text-visual->live-pict : text-visual? camera? -> pict?
;;   Builds the ordinary vector/font Pict at local origin before it is frozen.
(define (text-visual->live-pict visual camera)
  (define content-pict
    (text-content->pict visual camera))
  (define anchored-pict
    (anchor-pict
     content-pict
     (text-visual-horizontal-alignment visual)
     (text-visual-vertical-alignment visual)))
  (define scaled-pict
    (scale-pict-if-needed anchored-pict
                          (visual-scale visual)))
  (rotate-pict-if-needed scaled-pict
                         (visual-rotation visual)))

; freeze-text-pict-at-local-origin : pict?
;                                     -> (values pict? exact-nonnegative-integer?)
;;   Rasterizes source once at its stable local origin and returns a Pict that
;;   draws that alpha bitmap while preserving source's exact logical Pict bounds,
;;   ascent, and descent. Also reports estimated four-byte ARGB storage.
(define (freeze-text-pict-at-local-origin source)
  (define frozen-bitmap
    (pict->bitmap source 'aligned))
  (define frozen-pict
    (dc (lambda (drawing-context x y)
          (send drawing-context draw-bitmap frozen-bitmap x y))
        (pict-width source)
        (pict-height source)
        (pict-ascent source)
        (pict-descent source)))
  (values
   frozen-pict
   (* 4
      (send frozen-bitmap get-width)
      (send frozen-bitmap get-height))))

; text-raster-cache-key : text-visual? camera? -> (values boolean? any/c)
;;   Produces a position-independent cache key when the adapter color style can
;;   be snapshotted safely. Position and opacity deliberately do not participate:
;;   placement and cellophane happen after the local glyph raster is selected.
(define (text-raster-cache-key visual camera)
  (define-values (spans-cacheable? span-key)
    (text-spans-cache-key visual))
  (values
   spans-cacheable?
   (and spans-cacheable?
        (list span-key
              (text-visual-font-size visual)
              (text-visual-font-face visual)
              (text-visual-font-family visual)
              (text-visual-font-style visual)
              (text-visual-font-weight visual)
              (text-visual-horizontal-alignment visual)
              (text-visual-vertical-alignment visual)
              (text-visual-width visual)
              (text-visual-line-spacing visual)
              (text-visual-line-alignment visual)
              (visual-scale visual)
              (visual-rotation visual)
              (camera-scale camera)))))

; text-color-cache-key : any/c -> (values boolean? any/c)
;;   Snapshots common immutable/cache-safe text color specifications. Unknown
;;   adapter-native values bypass the cache so mutable drawing objects cannot
;;   leave a stale raster behind; they are still frozen locally on every render.
(define (text-color-cache-key color)
  (cond
    [(string? color)
     (values #t (string->immutable-string color))]
    [(or (symbol? color)
         (number? color)
         (boolean? color)
         (char? color))
     (values #t color)]
    [else
     (values #f #f)]))

;; text-spans-cache-key : text-visual? -> (values boolean? any/c)
;; A whole frozen text layout can be cached only when every effective inline
;; colour is an immutable/cache-safe value.
(define (text-spans-cache-key visual)
  (let loop ([remaining (text-visual-spans visual)]
             [keys '()])
    (cond
      [(null? remaining)
       (values #t (reverse keys))]
      [else
       (define span (car remaining))
       (define-values (cacheable? color-key)
         (text-color-cache-key
          (or (text-span-color span) (text-visual-color visual))))
       (if cacheable?
           (loop
            (cdr remaining)
            (cons
             (list (text-span-content span)
                   (text-span-font-size span)
                   (text-span-font-face span)
                   (text-span-font-family span)
                   (text-span-font-style span)
                   (text-span-font-weight span)
                   color-key)
             keys))
           (values #f #f))])))

(struct text-layout-token (kind pict) #:transparent)

;; text-content->pict : text-visual? camera? -> pict?
;; Keeps the old direct Pict route for one unwrapped run, while paragraphs and
;; rich spans receive deterministic renderer-measured line layout.
(define (text-content->pict visual camera)
  (define spans (text-visual-spans visual))
  (cond
    [(and (= (length spans) 1)
          (not (text-visual-width visual))
          (not (text-string-has-line-break?
                (text-span-content (car spans)))))
     (text-span-content->pict visual
                              (car spans)
                              (text-span-content (car spans))
                              camera)]
    [else
     (text-paragraph->pict visual camera)]))

;; text-span-content->pict : text-visual? text-span? string? camera? -> pict?
;; Renders one inline run at its camera-dependent local size.
(define (text-span-content->pict visual span content camera)
  (define effective-font-size
    (or (text-span-font-size span) (text-visual-font-size visual)))
  (define requested-pixel-size
    (camera-length->pixels camera
                           effective-font-size))
  (define direct-pixel-size
    (min maximum-font-pixel-size
         (max minimum-font-pixel-size
              requested-pixel-size)))
  (define font
    (make-font #:size direct-pixel-size
               #:face (or (text-span-font-face span)
                           (text-visual-font-face visual))
               #:family (or (text-span-font-family span)
                            (text-visual-font-family visual))
               #:style (or (text-span-font-style span)
                            (text-visual-font-style visual))
               #:weight (or (text-span-font-weight span)
                            (text-visual-font-weight visual))
               #:size-in-pixels? #t))
  (define colored-pict
    (colorize (text content font)
              (or (text-span-color span) (text-visual-color visual))))
  (if (= direct-pixel-size requested-pixel-size)
      colored-pict
      (scale colored-pict
             (/ requested-pixel-size direct-pixel-size))))

;; text-paragraph->pict : text-visual? camera? -> pict?
;; Positions rich runs by their individual Pict baselines. The returned Pict's
;; baseline is the first line's baseline, so it can align with a neighbouring
;; formula or label through the existing anchored-pict protocol.
(define (text-paragraph->pict visual camera)
  (define maximum-width
    (and (text-visual-width visual)
         (camera-length->pixels camera (text-visual-width visual))))
  (define tokens
    (apply append
           (for/list ([span (in-list (text-visual-spans visual))])
             (text-span->layout-tokens visual span camera))))
  (define default-line-pict
    (text-span-content->pict visual
                             (text-span "")
                             ""
                             camera))
  (define lines
    (layout-text-tokens tokens maximum-width))
  (define line-picts
    (for/list ([line (in-list lines)])
      (if (null? line)
          default-line-pict
          (apply hb-append
                 (for/list ([token (in-list line)])
                   (text-layout-token-pict token))))))
  (define maximum-ascent (apply max (map pict-ascent line-picts)))
  (define maximum-descent (apply max (map pict-descent line-picts)))
  (define natural-height (+ maximum-ascent maximum-descent))
  (define line-advance (* natural-height (text-visual-line-spacing visual)))
  (define layout-width (max 1 (apply max (map pict-width line-picts))))
  (define layout-height
    (+ natural-height (* (sub1 (length line-picts)) line-advance)))
  (dc
   (lambda (drawing-context x y)
     (for ([line (in-list line-picts)]
           [index (in-naturals)])
       (draw-pict
        line
        drawing-context
        (+ x (line-layout-x (text-visual-line-alignment visual)
                            layout-width
                            (pict-width line)))
        (+ y
           (- maximum-ascent (pict-ascent line))
           (* index line-advance)))))
   layout-width
   layout-height
   maximum-ascent
   (- layout-height maximum-ascent)))

;; text-span->layout-tokens : text-visual? text-span? camera?
;;                              -> (listof text-layout-token?)
;; The token stream separates explicit line breaks, collapsible wrapping spaces,
;; and visible words without inspecting or altering Unicode word characters.
(define (text-span->layout-tokens visual span camera)
  (define content (text-span-content span))
  (define length (string-length content))
  (define tokens-reversed '())
  (define (add! kind start end)
    (define piece (substring content start end))
    (set! tokens-reversed
          (cons (text-layout-token
                 kind
                 (and (not (eq? kind 'break))
                      (text-span-content->pict visual span piece camera)))
                tokens-reversed)))
  (let loop ([index 0])
    (cond
      [(= index length) (reverse tokens-reversed)]
      [else
       (define character (string-ref content index))
       (cond
         [(or (char=? character #\return)
              (char=? character #\newline))
          (define next-index
            (if (and (char=? character #\return)
                     (< (+ index 1) length)
                     (char=? (string-ref content (+ index 1)) #\newline))
                (+ index 2)
                (+ index 1)))
          (add! 'break index next-index)
          (loop next-index)]
         [(or (char=? character #\space)
              (char=? character #\tab))
          (define next-index
            (let scan ([cursor (+ index 1)])
              (if (and (< cursor length)
                       (let ([next-character (string-ref content cursor)])
                         (or (char=? next-character #\space)
                             (char=? next-character #\tab))))
                  (scan (+ cursor 1))
                  cursor)))
          (add! 'space index next-index)
          (loop next-index)]
         [else
          (define next-index
            (let scan ([cursor (+ index 1)])
              (if (and (< cursor length)
                       (let ([next-character (string-ref content cursor)])
                         (not (or (char=? next-character #\return)
                                  (char=? next-character #\newline)
                                  (char=? next-character #\space)
                                  (char=? next-character #\tab)))))
                  (scan (+ cursor 1))
                  cursor)))
          (add! 'word index next-index)
          (loop next-index)])])))

;; layout-text-tokens : (listof text-layout-token?) (or/c false/c real?)
;;                       -> (listof (listof text-layout-token?))
;; Explicit line breaks are always retained. When a maximum width is supplied,
;; word wrapping avoids leading/trailing inter-word whitespace but does not
;; hyphenate or split an overlong word.
(define (layout-text-tokens tokens maximum-width)
  (define lines-reversed '())
  (define current '())
  (define current-width 0)
  (define (flush!)
    (define settled
      (if maximum-width
          (trim-trailing-space current)
          current))
    (set! lines-reversed (cons settled lines-reversed))
    (set! current '())
    (set! current-width 0))
  (define (append-token! token)
    (set! current (append current (list token)))
    (set! current-width (+ current-width (pict-width (text-layout-token-pict token)))))
  (define (line-has-word?)
    (for/or ([token (in-list current)])
      (eq? (text-layout-token-kind token) 'word)))
  (for ([token (in-list tokens)])
    (case (text-layout-token-kind token)
      [(break) (flush!)]
      [(space)
       (when (or (not maximum-width) (pair? current))
         (append-token! token))]
      [(word)
       (define candidate-width
         (+ current-width (pict-width (text-layout-token-pict token))))
       (when (and maximum-width
                  (line-has-word?)
                  (> candidate-width maximum-width))
         (flush!))
       (append-token! token)]))
  (flush!)
  (reverse lines-reversed))

(define (trim-trailing-space tokens)
  (reverse
   (let loop ([remaining (reverse tokens)])
     (cond
       [(and (pair? remaining)
             (eq? (text-layout-token-kind (car remaining)) 'space))
        (loop (cdr remaining))]
       [else remaining]))))

(define (line-layout-x alignment layout-width line-width)
  (case alignment
    [(left) 0]
    [(center) (/ (- layout-width line-width) 2)]
    [(right) (- layout-width line-width)]))

(define (text-string-has-line-break? value)
  (for/or ([character (in-string value)])
    (or (char=? character #\return)
        (char=? character #\newline))))

;;;
;;; Path Conversion
;;;

; path-visual->pict : path-visual? camera? -> pict?
;;   Converts local path geometry to an anchor-centered Pict.
(define (path-visual->pict visual camera)
  (define pixel-geometry
    (path-visual->pixel-geometry visual camera))
  (if (path-geometry-empty? pixel-geometry)
      (empty-path-pict)
      (begin
        (check-default-pict-stroke-width
         'path-visual->pict
         (path-visual-stroke-width visual))
        (let-values ([(half-width half-height)
                      (path-pict-half-extents pixel-geometry
                                              (path-visual-stroke-width visual))])
          (define width
            (* 2 half-width))
          (define height
            (* 2 half-height))
          (dc (lambda (drawing-context x y)
                (draw-path-geometry! drawing-context
                                     pixel-geometry
                                     (+ x half-width)
                                     (+ y half-height)
                                     (path-visual-fill visual)
                                     (path-visual-stroke visual)
                                     (path-visual-stroke-width visual)))
              width
              height)))))

; arrow-path-visual->pict : path-visual? camera? -> pict?
;;   Draws arrow geometry like a normal path except that the closed triangular
;;   tips receive fill only.  An outlined, acute triangular tip uses a miter
;;   join whose visible apex can overshoot the arrow's semantic endpoint.
(define (arrow-path-visual->pict visual camera)
  (define pixel-geometry
    (path-visual->pixel-geometry visual camera))
  (if (path-geometry-empty? pixel-geometry)
      (empty-path-pict)
      (begin
        (check-default-pict-stroke-width
         'arrow-path-visual->pict
         (path-visual-stroke-width visual))
        (let-values ([(half-width half-height)
                      (path-pict-half-extents pixel-geometry
                                              (path-visual-stroke-width visual))])
          (define width
            (* 2 half-width))
          (define height
            (* 2 half-height))
          (dc (lambda (drawing-context x y)
                (draw-arrow-path-geometry!
                 drawing-context
                 pixel-geometry
                 (+ x half-width)
                 (+ y half-height)
                 (path-visual-stroke visual)
                 (path-visual-stroke-width visual)))
              width
              height)))))

; path-visual->pixel-geometry : path-visual? camera? -> path-geometry?
;;   Applies local affine deformation and converts y-up units to y-down pixels.
(define (path-visual->pixel-geometry visual camera)
  (define transform
    (visual-transform visual))
  (define pixel-scale
    (camera-scale camera))
  (path-geometry-map-points
   (path-visual-path visual)
   (lambda (point)
     (define transformed
       (affine-transform-apply-vector transform point))
     (vec2 (* pixel-scale (vec2-x transformed))
           (* -1 pixel-scale (vec2-y transformed))))))

; path-pict-half-extents : path-geometry? nonnegative-real?
;                          -> (values positive-real? positive-real?)
;;   Returns symmetric half-extents including cosmetic stroke padding.
(define (path-pict-half-extents geometry stroke-width)
  (define-values (minimum-x minimum-y maximum-x maximum-y)
    (path-geometry-bounds geometry))
  (define stroke-padding
    (max 1 (/ stroke-width 2)))
  (values (+ (max (abs minimum-x) (abs maximum-x))
             stroke-padding)
          (+ (max (abs minimum-y) (abs maximum-y))
             stroke-padding)))

; empty-path-pict : -> pict?
;;   Creates a transparent one-pixel Pict for empty path geometry.
(define (empty-path-pict)
  (dc (lambda (_drawing-context _x _y)
        (void))
      1
      1))


;;;
;;; Semantic Color Conversion
;;;

; draw-color-spec : any/c -> any/c
;;   Converts semantic rgba-color values only at the Pict/draw adapter boundary.
;;   Existing renderer-native strings and false style sentinels pass through.
(define (draw-color-spec color)
  (define resolved
    (cond
      [(rgba-color? color) color]
      [(and (string? color) (color-spec? color))
       (color-spec->rgba-color color 'draw-color-spec)]
      [else #f]))
  (if resolved
      (make-color (color-channel->byte (rgba-color-red resolved))
                  (color-channel->byte (rgba-color-green resolved))
                  (color-channel->byte (rgba-color-blue resolved))
                  (rgba-color-alpha resolved))
      color))

; color-channel->byte : finite-real? -> byte?
;;   Quantizes one semantic sRGB channel deterministically for racket/draw.
(define (color-channel->byte channel)
  (inexact->exact (round channel)))


;;;
;;; Path Drawing Effects
;;;

; draw-path-geometry! : (is-a?/c dc<%>) path-geometry? real? real?
;                       any/c any/c nonnegative-real? -> void?
;;   Draws closed and open subpaths while restoring drawing-context state.
(define (draw-path-geometry! drawing-context
                             geometry
                             x-offset
                             y-offset
                             fill
                             stroke
                             stroke-width)
  (define old-pen
    (send drawing-context get-pen))
  (define old-brush
    (send drawing-context get-brush))
  (dynamic-wind
    void
    (lambda ()
      (draw-closed-subpaths! drawing-context
                             geometry
                             x-offset
                             y-offset
                             fill
                             stroke
                             stroke-width)
      (draw-open-subpaths! drawing-context
                           geometry
                           x-offset
                           y-offset
                           stroke
                           stroke-width))
    (lambda ()
      (send drawing-context set-pen old-pen)
      (send drawing-context set-brush old-brush))))

; draw-arrow-path-geometry! : dc<%> path-geometry? real? real? any/c
;                              nonnegative-real? -> void?
;;   Draws the normally stroked shaft followed by filled, unoutlined arrowheads.
;; The separate styling preserves a precise visible arrow tip.
(define (draw-arrow-path-geometry! drawing-context
                                   geometry
                                   x-offset
                                   y-offset
                                   stroke
                                   stroke-width)
  (define old-pen
    (send drawing-context get-pen))
  (define old-brush
    (send drawing-context get-brush))
  (dynamic-wind
    void
    (lambda ()
      (draw-open-subpaths! drawing-context
                           geometry
                           x-offset
                           y-offset
                           stroke
                           stroke-width)
      (draw-closed-subpaths! drawing-context
                             geometry
                             x-offset
                             y-offset
                             stroke
                             #f
                             0))
    (lambda ()
      (send drawing-context set-pen old-pen)
      (send drawing-context set-brush old-brush))))

; draw-closed-subpaths! : (is-a?/c dc<%>) path-geometry? real? real?
;                         any/c any/c nonnegative-real? -> void?
;;   Draws closed subpaths with odd-even fill and sharp miter joins.
(define (draw-closed-subpaths! drawing-context
                               geometry
                               x-offset
                               y-offset
                               fill
                               stroke
                               stroke-width)
  (define closed-subpaths
    (for/list ([subpath (in-list (path-geometry-subpaths geometry))]
               #:when (path-subpath-closed? subpath))
      subpath))
  (unless (null? closed-subpaths)
    (define drawing-path
      (subpaths->dc-path closed-subpaths))
    (send drawing-context
          set-pen
          (make-closed-path-pen stroke stroke-width))
    (send drawing-context set-brush (make-path-brush fill))
    (send drawing-context
          draw-path
          drawing-path
          x-offset
          y-offset
          'odd-even)))

; draw-open-subpaths! : (is-a?/c dc<%>) path-geometry? real? real?
;                       any/c nonnegative-real? -> void?
;;   Strokes open subpaths with round caps and sharp segment joins.
(define (draw-open-subpaths! drawing-context
                             geometry
                             x-offset
                             y-offset
                             stroke
                             stroke-width)
  (send drawing-context
        set-pen
        (make-open-path-pen stroke stroke-width))
  (send drawing-context set-brush (make-path-brush #f))
  (for ([subpath (in-list (path-geometry-subpaths geometry))]
        #:unless (path-subpath-closed? subpath))
    (send drawing-context
          draw-path
          (subpaths->dc-path (list subpath))
          x-offset
          y-offset
          'odd-even)))

; subpaths->dc-path : (listof path-subpath?) -> (is-a?/c dc-path%)
;;   Converts semantic line and cubic subpaths to one racket/draw path.
(define (subpaths->dc-path subpaths)
  (define drawing-path
    (new dc-path%))
  (for ([subpath (in-list subpaths)])
    (add-subpath-to-dc-path! drawing-path subpath))
  drawing-path)

; add-subpath-to-dc-path! : (is-a?/c dc-path%) path-subpath? -> void?
;;   Appends one semantic subpath to a mutable drawing path.
(define (add-subpath-to-dc-path! drawing-path subpath)
  (define start
    (path-subpath-start subpath))
  (send drawing-path move-to (vec2-x start) (vec2-y start))
  (for ([segment (in-list (path-subpath-segments subpath))])
    (add-segment-to-dc-path! drawing-path segment))
  (when (path-subpath-closed? subpath)
    (send drawing-path close)))

; add-segment-to-dc-path! : (is-a?/c dc-path%) path-segment? -> void?
;;   Appends one supported semantic segment to a mutable drawing path.
(define (add-segment-to-dc-path! drawing-path segment)
  (cond
    [(line-path-segment? segment)
     (define end
       (line-path-segment-end segment))
     (send drawing-path line-to (vec2-x end) (vec2-y end))]
    [(cubic-bezier-path-segment? segment)
     (define control1
       (cubic-bezier-path-segment-control1 segment))
     (define control2
       (cubic-bezier-path-segment-control2 segment))
     (define end
       (cubic-bezier-path-segment-end segment))
     (send drawing-path
           curve-to
           (vec2-x control1)
           (vec2-y control1)
           (vec2-x control2)
           (vec2-y control2)
           (vec2-x end)
           (vec2-y end))]
    [else
     (raise-argument-error
      'add-segment-to-dc-path!
      "supported path segment"
      segment)]))

; make-closed-path-pen : any/c nonnegative-real? -> (is-a?/c pen%)
;;   Creates a sharp closed-path pen or a transparent pen when stroke is false.
(define (make-closed-path-pen stroke stroke-width)
  (make-pen #:color (if stroke (draw-color-spec stroke) "black")
            #:width stroke-width
            #:style (if stroke 'solid 'transparent)
            #:cap 'butt
            #:join 'miter))

; make-open-path-pen : any/c nonnegative-real? -> (is-a?/c pen%)
;;   Creates a round-ended open-path pen with sharp internal joins.
(define (make-open-path-pen stroke stroke-width)
  (make-pen #:color (if stroke (draw-color-spec stroke) "black")
            #:width stroke-width
            #:style (if stroke 'solid 'transparent)
            #:cap 'round
            #:join 'miter))

; make-path-brush : any/c -> (is-a?/c brush%)
;;   Creates a solid fill brush or a transparent brush when fill is false.
(define (make-path-brush fill)
  (make-brush #:color (if fill (draw-color-spec fill) "black")
              #:style (if fill 'solid 'transparent)))



;;;
;;; Test Support
;;;

(module+ test-support
  (provide closed-path-pen-cap-and-join
           open-path-pen-cap-and-join)

  ; closed-path-pen-cap-and-join : -> (values symbol? symbol?)
  ;;   Returns the cap and join styles used for closed paths.
  (define (closed-path-pen-cap-and-join)
    (define pen
      (make-closed-path-pen "black" 2))
    (values (send pen get-cap)
            (send pen get-join)))

  ; open-path-pen-cap-and-join : -> (values symbol? symbol?)
  ;;   Returns the cap and join styles used for open paths.
  (define (open-path-pen-cap-and-join)
    (define pen
      (make-open-path-pen "black" 2))
    (values (send pen get-cap)
            (send pen get-join))))
