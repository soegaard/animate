#lang racket/base

;;;
;;; Relative Layout
;;;

;; Measures rendered Visual boxes in one world or frame coordinate system and
;; returns immutable position updates for placement, alignment, and arrangement.
;;
;; Layout belongs at the Pict-adapter boundary because text, formula, and custom
;; renderer dimensions are not available in the pure semantic model.


;;;
;;; Imports and Exports
;;;

;; Imports
(require (only-in pict
                  pict-height
                  pict-width)
         "camera.rkt"
         "frame-space.rkt"
         "geometry.rkt"
         "pict-adapter.rkt"
         "pict-renderer.rkt"
         "visual-model.rkt")

;; Exports
(provide (struct-out layout-box)
         layout-horizontal-alignment?
         layout-vertical-alignment?
         layout-box-anchor?
         layout-box-width
         layout-box-height
         layout-box-center
         layout-box-anchor
         visual-layout-box
         visual-layout-anchor
         visuals-layout-box
         visual-place-at
         visual-align-to
         visual-align-horizontal
         visual-align-vertical
         visual-place-above
         visual-place-below
         visual-place-left-of
         visual-place-right-of
         visuals-center-at
         arrange-visuals-horizontally
         arrange-visuals-vertically)


;;;
;;; Data Representation
;;;

(struct layout-box (left bottom right top)
  #:transparent
  #:guard
  (lambda (left bottom right top who)
    (unless (finite-real? left)
      (raise-argument-error who "finite real?" left))
    (unless (finite-real? bottom)
      (raise-argument-error who "finite real?" bottom))
    (unless (finite-real? right)
      (raise-argument-error who "finite real?" right))
    (unless (finite-real? top)
      (raise-argument-error who "finite real?" top))
    (when (> left right)
      (raise-arguments-error
       who
       "a layout box left edge must not exceed its right edge"
       "left" left
       "right" right))
    (when (> bottom top)
      (raise-arguments-error
       who
       "a layout box bottom edge must not exceed its top edge"
       "bottom" bottom
       "top" top))
    (values left bottom right top)))

;; layout-box represents an axis-aligned rendered box in containing coordinates.
;;  - left    finite-real?  smallest horizontal coordinate.
;;  - bottom  finite-real?  smallest vertical coordinate.
;;  - right   finite-real?  largest horizontal coordinate.
;;  - top     finite-real?  largest vertical coordinate.


;;;
;;; Alignment Predicates
;;;

