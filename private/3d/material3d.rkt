#lang racket/base

;;; 3D Materials

(require "../color-style.rkt"
         (only-in "../color-token.rkt" theme-surface)
         "../geometry.rkt")

(provide material3d
         material3d?
         material3d-color
         material3d-shading
         material3d-ambient
         material3d-diffuse
         material3d-specular
         material3d-specular-color
         material3d-roughness
         material3d-specular-exponent
         material3d-lighting
         material3d-emission
         material3d-emission-strength
         material3d-double-sided?
         material3d-casts-shadow?
         material3d-receives-shadow?
         material3d-wireframe?
         material3d-with-color
         material3d-with-roughness
         material3d-with-emission
         material3d-with-shadow-policy
         default-material3d)

;; Material values are deliberately renderer independent.  Authored colour
;; specifications stay unresolved until a renderer prepares them against an
;; explicit theme snapshot.  Alpha belongs to that prepared material colour;
;; SCENE-3D-I's renderer decides how translucent triangles are sorted and
;; composited rather than baking a backend policy into the model.
(struct material3d-value
  (color shading lighting ambient diffuse specular specular-color roughness
         emission emission-strength double-sided? casts-shadow? receives-shadow? wireframe?)
  #:transparent)

(define material3d? material3d-value?)
(define material3d-color material3d-value-color)
(define material3d-shading material3d-value-shading)
(define material3d-ambient material3d-value-ambient)
(define material3d-diffuse material3d-value-diffuse)
(define material3d-specular material3d-value-specular)
(define material3d-specular-color material3d-value-specular-color)
(define material3d-roughness material3d-value-roughness)
(define material3d-lighting material3d-value-lighting)
(define material3d-emission material3d-value-emission)
(define material3d-emission-strength material3d-value-emission-strength)
(define material3d-double-sided? material3d-value-double-sided?)
(define material3d-casts-shadow? material3d-value-casts-shadow?)
(define material3d-receives-shadow? material3d-value-receives-shadow?)
(define material3d-wireframe? material3d-value-wireframe?)

(define omitted-material-field (gensym 'omitted-material-field))

; material3d : [#:color color-spec?] [#:shading (or/c 'unlit 'flat 'smooth)]
;              [#:ambient nonnegative-finite-real?]
;              [#:diffuse nonnegative-finite-real?]
;              [#:lighting (or/c 'lambert 'blinn-phong)]
;              [#:ambient nonnegative-finite-real?]
;              [#:diffuse nonnegative-finite-real?]
;              [#:specular nonnegative-finite-real?] [#:specular-color color-spec?]
;              [#:roughness finite-real-in-(0,1]?]
;              [#:emission color-spec?] [#:emission-strength nonnegative-finite-real?]
;              [#:double-sided? boolean?] [#:casts-shadow? boolean?]
;              [#:receives-shadow? boolean?] [#:wireframe? boolean?]
;              -> material3d?
;; Creates one renderer-independent surface material. `shading` chooses normal
;; interpolation; `lighting` chooses the illumination equation for lit modes.
(define (material3d #:color [color theme-surface]
                    #:shading [shading 'flat]
                    #:lighting [lighting 'lambert]
                    #:ambient [ambient 1]
                    #:diffuse [diffuse 1]
                    #:specular [specular 0]
                    #:specular-color [specular-color "white"]
                    #:roughness [roughness 1]
                    #:emission [emission "black"]
                    #:emission-strength [emission-strength 0]
                    #:double-sided? [double-sided? #f]
                    #:casts-shadow? [casts-shadow? #t]
                    #:receives-shadow? [receives-shadow? #t]
                    #:wireframe? [wireframe? #f])
  (unless (color-spec? color)
    (raise-argument-error 'material3d "color-spec?" color))
  (unless (memq shading '(unlit flat smooth))
    (raise-argument-error 'material3d "(or/c 'unlit 'flat 'smooth)" shading))
  (unless (memq lighting '(lambert blinn-phong))
    (raise-argument-error 'material3d "(or/c 'lambert 'blinn-phong)" lighting))
  (for ([value (in-list (list ambient diffuse specular emission-strength))]
        [name (in-list '(ambient diffuse specular emission-strength))])
    (unless (and (finite-real? value) (>= value 0))
      (raise-arguments-error 'material3d "nonnegative finite coefficients"
                             "coefficient" name "value" value)))
  (unless (and (finite-real? roughness) (positive? roughness) (<= roughness 1))
    (raise-argument-error 'material3d "finite real in (0, 1] as roughness" roughness))
  (for ([value (in-list (list specular-color emission))]
        [name (in-list '(specular-color emission))])
    (unless (color-spec? value)
      (raise-arguments-error 'material3d "color-spec? values"
                             "field" name "value" value)))
  (unless (boolean? double-sided?)
    (raise-argument-error 'material3d "boolean?" double-sided?))
  (unless (boolean? casts-shadow?)
    (raise-argument-error 'material3d "boolean?" casts-shadow?))
  (unless (boolean? receives-shadow?)
    (raise-argument-error 'material3d "boolean?" receives-shadow?))
  (unless (boolean? wireframe?)
    (raise-argument-error 'material3d "boolean?" wireframe?))
  (material3d-value (normalize-color-spec color 'material3d)
                    shading lighting ambient diffuse specular
                    (normalize-color-spec specular-color 'material3d) roughness
                    (normalize-color-spec emission 'material3d) emission-strength
                    double-sided? casts-shadow? receives-shadow? wireframe?))

;; material3d-specular-exponent : material3d? -> positive-real?
;; The mapping is deliberately kept in the authoring model so the CPU and GPU
;; cannot evolve different interpretations of roughness.
(define (material3d-specular-exponent material)
  (unless (material3d? material)
    (raise-argument-error 'material3d-specular-exponent "material3d?" material))
  (define roughness (material3d-roughness material))
  (max 1 (- (/ 2 (* roughness roughness)) 2)))

(define (copy-material material
                       #:color [color (material3d-color material)]
                       #:shading [shading (material3d-shading material)]
                       #:lighting [lighting (material3d-lighting material)]
                       #:ambient [ambient (material3d-ambient material)]
                       #:diffuse [diffuse (material3d-diffuse material)]
                       #:specular [specular (material3d-specular material)]
                       #:specular-color [specular-color (material3d-specular-color material)]
                       #:roughness [roughness (material3d-roughness material)]
                       #:emission [emission (material3d-emission material)]
                       #:emission-strength [emission-strength (material3d-emission-strength material)]
                       #:double-sided? [double-sided? (material3d-double-sided? material)]
                       #:casts-shadow? [casts-shadow? (material3d-casts-shadow? material)]
                       #:receives-shadow? [receives-shadow? (material3d-receives-shadow? material)]
                       #:wireframe? [wireframe? (material3d-wireframe? material)])
  (material3d #:color color #:shading shading #:lighting lighting
              #:ambient ambient #:diffuse diffuse #:specular specular
              #:specular-color specular-color #:roughness roughness
              #:emission emission #:emission-strength emission-strength
              #:double-sided? double-sided? #:casts-shadow? casts-shadow?
              #:receives-shadow? receives-shadow? #:wireframe? wireframe?))

(define (material3d-with-color material color)
  (unless (material3d? material)
    (raise-argument-error 'material3d-with-color "material3d?" material))
  (copy-material material #:color color))

(define (material3d-with-roughness material roughness)
  (unless (material3d? material)
    (raise-argument-error 'material3d-with-roughness "material3d?" material))
  (copy-material material #:roughness roughness))

(define (material3d-with-emission material emission
                                  #:strength [strength omitted-material-field])
  (unless (material3d? material)
    (raise-argument-error 'material3d-with-emission "material3d?" material))
  (copy-material material #:emission emission
                 #:emission-strength
                 (if (eq? strength omitted-material-field)
                     (material3d-emission-strength material)
                     strength)))

(define (material3d-with-shadow-policy material
                                       #:casts-shadow? [casts-shadow? omitted-material-field]
                                       #:receives-shadow? [receives-shadow? omitted-material-field])
  (unless (material3d? material)
    (raise-argument-error 'material3d-with-shadow-policy "material3d?" material))
  (copy-material
   material
   #:casts-shadow? (if (eq? casts-shadow? omitted-material-field)
                        (material3d-casts-shadow? material)
                        casts-shadow?)
   #:receives-shadow? (if (eq? receives-shadow? omitted-material-field)
                           (material3d-receives-shadow? material)
                           receives-shadow?)))

(define default-material3d (material3d))
