# Reads a JaCoCo XML report (JaCoCo, or Kover's XML report for Kotlin) into records:
#   L <path> <line> <hits> <partial>
# A line counts when it has instructions (mi + ci > 0), and is covered when one ran (ci > 0), as in the report's LINE
# counter. Paths are the package's directory and the file name (dev/x/Foo.kt), so they're partial: matched against
# the repository's files by suffix.
#
# Records are split on "<": Gradle's JaCoCo writes the whole report on one line, Kover one element per line.
function attr(rec, name,   p, rest) {
  p = index(rec, " " name "=\"")
  if (p == 0) return ""
  rest = substr(rec, p + length(name) + 3)
  return substr(rest, 1, index(rest, "\"") - 1)
}
BEGIN { RS = "<"; OFS = "\t" }
/^package / { pkg = attr($0, "name"); next }
/^\/package/ { pkg = ""; next }
/^sourcefile / { name = attr($0, "name"); src = pkg == "" ? name : pkg "/" name; next }
/^\/sourcefile/ { src = ""; next }
/^line / && src != "" {
  mi = attr($0, "mi") + 0
  ci = attr($0, "ci") + 0
  if (mi + ci > 0) print "L", src, attr($0, "nr") + 0, (ci > 0 ? 1 : 0), 1
}
