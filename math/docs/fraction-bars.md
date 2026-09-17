# Persistent animated fraction bars

Prepared formula geometry now assigns the residual marker for a `/` expression
the role `fraction-bar`. A transition matches two such tokens only when the
rewrite's path lineage preserves their division owner. The full TeX source text
is intentionally not part of that decision: evaluating a numerator changes
`\frac{17-5}{3}` to `\frac{12}{3}` while preserving the division itself.

Preparation continues to retain the bar's staged SVG crop. It remains useful as
immutable preparation evidence, a portable worker artifact, and fallback
material; the persistent native display does not paint that crop. Instead, the
native adapter reads the direct TeX rule rectangle from that frozen crop and
maps its measured width, thickness, and vertical offset into a centered local
path. This avoids treating the crop's transparent viewport as painted ink. The
prepared foreground supplies both colors, so dark and light math themes use
their existing palette.

For a matched persistent bar, `move-to` changes its center while `morph-to`
changes only its local rectangle geometry. This avoids `scale-to`, whose uniform
scale would incorrectly thicken or thin the bar along with its width. At the
checkpoint the adapter rebinds the destination token under the same identity
and displays the same path representation, avoiding an SVG replacement frame.

In an ordinary replacement phase, a matched fraction bar receives a dedicated
30%-to-70% geometry window. The first 15% overlaps the end of old-unit
retirement, the middle 10% is the existing safe replacement barrier, and the
last 15% overlaps the beginning of new-unit reveal. Other matched tokens retain
the usual replacement timing, and old/new arithmetic never overlaps.

The portable payload remains `animate-math-prepared-plan-v2`: token fields did
not change. The v2 codec validates `fraction-bar` against its original
`expression` span and transports the existing staged asset reference unchanged.
