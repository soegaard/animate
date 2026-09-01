#lang racket/base

;;;
;;; SCENE-P Relative-Layout Tests
;;;

;; Tests renderer-aware layout boxes, alignment, relative placement, ordered
;; arrangement, centering, custom renderer metrics, and update validation.


;;;
;;; Imports
;;;

(require rackunit
         (only-in pict filled-rectangle)
         "../main.rkt")


(module+ test
  ; test-camera : camera?
  ;;   Gives a fixed camera with ten pixels per world unit.
  (define test-camera
    (make-camera #:width 200
                 #:height 100
                 #:world-width 20))

  ; reference : rectangle-visual?
  ;;   Gives a four-by-two reference box spanning x 0..4 and y 0..2.
  (define reference
    (rectangle #:id 'reference
               #:center (vec2 2 1)
               #:width 4
               #:height 2
               #:stroke #f
               #:stroke-width 0))

  ; moving : rectangle-visual?
  ;;   Gives a two-by-four box spanning x -4..-2 and y -4..0.
  (define moving
    (rectangle #:id 'moving
               #:center (vec2 -3 -2)
               #:width 2
               #:height 4
               #:stroke #f
               #:stroke-width 0))

  ;; Layout-box construction and queries use mathematical y-up coordinates.
  (define manual-box
    (layout-box -2 -1 4 5))

  (check-equal? (layout-box-width manual-box) 6)
  (check-equal? (layout-box-height manual-box) 6)
  (check-equal? (layout-box-center manual-box) (vec2 1 2))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (layout-box 2 0 1 3)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (layout-box 0 3 2 1)))

  (for ([value (in-list '(left center right))])
    (check-true (layout-horizontal-alignment? value)))
  (for ([value (in-list '(bottom center top))])
    (check-true (layout-vertical-alignment? value)))
  (check-false (layout-horizontal-alignment? 'top))
  (check-false (layout-vertical-alignment? 'left))
  (check-false (layout-horizontal-alignment? "left"))

  ; reference-box : layout-box?
  ;;   Gives the measured world-coordinate box of reference.
  (define reference-box
    (visual-layout-box reference #:camera test-camera))

  ; moving-box : layout-box?
  ;;   Gives the measured world-coordinate box of moving.
  (define moving-box
    (visual-layout-box moving #:camera test-camera))

  (check-equal? reference-box (layout-box 0 0 4 2))
  (check-equal? moving-box (layout-box -4 -4 -2 0))
  (check-equal?
   (visual-layout-box
    (visual-with-opacity reference 0)
    #:camera test-camera)
   reference-box)

  (check-false
   (visuals-layout-box '() #:camera test-camera))
  (check-equal?
   (visuals-layout-box (list reference moving)
                       #:camera test-camera)
   (layout-box -4 -4 4 2))

  ;; Independent alignment changes only the selected position coordinate.
  (check-equal?
   (visual-position
    (visual-align-horizontal moving
                             reference
                             'left
                             #:camera test-camera))
   (vec2 1 -2))
  (check-equal?
   (visual-position
    (visual-align-horizontal moving
                             reference
                             'center
                             #:camera test-camera))
   (vec2 2 -2))
  (check-equal?
   (visual-position
    (visual-align-horizontal moving
                             reference
                             'right
                             #:camera test-camera))
   (vec2 3 -2))
  (check-equal?
   (visual-position
    (visual-align-vertical moving
                           reference
                           'bottom
                           #:camera test-camera))
   (vec2 -3 2))
  (check-equal?
   (visual-position
    (visual-align-vertical moving
                           reference
                           'center
                           #:camera test-camera))
   (vec2 -3 1))
  (check-equal?
   (visual-position
    (visual-align-vertical moving
                           reference
                           'top
                           #:camera test-camera))
   (vec2 -3 0))

  ;; Relative placement uses gaps between measured render boxes.
  ; above : visual?
  ;;   Gives moving centered above reference with one world unit of space.
  (define above
    (visual-place-above moving
                        reference
                        #:gap 1
                        #:camera test-camera))

  (check-equal? (visual-position above) (vec2 2 5))
  (check-equal? (visual-id above) 'moving)
  (check-equal?
   (- (layout-box-bottom
       (visual-layout-box above #:camera test-camera))
      (layout-box-top reference-box))
   1)

  ; below : visual?
  ;;   Gives moving below reference with left edges aligned.
  (define below
    (visual-place-below moving
                        reference
                        #:gap 1
                        #:horizontal-alignment 'left
                        #:camera test-camera))

  (check-equal? (visual-position below) (vec2 1 -3))
  (check-equal?
   (- (layout-box-bottom reference-box)
      (layout-box-top
       (visual-layout-box below #:camera test-camera)))
   1)

  ; left-of : visual?
  ;;   Gives moving left of reference with top edges aligned.
  (define left-of
    (visual-place-left-of moving
                          reference
                          #:gap 1
                          #:vertical-alignment 'top
                          #:camera test-camera))

  (check-equal? (visual-position left-of) (vec2 -2 0))
  (check-equal?
   (- (layout-box-left reference-box)
      (layout-box-right
       (visual-layout-box left-of #:camera test-camera)))
   1)

  ; right-of : visual?
  ;;   Gives moving right of reference with bottom edges aligned.
  (define right-of
    (visual-place-right-of moving
                           reference
                           #:gap 1
                           #:vertical-alignment 'bottom
                           #:camera test-camera))

  (check-equal? (visual-position right-of) (vec2 6 2))
  (check-equal?
   (- (layout-box-left
       (visual-layout-box right-of #:camera test-camera))
      (layout-box-right reference-box))
   1)

  ;; Source values remain unchanged because every update is immutable.
  (check-equal? (visual-position moving) (vec2 -3 -2))
  (check-equal? (visual-position reference) (vec2 2 1))

  (check-exn
   exn:fail:contract?
   (lambda ()
     (visual-place-above moving reference #:gap -1)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (visual-place-right-of moving
                            reference
                            #:vertical-alignment 'baseline)))

  ;; Ordered arrangements preserve order and identity. Without #:center, the
  ;; first Visual remains unchanged.
  ; first : rectangle-visual?
  ;;   Gives the fixed first item of an arrangement.
  (define first
    (rectangle #:id 'first
               #:center (vec2 5 5)
               #:width 2
               #:height 2
               #:stroke #f
               #:stroke-width 0))

  ; second : rectangle-visual?
  ;;   Gives the second item before arrangement.
  (define second
    (rectangle #:id 'second
               #:center (vec2 100 100)
               #:width 4
               #:height 1
               #:stroke #f
               #:stroke-width 0))

  ; third : rectangle-visual?
  ;;   Gives the third item before arrangement.
  (define third
    (rectangle #:id 'third
               #:center (vec2 -100 -100)
               #:width 1
               #:height 3
               #:stroke #f
               #:stroke-width 0))

  ; horizontal : (listof visual?)
  ;;   Gives a left-to-right arrangement with centered vertical boxes.
  (define horizontal
    (arrange-visuals-horizontally
     (list first second third)
     #:gap 1
     #:camera test-camera))

  (check-equal? (map visual-id horizontal)
                '(first second third))
  (check-equal? (map visual-position horizontal)
                (list (vec2 5 5)
                      (vec2 9 5)
                      (vec2 25/2 5)))

  ; horizontal-centered : (listof visual?)
  ;;   Gives the same arrangement centered at the world origin.
  (define horizontal-centered
    (arrange-visuals-horizontally
     (list first second third)
     #:gap 1
     #:center origin
     #:camera test-camera))

  (check-equal?
   (layout-box-center
    (visuals-layout-box horizontal-centered
                        #:camera test-camera))
   origin)

  ; vertical : (listof visual?)
  ;;   Gives a top-to-bottom arrangement with right edges aligned.
  (define vertical
    (arrange-visuals-vertically
     (list first second third)
     #:gap 1
     #:horizontal-alignment 'right
     #:camera test-camera))

  (check-equal? (map visual-id vertical)
                '(first second third))
  (check-equal? (visual-position (car vertical))
                (visual-position first))
  (for ([upper (in-list vertical)]
        [lower (in-list (cdr vertical))])
    (define upper-box
      (visual-layout-box upper #:camera test-camera))
    (define lower-box
      (visual-layout-box lower #:camera test-camera))
    (check-equal? (- (layout-box-bottom upper-box)
                     (layout-box-top lower-box))
                  1)
    (check-equal? (layout-box-right upper-box)
                  (layout-box-right lower-box)))

  ; centered-pair : (listof visual?)
  ;;   Gives two Visuals translated together to a requested union center.
  (define centered-pair
    (visuals-center-at (list reference moving)
                       (vec2 10 10)
                       #:camera test-camera))

  (check-equal?
   (layout-box-center
    (visuals-layout-box centered-pair
                        #:camera test-camera))
   (vec2 10 10))
  (check-equal? (map visual-id centered-pair)
                '(reference moving))
  (check-equal?
   (vec2- (visual-position (cadr centered-pair))
          (visual-position (car centered-pair)))
   (vec2- (visual-position moving)
          (visual-position reference)))
  (check-equal?
   (visuals-center-at '() origin #:camera test-camera)
   '())

  ;; Formula dimensions can be supplied by an explicit deterministic renderer,
  ;; so layout tests do not launch TeX.
  (struct formula-box-renderer ()
    #:transparent
    #:methods gen:pict-renderer
    [(define (pict-renderer-supports? _renderer visual)
       (formula-visual? visual))
     (define (pict-renderer-render _renderer visual _camera)
       (case (string->symbol (formula-visual-source visual))
         [(title)
          (filled-rectangle 80 10 #:draw-border? #f)]
         [(identity)
          (filled-rectangle 60 20 #:draw-border? #f)]
         [(sum)
          (filled-rectangle 100 40 #:draw-border? #f)]
         [else
          (filled-rectangle 10 10 #:draw-border? #f)]))])

  ; formula-renderers : (listof pict-renderer?)
  ;;   Gives deterministic formula metrics before the built-in renderer.
  (define formula-renderers
    (cons (formula-box-renderer)
          default-pict-renderers))

  ; formula-items : (listof formula-visual?)
  ;;   Gives three formulas with all initial anchors at the origin.
  (define formula-items
    (list (latex-formula "title" #:id 'title)
          (latex-formula "identity" #:id 'identity)
          (latex-formula "sum" #:id 'sum)))

  ; arranged-formulas : (listof formula-visual?)
  ;;   Gives non-overlapping formulas centered as one composition.
  (define arranged-formulas
    (arrange-visuals-vertically
     formula-items
     #:gap 1/2
     #:center origin
     #:camera test-camera
     #:renderers formula-renderers))

  (check-equal? (map visual-id arranged-formulas)
                '(title identity sum))
  (check-equal?
   (layout-box-center
    (visuals-layout-box arranged-formulas
                        #:camera test-camera
                        #:renderers formula-renderers))
   origin)
  (for ([upper (in-list arranged-formulas)]
        [lower (in-list (cdr arranged-formulas))])
    (define upper-box
      (visual-layout-box upper
                         #:camera test-camera
                         #:renderers formula-renderers))
    (define lower-box
      (visual-layout-box lower
                         #:camera test-camera
                         #:renderers formula-renderers))
    (check-equal? (- (layout-box-bottom upper-box)
                     (layout-box-top lower-box))
                  1/2))

  ;; Empty input still validates its explicit layout context.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (arrange-visuals-horizontally
      '()
      #:renderers 'not-a-renderer-list)))

  ;; A custom Visual update must install the requested position and preserve id.
  (struct broken-position-visual (id position)
    #:transparent
    #:methods gen:visual
    [(define (visual-id visual)
       (broken-position-visual-id visual))
     (define (visual-position visual)
       (broken-position-visual-position visual))
     (define (visual-with-position visual _position)
       visual)])

  (struct broken-position-renderer ()
    #:transparent
    #:methods gen:pict-renderer
    [(define (pict-renderer-supports? _renderer visual)
       (broken-position-visual? visual))
     (define (pict-renderer-render _renderer _visual _camera)
       (filled-rectangle 10 10 #:draw-border? #f))])

  (check-exn
   exn:fail:contract?
   (lambda ()
     (visual-place-above
      (broken-position-visual 'broken origin)
      reference
      #:camera test-camera
      #:renderers
      (cons (broken-position-renderer)
            default-pict-renderers)))))
