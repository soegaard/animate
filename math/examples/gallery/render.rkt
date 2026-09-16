#lang racket/base

;;;
;;; Native Mathematical Gallery Assembly
;;;
;; Prepares each view independently and appends ordinary mathematical clips to one
;; native Animate scene. Inspectors are compiled once, never updated from prior frames.

;;;
;;; Imports and Exports
;;;
(require (only-in racket/list append-map take)
         (only-in racket/string string-join)
         "../../main.rkt" "../../private/native.rkt"
         "../../private/prepare.rkt" "../../private/typeset-model.rkt"
         (only-in "../../private/animate-adapter.rkt" append-prepared-math-plan!)
         "model.rkt")
(provide prepare-gallery-views! prepare-gallery-view! build-gallery-scene!
         make-gallery-camera! gallery-top-margin gallery-view-key)

; gallery-top-margin : exact-positive-rational?
;;   Reserves native title/context/definition lines plus the gallery caption/API band.
(define gallery-top-margin 53/20)

; gallery-view-key : gallery-entry? -> (listof symbol?)
;;   Identifies a replay independently of the selected subset and worker assignment.
(define (gallery-view-key entry)
  (list (gallery-plate-id (gallery-entry-plate entry))
        (gallery-view-id (gallery-entry-view entry))))

