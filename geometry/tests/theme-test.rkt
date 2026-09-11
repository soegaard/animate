#lang racket/base
(require rackunit "../core.rkt")
(module+ test
  (test-case "world dimensions and cosmetic stroke widths remain distinct"
    (define t (geometry-theme (stroke [width 2]) (point [radius 0.06]) (label [font-size 1/2])))
    (define s (resolve-geometry-style t 'Point 'normal))
    (check-equal? (hash-ref s 'stroke-width) 2)
    (check-equal? (hash-ref s 'radius) 0.06)
    (check-equal? (hash-ref s 'font-size) 1/2))
  (test-case "a color family retains identity across presentation states"
    (define a (resolve-geometry-style default-geometry-theme 'Circle 'normal))
    (define b (resolve-geometry-style default-geometry-theme 'Circle 'deemphasized))
    (check-equal? (hash-ref a 'stroke-family) 'aqua)
    (check-equal? (hash-ref b 'stroke-family) 'aqua)
    (check-equal? (hash-ref a 'stroke-variant) 'd)
    (check-equal? (hash-ref b 'stroke-variant) 'c)
    (check-true (< (hash-ref b 'opacity) (hash-ref a 'opacity))))
  (test-case "dark base theme uses lighter family variants"
    (define a (resolve-geometry-style default-dark-geometry-theme 'Circle 'normal))
    (define b (resolve-geometry-style default-dark-geometry-theme 'Circle 'deemphasized))
    (check-equal? (hash-ref a 'stroke-variant) 'b)
    (check-equal? (hash-ref b 'stroke-variant) 'c))
  (test-case "object family overrides do not accidentally pin the normal variant"
    (define s (resolve-geometry-style default-geometry-theme 'Circle 'deemphasized '((color-family blue))))
    (check-equal? (hash-ref s 'stroke-family) 'blue)
    (check-equal? (hash-ref s 'stroke-variant) 'c))
  (test-case "an exact color overrides family and variant"
    (define s (resolve-geometry-style default-geometry-theme 'Circle 'deemphasized '((color blue-a))))
    (check-equal? (hash-ref s 'stroke-color) 'blue-a))
  (test-case "nested circle state rules do not dash point outlines"
    (define t (geometry-theme (circle (deemphasized (stroke [dash (7 5)])))))
    (check-equal? (hash-ref (resolve-geometry-style t 'Circle 'deemphasized) 'dash) '(7 5))
    (check-equal? (hash-ref (resolve-geometry-style t 'Point 'deemphasized) 'dash) 'solid))
  (test-case "theme inheritance and procedural updates preserve unrelated properties"
    (define parent (geometry-theme (stroke [width 3]) (circle [color-family red])))
    (define child (geometry-theme #:extends parent (label [font-size 0.4])))
    (define changed (geometry-theme-set child '(circle deemphasized stroke) '((width 1))))
    (define s (resolve-geometry-style changed 'Circle 'deemphasized))
    (check-equal? (hash-ref s 'stroke-width) 1)
    (check-equal? (hash-ref s 'stroke-family) 'red)
    (check-equal? (hash-ref s 'font-size) 0.4))
  (test-case "stroke and fill color channels are independent"
    (define t (geometry-theme (point (fill [color-family gold]) (stroke [color-family blue]))))
    (define s (resolve-geometry-style t 'Point 'normal))
    (check-equal? (hash-ref s 'fill-family) 'gold)
    (check-equal? (hash-ref s 'stroke-family) 'blue))
  (test-case "unsupported rules and invalid numeric styles are diagnosed"
    (check-exn exn:fail:geometry? (lambda () (geometry-theme (stroke [width -1]))))
    (check-exn exn:fail:geometry? (lambda () (geometry-theme (point [width 2]))))
    (check-exn exn:fail:geometry? (lambda () (geometry-theme (stroke [dash (2 3 4)]))))
    (check-exn exn:fail:geometry? (lambda () (geometry-theme (label (normal [opacity 0.5])))))))
