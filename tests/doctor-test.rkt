#lang racket/base

;;;
;;; SCENE-EM Environment Doctor Tests
;;;

(require rackunit
         "../private/doctor.rkt"
         "../version.rkt")

(module+ test
  (define report
    (collect-doctor-report))
  (check-true (doctor-report? report))
  (check-equal? (doctor-report-release-version report) animate-version)
  (check-eq? (doctor-report-release-stage report) animate-stage)
  (for ([capability
         (in-list
          (list (doctor-report-racket report)
                (doctor-report-gracket report)
                (doctor-report-latex report)
                (doctor-report-dvisvgm report)
                (doctor-report-ffmpeg report)
                (doctor-report-ffplay report)
                (doctor-report-parallel report)))])
    (check-true (doctor-capability? capability))
    (check-true (symbol? (doctor-capability-name capability)))
    (check-true (boolean? (doctor-capability-available? capability)))
    (check-true (string? (doctor-capability-detail capability))))
  (check-true
   (regexp-match?
    #rx"animate 1\\.8\\.0 \\(SCENE-EM\\)"
    (car (doctor-report->lines report)))))
