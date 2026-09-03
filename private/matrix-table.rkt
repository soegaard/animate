#lang racket/base

;;;
;;; Matrix and Table Visuals
;;;

;; Builds matrices and tables from the existing immutable group and path
;; vocabulary.  Rows and cells are ordinary nested groups, so all established
;; path-addressed operations (move, attention, copying, live attachment, and
;; styling) apply without a matrix-specific animation interpreter.


;;;
;;; Imports and Exports
;;;

(require racket/list
         "affine-transform.rkt"
         "geometry.rkt"
         "group-visual.rkt"
         "path-geometry.rkt"
         "relative-layout.rkt"
         "visual-model.rkt")

(provide matrix
         matrix-row-id
         matrix-column-id
         matrix-row-path
         matrix-entry-path
         matrix-bracket-path
         table
         table-row-id
         table-column-id
         table-row-path
         table-cell-path)


;;;
;;; Stable Nested Names
;;;

;; A matrix/table has rows named row-1, row-2, ... and every row has cells
;; named col-1, col-2, ....  They are deliberately local names: `(A row-1
;; col-2)` and `(A row-2 col-2)` are distinct nested paths.

(define (matrix-row-id row)
  (indexed-id 'matrix-row-id "row" row))

(define (matrix-column-id column)
  (indexed-id 'matrix-column-id "col" column))

(define (table-row-id row)
  (indexed-id 'table-row-id "row" row))

(define (table-column-id column)
  (indexed-id 'table-column-id "col" column))

(define (matrix-row-path matrix-id row)
  (list (check-root-id 'matrix-row-path matrix-id)
        (matrix-row-id row)))

(define (matrix-entry-path matrix-id row column)
  (append (matrix-row-path matrix-id row)
          (list (matrix-column-id column))))

(define (matrix-bracket-path matrix-id side)
  (unless (memq side '(left right))
    (raise-argument-error 'matrix-bracket-path "(or/c 'left 'right)" side))
  (list (check-root-id 'matrix-bracket-path matrix-id)
        (if (eq? side 'left) 'left-bracket 'right-bracket)))

(define (table-row-path table-id row)
  (list (check-root-id 'table-row-path table-id)
        (table-row-id row)))

(define (table-cell-path table-id row column)
  (append (table-row-path table-id row)
          (list (table-column-id column))))


;;;
;;; Matrix Construction
;;;

; matrix : (listof (non-empty-listof (and/c visual? affine-visual?)))
;          #:id symbol?
;          [#:center vec2?]
;          [#:rotation finite-real?]
;          [#:scale scale-factor?]
;          [#:opacity opacity?]
;          [#:entry-width positive-real?]
;          [#:entry-height positive-real?]
;          [#:column-gap nonnegative-real?]
;          [#:row-gap nonnegative-real?]
;          [#:brackets? boolean?]
;          [#:bracket-width positive-real?]
;          [#:bracket-gap nonnegative-real?]
;          [#:stroke any/c]
;          [#:stroke-width nonnegative-real?]
;          -> group-visual?
;;   Arranges a rectangular grid of entry Visuals with optional square brackets.
(define (matrix rows
                #:id id
                #:center [center origin]
                #:rotation [rotation 0]
                #:scale [scale 1]
                #:opacity [opacity 1]
                #:entry-width [entry-width 1]
                #:entry-height [entry-height 1]
                #:entry-padding [entry-padding 1/5]
                #:column-gap [column-gap 1/4]
                #:row-gap [row-gap 1/4]
                #:brackets? [brackets? #t]
                #:bracket-width [bracket-width 1/5]
                #:bracket-gap [bracket-gap 1/10]
                #:stroke [stroke "black"]
                #:stroke-width [stroke-width 2])
  (define dimensions
    (check-grid 'matrix rows))
  (check-root-id 'matrix id)
  (check-grid-placement 'matrix center rotation scale opacity
                        column-gap row-gap)
  (check-nonnegative-length 'matrix "entry-padding" entry-padding)
  (unless (boolean? brackets?)
    (raise-argument-error 'matrix "boolean?" brackets?))
  (check-positive-length 'matrix "bracket-width" bracket-width)
  (check-nonnegative-length 'matrix "bracket-gap" bracket-gap)
  (check-nonnegative-length 'matrix "stroke-width" stroke-width)
  (define row-count (car dimensions))
  (define column-count (cdr dimensions))
  (define-values (column-widths row-heights)
    (resolve-grid-sizes 'matrix rows entry-width entry-height entry-padding))
  (define-values (grid-width grid-height)
    (grid-extents column-widths row-heights column-gap row-gap))
  (define brackets
    (if brackets?
        (list (matrix-bracket 'left grid-width grid-height
                              bracket-width bracket-gap stroke stroke-width)
              (matrix-bracket 'right grid-width grid-height
                              bracket-width bracket-gap stroke stroke-width))
        '()))
  (group
   ;; Place brackets in front of entries.  This keeps both strokes visible when
   ;; a renderer gives a glyph a slightly wider ink box than its nominal cell.
   (append (grid-rows rows
                      matrix-row-id matrix-column-id
                      column-widths row-heights column-gap row-gap)
           brackets)
   #:id id
   #:center center
   #:rotation rotation
   #:scale scale
   #:opacity opacity))


;;;
;;; Table Construction
;;;

; table : (listof (non-empty-listof (and/c visual? affine-visual?)))
;         #:id symbol?
;         [#:center vec2?]
;         [#:rotation finite-real?]
;         [#:scale scale-factor?]
;         [#:opacity opacity?]
;         [#:cell-width positive-real?]
;         [#:cell-height positive-real?]
;         [#:column-gap nonnegative-real?]
;         [#:row-gap nonnegative-real?]
;         [#:stroke any/c]
;         [#:stroke-width nonnegative-real?]
;         -> group-visual?
;;   Arranges a rectangular grid of entries and draws a shared rectangular grid.
(define (table rows
               #:id id
               #:center [center origin]
               #:rotation [rotation 0]
               #:scale [scale 1]
               #:opacity [opacity 1]
               #:cell-width [cell-width 1]
               #:cell-height [cell-height 3/4]
               #:cell-padding [cell-padding 1/5]
               #:column-gap [column-gap 0]
               #:row-gap [row-gap 0]
               #:stroke [stroke "black"]
               #:stroke-width [stroke-width 2])
  (define dimensions
    (check-grid 'table rows))
  (check-root-id 'table id)
  (check-grid-placement 'table center rotation scale opacity
                        column-gap row-gap)
  (check-nonnegative-length 'table "cell-padding" cell-padding)
  (check-nonnegative-length 'table "stroke-width" stroke-width)
  (define row-count (car dimensions))
  (define column-count (cdr dimensions))
  (define-values (column-widths row-heights)
    (resolve-grid-sizes 'table rows cell-width cell-height cell-padding))
  (define-values (grid-width grid-height)
    (grid-extents column-widths row-heights column-gap row-gap))
  (group
   (append (table-grid-lines row-count column-count grid-width grid-height
                             column-widths row-heights column-gap row-gap
                             stroke stroke-width)
           (grid-rows rows
                      table-row-id table-column-id
                      column-widths row-heights column-gap row-gap))
   #:id id
   #:center center
   #:rotation rotation
   #:scale scale
   #:opacity opacity))


;;;
;;; Grid Assembly
;;;

; grid-rows : list? procedure? procedure? (listof positive-real?)
;             (listof positive-real?) nonnegative-real? nonnegative-real?
;             -> (listof group-visual?)
;;   Creates row/cell groups with content re-based at each cell's local origin.
(define (grid-rows rows row-id column-id
                   column-widths row-heights column-gap row-gap)
  (define-values (grid-width grid-height)
    (grid-extents column-widths row-heights column-gap row-gap))
  (for/list ([row (in-list rows)]
             [row-index (in-naturals 1)])
    (group
     (for/list ([entry (in-list row)]
                [column-index (in-naturals 1)])
       (group
        (list (visual-with-position entry origin))
        #:id (column-id column-index)
        #:center
        (grid-cell-center row-index column-index
                          grid-width grid-height
                          column-widths row-heights column-gap row-gap)))
     #:id (row-id row-index))))

; matrix-bracket : symbol? positive-real? positive-real? positive-real?
;                  nonnegative-real? any/c nonnegative-real? -> path-visual?
;;   Builds a square left/right bracket in one matrix-local coordinate system.
(define (matrix-bracket side grid-width grid-height bracket-width bracket-gap
                        stroke stroke-width)
  (define half-width (/ grid-width 2))
  (define half-height (/ grid-height 2))
  (define outer-x
    (if (eq? side 'left)
        (- (+ half-width bracket-gap))
        (+ half-width bracket-gap)))
  (define inner-x
    (if (eq? side 'left)
        (+ outer-x bracket-width)
        (- outer-x bracket-width)))
  (centered-open-path-visual
   (list (vec2 inner-x half-height)
         (vec2 outer-x half-height)
         (vec2 outer-x (- half-height))
         (vec2 inner-x (- half-height)))
   (if (eq? side 'left) 'left-bracket 'right-bracket)
   stroke stroke-width))

; table-grid-lines : ... -> (listof path-visual?)
;;   Draws each grid boundary exactly once.  This avoids the darker doubled
;; strokes that would result from rendering a rectangle around every cell.
(define (table-grid-lines row-count column-count grid-width grid-height
                          column-widths row-heights column-gap row-gap
                          stroke stroke-width)
  (append
   (for/list ([column-boundary (in-range (add1 column-count))])
     (define x
       (grid-boundary-position column-boundary column-widths
                               grid-width column-gap))
     (centered-open-path-visual
      (list (vec2 x (/ grid-height 2))
            (vec2 x (- (/ grid-height 2))))
      (string->symbol (format "grid-column-~a" column-boundary))
      stroke stroke-width))
   (for/list ([row-boundary (in-range (add1 row-count))])
     (define y
       (grid-boundary-position row-boundary row-heights
                               grid-height row-gap))
     (centered-open-path-visual
      (list (vec2 (- (/ grid-width 2)) y)
            (vec2 (/ grid-width 2) y))
      (string->symbol (format "grid-row-~a" row-boundary))
      stroke stroke-width))))

; centered-open-path-visual : (listof vec2?) symbol? any/c
;                             nonnegative-real? -> path-visual?
;; Builds a path whose geometry is local to its own reference point.  Group
;; composition positions children by this reference point, so leaving absolute
;; grid coordinates in the geometry would apply a parent translation twice.
(define (centered-open-path-visual points id stroke stroke-width)
  (define geometry (polyline-path points))
  (define center (path-geometry-center geometry))
  (make-path-visual
   (path-geometry-translate geometry (vec2-scale -1 center))
   #:id id #:center center #:stroke stroke #:stroke-width stroke-width))

; grid-boundary-position : exact-nonnegative-integer? (listof positive-real?)
;                          positive-real? nonnegative-real?
;                          -> finite-real?
;;   Maps an index from top/left to a table boundary coordinate.
(define (grid-boundary-position index sizes total gap)
  (+ (- (/ total 2))
     (for/sum ([size (in-list (take sizes index))]) size)
     (* (max 0 (sub1 index)) gap)))

; grid-cell-center : exact-positive-integer? exact-positive-integer?
;                    positive-real? positive-real? (listof positive-real?)
;                    (listof positive-real?) nonnegative-real? nonnegative-real?
;                    -> vec2?
;;   Returns the local center of one row-major grid cell.
(define (grid-cell-center row column grid-width grid-height
                          column-widths row-heights column-gap row-gap)
  (define cell-width (list-ref column-widths (sub1 column)))
  (define cell-height (list-ref row-heights (sub1 row)))
  (vec2 (+ (- (/ grid-width 2))
           (for/sum ([width (in-list (take column-widths (sub1 column)))])
             width)
           (* (sub1 column) column-gap)
           (/ cell-width 2))
        (- (/ grid-height 2)
           (for/sum ([height (in-list (take row-heights (sub1 row)))])
             height)
           (* (sub1 row) row-gap)
           (/ cell-height 2))))

; grid-extents : (listof positive-real?) (listof positive-real?)
;                nonnegative-real? nonnegative-real?
;                -> (values positive-real? positive-real?)
(define (grid-extents column-widths row-heights column-gap row-gap)
  (values (+ (apply + column-widths)
             (* (sub1 (length column-widths)) column-gap))
          (+ (apply + row-heights)
             (* (sub1 (length row-heights)) row-gap))))

;; resolve-grid-sizes accepts one fixed size, an explicit axis-size list, or
;; `auto`. Auto sizing measures every existing entry once at construction time,
;; then chooses the maximum measured extent in each column and row plus the
;; caller's padding. The resulting ordinary group has no renderer dependency.
(define (resolve-grid-sizes who rows width-spec height-spec padding)
  (values
   (resolve-grid-axis-sizes who rows width-spec padding 'column)
   (resolve-grid-axis-sizes who rows height-spec padding 'row)))

(define (resolve-grid-axis-sizes who rows specification padding axis)
  (define count
    (if (eq? axis 'column)
        (length (car rows))
        (length rows)))
  (cond
    [(and (finite-real? specification) (positive? specification))
     (make-list count specification)]
    [(eq? specification 'auto)
     (for/list ([index (in-range count)])
       (define entries
         (if (eq? axis 'column)
             (for/list ([row (in-list rows)])
               (list-ref row index))
             (list-ref rows index)))
       (+ (* 2 padding)
          (for/fold ([largest 0]) ([entry (in-list entries)])
            (define box (visual-layout-box entry))
            (max largest
                 (if (eq? axis 'column)
                     (layout-box-width box)
                     (layout-box-height box))))))]
    [(and (list? specification) (= (length specification) count))
     (for/list ([value (in-list specification)])
       (check-positive-length who
                              (if (eq? axis 'column)
                                  "column width"
                                  "row height")
                              value)
       value)]
    [else
     (raise-arguments-error
      who
      "a positive finite size, a matching list of positive finite sizes, or 'auto"
      (if (eq? axis 'column) "width specification" "height specification")
      specification)]))


;;;
;;; Validation
;;;

; check-grid : symbol? any/c -> (cons/c exact-positive-integer?
;                                         exact-positive-integer?)
;;   Validates a nonempty rectangular grid of affine Visual entries.
(define (check-grid who rows)
  (unless (and (list? rows) (pair? rows))
    (raise-argument-error
     who
     "nonempty rectangular list of nonempty rows of affine Visuals"
     rows))
  (unless (andmap list? rows)
    (raise-argument-error
     who
     "nonempty rectangular list of nonempty rows of affine Visuals"
     rows))
  (define column-count (length (car rows)))
  (when (zero? column-count)
    (raise-argument-error
     who
     "nonempty rectangular list of nonempty rows of affine Visuals"
     rows))
  (for ([row (in-list rows)] [row-index (in-naturals 1)])
    (unless (= (length row) column-count)
      (raise-arguments-error
       who
       "all matrix/table rows must have the same number of entries"
       "row" row-index
       "expected-column-count" column-count
       "actual-column-count" (length row)))
    (for ([entry (in-list row)] [column-index (in-naturals 1)])
      (unless (and (visual? entry) (affine-visual? entry))
        (raise-arguments-error
         who
         "every matrix/table entry must be an affine Visual"
         "row" row-index
         "column" column-index
         "entry" entry))))
  (cons (length rows) column-count))

(define (check-grid-placement who center rotation scale opacity
                              column-gap row-gap)
  (unless (vec2? center)
    (raise-argument-error who "vec2?" center))
  (unless (finite-real? rotation)
    (raise-argument-error who "finite real?" rotation))
  (unless (scale-factor? scale)
    (raise-argument-error who "scale-factor?" scale))
  (define normalized-scale (scale-factor->vec2 scale))
  (unless (= (vec2-x normalized-scale) (vec2-y normalized-scale))
    (raise-arguments-error who
                           "matrix/table scale must be uniform"
                           "scale" scale))
  (unless (opacity? opacity)
    (raise-argument-error who "finite real in [0, 1]" opacity))
  (check-nonnegative-length who "column-gap" column-gap)
  (check-nonnegative-length who "row-gap" row-gap))

(define (check-root-id who id)
  (unless (symbol? id)
    (raise-argument-error who "symbol?" id))
  id)

(define (indexed-id who prefix index)
  (unless (exact-positive-integer? index)
    (raise-argument-error who "exact-positive-integer?" index))
  (string->symbol (format "~a-~a" prefix index)))

(define (check-positive-length who name value)
  (unless (and (finite-real? value) (positive? value))
    (raise-arguments-error who
                           (format "~a must be a positive finite real" name)
                           name value)))

(define (check-nonnegative-length who name value)
  (unless (and (finite-real? value) (>= value 0))
    (raise-arguments-error who
                           (format "~a must be a nonnegative finite real" name)
                           name value)))
