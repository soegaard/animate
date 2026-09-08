#lang racket/base

;;; SCENE-3D-V10: material, light, and fragment inspection

;; This deliberately reuses the moving point-and-spot scene.  Run it in
;; GRacket, click the sphere or floor, and choose Material, Lights, or
;; Fragment probe from the Inspector section selector.  The probe is derived
;; from immutable authoring values and the exact CPU pick; it does not alter
;; the authored scene or add visible diagnostic geometry to rendered frames.

(require animate/preview
         "finite-lighting.rkt")

(provide make-demo-scene)

(module+ main
  (open-scene-preview (make-demo-scene)
                      #:title "Animate: 3D lighting inspector"))
