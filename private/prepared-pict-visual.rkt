#lang racket/base

;; A generic prepared Pict / sampled viewport adapter, independent of slides.
;; The ordinary Pict renderer handles it; there is no second frame renderer.
(require (prefix-in p: pict)
         "affine-transform.rkt" "geometry.rkt" "visual-model.rkt" "camera.rkt")
(provide prepared-panel? prepared-pict-panel prepared-scene-panel prepared-panel->pict)
(struct prepared-panel (id transform opacity kind payload width height colors typography)
  #:transparent
  #:methods gen:visual
  [(define (visual-id v) (prepared-panel-id v))
   (define (visual-position v) (affine-transform-translation (prepared-panel-transform v)))
   (define (visual-with-position v p)
     (unless (vec2? p) (raise-argument-error 'visual-with-position "vec2?" p))
     (struct-copy prepared-panel v [transform (affine-transform-with-translation (prepared-panel-transform v) p)]))]
  #:methods gen:affine-visual
  [(define (visual-transform v) (prepared-panel-transform v))
   (define (visual-with-transform v t)
     (unless (affine-transform? t) (raise-argument-error 'visual-with-transform "affine-transform?" t))
     (struct-copy prepared-panel v [transform t]))]
  #:methods gen:opacity-visual
  [(define (visual-opacity v) (prepared-panel-opacity v))
   (define (visual-with-opacity v a)
     (unless (opacity? a) (raise-argument-error 'visual-with-opacity "opacity?" a))
     (struct-copy prepared-panel v [opacity a]))])
(define (panel kind payload width height id center colors typography)
  (unless (and (finite-real? width) (finite-real? height) (>= width 0) (>= height 0))
    (raise-argument-error 'prepared-panel "finite nonnegative dimensions" (list width height)))
  (unless (symbol? id) (raise-argument-error 'prepared-panel "symbol?" id))
  (unless (vec2? center) (raise-argument-error 'prepared-panel "vec2?" center))
  (prepared-panel id (make-affine-transform #:translation center) 1 kind payload width height colors typography))
(define (prepared-pict-panel picture #:width width #:height height #:id id #:center [center origin])
  (unless (p:pict? picture) (raise-argument-error 'prepared-pict-panel "pict?" picture))
  (panel 'pict picture width height id center #f #f))
(define (prepared-scene-panel state camera #:width width #:height height #:id id
                              #:center [center origin] #:theme theme #:typography typography)
  (panel 'scene (cons state camera) width height id center theme typography))
(define (prepared-panel->pict v camera render-scene-state)
  (define picture
    (case (prepared-panel-kind v)
      [(pict) (prepared-panel-payload v)]
      [(scene)
       (render-scene-state (car (prepared-panel-payload v))
                           #:camera (cdr (prepared-panel-payload v))
                           #:theme (prepared-panel-colors v)
                           #:typography (prepared-panel-typography v))]))
  (define scale (visual-scale v))
  (define width (* (camera-scale camera) (prepared-panel-width v) (vec2-x scale)))
  (define height (* (camera-scale camera) (prepared-panel-height v) (vec2-y scale)))
  (define fitted (p:scale picture
                          (if (= (p:pict-width picture) 0) 1 (/ width (p:pict-width picture)))
                          (if (= (p:pict-height picture) 0) 1 (/ height (p:pict-height picture)))))
  (if (= (visual-rotation v) 0) fitted (p:rotate fitted (visual-rotation v))))
