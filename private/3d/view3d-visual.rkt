#lang racket/base

;;;
;;; Three-Dimensional Viewport Visual
;;;

;; A view3d is the deliberate boundary between an ordinary immutable 2D scene
;; and an immutable spatial tree.  It implements the 2D Visual protocols for
;; placement, transform, and opacity, but intentionally does not publish its
;; spatial children through the 2D visual-container protocol.


;;;
;;; Imports and Exports
;;;

(require (only-in racket/generic define/generic)
         "../affine-transform.rkt"
         "../color-style.rkt"
         "../geometry.rkt"
         "../visual-model.rkt"
         "affine3.rkt"
         "affine-map3d-visual.rkt"
         "bounds3.rkt"
         "camera3d.rkt"
         "light3d.rkt"
         "spatial-group.rkt"
         "spatial-path.rkt"
         "spatial-visual.rkt"
         "transform3.rkt")

(provide view3d
         view3d?
         view3d-children
         view3d-width
         view3d-height
         view3d-camera
         view3d-with-camera
         view3d-lights
         view3d-background
         view3d-render-mode
         view3d-transparency-mode
         view3d-spatial-ref
         view3d-spatial-has?
         view3d-spatial-replace
         view3d-spatial-update
         view3d-spatial-insert-after
         view3d-spatial-bounds
         view3d-spatial-world-transform)


;;;
;;; Viewport Value
;;;

