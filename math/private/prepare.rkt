#lang racket/base

;;;
;;; Lesson Layout Preparation
;;;
;; Prepares and fits complete formula artifacts with an explicit native camera.
;; Typesetting and cached assets stay behind this effect boundary.
;;;
;;; Imports and Exports
;;;
;; Imports
(require
  (only-in racket/list append-map argmin remove-duplicates)
  "native.rkt"
  "typeset.rkt"
  "prepared-plan-model.rkt"
  "datum.rkt"
  "model.rkt"
  "derivation.rkt"
  "presentation.rkt"
  "validation.rkt")

;; Exports
(provide prepare-math-plan! theme-colors current-math-preparation-observer
         (struct-out prepared-math-plan))

;;;
;;; Construction and Operations
;;;
; animate-binding : symbol? -> any/c
;;   Resolves a native animate binding at the adapter boundary.
(define (animate-binding name)
  (native 'animate name))

; theme-colors : symbol? -> (values string? string?)
;;   Selects the explicit foreground and background for the supported light or dark
;;   theme.
(define (theme-colors theme)
  (case theme
    [(light) (values "#171B24" "#FFFFFF")]
    [(dark) (values "#F1F3F8" "#121620")]
    [else (raise-argument-error 'animate/math "'light or 'dark" theme)]))

; default-math-preparation-observer : presentation-plan? -> void?
;;   Is silent except for the opt-in native integration event log.  Child
;;   builders inherit the environment, so an unexpected preparation in a child
;;   is visible to the same focused test evidence as parent preparation.
(define (default-math-preparation-observer plan)
  (define event-log (getenv "ANIMATE_MATH_PREPARATION_EVENT_LOG"))
  (when event-log
    (call-with-output-file event-log
      #:exists 'append
      (lambda (out)
        (fprintf out "~s ~a\n"
                 (presentation-plan-style plan)
                 (length (math-preparation-states plan))))))
  (void))

; current-math-preparation-observer : (parameter/c (presentation-plan? . -> . any/c))
;;   Instruments one complete lesson-preparation invocation for focused tests.
(define current-math-preparation-observer
  (make-parameter default-math-preparation-observer
    (lambda (observer)
      (check-procedure 'current-math-preparation-observer observer 1))))

; anchor-layout : symbol? symbol? -> prepared-layout?
;;   Anchors prepared parts to a relation sign without changing their mathematical
;;   owners.
(define (anchor-layout layout anchor)
  (define tokens (prepared-layout-tokens layout))
  (define eqs (filter (lambda (t) (eq? (prepared-token-role t) 'relation)) tokens))
  (define reference (and (eq? anchor 'relation) (pair? eqs) (argmin prepared-token-x eqs)))
  (define dx (if reference (- (prepared-token-x reference)) 0))
  (define dy (if reference (- (prepared-token-y reference)) 0))
  (struct-copy prepared-layout layout
    [tokens
     (map
       (lambda (t)
         (token-with-position t (+ dx (prepared-token-x t)) (+ dy (prepared-token-y t))))
       tokens)]))

;;;
;;; Effectful Lesson Preparation
;;;
; prepare-math-plan! : presentation-plan? [#:camera any/c] [#:theme symbol?]
;   [#:cache-directory path-string?] -> prepared-math-plan?
;;   Typesets and measures all checkpoints before native scene construction or sampling.
(define (prepare-math-plan! plan
          #:camera [camera #f]
          #:theme [theme 'light]
          #:cache-directory [cache-directory default-math-cache-directory])
  (unless (presentation-plan? plan)
    (raise-argument-error 'prepare-math-plan! "presentation-plan?" plan))
  ((current-math-preparation-observer) plan)
  (define-values (foreground background) (theme-colors theme))
  (define cam (or camera ((animate-binding 'make-camera) #:background background)))
  (define style (presentation-plan-style plan))
  (define schedule (plan-schedule plan))
  (define ordered-states (math-preparation-states plan))
  (define cache (make-hash))
  (define layouts0
    (for/hash ([state (in-list ordered-states)])
      (define template
        (hash-ref! cache
          (math-datum state)
          (lambda ()
            (anchor-layout
              (typeset-state! state
                #:font-size (presentation-style-font-size style)
                #:multiplication (presentation-style-multiplication style)
                #:foreground foreground
                #:cache-directory cache-directory)
              (presentation-style-anchor style)))))
      (values state (struct-copy prepared-layout template [state state]))))
  (define all-tokens
    (append-map
      (lambda (state) (prepared-layout-tokens (hash-ref layouts0 state)))
      ordered-states))
  (define xmin
    (apply min
      (map (lambda (t) (- (prepared-token-x t) (/ (prepared-token-width t) 2))) all-tokens)))
  (define xmax
    (apply max
      (map (lambda (t) (+ (prepared-token-x t) (/ (prepared-token-width t) 2))) all-tokens)))
  (define world-width ((animate-binding 'camera-world-width) cam))
  (unless (> world-width 7/5)
    (raise-arguments-error 'prepare-math-plan!
      "camera world width must exceed the 7/5 layout margin"
      "world-width"
      world-width))
  (define scale (min 1 (/ (- world-width 7/5) (max 1/10 (- xmax xmin)))))
  (define dx (* (- (/ (+ xmin xmax) 2)) scale))
  (define layouts
    (for/hash ([(s layout) (in-hash layouts0)])
      (values s
        (struct-copy prepared-layout layout
          [tokens
           (map (lambda (t) (token-scaled t scale dx 0)) (prepared-layout-tokens layout))]))))
  (define max-height
    (apply max
      (for/list ([layout (in-hash-values layouts)])
        (define ts (prepared-layout-tokens layout))
        (-
          (apply max
            (map (lambda (t) (+ (prepared-token-y t) (/ (prepared-token-height t) 2))) ts))
          (apply min
            (map (lambda (t) (- (prepared-token-y t) (/ (prepared-token-height t) 2))) ts))))))
  (define row-gap (max (presentation-style-row-gap style) (+ max-height 1/4)))
  (define explanation-states
    (for/list ([entry (in-list schedule)]
               #:when (eq? (scheduled-phase-kind entry) 'explain))
      (car (presentation-phase-annotation (scheduled-phase-phase entry)))))
  (define world-height
    (* world-width
      (/ ((animate-binding 'camera-height) cam) ((animate-binding 'camera-width) cam))))
  (define max-rows
    (min
      (presentation-style-max-visible-rows style)
      (max 2 (add1 (inexact->exact (floor (/ (max 1 (- world-height 3 (if (pair? explanation-states) 6/5 0))) row-gap)))))))
  (prepared-math-plan plan layouts
    schedule
    cam
    foreground
    background
    row-gap
    max-rows
    (map string->immutable-string
      (append
        (if (< scale 1)
          (list (format "All formulas uniformly scaled by ~a to fit the frame." scale))
          '())
        (append-map
          (lambda (state) (prepared-layout-diagnostics (hash-ref layouts state)))
          ordered-states)))))
