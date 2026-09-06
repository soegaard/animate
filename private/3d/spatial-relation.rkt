#lang racket/base

;;;
;;; First-Class Spatial Relations
;;;

;; A spatial relation is the 3D counterpart of an ordinary relation Visual.
;; It is immutable definition data: a resolver receives one current sampled
;; view3d context and returns concrete spatial geometry.  It is never a
;; frame-by-frame mutable updater.

(require "../geometry.rkt"
         "affine3.rkt"
         "bounds3.rkt"
         "material3d.rkt"
         "mesh3d.rkt"
         "rotation3.rkt"
         "spatial-dependency.rkt"
         "spatial-group.rkt"
         "spatial-relation-context.rkt"
         "spatial-visual.rkt"
         "transform3.rkt"
         "vec3.rkt")

(provide spatial-relation
         spatial-relation?
         spatial-relation-dependencies
         spatial-relation-structure
         spatial-relation-cache-key
         spatial-relation-cacheability
         resolve-spatial-relation
         line-between3d
         segment-between3d
         arrow-between3d
         plane-through3d
         normal-at3d
         distance-segment3d)

;; Preserve generic protocol bindings before the generated struct methods use
;; the same names. Without these aliases a method body would recursively apply
;; the relation accessor to its concrete template.
(define template-spatial-id spatial-id)
(define template-spatial-transform spatial-transform)
(define template-spatial-with-transform spatial-with-transform)
(define template-spatial-opacity spatial-opacity)
(define template-spatial-with-opacity spatial-with-opacity)
(define template-spatial-local-bounds spatial-local-bounds)
(define template-spatial-child-entries spatial-child-entries)
(define template-spatial-container-with-children spatial-container-with-children)