; make-gallery-camera! : exact-positive-integer? exact-positive-integer? symbol? -> camera?
;;   Constructs the one static native camera used for preparation and output.
(define (make-gallery-camera! width height theme)
  (define-values (_foreground background) (theme-colors theme))
  ((native 'animate 'make-camera) #:width width #:height height #:background background))

; fit-gallery-preparation : prepared-math-plan? boolean? -> prepared-math-plan?
;;   Reserves caption/footer space and, for hierarchy plates, a separate inspector column.
(define (fit-gallery-preparation prepared tree?)
  (define layouts (prepared-math-plan-layouts prepared))
  (define camera (prepared-math-plan-camera prepared))
  (define world-width ((native 'animate 'camera-world-width) camera))
  (define world-height (* world-width (/ ((native 'animate 'camera-height) camera)
                                        ((native 'animate 'camera-width) camera))))
  (define tokens (append-map prepared-layout-tokens (hash-values layouts)))
  (define xmin (apply min (map (lambda (t) (- (prepared-token-x t) (/ (prepared-token-width t) 2))) tokens)))
  (define xmax (apply max (map (lambda (t) (+ (prepared-token-x t) (/ (prepared-token-width t) 2))) tokens)))
  (define available-width (if tree? (* world-width 1/2) (- world-width 7/5)))
  (define scale (min 1 (/ available-width (max 1/10 (- xmax xmin)))))
  (define dx (if tree? (- (* world-width 1/6) (* scale (/ (+ xmin xmax) 2))) 0))
  (define fitted
    (for/hash ([(state layout) (in-hash layouts)])
      (values state (struct-copy prepared-layout layout
                      [tokens (map (lambda (t) (token-scaled t scale dx))
                                   (prepared-layout-tokens layout))]))))
  ;; Each formula row may extend on both sides of its reference baseline.
  (define max-height
    (apply max
      (for/list ([layout (in-hash-values fitted)])
        (define ts (prepared-layout-tokens layout))
        (- (apply max (map (lambda (t) (+ (prepared-token-y t) (/ (prepared-token-height t) 2))) ts))
           (apply min (map (lambda (t) (- (prepared-token-y t) (/ (prepared-token-height t) 2))) ts))))))
  (define gap (max (prepared-math-plan-row-gap prepared) (+ max-height 1/4)))
  (define count (max 2 (min 3 (add1 (inexact->exact
                                     (floor (/ (max 0 (- world-height gallery-top-margin 2)) gap)))))))
  (struct-copy prepared-math-plan prepared [layouts fitted] [max-rows count] [row-gap gap]))

; prepare-gallery-view! : gallery-entry? camera? symbol? -> prepared-math-plan?
;;   Typesets one complete replay once, independent of other plates and worker count.
(define (prepare-gallery-view! entry camera theme)
  (fit-gallery-preparation
    (prepare-math-plan! (gallery-view-plan (gallery-entry-view entry)) #:camera camera #:theme theme)
    (gallery-view-tree? (gallery-entry-view entry))))

; prepare-gallery-views! : (listof gallery-entry?) camera? symbol? -> list?
;;   Prepares the selected replays in stable catalogue order in the parent only.
(define (prepare-gallery-views! entries camera theme)
  (for/list ([entry (in-list entries)]) (prepare-gallery-view! entry camera theme)))

; text-visual! : string? symbol? real? real? positive-real? string? positive-real? -> visual?
;;   Creates a bounded caption or inspector line using native plain text.
(define (text-visual! text id x y size color width)
  ((native 'animate 'plain-text) text #:id id #:center ((native 'animate 'vec2) x y)
    #:font-size (min size (/ width (max 1 (* 3/5 (string-length text))))) #:color color))

; tree-lines : derivation? -> (listof (cons/c list? string?))
;;   Flattens the semantic hierarchy solely for a small compile-time inspector.
;;   Indentation is handled geometrically by the renderer rather than by leading
;;   spaces, so every label can remain left-aligned and readable.
(define (tree-lines derivation)
  (define (walk node)
    (define path (derivation-node-path node))
    (cons (cons path (symbol->string (car (reverse path))))
          (append-map walk (derivation-node-children node))))
  (append-map walk (derivation-tree derivation)))

; tree-line-visual! : string? symbol? real? real? nonnegative-integer?
;   positive-real? string? positive-real? boolean? -> visual?
;;   Creates one left-aligned hierarchy row with explicit indentation and a
;;   fixed marker column so the active path is easy to scan.
(define (tree-line-visual! label id left y depth size color total-width active?)
  (define marker (if active? "▸" "·"))
  (define indent-step 9/25)
  (define marker-width 3/10)
  (define text-left (+ left marker-width (* depth indent-step)))
  (define text-width (max 9/10 (- total-width marker-width (* depth indent-step))))
  (define row-text (string-append marker " " label))
  (define font-size (min size (/ text-width (max 1 (* 3/5 (string-length row-text))))))
  (define used-width (min text-width (* font-size 3/5 (string-length row-text))))
  ((native 'animate 'plain-text) row-text #:id id
   #:center ((native 'animate 'vec2) (+ text-left (/ used-width 2)) y)
   #:font-size font-size #:color color))

; active-path? : list? (or/c #f symbol? list?) -> boolean?
;;   Highlights a current leaf and its containing moves, never inferring glyph matches.
(define (active-path? path key)
  (define target (if (symbol? key) (list key) key))
  (and target (<= (length path) (length target)) (equal? path (take target (length path)))))

; build-gallery-scene! : (listof gallery-entry?) (listof prepared-math-plan?)
;   camera? [#:show-api? boolean?] -> scene?
;;   Appends independent prepared replays through the existing native compiler and cleans ids.
(define (build-gallery-scene! entries preparations camera #:show-api? [show-api? #f])
  (unless (and (= (length entries) (length preparations)) (pair? entries))
    (raise-arguments-error 'build-gallery-scene! "one preparation per selected view"
                           "entries" (length entries) "preparations" (length preparations)))
  (define scn ((native 'animate 'make-scene) #:camera camera))
  (define width ((native 'animate 'camera-world-width) camera))
  (define height (* width (/ ((native 'animate 'camera-height) camera)
                             ((native 'animate 'camera-width) camera))))
  (for ([entry (in-list entries)] [prepared (in-list preparations)])
    (define view (gallery-entry-view entry))
    (unless (and (equal? camera (prepared-math-plan-camera prepared))
                 (equal? (gallery-view-plan view) (prepared-math-plan-plan prepared)))
      (raise-arguments-error 'build-gallery-scene! "matching view and prepared camera/plan"
                             "view" (gallery-view-key entry)))
    (define plate (gallery-entry-plate entry))
    (define id (string->symbol (format "gallery.~a.~a" (gallery-plate-id plate) (gallery-view-id view))))
    (define foreground (prepared-math-plan-foreground prepared))
    (define caption-id (string->symbol (format "~a.caption" id)))
    (define api-id (string->symbol (format "~a.api" id)))
    (define tree-ids '())
    (define on-step
      (and (gallery-view-tree? view)
        (lambda (scene segment-index key)
          (define cleared (if (null? tree-ids) scene
                              (apply (native 'animate 'scene-remove) scene tree-ids)))
          (define d (plan-segment-derivation
                     (list-ref (presentation-plan-segments (gallery-view-plan view)) segment-index)))
          (define lines (tree-lines d))
          (set! tree-ids
                (for/list ([line (in-list lines)] [i (in-naturals)])
                  (string->symbol (format "~a.tree.~a" id i))))
          (define tree-left (+ (- (/ width 2)) 2/5))
          (define tree-width (- (* width 19/50) 2/5))
          (apply (native 'animate 'scene-add) cleared
            (for/list ([line (in-list lines)] [line-id (in-list tree-ids)] [i (in-naturals)])
              (define path (car line))
              (define label (cdr line))
              (tree-line-visual! label
                                 line-id
                                 tree-left
                                 (- (/ height 2) gallery-top-margin (* i 7/25))
                                 (sub1 (length path))
                                 17/100
                                 foreground
                                 tree-width
                                 (equal? path (if (symbol? key) (list key) key))))))))
    (set! scn ((native 'animate 'scene-add) scn
                (text-visual! (gallery-view-caption view) caption-id 0 (- (/ height 2) 8/5)
                              9/50 foreground (- width 7/5))))
    (when show-api?
      (set! scn ((native 'animate 'scene-add) scn
                  (text-visual! (string-append "API: " (string-join (map symbol->string (gallery-view-api view)) "  "))
                                api-id 0 (- (/ height 2) 39/20) 3/20 foreground (- width 7/5)))))
    (define title (if (string=? (gallery-view-title view) "") (gallery-plate-title plate)
                      (string-append (gallery-plate-title plate) " — " (gallery-view-title view))))
    (define-values (next owned checkpoint)
      (append-prepared-math-plan! scn prepared #:title title #:id id
                                 #:top-margin gallery-top-margin #:on-step on-step))
    (set! scn ((native 'animate 'scene-wait) next gallery-settle-time))
    (set! scn (apply (native 'animate 'scene-remove) scn
                     (append owned tree-ids (list caption-id) (if show-api? (list api-id) '()))))
    (set! scn ((native 'animate 'scene-remove-value) scn checkpoint))
    (set! scn ((native 'animate 'scene-wait) scn gallery-gap-time)))
  scn)
