#lang racket/base

;;;
;;; Read-Only Semantic Visual Inspection
;;;

;; Inspection samples a scene once, enumerates stable semantic paths from the
;; stored tree, then resolves all world-space targets through one memoized
;; resolver. The resulting records are ordinary immutable data; nothing is
;; inserted into the scene or its frame cache.

(require racket/list
         "camera.rkt"
         "formula-parts-visual.rkt"
         "geometry.rkt"
         "group-visual.rkt"
         "relative-layout.rkt"
         (only-in "pict-adapter.rkt" default-pict-renderers)
         "scene-state.rkt"
         "scene.rkt"
         "visual-model.rkt")

(provide (struct-out visual-inspection)
         scene-inspection-tree
         scene-inspect-path
         scene-paths-at
         scene-hit-candidates
         scene-hit-test)

(struct visual-inspection
  (path id kind depth drawing-index world-position composed-transform opacity
        fill stroke stroke-width layout-box anchors source-block metadata)
  #:transparent)

(define (scene-inspection-tree scene time
                               #:camera [requested-camera #f]
                               #:renderers [renderers default-pict-renderers]
                               #:source-block [source-block #f])
  (unless (scene? scene)
    (raise-argument-error 'scene-inspection-tree "scene?" scene))
  (unless (or (not requested-camera) (camera? requested-camera))
    (raise-argument-error 'scene-inspection-tree "(or/c #f camera?)" requested-camera))
  (define-values (state sampled-camera) (scene-sample-with-camera scene time))
  (define camera (or requested-camera sampled-camera))
  (define raw-roots (scene-state-visuals-in-drawing-order state))
  (define paths+drawing-indices
    (append*
     (for/list ([root (in-list raw-roots)] [drawing-index (in-naturals)])
       (enumerate-visual-paths root (list (visual-id root)) drawing-index))))
  (define paths (map car paths+drawing-indices))
  (define world-visuals (scene-state-resolved-world-refs state paths))
  (for/list ([entry (in-list paths+drawing-indices)]
             [world-visual (in-list world-visuals)])
    (inspection-for (car entry) (cdr entry) world-visual camera renderers source-block)))

(define (scene-inspect-path scene path time
                            #:camera [camera #f]
                            #:renderers [renderers default-pict-renderers]
                            #:source-block [source-block #f])
  (unless (and (list? path) (pair? path) (andmap symbol? path))
    (raise-argument-error 'scene-inspect-path "nonempty list of symbols" path))
  (or (findf (lambda (inspection) (equal? path (visual-inspection-path inspection)))
             (scene-inspection-tree scene time #:camera camera #:renderers renderers
                                    #:source-block source-block))
      #f))

(define (scene-paths-at scene time
                        #:camera [camera #f]
                        #:renderers [renderers default-pict-renderers])
  (map visual-inspection-path
       (scene-inspection-tree scene time #:camera camera #:renderers renderers)))

;; Bounding-box hit testing is intentionally the first inspection policy. It
;; makes every renderer-measurable Visual selectable, while documenting the
;; expected approximation around rotated thin paths, glyph counters, and
;; transparent regions. Exact alpha/path hit testing can refine it later.
(define (scene-hit-candidates scene time pixel-x pixel-y
                              #:camera [camera #f]
                              #:renderers [renderers default-pict-renderers]
                              #:source-block [source-block #f])
  (unless (or (not camera) (camera? camera))
    (raise-argument-error 'scene-hit-candidates "(or/c #f camera?)" camera))
  (define actual-camera (or camera (scene-camera-at scene time)))
  (define point (camera-pixel->world actual-camera pixel-x pixel-y))
  (sort
   (filter (lambda (inspection)
             (define box (visual-inspection-layout-box inspection))
             (and box (layout-box-contains? box point)))
           (scene-inspection-tree scene time #:camera actual-camera #:renderers renderers
                                  #:source-block source-block))
   inspection-precedes?))

(define (scene-hit-test scene time pixel-x pixel-y
                        #:camera [camera #f]
                        #:renderers [renderers default-pict-renderers]
                        #:source-block [source-block #f]
                        #:after-path [after-path #f])
  (define candidates
    (scene-hit-candidates scene time pixel-x pixel-y #:camera camera
                          #:renderers renderers #:source-block source-block))
  (cond
    [(null? candidates) #f]
    [(not after-path) (car candidates)]
    [else
     (define index
       (for/first ([candidate (in-list candidates)] [index (in-naturals)]
                   #:when (equal? after-path (visual-inspection-path candidate)))
         index))
     (list-ref candidates (modulo (add1 (or index -1)) (length candidates)))]))

(define (enumerate-visual-paths visual path drawing-index)
  (cons (cons path drawing-index)
        (if (visual-container? visual)
            (append*
             (for/list ([child (in-list (visual-child-entries visual))])
               (enumerate-visual-paths
                (visual-child-visual child)
                (append path (list (visual-child-id child)))
                drawing-index)))
            '())))

(define (inspection-for path drawing-index visual camera renderers source-block)
  (define box
    (with-handlers ([exn:fail? (lambda (_error) #f)])
      (visual-layout-box visual #:camera camera #:renderers renderers)))
  (visual-inspection
   path
   (visual-id visual)
   (visual-kind visual)
   (sub1 (length path))
   drawing-index
   (visual-position visual)
   (and (affine-visual? visual) (visual-transform visual))
   (and (opacity-visual? visual) (visual-opacity visual))
   (and (fill-color-visual? visual) (visual-fill-color visual))
   (and (stroke-color-visual? visual) (visual-stroke-color visual))
   (and (stroke-width-visual? visual) (visual-stroke-width visual))
   box
   (and box
        (for/hash ([anchor (in-list '(bottom-left bottom bottom-right
                                     left center right top-left top top-right))])
          (values anchor (layout-box-anchor box anchor))))
   source-block
   (hash 'container? (visual-container? visual)
         'drawing-index drawing-index)))

(define (visual-kind visual)
  (cond
    [(group-visual? visual) 'group]
    [(formula-assembly-visual? visual) 'formula-assembly]
    [else
     ;; Struct values keep a useful, renderer-independent type name in their
     ;; printed representation even for custom Visual implementations.
     (let ([printed (format "~s" visual)])
       (cond [(regexp-match #rx"^#\\(struct:([^ ]+)" printed)
             => (lambda (match) (string->symbol (cadr match)))]
             [else 'visual]))]))

(define (layout-box-contains? box point)
  (and (<= (layout-box-left box) (vec2-x point) (layout-box-right box))
       (<= (layout-box-bottom box) (vec2-y point) (layout-box-top box))))

(define (inspection-precedes? first second)
  (cond
    [(not (= (visual-inspection-drawing-index first)
             (visual-inspection-drawing-index second)))
     (> (visual-inspection-drawing-index first)
        (visual-inspection-drawing-index second))]
    [(not (= (visual-inspection-depth first)
             (visual-inspection-depth second)))
     (> (visual-inspection-depth first)
        (visual-inspection-depth second))]
    [else
     (< (inspection-area first) (inspection-area second))]))

(define (inspection-area inspection)
  (define box (visual-inspection-layout-box inspection))
  (* (layout-box-width box) (layout-box-height box)))