; layout-horizontal-alignment? : any/c -> boolean?
;;   Reports whether value names a horizontal layout-box anchor.
(define (layout-horizontal-alignment? value)
  (and (symbol? value)
       (memq value '(left center right))
       #t))

; layout-vertical-alignment? : any/c -> boolean?
;;   Reports whether value names a vertical layout-box anchor.
(define (layout-vertical-alignment? value)
  (and (symbol? value)
       (memq value '(bottom center top))
       #t))

; layout-box-anchor? : any/c -> boolean?
;;   Reports whether value names one of the nine canonical render-box anchors.
(define (layout-box-anchor? value)
  (and (symbol? value)
       (memq value
             '(bottom-left bottom bottom-right
               left center right
               top-left top top-right))
       #t))


;;;
;;; Layout-Box Queries
;;;

; layout-box-width : layout-box? -> nonnegative-real?
;;   Returns the horizontal extent of box.
(define (layout-box-width box)
  (check-layout-box 'layout-box-width box)
  (- (layout-box-right box)
     (layout-box-left box)))

; layout-box-height : layout-box? -> nonnegative-real?
;;   Returns the vertical extent of box.
(define (layout-box-height box)
  (check-layout-box 'layout-box-height box)
  (- (layout-box-top box)
     (layout-box-bottom box)))

; layout-box-center : layout-box? -> vec2?
;;   Returns the center of box.
(define (layout-box-center box)
  (check-layout-box 'layout-box-center box)
  (vec2 (/ (+ (layout-box-left box)
              (layout-box-right box))
           2)
        (/ (+ (layout-box-bottom box)
              (layout-box-top box))
           2)))

; layout-box-anchor : layout-box? layout-box-anchor? -> vec2?
;;   Returns the requested canonical anchor of box in its containing coordinates.
(define (layout-box-anchor box anchor)
  (check-layout-box 'layout-box-anchor box)
  (check-layout-box-anchor 'layout-box-anchor anchor)
  (case anchor
    [(bottom-left)
     (vec2 (layout-box-left box) (layout-box-bottom box))]
    [(bottom)
     (vec2 (vec2-x (layout-box-center box)) (layout-box-bottom box))]
    [(bottom-right)
     (vec2 (layout-box-right box) (layout-box-bottom box))]
    [(left)
     (vec2 (layout-box-left box) (vec2-y (layout-box-center box)))]
    [(center)
     (layout-box-center box)]
    [(right)
     (vec2 (layout-box-right box) (vec2-y (layout-box-center box)))]
    [(top-left)
     (vec2 (layout-box-left box) (layout-box-top box))]
    [(top)
     (vec2 (vec2-x (layout-box-center box)) (layout-box-top box))]
    [(top-right)
     (vec2 (layout-box-right box) (layout-box-top box))]))


;;;
;;; Visual Measurement
;;;

; visual-layout-box : visual?
;                     [#:camera camera?]
;                     [#:renderers (listof pict-renderer?)]
;                     -> layout-box?
;;   Returns visual's symmetric rendered Pict box in containing coordinates.
(define (visual-layout-box visual
                           #:camera [camera default-camera]
                           #:renderers [renderers default-pict-renderers])
  (check-layout-context 'visual-layout-box camera renderers)
  (define position
    (checked-visual-position 'visual-layout-box visual))
  (define rendered
    (visual->pict visual camera #:renderers renderers))
  (define measurement-camera
    (layout-measurement-camera visual camera))
  (define width
    (checked-pict-extent 'visual-layout-box
                         "Pict width"
                         (pict-width rendered)))
  (define height
    (checked-pict-extent 'visual-layout-box
                         "Pict height"
                         (pict-height rendered)))
  (define scale
    (camera-scale measurement-camera))
  (define half-width
    (/ width scale 2))
  (define half-height
    (/ height scale 2))
  (layout-box (- (vec2-x position) half-width)
              (- (vec2-y position) half-height)
              (+ (vec2-x position) half-width)
              (+ (vec2-y position) half-height)))

; visual-layout-anchor : visual? layout-box-anchor?
;                        [#:camera camera?]
;                        [#:renderers (listof pict-renderer?)]
;                        -> vec2?
;;   Measures visual and returns one canonical render-box anchor.
(define (visual-layout-anchor visual
                              anchor
                              #:camera [camera default-camera]
                              #:renderers [renderers default-pict-renderers])
  (check-layout-box-anchor 'visual-layout-anchor anchor)
  (layout-box-anchor
   (visual-layout-box visual #:camera camera #:renderers renderers)
   anchor))

; visuals-layout-box : (listof visual?)
;                      [#:camera camera?]
;                      [#:renderers (listof pict-renderer?)]
;                      -> (or/c layout-box? false/c)
;;   Returns the union box of visuals, or false for an empty list.
(define (visuals-layout-box visuals
                            #:camera [camera default-camera]
                            #:renderers [renderers default-pict-renderers])
  (check-layout-context 'visuals-layout-box camera renderers)
  (check-visual-list 'visuals-layout-box visuals)
  (check-shared-layout-coordinate-space 'visuals-layout-box visuals)
  (cond
    [(null? visuals)
     #f]
    [else
     (for/fold ([combined
                 (visual-layout-box (car visuals)
                                    #:camera camera
                                    #:renderers renderers)])
               ([visual (in-list (cdr visuals))])
       (layout-box-union
        combined
        (visual-layout-box visual
                           #:camera camera
                           #:renderers renderers)))]))


;;;
;;; Alignment
;;;

; visual-place-at : visual? vec2? [#:anchor layout-box-anchor?]
;                   [#:camera camera?]
;                   [#:renderers (listof pict-renderer?)]
;                   -> visual?
;;   Moves visual so its requested render-box anchor is at position.
(define (visual-place-at visual
                         position
                         #:anchor [anchor 'center]
                         #:camera [camera default-camera]
                         #:renderers [renderers default-pict-renderers])
  (check-layout-context 'visual-place-at camera renderers)
  (unless (vec2? position)
    (raise-argument-error 'visual-place-at "vec2?" position))
  (check-layout-box-anchor 'visual-place-at anchor)
  (define current-anchor
    (visual-layout-anchor visual
                          anchor
                          #:camera camera
                          #:renderers renderers))
  (shift-visual-position
   'visual-place-at
   visual
   (vec2- position current-anchor)))

; visual-align-to : visual? visual?
;                   [#:anchor layout-box-anchor?]
;                   [#:reference-anchor layout-box-anchor?]
;                   [#:camera camera?]
;                   [#:renderers (listof pict-renderer?)]
;                   -> visual?
;;   Aligns visual's selected render-box anchor with reference's selected anchor.
(define (visual-align-to visual
                         reference
                         #:anchor [anchor 'center]
                         #:reference-anchor [reference-anchor anchor]
                         #:camera [camera default-camera]
                         #:renderers [renderers default-pict-renderers])
  (check-layout-context 'visual-align-to camera renderers)
  (check-layout-box-anchor 'visual-align-to anchor)
  (check-layout-box-anchor 'visual-align-to reference-anchor)
  (check-compatible-layout-coordinate-space
   'visual-align-to
   visual
   reference)
  (define visual-anchor
    (visual-layout-anchor visual
                          anchor
                          #:camera camera
                          #:renderers renderers))
  (define reference-point
    (visual-layout-anchor reference
                          reference-anchor
                          #:camera camera
                          #:renderers renderers))
  (shift-visual-position
   'visual-align-to
   visual
   (vec2- reference-point visual-anchor)))

; visual-align-horizontal : visual? visual? layout-horizontal-alignment?
;                           [#:camera camera?]
;                           [#:renderers (listof pict-renderer?)]
;                           -> visual?
;;   Aligns one horizontal box anchor of visual with the same anchor of reference.
(define (visual-align-horizontal visual
                                 reference
                                 alignment
                                 #:camera [camera default-camera]
                                 #:renderers [renderers default-pict-renderers])
  (check-horizontal-alignment 'visual-align-horizontal alignment)
  (define-values (visual-box reference-box)
    (measure-visual-pair 'visual-align-horizontal
                         visual
                         reference
                         camera
                         renderers))
  (shift-visual-position
   'visual-align-horizontal
   visual
   (vec2 (- (layout-box-horizontal-coordinate reference-box alignment)
            (layout-box-horizontal-coordinate visual-box alignment))
         0)))

; visual-align-vertical : visual? visual? layout-vertical-alignment?
;                         [#:camera camera?]
;                         [#:renderers (listof pict-renderer?)]
;                         -> visual?
;;   Aligns one vertical box anchor of visual with the same anchor of reference.
(define (visual-align-vertical visual
                               reference
                               alignment
                               #:camera [camera default-camera]
                               #:renderers [renderers default-pict-renderers])
  (check-vertical-alignment 'visual-align-vertical alignment)
  (define-values (visual-box reference-box)
    (measure-visual-pair 'visual-align-vertical
                         visual
                         reference
                         camera
                         renderers))
  (shift-visual-position
   'visual-align-vertical
   visual
   (vec2 0
         (- (layout-box-vertical-coordinate reference-box alignment)
            (layout-box-vertical-coordinate visual-box alignment)))))


;;;
;;; Relative Placement
;;;

; visual-place-above : visual? visual?
;                      [#:gap nonnegative-real?]
;                      [#:horizontal-alignment layout-horizontal-alignment?]
;                      [#:camera camera?]
;                      [#:renderers (listof pict-renderer?)]
;                      -> visual?
;;   Places visual above reference with the requested box gap and alignment.
(define (visual-place-above visual
                            reference
                            #:gap [gap 1/4]
                            #:horizontal-alignment
                            [horizontal-alignment 'center]
                            #:camera [camera default-camera]
                            #:renderers [renderers default-pict-renderers])
  (check-layout-gap 'visual-place-above gap)
  (check-horizontal-alignment
   'visual-place-above
   horizontal-alignment)
  (define-values (visual-box reference-box)
    (measure-visual-pair 'visual-place-above
                         visual
                         reference
                         camera
                         renderers))
  (shift-visual-position
   'visual-place-above
   visual
   (vec2 (- (layout-box-horizontal-coordinate
             reference-box
             horizontal-alignment)
            (layout-box-horizontal-coordinate
             visual-box
             horizontal-alignment))
         (- (+ (layout-box-top reference-box) gap)
            (layout-box-bottom visual-box)))))

; visual-place-below : visual? visual?
;                      [#:gap nonnegative-real?]
;                      [#:horizontal-alignment layout-horizontal-alignment?]
;                      [#:camera camera?]
;                      [#:renderers (listof pict-renderer?)]
;                      -> visual?
;;   Places visual below reference with the requested box gap and alignment.
(define (visual-place-below visual
                            reference
                            #:gap [gap 1/4]
                            #:horizontal-alignment
                            [horizontal-alignment 'center]
                            #:camera [camera default-camera]
                            #:renderers [renderers default-pict-renderers])
  (check-layout-gap 'visual-place-below gap)
  (check-horizontal-alignment
   'visual-place-below
   horizontal-alignment)
  (define-values (visual-box reference-box)
    (measure-visual-pair 'visual-place-below
                         visual
                         reference
                         camera
                         renderers))
  (shift-visual-position
   'visual-place-below
   visual
   (vec2 (- (layout-box-horizontal-coordinate
             reference-box
             horizontal-alignment)
            (layout-box-horizontal-coordinate
             visual-box
             horizontal-alignment))
         (- (- (layout-box-bottom reference-box) gap)
            (layout-box-top visual-box)))))

; visual-place-left-of : visual? visual?
;                        [#:gap nonnegative-real?]
;                        [#:vertical-alignment layout-vertical-alignment?]
;                        [#:camera camera?]
;                        [#:renderers (listof pict-renderer?)]
;                        -> visual?
;;   Places visual left of reference with the requested box gap and alignment.
(define (visual-place-left-of visual
                              reference
                              #:gap [gap 1/4]
                              #:vertical-alignment
                              [vertical-alignment 'center]
                              #:camera [camera default-camera]
                              #:renderers [renderers default-pict-renderers])
  (check-layout-gap 'visual-place-left-of gap)
  (check-vertical-alignment
   'visual-place-left-of
   vertical-alignment)
  (define-values (visual-box reference-box)
    (measure-visual-pair 'visual-place-left-of
                         visual
                         reference
                         camera
                         renderers))
  (shift-visual-position
   'visual-place-left-of
   visual
   (vec2 (- (- (layout-box-left reference-box) gap)
            (layout-box-right visual-box))
         (- (layout-box-vertical-coordinate
             reference-box
             vertical-alignment)
            (layout-box-vertical-coordinate
             visual-box
             vertical-alignment)))))

; visual-place-right-of : visual? visual?
;                         [#:gap nonnegative-real?]
;                         [#:vertical-alignment layout-vertical-alignment?]
;                         [#:camera camera?]
;                         [#:renderers (listof pict-renderer?)]
;                         -> visual?
;;   Places visual right of reference with the requested box gap and alignment.
(define (visual-place-right-of visual
                               reference
                               #:gap [gap 1/4]
                               #:vertical-alignment
                               [vertical-alignment 'center]
                               #:camera [camera default-camera]
                               #:renderers [renderers default-pict-renderers])
  (check-layout-gap 'visual-place-right-of gap)
  (check-vertical-alignment
   'visual-place-right-of
   vertical-alignment)
  (define-values (visual-box reference-box)
    (measure-visual-pair 'visual-place-right-of
                         visual
                         reference
                         camera
                         renderers))
  (shift-visual-position
   'visual-place-right-of
   visual
   (vec2 (- (+ (layout-box-right reference-box) gap)
            (layout-box-left visual-box))
         (- (layout-box-vertical-coordinate
             reference-box
             vertical-alignment)
            (layout-box-vertical-coordinate
             visual-box
             vertical-alignment)))))


;;;
;;; Ordered Arrangement
;;;

; visuals-center-at : (listof visual?) vec2?
;                     [#:camera camera?]
;                     [#:renderers (listof pict-renderer?)]
;                     -> (listof visual?)
;;   Translates visuals together so their union layout box is centered at center.
(define (visuals-center-at visuals
                           center
                           #:camera [camera default-camera]
                           #:renderers [renderers default-pict-renderers])
  (check-layout-context 'visuals-center-at camera renderers)
  (check-visual-list 'visuals-center-at visuals)
  (unless (vec2? center)
    (raise-argument-error 'visuals-center-at "vec2?" center))
  (define box
    (visuals-layout-box visuals
                        #:camera camera
                        #:renderers renderers))
  (cond
    [(not box)
     '()]
    [else
     (define displacement
       (vec2- center (layout-box-center box)))
     (for/list ([visual (in-list visuals)])
       (shift-visual-position
        'visuals-center-at
        visual
        displacement))]))

; arrange-visuals-horizontally : (listof visual?)
;                                [#:gap nonnegative-real?]
;                                [#:vertical-alignment
;                                 layout-vertical-alignment?]
;                                [#:center (or/c vec2? false/c)]
;                                [#:camera camera?]
;                                [#:renderers (listof pict-renderer?)]
;                                -> (listof visual?)
;;   Places each later Visual right of its predecessor in significant order.
(define (arrange-visuals-horizontally
         visuals
         #:gap [gap 1/4]
         #:vertical-alignment [vertical-alignment 'center]
         #:center [center #f]
         #:camera [camera default-camera]
         #:renderers [renderers default-pict-renderers])
  (check-layout-context
   'arrange-visuals-horizontally
   camera
   renderers)
  (check-visual-list 'arrange-visuals-horizontally visuals)
  (check-layout-gap 'arrange-visuals-horizontally gap)
  (check-vertical-alignment
   'arrange-visuals-horizontally
   vertical-alignment)
  (check-optional-layout-center
   'arrange-visuals-horizontally
   center)
  (define arranged
    (arrange-visuals
     visuals
     (lambda (visual reference)
       (visual-place-right-of
        visual
        reference
        #:gap gap
        #:vertical-alignment vertical-alignment
        #:camera camera
        #:renderers renderers))))
  (maybe-center-visuals arranged center camera renderers))

; arrange-visuals-vertically : (listof visual?)
;                              [#:gap nonnegative-real?]
;                              [#:horizontal-alignment
;                               layout-horizontal-alignment?]
;                              [#:center (or/c vec2? false/c)]
;                              [#:camera camera?]
;                              [#:renderers (listof pict-renderer?)]
;                              -> (listof visual?)
;;   Places each later Visual below its predecessor in significant order.
(define (arrange-visuals-vertically
         visuals
         #:gap [gap 1/4]
         #:horizontal-alignment [horizontal-alignment 'center]
         #:center [center #f]
         #:camera [camera default-camera]
         #:renderers [renderers default-pict-renderers])
  (check-layout-context
   'arrange-visuals-vertically
   camera
   renderers)
  (check-visual-list 'arrange-visuals-vertically visuals)
  (check-layout-gap 'arrange-visuals-vertically gap)
  (check-horizontal-alignment
   'arrange-visuals-vertically
   horizontal-alignment)
  (check-optional-layout-center
   'arrange-visuals-vertically
   center)
  (define arranged
    (arrange-visuals
     visuals
     (lambda (visual reference)
       (visual-place-below
        visual
        reference
        #:gap gap
        #:horizontal-alignment horizontal-alignment
        #:camera camera
        #:renderers renderers))))
  (maybe-center-visuals arranged center camera renderers))

; arrange-visuals : (listof visual?) (visual? visual? -> visual?)
;                   -> (listof visual?)
;;   Leaves the first Visual fixed and places each later one from the previous.
(define (arrange-visuals visuals place-next)
  (cond
    [(null? visuals)
     '()]
    [else
     (let loop ([remaining (cdr visuals)]
                [previous (car visuals)]
                [reversed (list (car visuals))])
       (cond
         [(null? remaining)
          (reverse reversed)]
         [else
          (define placed
            (place-next (car remaining) previous))
          (loop (cdr remaining)
                placed
                (cons placed reversed))]))]))

; maybe-center-visuals : (listof visual?) (or/c vec2? false/c)
;                        camera? (listof pict-renderer?)
;                        -> (listof visual?)
;;   Centers visuals when center is a vec2 and otherwise returns them unchanged.
(define (maybe-center-visuals visuals center camera renderers)
  (if center
      (visuals-center-at visuals
                         center
                         #:camera camera
                         #:renderers renderers)
      visuals))


;;;
;;; Internal Box Operations
;;;

; layout-box-union : layout-box? layout-box? -> layout-box?
;;   Returns the smallest axis-aligned box containing a and b.
(define (layout-box-union a b)
  (layout-box (min (layout-box-left a)
                   (layout-box-left b))
              (min (layout-box-bottom a)
                   (layout-box-bottom b))
              (max (layout-box-right a)
                   (layout-box-right b))
              (max (layout-box-top a)
                   (layout-box-top b))))

; layout-box-horizontal-coordinate : layout-box?
;                                    layout-horizontal-alignment?
;                                    -> finite-real?
;;   Returns the selected horizontal coordinate of box.
(define (layout-box-horizontal-coordinate box alignment)
  (case alignment
    [(left)
     (layout-box-left box)]
    [(center)
     (vec2-x (layout-box-center box))]
    [(right)
     (layout-box-right box)]))

; layout-box-vertical-coordinate : layout-box?
;                                  layout-vertical-alignment?
;                                  -> finite-real?
;;   Returns the selected vertical coordinate of box.
(define (layout-box-vertical-coordinate box alignment)
  (case alignment
    [(bottom)
     (layout-box-bottom box)]
    [(center)
     (vec2-y (layout-box-center box))]
    [(top)
     (layout-box-top box)]))


;;;
;;; Coordinate-Space Measurement
;;;

; layout-measurement-camera : visual? camera? -> camera?
;;   Returns the coordinate-space camera used to convert rendered pixels to units.
(define (layout-measurement-camera visual camera)
  (if (frame-space-visual? visual)
      (frame-space-camera
       camera
       (frame-space-visual-frame-width visual))
      camera))

; check-shared-layout-coordinate-space : symbol? (listof visual?) -> void?
;;   Rejects layout unions that mix world and incompatible frame coordinates.
(define (check-shared-layout-coordinate-space who visuals)
  (unless (null? visuals)
    (define reference
      (car visuals))
    (for ([visual (in-list (cdr visuals))])
      (check-compatible-layout-coordinate-space who visual reference)))
  (void))

; check-compatible-layout-coordinate-space : symbol? visual? visual? -> void?
;;   Requires two Visuals to share world space or one frame-width coordinate space.
(define (check-compatible-layout-coordinate-space who visual reference)
  (define visual-frame?
    (frame-space-visual? visual))
  (define reference-frame?
    (frame-space-visual? reference))
  (unless
      (cond
        [(and visual-frame? reference-frame?)
         (= (frame-space-visual-frame-width visual)
            (frame-space-visual-frame-width reference))]
        [(or visual-frame? reference-frame?)
         #f]
        [else
         #t])
    (raise-arguments-error
     who
     "Visuals must share one world or frame coordinate system"
     "visual-id" (visual-id visual)
     "reference-id" (visual-id reference)))
  (void))

;;;
;;; Visual Update Helpers
;;;

; measure-visual-pair : symbol? visual? visual? camera?
;                       (listof pict-renderer?)
;                       -> (values layout-box? layout-box?)
;;   Validates and measures one moving Visual and one reference Visual.
(define (measure-visual-pair who visual reference camera renderers)
  (check-layout-context who camera renderers)
  (checked-visual-position who visual)
  (checked-visual-position who reference)
  (check-compatible-layout-coordinate-space who visual reference)
  (values
   (visual-layout-box visual
                      #:camera camera
                      #:renderers renderers)
   (visual-layout-box reference
                      #:camera camera
                      #:renderers renderers)))

; shift-visual-position : symbol? visual? vec2? -> visual?
;;   Returns visual translated by displacement with protocol results checked.
(define (shift-visual-position who visual displacement)
  (define current-position
    (checked-visual-position who visual))
  (replace-visual-position
   who
   visual
   (vec2+ current-position displacement)))

; replace-visual-position : symbol? visual? vec2? -> visual?
;;   Replaces one Visual position and checks identity and requested placement.
(define (replace-visual-position who visual position)
  (define expected-id
    (visual-target-id visual who))
  (define result
    (visual-with-position visual position))
  (unless (visual? result)
    (raise-arguments-error
     who
     "a Visual position update must return a Visual"
     "visual" visual
     "result" result))
  (define result-id
    (visual-target-id result who))
  (unless (eq? result-id expected-id)
    (raise-arguments-error
     who
     "a Visual position update must preserve identity"
     "expected visual-id" expected-id
     "result visual-id" result-id))
  (define result-position
    (checked-visual-position who result))
  (unless (equal? result-position position)
    (raise-arguments-error
     who
     "a Visual position update must install the requested position"
     "requested position" position
     "result position" result-position))
  result)

; checked-visual-position : symbol? any/c -> vec2?
;;   Returns a validated Visual reference position.
(define (checked-visual-position who visual)
  (unless (visual? visual)
    (raise-argument-error who "visual?" visual))
  (visual-target-id visual who)
  (define position
    (visual-position visual))
  (unless (vec2? position)
    (raise-arguments-error
     who
     "a Visual must return a vec2 reference position"
     "visual" visual
     "position" position))
  position)


;;;
;;; Validation
;;;

; check-layout-box : symbol? any/c -> void?
;;   Raises an argument error unless value is a layout box.
(define (check-layout-box who value)
  (unless (layout-box? value)
    (raise-argument-error who "layout-box?" value)))

; check-layout-context : symbol? any/c any/c -> void?
;;   Validates the camera and ordered renderer list used for measurement.
(define (check-layout-context who camera renderers)
  (unless (camera? camera)
    (raise-argument-error who "camera?" camera))
  (check-pict-renderer-list who renderers))

; check-visual-list : symbol? any/c -> void?
;;   Raises an argument error unless value is a list of Visuals.
(define (check-visual-list who value)
  (unless (and (list? value)
               (andmap visual? value))
    (raise-argument-error who "(listof visual?)" value))
  (for ([visual (in-list value)])
    (checked-visual-position who visual))
  (void))

; check-layout-gap : symbol? any/c -> void?
;;   Raises an argument error unless gap is a nonnegative finite real.
(define (check-layout-gap who gap)
  (unless (and (finite-real? gap)
               (not (negative? gap)))
    (raise-argument-error who "nonnegative finite real?" gap)))

; check-horizontal-alignment : symbol? any/c -> void?
;;   Raises an argument error unless alignment selects a horizontal box anchor.
(define (check-horizontal-alignment who alignment)
  (unless (layout-horizontal-alignment? alignment)
    (raise-argument-error
     who
     "layout-horizontal-alignment?"
     alignment)))

; check-vertical-alignment : symbol? any/c -> void?
;;   Raises an argument error unless alignment selects a vertical box anchor.
(define (check-vertical-alignment who alignment)
  (unless (layout-vertical-alignment? alignment)
    (raise-argument-error
     who
     "layout-vertical-alignment?"
     alignment)))

; check-layout-box-anchor : symbol? any/c -> void?
;;   Raises an argument error unless anchor selects a canonical render-box point.
(define (check-layout-box-anchor who anchor)
  (unless (layout-box-anchor? anchor)
    (raise-argument-error who "layout-box-anchor?" anchor)))

; check-optional-layout-center : symbol? any/c -> void?
;;   Raises an argument error unless center is false or a vec2.
(define (check-optional-layout-center who center)
  (unless (or (not center)
              (vec2? center))
    (raise-argument-error who "(or/c vec2? false/c)" center)))

; checked-pict-extent : symbol? string? any/c -> nonnegative-real?
;;   Returns a validated finite nonnegative Pict extent.
(define (checked-pict-extent who field-name value)
  (unless (and (finite-real? value)
               (not (negative? value)))
    (raise-arguments-error
     who
     "a rendered Pict extent must be a nonnegative finite real"
     field-name value))
  value)
