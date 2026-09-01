#lang racket/base

;;;
;;; SCENE-L Model Tests
;;;

;; Tests semantic one-line text, font and anchor data, immutable updates,
;; group participation, and existing affine and opacity animation behavior.


;;;
;;; Imports
;;;

(require rackunit
         (only-in "../private/group-visual.rkt"
                  group-visual-resolved-children)
         "../main.rkt")


(module+ test
  ; sampled-visual : scene? real? symbol? -> visual?
  ;;   Returns one top-level Visual from a sampled scene.
  (define (sampled-visual scene time id)
    (scene-state-ref (scene-sample scene time) id))

  ;; Public font and alignment predicates recognize only the documented symbols.

  (for ([family
         (in-list
          '(default decorative roman script swiss modern symbol system))])
    (check-true (text-font-family? family)))
  (for ([style (in-list '(normal italic slant))])
    (check-true (text-font-style? style)))
  (for ([weight (in-list '(normal bold light))])
    (check-true (text-font-weight? weight)))
  (for ([alignment (in-list '(left center right))])
    (check-true (text-horizontal-alignment? alignment)))
  (for ([alignment (in-list '(top center baseline bottom))])
    (check-true (text-vertical-alignment? alignment)))

  (check-false (text-font-family? 'sans-serif))
  (check-false (text-font-style? 'oblique))
  (check-false (text-font-weight? 'heavy))
  (check-false (text-horizontal-alignment? 'middle))
  (check-false (text-vertical-alignment? 'middle))

  ;; The default constructor creates an affine and opacity-aware text Visual.

  ; greeting : text-visual?
  ;;   Gives a centered default plain-text Visual.
  (define greeting
    (plain-text "Hello, Racket" #:id 'greeting))

  (check-true (visual? greeting))
  (check-true (affine-visual? greeting))
  (check-true (opacity-visual? greeting))
  (check-true (text-visual? greeting))
  (check-equal? (visual-id greeting) 'greeting)
  (check-equal? (visual-position greeting) origin)
  (check-equal? (visual-rotation greeting) 0)
  (check-equal? (visual-scale greeting) (vec2 1 1))
  (check-equal? (visual-opacity greeting) 1)
  (check-equal? (text-visual-content greeting) "Hello, Racket")
  (check-true (immutable? (text-visual-content greeting)))
  (check-equal? (text-visual-font-size greeting) 1/2)
  (check-false (text-visual-font-face greeting))
  (check-equal? (text-visual-font-family greeting) 'default)
  (check-equal? (text-visual-font-style greeting) 'normal)
  (check-equal? (text-visual-font-weight greeting) 'normal)
  (check-equal? (text-visual-color greeting) "black")
  (check-equal? (text-visual-horizontal-alignment greeting) 'center)
  (check-equal? (text-visual-vertical-alignment greeting) 'center)

  ;; Explicit content, font, transform, opacity, color, and anchor data are
  ;; stored without rendering dependencies.

  ; styled-label : text-visual?
  ;;   Gives a fully styled and transformed text Visual.
  (define styled-label
    (plain-text "Axis label"
                #:id 'styled-label
                #:center (vec2 3 -2)
                #:rotation 1/4
                #:scale (vec2 2 1/2)
                #:opacity 3/4
                #:font-size 2/3
                #:font-face "Helvetica"
                #:font-family 'swiss
                #:font-style 'italic
                #:font-weight 'bold
                #:color "navy"
                #:horizontal-alignment 'left
                #:vertical-alignment 'baseline))

  (check-equal? (visual-position styled-label) (vec2 3 -2))
  (check-equal? (visual-rotation styled-label) 1/4)
  (check-equal? (visual-scale styled-label) (vec2 2 1/2))
  (check-equal? (visual-opacity styled-label) 3/4)
  (check-equal? (text-visual-content styled-label) "Axis label")
  (check-equal? (text-visual-font-size styled-label) 2/3)
  (check-equal? (text-visual-font-face styled-label) "Helvetica")
  (check-true (immutable? (text-visual-font-face styled-label)))
  (check-equal? (text-visual-font-family styled-label) 'swiss)
  (check-equal? (text-visual-font-style styled-label) 'italic)
  (check-equal? (text-visual-font-weight styled-label) 'bold)
  (check-equal? (text-visual-color styled-label) "navy")
  (check-equal? (text-visual-horizontal-alignment styled-label) 'left)
  (check-equal? (text-visual-vertical-alignment styled-label) 'baseline)

  ;; Mutable input strings are copied into immutable semantic storage.

  ; mutable-content : string?
  ;;   Gives mutable source content for copy testing.
  (define mutable-content
    (string #\C #\o #\p #\y))

  ; mutable-face : string?
  ;;   Gives a mutable preferred face for copy testing.
  (define mutable-face
    (string #\M #\e #\n #\l #\o))

  ; copied-text : text-visual?
  ;;   Gives a Visual constructed from mutable strings.
  (define copied-text
    (plain-text mutable-content
                #:id 'copied-text
                #:font-face mutable-face))

  (string-set! mutable-content 0 #\X)
  (string-set! mutable-face 0 #\X)
  (check-equal? (text-visual-content copied-text) "Copy")
  (check-equal? (text-visual-font-face copied-text) "Menlo")
  (check-true (immutable? (text-visual-content copied-text)))
  (check-true (immutable? (text-visual-font-face copied-text)))

  ;; Content replacement preserves identity, placement, style, and opacity.

  ; changed-content : text-visual?
  ;;   Gives styled-label with only its text content replaced.
  (define changed-content
    (text-visual-with-content styled-label "Changed"))

  (check-equal? (text-visual-content changed-content) "Changed")
  (check-true (immutable? (text-visual-content changed-content)))
  (check-equal? (visual-id changed-content) (visual-id styled-label))
  (check-equal? (visual-transform changed-content)
                (visual-transform styled-label))
  (check-equal? (visual-opacity changed-content)
                (visual-opacity styled-label))
  (check-equal? (text-visual-font-size changed-content)
                (text-visual-font-size styled-label))
  (check-equal? (text-visual-font-face changed-content)
                (text-visual-font-face styled-label))
  (check-equal? (text-visual-color changed-content)
                (text-visual-color styled-label))
  (check-equal? (text-visual-content styled-label) "Axis label")

  ; mutable-replacement : string?
  ;;   Gives mutable content for immutable replacement testing.
  (define mutable-replacement
    (string #\N #\e #\w))

  ; copied-replacement : text-visual?
  ;;   Gives greeting with a copied immutable replacement string.
  (define copied-replacement
    (text-visual-with-content greeting mutable-replacement))

  (string-set! mutable-replacement 0 #\X)
  (check-equal? (text-visual-content copied-replacement) "New")
  (check-true (immutable? (text-visual-content copied-replacement)))

  ;; Existing generic immutable updates preserve all text-specific fields.

  ; moved-label : text-visual?
  ;;   Gives styled-label with only its position changed.
  (define moved-label
    (visual-with-position styled-label (vec2 -4 1)))

  ; rotated-label : text-visual?
  ;;   Gives styled-label with only its rotation changed.
  (define rotated-label
    (visual-with-rotation styled-label 3/4))

  ; scaled-label : text-visual?
  ;;   Gives styled-label with only its scale changed.
  (define scaled-label
    (visual-with-scale styled-label (vec2 3 2)))

  ; faded-label : text-visual?
  ;;   Gives styled-label with only its opacity changed.
  (define faded-label
    (visual-with-opacity styled-label 1/5))

  (for ([updated
         (in-list
          (list moved-label rotated-label scaled-label faded-label))])
    (check-true (text-visual? updated))
    (check-equal? (visual-id updated) 'styled-label)
    (check-equal? (text-visual-content updated) "Axis label")
    (check-equal? (text-visual-font-size updated) 2/3)
    (check-equal? (text-visual-font-face updated) "Helvetica")
    (check-equal? (text-visual-font-family updated) 'swiss)
    (check-equal? (text-visual-font-style updated) 'italic)
    (check-equal? (text-visual-font-weight updated) 'bold)
    (check-equal? (text-visual-color updated) "navy")
    (check-equal? (text-visual-horizontal-alignment updated) 'left)
    (check-equal? (text-visual-vertical-alignment updated) 'baseline))

  (check-equal? (visual-position moved-label) (vec2 -4 1))
  (check-equal? (visual-rotation rotated-label) 3/4)
  (check-equal? (visual-scale scaled-label) (vec2 3 2))
  (check-equal? (visual-opacity faded-label) 1/5)

  ;; Empty content is valid model data. Embedded line breaks are not part of the
  ;; one-line plain-text stage.

  (check-equal?
   (text-visual-content (plain-text "" #:id 'empty-text))
   "")

  (for ([bad-content (in-list (list "first\nsecond"
                                    "first\rsecond"
                                    "first\r\nsecond"))])
    (check-exn exn:fail:contract?
               (lambda ()
                 (plain-text bad-content #:id 'bad-content))))

  ;; Constructor and immutable-update validation rejects malformed model data.

  (check-exn exn:fail:contract?
             (lambda ()
               (plain-text 42 #:id 'not-text)))
  (check-exn exn:fail:contract?
             (lambda ()
               (plain-text "bad id" #:id 42)))
  (check-exn exn:fail:contract?
             (lambda ()
               (plain-text "bad center"
                           #:id 'bad-center
                           #:center 0)))
  (check-exn exn:fail:contract?
             (lambda ()
               (plain-text "bad rotation"
                           #:id 'bad-rotation
                           #:rotation +inf.0)))
  (check-exn exn:fail:contract?
             (lambda ()
               (plain-text "bad scale"
                           #:id 'bad-scale
                           #:scale 0)))
  (check-exn exn:fail:contract?
             (lambda ()
               (plain-text "bad opacity"
                           #:id 'bad-opacity
                           #:opacity 2)))
  (check-exn exn:fail:contract?
             (lambda ()
               (plain-text "bad size"
                           #:id 'bad-size
                           #:font-size 0)))
  (check-exn exn:fail:contract?
             (lambda ()
               (plain-text "bad face"
                           #:id 'bad-face
                           #:font-face 'Helvetica)))
  (check-exn exn:fail:contract?
             (lambda ()
               (plain-text "bad family"
                           #:id 'bad-family
                           #:font-family 'sans-serif)))
  (check-exn exn:fail:contract?
             (lambda ()
               (plain-text "bad style"
                           #:id 'bad-style
                           #:font-style 'oblique)))
  (check-exn exn:fail:contract?
             (lambda ()
               (plain-text "bad weight"
                           #:id 'bad-weight
                           #:font-weight 'heavy)))
  (check-exn exn:fail:contract?
             (lambda ()
               (plain-text "bad horizontal alignment"
                           #:id 'bad-horizontal
                           #:horizontal-alignment 'middle)))
  (check-exn exn:fail:contract?
             (lambda ()
               (plain-text "bad vertical alignment"
                           #:id 'bad-vertical
                           #:vertical-alignment 'middle)))
  (check-exn exn:fail:contract?
             (lambda ()
               (text-visual-with-content greeting "a\nb")))
  (check-exn exn:fail:contract?
             (lambda ()
               (text-visual-with-content 42 "text")))

  ;; Text Visuals participate as ordinary affine leaves in nested groups.

  ; local-title : text-visual?
  ;;   Gives one local text child for inherited-transform testing.
  (define local-title
    (plain-text "Grouped"
                #:id 'local-title
                #:center (vec2 2 0)
                #:rotation 1/4
                #:scale (vec2 2 1/2)
                #:opacity 2/3
                #:font-family 'swiss
                #:font-weight 'bold))

  ; title-group : group-visual?
  ;;   Gives a uniformly transformed group containing local-title.
  (define title-group
    (group (list local-title)
           #:id 'title-group
           #:rotation 1/2
           #:scale 3))

  ; resolved-title : text-visual?
  ;;   Gives local-title after inherited group rotation and scale.
  (define resolved-title
    (car (group-visual-resolved-children title-group)))

  (check-true (text-visual? resolved-title))
  (check-equal? (visual-id resolved-title) 'local-title)
  (check-equal? (visual-position resolved-title)
                (affine-transform-apply-vector
                 (visual-transform title-group)
                 (vec2 2 0)))
  (check-equal? (visual-rotation resolved-title) 3/4)
  (check-equal? (visual-scale resolved-title) (vec2 6 3/2))
  (check-equal? (visual-opacity resolved-title) 2/3)
  (check-equal? (text-visual-content resolved-title) "Grouped")
  (check-equal? (text-visual-font-family resolved-title) 'swiss)
  (check-equal? (text-visual-font-weight resolved-title) 'bold)

  ;; Existing timeline requests can animate text position, rotation, scale, and
  ;; opacity concurrently without a text-specific animation component.

  ; initial-scene : scene?
  ;;   Gives a scene containing styled-label.
  (define initial-scene
    (scene-add (make-scene) styled-label))

  ; animated-text : scene?
  ;;   Animates four disjoint semantic components for one text Visual.
  (define animated-text
    (scene-play initial-scene
                (move-to styled-label (vec2 7 2))
                (rotate-to styled-label 5/4)
                (scale-to styled-label (vec2 4 2))
                (fade-to styled-label 1/4)
                #:duration 2))

  ; midpoint-text : text-visual?
  ;;   Gives styled-label halfway through animated-text.
  (define midpoint-text
    (sampled-visual animated-text 1 'styled-label))

  ; endpoint-text : text-visual?
  ;;   Gives styled-label at the structural clip endpoint.
  (define endpoint-text
    (sampled-visual animated-text 2 'styled-label))

  (check-equal? (visual-position midpoint-text) (vec2 5 0))
  (check-equal? (visual-rotation midpoint-text) 3/4)
  (check-equal? (visual-scale midpoint-text) (vec2 3 5/4))
  (check-equal? (visual-opacity midpoint-text) 1/2)
  (check-equal? (text-visual-content midpoint-text) "Axis label")
  (check-equal? (visual-position endpoint-text) (vec2 7 2))
  (check-equal? (visual-rotation endpoint-text) 5/4)
  (check-equal? (visual-scale endpoint-text) (vec2 4 2))
  (check-equal? (visual-opacity endpoint-text) 1/4)

  ;; Fade-in prepares complete text model data at opacity zero and installs the
  ;; requested final opacity at the endpoint.

  ; appearing-text : text-visual?
  ;;   Gives a text Visual introduced by fade-in.
  (define appearing-text
    (plain-text "Appearing"
                #:id 'appearing-text
                #:center (vec2 -3 0)
                #:opacity 3/5))

  ; fade-in-scene : scene?
  ;;   Introduces and moves appearing-text over one second.
  (define fade-in-scene
    (scene-play (make-scene)
                (move-to appearing-text origin)
                (fade-in appearing-text)
                #:duration 1))

  ; fade-start : text-visual?
  ;;   Gives the prepared zero-opacity text at the clip start.
  (define fade-start
    (sampled-visual fade-in-scene 0 'appearing-text))

  (check-true (text-visual? fade-start))
  (check-equal? (visual-opacity fade-start) 0)
  (check-equal? (text-visual-content fade-start) "Appearing")
  (check-equal? (visual-opacity
                 (sampled-visual fade-in-scene 1 'appearing-text))
                3/5))
