#lang racket/base

;;;
;;; Semantic Color Styles
;;;

;; Defines renderer-independent RGBA colors and deterministic conversion from
;; common textual color specifications. This module intentionally has no
;; racket/draw, pict, bitmap, filesystem, process, or browser dependencies.

(require racket/string
         "geometry.rkt")

(provide (struct-out rgba-color)
         rgb-color
         color-spec?
         color-spec->rgba-color
         rgba-color-lerp)

;; rgba-color stores sRGB component values independently from any drawing backend.
;; Red, green, and blue are finite reals in [0,255]; alpha is in [0,1].
(struct rgba-color (red green blue alpha)
  #:transparent
  #:guard
  (lambda (red green blue alpha who)
    (for ([component (in-list (list red green blue))]
          [name (in-list '("red" "green" "blue"))])
      (unless (and (finite-real? component)
                   (<= 0 component 255))
        (raise-arguments-error
         who
         "RGB components must be finite reals in [0, 255]"
         name component)))
    (unless (and (finite-real? alpha)
                 (<= 0 alpha 1))
      (raise-arguments-error
       who
       "alpha must be a finite real in [0, 1]"
       "alpha" alpha))
    (values red green blue alpha)))

; rgb-color : finite-real? finite-real? finite-real? -> rgba-color?
;;   Constructs an opaque semantic RGB color.
(define (rgb-color red green blue)
  (rgba-color red green blue 1))

; color-spec? : any/c -> boolean?
;;   Reports whether value is a semantic color or a supported textual color.
(define (color-spec? value)
  (or (rgba-color? value)
      (and (string? value)
           (string-color->rgba-color value)
           #t)))

; color-spec->rgba-color : any/c [symbol?] -> rgba-color?
;;   Resolves a semantic or textual color to renderer-independent RGBA channels.
(define (color-spec->rgba-color value [who 'color-spec->rgba-color])
  (cond
    [(rgba-color? value)
     value]
    [(string? value)
     (or (string-color->rgba-color value)
         (raise-argument-error
          who
          "supported color name, #RGB[A], #RRGGBB[AA], or rgba-color?"
          value))]
    [else
     (raise-argument-error
      who
      "supported color name, #RGB[A], #RRGGBB[AA], or rgba-color?"
      value)]))

; rgba-color-lerp : rgba-color? rgba-color? finite-real? -> rgba-color?
;;   Interpolates semantic sRGB and alpha components componentwise.
(define (rgba-color-lerp from to progress)
  (unless (rgba-color? from)
    (raise-argument-error 'rgba-color-lerp "rgba-color?" from))
  (unless (rgba-color? to)
    (raise-argument-error 'rgba-color-lerp "rgba-color?" to))
  (unless (and (finite-real? progress) (<= 0 progress 1))
    (raise-argument-error
     'rgba-color-lerp
     "finite real in [0, 1]"
     progress))
  (cond
    [(zero? progress) from]
    [(= progress 1) to]
    [else
     (rgba-color
      (real-lerp (rgba-color-red from) (rgba-color-red to) progress)
      (real-lerp (rgba-color-green from) (rgba-color-green to) progress)
      (real-lerp (rgba-color-blue from) (rgba-color-blue to) progress)
      (real-lerp (rgba-color-alpha from) (rgba-color-alpha to) progress))]))

;; X11-style named colors used by Racket drawing backends. Keys are stored
;; in normalized lowercase form so spaced/hyphenated spellings share a key.
(define named-color-rgb
  (hash
        "aliceblue" #xF0F8FF
        "antiquewhite" #xFAEBD7
        "antiquewhite1" #xFFEFDB
        "antiquewhite2" #xEEDFCC
        "antiquewhite3" #xCDC0B0
        "antiquewhite4" #x8B8378
        "aquamarine" #x7FFFD4
        "aquamarine1" #x7FFFD4
        "aquamarine2" #x76EEC6
        "aquamarine3" #x66CDAA
        "aquamarine4" #x458B74
        "azure" #xF0FFFF
        "azure1" #xF0FFFF
        "azure2" #xE0EEEE
        "azure3" #xC1CDCD
        "azure4" #x838B8B
        "beige" #xF5F5DC
        "bisque" #xFFE4C4
        "bisque1" #xFFE4C4
        "bisque2" #xEED5B7
        "bisque3" #xCDB79E
        "bisque4" #x8B7D6B
        "black" #x000000
        "blanchedalmond" #xFFEBCD
        "blue" #x0000FF
        "blue1" #x0000FF
        "blue2" #x0000EE
        "blue3" #x0000CD
        "blue4" #x00008B
        "blueviolet" #x8A2BE2
        "brown" #xA52A2A
        "brown1" #xFF4040
        "brown2" #xEE3B3B
        "brown3" #xCD3333
        "brown4" #x8B2323
        "burlywood" #xDEB887
        "burlywood1" #xFFD39B
        "burlywood2" #xEEC591
        "burlywood3" #xCDAA7D
        "burlywood4" #x8B7355
        "cadetblue" #x5F9EA0
        "cadetblue1" #x98F5FF
        "cadetblue2" #x8EE5EE
        "cadetblue3" #x7AC5CD
        "cadetblue4" #x53868B
        "chartreuse" #x7FFF00
        "chartreuse1" #x7FFF00
        "chartreuse2" #x76EE00
        "chartreuse3" #x66CD00
        "chartreuse4" #x458B00
        "chocolate" #xD2691E
        "chocolate1" #xFF7F24
        "chocolate2" #xEE7621
        "chocolate3" #xCD661D
        "chocolate4" #x8B4513
        "coral" #xFF7F50
        "coral1" #xFF7256
        "coral2" #xEE6A50
        "coral3" #xCD5B45
        "coral4" #x8B3E2F
        "cornflowerblue" #x6495ED
        "cornsilk" #xFFF8DC
        "cornsilk1" #xFFF8DC
        "cornsilk2" #xEEE8CD
        "cornsilk3" #xCDC8B1
        "cornsilk4" #x8B8878
        "cyan" #x00FFFF
        "cyan1" #x00FFFF
        "cyan2" #x00EEEE
        "cyan3" #x00CDCD
        "cyan4" #x008B8B
        "darkblue" #x00008B
        "darkcyan" #x008B8B
        "darkgoldenrod" #xB8860B
        "darkgoldenrod1" #xFFB90F
        "darkgoldenrod2" #xEEAD0E
        "darkgoldenrod3" #xCD950C
        "darkgoldenrod4" #x8B6508
        "darkgray" #xA9A9A9
        "darkgreen" #x006400
        "darkgrey" #xA9A9A9
        "darkkhaki" #xBDB76B
        "darkmagenta" #x8B008B
        "darkolivegreen" #x556B2F
        "darkolivegreen1" #xCAFF70
        "darkolivegreen2" #xBCEE68
        "darkolivegreen3" #xA2CD5A
        "darkolivegreen4" #x6E8B3D
        "darkorange" #xFF8C00
        "darkorange1" #xFF7F00
        "darkorange2" #xEE7600
        "darkorange3" #xCD6600
        "darkorange4" #x8B4500
        "darkorchid" #x9932CC
        "darkorchid1" #xBF3EFF
        "darkorchid2" #xB23AEE
        "darkorchid3" #x9A32CD
        "darkorchid4" #x68228B
        "darkred" #x8B0000
        "darksalmon" #xE9967A
        "darkseagreen" #x8FBC8F
        "darkseagreen1" #xC1FFC1
        "darkseagreen2" #xB4EEB4
        "darkseagreen3" #x9BCD9B
        "darkseagreen4" #x698B69
        "darkslateblue" #x483D8B
        "darkslategray" #x2F4F4F
        "darkslategray1" #x97FFFF
        "darkslategray2" #x8DEEEE
        "darkslategray3" #x79CDCD
        "darkslategray4" #x528B8B
        "darkslategrey" #x2F4F4F
        "darkturquoise" #x00CED1
        "darkviolet" #x9400D3
        "debianred" #xD70751
        "deeppink" #xFF1493
        "deeppink1" #xFF1493
        "deeppink2" #xEE1289
        "deeppink3" #xCD1076
        "deeppink4" #x8B0A50
        "deepskyblue" #x00BFFF
        "deepskyblue1" #x00BFFF
        "deepskyblue2" #x00B2EE
        "deepskyblue3" #x009ACD
        "deepskyblue4" #x00688B
        "dimgray" #x696969
        "dimgrey" #x696969
        "dodgerblue" #x1E90FF
        "dodgerblue1" #x1E90FF
        "dodgerblue2" #x1C86EE
        "dodgerblue3" #x1874CD
        "dodgerblue4" #x104E8B
        "firebrick" #xB22222
        "firebrick1" #xFF3030
        "firebrick2" #xEE2C2C
        "firebrick3" #xCD2626
        "firebrick4" #x8B1A1A
        "floralwhite" #xFFFAF0
        "forestgreen" #x228B22
        "gainsboro" #xDCDCDC
        "ghostwhite" #xF8F8FF
        "gold" #xFFD700
        "gold1" #xFFD700
        "gold2" #xEEC900
        "gold3" #xCDAD00
        "gold4" #x8B7500
        "goldenrod" #xDAA520
        "goldenrod1" #xFFC125
        "goldenrod2" #xEEB422
        "goldenrod3" #xCD9B1D
        "goldenrod4" #x8B6914
        "gray" #xBEBEBE
        "gray0" #x000000
        "gray1" #x030303
        "gray10" #x1A1A1A
        "gray100" #xFFFFFF
        "gray11" #x1C1C1C
        "gray12" #x1F1F1F
        "gray13" #x212121
        "gray14" #x242424
        "gray15" #x262626
        "gray16" #x292929
        "gray17" #x2B2B2B
        "gray18" #x2E2E2E
        "gray19" #x303030
        "gray2" #x050505
        "gray20" #x333333
        "gray21" #x363636
        "gray22" #x383838
        "gray23" #x3B3B3B
        "gray24" #x3D3D3D
        "gray25" #x404040
        "gray26" #x424242
        "gray27" #x454545
        "gray28" #x474747
        "gray29" #x4A4A4A
        "gray3" #x080808
        "gray30" #x4D4D4D
        "gray31" #x4F4F4F
        "gray32" #x525252
        "gray33" #x545454
        "gray34" #x575757
        "gray35" #x595959
        "gray36" #x5C5C5C
        "gray37" #x5E5E5E
        "gray38" #x616161
        "gray39" #x636363
        "gray4" #x0A0A0A
        "gray40" #x666666
        "gray41" #x696969
        "gray42" #x6B6B6B
        "gray43" #x6E6E6E
        "gray44" #x707070
        "gray45" #x737373
        "gray46" #x757575
        "gray47" #x787878
        "gray48" #x7A7A7A
        "gray49" #x7D7D7D
        "gray5" #x0D0D0D
        "gray50" #x7F7F7F
        "gray51" #x828282
        "gray52" #x858585
        "gray53" #x878787
        "gray54" #x8A8A8A
        "gray55" #x8C8C8C
        "gray56" #x8F8F8F
        "gray57" #x919191
        "gray58" #x949494
        "gray59" #x969696
        "gray6" #x0F0F0F
        "gray60" #x999999
        "gray61" #x9C9C9C
        "gray62" #x9E9E9E
        "gray63" #xA1A1A1
        "gray64" #xA3A3A3
        "gray65" #xA6A6A6
        "gray66" #xA8A8A8
        "gray67" #xABABAB
        "gray68" #xADADAD
        "gray69" #xB0B0B0
        "gray7" #x121212
        "gray70" #xB3B3B3
        "gray71" #xB5B5B5
        "gray72" #xB8B8B8
        "gray73" #xBABABA
        "gray74" #xBDBDBD
        "gray75" #xBFBFBF
        "gray76" #xC2C2C2
        "gray77" #xC4C4C4
        "gray78" #xC7C7C7
        "gray79" #xC9C9C9
        "gray8" #x141414
        "gray80" #xCCCCCC
        "gray81" #xCFCFCF
        "gray82" #xD1D1D1
        "gray83" #xD4D4D4
        "gray84" #xD6D6D6
        "gray85" #xD9D9D9
        "gray86" #xDBDBDB
        "gray87" #xDEDEDE
        "gray88" #xE0E0E0
        "gray89" #xE3E3E3
        "gray9" #x171717
        "gray90" #xE5E5E5
        "gray91" #xE8E8E8
        "gray92" #xEBEBEB
        "gray93" #xEDEDED
        "gray94" #xF0F0F0
        "gray95" #xF2F2F2
        "gray96" #xF5F5F5
        "gray97" #xF7F7F7
        "gray98" #xFAFAFA
        "gray99" #xFCFCFC
        "green" #x00FF00
        "green1" #x00FF00
        "green2" #x00EE00
        "green3" #x00CD00
        "green4" #x008B00
        "greenyellow" #xADFF2F
        "grey" #xBEBEBE
        "grey0" #x000000
        "grey1" #x030303
        "grey10" #x1A1A1A
        "grey100" #xFFFFFF
        "grey11" #x1C1C1C
        "grey12" #x1F1F1F
        "grey13" #x212121
        "grey14" #x242424
        "grey15" #x262626
        "grey16" #x292929
        "grey17" #x2B2B2B
        "grey18" #x2E2E2E
        "grey19" #x303030
        "grey2" #x050505
        "grey20" #x333333
        "grey21" #x363636
        "grey22" #x383838
        "grey23" #x3B3B3B
        "grey24" #x3D3D3D
        "grey25" #x404040
        "grey26" #x424242
        "grey27" #x454545
        "grey28" #x474747
        "grey29" #x4A4A4A
        "grey3" #x080808
        "grey30" #x4D4D4D
        "grey31" #x4F4F4F
        "grey32" #x525252
        "grey33" #x545454
        "grey34" #x575757
        "grey35" #x595959
        "grey36" #x5C5C5C
        "grey37" #x5E5E5E
        "grey38" #x616161
        "grey39" #x636363
        "grey4" #x0A0A0A
        "grey40" #x666666
        "grey41" #x696969
        "grey42" #x6B6B6B
        "grey43" #x6E6E6E
        "grey44" #x707070
        "grey45" #x737373
        "grey46" #x757575
        "grey47" #x787878
        "grey48" #x7A7A7A
        "grey49" #x7D7D7D
        "grey5" #x0D0D0D
        "grey50" #x7F7F7F
        "grey51" #x828282
        "grey52" #x858585
        "grey53" #x878787
        "grey54" #x8A8A8A
        "grey55" #x8C8C8C
        "grey56" #x8F8F8F
        "grey57" #x919191
        "grey58" #x949494
        "grey59" #x969696
        "grey6" #x0F0F0F
        "grey60" #x999999
        "grey61" #x9C9C9C
        "grey62" #x9E9E9E
        "grey63" #xA1A1A1
        "grey64" #xA3A3A3
        "grey65" #xA6A6A6
        "grey66" #xA8A8A8
        "grey67" #xABABAB
        "grey68" #xADADAD
        "grey69" #xB0B0B0
        "grey7" #x121212
        "grey70" #xB3B3B3
        "grey71" #xB5B5B5
        "grey72" #xB8B8B8
        "grey73" #xBABABA
        "grey74" #xBDBDBD
        "grey75" #xBFBFBF
        "grey76" #xC2C2C2
        "grey77" #xC4C4C4
        "grey78" #xC7C7C7
        "grey79" #xC9C9C9
        "grey8" #x141414
        "grey80" #xCCCCCC
        "grey81" #xCFCFCF
        "grey82" #xD1D1D1
        "grey83" #xD4D4D4
        "grey84" #xD6D6D6
        "grey85" #xD9D9D9
        "grey86" #xDBDBDB
        "grey87" #xDEDEDE
        "grey88" #xE0E0E0
        "grey89" #xE3E3E3
        "grey9" #x171717
        "grey90" #xE5E5E5
        "grey91" #xE8E8E8
        "grey92" #xEBEBEB
        "grey93" #xEDEDED
        "grey94" #xF0F0F0
        "grey95" #xF2F2F2
        "grey96" #xF5F5F5
        "grey97" #xF7F7F7
        "grey98" #xFAFAFA
        "grey99" #xFCFCFC
        "honeydew" #xF0FFF0
        "honeydew1" #xF0FFF0
        "honeydew2" #xE0EEE0
        "honeydew3" #xC1CDC1
        "honeydew4" #x838B83
        "hotpink" #xFF69B4
        "hotpink1" #xFF6EB4
        "hotpink2" #xEE6AA7
        "hotpink3" #xCD6090
        "hotpink4" #x8B3A62
        "indianred" #xCD5C5C
        "indianred1" #xFF6A6A
        "indianred2" #xEE6363
        "indianred3" #xCD5555
        "indianred4" #x8B3A3A
        "ivory" #xFFFFF0
        "ivory1" #xFFFFF0
        "ivory2" #xEEEEE0
        "ivory3" #xCDCDC1
        "ivory4" #x8B8B83
        "khaki" #xF0E68C
        "khaki1" #xFFF68F
        "khaki2" #xEEE685
        "khaki3" #xCDC673
        "khaki4" #x8B864E
        "lavender" #xE6E6FA
        "lavenderblush" #xFFF0F5
        "lavenderblush1" #xFFF0F5
        "lavenderblush2" #xEEE0E5
        "lavenderblush3" #xCDC1C5
        "lavenderblush4" #x8B8386
        "lawngreen" #x7CFC00
        "lemonchiffon" #xFFFACD
        "lemonchiffon1" #xFFFACD
        "lemonchiffon2" #xEEE9BF
        "lemonchiffon3" #xCDC9A5
        "lemonchiffon4" #x8B8970
        "lightblue" #xADD8E6
        "lightblue1" #xBFEFFF
        "lightblue2" #xB2DFEE
        "lightblue3" #x9AC0CD
        "lightblue4" #x68838B
        "lightcoral" #xF08080
        "lightcyan" #xE0FFFF
        "lightcyan1" #xE0FFFF
        "lightcyan2" #xD1EEEE
        "lightcyan3" #xB4CDCD
        "lightcyan4" #x7A8B8B
        "lightgoldenrod" #xEEDD82
        "lightgoldenrod1" #xFFEC8B
        "lightgoldenrod2" #xEEDC82
        "lightgoldenrod3" #xCDBE70
        "lightgoldenrod4" #x8B814C
        "lightgoldenrodyellow" #xFAFAD2
        "lightgray" #xD3D3D3
        "lightgreen" #x90EE90
        "lightgrey" #xD3D3D3
        "lightpink" #xFFB6C1
        "lightpink1" #xFFAEB9
        "lightpink2" #xEEA2AD
        "lightpink3" #xCD8C95
        "lightpink4" #x8B5F65
        "lightsalmon" #xFFA07A
        "lightsalmon1" #xFFA07A
        "lightsalmon2" #xEE9572
        "lightsalmon3" #xCD8162
        "lightsalmon4" #x8B5742
        "lightseagreen" #x20B2AA
        "lightskyblue" #x87CEFA
        "lightskyblue1" #xB0E2FF
        "lightskyblue2" #xA4D3EE
        "lightskyblue3" #x8DB6CD
        "lightskyblue4" #x607B8B
        "lightslateblue" #x8470FF
        "lightslategray" #x778899
        "lightslategrey" #x778899
        "lightsteelblue" #xB0C4DE
        "lightsteelblue1" #xCAE1FF
        "lightsteelblue2" #xBCD2EE
        "lightsteelblue3" #xA2B5CD
        "lightsteelblue4" #x6E7B8B
        "lightyellow" #xFFFFE0
        "lightyellow1" #xFFFFE0
        "lightyellow2" #xEEEED1
        "lightyellow3" #xCDCDB4
        "lightyellow4" #x8B8B7A
        "limegreen" #x32CD32
        "linen" #xFAF0E6
        "magenta" #xFF00FF
        "magenta1" #xFF00FF
        "magenta2" #xEE00EE
        "magenta3" #xCD00CD
        "magenta4" #x8B008B
        "maroon" #xB03060
        "maroon1" #xFF34B3
        "maroon2" #xEE30A7
        "maroon3" #xCD2990
        "maroon4" #x8B1C62
        "mediumaquamarine" #x66CDAA
        "mediumblue" #x0000CD
        "mediumorchid" #xBA55D3
        "mediumorchid1" #xE066FF
        "mediumorchid2" #xD15FEE
        "mediumorchid3" #xB452CD
        "mediumorchid4" #x7A378B
        "mediumpurple" #x9370DB
        "mediumpurple1" #xAB82FF
        "mediumpurple2" #x9F79EE
        "mediumpurple3" #x8968CD
        "mediumpurple4" #x5D478B
        "mediumseagreen" #x3CB371
        "mediumslateblue" #x7B68EE
        "mediumspringgreen" #x00FA9A
        "mediumturquoise" #x48D1CC
        "mediumvioletred" #xC71585
        "midnightblue" #x191970
        "mintcream" #xF5FFFA
        "mistyrose" #xFFE4E1
        "mistyrose1" #xFFE4E1
        "mistyrose2" #xEED5D2
        "mistyrose3" #xCDB7B5
        "mistyrose4" #x8B7D7B
        "moccasin" #xFFE4B5
        "navajowhite" #xFFDEAD
        "navajowhite1" #xFFDEAD
        "navajowhite2" #xEECFA1
        "navajowhite3" #xCDB38B
        "navajowhite4" #x8B795E
        "navy" #x000080
        "navyblue" #x000080
        "oldlace" #xFDF5E6
        "olivedrab" #x6B8E23
        "olivedrab1" #xC0FF3E
        "olivedrab2" #xB3EE3A
        "olivedrab3" #x9ACD32
        "olivedrab4" #x698B22
        "orange" #xFFA500
        "orange1" #xFFA500
        "orange2" #xEE9A00
        "orange3" #xCD8500
        "orange4" #x8B5A00
        "orangered" #xFF4500
        "orangered1" #xFF4500
        "orangered2" #xEE4000
        "orangered3" #xCD3700
        "orangered4" #x8B2500
        "orchid" #xDA70D6
        "orchid1" #xFF83FA
        "orchid2" #xEE7AE9
        "orchid3" #xCD69C9
        "orchid4" #x8B4789
        "palegoldenrod" #xEEE8AA
        "palegreen" #x98FB98
        "palegreen1" #x9AFF9A
        "palegreen2" #x90EE90
        "palegreen3" #x7CCD7C
        "palegreen4" #x548B54
        "paleturquoise" #xAFEEEE
        "paleturquoise1" #xBBFFFF
        "paleturquoise2" #xAEEEEE
        "paleturquoise3" #x96CDCD
        "paleturquoise4" #x668B8B
        "palevioletred" #xDB7093
        "palevioletred1" #xFF82AB
        "palevioletred2" #xEE799F
        "palevioletred3" #xCD6889
        "palevioletred4" #x8B475D
        "papayawhip" #xFFEFD5
        "peachpuff" #xFFDAB9
        "peachpuff1" #xFFDAB9
        "peachpuff2" #xEECBAD
        "peachpuff3" #xCDAF95
        "peachpuff4" #x8B7765
        "peru" #xCD853F
        "pink" #xFFC0CB
        "pink1" #xFFB5C5
        "pink2" #xEEA9B8
        "pink3" #xCD919E
        "pink4" #x8B636C
        "plum" #xDDA0DD
        "plum1" #xFFBBFF
        "plum2" #xEEAEEE
        "plum3" #xCD96CD
        "plum4" #x8B668B
        "powderblue" #xB0E0E6
        "purple" #xA020F0
        "purple1" #x9B30FF
        "purple2" #x912CEE
        "purple3" #x7D26CD
        "purple4" #x551A8B
        "red" #xFF0000
        "red1" #xFF0000
        "red2" #xEE0000
        "red3" #xCD0000
        "red4" #x8B0000
        "rosybrown" #xBC8F8F
        "rosybrown1" #xFFC1C1
        "rosybrown2" #xEEB4B4
        "rosybrown3" #xCD9B9B
        "rosybrown4" #x8B6969
        "royalblue" #x4169E1
        "royalblue1" #x4876FF
        "royalblue2" #x436EEE
        "royalblue3" #x3A5FCD
        "royalblue4" #x27408B
        "saddlebrown" #x8B4513
        "salmon" #xFA8072
        "salmon1" #xFF8C69
        "salmon2" #xEE8262
        "salmon3" #xCD7054
        "salmon4" #x8B4C39
        "sandybrown" #xF4A460
        "seagreen" #x2E8B57
        "seagreen1" #x54FF9F
        "seagreen2" #x4EEE94
        "seagreen3" #x43CD80
        "seagreen4" #x2E8B57
        "seashell" #xFFF5EE
        "seashell1" #xFFF5EE
        "seashell2" #xEEE5DE
        "seashell3" #xCDC5BF
        "seashell4" #x8B8682
        "sienna" #xA0522D
        "sienna1" #xFF8247
        "sienna2" #xEE7942
        "sienna3" #xCD6839
        "sienna4" #x8B4726
        "skyblue" #x87CEEB
        "skyblue1" #x87CEFF
        "skyblue2" #x7EC0EE
        "skyblue3" #x6CA6CD
        "skyblue4" #x4A708B
        "slateblue" #x6A5ACD
        "slateblue1" #x836FFF
        "slateblue2" #x7A67EE
        "slateblue3" #x6959CD
        "slateblue4" #x473C8B
        "slategray" #x708090
        "slategray1" #xC6E2FF
        "slategray2" #xB9D3EE
        "slategray3" #x9FB6CD
        "slategray4" #x6C7B8B
        "slategrey" #x708090
        "snow" #xFFFAFA
        "snow1" #xFFFAFA
        "snow2" #xEEE9E9
        "snow3" #xCDC9C9
        "snow4" #x8B8989
        "springgreen" #x00FF7F
        "springgreen1" #x00FF7F
        "springgreen2" #x00EE76
        "springgreen3" #x00CD66
        "springgreen4" #x008B45
        "steelblue" #x4682B4
        "steelblue1" #x63B8FF
        "steelblue2" #x5CACEE
        "steelblue3" #x4F94CD
        "steelblue4" #x36648B
        "tan" #xD2B48C
        "tan1" #xFFA54F
        "tan2" #xEE9A49
        "tan3" #xCD853F
        "tan4" #x8B5A2B
        "thistle" #xD8BFD8
        "thistle1" #xFFE1FF
        "thistle2" #xEED2EE
        "thistle3" #xCDB5CD
        "thistle4" #x8B7B8B
        "tomato" #xFF6347
        "tomato1" #xFF6347
        "tomato2" #xEE5C42
        "tomato3" #xCD4F39
        "tomato4" #x8B3626
        "turquoise" #x40E0D0
        "turquoise1" #x00F5FF
        "turquoise2" #x00E5EE
        "turquoise3" #x00C5CD
        "turquoise4" #x00868B
        "violet" #xEE82EE
        "violetred" #xD02090
        "violetred1" #xFF3E96
        "violetred2" #xEE3A8C
        "violetred3" #xCD3278
        "violetred4" #x8B2252
        "wheat" #xF5DEB3
        "wheat1" #xFFE7BA
        "wheat2" #xEED8AE
        "wheat3" #xCDBA96
        "wheat4" #x8B7E66
        "white" #xFFFFFF
        "whitesmoke" #xF5F5F5
        "yellow" #xFFFF00
        "yellow1" #xFFFF00
        "yellow2" #xEEEE00
        "yellow3" #xCDCD00
        "yellow4" #x8B8B00
        "yellowgreen" #x9ACD32))

; string-color->rgba-color : string? -> (or/c rgba-color? #f)
;;   Parses supported X11/Racket-style names and short/long hexadecimal forms.
(define (string-color->rgba-color value)
  (define trimmed (string-trim value))
  (cond
    [(string=? (string-downcase trimmed) "transparent")
     (rgba-color 0 0 0 0)]
    [(regexp-match? #px"^#[0-9A-Fa-f]{3}$" trimmed)
     (define digits (substring trimmed 1))
     (rgba-color (* 17 (hex-digits->integer (substring digits 0 1)))
                 (* 17 (hex-digits->integer (substring digits 1 2)))
                 (* 17 (hex-digits->integer (substring digits 2 3)))
                 1)]
    [(regexp-match? #px"^#[0-9A-Fa-f]{4}$" trimmed)
     (define digits (substring trimmed 1))
     (rgba-color (* 17 (hex-digits->integer (substring digits 0 1)))
                 (* 17 (hex-digits->integer (substring digits 1 2)))
                 (* 17 (hex-digits->integer (substring digits 2 3)))
                 (/ (* 17 (hex-digits->integer (substring digits 3 4))) 255))]
    [(regexp-match? #px"^#[0-9A-Fa-f]{6}$" trimmed)
     (integer-rgb->rgba-color
      (hex-digits->integer (substring trimmed 1 7))
      1)]
    [(regexp-match? #px"^#[0-9A-Fa-f]{8}$" trimmed)
     (define packed (hex-digits->integer (substring trimmed 1 9)))
     (define alpha (bitwise-and packed #xFF))
     (integer-rgb->rgba-color
      (arithmetic-shift packed -8)
      (/ alpha 255))]
    [else
     (define packed
       (hash-ref named-color-rgb (normalize-color-name trimmed) #f))
     (and packed
          (integer-rgb->rgba-color packed 1))]))

; normalize-color-name : string? -> string?
;;   Makes common spaced/hyphenated spellings match normalized names.
(define (normalize-color-name value)
  (regexp-replace* #px"[[:space:]_-]+" (string-downcase value) ""))

; hex-digits->integer : string? -> exact-nonnegative-integer?
(define (hex-digits->integer digits)
  (string->number digits 16))

; integer-rgb->rgba-color : exact-nonnegative-integer? opacity? -> rgba-color?
(define (integer-rgb->rgba-color packed alpha)
  (rgba-color
   (bitwise-and (arithmetic-shift packed -16) #xFF)
   (bitwise-and (arithmetic-shift packed -8) #xFF)
   (bitwise-and packed #xFF)
   alpha))