(struct view3d-value
  (id transform opacity children width height camera lights background render-mode transparency-mode)
  #:transparent
  #:methods gen:visual
  [(define (visual-id view)
     (view3d-value-id view))
   (define (visual-position view)
     (affine-transform-translation (view3d-value-transform view)))
   (define (visual-with-position view position)
     (unless (vec2? position)
       (raise-argument-error 'visual-with-position "vec2?" position))
     (struct-copy view3d-value view
                  [transform
                   (affine-transform-with-translation
                    (view3d-value-transform view) position)]))]
  #:methods gen:affine-visual
  [(define (visual-transform view)
     (view3d-value-transform view))
   (define (visual-with-transform view transform)
     (unless (affine-transform? transform)
       (raise-argument-error 'visual-with-transform "affine-transform?" transform))
     (struct-copy view3d-value view [transform transform]))]
  #:methods gen:opacity-visual
  [(define (visual-opacity view)
     (view3d-value-opacity view))
   (define (visual-with-opacity view opacity)
     (unless (opacity? opacity)
       (raise-argument-error 'visual-with-opacity "finite real in [0, 1]" opacity))
     (struct-copy view3d-value view [opacity opacity]))]
  #:methods gen:spatial-container
  [(define (spatial-child-entries view)
     (for/list ([child (in-list (view3d-value-children view))])
       (spatial-child (spatial-id child) child)))
   (define (spatial-container-with-children view children)
     (view3d-with-children view children))])

;; view3d-value represents one ordinary 2D viewport containing a spatial tree.
;;  - id           symbol?                    stable 2D scene identity.
;;  - transform    affine-transform?          outer 2D placement and shape.
;;  - opacity      opacity?                   outer 2D composition opacity.
;;  - children     (listof spatial-visual?)   spatial direct children in stable order.
;;  - width        positive finite real?      local viewport world width.
;;  - height       positive finite real?      local viewport world height.
;;  - camera       camera3d?                  immutable internal camera.
;;  - lights       (listof light3d?)           opaque-render lighting values.
;;  - background   color-spec?                opaque local viewport background.
;;  - render-mode  'wireframe or 'opaque      renderer selection.

(define view3d? view3d-value?)
(define view3d-children view3d-value-children)
(define view3d-width view3d-value-width)
(define view3d-height view3d-value-height)
(define view3d-camera view3d-value-camera)
(define view3d-lights view3d-value-lights)
(define view3d-background view3d-value-background)
(define view3d-render-mode view3d-value-render-mode)
(define view3d-transparency-mode view3d-value-transparency-mode)


;;;
;;; Construction
;;;

; view3d : (listof spatial-visual?) #:id symbol?
;          [#:center vec2?] [#:width positive-real?] [#:height positive-real?]
;          [#:rotation finite-real?] [#:scale scale-factor?] [#:opacity opacity?]
;          [#:camera camera3d?] [#:lights list?] [#:background color-spec?]
;          [#:render-mode 'wireframe]
;          [#:transparency-mode (or/c 'object-sorted 'triangle-sorted)] -> view3d?
;;   Creates a 2D viewport whose spatial children retain a separate 3D tree.
(define (view3d children
                #:id id
                #:center [center origin]
                #:width [width 12]
                #:height [height 27/4]
                #:rotation [rotation 0]
                #:scale [scale 1]
                #:opacity [opacity 1]
                #:camera [camera (perspective-camera3d)]
                #:lights [lights '()]
                #:background [background "white"]
                #:render-mode [render-mode 'wireframe]
                #:transparency-mode [transparency-mode 'triangle-sorted])
  (unless (symbol? id)
    (raise-argument-error 'view3d "symbol?" id))
  (unless (vec2? center)
    (raise-argument-error 'view3d "vec2?" center))
  (unless (and (finite-real? width) (positive? width))
    (raise-argument-error 'view3d "positive finite width" width))
  (unless (and (finite-real? height) (positive? height))
    (raise-argument-error 'view3d "positive finite height" height))
  (unless (finite-real? rotation)
    (raise-argument-error 'view3d "finite real rotation" rotation))
  (unless (scale-factor? scale)
    (raise-argument-error 'view3d "positive finite scale or vec2 scale" scale))
  (unless (opacity? opacity)
    (raise-argument-error 'view3d "finite real in [0, 1]" opacity))
  (unless (camera3d? camera)
    (raise-argument-error 'view3d "camera3d?" camera))
  (unless (and (list? lights) (andmap light3d? lights))
    (raise-argument-error 'view3d "(listof light3d?)" lights))
  (unless (color-spec? background)
    (raise-argument-error 'view3d "color-spec?" background))
  (unless (memq render-mode '(wireframe opaque))
    (raise-argument-error 'view3d "(or/c 'wireframe 'opaque)" render-mode))
  (unless (memq transparency-mode '(object-sorted triangle-sorted))
    (raise-argument-error
     'view3d "(or/c 'object-sorted 'triangle-sorted) as #:transparency-mode"
     transparency-mode))
  (view3d-value
   id
   (make-affine-transform #:translation center #:rotation rotation #:scale scale)
   opacity
   (check-children 'view3d id children)
   width height camera (for/list ([light (in-list lights)]) light)
   background render-mode transparency-mode))

(define (view3d-with-children view children)
  (unless (view3d? view)
    (raise-argument-error 'view3d-with-children "view3d?" view))
  (struct-copy view3d-value view
               [children
                (check-children 'view3d-with-children
                                (view3d-value-id view)
                                children)]))

; view3d-with-camera : view3d? camera3d? -> view3d?
;;   Returns view with its internal authored camera replaced immutably.
(define (view3d-with-camera view camera)
  (unless (view3d? view)
    (raise-argument-error 'view3d-with-camera "view3d?" view))
  (unless (camera3d? camera)
    (raise-argument-error 'view3d-with-camera "camera3d?" camera))
  (struct-copy view3d-value view [camera camera]))


;;;
;;; Absolute Spatial Paths
;;;

; view3d-spatial-ref : view3d? spatial-path? -> spatial-visual?
;;   Resolves a path rooted at the outer view3d identity, such as '(world cube).
(define (view3d-spatial-ref view path)
  (check-view-path 'view3d-spatial-ref view path)
  (spatial-relative-ref view (cdr path)))

; view3d-spatial-has? : view3d? spatial-path? -> boolean?
;;   Reports whether rooted path resolves to one immutable spatial object.
(define (view3d-spatial-has? view path)
  (unless (view3d? view)
    (raise-argument-error 'view3d-spatial-has? "view3d?" view))
  (and (spatial-path? path)
       (pair? (cdr path))
       (eq? (car path) (visual-id view))
       (with-handlers ([exn:fail? (lambda (_ignored) #f)])
         (view3d-spatial-ref view path)
         #t)))

; view3d-spatial-replace : view3d? spatial-path? spatial-visual? -> view3d?
;;   Returns view with a same-ID spatial descendant replaced through its path.
(define (view3d-spatial-replace view path replacement)
  (check-view-path 'view3d-spatial-replace view path)
  (unless (spatial-visual? replacement)
    (raise-argument-error 'view3d-spatial-replace "spatial-visual?" replacement))
  (spatial-relative-replace view (cdr path) replacement))

; view3d-spatial-update : view3d? spatial-path? (spatial-visual? -> spatial-visual?)
;                         -> view3d?
;;   Applies update to one rooted spatial object while preserving its stable ID.
(define (view3d-spatial-update view path update)
  (check-view-path 'view3d-spatial-update view path)
  (unless (procedure? update)
    (raise-argument-error 'view3d-spatial-update "procedure?" update))
  (define original (view3d-spatial-ref view path))
  (define replacement (update original))
  (unless (spatial-visual? replacement)
    (raise-arguments-error 'view3d-spatial-update
                           "an update returning a spatial Visual"
                           "result" replacement))
  (unless (eq? (spatial-id original) (spatial-id replacement))
    (raise-arguments-error 'view3d-spatial-update
                           "an update preserving the spatial ID"
                           "expected-spatial-id" (spatial-id original)
                           "replacement-spatial-id" (spatial-id replacement)))
  (view3d-spatial-replace view path replacement))

; view3d-spatial-insert-after : view3d? spatial-path? spatial-visual? -> view3d?
;; Adds one transient sibling after a rooted target while retaining the target's
;; identity and all existing rooted paths.  It is used internally for overlay
;; effects such as a passing flash.
(define (view3d-spatial-insert-after view path addition)
  (check-view-path 'view3d-spatial-insert-after view path)
  (unless (spatial-visual? addition)
    (raise-argument-error 'view3d-spatial-insert-after "spatial-visual?" addition))
  (spatial-relative-insert-after view (cdr path) addition))


;;;
;;; Spatial Bounds and World Transforms
;;;

; view3d-spatial-bounds : view3d? -> aabb3?
;;   Returns the union of every descendant's bounds in view3d world coordinates.
(define (view3d-spatial-bounds view)
  (unless (view3d? view)
    (raise-argument-error 'view3d-spatial-bounds "view3d?" view))
  (for/fold ([bounds aabb3-empty])
            ([child (in-list (view3d-children view))])
    (aabb3-union bounds
                 (spatial-subtree-world-bounds child identity-affine3))))

; view3d-spatial-world-transform : view3d? spatial-path? -> affine3?
;;   Returns the complete local-to-world affine transform for one rooted path.
(define (view3d-spatial-world-transform view path)
  (check-view-path 'view3d-spatial-world-transform view path)
  (let loop ([container view]
             [remaining (cdr path)]
             [parent identity-affine3])
    (define entry
      (for/first ([candidate (in-list (spatial-child-entries container))]
                  #:when (eq? (spatial-child-id candidate) (car remaining)))
        candidate))
    (unless entry
      (raise-arguments-error
       'view3d-spatial-world-transform
       "a spatial path present in this view3d"
       "spatial-path" path
       "missing-spatial-id" (car remaining)))
    (define child (spatial-child-visual entry))
    (define world-transform
      (affine3-compose parent (spatial-visual->affine3 child)))
    (cond [(null? (cdr remaining)) world-transform]
          [(spatial-container? child)
           (loop child (cdr remaining) world-transform)]
          [else
           (raise-arguments-error
            'view3d-spatial-world-transform
            "an intermediate spatial path entry naming a spatial container"
            "spatial-path" path
            "spatial-visual" child)])))

(define (spatial-subtree-world-bounds spatial parent-transform)
  (define world-transform
    (affine3-compose parent-transform (spatial-visual->affine3 spatial)))
  (cond
    [(affine-map3d? spatial)
     ;; Its container protocol is path-transparent, but the retained content
     ;; still needs direct traversal for a correctly mapped leaf or subtree.
     (spatial-subtree-world-bounds (affine-map3d-content spatial) world-transform)]
    [(spatial-container? spatial)
      (for/fold ([bounds aabb3-empty])
                ([entry (in-list (spatial-child-entries spatial))])
        (aabb3-union
         bounds
        (spatial-subtree-world-bounds (spatial-child-visual entry)
                                      world-transform)))]
    [else (aabb3-transform (spatial-local-bounds spatial) world-transform)]))


;;;
;;; Validation
;;;

(define (check-view-path who view path)
  (unless (view3d? view)
    (raise-argument-error who "view3d?" view))
  (unless (and (spatial-path? path) (pair? (cdr path)))
    (raise-argument-error who "nonempty rooted spatial path below view3d" path))
  (unless (eq? (car path) (visual-id view))
    (raise-arguments-error who
                           "a spatial path rooted at this view3d ID"
                           "view3d-id" (visual-id view)
                           "spatial-path" path)))

(define (check-children who view-id children)
  (unless (list? children)
    (raise-argument-error who "(listof spatial-visual?)" children))
  (define copied
    (for/list ([child (in-list children)])
      (unless (spatial-visual? child)
        (raise-argument-error who "(listof spatial-visual?)" children))
      child))
  (define ids (map spatial-id copied))
  (when (member view-id ids)
    (raise-arguments-error who
                           "a view3d ID distinct from direct spatial child IDs"
                           "view3d-id" view-id
                           "child-ids" ids))
  (define duplicate (first-duplicate ids))
  (when duplicate
    (raise-arguments-error who "unique direct spatial child IDs"
                           "duplicate-id" duplicate
                           "child-ids" ids))
  copied)

(define (first-duplicate values)
  (let loop ([remaining values] [seen '()])
    (cond [(null? remaining) #f]
          [(memq (car remaining) seen) (car remaining)]
          [else (loop (cdr remaining) (cons (car remaining) seen))])))
