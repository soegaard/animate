#lang racket/base

;;;
;;; FX-G Canonical Renderer-Visible Probes
;;;

;; Every probe samples the same exact times in ascending and shuffled orders.
;; Equality is intentionally byte-for-byte on one host: these are not golden
;; images or cross-platform font assertions, but a guard against accidental
;; frame-history dependence in renderer-visible effects.

(require racket/class
         rackunit
         (only-in pict pict->bitmap)
         "../main.rkt"
         "../render.rkt")

(define probe-times '(0 1/2 1 3/2 2))
(define shuffled-probe-times '(3/2 0 2 1/2 1))

(define (bitmap-bytes bitmap)
  (define width (send bitmap get-width))
  (define height (send bitmap get-height))
  (define pixels (make-bytes (* 4 width height)))
  (send bitmap get-argb-pixels 0 0 width height pixels)
  pixels)

(define (scene-bytes scene time)
  (bitmap-bytes (pict->bitmap (scene->pict scene time) 'aligned)))

(define (check-canonical-probe label scene)
  (define ascending
    (for/hash ([time (in-list probe-times)])
      (values time (scene-bytes scene time))))
  (for ([time (in-list shuffled-probe-times)])
    (check-equal? (scene-bytes scene time)
                  (hash-ref ascending time)
                  (format "~a at ~a" label time))))

(module+ test
  (define camera
    (make-camera #:width 320 #:height 200 #:world-width 10 #:background "white"))
  (define card
    (rectangle #:id 'card #:width 3 #:height 3/2 #:fill "gold" #:stroke "sienna"))

  ;; Exact presence lifecycle.
  (check-canonical-probe
   'enter
   (scene-play (make-scene #:camera camera)
               (enter card #:translation-offset (vec2 -2 0) #:scale-factor 1/2)
               #:duration 2))
  (check-canonical-probe
   'leave
   (scene-play (scene-add (make-scene #:camera camera) card)
               (leave 'card #:translation-offset (vec2 2 0) #:scale-factor 1/2)
               #:duration 2))

  ;; Frozen local clip reveal.
  (check-canonical-probe
   'reveal-in
   (scene-play (make-scene #:camera camera)
               (reveal-in card (linear-reveal-front (vec2 1 0) #:padding 0))
               #:duration 2))

  ;; Target-writing attention plus read-only temporary overlays.
  (check-canonical-probe
   'pulse-and-ripple
   (scene-play (scene-add (make-scene #:camera camera) card)
               (animation-group
                (pulse 'card #:scale-factor 6/5 #:cycles 2)
                (ripple 'card #:rings 3 #:color "mediumorchid"))
               #:duration 2))

  ;; Source-sampled path deformation.
  (define curve
    (line (vec2 -3 0) (vec2 3 0) #:id 'curve #:stroke "teal" #:stroke-width 4))
  (check-canonical-probe
   'apply-wave
   (scene-play (scene-add (make-scene #:camera camera) curve)
               (apply-wave 'curve #:direction (vec2 0 1)
                           #:amplitude 2/5 #:phase 1/2)
               #:duration 2))

  ;; A seeded camera-offset plan changes rendered pixels but returns exactly.
  (check-canonical-probe
   'camera-shake
   (scene-play (scene-add (make-scene #:camera camera) card)
               (camera-shake #:amplitude 1/3 #:samples 6 #:seed 17)
               #:duration 2))

  ;; The Pict probe uses the documented conservative final-run subset. Rich
  ;; and wrapped partial text have dedicated capability-error tests instead of
  ;; a misleading visual approximation.
  (define caption
    (plain-text "sable text" #:id 'caption #:font-size 1/2 #:color "navy"))
  (check-canonical-probe
   'typewrite
   (scene-play (make-scene #:camera camera) (typewrite caption #:unit 'run)
               #:duration 2))

  ;; Semantic decorations are visible Pict-rendered overlays with independent
  ;; helper identities and ordinary drawing order.
  (check-canonical-probe
   'text-decorations
   (scene-play
    (scene-add (make-scene #:camera camera) caption)
    (animation-group
     (highlight-sweep 'caption #:retain? #t)
     (underline-sweep 'caption #:color "tomato")
     (strike-through 'caption #:color "mediumorchid"))
    #:duration 2))

  ;; Closed-form seed-explicit particle samples have no rendering history.
  (check-canonical-probe
   'confetti
   (scene-play (scene-add (make-scene #:camera camera) card)
               (confetti 'card #:count 20 #:seed 29 #:spread 3 #:height 3 #:gravity 5)
               #:duration 2)))
