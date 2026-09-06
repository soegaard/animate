#lang racket/base

;;;
;;; Spatial Axes and Vector Diagrams
;;;

;; Defines finite, path-stable 3D axes.  Axis captions remain ordinary 2D
;; projected labels; the invisible label anchors here give those labels stable
;; source paths without smuggling 2D Visuals into the spatial tree.


;;;
;;; Imports and Exports
;;;

(require racket/list
         "../geometry.rkt"
         "material3d.rkt"
         "mesh3d.rkt"
         "marker3d.rkt"
         "point-line-arrow3d.rkt"
         "spatial-group.rkt"
         "stroke3d.rkt"
         "transform3.rkt"
         "vec3.rkt")

(provide axes3d
         coordinate-plane3d
         grid-plane3d
         basis-vectors3d
         vector-arrow3d
         vector-components3d)


;;;
;;; Axes
;;;

; axes3d : #:id symbol? [#:x-range two-real-range?] ... -> group3d?
;;   Creates finite axes with stable children such as `(world axes x-axis)`,
;; `(world axes x-ticks)`, and `(world axes labels x)`.
(define (axes3d #:id id
                #:x-range [x-range (list -3 3)]
                #:y-range [y-range (list -3 3)]
                #:z-range [z-range (list -3 3)]
                #:tick-step [tick-step 1]
                #:tick-size [tick-size 1/12]
                #:stroke-style [stroke-style (stroke3d #:color "midnightblue" #:width 2)]
                #:arrow-style [arrow-style (arrow-style3d #:color "midnightblue")]
                #:transform [transform identity-transform3]
                #:opacity [opacity 1])
  (unless (symbol? id) (raise-argument-error 'axes3d "symbol?" id))
  (define-values (x-min x-max) (two-real-range 'axes3d x-range))
  (define-values (y-min y-max) (two-real-range 'axes3d y-range))
  (define-values (z-min z-max) (two-real-range 'axes3d z-range))
  (unless (and (finite-real? tick-step) (positive? tick-step))
    (raise-argument-error 'axes3d "positive finite tick step" tick-step))
  (unless (and (finite-real? tick-size) (positive? tick-size))
    (raise-argument-error 'axes3d "positive finite tick size" tick-size))
  (unless (stroke3d? stroke-style)
    (raise-argument-error 'axes3d "stroke3d? as #:stroke-style" stroke-style))
  (unless (arrow-style3d? arrow-style)
    (raise-argument-error 'axes3d "arrow-style3d? as #:arrow-style" arrow-style))
  (define x-axis (arrow3d (vec3 x-min 0 0) (vec3 x-max 0 0)
                          #:id 'x-axis #:shaft-style stroke-style #:tip-style arrow-style))
  (define y-axis (arrow3d (vec3 0 y-min 0) (vec3 0 y-max 0)
                          #:id 'y-axis #:shaft-style stroke-style #:tip-style arrow-style))
  (define z-axis (arrow3d (vec3 0 0 z-min) (vec3 0 0 z-max)
                          #:id 'z-axis #:shaft-style stroke-style #:tip-style arrow-style))
  (define labels
    (group3d
     (list (anchor3d 'x (vec3 (+ x-max 1/3) 0 0))
           (anchor3d 'y (vec3 0 (+ y-max 1/3) 0))
           (anchor3d 'z (vec3 0 0 (+ z-max 1/3))))
     #:id 'labels))
  (group3d
   (list x-axis y-axis z-axis
         (ticks3d 'x-ticks 'x x-min x-max tick-step tick-size stroke-style)
         (ticks3d 'y-ticks 'y y-min y-max tick-step tick-size stroke-style)
         (ticks3d 'z-ticks 'z z-min z-max tick-step tick-size stroke-style)
         labels)
   #:id id #:transform transform #:opacity opacity))


;;;
;;; Planes and Grids
;;;

; coordinate-plane3d : (or/c 'xy 'xz 'yz) #:id symbol? ... -> mesh3d?
;;   Creates a double-sided finite rectangular coordinate plane.
(define (coordinate-plane3d plane
                            #:id id
                            #:u-range [u-range (list -3 3)]
                            #:v-range [v-range (list -3 3)]
                            #:color [color "lightsteelblue"]
                            #:transform [transform identity-transform3]
                            #:opacity [opacity 1])
  (check-plane 'coordinate-plane3d plane)
  (unless (symbol? id) (raise-argument-error 'coordinate-plane3d "symbol?" id))
  (define-values (u-min u-max) (two-real-range 'coordinate-plane3d u-range))
  (define-values (v-min v-max) (two-real-range 'coordinate-plane3d v-range))
  (mesh3d
   #:id id
   #:vertices (vector (plane-point plane u-min v-min)
                      (plane-point plane u-max v-min)
                      (plane-point plane u-max v-max)
                      (plane-point plane u-min v-max))
   #:triangles (vector (vector 0 1 2) (vector 0 2 3))
   #:material (material3d #:color color #:shading 'unlit #:double-sided? #t)
   #:transform transform #:opacity opacity
   #:wireframe-color color #:wireframe-width 1))

; grid-plane3d : (or/c 'xy 'xz 'yz) #:id symbol? ... -> group3d?
;;   Creates finite screen-stroke grid curves at deterministic step locations.
(define (grid-plane3d plane
                      #:id id
                      #:u-range [u-range (list -3 3)]
                      #:v-range [v-range (list -3 3)]
                      #:step [step 1]
                      #:style [style (stroke3d #:color "lightsteelblue" #:width 1)]
                      #:transform [transform identity-transform3]
                      #:opacity [opacity 1])
  (check-plane 'grid-plane3d plane)
  (unless (symbol? id) (raise-argument-error 'grid-plane3d "symbol?" id))
  (define-values (u-min u-max) (two-real-range 'grid-plane3d u-range))
  (define-values (v-min v-max) (two-real-range 'grid-plane3d v-range))
  (unless (and (finite-real? step) (positive? step))
    (raise-argument-error 'grid-plane3d "positive finite step" step))
  (unless (stroke3d? style)
    (raise-argument-error 'grid-plane3d "stroke3d? as #:style" style))
  (define u-lines
    (for/list ([value (in-list (tick-values u-min u-max step))] [index (in-naturals)])
      (line3d (plane-point plane value v-min) (plane-point plane value v-max)
              #:id (string->symbol (format "u~a" index)) #:style style)))
  (define v-lines
    (for/list ([value (in-list (tick-values v-min v-max step))] [index (in-naturals)])
      (line3d (plane-point plane u-min value) (plane-point plane u-max value)
              #:id (string->symbol (format "v~a" index)) #:style style)))
  (group3d (append u-lines v-lines) #:id id #:transform transform #:opacity opacity))


;;;
;;; Vector Diagrams
;;;

; basis-vectors3d : #:id symbol? ... -> group3d?
;;   Creates the conventional unit vector arrows at stable paths i, j, and k.
(define (basis-vectors3d #:id id
                         #:length [length 1]
                         #:transform [transform identity-transform3]
                         #:opacity [opacity 1])
  (unless (symbol? id) (raise-argument-error 'basis-vectors3d "symbol?" id))
  (unless (and (finite-real? length) (positive? length))
    (raise-argument-error 'basis-vectors3d "positive finite length" length))
  (group3d
   (list (arrow3d origin3 (vec3 length 0 0) #:id 'i
                  #:shaft-style (stroke3d #:color "red")
                  #:tip-style (arrow-style3d #:color "red"))
         (arrow3d origin3 (vec3 0 length 0) #:id 'j
                  #:shaft-style (stroke3d #:color "forestgreen")
                  #:tip-style (arrow-style3d #:color "forestgreen"))
         (arrow3d origin3 (vec3 0 0 length) #:id 'k
                  #:shaft-style (stroke3d #:color "royalblue")
                  #:tip-style (arrow-style3d #:color "royalblue")))
   #:id id #:transform transform #:opacity opacity))

; vector-arrow3d : vec3? #:id symbol? ... -> group3d?
;;   Creates one arrow from origin (or explicit origin) to vector.
(define (vector-arrow3d vector
                        #:id id
                        #:origin [origin origin3]
                        #:shaft-style [shaft-style (stroke3d #:color "tomato")]
                        #:tip-style [tip-style (arrow-style3d #:color "tomato")]
                        #:transform [transform identity-transform3]
                        #:opacity [opacity 1])
  (unless (vec3? vector) (raise-argument-error 'vector-arrow3d "vec3?" vector))
  (unless (vec3? origin) (raise-argument-error 'vector-arrow3d "vec3?" origin))
  (arrow3d origin (vec3+ origin vector) #:id id #:shaft-style shaft-style #:tip-style tip-style
           #:transform transform #:opacity opacity))

; vector-components3d : vec3? #:id symbol? ... -> group3d?
;;   Creates orthogonal component arrows and a resultant under one stable root.
(define (vector-components3d vector
                             #:id id
                             #:origin [origin origin3]
                             #:transform [transform identity-transform3]
                             #:opacity [opacity 1])
  (unless (vec3? vector) (raise-argument-error 'vector-components3d "vec3?" vector))
  (unless (vec3? origin) (raise-argument-error 'vector-components3d "vec3?" origin))
  (define x-end (vec3+ origin (vec3 (vec3-x vector) 0 0)))
  (define y-end (vec3+ x-end (vec3 0 (vec3-y vector) 0)))
  (define end (vec3+ origin vector))
  (define components
    (filter values
            (list (and (not (zero? (vec3-x vector)))
                       (arrow3d origin x-end #:id 'x-component
                                #:shaft-style (stroke3d #:color "red")
                                #:tip-style (arrow-style3d #:color "red")))
                  (and (not (zero? (vec3-y vector)))
                       (arrow3d x-end y-end #:id 'y-component
                                #:shaft-style (stroke3d #:color "forestgreen")
                                #:tip-style (arrow-style3d #:color "forestgreen")))
                  (and (not (zero? (vec3-z vector)))
                       (arrow3d y-end end #:id 'z-component
                                #:shaft-style (stroke3d #:color "royalblue")
                                #:tip-style (arrow-style3d #:color "royalblue"))))))
  (when (zero? (vec3-length vector))
    (raise-arguments-error 'vector-components3d "a nonzero vector" "vector" vector))
  (group3d (append components
                  (list (arrow3d origin end #:id 'resultant
                                 #:shaft-style (stroke3d #:color "darkorange")
                                 #:tip-style (arrow-style3d #:color "darkorange"))))
           #:id id #:transform transform #:opacity opacity))


;;;
;;; Local Helpers
;;;

(define (anchor3d id position)
  (mesh3d #:id id #:vertices (vector origin3)
          #:transform (make-transform3 #:translation position)))

(define (ticks3d id axis minimum maximum step size style)
  (group3d
   (for/list ([value (in-list (tick-values minimum maximum step))] [index (in-naturals)])
     (define endpoints
       (case axis
         [(x) (list (vec3 value (- size) 0) (vec3 value size 0))]
         [(y) (list (vec3 (- size) value 0) (vec3 size value 0))]
         [(z) (list (vec3 (- size) 0 value) (vec3 size 0 value))]))
     (line3d (first endpoints) (second endpoints)
             #:id (string->symbol (format "t~a" index)) #:style style))
   #:id id))

(define (two-real-range who range)
  (unless (and (list? range) (= (length range) 2)
               (andmap finite-real? range) (< (first range) (second range)))
    (raise-argument-error who "two-element increasing list of finite reals" range))
  (values (first range) (second range)))

(define (tick-values minimum maximum step)
  (for/list ([value (in-range (ceiling (/ minimum step))
                              (add1 (floor (/ maximum step))))]
             #:unless (zero? value))
    (* value step)))

(define (check-plane who plane)
  (unless (memq plane '(xy xz yz))
    (raise-argument-error who "one of 'xy, 'xz, or 'yz" plane)))

(define (plane-point plane first-coordinate second-coordinate)
  (case plane
    [(xy) (vec3 first-coordinate second-coordinate 0)]
    [(xz) (vec3 first-coordinate 0 second-coordinate)]
    [(yz) (vec3 0 first-coordinate second-coordinate)]))
