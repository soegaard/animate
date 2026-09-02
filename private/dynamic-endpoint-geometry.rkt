#lang racket/base

;;;
;;; Dynamic Endpoint Geometry
;;;

;; Defines deterministic line and arrow definitions whose endpoints are sampled
;; from immutable scene state.  Ordinary point/parameter/reference endpoints are
;; pure derived Visuals.  An endpoint that selects a non-centre rendered-box
;; anchor is instead a small renderer-aware wrapper, just like SCENE-CM's live
;; attachment: only the adapter knows the measured extent of a Visual.

(require "arrow-visual.rkt"
         "derived-visual.rkt"
         "geometry.rkt"
         "layout-attachment.rkt"
         "parameter.rkt"
         "visual-model.rkt")

(provide anchor-of
         line-between
         segment-between
         arrow-between
         ray-from
         dynamic-endpoint-visual?
         dynamic-endpoint-visual-template
         dynamic-endpoint-visual-start
         dynamic-endpoint-visual-end
         dynamic-endpoint-visual-ray-length
         dynamic-endpoint-visual-resolve
         dynamic-endpoint-visual-resolve-renderer
         dynamic-endpoint-visual-has-renderer-anchors?)


;;;
;;; Endpoint Descriptions
;;;

;; A literal vec2, a scene parameter whose sampled value is a vec2, and a
;; Visual reference all name a point.  anchor-of additionally selects a target
;; Visual's live rendered-box anchor.
(struct point-endpoint (point) #:transparent)
(struct parameter-endpoint (parameter) #:transparent)
(struct visual-endpoint (target anchor offset) #:transparent)

; anchor-of : (or/c visual? symbol? visual-path?)
;             [layout-attachment-anchor?]
;             [#:offset vec2?]
;             -> endpoint-description?
;; Describes one point on a sampled Visual.  The centre is the Visual's normal
;; semantic reference position; an edge or corner is measured by the active
;; renderer when the scene is rendered.
(define (anchor-of target [anchor 'center] #:offset [offset origin])
  (unless (layout-attachment-anchor? anchor)
    (raise-argument-error 'anchor-of "layout-attachment-anchor?" anchor))
  (unless (vec2? offset)
    (raise-argument-error 'anchor-of "vec2?" offset))
  (visual-endpoint (visual-target-id target 'anchor-of) anchor offset))

(define (endpoint-description value who)
  (cond
    [(vec2? value)
     (point-endpoint value)]
    [(scene-parameter? value)
     (parameter-endpoint value)]
    [(visual-endpoint? value)
     value]
    [(or (visual? value) (symbol? value) (visual-path? value))
     (visual-endpoint (visual-target-id value who) 'center origin)]
    [else
     (raise-argument-error
      who
      "vec2?, scene-parameter?, Visual ID/path, or anchor-of endpoint"
      value)]))

(define (endpoint-has-renderer-anchor? endpoint)
  (and (visual-endpoint? endpoint)
       (not (eq? (visual-endpoint-anchor endpoint) 'center))))

(define (endpoint-target-terminal-id endpoint)
  (and (visual-endpoint? endpoint)
       (let ([target (visual-endpoint-target endpoint)])
         (if (symbol? target)
             target
             (car (reverse target))))))

; resolve-pure-endpoint : derived-context? endpoint-description? -> vec2?
;; Resolves the renderer-independent endpoint kinds through the ordinary pure
;; derived-Visual context.  Non-centre anchors are deliberately rejected here:
;; their visual extents do not exist in the model layer.
(define (resolve-pure-endpoint context endpoint)
  (cond
    [(point-endpoint? endpoint)
     (point-endpoint-point endpoint)]
    [(parameter-endpoint? endpoint)
     (define value
       (derived-context-value-ref context
                                  (parameter-endpoint-parameter endpoint)))
     (unless (vec2? value)
       (raise-arguments-error
        'line-between
        "a point-valued endpoint parameter"
        "parameter" (parameter-id (parameter-endpoint-parameter endpoint))
        "sampled-value" value))
     value]
    [(visual-endpoint? endpoint)
     (unless (eq? (visual-endpoint-anchor endpoint) 'center)
       (raise-arguments-error
        'line-between
        "a renderer-aware endpoint handled after scene sampling"
        "endpoint" endpoint))
     (define target
       (derived-context-visual-ref context (visual-endpoint-target endpoint)))
     (when (dynamic-endpoint-visual? target)
       (raise-arguments-error
        'line-between
        "a concrete endpoint target, not another renderer-aware endpoint geometry"
        "target" (visual-endpoint-target endpoint)))
     (vec2+ (visual-position target)
            (visual-endpoint-offset endpoint))]
    [else
     (raise-argument-error 'line-between "endpoint description" endpoint)]))


;;;
;;; Definition Data and Construction
;;;

;; kind is 'line or 'arrow. For a ray, ray-length is a positive length and end
;; names a through point; the concrete end is derived from the current direction.
(define endpoint-template-id visual-id)
(define endpoint-template-position visual-position)
(define endpoint-template-with-position visual-with-position)
(define endpoint-template-opacity visual-opacity)
(define endpoint-template-with-opacity visual-with-opacity)

(struct dynamic-endpoint-visual-value
  (template kind start end ray-length stroke stroke-width tip-length tip-width
            start-tip? end-tip?)
  #:transparent
  #:methods gen:visual
  [(define (visual-id definition)
     (endpoint-template-id
      (dynamic-endpoint-visual-value-template definition)))
   (define (visual-position definition)
     (endpoint-template-position
      (dynamic-endpoint-visual-value-template definition)))
   (define (visual-with-position definition position)
     (struct-copy
      dynamic-endpoint-visual-value
      definition
      [template
       (endpoint-template-with-position
        (dynamic-endpoint-visual-value-template definition)
        position)]))]
  #:methods gen:opacity-visual
  [(define (visual-opacity definition)
     (endpoint-template-opacity
      (dynamic-endpoint-visual-value-template definition)))
   (define (visual-with-opacity definition opacity)
     (struct-copy
      dynamic-endpoint-visual-value
      definition
      [template
       (endpoint-template-with-opacity
        (dynamic-endpoint-visual-value-template definition)
        opacity)]))])

; dynamic-endpoint-visual? : any/c -> boolean?
;; Recognizes a renderer-aware endpoint definition returned for an edge/corner.
(define (dynamic-endpoint-visual? value)
  (dynamic-endpoint-visual-value? value))

(define dynamic-endpoint-visual-template
  dynamic-endpoint-visual-value-template)
(define dynamic-endpoint-visual-start
  dynamic-endpoint-visual-value-start)
(define dynamic-endpoint-visual-end
  dynamic-endpoint-visual-value-end)
(define dynamic-endpoint-visual-ray-length
  dynamic-endpoint-visual-value-ray-length)

; dynamic-endpoint-visual-has-renderer-anchors? : dynamic-endpoint-visual?
;                                                  -> boolean?
;; Reports whether a definition requires active renderer layout measurement.
(define (dynamic-endpoint-visual-has-renderer-anchors? definition)
  (unless (dynamic-endpoint-visual? definition)
    (raise-argument-error
     'dynamic-endpoint-visual-has-renderer-anchors?
     "dynamic-endpoint-visual?"
     definition))
  (or (endpoint-has-renderer-anchor?
       (dynamic-endpoint-visual-value-start definition))
      (endpoint-has-renderer-anchor?
       (dynamic-endpoint-visual-value-end definition))))

; line-between : endpoint? endpoint?
;                #:id symbol?
;                [#:opacity opacity?]
;                [#:stroke any/c]
;                [#:stroke-width stroke-width?]
;                -> (or/c derived-visual? dynamic-endpoint-visual?)
;; Creates a live finite segment whose endpoints are independently sampled.
(define (line-between start end
                      #:id id
                      #:opacity [opacity 1]
                      #:stroke [stroke "black"]
                      #:stroke-width [stroke-width 2])
  (make-endpoint-definition
   'line start end #f id opacity stroke stroke-width 3/10 1/4 #f #f
   'line-between))

; segment-between : endpoint? endpoint? ... -> (or/c derived-visual? dynamic-endpoint-visual?)
;; A mathematical synonym for line-between, useful when the finite segment is
;; the intended object rather than an unbounded drawn line.
(define (segment-between start end
                         #:id id
                         #:opacity [opacity 1]
                         #:stroke [stroke "black"]
                         #:stroke-width [stroke-width 2])
  (line-between start end
                #:id id
                #:opacity opacity
                #:stroke stroke
                #:stroke-width stroke-width))

; arrow-between : endpoint? endpoint?
;                 #:id symbol?
;                 [#:opacity opacity?]
;                 [#:stroke any/c]
;                 [#:stroke-width stroke-width?]
;                 [#:tip-length positive-finite-real?]
;                 [#:tip-width positive-finite-real?]
;                 [#:start-tip? boolean?]
;                 [#:end-tip? boolean?]
;                 -> (or/c derived-visual? dynamic-endpoint-visual?)
;; Creates an arrow whose shaft and tips follow two independently sampled points.
(define (arrow-between start end
                       #:id id
                       #:opacity [opacity 1]
                       #:stroke [stroke "black"]
                       #:stroke-width [stroke-width 2]
                       #:tip-length [tip-length 3/10]
                       #:tip-width [tip-width 1/4]
                       #:start-tip? [start-tip? #f]
                       #:end-tip? [end-tip? #t])
  (make-endpoint-definition
   'arrow start end #f id opacity stroke stroke-width tip-length tip-width
   start-tip? end-tip? 'arrow-between))

; ray-from : endpoint? endpoint?
;            #:id symbol?
;            [#:length positive-finite-real?]
;            ... arrow style keywords ...
;            -> (or/c derived-visual? dynamic-endpoint-visual?)
;; Creates a finite visible ray beginning at start and pointing through through.
;; The ray's fixed visual length avoids an ill-defined infinite renderer object.
(define (ray-from start through
                  #:id id
                  #:length [length 2]
                  #:opacity [opacity 1]
                  #:stroke [stroke "black"]
                  #:stroke-width [stroke-width 2]
                  #:tip-length [tip-length 3/10]
                  #:tip-width [tip-width 1/4]
                  #:start-tip? [start-tip? #f]
                  #:end-tip? [end-tip? #t])
  (unless (positive-finite-real? length)
    (raise-argument-error 'ray-from "positive finite real?" length))
  (make-endpoint-definition
   'arrow start through length id opacity stroke stroke-width tip-length tip-width
   start-tip? end-tip? 'ray-from))

(define (make-endpoint-definition kind start end ray-length id opacity stroke
                                  stroke-width tip-length tip-width
                                  start-tip? end-tip? who)
  (unless (symbol? id)
    (raise-argument-error who "symbol?" id))
  (unless (opacity? opacity)
    (raise-argument-error who "finite real in [0, 1]" opacity))
  (unless (stroke-width? stroke-width)
    (raise-argument-error who "nonnegative finite real?" stroke-width))
  (unless (positive-finite-real? tip-length)
    (raise-argument-error who "positive finite real?" tip-length))
  (unless (positive-finite-real? tip-width)
    (raise-argument-error who "positive finite real?" tip-width))
  (unless (boolean? start-tip?)
    (raise-argument-error who "boolean?" start-tip?))
  (unless (boolean? end-tip?)
    (raise-argument-error who "boolean?" end-tip?))
  (define start-endpoint (endpoint-description start who))
  (define end-endpoint (endpoint-description end who))
  (for ([endpoint (in-list (list start-endpoint end-endpoint))])
    (when (eq? id (endpoint-target-terminal-id endpoint))
      (raise-arguments-error
       who
       "a geometry identity distinct from every endpoint target"
       "id" id
       "endpoint" endpoint)))
  ;; A harmless concrete template preserves the normal Visual protocol before
  ;; a scene has supplied actual endpoint coordinates.
  (define template
    (make-concrete-endpoint-visual
     kind origin (vec2 1 0) ray-length id opacity stroke stroke-width
     tip-length tip-width start-tip? end-tip? who))
  (define definition
    (dynamic-endpoint-visual-value
     template kind start-endpoint end-endpoint ray-length stroke stroke-width
     tip-length tip-width start-tip? end-tip?))
  (if (dynamic-endpoint-visual-has-renderer-anchors? definition)
      definition
      (derived-visual
       template
       (lambda (context _template)
         (dynamic-endpoint-visual-resolve
          definition
          (lambda (endpoint)
            (resolve-pure-endpoint context endpoint)))))))

; dynamic-endpoint-visual-resolve : dynamic-endpoint-visual?
;                                   (-> endpoint-description? vec2?) -> visual?
;; Builds this sampled geometry using resolver for the two endpoint descriptions.
;; The Pict adapter supplies a resolver that can measure non-centre anchors;
;; derived definitions supply the pure context resolver above.
(define (dynamic-endpoint-visual-resolve definition resolve-endpoint)
  (unless (dynamic-endpoint-visual? definition)
    (raise-argument-error
     'dynamic-endpoint-visual-resolve
     "dynamic-endpoint-visual?"
     definition))
  (unless (and (procedure? resolve-endpoint)
               (procedure-arity-includes? resolve-endpoint 1))
    (raise-argument-error
     'dynamic-endpoint-visual-resolve
     "procedure accepting one endpoint description"
     resolve-endpoint))
  (define start
    (checked-resolved-endpoint
     'dynamic-endpoint-visual-resolve
     (resolve-endpoint (dynamic-endpoint-visual-value-start definition))))
  (define end
    (checked-resolved-endpoint
     'dynamic-endpoint-visual-resolve
     (resolve-endpoint (dynamic-endpoint-visual-value-end definition))))
  (make-concrete-endpoint-visual
   (dynamic-endpoint-visual-value-kind definition)
   start
   end
   (dynamic-endpoint-visual-value-ray-length definition)
   (visual-id (dynamic-endpoint-visual-value-template definition))
   (visual-opacity (dynamic-endpoint-visual-value-template definition))
   (dynamic-endpoint-visual-value-stroke definition)
   (dynamic-endpoint-visual-value-stroke-width definition)
   (dynamic-endpoint-visual-value-tip-length definition)
   (dynamic-endpoint-visual-value-tip-width definition)
   (dynamic-endpoint-visual-value-start-tip? definition)
   (dynamic-endpoint-visual-value-end-tip? definition)
   'dynamic-endpoint-visual-resolve))

; dynamic-endpoint-visual-resolve-renderer : dynamic-endpoint-visual?
;                                            (-> scene-parameter? vec2?)
;                                            (-> visual-path? layout-anchor? vec2? vec2?)
;                                            -> visual?
;; Resolves a renderer-aware definition.  The adapter supplies the two lookup
;; operations so this model module remains independent of scene state and Pict.
(define (dynamic-endpoint-visual-resolve-renderer definition
                                                  parameter-ref
                                                  visual-anchor-ref)
  (unless (dynamic-endpoint-visual? definition)
    (raise-argument-error
     'dynamic-endpoint-visual-resolve-renderer
     "dynamic-endpoint-visual?"
     definition))
  (unless (and (procedure? parameter-ref)
               (procedure-arity-includes? parameter-ref 1))
    (raise-argument-error
     'dynamic-endpoint-visual-resolve-renderer
     "procedure accepting one scene parameter"
     parameter-ref))
  (unless (and (procedure? visual-anchor-ref)
               (procedure-arity-includes? visual-anchor-ref 3))
    (raise-argument-error
     'dynamic-endpoint-visual-resolve-renderer
     "procedure accepting target, anchor, and offset"
     visual-anchor-ref))
  (dynamic-endpoint-visual-resolve
   definition
   (lambda (endpoint)
     (cond
       [(point-endpoint? endpoint)
        (point-endpoint-point endpoint)]
       [(parameter-endpoint? endpoint)
        (checked-resolved-endpoint
         'dynamic-endpoint-visual-resolve-renderer
         (parameter-ref (parameter-endpoint-parameter endpoint)))]
       [(visual-endpoint? endpoint)
        (checked-resolved-endpoint
         'dynamic-endpoint-visual-resolve-renderer
         (visual-anchor-ref (visual-endpoint-target endpoint)
                            (visual-endpoint-anchor endpoint)
                            (visual-endpoint-offset endpoint)))]
       [else
        (raise-argument-error
         'dynamic-endpoint-visual-resolve-renderer
         "endpoint description"
         endpoint)]))))

(define (make-concrete-endpoint-visual kind start end ray-length id opacity stroke
                                       stroke-width tip-length tip-width
                                       start-tip? end-tip? who)
  (define concrete-end
    (if ray-length
        (ray-endpoint who start end ray-length)
        end))
  (case kind
    [(line)
     (line start concrete-end
           #:id id
           #:opacity opacity
           #:stroke stroke
           #:stroke-width stroke-width)]
    [(arrow)
     (arrow start concrete-end
            #:id id
            #:opacity opacity
            #:stroke stroke
            #:stroke-width stroke-width
            #:tip-length tip-length
            #:tip-width tip-width
            #:start-tip? start-tip?
            #:end-tip? end-tip?)]
    [else
     (raise-argument-error who "supported endpoint geometry kind" kind)]))

(define (ray-endpoint who start through length)
  (define direction
    (vec2- through start))
  (define direction-length
    (point-distance start through))
  (unless (positive? direction-length)
    (raise-arguments-error
     who
     "a ray start distinct from its through point"
     "start" start
     "through" through))
  (vec2+
   start
   (vec2-scale (/ length direction-length) direction)))

(define (checked-resolved-endpoint who value)
  (unless (vec2? value)
    (raise-arguments-error
     who
     "an endpoint resolver that returns a vec2"
     "result" value))
  value)

(define (positive-finite-real? value)
  (and (finite-real? value) (positive? value)))

;; This mirrors arrow-visual's overflow-resistant length calculation without
;; exporting another low-level geometry helper from the public model.
(define (point-distance start end)
  (define delta-x (abs (- (vec2-x end) (vec2-x start))))
  (define delta-y (abs (- (vec2-y end) (vec2-y start))))
  (define scale (max delta-x delta-y))
  (if (zero? scale)
      0
      (* scale
         (sqrt (+ (sqr (/ delta-x scale))
                  (sqr (/ delta-y scale)))))))

(define (sqr value) (* value value))