(struct spatial-relation-value
  (template outer-transform outer-opacity dependencies structure cache-key resolver)
  #:transparent
  #:methods gen:spatial-visual
  [(define (spatial-id relation)
     (template-spatial-id (spatial-relation-value-template relation)))
   (define (spatial-transform relation)
     (spatial-relation-value-outer-transform relation))
   (define (spatial-with-transform relation transform)
     (unless (transform3? transform)
       (raise-argument-error 'spatial-with-transform "transform3?" transform))
     (struct-copy spatial-relation-value relation [outer-transform transform]))
   (define (spatial-opacity relation)
     (spatial-relation-value-outer-opacity relation))
   (define (spatial-with-opacity relation opacity)
     (unless (spatial-opacity? opacity)
       (raise-argument-error
        'spatial-with-opacity "finite real in the closed unit interval" opacity))
     (struct-copy spatial-relation-value relation [outer-opacity opacity]))
   (define (spatial-local-bounds relation)
     ;; The outer transform is supplied by spatial-transform, just as it is
     ;; for a mesh or group, so local bounds remain in template coordinates.
     (template-spatial-local-bounds (spatial-relation-value-template relation)))]
  #:methods gen:spatial-container
  [(define (spatial-child-entries relation)
     ;; Only a fixed relation promises descendant identities to path lookup.
     ;; Root-only output can change shape freely and deliberately exposes none.
     (define template (spatial-relation-value-template relation))
     (if (and (eq? (spatial-relation-value-structure relation) 'fixed)
              (spatial-container? template))
         (template-spatial-child-entries template)
         '()))
   (define (spatial-container-with-children relation children)
     (unless (eq? (spatial-relation-value-structure relation) 'fixed)
       (raise-arguments-error
        'spatial-container-with-children
        "a fixed spatial relation with a declared child tree"
        "relation-id" (template-spatial-id relation)
        "structure" (spatial-relation-value-structure relation)))
     (define template (spatial-relation-value-template relation))
     (unless (spatial-container? template)
       (raise-arguments-error
        'spatial-container-with-children
        "a fixed spatial-relation template that is a spatial container"
        "relation-id" (template-spatial-id relation)))
     (struct-copy spatial-relation-value relation
                  [template (template-spatial-container-with-children template children)]))])

(define spatial-relation? spatial-relation-value?)

; spatial-relation : spatial-visual?
;                    #:depends-on (listof spatial-dependency?)
;                    #:structure (or/c 'root-only 'fixed)
;                    #:cache-key any/c
;                    (-> spatial-relation-context? spatial-visual? spatial-visual?)
;                    -> spatial-relation?
;; Creates a semantic spatial object.  `template` establishes its stable ID
;; and the transform/opacity envelope.  The resolver receives a transform-free
;; local template so an independently animated relation retains its envelope.
(define (spatial-relation template
                          #:depends-on [dependencies '()]
                          #:structure [structure 'root-only]
                          #:cache-key [cache-key #f]
                          resolver)
  (unless (spatial-visual? template)
    (raise-argument-error 'spatial-relation "spatial-visual?" template))
  (when (spatial-relation? template)
    (raise-arguments-error
     'spatial-relation
     "a concrete spatial template, not another spatial relation"
     "template" template))
  (unless (symbol? (spatial-id template))
    (raise-arguments-error
     'spatial-relation
     "a template spatial Visual with a symbol identity"
     "spatial-id" (spatial-id template)))
  (unless (list? dependencies)
    (raise-argument-error 'spatial-relation "list? as #:depends-on" dependencies))
  (for ([dependency (in-list dependencies)])
    (unless (spatial-dependency? dependency)
      (raise-argument-error
       'spatial-relation "spatial-dependency? values in #:depends-on" dependency)))
  (unless (memq structure '(root-only fixed))
    (raise-argument-error 'spatial-relation "(or/c 'root-only 'fixed)" structure))
  (when (and (eq? structure 'fixed) (not (spatial-container? template)))
    (raise-arguments-error
     'spatial-relation
     "a spatial-container? template for #:structure 'fixed"
     "template" template))
  (unless (and (procedure? resolver) (procedure-arity-includes? resolver 2))
    (raise-argument-error
     'spatial-relation
     "procedure accepting spatial-relation-context? and spatial-visual?"
     resolver))
  (define outer-transform (spatial-transform template))
  (define outer-opacity (spatial-opacity template))
  (define local-template
    (spatial-with-opacity
     (spatial-with-transform template identity-transform3)
     1))
  (spatial-relation-value local-template outer-transform outer-opacity
                          dependencies structure cache-key resolver))

(define (spatial-relation-dependencies relation)
  (check-relation 'spatial-relation-dependencies relation)
  (spatial-relation-value-dependencies relation))

(define (spatial-relation-structure relation)
  (check-relation 'spatial-relation-structure relation)
  (spatial-relation-value-structure relation))

(define (spatial-relation-cache-key relation)
  (check-relation 'spatial-relation-cache-key relation)
  (spatial-relation-value-cache-key relation))

; spatial-relation-cacheability : spatial-relation?
;                                -> (or/c 'explicit-key 'disabled)
;; A generic procedure is opaque process-local code.  It becomes cacheable
;; across render workers only when the author supplies an explicit stable key.
(define (spatial-relation-cacheability relation)
  (check-relation 'spatial-relation-cacheability relation)
  (if (spatial-relation-value-cache-key relation) 'explicit-key 'disabled))

; resolve-spatial-relation : spatial-relation? spatial-relation-context?
;                            -> spatial-visual?
;; Runs and validates one resolver, then restores the current independent
;; outer transform/opacity envelope.
(define (resolve-spatial-relation relation context)
  (check-relation 'resolve-spatial-relation relation)
  (unless (spatial-relation-context? context)
    (raise-argument-error 'resolve-spatial-relation
                          "spatial-relation-context?" context))
  (define template (spatial-relation-value-template relation))
  (define result ((spatial-relation-value-resolver relation) context template))
  (unless (spatial-visual? result)
    (raise-arguments-error
     'resolve-spatial-relation
     "a spatial relation resolver must return a spatial Visual"
     "spatial-id" (spatial-id template)
     "result" result))
  (when (spatial-tree-has-relation? result)
    (raise-arguments-error
     'resolve-spatial-relation
     "a concrete spatial result, not a nested spatial relation"
     "spatial-id" (spatial-id template)
     "result" result))
  (unless (eq? (spatial-id result) (spatial-id template))
    (raise-arguments-error
     'resolve-spatial-relation
     "the resolved spatial relation must preserve its template spatial ID"
     "expected spatial-id" (spatial-id template)
     "resolved spatial-id" (spatial-id result)))
  (when (and (eq? (spatial-relation-value-structure relation) 'fixed)
             (not (equal? (spatial-tree-signature template)
                          (spatial-tree-signature result))))
    (raise-arguments-error
     'resolve-spatial-relation
     "a fixed spatial relation result with exactly the template child-ID tree"
     "spatial-id" (spatial-id template)
     "expected tree" (spatial-tree-signature template)
     "result tree" (spatial-tree-signature result)))
  (apply-spatial-relation-envelope relation result))

(define (apply-spatial-relation-envelope relation result)
  (define outer (spatial-relation-value-outer-transform relation))
  (define local (spatial-transform result))
  ;; Like the 2D relation envelope, this is an author-oriented composition:
  ;; translate, rotate, and componentwise scale keep their ordinary animation
  ;; semantics.  Arbitrary affine shear remains intentionally outside
  ;; transform3's decomposed public model.
  (define composed
    (make-transform3
     #:translation
     (affine3-apply-point
      (transform3->affine3 outer)
      (transform3-translation local))
     #:rotation
     (rotation3-compose (transform3-rotation outer)
                        (transform3-rotation local))
     #:scale
     (vec3* (transform3-scale outer) (transform3-scale local))))
  (define enveloped (spatial-with-transform result composed))
  (define opaque
    (spatial-with-opacity
     enveloped
     (* (spatial-relation-value-outer-opacity relation)
        (spatial-opacity enveloped))))
  (unless (and (spatial-visual? opaque)
               (eq? (spatial-id opaque) (spatial-id relation)))
    (raise-arguments-error
     'resolve-spatial-relation
     "spatial relation envelope application preserving concrete spatial identity"
     "relation" (spatial-id relation)
     "result" opaque))
  opaque)

(define (spatial-tree-signature object)
  (cons (spatial-id object)
        (if (spatial-container? object)
            (for/list ([entry (in-list (spatial-child-entries object))])
              (spatial-tree-signature (spatial-child-visual entry)))
            '())))

(define (spatial-tree-has-relation? object)
  (or (spatial-relation? object)
      (and (spatial-container? object)
           (for/or ([entry (in-list (spatial-child-entries object))])
             (spatial-tree-has-relation? (spatial-child-visual entry))))))

(define (check-relation who value)
  (unless (spatial-relation? value)
    (raise-argument-error who "spatial-relation?" value)))


;;;
;;; Built-In Spatial Relations
;;;

;; These intentionally use the stable mesh vocabulary already rendered by
;; SCENE-3D-C.  SCENE-3D-F will replace their thin edge/triangle presentation
;; with proper points, tubes, and curve primitives without changing the
;; semantic relation model established here.

; segment-between3d : spatial-path? spatial-path? #:id symbol?
;                     [#:color color-spec?] [#:width positive-real?]
;                     [#:opacity spatial-opacity?] -> spatial-relation?
;; Creates a current finite wire segment between two declared spatial origins.
(define (segment-between3d from to
                           #:id id
                           #:color [color "slategray"]
                           #:width [width 2]
                           #:opacity [opacity 1])
  (make-between-relation 'segment-between3d from to id color width opacity
                         (lambda (start end) (list start end))))

; distance-segment3d : spatial-path? spatial-path? #:id symbol? ...
;                       -> spatial-relation?
;; Names a measured finite spatial distance.  It currently has the same thin
;; line geometry as segment-between3d; later dimension decorations build on
;; this stable dependency behavior.
(define (distance-segment3d from to
                            #:id id
                            #:color [color "darkgoldenrod"]
                            #:width [width 2]
                            #:opacity [opacity 1])
  (make-between-relation 'distance-segment3d from to id color width opacity
                         (lambda (start end) (list start end))))

; line-between3d : spatial-path? spatial-path? #:id symbol?
;                  [#:padding nonnegative-real?] ... -> spatial-relation?
;; Creates the displayed portion of the infinite line through two spatial
;; origins, extending `padding` world units beyond each endpoint.
(define (line-between3d from to
                        #:id id
                        #:padding [padding 10]
                        #:color [color "slategray"]
                        #:width [width 2]
                        #:opacity [opacity 1])
  (check-nonnegative-finite 'line-between3d "padding" padding)
  (make-between-relation
   'line-between3d from to id color width opacity
   (lambda (start end)
     (define direction (distinct-direction 'line-between3d start end))
     (list (vec3- start (vec3-scale padding direction))
           (vec3+ end (vec3-scale padding direction))))))

; arrow-between3d : spatial-path? spatial-path? #:id symbol?
;                   [#:color color-spec?] [#:width positive-real?]
;                   [#:tip-size positive-real?] [#:opacity spatial-opacity?]
;                   -> spatial-relation?
;; Creates a current shaft and a small opaque triangular head at `to`.  The
;; head is a stopgap SCENE-3D-E marker; camera-facing curved/tube arrows land
;; in SCENE-3D-F.
(define (arrow-between3d from to
                         #:id id
                         #:color [color "slategray"]
                         #:width [width 2]
                         #:tip-size [tip-size 1/4]
                         #:opacity [opacity 1])
  (check-spatial-target 'arrow-between3d from)
  (check-spatial-target 'arrow-between3d to)
  (check-symbol 'arrow-between3d id)
  (check-width 'arrow-between3d width)
  (check-positive-finite 'arrow-between3d "tip-size" tip-size)
  (check-opacity 'arrow-between3d opacity)
  (define template
    (group3d
     (list (segment-mesh (child-id id "shaft") origin3 x-axis3 color width 1)
           (arrow-head-mesh (child-id id "head") origin3 x-axis3 color 1))
     #:id id
     #:opacity opacity))
  (spatial-relation
   template
   #:depends-on (list (spatial-visual-dependency from)
                      (spatial-visual-dependency to))
   (lambda (context _template)
     (define start (spatial-relation-context-spatial-position context from))
     (define end (spatial-relation-context-spatial-position context to))
     (group3d
      (list (segment-mesh (child-id id "shaft") start end color width 1)
            (arrow-head-mesh (child-id id "head") start end color tip-size))
      #:id id))))

; plane-through3d : spatial-path? spatial-path? spatial-path? #:id symbol?
;                   [#:color color-spec?] [#:opacity spatial-opacity?]
;                   -> spatial-relation?
;; Creates one double-sided triangular plane through the three current origins.
(define (plane-through3d first second third
                         #:id id
                         #:color [color "lightskyblue"]
                         #:opacity [opacity 1])
  (for ([target (in-list (list first second third))])
    (check-spatial-target 'plane-through3d target))
  (check-symbol 'plane-through3d id)
  (check-opacity 'plane-through3d opacity)
  (define material
    (material3d #:color color #:shading 'flat #:double-sided? #t))
  (define (plane p q r actual-opacity)
    (mesh3d #:id id
            #:vertices (vector p q r)
            #:triangles (vector (vector 0 1 2))
            #:material material
            #:wireframe-color color
            #:wireframe-width 1
            #:opacity actual-opacity))
  (spatial-relation
   (plane origin3 x-axis3 y-axis3 opacity)
   #:depends-on (list (spatial-visual-dependency first)
                      (spatial-visual-dependency second)
                      (spatial-visual-dependency third))
   (lambda (context _template)
     (plane (spatial-relation-context-spatial-position context first)
            (spatial-relation-context-spatial-position context second)
            (spatial-relation-context-spatial-position context third)
            1))))

; normal-at3d : spatial-path? vec3? #:id symbol?
;               [#:length positive-real?] ... -> spatial-relation?
;; Creates an arrow from a current spatial origin in the declared normal
;; direction.  Mesh-normal inference is intentionally deferred until the
;; richer primitive/mesh-inspection stage.
(define (normal-at3d target normal
                     #:id id
                     #:length [length 1]
                     #:color [color "darkmagenta"]
                     #:width [width 2]
                     #:tip-size [tip-size 1/4]
                     #:opacity [opacity 1])
  (check-spatial-target 'normal-at3d target)
  (unless (vec3? normal)
    (raise-argument-error 'normal-at3d "vec3?" normal))
  (check-symbol 'normal-at3d id)
  (check-positive-finite 'normal-at3d "length" length)
  (check-width 'normal-at3d width)
  (check-positive-finite 'normal-at3d "tip-size" tip-size)
  (check-opacity 'normal-at3d opacity)
  (define direction
    (with-handlers ([exn:fail?
                     (lambda (_failure)
                       (raise-arguments-error
                        'normal-at3d "a nonzero normal vector" "normal" normal))])
      (vec3-normalize normal)))
  (define template
    (group3d
     (list (segment-mesh (child-id id "shaft") origin3 x-axis3 color width 1)
           (arrow-head-mesh (child-id id "head") origin3 x-axis3 color 1))
     #:id id
     #:opacity opacity))
  (spatial-relation
   template
   #:depends-on (list (spatial-visual-dependency target))
   (lambda (context _template)
     (define start (spatial-relation-context-spatial-position context target))
     (define end (vec3+ start (vec3-scale length direction)))
     (group3d
      (list (segment-mesh (child-id id "shaft") start end color width 1)
            (arrow-head-mesh (child-id id "head") start end color tip-size))
      #:id id))))

(define (make-between-relation who from to id color width opacity endpoints)
  (check-spatial-target who from)
  (check-spatial-target who to)
  (check-symbol who id)
  (check-width who width)
  (check-opacity who opacity)
  (define template (segment-mesh id origin3 x-axis3 color width opacity))
  (spatial-relation
   template
   #:depends-on (list (spatial-visual-dependency from)
                      (spatial-visual-dependency to))
   (lambda (context _template)
     (define start (spatial-relation-context-spatial-position context from))
     (define end (spatial-relation-context-spatial-position context to))
     (define resolved (endpoints start end))
     (segment-mesh id (car resolved) (cadr resolved) color width 1))))

(define (segment-mesh id start end color width opacity)
  (mesh3d #:id id
          #:vertices (vector start end)
          #:edges (vector (vector 0 1))
          #:material (material3d #:color color #:shading 'unlit)
          #:wireframe-color color
          #:wireframe-width width
          #:opacity opacity))

(define (arrow-head-mesh id start end color size)
  (define direction (distinct-direction 'arrow-between3d start end))
  ;; Select a stable nonparallel guide axis, then make a small triangular
  ;; pyramid whose point is the arrow endpoint.  It looks sensible in both
  ;; opaque and wireframe render modes and has no camera-dependent geometry.
  (define guide
    (if (< (abs (vec3-z direction)) 3/4) z-axis3 y-axis3))
  (define side (vec3-normalize (vec3-cross direction guide)))
  (define up (vec3-normalize (vec3-cross side direction)))
  (define base-center (vec3- end (vec3-scale size direction)))
  (define half (* size 1/2))
  (define first (vec3+ base-center (vec3-scale half side)))
  (define second (vec3+ base-center (vec3-scale half up)))
  (define third (vec3- base-center (vec3-scale half side)))
  (mesh3d #:id id
          #:vertices (vector end first second third)
          #:triangles (vector (vector 0 1 2)
                              (vector 0 2 3)
                              (vector 0 3 1)
                              (vector 1 3 2))
          #:material (material3d #:color color #:shading 'flat #:double-sided? #t)
          #:wireframe-color color
          #:wireframe-width 1))

(define (distinct-direction who start end)
  (define delta (vec3- end start))
  (with-handlers ([exn:fail?
                   (lambda (_failure)
                     (raise-arguments-error
                      who "distinct spatial endpoints" "from" start "to" end))])
    (vec3-normalize delta)))

(define (check-spatial-target who target)
  (unless (and (list? target) (pair? target) (andmap symbol? target))
    (raise-argument-error who "nonempty list of symbols" target)))

(define (check-symbol who value)
  (unless (symbol? value)
    (raise-argument-error who "symbol?" value)))

(define (check-width who value)
  (check-positive-finite who "width" value))

(define (check-positive-finite who label value)
  (unless (and (finite-real? value) (positive? value))
    (raise-arguments-error who "positive finite real" label value)))

(define (check-nonnegative-finite who label value)
  (unless (and (finite-real? value) (>= value 0))
    (raise-arguments-error who "nonnegative finite real" label value)))

(define (check-opacity who value)
  (unless (spatial-opacity? value)
    (raise-argument-error who "finite real in the closed unit interval" value)))

(define (child-id root suffix)
  (string->symbol (format "~a-~a" root suffix)))
